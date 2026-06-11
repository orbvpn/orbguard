package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// AdminHandler handles admin endpoints
type AdminHandler struct {
	aggregator *services.Aggregator
	scheduler  *services.Scheduler
	reports    *repository.ThreatReportRepository
	indicators *repository.IndicatorRepository
	logger     *logger.Logger
}

// NewAdminHandler creates a new AdminHandler. repos may be nil (e.g. some
// test harnesses); database-backed endpoints then return an explicit 503.
func NewAdminHandler(agg *services.Aggregator, sched *services.Scheduler, repos *repository.Repositories, log *logger.Logger) *AdminHandler {
	h := &AdminHandler{
		aggregator: agg,
		scheduler:  sched,
		logger:     log.WithComponent("admin"),
	}
	if repos != nil {
		h.reports = repos.ThreatReports
		h.indicators = repos.Indicators
	}
	return h
}

// validReportStatuses mirrors the CHECK constraint on
// orbguard_lab.threat_reports.status (migration 007).
var validReportStatuses = map[string]bool{
	"pending":   true,
	"reviewing": true,
	"approved":  true,
	"rejected":  true,
	"duplicate": true,
}

// adminIdentity returns the reviewer identity from the AdminAuth context.
// AdminAuth proves the caller holds the admin token; when the underlying API
// token also carries a user id we record it, otherwise the literal "admin".
func adminIdentity(ctx context.Context) string {
	if uid := middleware.GetUserID(ctx); uid != "" {
		return uid
	}
	return "admin"
}

func (h *AdminHandler) respondJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func (h *AdminHandler) respondError(w http.ResponseWriter, status int, message string) {
	h.respondJSON(w, status, map[string]string{"error": message})
}

// reportStoreAvailable returns true when the threat report repository is
// wired; otherwise it writes an explicit 503 and logs the gap.
func (h *AdminHandler) reportStoreAvailable(w http.ResponseWriter, r *http.Request) bool {
	if h.reports == nil {
		h.logger.Error().Str("path", r.URL.Path).
			Msg("threat report repository not configured; admin report endpoint unavailable")
		h.respondError(w, http.StatusServiceUnavailable, "report storage is not configured")
		return false
	}
	return true
}

// TriggerUpdate handles POST /api/v1/admin/update
func (h *AdminHandler) TriggerUpdate(w http.ResponseWriter, r *http.Request) {
	h.logger.Info().Msg("triggering full update")

	if h.aggregator != nil {
		go func() {
			// Use background context since HTTP request context will be cancelled
			ctx := context.Background()
			if err := h.aggregator.RunOnce(ctx); err != nil {
				h.logger.Error().Err(err).Msg("update failed")
			}
		}()
	}

	h.respondJSON(w, http.StatusOK, map[string]any{
		"success": true,
		"message": "Update triggered",
	})
}

// TriggerSourceUpdate handles POST /api/v1/admin/update/{source}
func (h *AdminHandler) TriggerSourceUpdate(w http.ResponseWriter, r *http.Request) {
	source := chi.URLParam(r, "source")
	h.logger.Info().Str("source", source).Msg("triggering source update")

	if h.aggregator != nil {
		go func() {
			// Use background context since HTTP request context will be cancelled
			ctx := context.Background()
			if err := h.aggregator.RunSource(ctx, source); err != nil {
				h.logger.Error().Err(err).Str("source", source).Msg("source update failed")
			}
		}()
	}

	h.respondJSON(w, http.StatusOK, map[string]any{
		"success": true,
		"message": "Source update triggered",
		"source":  source,
	})
}

// ListReports handles GET /api/v1/admin/reports
// Lists community threat reports from orbguard_lab.threat_reports, filtered
// by status (default: pending).
func (h *AdminHandler) ListReports(w http.ResponseWriter, r *http.Request) {
	if !h.reportStoreAvailable(w, r) {
		return
	}

	status := r.URL.Query().Get("status")
	if status == "" {
		status = "pending"
	}
	if !validReportStatuses[status] {
		h.respondError(w, http.StatusBadRequest,
			"invalid status: must be one of pending, reviewing, approved, rejected, duplicate")
		return
	}

	limit, offset := parsePagination(r, 50, 200)

	reports, total, err := h.reports.ListByStatus(r.Context(), status, limit, offset)
	if err != nil {
		h.logger.Error().Err(err).Str("status", status).Msg("failed to list threat reports")
		h.respondError(w, http.StatusInternalServerError, "failed to list reports")
		return
	}

	pending := total
	if status != "pending" {
		pending, err = h.reports.CountByStatus(r.Context(), "pending")
		if err != nil {
			h.logger.Error().Err(err).Msg("failed to count pending threat reports")
			h.respondError(w, http.StatusInternalServerError, "failed to count pending reports")
			return
		}
	}

	h.respondJSON(w, http.StatusOK, map[string]any{
		"data":    reports,
		"total":   total,
		"pending": pending,
		"status":  status,
		"limit":   limit,
		"offset":  offset,
	})
}

// GetReport handles GET /api/v1/admin/reports/{id}
func (h *AdminHandler) GetReport(w http.ResponseWriter, r *http.Request) {
	if !h.reportStoreAvailable(w, r) {
		return
	}

	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid report id")
		return
	}

	report, err := h.reports.GetByID(r.Context(), id)
	if err != nil {
		h.logger.Error().Err(err).Str("report_id", id.String()).Msg("failed to get threat report")
		h.respondError(w, http.StatusInternalServerError, "failed to get report")
		return
	}
	if report == nil {
		h.respondError(w, http.StatusNotFound, "report not found")
		return
	}

	h.respondJSON(w, http.StatusOK, report)
}

// reviewRequest is the optional JSON body for approve/reject actions.
type reviewRequest struct {
	Notes string `json:"notes,omitempty"`
}

// loadReviewableReport fetches a report and verifies it can still be
// reviewed. It writes the error response itself and returns nil on failure.
func (h *AdminHandler) loadReviewableReport(w http.ResponseWriter, r *http.Request) *repository.ThreatReport {
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid report id")
		return nil
	}

	report, err := h.reports.GetByID(r.Context(), id)
	if err != nil {
		h.logger.Error().Err(err).Str("report_id", id.String()).Msg("failed to load threat report")
		h.respondError(w, http.StatusInternalServerError, "failed to load report")
		return nil
	}
	if report == nil {
		h.respondError(w, http.StatusNotFound, "report not found")
		return nil
	}
	if report.Status != "pending" && report.Status != "reviewing" {
		h.respondError(w, http.StatusConflict, "report has already been reviewed (status: "+report.Status+")")
		return nil
	}
	return report
}

// ApproveReport handles POST /api/v1/admin/reports/{id}/approve
// Transitions the report pending -> approved and upserts the reported
// indicator into the indicators table with source 'community'.
func (h *AdminHandler) ApproveReport(w http.ResponseWriter, r *http.Request) {
	if !h.reportStoreAvailable(w, r) {
		return
	}
	if h.indicators == nil {
		h.logger.Error().Str("path", r.URL.Path).
			Msg("indicator repository not configured; cannot approve reports")
		h.respondError(w, http.StatusServiceUnavailable, "indicator storage is not configured")
		return
	}

	report := h.loadReviewableReport(w, r)
	if report == nil {
		return
	}

	var body reviewRequest
	if r.Body != nil {
		// Body is optional; ignore decode errors for an empty body only.
		_ = json.NewDecoder(r.Body).Decode(&body)
	}

	reviewer := adminIdentity(r.Context())

	// Promote the reported indicator into the live indicator set.
	indicator := &models.Indicator{
		Value:       report.IndicatorValue,
		Type:        models.ParseIndicatorType(report.IndicatorType),
		Severity:    models.ParseSeverity(report.Severity),
		Description: report.Description,
		Tags:        report.Tags,
		Confidence:  0.5, // community-sourced, single report
		SourceID:    "community",
		SourceName:  "Community Reports",
	}

	saved, err := h.indicators.Upsert(r.Context(), indicator)
	if err != nil {
		h.logger.Error().Err(err).
			Str("report_id", report.ID.String()).
			Str("indicator_value", report.IndicatorValue).
			Msg("failed to upsert indicator from approved report")
		h.respondError(w, http.StatusInternalServerError, "failed to create indicator from report")
		return
	}

	if err := h.reports.UpdateStatus(r.Context(), report.ID, "approved", reviewer, body.Notes, &saved.ID); err != nil {
		h.logger.Error().Err(err).Str("report_id", report.ID.String()).Msg("failed to mark report approved")
		h.respondError(w, http.StatusInternalServerError, "failed to update report status")
		return
	}

	h.logger.Info().
		Str("report_id", report.ID.String()).
		Str("indicator_id", saved.ID.String()).
		Str("reviewer", reviewer).
		Msg("report approved; indicator upserted")

	h.respondJSON(w, http.StatusOK, map[string]any{
		"success":      true,
		"message":      "Report approved",
		"report_id":    report.ID.String(),
		"indicator_id": saved.ID.String(),
	})
}

// RejectReport handles POST /api/v1/admin/reports/{id}/reject
func (h *AdminHandler) RejectReport(w http.ResponseWriter, r *http.Request) {
	if !h.reportStoreAvailable(w, r) {
		return
	}

	report := h.loadReviewableReport(w, r)
	if report == nil {
		return
	}

	var body reviewRequest
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&body)
	}

	reviewer := adminIdentity(r.Context())

	if err := h.reports.UpdateStatus(r.Context(), report.ID, "rejected", reviewer, body.Notes, nil); err != nil {
		h.logger.Error().Err(err).Str("report_id", report.ID.String()).Msg("failed to mark report rejected")
		h.respondError(w, http.StatusInternalServerError, "failed to update report status")
		return
	}

	h.logger.Info().
		Str("report_id", report.ID.String()).
		Str("reviewer", reviewer).
		Msg("report rejected")

	h.respondJSON(w, http.StatusOK, map[string]any{
		"success":   true,
		"message":   "Report rejected",
		"report_id": report.ID.String(),
	})
}

// DetailedStats handles GET /api/v1/admin/stats/detailed
func (h *AdminHandler) DetailedStats(w http.ResponseWriter, r *http.Request) {
	stats := make(map[string]any)

	if h.aggregator != nil {
		stats["aggregator"] = h.aggregator.Stats()
	}

	if h.scheduler != nil {
		stats["scheduler"] = h.scheduler.Stats()
	}

	// Real community-report queue counts from the database when available.
	if h.reports != nil {
		reportStats := make(map[string]int64, len(validReportStatuses))
		for status := range validReportStatuses {
			count, err := h.reports.CountByStatus(r.Context(), status)
			if err != nil {
				h.logger.Error().Err(err).Str("status", status).Msg("failed to count threat reports for stats")
				h.respondError(w, http.StatusInternalServerError, "failed to compute report stats")
				return
			}
			reportStats[status] = count
		}
		stats["reports"] = reportStats
	}

	h.respondJSON(w, http.StatusOK, stats)
}

// parsePagination extracts limit/offset query params with bounds.
func parsePagination(r *http.Request, defaultLimit, maxLimit int) (int, int) {
	limit := defaultLimit
	if l := r.URL.Query().Get("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil && parsed > 0 {
			limit = parsed
			if limit > maxLimit {
				limit = maxLimit
			}
		}
	}
	offset := 0
	if o := r.URL.Query().Get("offset"); o != "" {
		if parsed, err := strconv.Atoi(o); err == nil && parsed >= 0 {
			offset = parsed
		}
	}
	return limit, offset
}
