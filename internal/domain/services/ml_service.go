package services

import (
	"context"
	"fmt"
	"math"
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
	featureExtractor  *FeatureExtractor
	isolationForest   *IsolationForest
	kmeans            *KMeans
	randomForest      *RandomForest
	entityExtractor   *EntityExtractor
	repos             *repository.Repositories
	cache             *cache.RedisCache
	logger            *logger.Logger

	// Training state
	minTrainingSize   int
	lastTrainedAt     time.Time
	trainingInProgress atomic.Bool
	trainingMu        sync.Mutex

	// Stats
	totalPredictions   atomic.Int64
	totalAnomalies     atomic.Int64
	totalEntities      atomic.Int64
	cacheHits          atomic.Int64
	cacheMisses        atomic.Int64
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
		ModelType:      "all",
		Version:        "1.0",
		TrainingSize:   len(indicators),
		TrainingTime:   time.Since(startTime),
		Success:        true,
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
