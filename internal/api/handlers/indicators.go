package handlers

import (
	"net/http"
	"regexp"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// indicatorValueHashPattern matches a SHA-256 hex digest (the indicator
// value_hash form returned by the check endpoints).
var indicatorValueHashPattern = regexp.MustCompile(`^[0-9a-f]{64}$`)

// IndicatorsHandler serves single-indicator lookups on the /indicators
// path-alias surface. (The list alias GET /api/v1/indicators is served by
// IntelligenceHandler.List; this handler adds GET /api/v1/indicators/{id}.)
type IndicatorsHandler struct {
	repos  *repository.Repositories
	logger *logger.Logger
}

// NewIndicatorsHandler creates a new IndicatorsHandler
func NewIndicatorsHandler(repos *repository.Repositories, log *logger.Logger) *IndicatorsHandler {
	return &IndicatorsHandler{
		repos:  repos,
		logger: log.WithComponent("indicators"),
	}
}

// GetByID handles GET /api/v1/indicators/{id}. The path parameter is the
// indicator UUID; a 64-character hex value is also accepted and resolved as
// the indicator's SHA-256 value hash (the form clients receive from the
// check endpoints). The response body is a single indicator object in the
// same JSON shape as the items of the list endpoint.
func (h *IndicatorsHandler) GetByID(w http.ResponseWriter, r *http.Request) {
	if h.repos == nil || h.repos.Indicators == nil {
		h.logger.Error().Msg("indicator lookup unavailable: repository not configured")
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "indicator storage unavailable"})
		return
	}

	raw := chi.URLParam(r, "id")

	var indicator *models.Indicator
	var err error

	if id, parseErr := uuid.Parse(raw); parseErr == nil {
		indicator, err = h.repos.Indicators.GetByID(r.Context(), id)
	} else if indicatorValueHashPattern.MatchString(raw) {
		// 64-hex: resolve as the indicator value hash.
		indicator, err = h.repos.Indicators.GetByHash(r.Context(), raw)
	} else {
		respondJSON(w, http.StatusBadRequest, map[string]string{
			"error": "id must be an indicator UUID or a SHA-256 value hash",
		})
		return
	}

	if err != nil {
		h.logger.Error().Err(err).Str("id", raw).Msg("failed to fetch indicator")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to fetch indicator"})
		return
	}
	if indicator == nil {
		respondJSON(w, http.StatusNotFound, map[string]string{"error": "indicator not found"})
		return
	}

	respondJSON(w, http.StatusOK, indicator)
}
