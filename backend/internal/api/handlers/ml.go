package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// MLHandler handles Machine Learning API requests
type MLHandler struct {
	service *services.MLService
	logger  *logger.Logger
}

// NewMLHandler creates a new ML handler
func NewMLHandler(service *services.MLService, log *logger.Logger) *MLHandler {
	return &MLHandler{
		service: service,
		logger:  log.WithComponent("ml-handler"),
	}
}

// EnrichIndicator enriches an indicator with ML analysis
func (h *MLHandler) EnrichIndicator(w http.ResponseWriter, r *http.Request) {
	idStr := chi.URLParam(r, "id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid indicator ID", err)
		return
	}

	result, err := h.service.AnalyzeIndicator(r.Context(), id)
	if err != nil {
		h.respondError(w, http.StatusInternalServerError, "failed to analyze indicator", err)
		return
	}

	if result == nil {
		h.respondError(w, http.StatusNotFound, "indicator not found", nil)
		return
	}

	h.respondJSON(w, http.StatusOK, result)
}

// mlBatchRequest is the shared request body for batch ML operations.
// Either indicator_ids or filter fields select the input set; when
// indicator_ids is non-empty the filter fields are ignored.
type mlBatchRequest struct {
	IndicatorIDs []uuid.UUID `json:"indicator_ids"`

	// Filter-based selection (used when indicator_ids is empty)
	Types         []models.IndicatorType `json:"types,omitempty"`
	Severities    []models.Severity      `json:"severities,omitempty"`
	Tags          []string               `json:"tags,omitempty"`
	MinConfidence float64                `json:"min_confidence,omitempty"`
	Limit         int                    `json:"limit,omitempty"`

	// K is the number of clusters (clustering only)
	K int `json:"k,omitempty"`
}

const (
	mlMaxIndicatorIDs   = 1000
	mlDefaultBatchLimit = 1000
	mlMaxBatchLimit     = 10000
)

// fetchIndicatorsForBatch resolves the indicator set for a batch ML request,
// either by explicit IDs or by filter. The second return value lists
// requested IDs that do not exist.
func (h *MLHandler) fetchIndicatorsForBatch(ctx context.Context, req *mlBatchRequest) ([]*models.Indicator, []uuid.UUID, error) {
	if len(req.IndicatorIDs) > 0 {
		if len(req.IndicatorIDs) > mlMaxIndicatorIDs {
			return nil, nil, &mlRequestError{message: "too many indicator IDs", status: http.StatusBadRequest}
		}
		return h.service.GetIndicatorsByIDs(ctx, req.IndicatorIDs)
	}

	limit := req.Limit
	if limit <= 0 {
		limit = mlDefaultBatchLimit
	}
	if limit > mlMaxBatchLimit {
		limit = mlMaxBatchLimit
	}

	filter := repository.IndicatorFilter{
		Types:         req.Types,
		Severities:    req.Severities,
		Tags:          req.Tags,
		MinConfidence: req.MinConfidence,
		Limit:         limit,
	}

	indicators, err := h.service.ListIndicators(ctx, filter)
	return indicators, nil, err
}

// mlRequestError is a request-level error with an associated HTTP status.
type mlRequestError struct {
	message string
	status  int
}

func (e *mlRequestError) Error() string { return e.message }

// respondMLError maps ML service errors to HTTP responses, handling the
// explicit "models not trained" state with a 409.
func (h *MLHandler) respondMLError(w http.ResponseWriter, err error, fallbackMessage string) {
	var notTrained *services.ModelsNotTrainedError
	if errors.As(err, &notTrained) {
		h.logger.Warn().Str("model", notTrained.ModelType).Int("indicators_needed", notTrained.IndicatorsNeeded).Msg("ml operation requested before models trained")
		h.respondJSON(w, http.StatusConflict, map[string]interface{}{
			"error":             "models_not_trained",
			"model":             notTrained.ModelType,
			"indicators_needed": notTrained.IndicatorsNeeded,
			"details":           notTrained.Error(),
		})
		return
	}

	var reqErr *mlRequestError
	if errors.As(err, &reqErr) {
		h.respondError(w, reqErr.status, reqErr.message, nil)
		return
	}

	h.respondError(w, http.StatusInternalServerError, fallbackMessage, err)
}

// DetectAnomalies runs anomaly detection on indicators selected by ID or filter
func (h *MLHandler) DetectAnomalies(w http.ResponseWriter, r *http.Request) {
	var req mlBatchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body", err)
		return
	}

	indicators, missing, err := h.fetchIndicatorsForBatch(r.Context(), &req)
	if err != nil {
		h.respondMLError(w, err, "failed to fetch indicators")
		return
	}

	if len(req.IndicatorIDs) > 0 && len(indicators) == 0 {
		h.respondError(w, http.StatusNotFound, "none of the requested indicators exist", nil)
		return
	}

	result, err := h.service.DetectAnomalies(r.Context(), indicators)
	if err != nil {
		h.respondMLError(w, err, "anomaly detection failed")
		return
	}

	response := map[string]interface{}{
		"result":    result,
		"processed": len(indicators),
	}
	if len(missing) > 0 {
		response["missing_indicator_ids"] = missing
	}

	h.respondJSON(w, http.StatusOK, response)
}

// ClusterIndicators clusters indicators into groups
func (h *MLHandler) ClusterIndicators(w http.ResponseWriter, r *http.Request) {
	var req mlBatchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body", err)
		return
	}

	if req.K <= 0 {
		req.K = 5 // Default
	}
	if req.K < 2 {
		h.respondError(w, http.StatusBadRequest, "k must be at least 2", nil)
		return
	}

	indicators, missing, err := h.fetchIndicatorsForBatch(r.Context(), &req)
	if err != nil {
		h.respondMLError(w, err, "failed to fetch indicators")
		return
	}

	if len(indicators) < req.K {
		h.respondJSON(w, http.StatusUnprocessableEntity, map[string]interface{}{
			"error":            "insufficient_indicators",
			"details":          "clustering requires at least k indicators",
			"k":                req.K,
			"indicators_found": len(indicators),
		})
		return
	}

	result, err := h.service.ClusterIndicators(r.Context(), indicators, req.K)
	if err != nil {
		h.respondMLError(w, err, "clustering failed")
		return
	}

	response := map[string]interface{}{
		"result":    result,
		"processed": len(indicators),
		"k":         req.K,
	}
	if len(missing) > 0 {
		response["missing_indicator_ids"] = missing
	}

	h.respondJSON(w, http.StatusOK, response)
}

// PredictSeverity predicts severity for indicators selected by ID or filter
func (h *MLHandler) PredictSeverity(w http.ResponseWriter, r *http.Request) {
	var req mlBatchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body", err)
		return
	}

	indicators, missing, err := h.fetchIndicatorsForBatch(r.Context(), &req)
	if err != nil {
		h.respondMLError(w, err, "failed to fetch indicators")
		return
	}

	if len(req.IndicatorIDs) > 0 && len(indicators) == 0 {
		h.respondError(w, http.StatusNotFound, "none of the requested indicators exist", nil)
		return
	}

	result, err := h.service.PredictSeverity(r.Context(), indicators)
	if err != nil {
		h.respondMLError(w, err, "severity prediction failed")
		return
	}

	response := map[string]interface{}{
		"result":    result,
		"processed": len(indicators),
	}
	if len(missing) > 0 {
		response["missing_indicator_ids"] = missing
	}

	h.respondJSON(w, http.StatusOK, response)
}

// ExtractEntities extracts entities from text
func (h *MLHandler) ExtractEntities(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Text string `json:"text"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body", err)
		return
	}

	if req.Text == "" {
		h.respondError(w, http.StatusBadRequest, "text is required", nil)
		return
	}

	result := h.service.ExtractEntities(req.Text)
	h.respondJSON(w, http.StatusOK, result)
}

// ExtractIndicators extracts IOCs from text
func (h *MLHandler) ExtractIndicators(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Text string `json:"text"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body", err)
		return
	}

	if req.Text == "" {
		h.respondError(w, http.StatusBadRequest, "text is required", nil)
		return
	}

	indicators := h.service.ExtractIndicatorsFromText(req.Text)

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"indicators": indicators,
		"count":      len(indicators),
	})
}

// Train trains all ML models
func (h *MLHandler) Train(w http.ResponseWriter, r *http.Request) {
	result, err := h.service.Train(r.Context())
	if err != nil {
		h.respondError(w, http.StatusInternalServerError, "training failed", err)
		return
	}

	h.respondJSON(w, http.StatusOK, result)
}

// TrainModel trains a specific model
func (h *MLHandler) TrainModel(w http.ResponseWriter, r *http.Request) {
	modelType := chi.URLParam(r, "model")

	result, err := h.service.TrainModel(r.Context(), modelType)
	if err != nil {
		h.respondError(w, http.StatusInternalServerError, "training failed", err)
		return
	}

	h.respondJSON(w, http.StatusOK, result)
}

// GetStats returns ML service statistics
func (h *MLHandler) GetStats(w http.ResponseWriter, r *http.Request) {
	stats := h.service.GetStats()
	h.respondJSON(w, http.StatusOK, stats)
}

// mlAnomaliesDefaultLimit bounds how many recent indicators GET /ml/anomalies
// scores by default; ?limit= overrides up to mlMaxBatchLimit.
const mlAnomaliesDefaultLimit = 500

// GetAnomalies handles GET /api/v1/ml/anomalies. It scores recent indicators
// with the trained isolation forest and returns the anomalous ones. Responds
// 409 models_not_trained while the anomaly model is untrained.
func (h *MLHandler) GetAnomalies(w http.ResponseWriter, r *http.Request) {
	limit := mlAnomaliesDefaultLimit
	if raw := r.URL.Query().Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed <= 0 {
			h.respondError(w, http.StatusBadRequest, "limit must be a positive integer", nil)
			return
		}
		limit = parsed
		if limit > mlMaxBatchLimit {
			limit = mlMaxBatchLimit
		}
	}

	indicators, err := h.service.ListIndicators(r.Context(), repository.IndicatorFilter{Limit: limit})
	if err != nil {
		h.respondError(w, http.StatusInternalServerError, "failed to fetch indicators", err)
		return
	}

	result, err := h.service.DetectAnomalies(r.Context(), indicators)
	if err != nil {
		h.respondMLError(w, err, "anomaly detection failed")
		return
	}

	byID := make(map[uuid.UUID]*models.Indicator, len(indicators))
	for _, ind := range indicators {
		byID[ind.ID] = ind
	}

	anomalies := make([]map[string]interface{}, 0, result.AnomalyCount)
	for _, score := range result.Scores {
		if !score.IsAnomaly {
			continue
		}
		entry := map[string]interface{}{
			"indicator_id": score.IndicatorID,
			"score":        score.Score,
			"is_anomaly":   score.IsAnomaly,
			"threshold":    score.Threshold,
			"confidence":   score.Confidence,
			"contributors": score.Contributors,
			"method":       score.Method,
			"computed_at":  score.ComputedAt,
		}
		if ind, ok := byID[score.IndicatorID]; ok {
			entry["value"] = ind.Value
			entry["type"] = ind.Type
			entry["severity"] = ind.Severity
		}
		anomalies = append(anomalies, entry)
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"anomalies":  anomalies,
		"count":      len(anomalies),
		"processed":  result.TotalProcessed,
		"statistics": result.Statistics,
	})
}

// GetInsights handles GET /api/v1/ml/insights. Insights are derived from real
// indicator-store statistics and the trained model state — nothing is
// fabricated; an empty store yields an empty insight list.
func (h *MLHandler) GetInsights(w http.ResponseWriter, r *http.Request) {
	insights, err := h.service.GenerateInsights(r.Context())
	if err != nil {
		h.respondError(w, http.StatusInternalServerError, "failed to generate insights", err)
		return
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"insights": insights,
		"count":    len(insights),
	})
}

// GetModels handles GET /api/v1/ml/models, emitting the real in-memory model
// registry under the "models" key the client parses.
func (h *MLHandler) GetModels(w http.ResponseWriter, r *http.Request) {
	stats := h.service.GetStats()

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"models":          stats.Models,
		"count":           len(stats.Models),
		"models_loaded":   stats.ModelsLoaded,
		"last_trained_at": stats.LastTrainedAt,
	})
}

// GetModelInfo returns information about a specific model
func (h *MLHandler) GetModelInfo(w http.ResponseWriter, r *http.Request) {
	modelType := chi.URLParam(r, "model")

	info := h.service.GetModelInfo(modelType)
	if info == nil {
		h.respondError(w, http.StatusNotFound, "model not found", nil)
		return
	}

	h.respondJSON(w, http.StatusOK, info)
}

// GetFeatures returns the list of features used by ML models
func (h *MLHandler) GetFeatures(w http.ResponseWriter, r *http.Request) {
	features := h.service.GetFeatureNames()

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"features": features,
		"count":    len(features),
	})
}

// AnalyzeValue performs ML analysis on a raw value
func (h *MLHandler) AnalyzeValue(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Value string               `json:"value"`
		Type  models.IndicatorType `json:"type"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body", err)
		return
	}

	if req.Value == "" {
		h.respondError(w, http.StatusBadRequest, "value is required", nil)
		return
	}

	// Create temporary indicator for analysis
	indicator := &models.Indicator{
		ID:    uuid.New(),
		Value: req.Value,
		Type:  req.Type,
	}

	result, err := h.service.EnrichIndicator(r.Context(), indicator)
	if err != nil {
		h.respondError(w, http.StatusInternalServerError, "analysis failed", err)
		return
	}

	h.respondJSON(w, http.StatusOK, result)
}

// respondJSON sends a JSON response
func (h *MLHandler) respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(data); err != nil {
		h.logger.Error().Err(err).Msg("failed to encode JSON response")
	}
}

// respondError sends an error response
func (h *MLHandler) respondError(w http.ResponseWriter, status int, message string, err error) {
	if err != nil {
		h.logger.Error().Err(err).Msg(message)
	}

	h.respondJSON(w, status, map[string]interface{}{
		"error": message,
		"details": func() string {
			if err != nil {
				return err.Error()
			}
			return ""
		}(),
	})
}
