package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services/digital_footprint"
	"orbguard-lab/pkg/logger"
)

// removalProcessTimeout bounds the background opt-out submission per request.
const removalProcessTimeout = 2 * time.Minute

// FootprintHandler handles digital footprint endpoints
type FootprintHandler struct {
	scanner *digital_footprint.Scanner
	logger  *logger.Logger
}

// NewFootprintHandler creates a new FootprintHandler
func NewFootprintHandler(scanner *digital_footprint.Scanner, log *logger.Logger) *FootprintHandler {
	return &FootprintHandler{
		scanner: scanner,
		logger:  log.WithComponent("footprint-handler"),
	}
}

// Scan handles POST /api/v1/footprint/scan
func (h *FootprintHandler) Scan(w http.ResponseWriter, r *http.Request) {
	if h.scanner == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "footprint scanner not available"})
		return
	}

	var req models.FootprintScanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	if req.Email == "" {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "email is required"})
		return
	}
	if req.ScanType == "" {
		req.ScanType = "full"
	}

	result, err := h.scanner.ScanFootprint(r.Context(), req)
	if err != nil {
		h.logger.Error().Err(err).Msg("footprint scan failed")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": "scan failed"})
		return
	}

	respondJSON(w, http.StatusOK, result)
}

// QuickScan handles POST /api/v1/footprint/quick-scan
func (h *FootprintHandler) QuickScan(w http.ResponseWriter, r *http.Request) {
	if h.scanner == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "footprint scanner not available"})
		return
	}

	var req struct {
		Email string `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Email == "" {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "email is required"})
		return
	}

	result, err := h.scanner.QuickScan(r.Context(), req.Email)
	if err != nil {
		h.logger.Error().Err(err).Msg("quick scan failed")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": "scan failed"})
		return
	}

	respondJSON(w, http.StatusOK, result)
}

// GetBrokers handles GET /api/v1/footprint/brokers
func (h *FootprintHandler) GetBrokers(w http.ResponseWriter, r *http.Request) {
	if h.scanner == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "footprint scanner not available"})
		return
	}
	respondJSON(w, http.StatusOK, h.scanner.GetAllBrokers())
}

// GetCategories handles GET /api/v1/footprint/brokers/categories
func (h *FootprintHandler) GetCategories(w http.ResponseWriter, r *http.Request) {
	respondJSON(w, http.StatusOK, map[string]interface{}{
		"categories": []string{
			"people_search", "data_broker", "marketing", "background_check",
			"social_media", "public_records", "advertising", "other",
		},
	})
}

// GetBroker handles GET /api/v1/footprint/brokers/{id}
func (h *FootprintHandler) GetBroker(w http.ResponseWriter, r *http.Request) {
	if h.scanner == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "footprint scanner not available"})
		return
	}

	brokerID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid broker ID"})
		return
	}

	for _, b := range h.scanner.GetAllBrokers() {
		if b.ID == brokerID {
			respondJSON(w, http.StatusOK, b)
			return
		}
	}
	respondJSON(w, http.StatusNotFound, map[string]string{"error": "broker not found"})
}

// RequestRemoval handles POST /api/v1/footprint/removal
func (h *FootprintHandler) RequestRemoval(w http.ResponseWriter, r *http.Request) {
	if h.scanner == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "footprint scanner not available"})
		return
	}

	var req struct {
		UserID   string `json:"user_id"`
		BrokerID string `json:"broker_id"`
		Email    string `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	userID := h.resolveUserID(r.Context(), req.UserID)
	if userID == uuid.Nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "user identity required"})
		return
	}
	brokerID, err := uuid.Parse(req.BrokerID)
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid broker_id"})
		return
	}

	result, err := h.scanner.RequestRemoval(r.Context(), userID, brokerID, req.Email)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	// Submit the opt-out asynchronously; status transitions are persisted by
	// the removal service and visible via GET /footprint/removal/{id}.
	h.processRemovalAsync(*result)

	respondJSON(w, http.StatusOK, result)
}

// resolveUserID prefers the authenticated user identity from the request
// context and falls back to the (service-supplied) body value.
func (h *FootprintHandler) resolveUserID(ctx context.Context, bodyUserID string) uuid.UUID {
	if authUID := middleware.GetUserID(ctx); authUID != "" {
		if id, err := uuid.Parse(authUID); err == nil {
			return id
		}
	}
	id, _ := uuid.Parse(bodyUserID)
	return id
}

// processRemovalAsync runs the opt-out submission for a removal request in
// the background with its own bounded context.
func (h *FootprintHandler) processRemovalAsync(request models.RemovalRequest) {
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), removalProcessTimeout)
		defer cancel()

		if err := h.scanner.ProcessRemovalRequest(ctx, &request); err != nil {
			h.logger.Warn().Err(err).
				Str("request_id", request.ID.String()).
				Str("broker", request.BrokerName).
				Msg("removal request processing failed")
			return
		}
		h.logger.Info().
			Str("request_id", request.ID.String()).
			Str("broker", request.BrokerName).
			Str("status", string(request.Status)).
			Msg("removal request processed")
	}()
}

// RequestBatchRemoval handles POST /api/v1/footprint/removal/batch
func (h *FootprintHandler) RequestBatchRemoval(w http.ResponseWriter, r *http.Request) {
	if h.scanner == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "footprint scanner not available"})
		return
	}

	var req struct {
		UserID    string   `json:"user_id"`
		BrokerIDs []string `json:"broker_ids"`
		Email     string   `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	userID := h.resolveUserID(r.Context(), req.UserID)
	if userID == uuid.Nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "user identity required"})
		return
	}
	brokerIDs := make([]uuid.UUID, 0, len(req.BrokerIDs))
	for _, id := range req.BrokerIDs {
		if bid, err := uuid.Parse(id); err == nil {
			brokerIDs = append(brokerIDs, bid)
		}
	}

	result, err := h.scanner.RequestBatchRemoval(r.Context(), userID, brokerIDs, req.Email)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	// Submit each created opt-out asynchronously.
	for _, request := range result.Requests {
		h.processRemovalAsync(request)
	}

	respondJSON(w, http.StatusOK, result)
}

// GetRemovalStatus handles GET /api/v1/footprint/removal/{id}
func (h *FootprintHandler) GetRemovalStatus(w http.ResponseWriter, r *http.Request) {
	if h.scanner == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "footprint scanner not available"})
		return
	}

	requestID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request ID"})
		return
	}

	result, err := h.scanner.GetRemovalStatus(r.Context(), requestID)
	if err != nil {
		respondJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
		return
	}

	// Per-user scoping: non-service callers may only read their own requests.
	if !middleware.IsServiceRequest(r.Context()) {
		if authUID := middleware.GetUserID(r.Context()); authUID != "" && result.UserID.String() != authUID {
			respondJSON(w, http.StatusNotFound, map[string]string{"error": "removal request not found"})
			return
		}
	}

	respondJSON(w, http.StatusOK, result)
}

// GetStats handles GET /api/v1/footprint/stats
func (h *FootprintHandler) GetStats(w http.ResponseWriter, r *http.Request) {
	if h.scanner == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "footprint scanner not available"})
		return
	}
	respondJSON(w, http.StatusOK, h.scanner.GetStats())
}
