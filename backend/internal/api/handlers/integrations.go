package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/pkg/logger"
)

// IntegrationsHandler handles integration endpoints (Slack, Teams, PagerDuty)
type IntegrationsHandler struct {
	service *services.IntegrationService
	logger  *logger.Logger
}

// NewIntegrationsHandler creates a new IntegrationsHandler
func NewIntegrationsHandler(svc *services.IntegrationService, log *logger.Logger) *IntegrationsHandler {
	return &IntegrationsHandler{
		service: svc,
		logger:  log.WithComponent("integrations-handler"),
	}
}

// List handles GET /api/v1/integrations
func (h *IntegrationsHandler) List(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "integration service not available"})
		return
	}

	var intType *models.IntegrationType
	if t := r.URL.Query().Get("type"); t != "" {
		it := models.IntegrationType(t)
		intType = &it
	}

	integrations, err := h.service.ListIntegrations(r.Context(), intType)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, integrations)
}

// Get handles GET /api/v1/integrations/{id}
func (h *IntegrationsHandler) Get(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "integration service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid integration ID"})
		return
	}
	integration, err := h.service.GetIntegration(r.Context(), id)
	if err != nil {
		respondJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, integration)
}

// Create handles POST /api/v1/integrations
func (h *IntegrationsHandler) Create(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "integration service not available"})
		return
	}
	var integration models.Integration
	if err := json.NewDecoder(r.Body).Decode(&integration); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	result, err := h.service.CreateIntegration(r.Context(), &integration)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusCreated, result)
}

// Update handles PATCH /api/v1/integrations/{id}
func (h *IntegrationsHandler) Update(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "integration service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid integration ID"})
		return
	}
	var integration models.Integration
	if err := json.NewDecoder(r.Body).Decode(&integration); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	result, err := h.service.UpdateIntegration(r.Context(), id, &integration)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, result)
}

// Delete handles DELETE /api/v1/integrations/{id}
func (h *IntegrationsHandler) Delete(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "integration service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid integration ID"})
		return
	}
	if err := h.service.DeleteIntegration(r.Context(), id); err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// Enable handles POST /api/v1/integrations/{id}/enable
func (h *IntegrationsHandler) Enable(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "integration service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid integration ID"})
		return
	}
	if err := h.service.EnableIntegration(r.Context(), id); err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, map[string]string{"status": "enabled"})
}

// Disable handles POST /api/v1/integrations/{id}/disable
func (h *IntegrationsHandler) Disable(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "integration service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid integration ID"})
		return
	}
	if err := h.service.DisableIntegration(r.Context(), id); err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, map[string]string{"status": "disabled"})
}

// Test handles POST /api/v1/integrations/{id}/test
func (h *IntegrationsHandler) Test(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "integration service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid integration ID"})
		return
	}
	result, err := h.service.TestIntegration(r.Context(), id)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, result)
}

// GetStats handles GET /api/v1/integrations/{id}/stats
func (h *IntegrationsHandler) GetStats(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "integration service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid integration ID"})
		return
	}
	stats, err := h.service.GetIntegrationStats(r.Context(), id)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, stats)
}

// GetDeliveries handles GET /api/v1/integrations/{id}/deliveries
func (h *IntegrationsHandler) GetDeliveries(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "integration service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid integration ID"})
		return
	}
	limit := 50
	if l := r.URL.Query().Get("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil {
			limit = parsed
		}
	}
	deliveries, err := h.service.ListDeliveries(r.Context(), id, limit)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, deliveries)
}
