package services

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// Sentinel errors for the dark web monitoring service.
var (
	// ErrAssetNotFound is returned when an asset does not exist or does not
	// belong to the requesting user.
	ErrAssetNotFound = errors.New("monitored asset not found")
	// ErrAlertNotFound is returned when an alert does not exist or does not
	// belong to the requesting user.
	ErrAlertNotFound = errors.New("alert not found")
	// ErrNoBreachProviders is returned when no breach data provider (HIBP,
	// LeakCheck, IntelX) is configured.
	ErrNoBreachProviders = errors.New("no breach data providers configured")
	// ErrDarkWebStorageUnavailable is returned when the service is running
	// without a database and a persistence-backed operation is requested.
	ErrDarkWebStorageUnavailable = errors.New("dark web monitoring storage unavailable: database not connected")
)

const (
	breachCatalogCacheKey = "darkweb:breaches:catalog"
	breachCatalogTTL      = 24 * time.Hour
	emailCheckCacheTTL    = 1 * time.Hour
)

// DarkWebMonitor provides dark web and breach monitoring services. Monitored
// assets and breach alerts are persisted in Postgres
// (orbguard_lab.darkweb_assets / darkweb_alerts); Redis is used only for
// caching provider responses. Breach lookups aggregate every configured
// provider (HIBP, LeakCheck, Intelligence X), each failing independently.
type DarkWebMonitor struct {
	hibpClient *HIBPClient
	leakCheck  *LeakCheckClient // optional, nil or unconfigured when disabled
	intelX     *IntelXClient    // optional, nil or unconfigured when disabled
	repo       *repository.DarkWebRepository
	cache      *cache.RedisCache
	logger     *logger.Logger
}

// NewDarkWebMonitor creates a new dark web monitor. leakCheck and intelX may
// be nil when those providers are not configured. repo may be nil when the
// service runs without a database, in which case persistence-backed
// operations return ErrDarkWebStorageUnavailable.
func NewDarkWebMonitor(
	hibpClient *HIBPClient,
	leakCheck *LeakCheckClient,
	intelX *IntelXClient,
	repo *repository.DarkWebRepository,
	redisCache *cache.RedisCache,
	log *logger.Logger,
) *DarkWebMonitor {
	return &DarkWebMonitor{
		hibpClient: hibpClient,
		leakCheck:  leakCheck,
		intelX:     intelX,
		repo:       repo,
		cache:      redisCache,
		logger:     log.WithComponent("darkweb-monitor"),
	}
}

// CheckEmail checks if an email has been breached, aggregating all configured
// breach providers. Results are cached for one hour.
func (m *DarkWebMonitor) CheckEmail(ctx context.Context, req *models.BreachCheckRequest) (*models.BreachCheckResponse, error) {
	// Check cache first
	cacheKey := m.getCacheKey("email", req.Email)
	var cachedResult models.BreachCheckResponse
	if err := m.cache.GetJSON(ctx, cacheKey, &cachedResult); err == nil {
		return &cachedResult, nil
	}

	result, err := m.checkEmailProviders(ctx, req.Email)
	if err != nil {
		return nil, err
	}

	// Record real check statistics (best effort; skipped without a database)
	if m.repo != nil {
		if err := m.repo.RecordCheck(ctx, "email_check", result.IsBreached, result.BreachCount); err != nil {
			m.logger.Warn().Err(err).Msg("failed to record email check event")
		}
	}

	// Cache result for 1 hour
	_ = m.cache.SetJSON(ctx, cacheKey, result, emailCheckCacheTTL)

	return result, nil
}

// checkEmailProviders queries every configured breach provider and merges the
// results (deduplicated by breach name). Each provider fails independently:
// a failure is logged and the remaining providers are still consulted. An
// error is returned only when no provider is configured or every configured
// provider failed (so a false "not breached" is never reported).
func (m *DarkWebMonitor) checkEmailProviders(ctx context.Context, email string) (*models.BreachCheckResponse, error) {
	type providerResult struct {
		name     string
		breaches []models.Breach
		err      error
	}

	var results []providerResult

	if m.hibpClient != nil && m.hibpClient.Configured() {
		hibpResp, err := m.hibpClient.CheckEmail(ctx, email)
		var breaches []models.Breach
		if err == nil && hibpResp != nil {
			breaches = hibpResp.Breaches
		}
		results = append(results, providerResult{name: "hibp", breaches: breaches, err: err})
	}

	if m.leakCheck != nil && m.leakCheck.Configured() {
		breaches, err := m.leakCheck.CheckEmail(ctx, email)
		results = append(results, providerResult{name: "leakcheck", breaches: breaches, err: err})
	}

	if m.intelX != nil && m.intelX.Configured() {
		breaches, err := m.intelX.SearchLeaks(ctx, email)
		results = append(results, providerResult{name: "intelx", breaches: breaches, err: err})
	}

	if len(results) == 0 {
		return nil, ErrNoBreachProviders
	}

	merged := []models.Breach{}
	seen := make(map[string]bool)
	succeeded := 0
	var lastErr error

	for _, pr := range results {
		if pr.err != nil {
			lastErr = pr.err
			m.logger.Warn().Err(pr.err).Str("provider", pr.name).Msg("breach provider lookup failed, continuing with remaining providers")
			continue
		}
		succeeded++
		for _, breach := range pr.breaches {
			key := strings.ToLower(strings.TrimSpace(breach.Name))
			if key == "" || seen[key] {
				continue
			}
			seen[key] = true
			merged = append(merged, breach)
		}
	}

	if succeeded == 0 {
		return nil, fmt.Errorf("all breach providers failed: %w", lastErr)
	}

	return buildBreachCheckResponse(email, merged), nil
}

// buildBreachCheckResponse computes the aggregate response fields (exposed
// data types, first/latest breach, risk level, recommendations) from the
// merged breach list.
func buildBreachCheckResponse(email string, breaches []models.Breach) *models.BreachCheckResponse {
	response := &models.BreachCheckResponse{
		Email:       email,
		IsBreached:  len(breaches) > 0,
		BreachCount: len(breaches),
		Breaches:    breaches,
		CheckedAt:   time.Now(),
	}

	exposedTypesMap := make(map[string]bool)
	var firstBreach, latestBreach time.Time
	maxSeverity := models.BreachSeverityLow

	for _, breach := range breaches {
		for _, dataClass := range breach.DataClasses {
			exposedTypesMap[dataClass] = true
		}

		if !breach.BreachDate.IsZero() {
			if firstBreach.IsZero() || breach.BreachDate.Before(firstBreach) {
				firstBreach = breach.BreachDate
			}
			if latestBreach.IsZero() || breach.BreachDate.After(latestBreach) {
				latestBreach = breach.BreachDate
			}
		}

		if models.CompareSeverity(breach.Severity, maxSeverity) > 0 {
			maxSeverity = breach.Severity
		}
	}

	for dataType := range exposedTypesMap {
		response.ExposedDataTypes = append(response.ExposedDataTypes, dataType)
	}
	if !firstBreach.IsZero() {
		response.FirstBreach = &firstBreach
	}
	if !latestBreach.IsZero() {
		response.LatestBreach = &latestBreach
	}

	response.RiskLevel = maxSeverity
	if len(breaches) > 0 {
		response.Recommendations = generateBreachRecommendations(exposedTypesMap)
	} else {
		response.Recommendations = []string{"No breaches found. Continue using strong, unique passwords."}
	}

	return response
}

// CheckPassword checks if a password has been compromised
func (m *DarkWebMonitor) CheckPassword(ctx context.Context, req *models.PasswordCheckRequest) (*models.PasswordCheckResponse, error) {
	// Don't cache password results for security

	result, err := m.hibpClient.CheckPassword(ctx, req.Password)
	if err != nil {
		return nil, err
	}

	// Record real check statistics (best effort; skipped without a database)
	if m.repo != nil {
		if err := m.repo.RecordCheck(ctx, "password_check", result.IsBreached, result.BreachCount); err != nil {
			m.logger.Warn().Err(err).Msg("failed to record password check event")
		}
	}

	return result, nil
}

// AddMonitoredAsset adds an asset for continuous monitoring. Re-adding an
// asset the user already monitors re-activates the existing record.
func (m *DarkWebMonitor) AddMonitoredAsset(ctx context.Context, userID, deviceID string, assetType models.BreachType, value string) (*models.MonitoredAsset, error) {
	if m.repo == nil {
		return nil, ErrDarkWebStorageUnavailable
	}
	// Hash the value for lookup
	hash := sha256.Sum256([]byte(strings.ToLower(value)))
	hashStr := hex.EncodeToString(hash[:])

	asset := &models.MonitoredAsset{
		UserID:      userID,
		DeviceID:    deviceID,
		AssetType:   assetType,
		AssetValue:  value,
		AssetHash:   hashStr,
		DisplayName: m.maskValue(assetType, value),
		IsActive:    true,
	}

	// Perform initial check (best effort — the asset is still stored when
	// providers are unavailable; the refresh job retries later).
	var initialBreaches []models.Breach
	if assetType == models.BreachTypeEmail {
		result, err := m.CheckEmail(ctx, &models.BreachCheckRequest{
			Email:    value,
			DeviceID: deviceID,
		})
		if err != nil {
			m.logger.Warn().Err(err).Str("display", asset.DisplayName).Msg("initial breach check failed; asset will be checked by refresh job")
		} else {
			asset.BreachCount = result.BreachCount
			now := time.Now()
			asset.LastChecked = &now
			initialBreaches = result.Breaches
		}
	}

	if err := m.repo.UpsertAsset(ctx, asset); err != nil {
		return nil, fmt.Errorf("failed to store monitored asset: %w", err)
	}

	// Create alerts for any breaches found during the initial check.
	for i := range initialBreaches {
		breach := &initialBreaches[i]
		alert := m.createAlertForBreach(asset.ID, breach)
		if _, err := m.repo.InsertAlert(ctx, userID, alert, breach.Domain); err != nil {
			m.logger.Warn().Err(err).Str("breach", breach.Name).Msg("failed to store breach alert")
		}
	}

	// Load the persisted alerts (covers re-added assets with prior alerts).
	records, err := m.repo.ListAlertsByAsset(ctx, asset.ID)
	if err != nil {
		m.logger.Warn().Err(err).Msg("failed to load alerts for asset")
	} else {
		asset.Alerts = m.recordsToAlerts(records)
	}

	m.logger.Info().
		Str("asset_type", string(assetType)).
		Str("display", asset.DisplayName).
		Int("breach_count", asset.BreachCount).
		Msg("added monitored asset")

	return asset, nil
}

// RemoveMonitoredAsset removes an asset from monitoring. The asset must
// belong to userID; otherwise ErrAssetNotFound is returned.
func (m *DarkWebMonitor) RemoveMonitoredAsset(ctx context.Context, userID string, assetID uuid.UUID) error {
	if m.repo == nil {
		return ErrDarkWebStorageUnavailable
	}
	deleted, err := m.repo.DeleteAsset(ctx, userID, assetID)
	if err != nil {
		return fmt.Errorf("failed to remove monitored asset: %w", err)
	}
	if !deleted {
		return ErrAssetNotFound
	}

	m.logger.Info().Str("id", assetID.String()).Msg("removed monitored asset")
	return nil
}

// GetMonitoredAssets returns all monitored assets for a user, including
// their alerts.
func (m *DarkWebMonitor) GetMonitoredAssets(ctx context.Context, userID string) ([]models.MonitoredAsset, error) {
	if m.repo == nil {
		return nil, ErrDarkWebStorageUnavailable
	}
	assets, err := m.repo.ListAssetsByUser(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to list monitored assets: %w", err)
	}

	records, err := m.repo.ListAlertsByUser(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to list alerts: %w", err)
	}

	alertsByAsset := make(map[uuid.UUID][]models.BreachAlert)
	for _, rec := range records {
		alertsByAsset[rec.Alert.AssetID] = append(alertsByAsset[rec.Alert.AssetID], m.recordToAlert(rec))
	}

	for i := range assets {
		assets[i].Alerts = alertsByAsset[assets[i].ID]
	}

	return assets, nil
}

// GetMonitoringStatus returns the overall monitoring status for a user
func (m *DarkWebMonitor) GetMonitoringStatus(ctx context.Context, userID string) (*models.DarkWebMonitoringStatus, error) {
	assets, err := m.GetMonitoredAssets(ctx, userID)
	if err != nil {
		return nil, err
	}

	status := &models.DarkWebMonitoringStatus{
		IsEnabled:       len(assets) > 0,
		MonitoredAssets: len(assets),
		Assets:          assets,
	}

	// Calculate totals and risk level
	maxSeverity := models.BreachSeverityLow
	for _, asset := range assets {
		status.TotalBreaches += asset.BreachCount

		for _, alert := range asset.Alerts {
			if !alert.IsRead {
				status.UnreadAlerts++
				if models.CompareSeverity(alert.Severity, maxSeverity) > 0 {
					maxSeverity = alert.Severity
				}
			}
		}

		if asset.LastChecked != nil && (status.LastScan == nil || asset.LastChecked.After(*status.LastScan)) {
			status.LastScan = asset.LastChecked
		}
	}

	status.RiskLevel = maxSeverity

	// Calculate next scan time (every 24 hours)
	if status.LastScan != nil {
		nextScan := status.LastScan.Add(24 * time.Hour)
		status.NextScan = &nextScan
	}

	return status, nil
}

// GetAlerts returns all alerts for a user
func (m *DarkWebMonitor) GetAlerts(ctx context.Context, userID string) ([]models.BreachAlert, error) {
	if m.repo == nil {
		return nil, ErrDarkWebStorageUnavailable
	}
	records, err := m.repo.ListAlertsByUser(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to list alerts: %w", err)
	}

	return m.recordsToAlerts(records), nil
}

// AcknowledgeAlert marks an alert as read. The alert must belong to userID;
// otherwise ErrAlertNotFound is returned.
func (m *DarkWebMonitor) AcknowledgeAlert(ctx context.Context, userID string, alertID uuid.UUID) error {
	if m.repo == nil {
		return ErrDarkWebStorageUnavailable
	}
	updated, err := m.repo.AcknowledgeAlert(ctx, userID, alertID)
	if err != nil {
		return fmt.Errorf("failed to acknowledge alert: %w", err)
	}
	if !updated {
		return ErrAlertNotFound
	}

	m.logger.Info().Str("alert_id", alertID.String()).Msg("alert acknowledged")
	return nil
}

// GetStats returns dark web monitoring statistics computed from persisted
// check events, assets and alerts.
func (m *DarkWebMonitor) GetStats(ctx context.Context) (*models.DarkWebStats, error) {
	if m.repo == nil {
		return nil, ErrDarkWebStorageUnavailable
	}
	checkStats, err := m.repo.GetCheckStats(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to load check statistics: %w", err)
	}

	byAssetType, err := m.repo.CountAssetsByType(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to count assets by type: %w", err)
	}

	bySeverity, err := m.repo.CountAlertsBySeverity(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to count alerts by severity: %w", err)
	}

	stats := &models.DarkWebStats{
		TotalChecks:      checkStats.TotalChecks,
		BreachesFound:    checkStats.BreachesFound,
		PasswordsChecked: checkStats.PasswordsChecked,
		CompromisedCount: checkStats.CompromisedCount,
		ByAssetType:      byAssetType,
		BySeverity:       bySeverity,
	}
	stats.Last24Hours.Checks = checkStats.Checks24h
	stats.Last24Hours.Breaches = checkStats.Breaches24h

	return stats, nil
}

// GetAllBreaches returns the public breach catalog (HIBP), cached for 24
// hours since the catalog changes rarely.
func (m *DarkWebMonitor) GetAllBreaches(ctx context.Context) ([]models.Breach, error) {
	var cached []models.Breach
	if err := m.cache.GetJSON(ctx, breachCatalogCacheKey, &cached); err == nil && len(cached) > 0 {
		return cached, nil
	}

	breaches, err := m.hibpClient.GetAllBreaches(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch breach catalog: %w", err)
	}

	if err := m.cache.SetJSON(ctx, breachCatalogCacheKey, breaches, breachCatalogTTL); err != nil {
		m.logger.Warn().Err(err).Msg("failed to cache breach catalog")
	}

	return breaches, nil
}

// GetBreachByName returns details for a single breach by its HIBP name,
// cached for 24 hours. Returns ErrBreachNotFound when no such breach exists.
func (m *DarkWebMonitor) GetBreachByName(ctx context.Context, name string) (*models.Breach, error) {
	cacheKey := "darkweb:breach:" + strings.ToLower(name)
	var cached models.Breach
	if err := m.cache.GetJSON(ctx, cacheKey, &cached); err == nil && cached.Name != "" {
		return &cached, nil
	}

	breach, err := m.hibpClient.GetBreachByName(ctx, name)
	if err != nil {
		return nil, err
	}

	if err := m.cache.SetJSON(ctx, cacheKey, breach, breachCatalogTTL); err != nil {
		m.logger.Warn().Err(err).Msg("failed to cache breach details")
	}

	return breach, nil
}

// RefreshMonitoredAssets re-checks all active monitored assets for new
// breaches and stores new alerts. Alert creation is idempotent per
// (asset, breach name).
func (m *DarkWebMonitor) RefreshMonitoredAssets(ctx context.Context) error {
	if m.repo == nil {
		return ErrDarkWebStorageUnavailable
	}
	assets, err := m.repo.ListActiveAssets(ctx)
	if err != nil {
		return fmt.Errorf("failed to list active assets: %w", err)
	}

	for i := range assets {
		asset := &assets[i]
		if asset.AssetType != models.BreachTypeEmail {
			continue
		}

		// Query providers directly (bypassing the cache) so refresh always
		// sees fresh data, then update the cache for subsequent reads.
		result, err := m.checkEmailProviders(ctx, asset.AssetValue)
		if err != nil {
			m.logger.Warn().Err(err).Str("asset_id", asset.ID.String()).Msg("failed to refresh asset")
			continue
		}
		_ = m.cache.SetJSON(ctx, m.getCacheKey("email", asset.AssetValue), result, emailCheckCacheTTL)

		for j := range result.Breaches {
			breach := &result.Breaches[j]
			alert := m.createAlertForBreach(asset.ID, breach)
			inserted, err := m.repo.InsertAlert(ctx, asset.UserID, alert, breach.Domain)
			if err != nil {
				m.logger.Warn().Err(err).Str("breach", breach.Name).Msg("failed to store breach alert")
				continue
			}
			if inserted {
				m.logger.Warn().
					Str("asset_id", asset.ID.String()).
					Str("breach", breach.Name).
					Msg("new breach detected for monitored asset")
			}
		}

		now := time.Now()
		if err := m.repo.UpdateAssetCheckResult(ctx, asset.ID, result.BreachCount, now); err != nil {
			m.logger.Warn().Err(err).Str("asset_id", asset.ID.String()).Msg("failed to update asset check result")
		}
	}

	return nil
}

// Helper functions

// recordToAlert converts a persisted alert record back to the API model,
// regenerating the recommended actions from the stored data classes.
func (m *DarkWebMonitor) recordToAlert(rec repository.AlertRecord) models.BreachAlert {
	alert := rec.Alert
	alert.Actions = m.getActionsForDataClasses(alert.DataExposed, rec.BreachDomain)
	return alert
}

func (m *DarkWebMonitor) recordsToAlerts(records []repository.AlertRecord) []models.BreachAlert {
	alerts := make([]models.BreachAlert, len(records))
	for i, rec := range records {
		alerts[i] = m.recordToAlert(rec)
	}
	return alerts
}

func (m *DarkWebMonitor) getCacheKey(keyType, value string) string {
	hash := sha256.Sum256([]byte(value))
	return "darkweb:" + keyType + ":" + hex.EncodeToString(hash[:8])
}

func (m *DarkWebMonitor) maskValue(assetType models.BreachType, value string) string {
	switch assetType {
	case models.BreachTypeEmail:
		return maskEmail(value)
	case models.BreachTypePhone:
		if len(value) > 4 {
			return "***" + value[len(value)-4:]
		}
		return "***"
	case models.BreachTypeCreditCard:
		if len(value) > 4 {
			return "****-****-****-" + value[len(value)-4:]
		}
		return "****"
	default:
		if len(value) > 4 {
			return value[:2] + "***" + value[len(value)-2:]
		}
		return "***"
	}
}

func (m *DarkWebMonitor) createAlertForBreach(assetID uuid.UUID, breach *models.Breach) *models.BreachAlert {
	return &models.BreachAlert{
		ID:          uuid.New(),
		AssetID:     assetID,
		BreachID:    breach.ID,
		BreachName:  breach.Name,
		Severity:    breach.Severity,
		DataExposed: breach.DataClasses,
		DetectedAt:  time.Now(),
		IsRead:      false,
		Actions:     m.getActionsForDataClasses(breach.DataClasses, breach.Domain),
	}
}

// getActionsForDataClasses builds the recommended actions for an alert from
// the exposed data classes and the breached site's domain.
func (m *DarkWebMonitor) getActionsForDataClasses(dataClasses []string, domain string) []models.AlertAction {
	actions := []models.AlertAction{
		{
			ID:     "view_details",
			Label:  "View Details",
			Action: "view_details",
		},
	}

	// Add specific actions based on data classes (deduplicated)
	added := make(map[string]bool)
	for _, dataClass := range dataClasses {
		switch dataClass {
		case "Passwords":
			if !added["change_password"] {
				added["change_password"] = true
				actions = append(actions, models.AlertAction{
					ID:     "change_password",
					Label:  "Change Password",
					Action: "change_password",
					URL:    domain,
				})
			}
		case "Credit cards", "Bank account numbers":
			if !added["contact_bank"] {
				added["contact_bank"] = true
				actions = append(actions, models.AlertAction{
					ID:     "contact_bank",
					Label:  "Contact Your Bank",
					Action: "contact_bank",
				})
			}
		}
	}

	// Always add enable 2FA action
	actions = append(actions, models.AlertAction{
		ID:     "enable_2fa",
		Label:  "Enable 2FA",
		Action: "enable_2fa",
	})

	// Add dismiss action
	actions = append(actions, models.AlertAction{
		ID:     "dismiss",
		Label:  "Dismiss",
		Action: "dismiss",
	})

	return actions
}
