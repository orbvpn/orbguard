package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services/push"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// ErrDeviceSecurityPersistenceUnavailable is returned when the service is
// running without a database connection. No anti-theft state can be stored
// or retrieved in that mode.
var ErrDeviceSecurityPersistenceUnavailable = errors.New("device security persistence unavailable: database not configured")

// maxLocationHistory bounds the per-device location history kept in Postgres.
const maxLocationHistory = 100

// deviceCacheTTL is how long device records are cached in Redis. Postgres is
// the source of truth; the cache only absorbs hot read paths (status polls).
const deviceCacheTTL = 60 * time.Second

// DeviceSecurityService handles device security operations (anti-theft,
// remote commands, SIM monitoring, OS vulnerability auditing). All durable
// state lives in Postgres via DeviceSecurityRepository.
type DeviceSecurityService struct {
	repo   *repository.DeviceSecurityRepository
	cache  *cache.RedisCache
	push   push.Sender
	logger *logger.Logger
}

// NewDeviceSecurityService creates a new device security service. repo may be
// nil when the API runs without a database; persistence-dependent operations
// then return ErrDeviceSecurityPersistenceUnavailable.
//
// pushSender delivers real-time "command pending" notifications so devices
// poll immediately after a remote command is issued. It may be nil (or a
// disabled no-op Sender) — command creation never depends on push success.
func NewDeviceSecurityService(repo *repository.DeviceSecurityRepository, c *cache.RedisCache, pushSender push.Sender, log *logger.Logger) *DeviceSecurityService {
	return &DeviceSecurityService{
		repo:   repo,
		cache:  c,
		push:   pushSender,
		logger: log.WithComponent("device-security"),
	}
}

// RegisterPushToken stores/refreshes a device's FCM token so anti-theft
// commands can be delivered in real time. platform is "android" or "ios".
func (s *DeviceSecurityService) RegisterPushToken(ctx context.Context, deviceID, token, platform string) error {
	if err := s.requireRepo(); err != nil {
		return err
	}
	if err := s.repo.UpsertToken(ctx, deviceID, token, platform); err != nil {
		return fmt.Errorf("persist push token: %w", err)
	}
	s.invalidateDeviceCache(ctx, deviceID)
	s.logger.Info().Str("device_id", deviceID).Str("platform", platform).Msg("push token registered")
	return nil
}

// notifyCommandPending best-effort delivers a real-time push so the device
// polls immediately. Any failure is logged and swallowed: the command is still
// delivered by polling, so push must never affect command-creation outcome.
func (s *DeviceSecurityService) notifyCommandPending(ctx context.Context, deviceID string) {
	if s.push == nil {
		return
	}
	if err := s.push.NotifyCommand(ctx, deviceID); err != nil {
		s.logger.Warn().Err(err).Str("device_id", deviceID).Msg("command push notification failed (command still polled)")
	}
}

func (s *DeviceSecurityService) requireRepo() error {
	if s.repo == nil {
		return ErrDeviceSecurityPersistenceUnavailable
	}
	return nil
}

func (s *DeviceSecurityService) deviceCacheKey(deviceID string) string {
	return "device:security:" + deviceID
}

func (s *DeviceSecurityService) invalidateDeviceCache(ctx context.Context, deviceID string) {
	if s.cache == nil {
		return
	}
	if err := s.cache.Delete(ctx, s.deviceCacheKey(deviceID)); err != nil {
		s.logger.Warn().Err(err).Str("device_id", deviceID).Msg("failed to invalidate device cache")
	}
}

// defaultAntiTheftSettings returns the default settings document for a device.
func defaultAntiTheftSettings(deviceID string) *models.AntiTheftSettings {
	return &models.AntiTheftSettings{
		DeviceID:             deviceID,
		EnableRemoteLocate:   true,
		EnableRemoteLock:     true,
		EnableRemoteWipe:     false, // Disabled by default for safety
		EnableThiefSelfie:    true,
		EnableSIMAlert:       true,
		SelfieOnWrongPIN:     true,
		SelfieOnWrongPattern: true,
		SelfieAfterAttempts:  3,
		AlertPushEnabled:     true,
		UpdatedAt:            time.Now(),
	}
}

// RegisterDevice registers a new device for tracking
func (s *DeviceSecurityService) RegisterDevice(ctx context.Context, device *models.SecureDeviceInfo) error {
	if err := s.requireRepo(); err != nil {
		return err
	}

	if device.ID == uuid.Nil {
		device.ID = uuid.New()
	}
	device.RegisteredAt = time.Now()
	device.UpdatedAt = time.Now()
	device.LastSeen = time.Now()
	device.Status = models.DeviceStatusActive

	if err := s.repo.UpsertDevice(ctx, device); err != nil {
		return fmt.Errorf("persist device: %w", err)
	}

	// Initialize default settings without clobbering an existing config
	// (re-registration after app reinstall must not reset user choices).
	if err := s.repo.InsertDefaultSettings(ctx, defaultAntiTheftSettings(device.DeviceID)); err != nil {
		return fmt.Errorf("persist default settings: %w", err)
	}

	s.invalidateDeviceCache(ctx, device.DeviceID)

	s.logger.Info().
		Str("device_id", device.DeviceID).
		Str("model", device.Model).
		Str("platform", device.Platform).
		Msg("device registered")

	return nil
}

// UpdateDevice updates device information
func (s *DeviceSecurityService) UpdateDevice(ctx context.Context, deviceID string, update *models.SecureDeviceInfo) error {
	if err := s.requireRepo(); err != nil {
		return err
	}

	device, err := s.repo.GetDevice(ctx, deviceID)
	if err != nil {
		return err
	}

	// Update fields
	if update.Name != "" {
		device.Name = update.Name
	}
	if update.OSVersion != "" {
		device.OSVersion = update.OSVersion
	}
	if update.SecurityPatch != "" {
		device.SecurityPatch = update.SecurityPatch
	}
	if update.APILevel > 0 {
		device.APILevel = update.APILevel
	}
	device.IsRooted = update.IsRooted
	device.IsEncrypted = update.IsEncrypted
	device.HasScreenLock = update.HasScreenLock
	if update.BiometricType != "" {
		device.BiometricType = update.BiometricType
	}
	device.LastSeen = time.Now()

	if err := s.repo.UpsertDevice(ctx, device); err != nil {
		return fmt.Errorf("persist device update: %w", err)
	}

	s.invalidateDeviceCache(ctx, deviceID)
	return nil
}

// GetDevice returns device information
func (s *DeviceSecurityService) GetDevice(ctx context.Context, deviceID string) (*models.SecureDeviceInfo, error) {
	if err := s.requireRepo(); err != nil {
		return nil, err
	}

	// Hot path: short-TTL Redis cache in front of Postgres.
	if s.cache != nil {
		var cached models.SecureDeviceInfo
		if err := s.cache.GetJSON(ctx, s.deviceCacheKey(deviceID), &cached); err == nil && cached.DeviceID == deviceID {
			return &cached, nil
		}
	}

	device, err := s.repo.GetDevice(ctx, deviceID)
	if err != nil {
		return nil, err
	}

	if s.cache != nil {
		if err := s.cache.SetJSON(ctx, s.deviceCacheKey(deviceID), device, deviceCacheTTL); err != nil {
			s.logger.Warn().Err(err).Str("device_id", deviceID).Msg("failed to cache device")
		}
	}

	return device, nil
}

// UpdateLocation updates device location
func (s *DeviceSecurityService) UpdateLocation(ctx context.Context, deviceID string, location *models.Location) error {
	if err := s.requireRepo(); err != nil {
		return err
	}

	// Validate device exists before recording.
	if _, err := s.repo.GetDevice(ctx, deviceID); err != nil {
		return err
	}

	location.Timestamp = time.Now()

	// Persist the fix, update last known location, trim history to bound.
	if err := s.repo.InsertLocation(ctx, deviceID, location, maxLocationHistory); err != nil {
		return fmt.Errorf("persist location: %w", err)
	}

	s.invalidateDeviceCache(ctx, deviceID)
	return nil
}

// GetLocationHistory returns location history for a device
func (s *DeviceSecurityService) GetLocationHistory(ctx context.Context, deviceID string, limit int) ([]*models.Location, error) {
	if err := s.requireRepo(); err != nil {
		return nil, err
	}
	return s.repo.GetLocations(ctx, deviceID, limit)
}

// IssueCommand issues a remote command to a device
func (s *DeviceSecurityService) IssueCommand(ctx context.Context, cmd *models.RemoteCommand) error {
	if err := s.requireRepo(); err != nil {
		return err
	}

	// Validate device exists
	device, err := s.repo.GetDevice(ctx, cmd.DeviceID)
	if err != nil {
		return err
	}

	// Check settings
	settings, err := s.repo.GetSettings(ctx, cmd.DeviceID)
	if err != nil {
		return fmt.Errorf("load settings: %w", err)
	}
	if settings != nil {
		switch cmd.Type {
		case models.CommandLocate:
			if !settings.EnableRemoteLocate {
				return fmt.Errorf("remote locate is disabled for this device")
			}
		case models.CommandLock, models.CommandUnlock:
			if !settings.EnableRemoteLock {
				return fmt.Errorf("remote lock is disabled for this device")
			}
		case models.CommandWipe:
			if !settings.EnableRemoteWipe {
				return fmt.Errorf("remote wipe is disabled for this device")
			}
			// Require confirmation for wipe
			var payload models.WipeCommandPayload
			if err := json.Unmarshal([]byte(cmd.Payload), &payload); err != nil || payload.ConfirmationID == "" {
				return fmt.Errorf("wipe command requires valid confirmation_id")
			}
		case models.CommandTakeSelfie:
			if !settings.EnableThiefSelfie {
				return fmt.Errorf("thief selfie is disabled for this device")
			}
		}
	}

	// Initialize command
	if cmd.ID == uuid.Nil {
		cmd.ID = uuid.New()
	}
	cmd.Status = models.CommandStatusPending
	cmd.CreatedAt = time.Now()
	cmd.ExpiresAt = time.Now().Add(24 * time.Hour) // Commands expire after 24 hours

	if err := s.repo.InsertCommand(ctx, cmd); err != nil {
		return fmt.Errorf("persist command: %w", err)
	}

	// Update device status based on command
	switch cmd.Type {
	case models.CommandLock:
		if err := s.repo.UpdateDeviceStatus(ctx, device.DeviceID, models.DeviceStatusLocked); err != nil {
			s.logger.Error().Err(err).Str("device_id", device.DeviceID).Msg("failed to update device status to locked")
		}
		s.invalidateDeviceCache(ctx, device.DeviceID)
	case models.CommandWipe:
		if err := s.repo.UpdateDeviceStatus(ctx, device.DeviceID, models.DeviceStatusWiped); err != nil {
			s.logger.Error().Err(err).Str("device_id", device.DeviceID).Msg("failed to update device status to wiped")
		}
		s.invalidateDeviceCache(ctx, device.DeviceID)
	}

	s.logger.Info().
		Str("device_id", cmd.DeviceID).
		Str("command", string(cmd.Type)).
		Str("command_id", cmd.ID.String()).
		Msg("command issued")

	// Best-effort real-time delivery: tell the device to poll now. Push
	// failure never fails command creation — the command is already persisted
	// and will be delivered by polling.
	s.notifyCommandPending(ctx, cmd.DeviceID)

	return nil
}

// GetPendingCommands returns pending commands for a device
func (s *DeviceSecurityService) GetPendingCommands(ctx context.Context, deviceID string) ([]*models.RemoteCommand, error) {
	if err := s.requireRepo(); err != nil {
		return nil, err
	}
	return s.repo.GetPendingCommands(ctx, deviceID)
}

// AcknowledgeCommand marks a command as executed
func (s *DeviceSecurityService) AcknowledgeCommand(ctx context.Context, deviceID string, commandID uuid.UUID, result string, err error) error {
	if repoErr := s.requireRepo(); repoErr != nil {
		return repoErr
	}

	status := models.CommandStatusExecuted
	errMsg := ""
	if err != nil {
		status = models.CommandStatusFailed
		errMsg = err.Error()
	}

	found, ackErr := s.repo.AckCommand(ctx, deviceID, commandID, status, result, errMsg, time.Now())
	if ackErr != nil {
		return fmt.Errorf("persist command ack: %w", ackErr)
	}
	if !found {
		return fmt.Errorf("command not found: %s", commandID)
	}
	return nil
}

// ReportSIMInfo reports current SIM information
func (s *DeviceSecurityService) ReportSIMInfo(ctx context.Context, deviceID string, sims []*models.SIMInfo) error {
	if err := s.requireRepo(); err != nil {
		return err
	}

	oldSIMs, err := s.repo.GetSIMs(ctx, deviceID, true)
	if err != nil {
		return fmt.Errorf("load current SIMs: %w", err)
	}

	// Context for risk scoring (device may legitimately be unregistered yet).
	device, _ := s.repo.GetDevice(ctx, deviceID)
	settings, settingsErr := s.repo.GetSettings(ctx, deviceID)
	if settingsErr != nil {
		s.logger.Warn().Err(settingsErr).Str("device_id", deviceID).Msg("failed to load settings for SIM risk scoring")
	}

	// Check for new / refreshed SIMs
	for _, newSIM := range sims {
		newSIM.DeviceID = deviceID

		isNew := true
		for _, oldSIM := range oldSIMs {
			if oldSIM.ICCID == newSIM.ICCID {
				isNew = false
				break
			}
		}

		// Upsert refreshes last_seen/is_active and preserves first_seen.
		if err := s.repo.UpsertSIM(ctx, newSIM); err != nil {
			return fmt.Errorf("persist SIM %s: %w", newSIM.ICCID, err)
		}

		if isNew {
			// Create SIM change event
			event := &models.SIMChangeEvent{
				ID:         uuid.New(),
				DeviceID:   deviceID,
				EventType:  models.SIMEventInserted,
				NewSIM:     newSIM,
				DetectedAt: time.Now(),
			}

			// Calculate risk level
			event.RiskLevel = s.calculateSIMRisk(device, settings, event)

			// Alert if high risk
			if event.RiskLevel == models.SIMRiskCritical || event.RiskLevel == models.SIMRiskHigh {
				event.IsAlerted = true
				now := time.Now()
				event.AlertedAt = &now

				s.logger.Warn().
					Str("device_id", deviceID).
					Str("iccid", newSIM.ICCID).
					Str("carrier", newSIM.Carrier).
					Str("risk", string(event.RiskLevel)).
					Msg("SIM change alert")
			}

			if err := s.repo.InsertSIMEvent(ctx, event); err != nil {
				return fmt.Errorf("persist SIM event: %w", err)
			}
		}
	}

	// Check for removed SIMs
	for _, oldSIM := range oldSIMs {
		found := false
		for _, newSIM := range sims {
			if oldSIM.ICCID == newSIM.ICCID {
				found = true
				break
			}
		}
		if found {
			continue
		}

		wasActive := oldSIM.IsActive

		if err := s.repo.MarkSIMAbsent(ctx, deviceID, oldSIM.ICCID); err != nil {
			return fmt.Errorf("mark SIM absent %s: %w", oldSIM.ICCID, err)
		}

		if wasActive {
			now := time.Now()
			event := &models.SIMChangeEvent{
				ID:         uuid.New(),
				DeviceID:   deviceID,
				EventType:  models.SIMEventRemoved,
				OldSIM:     oldSIM,
				RiskLevel:  models.SIMRiskHigh,
				IsAlerted:  true,
				AlertedAt:  &now,
				DetectedAt: now,
			}
			if err := s.repo.InsertSIMEvent(ctx, event); err != nil {
				return fmt.Errorf("persist SIM removal event: %w", err)
			}

			s.logger.Warn().
				Str("device_id", deviceID).
				Str("iccid", oldSIM.ICCID).
				Msg("SIM removed alert")
		}
	}

	return nil
}

// calculateSIMRisk calculates the risk level of a SIM change
func (s *DeviceSecurityService) calculateSIMRisk(device *models.SecureDeviceInfo, settings *models.AntiTheftSettings, event *models.SIMChangeEvent) models.SIMRiskLevel {
	// Check if SIM is in trusted list
	if settings != nil && event.NewSIM != nil {
		for _, trustedICCID := range settings.TrustedSIMICCIDs {
			if event.NewSIM.ICCID == trustedICCID {
				return models.SIMRiskLow
			}
		}
	}

	// Check for suspicious patterns
	if device != nil {
		// If device was reported lost/stolen, any SIM change is critical
		if device.Status == models.DeviceStatusLost || device.Status == models.DeviceStatusStolen {
			return models.SIMRiskCritical
		}
	}

	// Check timing - SIM changes at unusual hours are higher risk
	hour := time.Now().Hour()
	if hour >= 0 && hour < 6 {
		return models.SIMRiskHigh
	}

	// Check if location changed significantly
	if event.Location != nil && device != nil && device.LastLocation != nil {
		// Simple distance check (would use proper haversine in production)
		latDiff := event.Location.Latitude - device.LastLocation.Latitude
		lonDiff := event.Location.Longitude - device.LastLocation.Longitude
		if latDiff*latDiff+lonDiff*lonDiff > 0.01 { // ~1km at equator
			return models.SIMRiskHigh
		}
	}

	// Default to medium risk for unknown SIMs
	return models.SIMRiskMedium
}

// GetSIMHistory returns SIM change history for a device
func (s *DeviceSecurityService) GetSIMHistory(ctx context.Context, deviceID string) ([]*models.SIMChangeEvent, error) {
	if err := s.requireRepo(); err != nil {
		return nil, err
	}
	return s.repo.GetSIMEvents(ctx, deviceID, 200)
}

// GetCurrentSIMs returns current SIM information for a device
func (s *DeviceSecurityService) GetCurrentSIMs(ctx context.Context, deviceID string) ([]*models.SIMInfo, error) {
	if err := s.requireRepo(); err != nil {
		return nil, err
	}
	return s.repo.GetSIMs(ctx, deviceID, true)
}

// AddTrustedSIM adds a SIM to the trusted list
func (s *DeviceSecurityService) AddTrustedSIM(ctx context.Context, deviceID string, iccid string) error {
	if err := s.requireRepo(); err != nil {
		return err
	}

	settings, err := s.repo.GetSettings(ctx, deviceID)
	if err != nil {
		return fmt.Errorf("load settings: %w", err)
	}
	if settings == nil {
		settings = defaultAntiTheftSettings(deviceID)
	}

	// Check if already trusted
	for _, trusted := range settings.TrustedSIMICCIDs {
		if trusted == iccid {
			return nil
		}
	}

	settings.TrustedSIMICCIDs = append(settings.TrustedSIMICCIDs, iccid)
	settings.UpdatedAt = time.Now()

	if err := s.repo.UpsertSettings(ctx, settings); err != nil {
		return fmt.Errorf("persist settings: %w", err)
	}
	return nil
}

// RecordThiefSelfie records a thief selfie capture
func (s *DeviceSecurityService) RecordThiefSelfie(ctx context.Context, selfie *models.ThiefSelfie) error {
	if err := s.requireRepo(); err != nil {
		return err
	}

	if selfie.ID == uuid.Nil {
		selfie.ID = uuid.New()
	}
	selfie.CapturedAt = time.Now()

	if err := s.repo.InsertSelfie(ctx, selfie); err != nil {
		return fmt.Errorf("persist selfie: %w", err)
	}

	s.logger.Warn().
		Str("device_id", selfie.DeviceID).
		Str("trigger", selfie.TriggerType).
		Int("attempts", selfie.AttemptCount).
		Msg("thief selfie captured")

	return nil
}

// GetThiefSelfies returns thief selfies for a device
func (s *DeviceSecurityService) GetThiefSelfies(ctx context.Context, deviceID string) ([]*models.ThiefSelfie, error) {
	if err := s.requireRepo(); err != nil {
		return nil, err
	}
	return s.repo.GetSelfies(ctx, deviceID, 100)
}

// GetSettings returns anti-theft settings for a device
func (s *DeviceSecurityService) GetSettings(ctx context.Context, deviceID string) (*models.AntiTheftSettings, error) {
	if err := s.requireRepo(); err != nil {
		return nil, err
	}

	settings, err := s.repo.GetSettings(ctx, deviceID)
	if err != nil {
		return nil, fmt.Errorf("load settings: %w", err)
	}
	if settings == nil {
		// Return default settings
		return defaultAntiTheftSettings(deviceID), nil
	}
	return settings, nil
}

// UpdateSettings updates anti-theft settings
func (s *DeviceSecurityService) UpdateSettings(ctx context.Context, deviceID string, update *models.AntiTheftSettings) error {
	if err := s.requireRepo(); err != nil {
		return err
	}

	settings, err := s.repo.GetSettings(ctx, deviceID)
	if err != nil {
		return fmt.Errorf("load settings: %w", err)
	}
	if settings == nil {
		settings = &models.AntiTheftSettings{DeviceID: deviceID}
	}

	settings.EnableRemoteLocate = update.EnableRemoteLocate
	settings.EnableRemoteLock = update.EnableRemoteLock
	settings.EnableRemoteWipe = update.EnableRemoteWipe
	settings.EnableThiefSelfie = update.EnableThiefSelfie
	settings.EnableSIMAlert = update.EnableSIMAlert
	settings.SelfieOnWrongPIN = update.SelfieOnWrongPIN
	settings.SelfieOnWrongPattern = update.SelfieOnWrongPattern
	settings.SelfieAfterAttempts = update.SelfieAfterAttempts
	settings.AlertEmail = update.AlertEmail
	settings.AlertPhone = update.AlertPhone
	settings.AlertPushEnabled = update.AlertPushEnabled
	settings.UpdatedAt = time.Now()

	if err := s.repo.UpsertSettings(ctx, settings); err != nil {
		return fmt.Errorf("persist settings: %w", err)
	}
	return nil
}

// MarkDeviceLost marks a device as lost
func (s *DeviceSecurityService) MarkDeviceLost(ctx context.Context, deviceID string) error {
	if err := s.requireRepo(); err != nil {
		return err
	}
	if err := s.repo.UpdateDeviceStatus(ctx, deviceID, models.DeviceStatusLost); err != nil {
		return err
	}
	s.invalidateDeviceCache(ctx, deviceID)
	s.logger.Warn().Str("device_id", deviceID).Msg("device marked as lost")
	return nil
}

// MarkDeviceStolen marks a device as stolen
func (s *DeviceSecurityService) MarkDeviceStolen(ctx context.Context, deviceID string) error {
	if err := s.requireRepo(); err != nil {
		return err
	}
	if err := s.repo.UpdateDeviceStatus(ctx, deviceID, models.DeviceStatusStolen); err != nil {
		return err
	}
	s.invalidateDeviceCache(ctx, deviceID)
	s.logger.Warn().Str("device_id", deviceID).Msg("device marked as stolen")
	return nil
}

// MarkDeviceRecovered marks a device as recovered/active
func (s *DeviceSecurityService) MarkDeviceRecovered(ctx context.Context, deviceID string) error {
	if err := s.requireRepo(); err != nil {
		return err
	}
	if err := s.repo.UpdateDeviceStatus(ctx, deviceID, models.DeviceStatusActive); err != nil {
		return err
	}
	s.invalidateDeviceCache(ctx, deviceID)
	s.logger.Info().Str("device_id", deviceID).Msg("device marked as recovered")
	return nil
}

// AuditOSVulnerabilities checks device OS for known vulnerabilities
func (s *DeviceSecurityService) AuditOSVulnerabilities(ctx context.Context, deviceID string, platform string, osVersion string, securityPatch string, apiLevel int) *models.OSSecurityAuditResult {
	result := &models.OSSecurityAuditResult{
		DeviceID:        deviceID,
		Platform:        platform,
		OSVersion:       osVersion,
		SecurityPatch:   securityPatch,
		APILevel:        apiLevel,
		AuditedAt:       time.Now(),
		Vulnerabilities: make([]models.OSVulnerability, 0),
		Recommendations: make([]models.SecurityRecommendation, 0),
	}

	// Get relevant vulnerabilities
	var vulns []models.OSVulnerability
	var latestInfo models.LatestSecurityInfo

	if strings.ToLower(platform) == "android" {
		vulns = models.KnownAndroidVulnerabilities
		latestInfo = models.LatestAndroidSecurity
	} else if strings.ToLower(platform) == "ios" {
		vulns = models.KnowniOSVulnerabilities
		latestInfo = models.LatestiOSSecurity
	}

	result.LatestOSVersion = latestInfo.LatestVersion
	result.LatestPatchDate = latestInfo.LatestPatchDate

	// Check each vulnerability
	for _, vuln := range vulns {
		if s.isAffected(platform, osVersion, securityPatch, apiLevel, &vuln) {
			result.Vulnerabilities = append(result.Vulnerabilities, vuln)

			switch vuln.Severity {
			case models.VulnSeverityCritical:
				result.CriticalVulns++
			case models.VulnSeverityHigh:
				result.HighVulns++
			case models.VulnSeverityMedium:
				result.MediumVulns++
			case models.VulnSeverityLow:
				result.LowVulns++
			}

			if vuln.IsExploited {
				result.ExploitedVulns++
			}
		}
	}

	result.TotalVulns = len(result.Vulnerabilities)

	// Calculate risk score
	result.RiskScore = s.calculateOSRiskScore(result)
	result.RiskLevel = s.scoreToSeverity(result.RiskScore)

	// Check if up to date
	result.IsUpToDate = s.isOSUpToDate(platform, osVersion, securityPatch, latestInfo)

	// Calculate days behind
	result.DaysBehind = s.calculateDaysBehind(platform, securityPatch, latestInfo)

	// Generate recommendations
	result.Recommendations = s.generateOSRecommendations(result)

	return result
}

// isAffected checks if a device is affected by a vulnerability
func (s *DeviceSecurityService) isAffected(platform, osVersion, securityPatch string, apiLevel int, vuln *models.OSVulnerability) bool {
	// Check platform
	platformMatch := false
	for _, p := range vuln.AffectedOS {
		if strings.EqualFold(p, platform) {
			platformMatch = true
			break
		}
	}
	if !platformMatch {
		return false
	}

	// Check if patched
	if vuln.PatchedIn != "" && compareVersions(osVersion, vuln.PatchedIn) >= 0 {
		return false
	}

	if vuln.SecurityPatch != "" && securityPatch != "" && securityPatch >= vuln.SecurityPatch {
		return false
	}

	// Check version range
	for _, vr := range vuln.AffectedVersions {
		if vr.APILevel > 0 && apiLevel > 0 {
			if apiLevel >= vr.APILevel {
				continue // Not affected
			}
		}

		if vr.MinVersion != "" && compareVersions(osVersion, vr.MinVersion) < 0 {
			continue
		}
		if vr.MaxVersion != "" && compareVersions(osVersion, vr.MaxVersion) > 0 {
			continue
		}

		return true
	}

	return len(vuln.AffectedVersions) == 0 // If no specific versions, assume all affected
}

// compareVersions compares two version strings (simplified)
func compareVersions(v1, v2 string) int {
	// Split by common delimiters
	parts1 := strings.FieldsFunc(v1, func(r rune) bool { return r == '.' || r == '-' })
	parts2 := strings.FieldsFunc(v2, func(r rune) bool { return r == '.' || r == '-' })

	for i := 0; i < len(parts1) && i < len(parts2); i++ {
		if parts1[i] < parts2[i] {
			return -1
		}
		if parts1[i] > parts2[i] {
			return 1
		}
	}

	if len(parts1) < len(parts2) {
		return -1
	}
	if len(parts1) > len(parts2) {
		return 1
	}

	return 0
}

// calculateOSRiskScore calculates risk score based on vulnerabilities
func (s *DeviceSecurityService) calculateOSRiskScore(result *models.OSSecurityAuditResult) float64 {
	// Start with perfect score
	score := 100.0

	// Deduct for vulnerabilities
	score -= float64(result.CriticalVulns) * 25.0
	score -= float64(result.HighVulns) * 15.0
	score -= float64(result.MediumVulns) * 8.0
	score -= float64(result.LowVulns) * 3.0

	// Extra penalty for exploited vulnerabilities
	score -= float64(result.ExploitedVulns) * 10.0

	// Penalty for being behind on updates
	score -= float64(result.DaysBehind) * 0.5

	if score < 0 {
		score = 0
	}

	return score
}

// scoreToSeverity converts score to severity level
func (s *DeviceSecurityService) scoreToSeverity(score float64) models.VulnSeverity {
	switch {
	case score < 40:
		return models.VulnSeverityCritical
	case score < 60:
		return models.VulnSeverityHigh
	case score < 80:
		return models.VulnSeverityMedium
	default:
		return models.VulnSeverityLow
	}
}

// isOSUpToDate checks if OS is up to date
func (s *DeviceSecurityService) isOSUpToDate(platform, osVersion, securityPatch string, latest models.LatestSecurityInfo) bool {
	if platform == "android" && securityPatch != "" {
		return securityPatch >= latest.LatestPatchDate
	}
	return compareVersions(osVersion, latest.LatestVersion) >= 0
}

// calculateDaysBehind calculates how many days behind on security patches
func (s *DeviceSecurityService) calculateDaysBehind(platform, securityPatch string, latest models.LatestSecurityInfo) int {
	if securityPatch == "" {
		return 365 // Unknown, assume very old
	}

	// Parse security patch date (format: YYYY-MM-DD)
	patchDate, err := time.Parse("2006-01-02", securityPatch)
	if err != nil {
		return 90 // Unknown format
	}

	diff := time.Since(patchDate)
	days := int(diff.Hours() / 24)
	if days < 0 {
		days = 0
	}

	return days
}

// generateOSRecommendations generates security recommendations
func (s *DeviceSecurityService) generateOSRecommendations(result *models.OSSecurityAuditResult) []models.SecurityRecommendation {
	recs := make([]models.SecurityRecommendation, 0)
	priority := 1

	// Critical vulnerabilities
	if result.CriticalVulns > 0 {
		criticalCVEs := make([]string, 0)
		for _, v := range result.Vulnerabilities {
			if v.Severity == models.VulnSeverityCritical {
				criticalCVEs = append(criticalCVEs, v.ID)
			}
		}
		recs = append(recs, models.SecurityRecommendation{
			ID:          "update_critical",
			Priority:    priority,
			Title:       "Critical Security Update Required",
			Description: fmt.Sprintf("Your device has %d critical vulnerabilities that could allow attackers to take full control.", result.CriticalVulns),
			Action:      "Update your operating system immediately to the latest version.",
			AutoFixable: false,
			RelatedCVEs: criticalCVEs,
		})
		priority++
	}

	// Exploited vulnerabilities
	if result.ExploitedVulns > 0 {
		exploitedCVEs := make([]string, 0)
		for _, v := range result.Vulnerabilities {
			if v.IsExploited {
				exploitedCVEs = append(exploitedCVEs, v.ID)
			}
		}
		recs = append(recs, models.SecurityRecommendation{
			ID:          "exploited_vulns",
			Priority:    priority,
			Title:       "Actively Exploited Vulnerabilities",
			Description: fmt.Sprintf("Your device has %d vulnerabilities that are being actively exploited in the wild.", result.ExploitedVulns),
			Action:      "These vulnerabilities are being used by attackers. Update immediately.",
			AutoFixable: false,
			RelatedCVEs: exploitedCVEs,
		})
		priority++
	}

	// Outdated OS
	if !result.IsUpToDate {
		recs = append(recs, models.SecurityRecommendation{
			ID:          "outdated_os",
			Priority:    priority,
			Title:       "Operating System Out of Date",
			Description: fmt.Sprintf("Your device is %d days behind on security updates.", result.DaysBehind),
			Action:      fmt.Sprintf("Update to %s %s for the latest security patches.", result.Platform, result.LatestOSVersion),
			AutoFixable: false,
		})
		priority++
	}

	// High vulnerabilities
	if result.HighVulns > 0 {
		recs = append(recs, models.SecurityRecommendation{
			ID:          "high_vulns",
			Priority:    priority,
			Title:       "High Severity Vulnerabilities Present",
			Description: fmt.Sprintf("Your device has %d high severity vulnerabilities.", result.HighVulns),
			Action:      "Consider updating your device to address these security issues.",
			AutoFixable: false,
		})
		priority++
	}

	// Sort by priority
	sort.Slice(recs, func(i, j int) bool {
		return recs[i].Priority < recs[j].Priority
	})

	return recs
}

// GetDeviceSecurityStatus returns comprehensive security status
func (s *DeviceSecurityService) GetDeviceSecurityStatus(ctx context.Context, deviceID string) (*models.DeviceSecurityStatus, error) {
	if err := s.requireRepo(); err != nil {
		return nil, err
	}

	device, err := s.repo.GetDevice(ctx, deviceID)
	if err != nil {
		return nil, err
	}

	status := &models.DeviceSecurityStatus{
		DeviceID:   deviceID,
		DeviceInfo: device,
		LastCheck:  time.Now(),
		Issues:     make([]models.SecurityIssue, 0),
	}

	// Check if rooted
	if device.IsRooted {
		status.IsRooted = true
		status.Issues = append(status.Issues, models.SecurityIssue{
			ID:          "rooted_device",
			Type:        "root",
			Severity:    models.VulnSeverityHigh,
			Title:       "Device is Rooted/Jailbroken",
			Description: "Your device has root access enabled which increases security risks.",
			DetectedAt:  time.Now(),
		})
	}

	// Get anti-theft status
	settings, err := s.repo.GetSettings(ctx, deviceID)
	if err != nil {
		return nil, fmt.Errorf("load settings: %w", err)
	}
	if settings != nil {
		status.AntiTheftEnabled = settings.EnableRemoteLocate || settings.EnableRemoteLock || settings.EnableRemoteWipe
	}

	// Get location
	status.LastLocation = device.LastLocation

	// Count pending commands
	pendingCount, err := s.repo.CountPendingCommands(ctx, deviceID)
	if err != nil {
		return nil, fmt.Errorf("count pending commands: %w", err)
	}
	status.PendingCommands = pendingCount

	// Get SIM info
	sims, err := s.repo.GetSIMs(ctx, deviceID, true)
	if err != nil {
		return nil, fmt.Errorf("load SIMs: %w", err)
	}
	for _, sim := range sims {
		if sim.IsActive {
			status.CurrentSIM = sim
			break
		}
	}

	// Count SIM alerts
	alertCount, err := s.repo.CountAlertedSIMEvents(ctx, deviceID)
	if err != nil {
		return nil, fmt.Errorf("count SIM alerts: %w", err)
	}
	status.SIMChangeAlerts = alertCount

	// Run OS vulnerability audit
	osAudit := s.AuditOSVulnerabilities(ctx, deviceID, device.Platform, device.OSVersion, device.SecurityPatch, device.APILevel)
	status.OSSecurityScore = osAudit.RiskScore
	status.HasOSVulns = osAudit.TotalVulns > 0

	// Add OS vulnerability issues
	for _, vuln := range osAudit.Vulnerabilities {
		if vuln.Severity == models.VulnSeverityCritical || vuln.Severity == models.VulnSeverityHigh {
			status.Issues = append(status.Issues, models.SecurityIssue{
				ID:          vuln.ID,
				Type:        "os_vuln",
				Severity:    vuln.Severity,
				Title:       vuln.Title,
				Description: vuln.Description,
				DetectedAt:  time.Now(),
			})
		}
	}

	// Calculate overall score (weighted average)
	status.OverallScore = status.OSSecurityScore * 0.4
	if !device.IsRooted {
		status.OverallScore += 20.0
	}
	if device.IsEncrypted {
		status.OverallScore += 15.0
	}
	if device.HasScreenLock {
		status.OverallScore += 15.0
	}
	if status.AntiTheftEnabled {
		status.OverallScore += 10.0
	}

	// Top recommendations
	status.TopRecommendations = osAudit.Recommendations
	if len(status.TopRecommendations) > 3 {
		status.TopRecommendations = status.TopRecommendations[:3]
	}

	return status, nil
}

// GetStats returns service statistics sourced from the database.
func (s *DeviceSecurityService) GetStats() map[string]interface{} {
	stats := map[string]interface{}{
		"devices_tracked":   int64(0),
		"commands_issued":   int64(0),
		"commands_executed": int64(0),
		"sim_alerts_raised": int64(0),
		"selfies_taken":     int64(0),
		"android_vulns":     len(models.KnownAndroidVulnerabilities),
		"ios_vulns":         len(models.KnowniOSVulnerabilities),
	}

	if s.repo == nil {
		stats["error"] = ErrDeviceSecurityPersistenceUnavailable.Error()
		return stats
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dbStats, err := s.repo.GetStats(ctx)
	if err != nil {
		s.logger.Error().Err(err).Msg("failed to load device security stats")
		stats["error"] = "failed to load stats from database"
		return stats
	}

	stats["devices_tracked"] = dbStats.DevicesTracked
	stats["commands_issued"] = dbStats.CommandsIssued
	stats["commands_executed"] = dbStats.CommandsExecuted
	stats["sim_alerts_raised"] = dbStats.SIMAlertsRaised
	stats["selfies_taken"] = dbStats.SelfiesTaken
	return stats
}
