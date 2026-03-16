package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/pkg/logger"
)

// WebhookHandler handles webhook endpoints
type WebhookHandler struct {
	service *services.WebhookService
	logger  *logger.Logger
}

// NewWebhookHandler creates a new WebhookHandler
func NewWebhookHandler(log *logger.Logger, svc *services.WebhookService) *WebhookHandler {
	return &WebhookHandler{
		service: svc,
		logger:  log.WithComponent("webhook-handler"),
	}
}

// List handles GET /api/v1/webhooks
func (h *WebhookHandler) List(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "webhook service not available"})
		return
	}
	webhooks, err := h.service.ListWebhooks(r.Context())
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, webhooks)
}

// Get handles GET /api/v1/webhooks/{id}
func (h *WebhookHandler) Get(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "webhook service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid webhook ID"})
		return
	}
	webhook, err := h.service.GetWebhook(r.Context(), id)
	if err != nil {
		respondJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, webhook)
}

// Create handles POST /api/v1/webhooks
func (h *WebhookHandler) Create(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "webhook service not available"})
		return
	}
	var webhook models.Webhook
	if err := json.NewDecoder(r.Body).Decode(&webhook); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	if err := h.service.RegisterWebhook(r.Context(), &webhook); err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusCreated, webhook)
}

// Update handles PUT /api/v1/webhooks/{id}
func (h *WebhookHandler) Update(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "webhook service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid webhook ID"})
		return
	}
	var webhook models.Webhook
	if err := json.NewDecoder(r.Body).Decode(&webhook); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	webhook.ID = id
	if err := h.service.UpdateWebhook(r.Context(), &webhook); err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, webhook)
}

// Delete handles DELETE /api/v1/webhooks/{id}
func (h *WebhookHandler) Delete(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "webhook service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid webhook ID"})
		return
	}
	if err := h.service.DeleteWebhook(r.Context(), id); err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// Enable handles POST /api/v1/webhooks/{id}/enable
func (h *WebhookHandler) Enable(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "webhook service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid webhook ID"})
		return
	}
	if err := h.service.EnableWebhook(r.Context(), id); err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, map[string]string{"status": "enabled"})
}

// Disable handles POST /api/v1/webhooks/{id}/disable
func (h *WebhookHandler) Disable(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "webhook service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid webhook ID"})
		return
	}
	if err := h.service.DisableWebhook(r.Context(), id); err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, map[string]string{"status": "disabled"})
}

// Test handles POST /api/v1/webhooks/{id}/test
func (h *WebhookHandler) Test(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "webhook service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid webhook ID"})
		return
	}
	result, err := h.service.TestWebhook(r.Context(), id)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, result)
}

// GetStats handles GET /api/v1/webhooks/stats
func (h *WebhookHandler) GetStats(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "webhook service not available"})
		return
	}
	respondJSON(w, http.StatusOK, h.service.GetStats(r.Context()))
}

// RotateSecret handles POST /api/v1/webhooks/{id}/rotate-secret
func (h *WebhookHandler) RotateSecret(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "webhook service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid webhook ID"})
		return
	}
	newSecret, err := h.service.RotateSecret(r.Context(), id)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, map[string]string{"secret": newSecret})
}
