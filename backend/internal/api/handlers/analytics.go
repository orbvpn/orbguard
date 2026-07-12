package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

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

func parseTimeRange(r *http.Request) models.AnalyticsTimeRange {
	now := time.Now()
	period := r.URL.Query().Get("period")
	if period == "" {
		period = "7d"
	}
	var start time.Time
	switch period {
	case "24h":
		start = now.Add(-24 * time.Hour)
	case "7d":
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

// GetThreatAnalytics handles GET /api/v1/analytics/threats
func (h *AnalyticsHandler) GetThreatAnalytics(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "analytics service not available"})
		return
	}
	result, err := h.service.GetThreatAnalytics(r.Context(), parseTimeRange(r))
	if err != nil {
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

	tr := parseTimeRange(r)
	_ = req.Period // period parsed from query params

	report, err := h.service.CreateReport(r.Context(), models.ReportType(req.ReportType), models.ReportFormat(req.Format), tr, req.Params)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusCreated, report)
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
		respondJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, report)
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
	reports, err := h.service.ListReports(r.Context(), limit)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, reports)
}
