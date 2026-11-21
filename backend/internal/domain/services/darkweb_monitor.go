package services

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"sync/atomic"
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
	// ErrBreachProvidersFailed means a check could not be completed. It holds
	// no provider error text, which can contain the address that was checked.
	ErrBreachProvidersFailed = errors.New("breach providers failed")
	// ErrDarkWebStorageUnavailable is returned when the service is running
	// without a database and a persistence-backed operation is requested.
	ErrDarkWebStorageUnavailable = errors.New("dark web monitoring storage unavailable: database not connected")
	// ErrRefreshInProgress is returned, without starting a sweep, while another
	// refresh is running in this process or on another replica.
	ErrRefreshInProgress = errors.New("dark web refresh already running")
)

const (
	breachCatalogCacheKey = "darkweb:breaches:catalog"
	breachCatalogTTL      = 24 * time.Hour
	emailCheckCacheTTL    = 1 * time.Hour

	refreshLockKey = "darkweb:refresh"
	// sweepMaxConsecutiveFailures stops a refresh during a provider outage.
	sweepMaxConsecutiveFailures = 3
	// refreshLockTTL only matters if a replica dies mid-sweep. It is well above
	// the longest sweep: the router's 60s request timeout cancels the sweep's
	// context, and the sweep stops at the next asset.
	refreshLockTTL = 10 * time.Minute
)

// refreshLocker is the cross-replica lock a sweep holds (*cache.RedisCache).
type refreshLocker interface {
	AcquireOwnedLock(ctx context.Context, lockKey string, ttl time.Duration) (string, bool, error)
	ReleaseOwnedLock(ctx context.Context, lockKey, owner string) (bool, error)
}

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

	refreshing  atomic.Bool
	refreshLock refreshLocker
	sweep       func(context.Context) error

	paidLookups       paidLookupStore
	paidLookupsPerDay int64
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
	m := &DarkWebMonitor{
		hibpClient: hibpClient,
		leakCheck:  leakCheck,
		intelX:     intelX,
		repo:       repo,
		cache:      redisCache,
		logger:     log.WithComponent("darkweb-monitor"),

		paidLookupsPerDay: paidLookupsPerDay(),
	}
	m.sweep = m.sweepMonitoredAssets
	if redisCache != nil {
		m.refreshLock = redisCache
		m.paidLookups = redisCache
	}
	return m
}

// CheckEmail checks if an email has been breached, aggregating all configured
// breach providers. Results are cached for one hour. A cache miss spends paid
// provider quota and is refused with ErrPaidLookupLimited or
// ErrPaidLookupUnavailable when the caller's budget does not allow it.
func (m *DarkWebMonitor) CheckEmail(ctx context.Context, req *models.BreachCheckRequest) (*models.BreachCheckResponse, error) {
	return m.paidEmailLookup(ctx, req.Email, false)
}

// cachedEmailResult returns the cached result for email, if any.
func (m *DarkWebMonitor) cachedEmailResult(ctx context.Context, email string) *models.BreachCheckResponse {
	if m.cache == nil {
		return nil
	}
	var cached models.BreachCheckResponse
	if err := m.cache.GetJSON(ctx, m.getCacheKey("email", email), &cached); err != nil {
		return nil
	}
	cached.Email = email
	return &cached
}

// cacheEmailResult stores a result without the address it belongs to.
func (m *DarkWebMonitor) cacheEmailResult(ctx context.Context, email string, result *models.BreachCheckResponse) {
	if m.cache != nil {
		_ = m.cache.SetJSON(ctx, m.getCacheKey("email", email), breachResultWithoutEmail(result), emailCheckCacheTTL)
	}
}

// paidEmailLookup answers from this caller's recent answer, then the cache,
// then the providers. With chargeCacheHit a cache hit also takes one unit.
func (m *DarkWebMonitor) paidEmailLookup(ctx context.Context, email string, chargeCacheHit bool) (*models.BreachCheckResponse, error) {
	if result, found, err := m.recallPaidLookup(ctx, email); found {
		return result, err
	}

	cached := m.cachedEmailResult(ctx, email)
	if cached != nil && !chargeCacheHit {
		return cached, nil
	}

	reservation, err := m.reservePaidLookup(ctx)
	if err != nil {
		return nil, err
	}
	if cached != nil {
		m.rememberPaidLookup(ctx, email, cached)
		return cached, nil
	}

	result, err := m.checkEmailProviders(ctx, email)
	if err != nil {
		m.refundPaidLookup(ctx, reservation)
		// A request the client abandoned says nothing about the providers.
		if errors.Is(err, ErrBreachProvidersFailed) && ctx.Err() == nil {
			m.rememberPaidLookup(ctx, email, nil)
		}
		return nil, err
	}

	// Record real check statistics (best effort; skipped without a database)
	if m.repo != nil {
		if err := m.repo.RecordCheck(ctx, "email_check", result.IsBreached, result.BreachCount); err != nil {
			m.logger.Warn().Err(err).Msg("failed to record email check event")
		}
	}

	m.cacheEmailResult(ctx, email, result)
	m.rememberPaidLookup(ctx, email, result)
	return result, nil
}

// checkEmailProviders queries every configured breach provider and merges the
// results (deduplicated by breach name). Each provider fails independently:
// a failure is logged and the remaining providers are still consulted.
// Breaches a working provider found are returned even if another failed, but
// "no breaches" is only returned when every configured provider answered.
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
	failed := 0

	for _, pr := range results {
		if pr.err != nil {
			failed++
			// The error text can hold the request URL, and with it the address.
			m.logger.Warn().Str("provider", pr.name).Str("reason", breachProviderFailureReason(pr.err)).
				Msg("breach provider lookup failed, continuing with remaining providers")
			continue
		}
		for _, breach := range pr.breaches {
			key := strings.ToLower(strings.TrimSpace(breach.Name))
			if key == "" || seen[key] {
				continue
			}
			seen[key] = true
			merged = append(merged, breach)
		}
	}

	if failed > 0 && len(merged) == 0 {
		return nil, ErrBreachProvidersFailed
	}

	return buildBreachCheckResponse(email, merged), nil
}

// breachProviderFailureReason names a failure without any of its text.
func breachProviderFailureReason(err error) string {
	var urlErr *url.Error
	switch {
	case errors.Is(err, context.Canceled):
		return "canceled"
	case errors.Is(err, context.DeadlineExceeded):
		return "timeout"
	case errors.As(err, &urlErr):
		if urlErr.Timeout() {
			return "timeout"
		}
		return "transport"
	default:
		return "upstream"
	}
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

// PasswordRange returns every known hash suffix for a five character SHA-1
// prefix, for the client to compare on its own device. The prefix is neither
// logged nor stored.
func (m *DarkWebMonitor) PasswordRange(ctx context.Context, prefix string) ([]models.PasswordRangeEntry, error) {
	if m.hibpClient == nil {
		return nil, ErrPasswordRangeUnavailable
	}
	return m.hibpClient.PasswordRange(ctx, prefix)
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

	// Check before storing. Every registration of an email takes one unit of
	// the budget, even on a cache hit, because each stored row is looked up
	// again by every refresh sweep. An email that could not be checked is not
	// stored: clients show a stored asset with no breaches as safe.
	var initialBreaches []models.Breach
	if assetType == models.BreachTypeEmail {
		result, err := m.paidEmailLookup(ctx, value, true)
		if err != nil {
			m.logger.Warn().Err(err).Str("display", asset.DisplayName).Msg("initial breach check failed; asset not stored")
			return nil, fmt.Errorf("initial breach check failed: %w", err)
		}
		asset.BreachCount = result.BreachCount
		now := time.Now()
		asset.LastChecked = &now
		initialBreaches = result.Breaches
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

// RefreshMonitoredAssets runs one sweep of all monitored assets. Each sweep
// spends paid provider quota, so at most one runs at a time: a call made while
// another is running returns ErrRefreshInProgress without starting a sweep.
func (m *DarkWebMonitor) RefreshMonitoredAssets(ctx context.Context) error {
	if !m.refreshing.CompareAndSwap(false, true) {
		return ErrRefreshInProgress
	}
	defer m.refreshing.Store(false)

	if m.refreshLock != nil {
		owner, acquired, err := m.refreshLock.AcquireOwnedLock(ctx, refreshLockKey, refreshLockTTL)
		if err != nil {
			return fmt.Errorf("failed to take the refresh lock: %w", err)
		}
		if !acquired {
			return ErrRefreshInProgress
		}
		defer func() {
			// Not ctx: the request may already have timed out, and a lock left
			// behind would refuse every refresh until its TTL.
			releaseCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			released, err := m.refreshLock.ReleaseOwnedLock(releaseCtx, refreshLockKey, owner)
			if err != nil {
				m.logger.Warn().Err(err).Msg("failed to release the refresh lock")
			} else if !released {
				m.logger.Warn().Msg("refresh lock expired during the sweep; left any newer holder's lock in place")
			}
		}()
	}

	return m.sweep(ctx)
}

// sweepMonitoredAssets re-checks all active monitored assets for new
// breaches and stores new alerts. Alert creation is idempotent per
// (asset, breach name).
func (m *DarkWebMonitor) sweepMonitoredAssets(ctx context.Context) error {
	if m.repo == nil {
		return ErrDarkWebStorageUnavailable
	}
	assets, err := m.repo.ListActiveAssets(ctx)
	if err != nil {
		return fmt.Errorf("failed to list active assets: %w", err)
	}

	ctx = WithPaidLookupCaller(ctx, PaidLookupCaller{Tier: PaidLookupSweep, Identity: paidLookupSweepIdentity})
	return m.sweepAssets(ctx, assets, m.storeSweepResult)
}

// sweepAssets re-checks each email from the shared daily budget. It stops when
// the budget refuses or the providers keep failing, leaving the remaining
// assets as they were.
func (m *DarkWebMonitor) sweepAssets(ctx context.Context, assets []models.MonitoredAsset, store func(context.Context, *models.MonitoredAsset, *models.BreachCheckResponse)) error {
	consecutiveFailures := 0
	for i := range assets {
		if err := ctx.Err(); err != nil {
			return fmt.Errorf("refresh stopped: %w", err)
		}
		asset := &assets[i]
		if asset.AssetType != models.BreachTypeEmail {
			continue
		}

		reservation, err := m.reservePaidLookup(ctx)
		if err != nil {
			return fmt.Errorf("refresh stopped: %w", err)
		}

		// Query providers directly (bypassing the cache) so refresh always
		// sees fresh data, then update the cache for subsequent reads.
		result, err := m.checkEmailProviders(ctx, asset.AssetValue)
		if err != nil {
			m.refundPaidLookup(ctx, reservation)
			m.logger.Warn().Err(err).Str("asset_id", asset.ID.String()).Msg("failed to refresh asset")
			if consecutiveFailures++; consecutiveFailures >= sweepMaxConsecutiveFailures {
				return fmt.Errorf("refresh stopped: %w", err)
			}
			continue
		}
		consecutiveFailures = 0
		m.cacheEmailResult(ctx, asset.AssetValue, result)
		store(ctx, asset, result)
	}

	return nil
}

// storeSweepResult records the alerts and check result of one refreshed asset.
func (m *DarkWebMonitor) storeSweepResult(ctx context.Context, asset *models.MonitoredAsset, result *models.BreachCheckResponse) {
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
