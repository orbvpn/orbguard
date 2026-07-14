package services

import (
	"context"
	"fmt"
	"math"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// MLService orchestrates all ML operations for threat intelligence
type MLService struct {
	featureExtractor *FeatureExtractor
	isolationForest  *IsolationForest
	kmeans           *KMeans
	randomForest     *RandomForest
	entityExtractor  *EntityExtractor
	repos            *repository.Repositories
	cache            *cache.RedisCache
	logger           *logger.Logger

	// Training state
	minTrainingSize    int
	lastTrainedAt      time.Time
	trainingInProgress atomic.Bool
	trainingMu         sync.Mutex

	// Stats
	totalPredictions atomic.Int64
	totalAnomalies   atomic.Int64
	totalEntities    atomic.Int64
	cacheHits        atomic.Int64
	cacheMisses      atomic.Int64
}

// MLServiceConfig holds configuration for the ML service
type MLServiceConfig struct {
	IsolationForest IsolationForestConfig
	KMeans          KMeansConfig
	RandomForest    RandomForestConfig
	AutoTrain       bool
	TrainInterval   time.Duration
	MinTrainingSize int
}

// DefaultMLServiceConfig returns default configuration
func DefaultMLServiceConfig() MLServiceConfig {
	return MLServiceConfig{
		IsolationForest: DefaultIsolationForestConfig(),
		KMeans:          DefaultKMeansConfig(),
		RandomForest:    DefaultRandomForestConfig(),
		AutoTrain:       true,
		TrainInterval:   24 * time.Hour,
		MinTrainingSize: 100,
	}
}

// NewMLService creates a new ML service
func NewMLService(
	config MLServiceConfig,
	repos *repository.Repositories,
	c *cache.RedisCache,
	log *logger.Logger,
) *MLService {
	minTrainingSize := config.MinTrainingSize
	if minTrainingSize <= 0 {
		minTrainingSize = DefaultMLServiceConfig().MinTrainingSize
	}

	return &MLService{
		featureExtractor: NewFeatureExtractor(log),
		isolationForest:  NewIsolationForest(config.IsolationForest, log),
		kmeans:           NewKMeans(config.KMeans, log),
		randomForest:     NewRandomForest(config.RandomForest, log),
		entityExtractor:  NewEntityExtractor(log),
		repos:            repos,
		cache:            c,
		logger:           log.WithComponent("ml-service"),
		minTrainingSize:  minTrainingSize,
	}
}

// ModelsNotTrainedError indicates that a requested ML operation requires a
// trained model, but training has not (yet) happened — typically because the
// indicator store does not hold enough data, or the auto-train loop has not
// run since startup (models are in-memory only).
type ModelsNotTrainedError struct {
	// ModelType is the model the operation required.
	ModelType string
	// IndicatorsNeeded is how many more indicators are needed before
	// training can start (0 means enough data exists and training is
	// pending or in progress).
	IndicatorsNeeded int
}

// Error implements the error interface.
func (e *ModelsNotTrainedError) Error() string {
	return fmt.Sprintf("ml model %q is not trained yet (%d more indicators needed)", e.ModelType, e.IndicatorsNeeded)
}

// modelsNotTrainedError builds a ModelsNotTrainedError, computing how many
// more indicators are required from the current store size.
func (s *MLService) modelsNotTrainedError(ctx context.Context, modelType string) *ModelsNotTrainedError {
	needed := s.minTrainingSize
	if s.repos != nil && s.repos.Indicators != nil {
		if _, total, err := s.repos.Indicators.List(ctx, repository.IndicatorFilter{Limit: 1}); err == nil {
			remaining := s.minTrainingSize - int(total)
			if remaining < 0 {
				remaining = 0
			}
			needed = remaining
		} else {
			s.logger.Warn().Err(err).Msg("failed to count indicators for training-state report")
		}
	}

	return &ModelsNotTrainedError{
		ModelType:        modelType,
		IndicatorsNeeded: needed,
	}
}

// GetIndicatorsByIDs fetches indicators by ID for batch ML operations.
// Missing IDs are returned separately; database errors abort the fetch.
func (s *MLService) GetIndicatorsByIDs(ctx context.Context, ids []uuid.UUID) ([]*models.Indicator, []uuid.UUID, error) {
	if s.repos == nil || s.repos.Indicators == nil {
		return nil, nil, fmt.Errorf("indicator repository is not available")
	}

	indicators := make([]*models.Indicator, 0, len(ids))
	missing := make([]uuid.UUID, 0)

	for _, id := range ids {
		indicator, err := s.repos.Indicators.GetByID(ctx, id)
		if err != nil {
			return nil, nil, err
		}
		if indicator == nil {
			missing = append(missing, id)
			continue
		}
		indicators = append(indicators, indicator)
	}

	return indicators, missing, nil
}

// ListIndicators fetches indicators matching a filter for batch ML operations.
func (s *MLService) ListIndicators(ctx context.Context, filter repository.IndicatorFilter) ([]*models.Indicator, error) {
	if s.repos == nil || s.repos.Indicators == nil {
		return nil, fmt.Errorf("indicator repository is not available")
	}

	indicators, _, err := s.repos.Indicators.List(ctx, filter)
	return indicators, err
}

// EnrichIndicator enriches an indicator with ML analysis
func (s *MLService) EnrichIndicator(ctx context.Context, indicator *models.Indicator) (*models.MLEnrichmentResult, error) {
	startTime := time.Now()
	s.totalPredictions.Add(1)

	result := &models.MLEnrichmentResult{
		IndicatorID: indicator.ID,
		EnrichedAt:  time.Now(),
	}

	// Extract features
	features := s.featureExtractor.ExtractFeatures(indicator)
	result.Features = features

	// Convert to feature vector
	vector := s.featureExtractor.FeaturesToVector(indicator.ID, indicator.Type, features)

	// Anomaly detection
	if s.isolationForest.IsTrained() {
		anomalyScore := s.isolationForest.PredictOne(vector)
		result.AnomalyScore = &anomalyScore
		if anomalyScore.IsAnomaly {
			s.totalAnomalies.Add(1)
		}
	}

	// Cluster assignment
	if s.kmeans.IsTrained() {
		clusterResult := s.kmeans.Predict([]*models.FeatureVector{vector})
		if len(clusterResult.Assignments) > 0 {
			result.ClusterAssignment = &clusterResult.Assignments[0]
		}
	}

	// Severity prediction
	if s.randomForest.IsTrained() {
		predictions := s.randomForest.Predict([]*models.FeatureVector{vector})
		if len(predictions) > 0 {
			result.SeverityPrediction = &predictions[0]
		}
	}

	result.ProcessingTime = time.Since(startTime)

	return result, nil
}

// EnrichBatch enriches multiple indicators
func (s *MLService) EnrichBatch(ctx context.Context, indicators []*models.Indicator) ([]*models.MLEnrichmentResult, error) {
	results := make([]*models.MLEnrichmentResult, len(indicators))

	for i, ind := range indicators {
		result, err := s.EnrichIndicator(ctx, ind)
		if err != nil {
			s.logger.Error().Err(err).Str("indicator_id", ind.ID.String()).Msg("failed to enrich indicator")
			continue
		}
		results[i] = result
	}

	return results, nil
}

// DetectAnomalies runs anomaly detection on indicators. Returns
// ModelsNotTrainedError when the isolation forest has not been trained.
func (s *MLService) DetectAnomalies(ctx context.Context, indicators []*models.Indicator) (*models.AnomalyDetectionResult, error) {
	startTime := time.Now()

	if !s.isolationForest.IsTrained() {
		return nil, s.modelsNotTrainedError(ctx, "isolation_forest")
	}

	if len(indicators) == 0 {
		return &models.AnomalyDetectionResult{
			TotalProcessed: 0,
			AnomalyCount:   0,
			Scores:         []models.AnomalyScore{},
			ProcessingTime: time.Since(startTime),
		}, nil
	}

	// Extract feature vectors
	vectors := s.featureExtractor.ExtractBatchFeatures(indicators)

	// Run anomaly detection
	scores := s.isolationForest.Predict(vectors)

	// Calculate statistics
	anomalyCount := 0
	var sum, sumSq, min, max float64
	min = 1.0

	for _, score := range scores {
		if score.IsAnomaly {
			anomalyCount++
			s.totalAnomalies.Add(1)
		}
		sum += score.Score
		sumSq += score.Score * score.Score
		if score.Score < min {
			min = score.Score
		}
		if score.Score > max {
			max = score.Score
		}
	}

	n := float64(len(scores))
	mean := 0.0
	stdDev := 0.0
	anomalyRate := 0.0
	if n > 0 {
		mean = sum / n
		variance := (sumSq / n) - (mean * mean)
		if variance > 0 {
			stdDev = math.Sqrt(variance)
		}
		anomalyRate = float64(anomalyCount) / n
	} else {
		min = 0
	}

	s.totalPredictions.Add(int64(len(scores)))

	return &models.AnomalyDetectionResult{
		TotalProcessed: len(indicators),
		AnomalyCount:   anomalyCount,
		Scores:         scores,
		Statistics: models.AnomalyStats{
			MeanScore:   mean,
			StdDevScore: stdDev,
			MinScore:    min,
			MaxScore:    max,
			AnomalyRate: anomalyRate,
		},
		ProcessingTime: time.Since(startTime),
	}, nil
}

// ClusterIndicators clusters indicators into groups. Clustering trains an
// ad-hoc K-Means model on the provided indicators, so it requires at least k
// data points but no pre-trained model.
func (s *MLService) ClusterIndicators(ctx context.Context, indicators []*models.Indicator, k int) (*models.ClusteringResult, error) {
	if k < 2 {
		return nil, fmt.Errorf("k must be at least 2, got %d", k)
	}
	if len(indicators) < k {
		return nil, fmt.Errorf("clustering requires at least k=%d indicators, got %d", k, len(indicators))
	}

	// Extract feature vectors
	vectors := s.featureExtractor.ExtractBatchFeatures(indicators)

	// Create temporary K-Means with specified k
	config := DefaultKMeansConfig()
	config.K = k
	km := NewKMeans(config, s.logger)

	// Train and predict
	if err := km.Train(vectors); err != nil {
		return nil, err
	}

	return km.Predict(vectors), nil
}

// PredictSeverity predicts severity for indicators. Returns
// ModelsNotTrainedError when the random forest has not been trained.
func (s *MLService) PredictSeverity(ctx context.Context, indicators []*models.Indicator) (*models.SeverityPredictionResult, error) {
	startTime := time.Now()

	if !s.randomForest.IsTrained() {
		return nil, s.modelsNotTrainedError(ctx, "random_forest")
	}

	if len(indicators) == 0 {
		return &models.SeverityPredictionResult{
			TotalProcessed: 0,
			Predictions:    []models.SeverityPrediction{},
			ProcessingTime: time.Since(startTime),
		}, nil
	}

	// Extract feature vectors
	vectors := s.featureExtractor.ExtractBatchFeatures(indicators)

	// Run predictions
	predictions := s.randomForest.Predict(vectors)
	s.totalPredictions.Add(int64(len(predictions)))

	return &models.SeverityPredictionResult{
		TotalProcessed: len(indicators),
		Predictions:    predictions,
		ProcessingTime: time.Since(startTime),
	}, nil
}

// ExtractEntities extracts entities from text
func (s *MLService) ExtractEntities(text string) *models.EntityExtractionResult {
	result := s.entityExtractor.ExtractEntities(text)
	s.totalEntities.Add(int64(len(result.Entities)))
	return result
}

// ExtractIndicatorsFromText extracts IOCs from text
func (s *MLService) ExtractIndicatorsFromText(text string) []models.ExtractedIndicator {
	return s.entityExtractor.ExtractIndicators(text)
}

// Train trains all ML models on existing data
func (s *MLService) Train(ctx context.Context) (*models.MLTrainingResult, error) {
	if !s.trainingInProgress.CompareAndSwap(false, true) {
		return &models.MLTrainingResult{
			Success: false,
			Error:   "training already in progress",
		}, nil
	}
	defer s.trainingInProgress.Store(false)

	s.trainingMu.Lock()
	defer s.trainingMu.Unlock()

	startTime := time.Now()

	// Fetch training data from database
	var indicators []*models.Indicator
	var err error

	if s.repos != nil {
		filter := repository.IndicatorFilter{
			Limit:  10000,
			Offset: 0,
		}
		indicators, _, err = s.repos.Indicators.List(ctx, filter)
		if err != nil {
			return &models.MLTrainingResult{
				Success: false,
				Error:   err.Error(),
			}, err
		}
	}

	if len(indicators) < s.minTrainingSize {
		return &models.MLTrainingResult{
			Success: false,
			Error:   "insufficient training data",
		}, nil
	}

	// Extract features
	vectors := s.featureExtractor.ExtractBatchFeatures(indicators)

	// Train Isolation Forest
	if err := s.isolationForest.Train(vectors); err != nil {
		s.logger.Error().Err(err).Msg("failed to train isolation forest")
	}

	// Train K-Means
	optimalK := s.kmeans.OptimalK(vectors, 10)
	kmeansConfig := DefaultKMeansConfig()
	kmeansConfig.K = optimalK
	s.kmeans = NewKMeans(kmeansConfig, s.logger)
	if err := s.kmeans.Train(vectors); err != nil {
		s.logger.Error().Err(err).Msg("failed to train k-means")
	}

	// Train Random Forest (need labels)
	labels := make([]models.Severity, len(indicators))
	for i, ind := range indicators {
		labels[i] = ind.Severity
	}
	if err := s.randomForest.Train(vectors, labels); err != nil {
		s.logger.Error().Err(err).Msg("failed to train random forest")
	}

	s.lastTrainedAt = time.Now()

	return &models.MLTrainingResult{
		ModelType:    "all",
		Version:      "1.0",
		TrainingSize: len(indicators),
		TrainingTime: time.Since(startTime),
		Success:      true,
		Metrics: map[string]float64{
			"isolation_forest_threshold": s.isolationForest.threshold,
			"kmeans_silhouette":          s.kmeans.silhouette,
			"random_forest_accuracy":     s.randomForest.accuracy,
		},
	}, nil
}

// TrainModel trains a specific model
func (s *MLService) TrainModel(ctx context.Context, modelType string) (*models.MLTrainingResult, error) {
	if !s.trainingInProgress.CompareAndSwap(false, true) {
		return &models.MLTrainingResult{
			Success: false,
			Error:   "training already in progress",
		}, nil
	}
	defer s.trainingInProgress.Store(false)

	startTime := time.Now()

	// Fetch training data
	var indicators []*models.Indicator
	var err error

	if s.repos != nil {
		filter := repository.IndicatorFilter{
			Limit:  10000,
			Offset: 0,
		}
		indicators, _, err = s.repos.Indicators.List(ctx, filter)
		if err != nil {
			return nil, err
		}
	}

	if len(indicators) < s.minTrainingSize {
		return &models.MLTrainingResult{
			Success: false,
			Error:   "insufficient training data",
		}, nil
	}

	vectors := s.featureExtractor.ExtractBatchFeatures(indicators)

	result := &models.MLTrainingResult{
		ModelType:    modelType,
		Version:      "1.0",
		TrainingSize: len(indicators),
		Metrics:      make(map[string]float64),
	}

	switch modelType {
	case "isolation_forest", "anomaly":
		if err := s.isolationForest.Train(vectors); err != nil {
			result.Error = err.Error()
		} else {
			result.Success = true
			result.Metrics["threshold"] = s.isolationForest.threshold
		}

	case "kmeans", "clustering":
		if err := s.kmeans.Train(vectors); err != nil {
			result.Error = err.Error()
		} else {
			result.Success = true
			result.Metrics["silhouette"] = s.kmeans.silhouette
			result.Metrics["inertia"] = s.kmeans.inertia
		}

	case "random_forest", "severity":
		labels := make([]models.Severity, len(indicators))
		for i, ind := range indicators {
			labels[i] = ind.Severity
		}
		if err := s.randomForest.Train(vectors, labels); err != nil {
			result.Error = err.Error()
		} else {
			result.Success = true
			result.Metrics["accuracy"] = s.randomForest.accuracy
		}

	default:
		result.Error = "unknown model type"
	}

	result.TrainingTime = time.Since(startTime)

	return result, nil
}

// GetStats returns ML service statistics
func (s *MLService) GetStats() *models.MLServiceStats {
	modelInfos := []models.MLModelInfo{
		s.isolationForest.GetModelInfo(),
		s.kmeans.GetModelInfo(),
		s.randomForest.GetModelInfo(),
	}

	modelsLoaded := 0
	for _, m := range modelInfos {
		if m.Status == "ready" {
			modelsLoaded++
		}
	}

	totalCacheOps := s.cacheHits.Load() + s.cacheMisses.Load()
	hitRate := 0.0
	if totalCacheOps > 0 {
		hitRate = float64(s.cacheHits.Load()) / float64(totalCacheOps)
	}

	return &models.MLServiceStats{
		ModelsLoaded:           modelsLoaded,
		Models:                 modelInfos,
		TotalPredictions:       s.totalPredictions.Load(),
		TotalAnomalies:         s.totalAnomalies.Load(),
		TotalClusters:          s.kmeans.k,
		TotalEntitiesExtracted: s.totalEntities.Load(),
		LastTrainedAt:          s.lastTrainedAt,
		CacheHitRate:           hitRate,
	}
}

// GetModelInfo returns information about a specific model
func (s *MLService) GetModelInfo(modelType string) *models.MLModelInfo {
	switch modelType {
	case "isolation_forest", "anomaly":
		info := s.isolationForest.GetModelInfo()
		return &info
	case "kmeans", "clustering":
		info := s.kmeans.GetModelInfo()
		return &info
	case "random_forest", "severity":
		info := s.randomForest.GetModelInfo()
		return &info
	default:
		return nil
	}
}

// IsReady returns whether the ML service is ready (at least one model trained)
func (s *MLService) IsReady() bool {
	return s.isolationForest.IsTrained() || s.kmeans.IsTrained() || s.randomForest.IsTrained()
}

// GetFeatureNames returns the list of feature names used by the ML models
func (s *MLService) GetFeatureNames() []string {
	return s.featureExtractor.GetFeatureNames()
}

// FindOptimalClusters finds the optimal number of clusters for the data
func (s *MLService) FindOptimalClusters(ctx context.Context, indicators []*models.Indicator, maxK int) int {
	vectors := s.featureExtractor.ExtractBatchFeatures(indicators)
	return s.kmeans.OptimalK(vectors, maxK)
}

// IsAnomalyModelTrained reports whether the isolation forest is trained and
// anomaly detection can run.
func (s *MLService) IsAnomalyModelTrained() bool {
	return s.isolationForest.IsTrained()
}

// MLInsight is a narrative insight derived from real indicator and model
// state. Every insight is computed from persisted data — no values are
// fabricated; when a data source is empty the corresponding insight is simply
// omitted.
type MLInsight struct {
	ID          string         `json:"id"`
	Title       string         `json:"title"`
	Description string         `json:"description"`
	Severity    string         `json:"severity"` // info, warning, high, critical
	GeneratedAt time.Time      `json:"generated_at"`
	Data        map[string]any `json:"data,omitempty"`
}

// mlInsightRecentLimit bounds how many recent indicators are scored when
// computing the anomaly-cluster insight.
const mlInsightRecentLimit = 1000

// GenerateInsights derives narrative insights from the indicator store and
// the in-memory model state: indicator velocity vs the prior period, dominant
// types and severities, Pegasus presence, and (when the anomaly model is
// trained) the types that cluster among anomalous indicators.
func (s *MLService) GenerateInsights(ctx context.Context) ([]MLInsight, error) {
	if s.repos == nil || s.repos.Indicators == nil {
		return nil, fmt.Errorf("indicator repository is not available")
	}

	stats, err := s.repos.Indicators.GetStats(ctx)
	if err != nil {
		return nil, fmt.Errorf("load indicator stats: %w", err)
	}

	now := time.Now()
	insights := make([]MLInsight, 0, 5)

	if stats.TotalCount == 0 {
		return insights, nil
	}

	// --- Indicator velocity: this week vs the average of the prior three weeks.
	priorMonthRemainder := stats.MonthlyNew - stats.WeeklyNew
	if priorMonthRemainder > 0 {
		prevWeeklyAvg := float64(priorMonthRemainder) / 3.0
		changePct := (float64(stats.WeeklyNew) - prevWeeklyAvg) / prevWeeklyAvg * 100.0
		severity := "info"
		direction := "down"
		if changePct >= 0 {
			direction = "up"
		}
		if changePct >= 50 {
			severity = "warning"
		}
		insights = append(insights, MLInsight{
			ID:    "indicator-velocity",
			Title: "Indicator Velocity",
			Description: fmt.Sprintf(
				"%d new indicators in the last 7 days, %s %.0f%% vs the prior three-week average of %.1f per week.",
				stats.WeeklyNew, direction, math.Abs(changePct), prevWeeklyAvg),
			Severity:    severity,
			GeneratedAt: now,
			Data: map[string]any{
				"weekly_new":          stats.WeeklyNew,
				"monthly_new":         stats.MonthlyNew,
				"today_new":           stats.TodayNew,
				"prev_weekly_average": prevWeeklyAvg,
				"change_percent":      changePct,
			},
		})
	} else if stats.WeeklyNew > 0 {
		// No prior-period baseline exists; report counts without a trend claim.
		insights = append(insights, MLInsight{
			ID:    "indicator-velocity",
			Title: "Indicator Velocity",
			Description: fmt.Sprintf(
				"%d new indicators in the last 7 days (%d today). No prior-period data is available for trend comparison.",
				stats.WeeklyNew, stats.TodayNew),
			Severity:    "info",
			GeneratedAt: now,
			Data: map[string]any{
				"weekly_new":  stats.WeeklyNew,
				"monthly_new": stats.MonthlyNew,
				"today_new":   stats.TodayNew,
			},
		})
	}

	// --- Dominant indicator types.
	if len(stats.ByType) > 0 {
		type typeCount struct {
			Type  string
			Count int64
		}
		counts := make([]typeCount, 0, len(stats.ByType))
		for t, c := range stats.ByType {
			counts = append(counts, typeCount{Type: t, Count: c})
		}
		sort.Slice(counts, func(i, j int) bool {
			if counts[i].Count != counts[j].Count {
				return counts[i].Count > counts[j].Count
			}
			return counts[i].Type < counts[j].Type
		})
		top := counts
		if len(top) > 3 {
			top = top[:3]
		}
		parts := make([]string, 0, len(top))
		data := map[string]any{"total_count": stats.TotalCount}
		for _, tc := range top {
			pct := float64(tc.Count) / float64(stats.TotalCount) * 100.0
			parts = append(parts, fmt.Sprintf("%s (%d, %.1f%%)", tc.Type, tc.Count, pct))
			data[tc.Type] = tc.Count
		}
		insights = append(insights, MLInsight{
			ID:          "dominant-types",
			Title:       "Dominant Indicator Types",
			Description: fmt.Sprintf("Top indicator types across %d stored indicators: %s.", stats.TotalCount, strings.Join(parts, ", ")),
			Severity:    "info",
			GeneratedAt: now,
			Data:        data,
		})
	}

	// --- Severity distribution.
	if stats.CriticalCount > 0 {
		criticalShare := float64(stats.CriticalCount) / float64(stats.TotalCount) * 100.0
		severity := "info"
		if criticalShare >= 25 {
			severity = "high"
		} else if criticalShare >= 10 {
			severity = "warning"
		}
		insights = append(insights, MLInsight{
			ID:    "critical-share",
			Title: "Critical Severity Share",
			Description: fmt.Sprintf(
				"%d of %d indicators (%.1f%%) are rated critical severity.",
				stats.CriticalCount, stats.TotalCount, criticalShare),
			Severity:    severity,
			GeneratedAt: now,
			Data: map[string]any{
				"critical_count":   stats.CriticalCount,
				"total_count":      stats.TotalCount,
				"critical_percent": criticalShare,
				"by_severity":      stats.BySeverity,
			},
		})
	}

	// --- Pegasus presence.
	if stats.PegasusCount > 0 {
		insights = append(insights, MLInsight{
			ID:    "pegasus-presence",
			Title: "Pegasus-Linked Indicators",
			Description: fmt.Sprintf(
				"%d indicators in the store are linked to Pegasus spyware infrastructure.",
				stats.PegasusCount),
			Severity:    "critical",
			GeneratedAt: now,
			Data:        map[string]any{"pegasus_count": stats.PegasusCount},
		})
	}

	// --- Anomaly clusters over recent indicators (only when the model is
	// actually trained — no fabricated anomaly data).
	if s.isolationForest.IsTrained() {
		indicators, _, err := s.repos.Indicators.List(ctx, repository.IndicatorFilter{Limit: mlInsightRecentLimit})
		if err != nil {
			s.logger.Warn().Err(err).Msg("insights: failed to list recent indicators for anomaly clustering")
		} else if len(indicators) > 0 {
			result, err := s.DetectAnomalies(ctx, indicators)
			if err != nil {
				s.logger.Warn().Err(err).Msg("insights: anomaly detection failed")
			} else if result.AnomalyCount > 0 {
				byID := make(map[uuid.UUID]*models.Indicator, len(indicators))
				for _, ind := range indicators {
					byID[ind.ID] = ind
				}
				typeCounts := make(map[string]int)
				for _, score := range result.Scores {
					if !score.IsAnomaly {
						continue
					}
					if ind, ok := byID[score.IndicatorID]; ok {
						typeCounts[string(ind.Type)]++
					}
				}
				type cluster struct {
					Type  string
					Count int
				}
				clusters := make([]cluster, 0, len(typeCounts))
				for t, c := range typeCounts {
					clusters = append(clusters, cluster{Type: t, Count: c})
				}
				sort.Slice(clusters, func(i, j int) bool {
					if clusters[i].Count != clusters[j].Count {
						return clusters[i].Count > clusters[j].Count
					}
					return clusters[i].Type < clusters[j].Type
				})
				top := clusters
				if len(top) > 3 {
					top = top[:3]
				}
				parts := make([]string, 0, len(top))
				data := map[string]any{
					"anomaly_count":  result.AnomalyCount,
					"processed":      result.TotalProcessed,
					"anomaly_rate":   result.Statistics.AnomalyRate,
					"mean_score":     result.Statistics.MeanScore,
					"detection_time": result.ProcessingTime.String(),
				}
				for _, c := range top {
					parts = append(parts, fmt.Sprintf("%s (%d)", c.Type, c.Count))
					data["cluster_"+c.Type] = c.Count
				}
				severity := "info"
				if result.Statistics.AnomalyRate >= 0.2 {
					severity = "warning"
				}
				insights = append(insights, MLInsight{
					ID:    "anomaly-clusters",
					Title: "Anomaly Clusters",
					Description: fmt.Sprintf(
						"Anomaly detection flags %d of %d recent indicators (%.1f%%); most anomalous types: %s.",
						result.AnomalyCount, result.TotalProcessed,
						result.Statistics.AnomalyRate*100.0, strings.Join(parts, ", ")),
					Severity:    severity,
					GeneratedAt: now,
					Data:        data,
				})
			}
		}
	} else {
		// Honest model state: anomaly insights are unavailable until training.
		notTrained := s.modelsNotTrainedError(ctx, "isolation_forest")
		insights = append(insights, MLInsight{
			ID:          "anomaly-model-untrained",
			Title:       "Anomaly Model Not Trained",
			Description: fmt.Sprintf("Anomaly-based insights are unavailable: %s.", notTrained.Error()),
			Severity:    "info",
			GeneratedAt: now,
			Data: map[string]any{
				"model":             notTrained.ModelType,
				"indicators_needed": notTrained.IndicatorsNeeded,
			},
		})
	}

	return insights, nil
}

// AnalyzeIndicator provides comprehensive ML analysis of a single indicator.
// Returns (nil, nil) when the indicator does not exist.
func (s *MLService) AnalyzeIndicator(ctx context.Context, indicatorID uuid.UUID) (*models.MLEnrichmentResult, error) {
	if s.repos == nil || s.repos.Indicators == nil {
		return nil, fmt.Errorf("indicator repository is not available")
	}

	indicator, err := s.repos.Indicators.GetByID(ctx, indicatorID)
	if err != nil {
		return nil, err
	}
	if indicator == nil {
		return nil, nil
	}

	return s.EnrichIndicator(ctx, indicator)
}
