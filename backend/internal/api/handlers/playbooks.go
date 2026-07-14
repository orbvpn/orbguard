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

// PlaybookHandler handles playbook endpoints
type PlaybookHandler struct {
	service *services.PlaybookService
	logger  *logger.Logger
}

// NewPlaybookHandler creates a new PlaybookHandler
func NewPlaybookHandler(log *logger.Logger, svc *services.PlaybookService) *PlaybookHandler {
	return &PlaybookHandler{
		service: svc,
		logger:  log.WithComponent("playbook-handler"),
	}
}

// List handles GET /api/v1/playbooks
func (h *PlaybookHandler) List(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "playbook service not available"})
		return
	}
	playbooks, err := h.service.ListPlaybooks(r.Context())
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, playbooks)
}

// Get handles GET /api/v1/playbooks/{id}
func (h *PlaybookHandler) Get(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "playbook service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid playbook ID"})
		return
	}
	playbook, err := h.service.GetPlaybook(r.Context(), id)
	if err != nil {
		respondJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, playbook)
}

// Create handles POST /api/v1/playbooks
func (h *PlaybookHandler) Create(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "playbook service not available"})
		return
	}
	var playbook models.Playbook
	if err := json.NewDecoder(r.Body).Decode(&playbook); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	if err := h.service.RegisterPlaybook(r.Context(), &playbook); err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusCreated, playbook)
}

// Update handles PUT /api/v1/playbooks/{id}
func (h *PlaybookHandler) Update(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "playbook service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid playbook ID"})
		return
	}
	var playbook models.Playbook
	if err := json.NewDecoder(r.Body).Decode(&playbook); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	playbook.ID = id
	if err := h.service.UpdatePlaybook(r.Context(), &playbook); err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, playbook)
}

// Delete handles DELETE /api/v1/playbooks/{id}
func (h *PlaybookHandler) Delete(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "playbook service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid playbook ID"})
		return
	}
	if err := h.service.DeletePlaybook(r.Context(), id); err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// Enable handles POST /api/v1/playbooks/{id}/enable
func (h *PlaybookHandler) Enable(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "playbook service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid playbook ID"})
		return
	}
	if err := h.service.EnablePlaybook(r.Context(), id); err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, map[string]string{"status": "enabled"})
}

// Disable handles POST /api/v1/playbooks/{id}/disable
func (h *PlaybookHandler) Disable(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "playbook service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid playbook ID"})
		return
	}
	if err := h.service.DisablePlaybook(r.Context(), id); err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, map[string]string{"status": "disabled"})
}

// Execute handles POST /api/v1/playbooks/{id}/execute
func (h *PlaybookHandler) Execute(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "playbook service not available"})
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid playbook ID"})
		return
	}
	var req struct {
		InputData map[string]interface{} `json:"input_data"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)

	execution, err := h.service.TriggerManually(r.Context(), id, req.InputData)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, execution)
}

// GetExecutions handles GET /api/v1/playbooks/executions
func (h *PlaybookHandler) GetExecutions(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "playbook service not available"})
		return
	}
	limit := 50
	if l := r.URL.Query().Get("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil {
			limit = parsed
		}
	}

	var playbookID *uuid.UUID
	if idStr := r.URL.Query().Get("playbook_id"); idStr != "" {
		if id, err := uuid.Parse(idStr); err == nil {
			playbookID = &id
		}
	}

	executions, err := h.service.GetExecutions(r.Context(), playbookID, limit)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, executions)
}

// GetStats handles GET /api/v1/playbooks/stats
func (h *PlaybookHandler) GetStats(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "playbook service not available"})
		return
	}
	respondJSON(w, http.StatusOK, h.service.GetStats(r.Context()))
}

// GetTemplates handles GET /api/v1/playbooks/templates
func (h *PlaybookHandler) GetTemplates(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "playbook service not available"})
		return
	}
	respondJSON(w, http.StatusOK, h.service.GetTemplates())
}

// CreateFromTemplate handles POST /api/v1/playbooks/from-template
func (h *PlaybookHandler) CreateFromTemplate(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "playbook service not available"})
		return
	}
	var req struct {
		TemplateID string `json:"template_id"`
		Name       string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.TemplateID == "" || req.Name == "" {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "template_id and name are required"})
		return
	}
	playbook, err := h.service.CreateFromTemplate(r.Context(), req.TemplateID, req.Name)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusCreated, playbook)
}
