package handlers

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// AppSecurityHandler handles app security API requests
type AppSecurityHandler struct {
	analyzer *services.AppAnalyzer
	logger   *logger.Logger
}

// NewAppSecurityHandler creates a new app security handler
func NewAppSecurityHandler(analyzer *services.AppAnalyzer, log *logger.Logger) *AppSecurityHandler {
	return &AppSecurityHandler{
		analyzer: analyzer,
		logger:   log.WithComponent("app-security-handler"),
	}
}

// AnalyzeApp handles POST /api/v1/apps/analyze
func (h *AppSecurityHandler) AnalyzeApp(w http.ResponseWriter, r *http.Request) {
	var req models.AppAnalysisRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.PackageName == "" {
		h.respondError(w, http.StatusBadRequest, "package_name is required")
		return
	}

	// Scope the analysis to the authenticated identity. The user ID is never
	// accepted from the request body.
	req.UserID = middleware.GetUserID(r.Context())
	if req.DeviceID == "" {
		req.DeviceID = middleware.GetDeviceID(r.Context())
	}

	result, err := h.analyzer.AnalyzeApp(r.Context(), &req)
	if err != nil {
		h.logger.Error().Err(err).Str("package", req.PackageName).Msg("failed to analyze app")
		h.respondError(w, http.StatusInternalServerError, "failed to analyze app")
		return
	}

	h.respondJSON(w, http.StatusOK, result)
}

// AnalyzeBatch handles POST /api/v1/apps/analyze/batch
func (h *AppSecurityHandler) AnalyzeBatch(w http.ResponseWriter, r *http.Request) {
	var req models.AppBatchAnalysisRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if len(req.Apps) == 0 {
		h.respondError(w, http.StatusBadRequest, "apps array is required")
		return
	}

	if len(req.Apps) > 100 {
		h.respondError(w, http.StatusBadRequest, "maximum 100 apps per batch")
		return
	}

	// Scope each analysis to the authenticated identity.
	userID := middleware.GetUserID(r.Context())
	if req.DeviceID == "" {
		req.DeviceID = middleware.GetDeviceID(r.Context())
	}
	for i := range req.Apps {
		req.Apps[i].UserID = userID
		if req.Apps[i].DeviceID == "" {
			req.Apps[i].DeviceID = req.DeviceID
		}
	}

	result, err := h.analyzer.AnalyzeBatch(r.Context(), &req)
	if err != nil {
		h.logger.Error().Err(err).Int("count", len(req.Apps)).Msg("failed to analyze apps batch")
		h.respondError(w, http.StatusInternalServerError, "failed to analyze apps")
		return
	}

	h.respondJSON(w, http.StatusOK, result)
}

// GetAppReputation handles GET /api/v1/apps/reputation/{package}
func (h *AppSecurityHandler) GetAppReputation(w http.ResponseWriter, r *http.Request) {
	packageName := chi.URLParam(r, "package")
	if packageName == "" {
		h.respondError(w, http.StatusBadRequest, "package name is required")
		return
	}

	reputation, err := h.analyzer.GetAppReputation(r.Context(), packageName)
	if err != nil {
		h.logger.Error().Err(err).Str("package", packageName).Msg("failed to get app reputation")
		h.respondError(w, http.StatusInternalServerError, "failed to get app reputation")
		return
	}

	if reputation == nil {
		// Nothing is known about this package: no indicators, no analysis
		// history, no reports. Be explicit rather than fabricating "safe".
		h.respondJSON(w, http.StatusNotFound, map[string]interface{}{
			"package_name": packageName,
			"known":        false,
			"message":      "no reputation data available for this package",
		})
		return
	}

	h.respondJSON(w, http.StatusOK, reputation)
}

// CheckSideloaded handles POST /api/v1/apps/sideloaded
func (h *AppSecurityHandler) CheckSideloaded(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Apps     []models.AppInfo `json:"apps"`
		DeviceID string           `json:"device_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if len(req.Apps) == 0 {
		h.respondError(w, http.StatusBadRequest, "apps array is required")
		return
	}

	report, err := h.analyzer.GetSideloadedApps(r.Context(), req.Apps)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to check sideloaded apps")
		h.respondError(w, http.StatusInternalServerError, "failed to check sideloaded apps")
		return
	}

	if req.DeviceID != "" {
		report.DeviceID = req.DeviceID
	}

	h.respondJSON(w, http.StatusOK, report)
}

// GetPrivacyReport handles POST /api/v1/apps/privacy-report
func (h *AppSecurityHandler) GetPrivacyReport(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Apps     []models.AppAnalysisRequest `json:"apps"`
		DeviceID string                      `json:"device_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if len(req.Apps) == 0 {
		h.respondError(w, http.StatusBadRequest, "apps array is required")
		return
	}

	// Scope each analysis to the authenticated identity.
	userID := middleware.GetUserID(r.Context())
	if req.DeviceID == "" {
		req.DeviceID = middleware.GetDeviceID(r.Context())
	}
	for i := range req.Apps {
		req.Apps[i].UserID = userID
		if req.Apps[i].DeviceID == "" {
			req.Apps[i].DeviceID = req.DeviceID
		}
	}

	// Analyze all apps first
	batchResult, err := h.analyzer.AnalyzeBatch(r.Context(), &models.AppBatchAnalysisRequest{
		Apps:     req.Apps,
		DeviceID: req.DeviceID,
	})
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to analyze apps for privacy report")
		h.respondError(w, http.StatusInternalServerError, "failed to generate privacy report")
		return
	}

	// Generate privacy report
	report, err := h.analyzer.GeneratePrivacyReport(r.Context(), batchResult.Results, req.DeviceID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to generate privacy report")
		h.respondError(w, http.StatusInternalServerError, "failed to generate privacy report")
		return
	}

	h.respondJSON(w, http.StatusOK, report)
}

// GetStats handles GET /api/v1/apps/stats
func (h *AppSecurityHandler) GetStats(w http.ResponseWriter, r *http.Request) {
	stats, err := h.analyzer.GetStats(r.Context())
	if err != nil {
		if errors.Is(err, services.ErrAppSecurityUnavailable) {
			h.respondError(w, http.StatusServiceUnavailable, "app security statistics unavailable: persistence not configured")
			return
		}
		h.logger.Error().Err(err).Msg("failed to get app stats")
		h.respondError(w, http.StatusInternalServerError, "failed to get stats")
		return
	}

	h.respondJSON(w, http.StatusOK, stats)
}

// GetKnownTrackers handles GET /api/v1/apps/trackers
func (h *AppSecurityHandler) GetKnownTrackers(w http.ResponseWriter, r *http.Request) {
	trackers := make([]models.TrackerSDK, 0, len(models.KnownTrackers))
	for _, tracker := range models.KnownTrackers {
		trackers = append(trackers, tracker)
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"trackers": trackers,
		"count":    len(trackers),
	})
}

// GetDangerousPermissions handles GET /api/v1/apps/permissions/dangerous
func (h *AppSecurityHandler) GetDangerousPermissions(w http.ResponseWriter, r *http.Request) {
	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"dangerous_combos": models.DangerousPermissionCombos,
		"count":            len(models.DangerousPermissionCombos),
	})
}

// ReportApp handles POST /api/v1/apps/report
func (h *AppSecurityHandler) ReportApp(w http.ResponseWriter, r *http.Request) {
	var req struct {
		PackageName string `json:"package_name"`
		ReportType  string `json:"report_type"` // "malware", "privacy", "scam", "other"
		Description string `json:"description"`
		DeviceID    string `json:"device_id,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.PackageName == "" || req.ReportType == "" {
		h.respondError(w, http.StatusBadRequest, "package_name and report_type are required")
		return
	}

	switch req.ReportType {
	case "malware", "privacy", "scam", "fraud", "other":
		// valid
	default:
		h.respondError(w, http.StatusBadRequest, "report_type must be one of: malware, privacy, scam, fraud, other")
		return
	}

	deviceID := req.DeviceID
	if deviceID == "" {
		deviceID = middleware.GetDeviceID(r.Context())
	}

	saved, err := h.analyzer.SaveAppReport(r.Context(), &repository.AppReportRecord{
		PackageName: req.PackageName,
		ReportType:  req.ReportType,
		Description: req.Description,
		DeviceID:    deviceID,
		UserID:      middleware.GetUserID(r.Context()),
	})
	if err != nil {
		if errors.Is(err, services.ErrAppSecurityUnavailable) {
			h.respondError(w, http.StatusServiceUnavailable, "app reports unavailable: persistence not configured")
			return
		}
		h.logger.Error().Err(err).Str("package", req.PackageName).Msg("failed to save app report")
		h.respondError(w, http.StatusInternalServerError, "failed to save app report")
		return
	}

	h.logger.Info().
		Str("package", req.PackageName).
		Str("type", req.ReportType).
		Str("report_id", saved.ID.String()).
		Msg("app report received")

	h.respondJSON(w, http.StatusCreated, map[string]interface{}{
		"id":         saved.ID.String(),
		"status":     saved.Status,
		"created_at": saved.CreatedAt,
		"message":    "Thank you for your report. It will be reviewed by our team.",
	})
}

func (h *AppSecurityHandler) respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func (h *AppSecurityHandler) respondError(w http.ResponseWriter, status int, message string) {
	h.respondJSON(w, status, map[string]string{"error": message})
}
