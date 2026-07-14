package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/pkg/logger"
)

// AnalyticsHandler handles analytics and reporting endpoints
type AnalyticsHandler struct {
	service *services.AnalyticsService
	logger  *logger.Logger
}

// NewAnalyticsHandler creates a new AnalyticsHandler
func NewAnalyticsHandler(log *logger.Logger, svc *services.AnalyticsService) *AnalyticsHandler {
	return &AnalyticsHandler{
		service: svc,
		logger:  log.WithComponent("analytics-handler"),
	}
}

func periodToTimeRange(period string, now time.Time) models.AnalyticsTimeRange {
	var start time.Time
	switch period {
	case "24h":
		start = now.Add(-24 * time.Hour)
	case "7d", "":
		start = now.AddDate(0, 0, -7)
	case "30d":
		start = now.AddDate(0, 0, -30)
	case "90d":
		start = now.AddDate(0, 0, -90)
	default:
		start = now.AddDate(0, 0, -7)
	}
	return models.AnalyticsTimeRange{Start: start, End: now}
}

func parseTimeRange(r *http.Request) models.AnalyticsTimeRange {
	return periodToTimeRange(r.URL.Query().Get("period"), time.Now())
}

// GetThreatAnalytics handles GET /api/v1/analytics/threats
func (h *AnalyticsHandler) GetThreatAnalytics(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "analytics service not available"})
		return
	}
	result, err := h.service.GetThreatAnalytics(r.Context(), parseTimeRange(r))
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to compute threat analytics")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, result)
}

// GetAlertMetrics handles GET /api/v1/analytics/alerts
func (h *AnalyticsHandler) GetAlertMetrics(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "analytics service not available"})
		return
	}
	result, err := h.service.GetAlertMetrics(r.Context(), parseTimeRange(r))
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to compute alert metrics")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, result)
}

// GetDetectionMetrics handles GET /api/v1/analytics/detections
func (h *AnalyticsHandler) GetDetectionMetrics(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "analytics service not available"})
		return
	}
	result, err := h.service.GetDetectionMetrics(r.Context(), parseTimeRange(r))
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to compute detection metrics")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, result)
}

// GetSourceHealth handles GET /api/v1/analytics/sources
func (h *AnalyticsHandler) GetSourceHealth(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "analytics service not available"})
		return
	}
	result, err := h.service.GetSourceHealth(r.Context())
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to compute source health")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, result)
}

// GetGeoDistribution handles GET /api/v1/analytics/geo
func (h *AnalyticsHandler) GetGeoDistribution(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "analytics service not available"})
		return
	}
	result, err := h.service.GetGeoDistribution(r.Context(), parseTimeRange(r))
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to compute geo distribution")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, result)
}

// GetDashboard handles GET /api/v1/analytics/dashboard
func (h *AnalyticsHandler) GetDashboard(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "analytics service not available"})
		return
	}
	respondJSON(w, http.StatusOK, h.service.GetDefaultDashboard())
}

// CreateReport handles POST /api/v1/analytics/reports
func (h *AnalyticsHandler) CreateReport(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "analytics service not available"})
		return
	}
	var req struct {
		ReportType string                 `json:"report_type"`
		Format     string                 `json:"format"`
		Period     string                 `json:"period"`
		Params     map[string]interface{} `json:"params"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	// Body period takes precedence over the query parameter
	tr := parseTimeRange(r)
	if req.Period != "" {
		tr = periodToTimeRange(req.Period, time.Now())
	}

	createdBy := middleware.GetUserID(r.Context())

	report, err := h.service.CreateReport(r.Context(), models.ReportType(req.ReportType), models.ReportFormat(req.Format), tr, req.Params, createdBy)
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusCreated, report)
}

// canAccessReport applies per-user report scoping: service requests see all
// reports, users see their own (and legacy reports without an owner)
func canAccessReport(r *http.Request, createdBy string) bool {
	if middleware.IsServiceRequest(r.Context()) {
		return true
	}
	if createdBy == "" {
		return true
	}
	return createdBy == middleware.GetUserID(r.Context())
}

// GetReport handles GET /api/v1/analytics/reports/{id}
func (h *AnalyticsHandler) GetReport(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "analytics service not available"})
		return
	}
	id := chi.URLParam(r, "id")
	report, err := h.service.GetReport(r.Context(), id)
	if err != nil {
		h.logger.Error().Err(err).Str("report_id", id).Msg("failed to get report")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	if report == nil || !canAccessReport(r, report.CreatedBy) {
		respondJSON(w, http.StatusNotFound, map[string]string{"error": "report not found"})
		return
	}
	respondJSON(w, http.StatusOK, report)
}

// DownloadReport handles GET /api/v1/analytics/reports/{id}/download
func (h *AnalyticsHandler) DownloadReport(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "analytics service not available"})
		return
	}
	id := chi.URLParam(r, "id")
	data, report, err := h.service.GetReportFile(r.Context(), id)
	if err != nil {
		h.logger.Error().Err(err).Str("report_id", id).Msg("failed to load report file")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	if report == nil || !canAccessReport(r, report.CreatedBy) {
		respondJSON(w, http.StatusNotFound, map[string]string{"error": "report not found"})
		return
	}
	if !report.ExpiresAt.IsZero() && time.Now().After(report.ExpiresAt) {
		respondJSON(w, http.StatusGone, map[string]string{"error": "report has expired"})
		return
	}
	if report.Status != models.AnalyticsReportStatusCompleted || len(data) == 0 {
		respondJSON(w, http.StatusConflict, map[string]string{
			"error":  "report is not ready for download",
			"status": string(report.Status),
		})
		return
	}

	var contentType, ext string
	switch report.Format {
	case models.ReportFormatCSV:
		contentType, ext = "text/csv; charset=utf-8", "csv"
	case models.ReportFormatHTML:
		contentType, ext = "text/html; charset=utf-8", "html"
	default:
		contentType, ext = "application/json", "json"
	}

	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", report.Name+"."+ext))
	w.Header().Set("Content-Length", strconv.Itoa(len(data)))
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(data)
}

// ListReports handles GET /api/v1/analytics/reports
func (h *AnalyticsHandler) ListReports(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "analytics service not available"})
		return
	}
	limit := 20
	if l := r.URL.Query().Get("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil {
			limit = parsed
		}
	}

	// Per-user scoping: service requests list all reports
	createdBy := ""
	if !middleware.IsServiceRequest(r.Context()) {
		createdBy = middleware.GetUserID(r.Context())
	}

	reports, err := h.service.ListReports(r.Context(), createdBy, limit)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to list reports")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, reports)
}
