package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// StatsHandler handles statistics endpoints
type StatsHandler struct {
	repos  *repository.Repositories
	cache  *cache.RedisCache
	logger *logger.Logger

	// netRepo reads per-device protection state (DNS/VPN configs, audits,
	// anti-theft settings, SMS/app analysis activity).
	netRepo *repository.NetworkSecurityRepository

	// reports counts user-submitted community threat reports; shares the
	// indicator repository's pool (as IntelligenceHandler does).
	reports *repository.ThreatReportRepository
}

// NewStatsHandler creates a new StatsHandler
func NewStatsHandler(repos *repository.Repositories, c *cache.RedisCache, log *logger.Logger) *StatsHandler {
	h := &StatsHandler{
		repos:   repos,
		cache:   c,
		logger:  log.WithComponent("stats"),
		netRepo: repository.NewNetworkSecurityRepositoryFromRepos(repos),
	}
	if repos != nil && repos.Indicators != nil {
		if pool := repos.Indicators.Pool(); pool != nil {
			h.reports = repository.NewThreatReportRepository(pool)
		}
	}
	return h
}

// Get handles GET /api/v1/stats
func (h *StatsHandler) Get(w http.ResponseWriter, r *http.Request) {
	// Try to get from cache first
	var stats models.Stats
	err := h.cache.GetJSON(r.Context(), cache.KeyStats, &stats)
	if err != nil {
		// Cache miss - compute stats
		stats = h.computeStats()

		// Cache for 5 minutes
		_ = h.cache.SetJSON(r.Context(), cache.KeyStats, stats, 5*time.Minute)
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "public, max-age=300") // 5 min cache
	json.NewEncoder(w).Encode(stats)
}

// computeStats computes statistics from database
func (h *StatsHandler) computeStats() models.Stats {
	ctx := context.Background()
	version, _ := h.cache.GetSyncVersion(ctx)

	stats := models.Stats{
		TotalIndicators: 0,
		IndicatorsByType: map[string]int{
			"domain":  0,
			"ip":      0,
			"hash":    0,
			"url":     0,
			"process": 0,
			"package": 0,
		},
		IndicatorsBySeverity: map[string]int{
			"critical": 0,
			"high":     0,
			"medium":   0,
			"low":      0,
			"info":     0,
		},
		IndicatorsByPlatform: map[string]int{
			"android": 0,
			"ios":     0,
			"windows": 0,
			"macos":   0,
			"linux":   0,
		},
		TotalSources:       0,
		ActiveSources:      0,
		TotalCampaigns:     0,
		ActiveCampaigns:    0,
		TotalReports:       0,
		PendingReports:     0,
		PegasusIndicators:  0,
		MobileIndicators:   0,
		CriticalIndicators: 0,
		LastUpdate:         time.Now(),
		TodayNewIOCs:       0,
		WeeklyNewIOCs:      0,
		MonthlyNewIOCs:     0,
		DataVersion:        version,
	}

	// Fetch real stats from database
	if h.repos != nil {
		ctx := context.Background()
		if dbStats, err := h.repos.Indicators.GetStats(ctx); err == nil {
			stats.TotalIndicators = int(dbStats.TotalCount)
			for k, v := range dbStats.ByType {
				stats.IndicatorsByType[k] = int(v)
			}
			for k, v := range dbStats.BySeverity {
				stats.IndicatorsBySeverity[k] = int(v)
			}
			stats.PegasusIndicators = int(dbStats.PegasusCount)
			stats.MobileIndicators = int(dbStats.MobileCount)
			stats.CriticalIndicators = int(dbStats.CriticalCount)
			stats.TodayNewIOCs = int(dbStats.TodayNew)
			stats.WeeklyNewIOCs = int(dbStats.WeeklyNew)
			stats.MonthlyNewIOCs = int(dbStats.MonthlyNew)
		} else {
			h.logger.Warn().Err(err).Msg("failed to fetch indicator stats")
		}

		// Fetch source stats
		if sources, err := h.repos.Sources.ListActive(ctx); err == nil {
			stats.ActiveSources = len(sources)
		}
		if allSources, err := h.repos.Sources.List(ctx); err == nil {
			stats.TotalSources = len(allSources)
		}

		// Fetch campaign stats
		if campaigns, _, err := h.repos.Campaigns.List(ctx, true, 1000, 0); err == nil {
			stats.ActiveCampaigns = len(campaigns)
		}
		if _, total, err := h.repos.Campaigns.List(ctx, false, 1, 0); err == nil {
			stats.TotalCampaigns = int(total)
		}

		// Fetch community threat-report counts
		if h.reports != nil {
			if total, err := h.reports.CountAll(ctx); err == nil {
				stats.TotalReports = int(total)
			} else {
				h.logger.Warn().Err(err).Msg("failed to count threat reports")
			}
			if pending, err := h.reports.CountByStatus(ctx, "pending"); err == nil {
				stats.PendingReports = int(pending)
			}
		}
	}

	return stats
}

// GetProtection handles GET /api/v1/stats/protection
func featureState(enabled bool) string {
	if enabled {
		return "protected"
	}
	return "disabled"
}

func calculateGrade(score float64) string {
	switch {
	case score >= 90:
		return "A"
	case score >= 75:
		return "B"
	case score >= 60:
		return "C"
	case score >= 40:
		return "D"
	default:
		return "F"
	}
}

// GetProtection handles GET /api/v1/stats/protection. The protection status
// is computed from the authenticated device's real persisted state — never
// from hardcoded feature flags.
func (h *StatsHandler) GetProtection(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	deviceID := middleware.GetDeviceID(ctx)
	if deviceID == "" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "device identity required for protection status"})
		return
	}

	if h.repos == nil || h.netRepo == nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"error": "protection status unavailable: database not configured"})
		return
	}

	var status models.ProtectionStatus
	cacheKey := cache.KeyProtectionStats + ":device:" + deviceID

	// Try cache (per device)
	err := h.cache.GetJSON(ctx, cacheKey, &status)
	if err != nil {
		status, err = h.computeProtectionStatus(ctx, deviceID)
		if err != nil {
			h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to compute protection status")
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusInternalServerError)
			json.NewEncoder(w).Encode(map[string]string{"error": "failed to compute protection status"})
			return
		}

		// Short cache (1 minute)
		_ = h.cache.SetJSON(ctx, cacheKey, status, 1*time.Minute)
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "private, max-age=60")
	json.NewEncoder(w).Encode(status)
}

// computeProtectionStatus derives the protection status from the device's
// persisted state: the device registry row, per-device DNS/VPN configuration,
// anti-theft settings, and recent SMS/app/network analysis activity.
func (h *StatsHandler) computeProtectionStatus(ctx context.Context, deviceID string) (models.ProtectionStatus, error) {
	// Resolve the device row; tokens carry the devices.id, with hardware ID
	// as a fallback for older registrations.
	device, err := h.repos.Devices.FindByID(ctx, deviceID)
	if err != nil {
		device, err = h.repos.Devices.FindByHardwareID(ctx, deviceID)
	}
	if err != nil || device == nil || device.Revoked || device.Status != "active" {
		// Unknown or revoked device: nothing is protected.
		if err != nil {
			h.logger.Warn().Err(err).Str("device_id", deviceID).Msg("device not found for protection status")
		}
		off := models.FeatureStatus{Enabled: false, Status: featureState(false)}
		return models.ProtectionStatus{
			IsActive: false,
			Score:    0,
			Grade:    calculateGrade(0),
			Features: models.FeatureSet{SMS: off, Web: off, App: off, Network: off, VPN: off, AntiTheft: off},
			LastScan: time.Now(),
		}, nil
	}

	state, err := h.netRepo.GetDeviceProtectionState(ctx, deviceID)
	if err != nil {
		return models.ProtectionStatus{}, err
	}

	smsEnabled := state.SMSActive
	webEnabled := state.DNSConfigured
	appEnabled := state.AppScanActive
	networkEnabled := state.NetworkAuditRecent
	vpnEnabled := state.VPNConfigured
	antiTheftEnabled := state.AntiTheftEnabled

	// Score from actually-enabled modules (6 modules, equal weight).
	enabled := 0
	for _, on := range []bool{smsEnabled, webEnabled, appEnabled, networkEnabled, vpnEnabled, antiTheftEnabled} {
		if on {
			enabled++
		}
	}
	score := float64(enabled) / 6.0 * 100.0

	return models.ProtectionStatus{
		IsActive: score >= 60,
		Score:    score,
		Grade:    calculateGrade(score),
		Features: models.FeatureSet{
			SMS:       models.FeatureStatus{Enabled: smsEnabled, Status: featureState(smsEnabled)},
			Web:       models.FeatureStatus{Enabled: webEnabled, Status: featureState(webEnabled)},
			App:       models.FeatureStatus{Enabled: appEnabled, Status: featureState(appEnabled)},
			Network:   models.FeatureStatus{Enabled: networkEnabled, Status: featureState(networkEnabled)},
			VPN:       models.FeatureStatus{Enabled: vpnEnabled, Status: featureState(vpnEnabled)},
			AntiTheft: models.FeatureStatus{Enabled: antiTheftEnabled, Status: featureState(antiTheftEnabled)},
		},
		LastScan: time.Now(),
	}, nil
}
