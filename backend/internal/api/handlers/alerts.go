package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// AlertsHandler handles alert endpoints
type AlertsHandler struct {
	repos  *repository.Repositories
	cache  *cache.RedisCache
	logger *logger.Logger

	// netRepo reads per-device protection state. It mirrors the repository
	// used by StatsHandler.GetProtection so the dashboard's protection
	// section is computed from exactly the same source data.
	netRepo *repository.NetworkSecurityRepository
}

// NewAlertsHandler creates a new AlertsHandler
func NewAlertsHandler(repos *repository.Repositories, c *cache.RedisCache, log *logger.Logger) *AlertsHandler {
	return &AlertsHandler{
		repos:   repos,
		cache:   c,
		logger:  log.WithComponent("alerts-handler"),
		netRepo: repository.NewNetworkSecurityRepositoryFromRepos(repos),
	}
}

// alertItem represents a security alert
type alertItem struct {
	ID          string                 `json:"id"`
	Title       string                 `json:"title"`
	Description string                 `json:"description"`
	Severity    string                 `json:"severity"`
	Category    string                 `json:"category"`
	Source      string                 `json:"source"`
	IsRead      bool                   `json:"is_read"`
	CreatedAt   time.Time              `json:"created_at"`
	ReadAt      *time.Time             `json:"read_at,omitempty"`
	Metadata    map[string]interface{} `json:"metadata,omitempty"`
}

// loadAlerts reads the live alerts list from the cache, overlays the
// per-alert read marks written by MarkRead, and returns the alerts sorted
// newest-first. Returns an empty (non-nil) slice when no alerts exist.
func (h *AlertsHandler) loadAlerts(ctx context.Context) []alertItem {
	var alerts []alertItem
	_ = h.cache.GetJSON(ctx, "alerts:list", &alerts)
	if alerts == nil {
		alerts = []alertItem{}
	}

	// Overlay read marks (MarkRead stores them under alerts:read:<id>).
	for i := range alerts {
		if alerts[i].IsRead {
			continue
		}
		var mark map[string]interface{}
		if err := h.cache.GetJSON(ctx, "alerts:read:"+alerts[i].ID, &mark); err == nil && mark != nil {
			alerts[i].IsRead = true
			if ts, ok := mark["read_at"].(string); ok {
				if t, terr := time.Parse(time.RFC3339, ts); terr == nil {
					alerts[i].ReadAt = &t
				}
			}
		}
	}

	sort.SliceStable(alerts, func(a, b int) bool {
		return alerts[a].CreatedAt.After(alerts[b].CreatedAt)
	})
	return alerts
}

// List handles GET /api/v1/alerts
func (h *AlertsHandler) List(w http.ResponseWriter, r *http.Request) {
	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	if page < 1 {
		page = 1
	}
	pageSize, _ := strconv.Atoi(r.URL.Query().Get("page_size"))
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	severity := r.URL.Query().Get("severity")
	unreadOnly := r.URL.Query().Get("unread") == "true"

	alerts := h.loadAlerts(r.Context())

	// Filter
	var filtered []alertItem
	for _, a := range alerts {
		if severity != "" && a.Severity != severity {
			continue
		}
		if unreadOnly && a.IsRead {
			continue
		}
		filtered = append(filtered, a)
	}
	if filtered == nil {
		filtered = []alertItem{}
	}

	unread := 0
	for _, a := range alerts {
		if !a.IsRead {
			unread++
		}
	}

	total := len(filtered)
	start := (page - 1) * pageSize
	end := start + pageSize
	if start > total {
		start = total
	}
	if end > total {
		end = total
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"alerts":    filtered[start:end],
		"total":     total,
		"unread":    unread,
		"page":      page,
		"page_size": pageSize,
	})
}

// MarkRead handles POST /api/v1/alerts/{id}/read
func (h *AlertsHandler) MarkRead(w http.ResponseWriter, r *http.Request) {
	alertID := chi.URLParam(r, "id")
	if alertID == "" {
		http.Error(w, `{"error":"alert ID is required"}`, http.StatusBadRequest)
		return
	}

	_ = h.cache.SetJSON(r.Context(), "alerts:read:"+alertID, map[string]interface{}{
		"read_at": time.Now().UTC().Format(time.RFC3339),
	}, 30*24*time.Hour)

	h.logger.Info().Str("alert_id", alertID).Msg("alert marked as read")

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"id":      alertID,
		"is_read": true,
		"read_at": time.Now().UTC().Format(time.RFC3339),
	})
}

// Clear handles DELETE /api/v1/alerts
func (h *AlertsHandler) Clear(w http.ResponseWriter, r *http.Request) {
	_ = h.cache.Delete(r.Context(), "alerts:list")
	h.logger.Info().Msg("all alerts cleared")

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message":    "All alerts cleared",
		"cleared_at": time.Now().UTC().Format(time.RFC3339),
	})
}

// resolveBearerDeviceID resolves the device identity for routes that are not
// behind the auth middleware. It accepts the same credentials APIKeyAuth
// does (session tokens and device API keys, stored in Redis by the auth
// handler) and returns the device ID, or "" when no valid device credential
// is presented.
func (h *AlertsHandler) resolveBearerDeviceID(r *http.Request) string {
	authHeader := r.Header.Get("Authorization")
	if authHeader == "" {
		return ""
	}
	parts := strings.SplitN(authHeader, " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "bearer") || parts[1] == "" {
		return ""
	}
	token := parts[1]

	for _, key := range []string{"auth:token:" + token, "auth:apikey:" + token} {
		var claims middleware.TokenClaims
		if err := h.cache.GetJSON(r.Context(), key, &claims); err != nil {
			continue
		}
		if !claims.ExpiresAt.IsZero() && time.Now().After(claims.ExpiresAt) {
			continue
		}
		if claims.DeviceID != "" {
			return claims.DeviceID
		}
	}
	return ""
}

// resolveDevice loads the device row for an authenticated device ID,
// matching the resolution order used by StatsHandler (devices.id first,
// hardware ID as fallback). Returns nil when the device cannot be resolved.
func (h *AlertsHandler) resolveDevice(ctx context.Context, deviceID string) *repository.Device {
	if h.repos == nil || h.repos.Devices == nil {
		return nil
	}
	device, err := h.repos.Devices.FindByID(ctx, deviceID)
	if err != nil {
		device, err = h.repos.Devices.FindByHardwareID(ctx, deviceID)
	}
	if err != nil {
		h.logger.Warn().Err(err).Str("device_id", deviceID).Msg("device not found for dashboard")
		return nil
	}
	return device
}

// deviceProtection computes the per-device protection status using exactly
// the same source data and scoring as StatsHandler.GetProtection, sharing
// its per-device cache key so both endpoints always agree.
func (h *AlertsHandler) deviceProtection(ctx context.Context, deviceID string, device *repository.Device) (*models.ProtectionStatus, error) {
	cacheKey := cache.KeyProtectionStats + ":device:" + deviceID

	var status models.ProtectionStatus
	if err := h.cache.GetJSON(ctx, cacheKey, &status); err == nil {
		return &status, nil
	}

	if device == nil || device.Revoked || device.Status != "active" {
		// Unknown or revoked device: nothing is protected.
		off := models.FeatureStatus{Enabled: false, Status: featureState(false)}
		return &models.ProtectionStatus{
			IsActive: false,
			Score:    0,
			Grade:    calculateGrade(0),
			Features: models.FeatureSet{SMS: off, Web: off, App: off, Network: off, VPN: off, AntiTheft: off},
			LastScan: time.Now(),
		}, nil
	}

	state, err := h.netRepo.GetDeviceProtectionState(ctx, deviceID)
	if err != nil {
		return nil, err
	}

	smsEnabled := state.SMSActive
	webEnabled := state.DNSConfigured
	appEnabled := state.AppScanActive
	networkEnabled := state.NetworkAuditRecent
	vpnEnabled := state.VPNConfigured
	antiTheftEnabled := state.AntiTheftEnabled

	// Score from actually-enabled modules (6 modules, equal weight) —
	// identical to StatsHandler.computeProtectionStatus.
	enabled := 0
	for _, on := range []bool{smsEnabled, webEnabled, appEnabled, networkEnabled, vpnEnabled, antiTheftEnabled} {
		if on {
			enabled++
		}
	}
	score := float64(enabled) / 6.0 * 100.0

	status = models.ProtectionStatus{
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
	}
	_ = h.cache.SetJSON(ctx, cacheKey, status, 1*time.Minute)
	return &status, nil
}

// isSecurityPatchCurrent reports whether a device-reported security patch
// level (YYYY-MM-DD or YYYY-MM) is recent enough (within 180 days).
func isSecurityPatchCurrent(patch string) bool {
	patch = strings.TrimSpace(patch)
	if patch == "" {
		return false
	}
	var t time.Time
	var err error
	for _, layout := range []string{"2006-01-02", "2006-01"} {
		t, err = time.Parse(layout, patch)
		if err == nil {
			break
		}
	}
	if err != nil {
		return false
	}
	return time.Since(t) <= 180*24*time.Hour
}

// deviceHealth builds the device-health section from the device's real
// security registration (anti-theft / device-security enrollment). Returns
// nil when the device has no security registration — the section is then
// omitted from the dashboard instead of being fabricated.
func (h *AlertsHandler) deviceHealth(ctx context.Context, deviceID string, device *repository.Device) map[string]interface{} {
	if h.repos == nil || h.repos.DeviceSecurity == nil {
		return nil
	}

	sec, err := h.repos.DeviceSecurity.GetDevice(ctx, deviceID)
	if err != nil && device != nil && device.HardwareID != "" && device.HardwareID != deviceID {
		sec, err = h.repos.DeviceSecurity.GetDevice(ctx, device.HardwareID)
	}
	if err != nil || sec == nil {
		return nil
	}

	patchCurrent := isSecurityPatchCurrent(sec.SecurityPatch)

	checks := []struct {
		ok             bool
		issue          string
		recommendation string
	}{
		{!sec.IsRooted, "Device is rooted", "Rooted devices bypass platform security; consider unrooting or using a separate device for sensitive activity"},
		{sec.IsEncrypted, "Device storage is not encrypted", "Enable full-device encryption in system settings"},
		{sec.HasScreenLock, "No secure screen lock configured", "Set a PIN, password or biometric screen lock"},
		{patchCurrent, "Security patch level is outdated or unknown", "Install the latest system security updates"},
	}

	passed := 0
	issues := []string{}
	recommendations := []string{}
	for _, c := range checks {
		if c.ok {
			passed++
			continue
		}
		issues = append(issues, c.issue)
		recommendations = append(recommendations, c.recommendation)
	}
	score := float64(passed) / float64(len(checks)) * 100.0

	return map[string]interface{}{
		"score":                     score,
		"grade":                     calculateGrade(score),
		"is_rooted":                 sec.IsRooted,
		"is_encrypted":              sec.IsEncrypted,
		"has_screen_lock":           sec.HasScreenLock,
		"security_patch":            sec.SecurityPatch,
		"has_latest_security_patch": patchCurrent,
		"platform":                  sec.Platform,
		"os_version":                sec.OSVersion,
		"model":                     sec.Model,
		"issues":                    issues,
		"recommendations":           recommendations,
	}
}

// GetDashboard handles GET /api/v1/stats/dashboard.
//
// Response contract (sections are omitted — never fabricated — when their
// real data source is unavailable):
//
//	{
//	  "generated_at": RFC3339,
//	  "recent_alerts": [ {id,title,description,severity,category,source,is_read,created_at,...} ],
//	  "unread_alerts": N,
//	  "total_alerts": N,
//	  "threats": {                       // global threat-intel stats from the indicators DB
//	    "total_indicators", "by_type", "by_severity", "high_severity",
//	    "new_today", "new_week", "new_month",
//	    "pegasus_indicators", "mobile_indicators",
//	    "active_campaigns",
//	    "campaigns_targeting_device"     // only with device identity
//	  },
//	  "protection": {                    // only with device identity; same shape as GET /stats/protection
//	    "is_active", "score", "grade",
//	    "features": {"sms":{"enabled","status"}, "web", "app", "network", "vpn"},
//	    "last_scan"
//	  },
//	  "activity": {                      // only with device identity; real per-device detections
//	    "threats_detected_today", "threats_detected_week", "threats_detected_month",
//	    "threats_detected_total", "messages_analyzed_total",
//	    "trend": [{"date","analyzed","count"}]
//	  },
//	  "device_health": { ... }           // only when the device has a security registration
//	}
//
// Device identity comes from the auth middleware when present, otherwise
// from the same bearer credentials the middleware accepts (the route is
// public so unauthenticated clients still get the global sections).
func (h *AlertsHandler) GetDashboard(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	deviceID := middleware.GetDeviceID(ctx)
	if deviceID == "" {
		deviceID = h.resolveBearerDeviceID(r)
	}

	cacheKey := "stats:dashboard:anon"
	if deviceID != "" {
		cacheKey = "stats:dashboard:device:" + deviceID
	}
	var cached map[string]interface{}
	if err := h.cache.GetJSON(ctx, cacheKey, &cached); err == nil && cached != nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(cached)
		return
	}

	resp := map[string]interface{}{
		"generated_at": time.Now().UTC().Format(time.RFC3339),
	}

	// Recent alerts from the live alerts source, newest first.
	alerts := h.loadAlerts(ctx)
	unread := 0
	for _, a := range alerts {
		if !a.IsRead {
			unread++
		}
	}
	recent := alerts
	if len(recent) > 10 {
		recent = recent[:10]
	}
	resp["recent_alerts"] = recent
	resp["unread_alerts"] = unread
	resp["total_alerts"] = len(alerts)

	// Resolve the device row once; it feeds protection, activity, health
	// and platform-targeted campaign counts.
	var device *repository.Device
	if deviceID != "" {
		device = h.resolveDevice(ctx, deviceID)
	}

	// Global threat-intelligence overview from the real indicators database.
	if h.repos != nil && h.repos.Indicators != nil {
		if dbStats, err := h.repos.Indicators.GetStats(ctx); err == nil && dbStats != nil {
			threats := map[string]interface{}{
				"total_indicators":   dbStats.TotalCount,
				"by_type":            dbStats.ByType,
				"by_severity":        dbStats.BySeverity,
				"high_severity":      dbStats.BySeverity["critical"] + dbStats.BySeverity["high"],
				"new_today":          dbStats.TodayNew,
				"new_week":           dbStats.WeeklyNew,
				"new_month":          dbStats.MonthlyNew,
				"pegasus_indicators": dbStats.PegasusCount,
				"mobile_indicators":  dbStats.MobileCount,
			}

			if h.repos.Campaigns != nil {
				if campaigns, total, cerr := h.repos.Campaigns.List(ctx, true, 1000, 0); cerr == nil {
					threats["active_campaigns"] = total
					if device != nil && device.Platform != "" {
						targeting := 0
						for _, c := range campaigns {
							if c == nil {
								continue
							}
							if len(c.TargetPlatforms) == 0 {
								// No platform restriction: campaign applies
								// to all platforms, including this device.
								targeting++
								continue
							}
							for _, p := range c.TargetPlatforms {
								if strings.EqualFold(string(p), device.Platform) {
									targeting++
									break
								}
							}
						}
						threats["campaigns_targeting_device"] = targeting
					}
				} else {
					h.logger.Warn().Err(cerr).Msg("failed to fetch campaign stats for dashboard")
				}
			}

			resp["threats"] = threats
		} else if err != nil {
			h.logger.Warn().Err(err).Msg("failed to fetch indicator stats for dashboard")
		}
	}

	// Device-scoped sections.
	if deviceID != "" && h.repos != nil {
		if h.netRepo != nil {
			if status, perr := h.deviceProtection(ctx, deviceID, device); perr == nil && status != nil {
				resp["protection"] = status
			} else if perr != nil {
				h.logger.Error().Err(perr).Str("device_id", deviceID).Msg("failed to compute protection status for dashboard")
			}
		}

		if h.repos.SMS != nil {
			if smsStats, serr := h.repos.SMS.GetDeviceStats(ctx, deviceID); serr == nil && smsStats != nil {
				var weekThreats, monthThreats int64
				now := time.Now().UTC()
				trend := make([]map[string]interface{}, 0, len(smsStats.Last30DaysTrend))
				for _, point := range smsStats.Last30DaysTrend {
					if day, derr := time.Parse("2006-01-02", point.Date); derr == nil {
						if now.Sub(day) <= 7*24*time.Hour {
							weekThreats += point.Threats
						}
						monthThreats += point.Threats
					}
					trend = append(trend, map[string]interface{}{
						"date":     point.Date,
						"analyzed": point.Analyzed,
						"count":    point.Threats,
					})
				}
				resp["activity"] = map[string]interface{}{
					"threats_detected_today":  smsStats.Last24hThreats,
					"threats_detected_week":   weekThreats,
					"threats_detected_month":  monthThreats,
					"threats_detected_total":  smsStats.ThreatsDetected,
					"messages_analyzed_total": smsStats.TotalAnalyzed,
					"trend":                   trend,
				}
			} else if serr != nil {
				h.logger.Warn().Err(serr).Str("device_id", deviceID).Msg("failed to fetch sms activity for dashboard")
			}
		}

		if health := h.deviceHealth(ctx, deviceID, device); health != nil {
			resp["device_health"] = health
		}
	}

	_ = h.cache.SetJSON(ctx, cacheKey, resp, 30*time.Second)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}
