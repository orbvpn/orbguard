package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// URLHandler handles URL protection API requests
type URLHandler struct {
	urlService *services.URLReputationService
	logger     *logger.Logger
}

// NewURLHandler creates a new URL handler
func NewURLHandler(urlService *services.URLReputationService, log *logger.Logger) *URLHandler {
	return &URLHandler{
		urlService: urlService,
		logger:     log.WithComponent("url-handler"),
	}
}

// CheckURL handles POST /api/v1/url/check
func (h *URLHandler) CheckURL(w http.ResponseWriter, r *http.Request) {
	var req models.URLCheckRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.URL == "" {
		h.respondError(w, http.StatusBadRequest, "url is required")
		return
	}

	userID := middleware.GetUserID(r.Context())

	result, err := h.urlService.CheckURLForUser(r.Context(), userID, &req)
	if err != nil {
		h.logger.Error().Err(err).Str("url", req.URL).Msg("failed to check URL")
		h.respondError(w, http.StatusInternalServerError, "failed to check URL")
		return
	}

	h.respondJSON(w, http.StatusOK, result)
}

// BatchCheckURLs handles POST /api/v1/url/check/batch
func (h *URLHandler) BatchCheckURLs(w http.ResponseWriter, r *http.Request) {
	var req models.URLBatchCheckRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if len(req.URLs) == 0 {
		h.respondError(w, http.StatusBadRequest, "urls array is required")
		return
	}

	if len(req.URLs) > 100 {
		h.respondError(w, http.StatusBadRequest, "maximum 100 URLs per batch")
		return
	}

	result, err := h.urlService.BatchCheckURLs(r.Context(), &req)
	if err != nil {
		h.logger.Error().Err(err).Int("count", len(req.URLs)).Msg("failed to batch check URLs")
		h.respondError(w, http.StatusInternalServerError, "failed to check URLs")
		return
	}

	h.respondJSON(w, http.StatusOK, result)
}

// GetReputation handles GET /api/v1/url/reputation/{domain}
func (h *URLHandler) GetReputation(w http.ResponseWriter, r *http.Request) {
	domain := chi.URLParam(r, "domain")
	if domain == "" {
		h.respondError(w, http.StatusBadRequest, "domain is required")
		return
	}

	rep, err := h.urlService.GetDomainReputation(r.Context(), domain)
	if err != nil {
		h.logger.Error().Err(err).Str("domain", domain).Msg("failed to get domain reputation")
		h.respondError(w, http.StatusInternalServerError, "failed to get reputation")
		return
	}

	if rep == nil {
		h.respondError(w, http.StatusNotFound, "domain does not exist or is not a valid domain name")
		return
	}

	h.respondJSON(w, http.StatusOK, rep)
}

// GetStats handles GET /api/v1/url/stats
func (h *URLHandler) GetStats(w http.ResponseWriter, r *http.Request) {
	stats, err := h.urlService.GetStats(r.Context())
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to get URL stats")
		h.respondError(w, http.StatusInternalServerError, "failed to get stats")
		return
	}

	h.respondJSON(w, http.StatusOK, stats)
}

// GetDNSBlockRules handles GET /api/v1/url/dns-rules
func (h *URLHandler) GetDNSBlockRules(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())

	rules, err := h.urlService.GetDNSBlockRules(r.Context(), userID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to get DNS block rules")
		h.respondError(w, http.StatusInternalServerError, "failed to get DNS rules")
		return
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"rules":      rules,
		"count":      len(rules),
		"updated_at": time.Now(),
	})
}

// urlListRequest is the request body for whitelist/blacklist additions
type urlListRequest struct {
	URL     string `json:"url,omitempty"`
	Domain  string `json:"domain,omitempty"`
	Pattern string `json:"pattern,omitempty"`
	Reason  string `json:"reason,omitempty"`
}

// addToList handles adding an entry to the authenticated user's list
func (h *URLHandler) addToList(w http.ResponseWriter, r *http.Request, listType models.URLListType) {
	var req urlListRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.URL == "" && req.Domain == "" && req.Pattern == "" {
		h.respondError(w, http.StatusBadRequest, "url, domain, or pattern is required")
		return
	}

	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		h.respondError(w, http.StatusUnauthorized, "user identity is required to manage URL lists")
		return
	}

	entry := &models.URLListEntry{
		URL:       req.URL,
		Domain:    req.Domain,
		Pattern:   req.Pattern,
		ListType:  listType,
		Reason:    req.Reason,
		CreatedBy: userID,
		IsActive:  true,
	}

	if err := h.urlService.AddToList(r.Context(), userID, entry); err != nil {
		h.respondListError(w, err, "failed to add to "+string(listType))
		return
	}

	h.respondJSON(w, http.StatusCreated, entry)
}

// AddToWhitelist handles POST /api/v1/url/whitelist
func (h *URLHandler) AddToWhitelist(w http.ResponseWriter, r *http.Request) {
	h.addToList(w, r, models.URLListTypeWhitelist)
}

// AddToBlacklist handles POST /api/v1/url/blacklist
func (h *URLHandler) AddToBlacklist(w http.ResponseWriter, r *http.Request) {
	h.addToList(w, r, models.URLListTypeBlacklist)
}

// getList handles fetching the authenticated user's list entries
func (h *URLHandler) getList(w http.ResponseWriter, r *http.Request, listType models.URLListType) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		h.respondError(w, http.StatusUnauthorized, "user identity is required to view URL lists")
		return
	}

	entries, err := h.urlService.GetList(r.Context(), userID, listType)
	if err != nil {
		h.respondListError(w, err, "failed to get "+string(listType))
		return
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"entries": entries,
		"count":   len(entries),
	})
}

// GetWhitelist handles GET /api/v1/url/whitelist
func (h *URLHandler) GetWhitelist(w http.ResponseWriter, r *http.Request) {
	h.getList(w, r, models.URLListTypeWhitelist)
}

// GetBlacklist handles GET /api/v1/url/blacklist
func (h *URLHandler) GetBlacklist(w http.ResponseWriter, r *http.Request) {
	h.getList(w, r, models.URLListTypeBlacklist)
}

// RemoveFromList handles DELETE /api/v1/url/list/{id}
func (h *URLHandler) RemoveFromList(w http.ResponseWriter, r *http.Request) {
	idStr := chi.URLParam(r, "id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid id")
		return
	}

	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		h.respondError(w, http.StatusUnauthorized, "user identity is required to manage URL lists")
		return
	}

	if err := h.urlService.RemoveFromList(r.Context(), userID, id); err != nil {
		if errors.Is(err, repository.ErrURLListEntryNotFound) {
			h.respondError(w, http.StatusNotFound, "list entry not found")
			return
		}
		h.logger.Error().Err(err).Str("id", idStr).Msg("failed to remove from list")
		h.respondListError(w, err, "failed to remove from list")
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// GetBlockPage handles GET /api/v1/url/block-page
func (h *URLHandler) GetBlockPage(w http.ResponseWriter, r *http.Request) {
	url := r.URL.Query().Get("url")
	if url == "" {
		h.respondError(w, http.StatusBadRequest, "url query parameter is required")
		return
	}

	userID := middleware.GetUserID(r.Context())

	// Check the URL to get threat details
	result, err := h.urlService.CheckURLForUser(r.Context(), userID, &models.URLCheckRequest{URL: url})
	if err != nil {
		h.logger.Error().Err(err).Str("url", url).Msg("failed to check URL for block page")
		h.respondError(w, http.StatusInternalServerError, "failed to generate block page")
		return
	}

	blockData := &models.BlockPageData{
		URL:           url,
		Domain:        result.Domain,
		Category:      result.Category,
		ThreatLevel:   result.ThreatLevel,
		Reason:        result.BlockReason,
		AllowOverride: result.AllowOverride,
		ReportURL:     "/api/v1/url/report",
		Timestamp:     time.Now(),
	}

	h.respondJSON(w, http.StatusOK, blockData)
}

// ReportURL handles POST /api/v1/url/report
func (h *URLHandler) ReportURL(w http.ResponseWriter, r *http.Request) {
	var req struct {
		URL        string `json:"url"`
		ReportType string `json:"report_type"` // "false_positive", "missed_threat", "feedback"
		Comment    string `json:"comment,omitempty"`
		DeviceID   string `json:"device_id,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.URL == "" || req.ReportType == "" {
		h.respondError(w, http.StatusBadRequest, "url and report_type are required")
		return
	}

	switch req.ReportType {
	case "false_positive", "missed_threat", "feedback":
	default:
		h.respondError(w, http.StatusBadRequest, "report_type must be one of: false_positive, missed_threat, feedback")
		return
	}

	userID := middleware.GetUserID(r.Context())
	deviceID := middleware.GetDeviceID(r.Context())
	if deviceID == "" {
		deviceID = req.DeviceID
	}

	report, err := h.urlService.ReportURL(r.Context(), userID, deviceID, req.URL, req.ReportType, req.Comment)
	if err != nil {
		h.logger.Error().Err(err).Str("url", req.URL).Msg("failed to persist URL report")
		h.respondListError(w, err, "failed to submit report")
		return
	}

	h.respondJSON(w, http.StatusCreated, map[string]interface{}{
		"id":         report.ID,
		"status":     report.Status,
		"created_at": report.CreatedAt,
		"message":    "Thank you for your report. It will be reviewed.",
	})
}

// respondListError maps known service errors for list operations to
// appropriate HTTP statuses, falling back to 500.
func (h *URLHandler) respondListError(w http.ResponseWriter, err error, fallback string) {
	switch {
	case errors.Is(err, services.ErrURLListsUnavailable):
		h.respondError(w, http.StatusServiceUnavailable, "URL list storage is currently unavailable")
	case errors.Is(err, services.ErrUserIdentityRequired):
		h.respondError(w, http.StatusUnauthorized, "user identity is required")
	default:
		h.logger.Error().Err(err).Msg(fallback)
		h.respondError(w, http.StatusInternalServerError, fallback)
	}
}

func (h *URLHandler) respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func (h *URLHandler) respondError(w http.ResponseWriter, status int, message string) {
	h.respondJSON(w, status, map[string]string{"error": message})
}
