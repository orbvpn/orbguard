package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/internal/infrastructure/graph"
	"orbguard-lab/pkg/logger"
)

// GraphService provides threat graph operations
type GraphService struct {
	graphRepo *graph.GraphRepository
	sqlRepos  *repository.Repositories
	cache     *cache.RedisCache
	logger    *logger.Logger
}

// NewGraphService creates a new graph service
func NewGraphService(
	graphRepo *graph.GraphRepository,
	sqlRepos *repository.Repositories,
	cache *cache.RedisCache,
	log *logger.Logger,
) *GraphService {
	return &GraphService{
		graphRepo: graphRepo,
		sqlRepos:  sqlRepos,
		cache:     cache,
		logger:    log.WithComponent("graph-service"),
	}
}

// ErrGraphUnavailable is returned when Neo4j is not configured or could not
// be reached at startup, so graph exploration features cannot be served.
var ErrGraphUnavailable = errors.New("graph database (Neo4j) is not available")

// Available reports whether the graph backend can serve queries. The service
// is only constructed when Neo4j connects at startup, but this guards against
// partially-wired instances.
func (s *GraphService) Available() bool {
	return s != nil && s.graphRepo != nil
}

// ListNodes returns graph nodes for the exploration API, optionally filtered
// by node label (type) and a free-text search. Limit is capped by the caller.
func (s *GraphService) ListNodes(ctx context.Context, nodeType, search string, limit int) ([]graph.NodeView, error) {
	if !s.Available() {
		return nil, ErrGraphUnavailable
	}

	queryCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()

	return s.graphRepo.ListNodes(queryCtx, nodeType, search, limit)
}

// ListRelations returns graph relationships for the exploration API,
// optionally filtered by relationship type, endpoint node id, and free-text
// search. Limit is capped by the caller.
func (s *GraphService) ListRelations(ctx context.Context, relType, nodeID, search string, limit int) ([]graph.RelationView, error) {
	if !s.Available() {
		return nil, ErrGraphUnavailable
	}

	queryCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()

	return s.graphRepo.ListRelations(queryCtx, relType, nodeID, search, limit)
}

// SyncFromPostgres syncs data from PostgreSQL to Neo4j
func (s *GraphService) SyncFromPostgres(ctx context.Context) error {
	s.logger.Info().Msg("starting PostgreSQL to Neo4j sync")
	start := time.Now()

	// Sync campaigns
	campaignCount, err := s.syncCampaigns(ctx)
	if err != nil {
		s.logger.Error().Err(err).Msg("failed to sync campaigns")
	}

	// Sync threat actors
	actorCount, err := s.syncActors(ctx)
	if err != nil {
		s.logger.Error().Err(err).Msg("failed to sync threat actors")
	}

	// Sync indicators (paginated)
	indicatorCount, err := s.syncIndicators(ctx)
	if err != nil {
		s.logger.Error().Err(err).Msg("failed to sync indicators")
	}

	s.logger.Info().
		Int("campaigns", campaignCount).
		Int("actors", actorCount).
		Int("indicators", indicatorCount).
		Dur("duration", time.Since(start)).
		Msg("PostgreSQL to Neo4j sync complete")

	return nil
}

func (s *GraphService) syncCampaigns(ctx context.Context) (int, error) {
	if s.sqlRepos == nil || s.sqlRepos.Campaigns == nil {
		return 0, nil
	}

	campaigns, _, err := s.sqlRepos.Campaigns.List(ctx, false, 1000, 0)
	if err != nil {
		return 0, err
	}

	count := 0
	for _, c := range campaigns {
		node := &models.CampaignNode{
			ID:          c.ID,
			Slug:        c.Slug,
			Name:        c.Name,
			Description: c.Description,
			FirstSeen:   c.FirstSeen,
			LastSeen:    c.LastSeen,
			IsActive:    c.IsActive,
		}

		if err := s.graphRepo.CreateCampaign(ctx, node); err != nil {
			s.logger.Warn().Err(err).Str("campaign", c.Name).Msg("failed to sync campaign")
			continue
		}
		count++
	}

	return count, nil
}

func (s *GraphService) syncActors(ctx context.Context) (int, error) {
	if s.sqlRepos == nil || s.sqlRepos.Actors == nil {
		return 0, nil
	}

	actors, _, err := s.sqlRepos.Actors.List(ctx, false, 1000, 0)
	if err != nil {
		return 0, err
	}

	count := 0
	for _, a := range actors {
		node := &models.ThreatActorNode{
			ID:          a.ID,
			Name:        a.Name,
			Aliases:     a.Aliases,
			Description: a.Description,
			Motivation:  string(a.Motivation),
			Country:     a.Country,
			FirstSeen:   a.CreatedAt,
			LastSeen:    a.UpdatedAt,
			IsActive:    a.Active,
		}

		if err := s.graphRepo.CreateThreatActor(ctx, node); err != nil {
			s.logger.Warn().Err(err).Str("actor", a.Name).Msg("failed to sync actor")
			continue
		}
		count++

		// Build (Actor)-[:USES]->(Technique) edges from the actor's known
		// techniques and the techniques of campaigns attributed to it.
		techniques := normalizeTechniqueIDs(a.CommonTechniques)
		if s.sqlRepos.Campaigns != nil {
			campaigns, err := s.sqlRepos.Campaigns.ListByThreatActor(ctx, a.ID)
			if err != nil {
				s.logger.Warn().Err(err).Str("actor", a.Name).Msg("failed to list campaigns for actor technique sync")
			} else {
				for _, c := range campaigns {
					techniques = mergeTechniqueIDs(techniques, c.MitreTechniques)
				}
			}
		}

		if len(techniques) > 0 {
			linkCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
			linked, err := s.graphRepo.LinkActorToTechniques(linkCtx, a.ID, techniques)
			cancel()
			if err != nil {
				s.logger.Warn().Err(err).Str("actor", a.Name).Msg("failed to link actor techniques")
			} else if linked > 0 {
				s.logger.Debug().Str("actor", a.Name).Int("techniques", linked).Msg("actor technique edges synced")
			}
		}
	}

	return count, nil
}

func (s *GraphService) syncIndicators(ctx context.Context) (int, error) {
	if s.sqlRepos == nil || s.sqlRepos.Indicators == nil {
		return 0, nil
	}

	// Use smaller batch size for DB fetch and even smaller for Neo4j writes
	fetchBatchSize := 1000
	neo4jBatchSize := 100 // Smaller batches for Neo4j to avoid timeouts
	offset := 0
	totalCount := 0
	failedBatches := 0
	maxFailedBatches := 5 // Stop if too many consecutive failures

	for {
		// Check if context is cancelled
		select {
		case <-ctx.Done():
			s.logger.Warn().Int("synced", totalCount).Msg("sync cancelled")
			return totalCount, ctx.Err()
		default:
		}

		filter := repository.IndicatorFilter{
			Limit:  fetchBatchSize,
			Offset: offset,
		}
		indicators, _, err := s.sqlRepos.Indicators.List(ctx, filter)
		if err != nil {
			return totalCount, err
		}

		if len(indicators) == 0 {
			break
		}

		// Convert to nodes
		nodes := make([]*models.IndicatorNode, 0, len(indicators))
		campaignLinks := make([]struct {
			indicatorID uuid.UUID
			campaignID  uuid.UUID
			confidence  float64
		}, 0)

		for _, ind := range indicators {
			sourceName := ""
			if len(ind.Sources) > 0 {
				sourceName = ind.Sources[0].SourceName
			}

			nodes = append(nodes, &models.IndicatorNode{
				ID:         ind.ID,
				Type:       ind.Type,
				Value:      ind.Value,
				Severity:   ind.Severity,
				Confidence: ind.Confidence,
				FirstSeen:  ind.FirstSeen,
				LastSeen:   ind.LastSeen,
				Tags:       ind.Tags,
				Source:     sourceName,
			})

			if ind.CampaignID != nil && *ind.CampaignID != uuid.Nil {
				campaignLinks = append(campaignLinks, struct {
					indicatorID uuid.UUID
					campaignID  uuid.UUID
					confidence  float64
				}{ind.ID, *ind.CampaignID, ind.Confidence})
			}
		}

		// Batch create indicators in smaller chunks
		for i := 0; i < len(nodes); i += neo4jBatchSize {
			end := i + neo4jBatchSize
			if end > len(nodes) {
				end = len(nodes)
			}

			batch := nodes[i:end]

			// Create a timeout context for this batch
			batchCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
			count, err := s.graphRepo.CreateIndicatorsBatch(batchCtx, batch)
			cancel()

			if err != nil {
				failedBatches++
				s.logger.Warn().
					Err(err).
					Int("batch_start", offset+i).
					Int("batch_size", len(batch)).
					Int("failed_batches", failedBatches).
					Msg("failed to sync indicator batch")

				if failedBatches >= maxFailedBatches {
					s.logger.Error().
						Int("synced", totalCount).
						Int("failed_batches", failedBatches).
						Msg("too many failed batches, stopping sync")
					return totalCount, fmt.Errorf("too many failed batches: %d", failedBatches)
				}
				continue
			}

			failedBatches = 0 // Reset on success
			totalCount += count
		}

		// Create campaign relationships (these are typically few)
		for _, link := range campaignLinks {
			linkCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
			if err := s.graphRepo.LinkIndicatorToCampaign(linkCtx, link.indicatorID, link.campaignID, link.confidence); err != nil {
				s.logger.Warn().Err(err).Msg("failed to link indicator to campaign")
			}
			cancel()
		}

		s.logger.Info().
			Int("offset", offset).
			Int("batch_count", len(indicators)).
			Int("total_synced", totalCount).
			Msg("sync progress")

		offset += fetchBatchSize

		if len(indicators) < fetchBatchSize {
			break
		}
	}

	return totalCount, nil
}

// GetCorrelation returns correlation data for an indicator
func (s *GraphService) GetCorrelation(ctx context.Context, indicatorID uuid.UUID) (*models.CorrelationResult, error) {
	// Check cache first
	cacheKey := fmt.Sprintf("graph:correlation:%s", indicatorID.String())
	if s.cache != nil {
		if cached, err := s.cache.Get(ctx, cacheKey); err == nil && cached != "" {
			var result models.CorrelationResult
			if err := json.Unmarshal([]byte(cached), &result); err == nil {
				return &result, nil
			}
		}
	}

	// Get from graph
	correlation, err := s.graphRepo.GetCorrelation(ctx, indicatorID)
	if err != nil {
		return nil, err
	}

	// Cache for 5 minutes
	if s.cache != nil {
		if data, err := json.Marshal(correlation); err == nil {
			s.cache.Set(ctx, cacheKey, string(data), 5*time.Minute)
		}
	}

	return correlation, nil
}

// FindRelated finds indicators related to a given indicator
func (s *GraphService) FindRelated(ctx context.Context, indicatorID uuid.UUID, maxDepth, limit int) ([]models.RelatedIndicator, error) {
	return s.graphRepo.FindRelatedIndicators(ctx, indicatorID, maxDepth, limit)
}

// FindSharedInfrastructure finds indicators sharing infrastructure
func (s *GraphService) FindSharedInfrastructure(ctx context.Context, limit int) (*models.InfrastructureOverlapResult, error) {
	return s.graphRepo.FindSharedInfrastructure(ctx, limit)
}

// DetectCampaigns attempts to auto-detect new campaigns
func (s *GraphService) DetectCampaigns(ctx context.Context, minSharedInfra, limit int) ([]models.CampaignDetection, error) {
	return s.graphRepo.DetectCampaigns(ctx, minSharedInfra, limit)
}

// TraverseGraph performs a graph traversal
func (s *GraphService) TraverseGraph(ctx context.Context, req *models.GraphTraversalRequest) (*models.GraphQueryResult, error) {
	return s.graphRepo.Traverse(ctx, req)
}

// GetStats returns graph statistics
func (s *GraphService) GetStats(ctx context.Context) (*models.GraphStats, error) {
	// Check cache first
	cacheKey := "graph:stats"
	if s.cache != nil {
		if cached, err := s.cache.Get(ctx, cacheKey); err == nil && cached != "" {
			var result models.GraphStats
			if err := json.Unmarshal([]byte(cached), &result); err == nil {
				return &result, nil
			}
		}
	}

	stats, err := s.graphRepo.GetStats(ctx)
	if err != nil {
		return nil, err
	}

	// Cache for 1 minute
	if s.cache != nil {
		if data, err := json.Marshal(stats); err == nil {
			s.cache.Set(ctx, cacheKey, string(data), time.Minute)
		}
	}

	return stats, nil
}

// CalculateTTPSimilarity calculates TTP similarity between threat actors as
// the Jaccard similarity over their MITRE ATT&CK technique sets. Technique
// sets come from (Actor)-[:USES]->(Technique) edges in Neo4j, falling back to
// relational data (actor common_techniques, campaign and indicator MITRE
// fields) when the graph holds no data for an actor.
func (s *GraphService) CalculateTTPSimilarity(ctx context.Context, actor1ID, actor2ID uuid.UUID) (*models.TTPSimilarity, error) {
	ttp1, err := s.collectActorTTPData(ctx, actor1ID)
	if err != nil {
		return nil, fmt.Errorf("failed to collect TTP data for actor %s: %w", actor1ID, err)
	}

	ttp2, err := s.collectActorTTPData(ctx, actor2ID)
	if err != nil {
		return nil, fmt.Errorf("failed to collect TTP data for actor %s: %w", actor2ID, err)
	}

	result := &models.TTPSimilarity{
		Actor1:           actor1ID.String(),
		Actor2:           actor2ID.String(),
		SharedTactics:    []string{},
		SharedTechniques: []string{},
		Similarity:       0.0,
		DataSource:       combineTTPSources(ttp1.source, ttp2.source),
	}

	// Similarity is only meaningful when both actors have technique data.
	if len(ttp1.techniques) == 0 || len(ttp2.techniques) == 0 {
		result.InsufficientData = true
		return result, nil
	}

	shared := make([]string, 0)
	unionSize := len(ttp2.techniques)
	for t := range ttp1.techniques {
		if _, ok := ttp2.techniques[t]; ok {
			shared = append(shared, t)
		} else {
			unionSize++
		}
	}
	sort.Strings(shared)

	sharedTactics := make([]string, 0)
	for t := range ttp1.tactics {
		if _, ok := ttp2.tactics[t]; ok {
			sharedTactics = append(sharedTactics, t)
		}
	}
	sort.Strings(sharedTactics)

	result.SharedTechniques = shared
	result.SharedTactics = sharedTactics
	if unionSize > 0 {
		result.Similarity = float64(len(shared)) / float64(unionSize)
	}

	return result, nil
}

// actorTTPData holds the technique/tactic sets gathered for a single actor.
type actorTTPData struct {
	techniques map[string]struct{}
	tactics    map[string]struct{}
	source     string // "graph", "sql_fallback", or "none"
}

// collectActorTTPData gathers an actor's MITRE technique and tactic sets.
// Techniques are read from the graph first; when the graph has no USES edges
// for the actor, they are derived from relational data (actor
// common_techniques, attributed campaigns, attributed indicators) and the
// graph is back-filled best-effort. Tactics always come from relational data
// because Technique nodes do not carry tactic information.
func (s *GraphService) collectActorTTPData(ctx context.Context, actorID uuid.UUID) (*actorTTPData, error) {
	data := &actorTTPData{
		techniques: make(map[string]struct{}),
		tactics:    make(map[string]struct{}),
		source:     "none",
	}

	// 1. Graph: (Actor)-[:USES]->(Technique)
	graphTechniques, err := s.graphRepo.GetActorTechniques(ctx, actorID)
	if err != nil {
		// Graph unavailability is not fatal — fall back to SQL below.
		s.logger.Warn().Err(err).Str("actor_id", actorID.String()).Msg("failed to read actor techniques from graph, falling back to SQL")
	}
	for _, t := range normalizeTechniqueIDs(graphTechniques) {
		data.techniques[t] = struct{}{}
	}
	if len(data.techniques) > 0 {
		data.source = "graph"
	}

	if s.sqlRepos == nil {
		return data, nil
	}

	// 2. Relational data: actor record, campaigns, indicators.
	sqlTechniques := make(map[string]struct{})

	if s.sqlRepos.Actors != nil {
		actor, err := s.sqlRepos.Actors.GetByID(ctx, actorID)
		if err != nil {
			return nil, err
		}
		if actor != nil {
			for _, t := range normalizeTechniqueIDs(actor.CommonTechniques) {
				sqlTechniques[t] = struct{}{}
			}
		}
	}

	if s.sqlRepos.Campaigns != nil {
		campaigns, err := s.sqlRepos.Campaigns.ListByThreatActor(ctx, actorID)
		if err != nil {
			s.logger.Warn().Err(err).Str("actor_id", actorID.String()).Msg("failed to list campaigns for TTP data")
		} else {
			for _, c := range campaigns {
				for _, t := range normalizeTechniqueIDs(c.MitreTechniques) {
					sqlTechniques[t] = struct{}{}
				}
				for _, t := range normalizeTacticNames(c.MitreTactics) {
					data.tactics[t] = struct{}{}
				}
			}
		}
	}

	if s.sqlRepos.Indicators != nil {
		filter := repository.IndicatorFilter{
			ThreatActorID: &actorID,
			Limit:         2000,
		}
		indicators, _, err := s.sqlRepos.Indicators.List(ctx, filter)
		if err != nil {
			s.logger.Warn().Err(err).Str("actor_id", actorID.String()).Msg("failed to list indicators for TTP data")
		} else {
			for _, ind := range indicators {
				for _, t := range normalizeTechniqueIDs(ind.MitreTechniques) {
					sqlTechniques[t] = struct{}{}
				}
				for _, t := range normalizeTacticNames(ind.MitreTactics) {
					data.tactics[t] = struct{}{}
				}
			}
		}
	}

	if len(data.techniques) == 0 && len(sqlTechniques) > 0 {
		// Graph had nothing — use SQL-derived techniques and back-fill the
		// graph so future queries are served from Neo4j directly.
		data.source = "sql_fallback"
		backfill := make([]string, 0, len(sqlTechniques))
		for t := range sqlTechniques {
			data.techniques[t] = struct{}{}
			backfill = append(backfill, t)
		}
		sort.Strings(backfill)

		linkCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
		if _, err := s.graphRepo.LinkActorToTechniques(linkCtx, actorID, backfill); err != nil {
			s.logger.Warn().Err(err).Str("actor_id", actorID.String()).Msg("failed to back-fill actor technique edges")
		}
		cancel()
	}

	return data, nil
}

// combineTTPSources combines per-actor data sources into a single label.
func combineTTPSources(s1, s2 string) string {
	switch {
	case s1 == s2:
		return s1
	case s1 == "none":
		return s2
	case s2 == "none":
		return s1
	default:
		return "mixed"
	}
}

// normalizeTechniqueIDs trims, upper-cases, and de-duplicates MITRE technique
// IDs (e.g. "t1059.001" -> "T1059.001"), dropping empty entries.
func normalizeTechniqueIDs(ids []string) []string {
	seen := make(map[string]struct{}, len(ids))
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		norm := strings.ToUpper(strings.TrimSpace(id))
		if norm == "" {
			continue
		}
		if _, ok := seen[norm]; ok {
			continue
		}
		seen[norm] = struct{}{}
		out = append(out, norm)
	}
	return out
}

// normalizeTacticNames trims, lower-cases, and de-duplicates MITRE tactic
// names (e.g. "Initial Access" -> "initial-access"), dropping empty entries.
func normalizeTacticNames(tactics []string) []string {
	seen := make(map[string]struct{}, len(tactics))
	out := make([]string, 0, len(tactics))
	for _, t := range tactics {
		norm := strings.ToLower(strings.TrimSpace(t))
		norm = strings.ReplaceAll(norm, " ", "-")
		if norm == "" {
			continue
		}
		if _, ok := seen[norm]; ok {
			continue
		}
		seen[norm] = struct{}{}
		out = append(out, norm)
	}
	return out
}

// mergeTechniqueIDs merges additional technique IDs into an existing
// normalized list, preserving order and uniqueness.
func mergeTechniqueIDs(existing []string, additional []string) []string {
	seen := make(map[string]struct{}, len(existing))
	for _, t := range existing {
		seen[t] = struct{}{}
	}
	for _, t := range normalizeTechniqueIDs(additional) {
		if _, ok := seen[t]; ok {
			continue
		}
		seen[t] = struct{}{}
		existing = append(existing, t)
	}
	return existing
}

// FindTemporalCorrelation finds indicators that appeared around the same time
func (s *GraphService) FindTemporalCorrelation(ctx context.Context, indicatorID uuid.UUID, window time.Duration) (*models.TemporalCorrelation, error) {
	// Get the base indicator
	correlation, err := s.graphRepo.GetCorrelation(ctx, indicatorID)
	if err != nil {
		return nil, err
	}

	if correlation.PrimaryIndicator == nil {
		return nil, fmt.Errorf("indicator not found")
	}

	// Find indicators within the time window
	temporal := &models.TemporalCorrelation{
		TimeWindow: window,
		Indicators: []models.IndicatorNode{*correlation.PrimaryIndicator},
		FirstSeen:  correlation.PrimaryIndicator.FirstSeen,
		LastSeen:   correlation.PrimaryIndicator.LastSeen,
	}

	// Add related indicators that fall within the time window
	for _, related := range correlation.RelatedIndicators {
		indicatorTime := related.Indicator.FirstSeen
		baseTime := correlation.PrimaryIndicator.FirstSeen

		if indicatorTime.After(baseTime.Add(-window)) && indicatorTime.Before(baseTime.Add(window)) {
			temporal.Indicators = append(temporal.Indicators, related.Indicator)

			if indicatorTime.Before(temporal.FirstSeen) {
				temporal.FirstSeen = indicatorTime
			}
			if indicatorTime.After(temporal.LastSeen) {
				temporal.LastSeen = indicatorTime
			}
		}
	}

	return temporal, nil
}

// EnrichIndicator enriches an indicator with graph data
func (s *GraphService) EnrichIndicator(ctx context.Context, indicator *models.Indicator) (*models.Indicator, error) {
	correlation, err := s.graphRepo.GetCorrelation(ctx, indicator.ID)
	if err != nil {
		return indicator, nil // Return original if graph enrichment fails
	}

	// Add campaign info
	if len(correlation.Campaigns) > 0 {
		for _, c := range correlation.Campaigns {
			indicator.Tags = append(indicator.Tags, fmt.Sprintf("campaign:%s", c.Slug))
		}
	}

	// Add actor info
	if len(correlation.ThreatActors) > 0 {
		for _, a := range correlation.ThreatActors {
			indicator.Tags = append(indicator.Tags, fmt.Sprintf("actor:%s", a.Name))
		}
	}

	// Note: RiskScore is part of CorrelationResult, not Indicator
	// Caller can use correlation.RiskScore if needed

	return indicator, nil
}

// CreateRelationship creates a relationship between entities
func (s *GraphService) CreateRelationship(ctx context.Context, sourceID, targetID uuid.UUID, relType models.GraphRelationType, confidence float64) error {
	return s.graphRepo.LinkIndicators(ctx, sourceID, targetID, relType, confidence)
}

// BuildRelationships creates relationships between indicators based on various criteria
func (s *GraphService) BuildRelationships(ctx context.Context) (*models.RelationshipBuildResult, error) {
	s.logger.Info().Msg("starting relationship building")
	start := time.Now()

	result := &models.RelationshipBuildResult{
		StartedAt: start,
	}

	// Create relationships by shared tags (most valuable)
	s.logger.Info().Msg("creating relationships by shared tags")
	tagCtx, tagCancel := context.WithTimeout(ctx, 5*time.Minute)
	tagCount, err := s.graphRepo.CreateRelationshipsBySharedTags(tagCtx, nil, 10)
	tagCancel()
	if err != nil {
		s.logger.Warn().Err(err).Msg("failed to create tag relationships")
		result.Errors = append(result.Errors, err.Error())
	} else {
		result.TagRelationships = tagCount
		s.logger.Info().Int("count", tagCount).Msg("tag relationships created")
	}

	result.TotalCreated = result.TagRelationships
	result.Duration = time.Since(start)
	result.CompletedAt = time.Now()

	s.logger.Info().
		Int("total", result.TotalCreated).
		Int("by_tags", result.TagRelationships).
		Dur("duration", result.Duration).
		Msg("relationship building complete")

	return result, nil
}

// BulkSync syncs a batch of indicators to the graph
func (s *GraphService) BulkSync(ctx context.Context, indicators []*models.Indicator) error {
	s.logger.Info().Int("count", len(indicators)).Msg("bulk syncing indicators to graph")

	for _, ind := range indicators {
		// Get source name from sources array
		sourceName := ""
		if len(ind.Sources) > 0 {
			sourceName = ind.Sources[0].SourceName
		}

		node := &models.IndicatorNode{
			ID:         ind.ID,
			Type:       ind.Type,
			Value:      ind.Value,
			Severity:   ind.Severity,
			Confidence: ind.Confidence,
			FirstSeen:  ind.FirstSeen,
			LastSeen:   ind.LastSeen,
			Tags:       ind.Tags,
			Source:     sourceName,
		}

		if err := s.graphRepo.CreateIndicator(ctx, node); err != nil {
			s.logger.Warn().Err(err).Str("indicator", ind.Value).Msg("failed to sync indicator")
			continue
		}

		// Create campaign relationship
		if ind.CampaignID != nil && *ind.CampaignID != uuid.Nil {
			if err := s.graphRepo.LinkIndicatorToCampaign(ctx, ind.ID, *ind.CampaignID, ind.Confidence); err != nil {
				s.logger.Warn().Err(err).Msg("failed to link indicator to campaign")
			}
		}
	}

	return nil
}
