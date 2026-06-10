package services

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// Sentinel errors that let the API layer report enterprise integration
// state honestly (503 not configured / 501 not implemented / 404 unknown
// device) instead of pretending success.
var (
	// ErrIntegrationNotConfigured indicates the integration is missing the
	// external credentials/settings required to perform real API calls.
	ErrIntegrationNotConfigured = errors.New("integration not configured")

	// ErrIntegrationNotImplemented indicates an external integration that
	// requires partner credentials/onboarding OrbGuard does not have; the
	// operation is honestly unimplemented rather than simulated.
	ErrIntegrationNotImplemented = errors.New("integration not implemented")

	// ErrDeviceNotFound indicates the referenced device is not registered.
	ErrDeviceNotFound = errors.New("device not found")

	// ErrUnsupportedFramework indicates an unknown compliance framework.
	ErrUnsupportedFramework = errors.New("unsupported compliance framework")
)

// ============================================================================
// MDM Service
// ============================================================================

// MDMService handles MDM/UEM integrations
type MDMService struct {
	repos   *repository.Repositories
	cache   *cache.RedisCache
	logger  *logger.Logger

	// In-memory config store (in production, use database)
	configs map[uuid.UUID]*models.MDMIntegrationConfig
	devices map[uuid.UUID]*models.MDMDevice
	mu      sync.RWMutex

	// HTTP client for MDM API calls
	httpClient *http.Client
}

// NewMDMService creates a new MDM service
func NewMDMService(repos *repository.Repositories, cache *cache.RedisCache, log *logger.Logger) *MDMService {
	return &MDMService{
		repos:   repos,
		cache:   cache,
		logger:  log.WithComponent("mdm"),
		configs: make(map[uuid.UUID]*models.MDMIntegrationConfig),
		devices: make(map[uuid.UUID]*models.MDMDevice),
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// CreateIntegration creates a new MDM integration
func (s *MDMService) CreateIntegration(ctx context.Context, config *models.MDMIntegrationConfig) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	config.ID = uuid.New()
	config.CreatedAt = time.Now()
	config.UpdatedAt = time.Now()

	s.configs[config.ID] = config

	s.logger.Info().
		Str("id", config.ID.String()).
		Str("provider", string(config.Provider)).
		Str("name", config.Name).
		Msg("MDM integration created")

	return nil
}

// GetIntegration retrieves an MDM integration
func (s *MDMService) GetIntegration(id uuid.UUID) (*models.MDMIntegrationConfig, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	config, ok := s.configs[id]
	if !ok {
		return nil, fmt.Errorf("integration not found: %s", id)
	}
	return config, nil
}

// ListIntegrations lists all MDM integrations
func (s *MDMService) ListIntegrations() []*models.MDMIntegrationConfig {
	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make([]*models.MDMIntegrationConfig, 0, len(s.configs))
	for _, config := range s.configs {
		result = append(result, config)
	}
	return result
}

// UpdateIntegration updates an MDM integration
func (s *MDMService) UpdateIntegration(ctx context.Context, config *models.MDMIntegrationConfig) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.configs[config.ID]; !ok {
		return fmt.Errorf("integration not found: %s", config.ID)
	}

	config.UpdatedAt = time.Now()
	s.configs[config.ID] = config
	return nil
}

// DeleteIntegration deletes an MDM integration
func (s *MDMService) DeleteIntegration(id uuid.UUID) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.configs[id]; !ok {
		return fmt.Errorf("integration not found: %s", id)
	}

	delete(s.configs, id)
	return nil
}

// SyncDevices syncs devices from MDM provider
func (s *MDMService) SyncDevices(ctx context.Context, configID uuid.UUID) error {
	config, err := s.GetIntegration(configID)
	if err != nil {
		return err
	}

	s.logger.Info().
		Str("config_id", configID.String()).
		Str("provider", string(config.Provider)).
		Msg("starting device sync")

	var syncErr error
	var deviceCount int

	switch config.Provider {
	case models.MDMProviderIntune:
		deviceCount, syncErr = s.syncIntuneDevices(ctx, config)
	case models.MDMProviderWorkspaceONE:
		deviceCount, syncErr = s.syncWorkspaceONEDevices(ctx, config)
	case models.MDMProviderJamf:
		deviceCount, syncErr = s.syncJamfDevices(ctx, config)
	default:
		syncErr = fmt.Errorf("%w: no device-sync implementation exists for MDM provider %q", ErrIntegrationNotImplemented, config.Provider)
	}

	// Update sync status
	s.mu.Lock()
	now := time.Now()
	config.LastSyncAt = &now
	if syncErr != nil {
		config.LastSyncStatus = "failed"
		config.LastSyncError = syncErr.Error()
	} else {
		config.LastSyncStatus = "success"
		config.LastSyncError = ""
		config.DevicesSynced = deviceCount
	}
	s.mu.Unlock()

	return syncErr
}

// graphManagedDevice is the subset of the Microsoft Graph managedDevice
// resource consumed by the Intune sync.
type graphManagedDevice struct {
	ID               string     `json:"id"`
	DeviceName       string     `json:"deviceName"`
	Model            string     `json:"model"`
	Manufacturer     string     `json:"manufacturer"`
	OSVersion        string     `json:"osVersion"`
	SerialNumber     string     `json:"serialNumber"`
	IMEI             string     `json:"imei"`
	ComplianceState  string     `json:"complianceState"`
	OwnerType        string     `json:"managedDeviceOwnerType"`
	UserID           string     `json:"userId"`
	UserEmail        string     `json:"emailAddress"`
	UserDisplayName  string     `json:"userDisplayName"`
	EnrolledDateTime *time.Time `json:"enrolledDateTime"`
	LastSyncDateTime *time.Time `json:"lastSyncDateTime"`
}

// intuneAccessToken obtains an OAuth2 client-credentials token for the
// Microsoft Graph API.
func (s *MDMService) intuneAccessToken(ctx context.Context, config *models.MDMIntegrationConfig) (string, error) {
	tokenURL := fmt.Sprintf("https://login.microsoftonline.com/%s/oauth2/v2.0/token", url.PathEscape(config.TenantID))

	form := url.Values{}
	form.Set("client_id", config.ClientID)
	form.Set("client_secret", config.ClientSecret)
	form.Set("scope", "https://graph.microsoft.com/.default")
	form.Set("grant_type", "client_credentials")

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, tokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("intune token request: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode >= 400 {
		return "", fmt.Errorf("intune token request failed: status %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	var tokenResp struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.Unmarshal(body, &tokenResp); err != nil {
		return "", fmt.Errorf("decode intune token response: %w", err)
	}
	if tokenResp.AccessToken == "" {
		return "", fmt.Errorf("intune token response contained no access_token")
	}
	return tokenResp.AccessToken, nil
}

// syncIntuneDevices syncs devices from Microsoft Intune via the Microsoft
// Graph API (GET /v1.0/deviceManagement/managedDevices, paged).
func (s *MDMService) syncIntuneDevices(ctx context.Context, config *models.MDMIntegrationConfig) (int, error) {
	if config.TenantID == "" || config.ClientID == "" || config.ClientSecret == "" {
		s.logger.Warn().Str("integration", config.Name).
			Msg("intune sync rejected: tenant_id, client_id and client_secret are required")
		return 0, fmt.Errorf("%w: Intune device sync requires tenant_id, client_id and client_secret on the integration", ErrIntegrationNotConfigured)
	}

	token, err := s.intuneAccessToken(ctx, config)
	if err != nil {
		return 0, err
	}

	count := 0
	nextURL := "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?$top=100"
	for nextURL != "" {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, nextURL, nil)
		if err != nil {
			return count, err
		}
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Accept", "application/json")

		resp, err := s.httpClient.Do(req)
		if err != nil {
			return count, fmt.Errorf("intune managedDevices request: %w", err)
		}
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
		resp.Body.Close()
		if resp.StatusCode >= 400 {
			return count, fmt.Errorf("intune managedDevices request failed: status %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
		}

		var page struct {
			Value    []graphManagedDevice `json:"value"`
			NextLink string               `json:"@odata.nextLink"`
		}
		if err := json.Unmarshal(body, &page); err != nil {
			return count, fmt.Errorf("decode intune managedDevices response: %w", err)
		}

		now := time.Now()
		s.mu.Lock()
		for _, gd := range page.Value {
			device := s.findDeviceByExternalID(config.ID, gd.ID)
			if device == nil {
				device = &models.MDMDevice{
					ID:          uuid.New(),
					MDMConfigID: config.ID,
					ExternalID:  gd.ID,
					CreatedAt:   now,
				}
				s.devices[device.ID] = device
			}
			device.DeviceName = gd.DeviceName
			device.Model = gd.Model
			device.Manufacturer = gd.Manufacturer
			device.OSVersion = gd.OSVersion
			device.SerialNumber = gd.SerialNumber
			device.IMEI = gd.IMEI
			device.EnrollmentStatus = "enrolled"
			device.ComplianceStatus = mapIntuneComplianceState(gd.ComplianceState)
			device.ManagementStatus = "managed"
			device.Ownership = mapIntuneOwnerType(gd.OwnerType)
			device.UserID = gd.UserID
			device.UserEmail = gd.UserEmail
			device.UserName = gd.UserDisplayName
			device.EnrolledAt = gd.EnrolledDateTime
			device.LastCheckIn = gd.LastSyncDateTime
			device.LastSyncAt = &now
			device.UpdatedAt = now
			count++
		}
		s.mu.Unlock()

		nextURL = page.NextLink
	}

	s.logger.Info().Int("devices", count).Str("tenant_id", config.TenantID).
		Msg("intune device sync completed")
	return count, nil
}

// findDeviceByExternalID returns the stored MDM device matching an external
// (provider-side) ID for an integration. Caller must hold s.mu.
func (s *MDMService) findDeviceByExternalID(configID uuid.UUID, externalID string) *models.MDMDevice {
	for _, d := range s.devices {
		if d.MDMConfigID == configID && d.ExternalID == externalID {
			return d
		}
	}
	return nil
}

func mapIntuneComplianceState(state string) string {
	switch strings.ToLower(state) {
	case "compliant":
		return "compliant"
	case "noncompliant":
		return "non_compliant"
	default:
		return "unknown"
	}
}

func mapIntuneOwnerType(owner string) string {
	switch strings.ToLower(owner) {
	case "company":
		return "corporate"
	case "personal":
		return "byod"
	default:
		return "unknown"
	}
}

// syncWorkspaceONEDevices would sync devices from VMware Workspace ONE.
// The Workspace ONE UEM REST API requires customer tenant credentials and an
// aw-tenant-code OrbGuard does not hold; the integration is honestly
// unimplemented instead of returning simulated data.
func (s *MDMService) syncWorkspaceONEDevices(ctx context.Context, config *models.MDMIntegrationConfig) (int, error) {
	if config.BaseURL == "" || config.ClientID == "" || config.ClientSecret == "" {
		s.logger.Warn().Str("integration", config.Name).
			Msg("workspace one sync rejected: base_url, client_id and client_secret are required")
		return 0, fmt.Errorf("%w: Workspace ONE device sync requires base_url, client_id and client_secret on the integration", ErrIntegrationNotConfigured)
	}
	return 0, fmt.Errorf("%w: Workspace ONE device sync requires VMware partner API onboarding (aw-tenant-code) that is not available; no data is simulated", ErrIntegrationNotImplemented)
}

// syncJamfDevices would sync devices from Jamf Pro. The Jamf Pro API requires
// customer instance credentials OrbGuard does not hold; the integration is
// honestly unimplemented instead of returning simulated data.
func (s *MDMService) syncJamfDevices(ctx context.Context, config *models.MDMIntegrationConfig) (int, error) {
	if config.BaseURL == "" || config.ClientID == "" || config.ClientSecret == "" {
		s.logger.Warn().Str("integration", config.Name).
			Msg("jamf sync rejected: base_url, client_id and client_secret are required")
		return 0, fmt.Errorf("%w: Jamf device sync requires base_url, client_id and client_secret on the integration", ErrIntegrationNotConfigured)
	}
	return 0, fmt.Errorf("%w: Jamf Pro device sync requires partner instance onboarding that is not available; no data is simulated", ErrIntegrationNotImplemented)
}

// SendThreatAlert sends a threat alert to MDM
func (s *MDMService) SendThreatAlert(ctx context.Context, alert *models.MDMThreatAlert) error {
	config, err := s.GetIntegration(alert.MDMConfigID)
	if err != nil {
		return err
	}

	if !config.PushThreatAlerts {
		return fmt.Errorf("threat alerts disabled for this integration")
	}

	s.logger.Info().
		Str("device_id", alert.DeviceID.String()).
		Str("threat_type", alert.ThreatType).
		Str("severity", string(alert.Severity)).
		Msg("sending threat alert to MDM")

	var sendErr error
	switch config.Provider {
	case models.MDMProviderIntune:
		sendErr = s.sendIntuneAlert(ctx, config, alert)
	case models.MDMProviderWorkspaceONE:
		sendErr = s.sendWorkspaceONEAlert(ctx, config, alert)
	case models.MDMProviderJamf:
		sendErr = s.sendJamfAlert(ctx, config, alert)
	default:
		sendErr = fmt.Errorf("%w: no alert-forwarding implementation exists for MDM provider %q", ErrIntegrationNotImplemented, config.Provider)
	}

	// Update alert status
	now := time.Now()
	if sendErr != nil {
		alert.Status = "failed"
		alert.Error = sendErr.Error()
	} else {
		alert.Status = "sent"
		alert.SentAt = &now
	}

	return sendErr
}

// sendIntuneAlert would push a threat alert into Microsoft Intune. Pushing
// device threat state into Intune is only possible for enrolled Mobile
// Threat Defense (MTD) partners via the Defender/Intune partner connector;
// OrbGuard is not an enrolled MTD partner, so this is honestly unimplemented
// rather than logging a fake success.
func (s *MDMService) sendIntuneAlert(ctx context.Context, config *models.MDMIntegrationConfig, alert *models.MDMThreatAlert) error {
	if config.TenantID == "" || config.ClientID == "" || config.ClientSecret == "" {
		return fmt.Errorf("%w: Intune alert forwarding requires tenant_id, client_id and client_secret on the integration", ErrIntegrationNotConfigured)
	}
	return fmt.Errorf("%w: forwarding threat alerts to Intune requires Microsoft Mobile Threat Defense partner onboarding, which OrbGuard does not have; the alert was NOT delivered", ErrIntegrationNotImplemented)
}

func (s *MDMService) sendWorkspaceONEAlert(ctx context.Context, config *models.MDMIntegrationConfig, alert *models.MDMThreatAlert) error {
	if config.BaseURL == "" || config.ClientID == "" || config.ClientSecret == "" {
		return fmt.Errorf("%w: Workspace ONE alert forwarding requires base_url, client_id and client_secret on the integration", ErrIntegrationNotConfigured)
	}
	return fmt.Errorf("%w: forwarding threat alerts to Workspace ONE requires VMware partner API onboarding, which OrbGuard does not have; the alert was NOT delivered", ErrIntegrationNotImplemented)
}

func (s *MDMService) sendJamfAlert(ctx context.Context, config *models.MDMIntegrationConfig, alert *models.MDMThreatAlert) error {
	if config.BaseURL == "" || config.ClientID == "" || config.ClientSecret == "" {
		return fmt.Errorf("%w: Jamf alert forwarding requires base_url, client_id and client_secret on the integration", ErrIntegrationNotConfigured)
	}
	return fmt.Errorf("%w: forwarding threat alerts to Jamf Pro requires partner instance onboarding, which OrbGuard does not have; the alert was NOT delivered", ErrIntegrationNotImplemented)
}

// GetMDMDevice retrieves an MDM device
func (s *MDMService) GetMDMDevice(deviceID uuid.UUID) (*models.MDMDevice, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	device, ok := s.devices[deviceID]
	if !ok {
		return nil, fmt.Errorf("device not found: %s", deviceID)
	}
	return device, nil
}

// ListMDMDevices lists MDM devices for a config
func (s *MDMService) ListMDMDevices(configID uuid.UUID) []*models.MDMDevice {
	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make([]*models.MDMDevice, 0)
	for _, device := range s.devices {
		if device.MDMConfigID == configID {
			result = append(result, device)
		}
	}
	return result
}

// GetMDMStats returns MDM statistics
func (s *MDMService) GetMDMStats() map[string]interface{} {
	s.mu.RLock()
	defer s.mu.RUnlock()

	compliantCount := 0
	for _, device := range s.devices {
		if device.ComplianceStatus == "compliant" {
			compliantCount++
		}
	}

	return map[string]interface{}{
		"total_integrations": len(s.configs),
		"total_devices":      len(s.devices),
		"compliant_devices":  compliantCount,
	}
}

// ============================================================================
// Zero Trust Service
// ============================================================================

// ZeroTrustService handles Zero Trust / Conditional Access
type ZeroTrustService struct {
	repos   *repository.Repositories
	cache   *cache.RedisCache
	logger  *logger.Logger

	// netRepo reads the per-device protection state and 30-day security
	// telemetry that posture assessments are computed from.
	netRepo *repository.NetworkSecurityRepository

	// Policies (in-memory working set, backed by policyRepo when available)
	policies   map[uuid.UUID]*models.ConditionalAccessPolicy
	policyRepo *repository.EnterprisePolicyRepository
	mu         sync.RWMutex
}

// NewZeroTrustService creates a new Zero Trust service
func NewZeroTrustService(repos *repository.Repositories, cache *cache.RedisCache, log *logger.Logger) *ZeroTrustService {
	svc := &ZeroTrustService{
		repos:    repos,
		cache:    cache,
		logger:   log.WithComponent("zero-trust"),
		netRepo:  repository.NewNetworkSecurityRepositoryFromRepos(repos),
		policies: make(map[uuid.UUID]*models.ConditionalAccessPolicy),
	}
	if repos != nil {
		svc.policyRepo = repos.EnterprisePolicies
	}

	// Load persisted policies; seed defaults only on first run (or when no
	// database is available).
	svc.loadPolicies()

	return svc
}

// loadPolicies populates the in-memory policy set from the database. When
// the table is empty (first run) the default policies are seeded and
// persisted; when no repository is available the defaults exist in memory
// only.
func (s *ZeroTrustService) loadPolicies() {
	if s.policyRepo == nil {
		s.initDefaultPolicies()
		s.logger.Warn().Msg("no database available: conditional access policies are in-memory only")
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	stored, err := s.policyRepo.List(ctx)
	if err != nil {
		// Do not seed on a load failure — that would shadow persisted
		// policies with defaults. Operate on an empty set until restart.
		s.logger.Error().Err(err).Msg("failed to load conditional access policies")
		return
	}

	if len(stored) == 0 {
		s.initDefaultPolicies()
		for _, policy := range s.policies {
			if err := s.policyRepo.Upsert(ctx, policy); err != nil {
				s.logger.Error().Err(err).Str("policy", policy.Name).Msg("failed to persist default policy")
			}
		}
		s.logger.Info().Int("count", len(s.policies)).Msg("seeded default conditional access policies")
		return
	}

	for _, policy := range stored {
		s.policies[policy.ID] = policy
	}
	s.logger.Info().Int("count", len(stored)).Msg("loaded conditional access policies")
}

// persistPolicy writes a policy to the database when persistence is
// configured.
func (s *ZeroTrustService) persistPolicy(policy *models.ConditionalAccessPolicy) error {
	if s.policyRepo == nil {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return s.policyRepo.Upsert(ctx, policy)
}

// initDefaultPolicies creates default conditional access policies
func (s *ZeroTrustService) initDefaultPolicies() {
	minScore := 70
	lowTrust := models.TrustLevelLow

	policies := []*models.ConditionalAccessPolicy{
		{
			ID:          uuid.New(),
			Name:        "Block Untrusted Devices",
			Description: "Block access from devices with low trust scores",
			Enabled:     true,
			Priority:    1,
			Conditions: models.AccessConditions{
				MinTrustLevel:    &lowTrust,
				MinPostureScore:  &minScore,
			},
			GrantControls: models.GrantControls{
				Operator:   "AND",
				RequireMFA: true,
			},
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		},
		{
			ID:          uuid.New(),
			Name:        "Require MFA for External Networks",
			Description: "Require MFA when accessing from non-corporate networks",
			Enabled:     true,
			Priority:    2,
			Conditions: models.AccessConditions{
				RequireSecureNetwork: true,
			},
			GrantControls: models.GrantControls{
				Operator:   "AND",
				RequireMFA: true,
			},
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		},
		{
			ID:          uuid.New(),
			Name:        "Block on Active Threats",
			Description: "Block access when device has active threats",
			Enabled:     true,
			Priority:    0, // Highest priority
			Conditions: models.AccessConditions{
				BlockOnActiveThreats: true,
			},
			GrantControls: models.GrantControls{
				Operator: "AND",
			},
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		},
	}

	for _, policy := range policies {
		s.policies[policy.ID] = policy
	}
}

// clampScore bounds a component score to the 0-100 range.
func clampScore(v int) int {
	if v < 0 {
		return 0
	}
	if v > 100 {
		return 100
	}
	return v
}

// AssessDevicePosture evaluates device security posture from the device's
// REAL persisted state: protection-module configuration
// (device_network_configs, device_security_settings) and 30-day security
// telemetry (network_audits, app_analyses, sms_analyses). Components with no
// signal are explicitly reported as insufficient_data — scores are never
// fabricated.
func (s *ZeroTrustService) AssessDevicePosture(ctx context.Context, deviceID uuid.UUID) (*models.DevicePosture, error) {
	s.logger.Debug().
		Str("device_id", deviceID.String()).
		Msg("assessing device posture")

	if s.repos == nil || s.repos.Devices == nil || s.netRepo == nil {
		return nil, fmt.Errorf("posture assessment unavailable: database not configured")
	}

	idStr := deviceID.String()
	device, err := s.repos.Devices.FindByID(ctx, idStr)
	if err != nil || device == nil {
		device, err = s.repos.Devices.FindByHardwareID(ctx, idStr)
	}
	if err != nil || device == nil {
		return nil, fmt.Errorf("%w: %s", ErrDeviceNotFound, idStr)
	}

	now := time.Now()
	posture := &models.DevicePosture{
		DeviceID:          deviceID,
		LastAssessedAt:    now,
		NextAssessmentAt:  now.Add(15 * time.Minute),
		AssessmentVersion: "2.0",
		RiskFactors:       make([]models.RiskFactor, 0),
		TrustSignals:      make([]models.TrustSignal, 0),
		Recommendations:   make([]string, 0),
		ComponentStatus: map[string]string{
			"os_security":      models.PostureComponentInsufficientData,
			"app_security":     models.PostureComponentInsufficientData,
			"network_security": models.PostureComponentInsufficientData,
			"behavior":         models.PostureComponentInsufficientData,
			"compliance":       models.PostureComponentInsufficientData,
		},
	}

	// A revoked / inactive device is never trusted, regardless of telemetry.
	if device.Revoked || device.Status != "active" {
		posture.TrustLevel = models.TrustLevelBlocked
		posture.RiskFactors = append(posture.RiskFactors, models.RiskFactor{
			Type:        "registration",
			Name:        "Device revoked or inactive",
			Description: fmt.Sprintf("Device registration status is %q (revoked=%t)", device.Status, device.Revoked),
			Severity:    models.SeverityCritical,
			Impact:      100,
			DetectedAt:  now,
			Remediation: "Re-register the device through the OrbGuard app",
		})
		return posture, nil
	}

	state, err := s.netRepo.GetDeviceProtectionState(ctx, idStr)
	if err != nil {
		return nil, fmt.Errorf("read device protection state: %w", err)
	}
	signals, err := s.netRepo.GetDevicePostureSignals(ctx, idStr)
	if err != nil {
		return nil, fmt.Errorf("read device posture signals: %w", err)
	}

	// --- network_security: from 30-day network audit outcomes -------------
	// network_audits.risk_score is on a 0.0-1.0 scale.
	if signals.HasNetworkAudits {
		posture.NetworkSecurityScore = clampScore(100 - int(signals.AvgNetworkRisk*100))
		posture.ComponentStatus["network_security"] = models.PostureComponentAssessed
		if signals.NetworkAttacks > 0 {
			posture.RiskFactors = append(posture.RiskFactors, models.RiskFactor{
				Type:        "network",
				Name:        "Network attacks detected",
				Description: fmt.Sprintf("%d of %d network audits in the last 30 days found rogue APs, evil twins or DNS hijacking", signals.NetworkAttacks, signals.NetworkAuditCount),
				Severity:    models.SeverityHigh,
				Impact:      int(signals.NetworkAttacks),
				DetectedAt:  now,
				Remediation: "Avoid the flagged networks and re-run a network audit",
			})
		}
	} else {
		posture.Recommendations = append(posture.Recommendations, "Run a network security audit to assess network security posture")
	}

	// --- app_security: from 30-day app analysis outcomes ------------------
	if signals.HasAppAnalyses {
		posture.AppSecurityScore = clampScore(100 - int(signals.AvgAppRisk))
		posture.ComponentStatus["app_security"] = models.PostureComponentAssessed
		if signals.HighRiskApps > 0 {
			posture.RiskFactors = append(posture.RiskFactors, models.RiskFactor{
				Type:        "application",
				Name:        "High-risk applications detected",
				Description: fmt.Sprintf("%d app analyses in the last 30 days returned high or critical risk", signals.HighRiskApps),
				Severity:    models.SeverityHigh,
				Impact:      int(signals.HighRiskApps),
				DetectedAt:  now,
				Remediation: "Review and remove high-risk applications",
			})
			posture.Recommendations = append(posture.Recommendations, "Review and remove high-risk applications")
		}
	} else {
		posture.Recommendations = append(posture.Recommendations, "Run an app security scan to assess application posture")
	}

	// --- behavior: SMS threat exposure over the last 30 days --------------
	if signals.HasSMSAnalyses {
		exposure := int(signals.SMSThreats * 100 / signals.SMSCount)
		posture.BehaviorScore = clampScore(100 - exposure)
		posture.ComponentStatus["behavior"] = models.PostureComponentAssessed
		if signals.SMSThreats > 0 {
			posture.RiskFactors = append(posture.RiskFactors, models.RiskFactor{
				Type:        "behavior",
				Name:        "SMS threats received",
				Description: fmt.Sprintf("%d of %d analyzed SMS messages in the last 30 days were threats", signals.SMSThreats, signals.SMSCount),
				Severity:    models.SeverityMedium,
				Impact:      int(signals.SMSThreats),
				DetectedAt:  now,
				Remediation: "Do not interact with flagged messages; block the senders",
			})
		}
	} else {
		posture.Recommendations = append(posture.Recommendations, "Enable SMS protection to assess social-engineering exposure")
	}

	// --- compliance: protection modules actually enabled -------------------
	// Always computable: derived from persisted configuration rows (the same
	// source as GET /stats/protection).
	modules := []struct {
		on   bool
		name string
	}{
		{state.SMSActive, "SMS protection"},
		{state.DNSConfigured, "DNS filtering"},
		{state.AppScanActive, "App scanning"},
		{state.NetworkAuditRecent, "Network auditing"},
		{state.VPNConfigured, "VPN"},
		{state.AntiTheftEnabled, "Anti-theft"},
	}
	enabled := 0
	for _, m := range modules {
		if m.on {
			enabled++
			posture.TrustSignals = append(posture.TrustSignals, models.TrustSignal{
				Type:        "protection_module",
				Name:        m.name + " active",
				Description: m.name + " is configured or has been active within the last 30 days",
				Value:       100 / len(modules),
			})
		} else {
			posture.Recommendations = append(posture.Recommendations, "Enable "+m.name)
		}
	}
	posture.ComplianceScore = enabled * 100 / len(modules)
	posture.ComponentStatus["compliance"] = models.PostureComponentAssessed

	// --- os_security: no real signal collected -----------------------------
	// OrbGuard does not collect OS patch-level / vulnerability intelligence
	// for devices, so this component cannot be honestly scored.
	posture.Recommendations = append(posture.Recommendations, "OS security cannot be assessed: no OS patch-level telemetry is collected")

	// --- overall: weighted average of ASSESSED components only -------------
	type weighted struct {
		key    string
		score  int
		weight int
	}
	components := []weighted{
		{"os_security", posture.OSSecurityScore, 25},
		{"app_security", posture.AppSecurityScore, 20},
		{"network_security", posture.NetworkSecurityScore, 20},
		{"behavior", posture.BehaviorScore, 15},
		{"compliance", posture.ComplianceScore, 20},
	}
	sum, weightSum := 0, 0
	for _, c := range components {
		if posture.ComponentStatus[c.key] == models.PostureComponentAssessed {
			sum += c.score * c.weight
			weightSum += c.weight
		}
	}
	if weightSum > 0 {
		posture.OverallScore = sum / weightSum
	}

	// Determine trust level from the real overall score.
	switch {
	case posture.OverallScore >= 90:
		posture.TrustLevel = models.TrustLevelHigh
	case posture.OverallScore >= 70:
		posture.TrustLevel = models.TrustLevelMedium
	case posture.OverallScore >= 50:
		posture.TrustLevel = models.TrustLevelLow
	default:
		posture.TrustLevel = models.TrustLevelUntrusted
	}

	// Cache the posture
	if s.cache != nil {
		cacheKey := fmt.Sprintf("posture:%s", deviceID.String())
		data, _ := json.Marshal(posture)
		s.cache.Set(ctx, cacheKey, string(data), 15*time.Minute)
	}

	return posture, nil
}

// EvaluateAccess evaluates access request against policies
func (s *ZeroTrustService) EvaluateAccess(ctx context.Context, req *AccessRequest) (*models.AccessDecision, error) {
	s.logger.Debug().
		Str("device_id", req.DeviceID.String()).
		Str("resource", req.ResourceID).
		Msg("evaluating access request")

	decision := &models.AccessDecision{
		ID:         uuid.New(),
		DeviceID:   req.DeviceID,
		UserID:     req.UserID,
		ResourceID: req.ResourceID,
		Location:   req.Location,
		IPAddress:  req.IPAddress,
		UserAgent:  req.UserAgent,
		CreatedAt:  time.Now(),
	}

	// Get device posture. Errors (unknown device, database unavailable) are
	// surfaced to the caller instead of being converted into a silent deny.
	posture, err := s.AssessDevicePosture(ctx, req.DeviceID)
	if err != nil {
		return nil, err
	}
	decision.DevicePosture = posture

	// A blocked device (revoked/inactive registration) is always denied.
	if posture.TrustLevel == models.TrustLevelBlocked {
		decision.Decision = "deny"
		decision.Reason = "Device registration is revoked or inactive"
		return decision, nil
	}

	// Check for active threats
	if req.HasActiveThreats {
		decision.Decision = "deny"
		decision.Reason = "Device has active security threats"
		return decision, nil
	}

	// Evaluate policies in priority order
	s.mu.RLock()
	defer s.mu.RUnlock()

	for _, policy := range s.policies {
		if !policy.Enabled {
			continue
		}

		if s.policyApplies(policy, req, posture) {
			if s.conditionsMet(policy, req, posture) {
				decision.PolicyID = &policy.ID
				decision.Decision = "allow"
				decision.Reason = fmt.Sprintf("Policy '%s' conditions met", policy.Name)

				// Check if MFA required
				if policy.GrantControls.RequireMFA && !req.MFACompleted {
					decision.Decision = "challenge"
					decision.ChallengeType = "mfa"
					decision.ChallengeStatus = "pending"
					decision.Reason = "MFA required"
				}
				return decision, nil
			} else {
				decision.PolicyID = &policy.ID
				decision.Decision = "deny"
				decision.Reason = fmt.Sprintf("Policy '%s' conditions not met", policy.Name)
				return decision, nil
			}
		}
	}

	// Default allow if no policies match
	decision.Decision = "allow"
	decision.Reason = "No blocking policies applied"
	return decision, nil
}

// AccessRequest represents an access request
type AccessRequest struct {
	DeviceID         uuid.UUID
	UserID           string
	ResourceID       string
	Location         string
	IPAddress        string
	UserAgent        string
	HasActiveThreats bool
	MFACompleted     bool
}

func (s *ZeroTrustService) policyApplies(policy *models.ConditionalAccessPolicy, req *AccessRequest, posture *models.DevicePosture) bool {
	// Check user/group assignments
	if len(policy.IncludeUsers) > 0 {
		found := false
		for _, u := range policy.IncludeUsers {
			if u == req.UserID || u == "all" {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}

	// Check app assignments
	if len(policy.IncludeApps) > 0 {
		found := false
		for _, app := range policy.IncludeApps {
			if app == req.ResourceID || app == "all" {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}

	return true
}

func (s *ZeroTrustService) conditionsMet(policy *models.ConditionalAccessPolicy, req *AccessRequest, posture *models.DevicePosture) bool {
	cond := policy.Conditions

	// Check trust level
	if cond.MinTrustLevel != nil {
		if !s.trustLevelSufficient(posture.TrustLevel, *cond.MinTrustLevel) {
			return false
		}
	}

	// Check posture score
	if cond.MinPostureScore != nil && posture.OverallScore < *cond.MinPostureScore {
		return false
	}

	// Check active threats
	if cond.BlockOnActiveThreats && req.HasActiveThreats {
		return false
	}

	return true
}

func (s *ZeroTrustService) trustLevelSufficient(actual, required models.TrustLevel) bool {
	levels := map[models.TrustLevel]int{
		models.TrustLevelHigh:      4,
		models.TrustLevelMedium:    3,
		models.TrustLevelLow:       2,
		models.TrustLevelUntrusted: 1,
		models.TrustLevelBlocked:   0,
	}
	return levels[actual] >= levels[required]
}

// CreatePolicy creates a conditional access policy
func (s *ZeroTrustService) CreatePolicy(policy *models.ConditionalAccessPolicy) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	policy.ID = uuid.New()
	policy.CreatedAt = time.Now()
	policy.UpdatedAt = time.Now()

	if err := s.persistPolicy(policy); err != nil {
		return fmt.Errorf("persist policy: %w", err)
	}

	s.policies[policy.ID] = policy
	return nil
}

// GetPolicy retrieves a policy
func (s *ZeroTrustService) GetPolicy(id uuid.UUID) (*models.ConditionalAccessPolicy, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	policy, ok := s.policies[id]
	if !ok {
		return nil, fmt.Errorf("policy not found: %s", id)
	}
	return policy, nil
}

// ListPolicies lists all policies
func (s *ZeroTrustService) ListPolicies() []*models.ConditionalAccessPolicy {
	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make([]*models.ConditionalAccessPolicy, 0, len(s.policies))
	for _, p := range s.policies {
		result = append(result, p)
	}
	return result
}

// UpdatePolicy updates a policy
func (s *ZeroTrustService) UpdatePolicy(policy *models.ConditionalAccessPolicy) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	existing, ok := s.policies[policy.ID]
	if !ok {
		return fmt.Errorf("policy not found: %s", policy.ID)
	}

	policy.CreatedAt = existing.CreatedAt
	policy.UpdatedAt = time.Now()

	if err := s.persistPolicy(policy); err != nil {
		return fmt.Errorf("persist policy: %w", err)
	}

	s.policies[policy.ID] = policy
	return nil
}

// DeletePolicy deletes a policy
func (s *ZeroTrustService) DeletePolicy(id uuid.UUID) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.policies[id]; !ok {
		return fmt.Errorf("policy not found: %s", id)
	}

	if s.policyRepo != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := s.policyRepo.Delete(ctx, id); err != nil {
			return fmt.Errorf("delete persisted policy: %w", err)
		}
	}

	delete(s.policies, id)
	return nil
}

// GetZeroTrustStats returns Zero Trust statistics
func (s *ZeroTrustService) GetZeroTrustStats() map[string]interface{} {
	s.mu.RLock()
	defer s.mu.RUnlock()

	enabledCount := 0
	for _, p := range s.policies {
		if p.Enabled {
			enabledCount++
		}
	}

	return map[string]interface{}{
		"total_policies":   len(s.policies),
		"enabled_policies": enabledCount,
	}
}

// ============================================================================
// SIEM Service
// ============================================================================

// SIEMService handles SIEM integrations
type SIEMService struct {
	repos   *repository.Repositories
	cache   *cache.RedisCache
	logger  *logger.Logger

	configs     map[uuid.UUID]*models.SIEMIntegrationConfig
	eventQueues map[uuid.UUID][]models.SIEMEvent
	mu          sync.RWMutex

	httpClient *http.Client

	// Flush control
	flushTicker *time.Ticker
	stopCh      chan struct{}
}

// NewSIEMService creates a new SIEM service
func NewSIEMService(repos *repository.Repositories, cache *cache.RedisCache, log *logger.Logger) *SIEMService {
	svc := &SIEMService{
		repos:       repos,
		cache:       cache,
		logger:      log.WithComponent("siem"),
		configs:     make(map[uuid.UUID]*models.SIEMIntegrationConfig),
		eventQueues: make(map[uuid.UUID][]models.SIEMEvent),
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		stopCh: make(chan struct{}),
	}

	return svc
}

// Start starts the SIEM service background processing
func (s *SIEMService) Start(ctx context.Context) {
	s.flushTicker = time.NewTicker(10 * time.Second)
	go func() {
		for {
			select {
			case <-s.flushTicker.C:
				s.flushAllQueues(ctx)
			case <-s.stopCh:
				s.flushTicker.Stop()
				return
			case <-ctx.Done():
				s.flushTicker.Stop()
				return
			}
		}
	}()
}

// Stop stops the SIEM service
func (s *SIEMService) Stop() {
	close(s.stopCh)
}

// CreateIntegration creates a SIEM integration. Providers without a real
// event sender are rejected at creation time so events are never queued into
// an integration that can't deliver them.
func (s *SIEMService) CreateIntegration(config *models.SIEMIntegrationConfig) error {
	switch config.Provider {
	case models.SIEMProviderSplunk, models.SIEMProviderElastic,
		models.SIEMProviderSentinel, models.SIEMProviderWebhook:
		// supported
	default:
		return fmt.Errorf("%w: no event sender exists for SIEM provider %q; supported providers are splunk, elastic, sentinel, webhook", ErrIntegrationNotImplemented, config.Provider)
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	config.ID = uuid.New()
	config.CreatedAt = time.Now()
	config.UpdatedAt = time.Now()

	if config.BatchSize == 0 {
		config.BatchSize = 100
	}
	if config.FlushInterval == 0 {
		config.FlushInterval = 10 * time.Second
	}

	s.configs[config.ID] = config
	s.eventQueues[config.ID] = make([]models.SIEMEvent, 0)

	s.logger.Info().
		Str("id", config.ID.String()).
		Str("provider", string(config.Provider)).
		Str("name", config.Name).
		Msg("SIEM integration created")

	return nil
}

// GetIntegration retrieves a SIEM integration
func (s *SIEMService) GetIntegration(id uuid.UUID) (*models.SIEMIntegrationConfig, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	config, ok := s.configs[id]
	if !ok {
		return nil, fmt.Errorf("integration not found: %s", id)
	}
	return config, nil
}

// HasEnabledIntegrations reports whether at least one enabled SIEM
// integration exists. Used by the API layer to reject event forwarding
// honestly (503) when no integration is configured, instead of silently
// dropping events while reporting "queued".
func (s *SIEMService) HasEnabledIntegrations() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()

	for _, config := range s.configs {
		if config.Enabled {
			return true
		}
	}
	return false
}

// ListIntegrations lists all SIEM integrations
func (s *SIEMService) ListIntegrations() []*models.SIEMIntegrationConfig {
	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make([]*models.SIEMIntegrationConfig, 0, len(s.configs))
	for _, config := range s.configs {
		result = append(result, config)
	}
	return result
}

// DeleteIntegration deletes a SIEM integration
func (s *SIEMService) DeleteIntegration(id uuid.UUID) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.configs[id]; !ok {
		return fmt.Errorf("integration not found: %s", id)
	}

	delete(s.configs, id)
	delete(s.eventQueues, id)
	return nil
}

// SendEvent queues an event for sending to SIEM
func (s *SIEMService) SendEvent(ctx context.Context, event *models.SIEMEvent) {
	s.mu.Lock()
	defer s.mu.Unlock()

	for id, config := range s.configs {
		if !config.Enabled {
			continue
		}

		// Check if event type is enabled
		if !s.eventTypeEnabled(config, event.EventType) {
			continue
		}

		// Check severity filter
		if !s.severityAllowed(config.MinSeverity, event.Severity) {
			continue
		}

		// Add to queue
		s.eventQueues[id] = append(s.eventQueues[id], *event)

		// Flush if queue is full
		if len(s.eventQueues[id]) >= config.BatchSize {
			go s.flushQueue(ctx, id)
		}
	}
}

func (s *SIEMService) eventTypeEnabled(config *models.SIEMIntegrationConfig, eventType string) bool {
	if len(config.EventTypes) == 0 {
		return true // All types enabled
	}
	for _, t := range config.EventTypes {
		if t == eventType || t == "all" {
			return true
		}
	}
	return false
}

func (s *SIEMService) severityAllowed(minSeverity, eventSeverity models.Severity) bool {
	severityOrder := map[models.Severity]int{
		models.SeverityInfo:     0,
		models.SeverityLow:      1,
		models.SeverityMedium:   2,
		models.SeverityHigh:     3,
		models.SeverityCritical: 4,
	}
	return severityOrder[eventSeverity] >= severityOrder[minSeverity]
}

func (s *SIEMService) flushAllQueues(ctx context.Context) {
	s.mu.RLock()
	ids := make([]uuid.UUID, 0, len(s.eventQueues))
	for id := range s.eventQueues {
		ids = append(ids, id)
	}
	s.mu.RUnlock()

	for _, id := range ids {
		s.flushQueue(ctx, id)
	}
}

func (s *SIEMService) flushQueue(ctx context.Context, configID uuid.UUID) {
	s.mu.Lock()
	events := s.eventQueues[configID]
	if len(events) == 0 {
		s.mu.Unlock()
		return
	}

	// Clear queue
	s.eventQueues[configID] = make([]models.SIEMEvent, 0)
	config := s.configs[configID]
	s.mu.Unlock()

	if config == nil {
		return
	}

	// Send events
	var err error
	switch config.Provider {
	case models.SIEMProviderSplunk:
		err = s.sendToSplunk(ctx, config, events)
	case models.SIEMProviderElastic:
		err = s.sendToElastic(ctx, config, events)
	case models.SIEMProviderSentinel:
		err = s.sendToSentinel(ctx, config, events)
	case models.SIEMProviderWebhook:
		err = s.sendToWebhook(ctx, config, events)
	default:
		err = fmt.Errorf("%w: no event sender exists for SIEM provider %q", ErrIntegrationNotImplemented, config.Provider)
	}

	// Update status
	s.mu.Lock()
	now := time.Now()
	if err != nil {
		config.LastError = err.Error()
		config.LastErrorAt = &now
		s.logger.Error().Err(err).Str("provider", string(config.Provider)).Msg("failed to send events to SIEM")
	} else {
		config.LastEventAt = &now
		config.EventsSent += int64(len(events))
	}
	s.mu.Unlock()
}

func (s *SIEMService) sendToSplunk(ctx context.Context, config *models.SIEMIntegrationConfig, events []models.SIEMEvent) error {
	// Splunk HEC format
	// POST https://splunk-server:8088/services/collector/event
	// Header: Authorization: Splunk <token>
	if config.Endpoint == "" || config.Token == "" {
		return fmt.Errorf("%w: Splunk forwarding requires endpoint and token on the integration", ErrIntegrationNotConfigured)
	}

	for _, event := range events {
		payload := map[string]interface{}{
			"time":       event.Timestamp.Unix(),
			"host":       event.SourceHost,
			"source":     event.Source,
			"sourcetype": "orbguard:security",
			"index":      config.Index,
			"event":      event,
		}

		data, err := json.Marshal(payload)
		if err != nil {
			return err
		}

		req, err := http.NewRequestWithContext(ctx, "POST", config.Endpoint, bytes.NewReader(data))
		if err != nil {
			return err
		}

		req.Header.Set("Authorization", "Splunk "+config.Token)
		req.Header.Set("Content-Type", "application/json")

		resp, err := s.httpClient.Do(req)
		if err != nil {
			return err
		}
		resp.Body.Close()

		if resp.StatusCode >= 400 {
			return fmt.Errorf("splunk returned status %d", resp.StatusCode)
		}
	}

	s.logger.Debug().Int("count", len(events)).Msg("sent events to Splunk")
	return nil
}

func (s *SIEMService) sendToElastic(ctx context.Context, config *models.SIEMIntegrationConfig, events []models.SIEMEvent) error {
	// Elasticsearch bulk API
	// POST /_bulk
	if config.Endpoint == "" {
		return fmt.Errorf("%w: Elasticsearch forwarding requires endpoint on the integration", ErrIntegrationNotConfigured)
	}

	var buf bytes.Buffer
	for _, event := range events {
		// Index action
		action := map[string]interface{}{
			"index": map[string]interface{}{
				"_index": config.Index,
			},
		}
		actionLine, _ := json.Marshal(action)
		buf.Write(actionLine)
		buf.WriteByte('\n')

		// Document
		docLine, _ := json.Marshal(event)
		buf.Write(docLine)
		buf.WriteByte('\n')
	}

	req, err := http.NewRequestWithContext(ctx, "POST", config.Endpoint+"/_bulk", &buf)
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/x-ndjson")
	if config.Token != "" {
		req.Header.Set("Authorization", "ApiKey "+config.Token)
	} else if config.Username != "" {
		req.SetBasicAuth(config.Username, config.Password)
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return err
	}
	resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("elasticsearch returned status %d", resp.StatusCode)
	}

	s.logger.Debug().Int("count", len(events)).Msg("sent events to Elasticsearch")
	return nil
}

func (s *SIEMService) sendToSentinel(ctx context.Context, config *models.SIEMIntegrationConfig, events []models.SIEMEvent) error {
	// Azure Sentinel via the Log Analytics HTTP Data Collector API:
	// POST https://<workspace-id>.ods.opinsights.azure.com/api/logs?api-version=2016-04-01
	// Authorization: SharedKey <workspace-id>:<base64(hmac-sha256(key, stringToSign))>
	if config.WorkspaceID == "" || config.Token == "" {
		return fmt.Errorf("%w: Sentinel forwarding requires workspace_id and the Log Analytics shared key (token) on the integration", ErrIntegrationNotConfigured)
	}

	data, err := json.Marshal(events)
	if err != nil {
		return err
	}

	key, err := base64.StdEncoding.DecodeString(config.Token)
	if err != nil {
		return fmt.Errorf("sentinel shared key is not valid base64: %w", err)
	}

	endpoint := config.Endpoint
	if endpoint == "" {
		endpoint = fmt.Sprintf("https://%s.ods.opinsights.azure.com/api/logs?api-version=2016-04-01", config.WorkspaceID)
	}

	dateStr := time.Now().UTC().Format(http.TimeFormat)
	stringToSign := fmt.Sprintf("POST\n%d\napplication/json\nx-ms-date:%s\n/api/logs", len(data), dateStr)
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(stringToSign))
	signature := base64.StdEncoding.EncodeToString(mac.Sum(nil))

	req, err := http.NewRequestWithContext(ctx, "POST", endpoint, bytes.NewReader(data))
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Log-Type", "OrbGuard")
	req.Header.Set("x-ms-date", dateStr)
	req.Header.Set("Authorization", fmt.Sprintf("SharedKey %s:%s", config.WorkspaceID, signature))

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return err
	}
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("sentinel returned status %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	s.logger.Debug().Int("count", len(events)).Msg("sent events to Sentinel")
	return nil
}

func (s *SIEMService) sendToWebhook(ctx context.Context, config *models.SIEMIntegrationConfig, events []models.SIEMEvent) error {
	// Generic webhook
	if config.Endpoint == "" {
		return fmt.Errorf("%w: webhook forwarding requires endpoint on the integration", ErrIntegrationNotConfigured)
	}
	data, err := json.Marshal(map[string]interface{}{
		"source": "orbguard",
		"events": events,
	})
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, "POST", config.Endpoint, bytes.NewReader(data))
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")
	if config.Token != "" {
		req.Header.Set("Authorization", "Bearer "+config.Token)
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return err
	}
	resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("webhook returned status %d", resp.StatusCode)
	}

	s.logger.Debug().Int("count", len(events)).Msg("sent events to webhook")
	return nil
}

// GetSIEMStats returns SIEM statistics
func (s *SIEMService) GetSIEMStats() map[string]interface{} {
	s.mu.RLock()
	defer s.mu.RUnlock()

	totalEvents := int64(0)
	for _, config := range s.configs {
		totalEvents += config.EventsSent
	}

	return map[string]interface{}{
		"total_integrations": len(s.configs),
		"total_events_sent":  totalEvents,
	}
}

// ============================================================================
// Compliance Service
// ============================================================================

// ComplianceService handles compliance reporting
type ComplianceService struct {
	repos   *repository.Repositories
	cache   *cache.RedisCache
	logger  *logger.Logger

	// netRepo reads the real fleet/device protection state that automated
	// control assessments are computed from.
	netRepo *repository.NetworkSecurityRepository

	reports  map[uuid.UUID]*models.ComplianceReport
	findings map[uuid.UUID]*models.ComplianceFinding
	mu       sync.RWMutex
}

// NewComplianceService creates a new compliance service
func NewComplianceService(repos *repository.Repositories, cache *cache.RedisCache, log *logger.Logger) *ComplianceService {
	return &ComplianceService{
		repos:    repos,
		cache:    cache,
		logger:   log.WithComponent("compliance"),
		netRepo:  repository.NewNetworkSecurityRepositoryFromRepos(repos),
		reports:  make(map[uuid.UUID]*models.ComplianceReport),
		findings: make(map[uuid.UUID]*models.ComplianceFinding),
	}
}

// GenerateReport generates a compliance report for a framework
func (s *ComplianceService) GenerateReport(ctx context.Context, framework models.ComplianceFramework, startDate, endDate time.Time) (*models.ComplianceReport, error) {
	s.logger.Info().
		Str("framework", string(framework)).
		Time("start_date", startDate).
		Time("end_date", endDate).
		Msg("generating compliance report")

	report := &models.ComplianceReport{
		ID:          uuid.New(),
		Framework:   framework,
		Name:        fmt.Sprintf("%s Compliance Report", framework),
		Description: fmt.Sprintf("Compliance assessment for %s framework", framework),
		StartDate:   startDate,
		EndDate:     endDate,
		GeneratedAt: time.Now(),
		GeneratedBy: "system",
		Version:     "1.0",
		Controls:    make([]models.ControlAssessment, 0),
		Findings:    make([]models.ComplianceFinding, 0),
	}

	// Get controls for framework
	var controls []models.ControlAssessment
	switch framework {
	case models.ComplianceGDPR:
		controls = models.GDPRControls
	case models.ComplianceSOC2:
		controls = models.SOC2Controls
	case models.ComplianceCIS:
		controls = models.CISControls
	default:
		return nil, fmt.Errorf("%w: %s (control catalogs exist for gdpr, soc2, cis)", ErrUnsupportedFramework, framework)
	}

	// Automated assessments require the real fleet protection state.
	if s.netRepo == nil {
		return nil, fmt.Errorf("compliance assessment unavailable: database not configured")
	}
	fleet, err := s.netRepo.GetFleetProtectionStats(ctx)
	if err != nil {
		return nil, fmt.Errorf("read fleet protection stats: %w", err)
	}

	// Assess each control. Only controls mapped to a real fleet signal are
	// assessed; all others are explicitly not_assessed and excluded from the
	// score.
	for _, control := range controls {
		assessment := s.assessControl(control, fleet)
		report.Controls = append(report.Controls, assessment)

		// Track counts
		report.TotalControls++
		switch assessment.Status {
		case models.ComplianceStatusCompliant:
			report.PassedControls++
		case models.ComplianceStatusNonCompliant:
			report.FailedControls++
		case models.ComplianceStatusPartial:
			report.PartialControls++
		case models.ComplianceStatusNotAssessed:
			report.NotAssessed++
		default:
			report.NotApplicable++
		}
	}
	report.AssessedControls = report.PassedControls + report.FailedControls + report.PartialControls

	// Overall score is computed over ASSESSED controls only; not_assessed
	// controls are never silently counted as passing or failing.
	if report.AssessedControls > 0 {
		report.OverallScore = float64(report.PassedControls*100+report.PartialControls*50) / float64(report.AssessedControls)
	}

	// Determine overall status
	switch {
	case report.AssessedControls == 0:
		report.OverallStatus = models.ComplianceStatusNotAssessed
	case report.FailedControls > 0:
		report.OverallStatus = models.ComplianceStatusNonCompliant
	case report.PartialControls > 0:
		report.OverallStatus = models.ComplianceStatusPartial
	default:
		report.OverallStatus = models.ComplianceStatusCompliant
	}

	// Store report
	s.mu.Lock()
	s.reports[report.ID] = report
	s.mu.Unlock()

	s.logger.Info().
		Str("report_id", report.ID.String()).
		Float64("score", report.OverallScore).
		Str("status", string(report.OverallStatus)).
		Msg("compliance report generated")

	return report, nil
}

// fleetControlSignal describes the real fleet signal an automated control
// assessment is based on: how many active devices satisfy the control and a
// human-readable name for the capability measured.
type fleetControlSignal struct {
	capability string
	covered    int64
}

// fleetSignalForControl maps a control ID to the real fleet protection
// signal it can be assessed against. Returns nil when no automated signal
// exists for the control (it must then be reported as not_assessed).
//
// Only controls with a direct, defensible mapping to persisted device state
// are automated:
//   - CIS-9  (Email and Browser Protections) -> DNS filtering configured
//   - CIS-10 (Malware Defenses)              -> app scanning active (30d)
//   - CIS-13 (Network Monitoring and Defense)-> network audits run (30d)
//   - CC7.2  (Incident Response / monitoring)-> any monitoring activity (30d)
//   - GDPR-32 (Security of Processing)       -> security analysis activity (30d)
func fleetSignalForControl(controlID string, fleet *repository.FleetProtectionStats) *fleetControlSignal {
	switch controlID {
	case "CIS-9":
		return &fleetControlSignal{"DNS filtering configured", fleet.WithDNSFiltering}
	case "CIS-10":
		return &fleetControlSignal{"app security scanning active in the last 30 days", fleet.WithAppScanRecent}
	case "CIS-13":
		return &fleetControlSignal{"network security audits run in the last 30 days", fleet.WithNetworkAuditRecent}
	case "CC7.2":
		return &fleetControlSignal{"security monitoring (app/network/SMS analysis) active in the last 30 days", fleet.WithAnyMonitoring}
	case "GDPR-32":
		return &fleetControlSignal{"security analysis activity in the last 30 days", fleet.WithAnyMonitoring}
	default:
		return nil
	}
}

// assessControl assesses a single compliance control against the REAL fleet
// protection state. Controls without a mapped signal are explicitly
// not_assessed — a score is never fabricated for them.
func (s *ComplianceService) assessControl(control models.ControlAssessment, fleet *repository.FleetProtectionStats) models.ControlAssessment {
	assessment := control
	assessment.LastAssessedAt = time.Now()

	signal := fleetSignalForControl(control.ControlID, fleet)
	if signal == nil {
		assessment.Assessor = "none"
		assessment.Status = models.ComplianceStatusNotAssessed
		assessment.Score = 0
		assessment.Gaps = []string{"No automated signal is mapped to this control; manual assessment is required"}
		assessment.Remediation = []string{"Assess this control manually"}
		return assessment
	}

	assessment.Assessor = "automated"
	if fleet.TotalActiveDevices == 0 {
		assessment.Status = models.ComplianceStatusNotAssessed
		assessment.Score = 0
		assessment.Gaps = []string{"No active devices are enrolled; there is nothing to assess"}
		return assessment
	}

	coverage := float64(signal.covered) / float64(fleet.TotalActiveDevices)
	assessment.Score = coverage * 100
	assessment.Evidence = []string{fmt.Sprintf("%d of %d active devices have %s",
		signal.covered, fleet.TotalActiveDevices, signal.capability)}

	switch {
	case coverage >= 0.9:
		assessment.Status = models.ComplianceStatusCompliant
	case coverage >= 0.5:
		assessment.Status = models.ComplianceStatusPartial
		assessment.Gaps = []string{fmt.Sprintf("%d active devices lack %s",
			fleet.TotalActiveDevices-signal.covered, signal.capability)}
		assessment.Remediation = []string{"Enable the missing protection on uncovered devices"}
	default:
		assessment.Status = models.ComplianceStatusNonCompliant
		assessment.Gaps = []string{fmt.Sprintf("%d active devices lack %s",
			fleet.TotalActiveDevices-signal.covered, signal.capability)}
		assessment.Remediation = []string{"Enable the missing protection on uncovered devices"}
	}

	return assessment
}

// GetReport retrieves a compliance report
func (s *ComplianceService) GetReport(id uuid.UUID) (*models.ComplianceReport, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	report, ok := s.reports[id]
	if !ok {
		return nil, fmt.Errorf("report not found: %s", id)
	}
	return report, nil
}

// ListReports lists all compliance reports
func (s *ComplianceService) ListReports() []*models.ComplianceReport {
	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make([]*models.ComplianceReport, 0, len(s.reports))
	for _, r := range s.reports {
		result = append(result, r)
	}
	return result
}

// GetDeviceComplianceStatus gets compliance status for a device, assessed
// from the device's REAL protection-module state. Only controls with a
// mapped device signal are assessed; the rest are counted as not_assessed.
func (s *ComplianceService) GetDeviceComplianceStatus(ctx context.Context, deviceID uuid.UUID) (*models.DeviceComplianceStatus, error) {
	if s.repos == nil || s.repos.Devices == nil || s.netRepo == nil {
		return nil, fmt.Errorf("device compliance assessment unavailable: database not configured")
	}

	idStr := deviceID.String()
	device, err := s.repos.Devices.FindByID(ctx, idStr)
	if err != nil || device == nil {
		device, err = s.repos.Devices.FindByHardwareID(ctx, idStr)
	}
	if err != nil || device == nil {
		return nil, fmt.Errorf("%w: %s", ErrDeviceNotFound, idStr)
	}

	state, err := s.netRepo.GetDeviceProtectionState(ctx, idStr)
	if err != nil {
		return nil, fmt.Errorf("read device protection state: %w", err)
	}

	status := &models.DeviceComplianceStatus{
		DeviceID:        deviceID,
		FrameworkStatus: make(map[models.ComplianceFramework]models.FrameworkComplianceStatus),
		Issues:          make([]models.ComplianceIssue, 0),
		LastCheckedAt:   time.Now(),
		NextCheckAt:     time.Now().Add(24 * time.Hour),
	}

	// Assess against each framework with a control catalog.
	frameworks := []models.ComplianceFramework{
		models.ComplianceGDPR,
		models.ComplianceSOC2,
		models.ComplianceCIS,
	}

	totalScore := 0.0
	assessedFrameworks := 0
	for _, fw := range frameworks {
		fwStatus, issues := s.assessDeviceForFramework(deviceID, fw, state)
		status.FrameworkStatus[fw] = fwStatus
		status.Issues = append(status.Issues, issues...)
		if fwStatus.Status != models.ComplianceStatusNotAssessed {
			totalScore += fwStatus.Score
			assessedFrameworks++
		}
	}

	// Average over frameworks that actually have assessed controls only.
	if assessedFrameworks > 0 {
		status.ComplianceScore = totalScore / float64(assessedFrameworks)
		status.IsCompliant = status.ComplianceScore >= 70
	}

	return status, nil
}

// deviceControlChecks maps framework control IDs to boolean checks against
// the device's real protection state. Only these controls are automated at
// the device level; everything else in the catalog is not_assessed.
func deviceControlChecks(framework models.ComplianceFramework, state *repository.DeviceProtectionState) map[string]bool {
	monitoring := state.NetworkAuditRecent || state.SMSActive || state.AppScanActive
	switch framework {
	case models.ComplianceCIS:
		return map[string]bool{
			"CIS-9":  state.DNSConfigured,      // Email and Browser Protections
			"CIS-10": state.AppScanActive,      // Malware Defenses
			"CIS-13": state.NetworkAuditRecent, // Network Monitoring and Defense
		}
	case models.ComplianceSOC2:
		return map[string]bool{
			"CC7.2": monitoring, // Incident Response: monitors for anomalies
		}
	case models.ComplianceGDPR:
		return map[string]bool{
			"GDPR-32": monitoring, // Security of Processing
		}
	default:
		return nil
	}
}

// frameworkControlCount returns the catalog size for a framework.
func frameworkControlCount(framework models.ComplianceFramework) int {
	switch framework {
	case models.ComplianceGDPR:
		return len(models.GDPRControls)
	case models.ComplianceSOC2:
		return len(models.SOC2Controls)
	case models.ComplianceCIS:
		return len(models.CISControls)
	default:
		return 0
	}
}

// assessDeviceForFramework assesses a device against the controls of a
// framework that map to real device signals. The score covers assessed
// controls only; unmapped controls are counted in NotAssessedControls.
func (s *ComplianceService) assessDeviceForFramework(deviceID uuid.UUID, framework models.ComplianceFramework, state *repository.DeviceProtectionState) (models.FrameworkComplianceStatus, []models.ComplianceIssue) {
	now := time.Now()
	status := models.FrameworkComplianceStatus{
		Framework:     framework,
		LastCheckedAt: now,
	}

	checks := deviceControlChecks(framework, state)
	issues := make([]models.ComplianceIssue, 0)

	for controlID, passed := range checks {
		if passed {
			status.PassedControls++
		} else {
			status.FailedControls++
			issues = append(issues, models.ComplianceIssue{
				ID:          uuid.New(),
				Framework:   framework,
				ControlID:   controlID,
				Severity:    models.SeverityMedium,
				Title:       fmt.Sprintf("Control %s not satisfied", controlID),
				Description: "The protection capability mapped to this control is not configured or has not been active in the last 30 days on this device",
				Remediation: "Enable the corresponding protection module in the OrbGuard app",
				DetectedAt:  now,
			})
		}
	}
	status.NotAssessedControls = frameworkControlCount(framework) - len(checks)

	assessed := status.PassedControls + status.FailedControls
	if assessed == 0 {
		status.Status = models.ComplianceStatusNotAssessed
		return status, issues
	}

	status.Score = float64(status.PassedControls) * 100 / float64(assessed)
	switch {
	case status.FailedControls == 0:
		status.Status = models.ComplianceStatusCompliant
	case status.PassedControls == 0:
		status.Status = models.ComplianceStatusNonCompliant
	default:
		status.Status = models.ComplianceStatusPartial
	}

	return status, issues
}

// CreateFinding creates a compliance finding
func (s *ComplianceService) CreateFinding(finding *models.ComplianceFinding) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	finding.ID = uuid.New()
	finding.CreatedAt = time.Now()
	finding.UpdatedAt = time.Now()
	finding.Status = "open"

	s.findings[finding.ID] = finding
	return nil
}

// GetFinding retrieves a finding
func (s *ComplianceService) GetFinding(id uuid.UUID) (*models.ComplianceFinding, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	finding, ok := s.findings[id]
	if !ok {
		return nil, fmt.Errorf("finding not found: %s", id)
	}
	return finding, nil
}

// ListFindings lists all findings
func (s *ComplianceService) ListFindings(status string) []*models.ComplianceFinding {
	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make([]*models.ComplianceFinding, 0)
	for _, f := range s.findings {
		if status == "" || f.Status == status {
			result = append(result, f)
		}
	}
	return result
}

// UpdateFinding updates a finding
func (s *ComplianceService) UpdateFinding(finding *models.ComplianceFinding) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.findings[finding.ID]; !ok {
		return fmt.Errorf("finding not found: %s", finding.ID)
	}

	finding.UpdatedAt = time.Now()
	s.findings[finding.ID] = finding
	return nil
}

// ResolveFinding marks a finding as resolved
func (s *ComplianceService) ResolveFinding(id uuid.UUID, resolvedBy string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	finding, ok := s.findings[id]
	if !ok {
		return fmt.Errorf("finding not found: %s", id)
	}

	now := time.Now()
	finding.Status = "resolved"
	finding.ResolvedAt = &now
	finding.ResolvedBy = resolvedBy
	finding.UpdatedAt = now

	return nil
}

// GetSupportedFrameworks returns list of supported compliance frameworks
func (s *ComplianceService) GetSupportedFrameworks() []map[string]string {
	return []map[string]string{
		{"id": string(models.ComplianceGDPR), "name": "GDPR", "description": "General Data Protection Regulation"},
		{"id": string(models.ComplianceSOC2), "name": "SOC 2", "description": "Service Organization Control 2"},
		{"id": string(models.ComplianceHIPAA), "name": "HIPAA", "description": "Health Insurance Portability and Accountability Act"},
		{"id": string(models.CompliancePCIDSS), "name": "PCI DSS", "description": "Payment Card Industry Data Security Standard"},
		{"id": string(models.ComplianceISO27001), "name": "ISO 27001", "description": "Information Security Management System"},
		{"id": string(models.ComplianceNIST), "name": "NIST", "description": "National Institute of Standards and Technology"},
		{"id": string(models.ComplianceCIS), "name": "CIS", "description": "Center for Internet Security Controls"},
	}
}

// GetComplianceStats returns compliance statistics
func (s *ComplianceService) GetComplianceStats() map[string]interface{} {
	s.mu.RLock()
	defer s.mu.RUnlock()

	openFindings := 0
	criticalFindings := 0
	for _, f := range s.findings {
		if f.Status == "open" {
			openFindings++
			if f.Severity == models.SeverityCritical {
				criticalFindings++
			}
		}
	}

	return map[string]interface{}{
		"total_reports":     len(s.reports),
		"total_findings":    len(s.findings),
		"open_findings":     openFindings,
		"critical_findings": criticalFindings,
	}
}

// ============================================================================
// Enterprise Service (Combines all enterprise services)
// ============================================================================

// EnterpriseService combines all enterprise services
type EnterpriseService struct {
	MDM        *MDMService
	ZeroTrust  *ZeroTrustService
	SIEM       *SIEMService
	Compliance *ComplianceService

	repos  *repository.Repositories
	cache  *cache.RedisCache
	logger *logger.Logger
}

// NewEnterpriseService creates a new enterprise service
func NewEnterpriseService(repos *repository.Repositories, cache *cache.RedisCache, log *logger.Logger) *EnterpriseService {
	return &EnterpriseService{
		MDM:        NewMDMService(repos, cache, log),
		ZeroTrust:  NewZeroTrustService(repos, cache, log),
		SIEM:       NewSIEMService(repos, cache, log),
		Compliance: NewComplianceService(repos, cache, log),
		repos:      repos,
		cache:      cache,
		logger:     log.WithComponent("enterprise"),
	}
}

// Start starts all enterprise services
func (s *EnterpriseService) Start(ctx context.Context) {
	s.SIEM.Start(ctx)
	s.logger.Info().Msg("enterprise services started")
}

// Stop stops all enterprise services
func (s *EnterpriseService) Stop() {
	s.SIEM.Stop()
	s.logger.Info().Msg("enterprise services stopped")
}

// GetStats returns combined enterprise statistics
func (s *EnterpriseService) GetStats() *models.EnterpriseStats {
	mdmStats := s.MDM.GetMDMStats()
	_ = s.ZeroTrust.GetZeroTrustStats() // Zero Trust stats tracked separately via posture assessments
	siemStats := s.SIEM.GetSIEMStats()
	compStats := s.Compliance.GetComplianceStats()

	return &models.EnterpriseStats{
		MDMIntegrations:     mdmStats["total_integrations"].(int),
		MDMDevices:          mdmStats["total_devices"].(int),
		MDMCompliantDevices: mdmStats["compliant_devices"].(int),

		SIEMIntegrations: siemStats["total_integrations"].(int),
		EventsSentToday:  siemStats["total_events_sent"].(int64),

		ComplianceReports: compStats["total_reports"].(int),
		OpenFindings:      compStats["open_findings"].(int),
		CriticalFindings:  compStats["critical_findings"].(int),

		Timestamp: time.Now(),
	}
}

// LogAuditEvent logs an audit event and sends to SIEM
func (s *EnterpriseService) LogAuditEvent(ctx context.Context, log *models.AuditLog) {
	// Convert to SIEM event and send
	event := &models.SIEMEvent{
		ID:         log.ID.String(),
		Timestamp:  log.Timestamp,
		EventType:  "audit",
		Severity:   models.SeverityInfo,
		Source:     "orbguard",
		SourceHost: log.ActorIP,
		UserID:     log.ActorID,
		UserName:   log.ActorName,
		Category:   "audit",
		Action:     log.Action,
		Outcome:    log.Outcome,
		Message:    log.Details,
	}

	s.SIEM.SendEvent(ctx, event)
}
