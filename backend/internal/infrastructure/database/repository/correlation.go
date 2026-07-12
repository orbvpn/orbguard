package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"orbguard-lab/internal/domain/models"
)

// CorrelationRepository persists correlation events produced by the
// correlation engine and the summaries of server-side correlation runs.
type CorrelationRepository struct {
	pool *pgxpool.Pool
}

// NewCorrelationRepository creates a new correlation repository.
func NewCorrelationRepository(pool *pgxpool.Pool) *CorrelationRepository {
	return &CorrelationRepository{pool: pool}
}

// NewCorrelationRepositoryFromRepos builds a CorrelationRepository reusing
// the shared connection pool held by the existing repositories. Returns nil
// when the repositories (and therefore the pool) are unavailable.
func NewCorrelationRepositoryFromRepos(repos *Repositories) *CorrelationRepository {
	if repos == nil || repos.Devices == nil || repos.Devices.pool == nil {
		return nil
	}
	return NewCorrelationRepository(repos.Devices.pool)
}

// CorrelationRunRecord is the persisted summary of one server-side
// correlation run (POST /correlation/run).
type CorrelationRunRecord struct {
	ID                   uuid.UUID `json:"id"`
	RequestID            uuid.UUID `json:"request_id"`
	RequestedBy          string    `json:"requested_by"`
	IndicatorsAnalyzed   int       `json:"indicators_analyzed"`
	CorrelationsFound    int       `json:"correlations_found"`
	ClustersFormed       int       `json:"clusters_formed"`
	CampaignsMatched     int       `json:"campaigns_matched"`
	ActorsMatched        int       `json:"actors_matched"`
	AverageConfidence    float64   `json:"average_confidence"`
	StrongestCorrelation float64   `json:"strongest_correlation"`
	ProcessingMS         int64     `json:"processing_ms"`
	StartedAt            time.Time `json:"started_at"`
	CompletedAt          time.Time `json:"completed_at"`
}

const correlationEventInsert = `
INSERT INTO orbguard_lab.correlation_events
    (id, request_id, type, strength, confidence, description,
     indicator_ids, campaign_id, threat_actor_id, evidence, triggered_by, created_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
ON CONFLICT (id) DO NOTHING
`

// InsertEvents stores a batch of correlation events in one round trip.
func (r *CorrelationRepository) InsertEvents(ctx context.Context, requestID uuid.UUID, triggeredBy string, events []models.CorrelationEvent) error {
	if len(events) == 0 {
		return nil
	}

	batch := &pgx.Batch{}
	for i := range events {
		ev := &events[i]
		if ev.ID == uuid.Nil {
			ev.ID = uuid.New()
		}
		createdAt := ev.CreatedAt
		if createdAt.IsZero() {
			createdAt = time.Now().UTC()
		}

		indicatorIDs, err := marshalUUIDs(ev.Indicators)
		if err != nil {
			return fmt.Errorf("marshal correlation indicator ids: %w", err)
		}
		evidence, err := json.Marshal(ev.Evidence)
		if err != nil {
			return fmt.Errorf("marshal correlation evidence: %w", err)
		}

		batch.Queue(correlationEventInsert,
			ev.ID,
			requestID,
			string(ev.Type),
			string(ev.Strength),
			ev.Confidence,
			ev.Description,
			indicatorIDs,
			ev.CampaignID,
			ev.ThreatActorID,
			evidence,
			triggeredBy,
			createdAt,
		)
	}

	results := r.pool.SendBatch(ctx, batch)
	defer results.Close()

	for range events {
		if _, err := results.Exec(); err != nil {
			return fmt.Errorf("insert correlation event batch: %w", err)
		}
	}
	return nil
}

// ListRecentEvents returns the most recent correlation events, newest first,
// optionally filtered by a free-text search over type, strength, and
// description.
func (r *CorrelationRepository) ListRecentEvents(ctx context.Context, search string, limit int) ([]models.CorrelationEvent, error) {
	query := `
SELECT id, type, strength, confidence, description,
       indicator_ids, campaign_id, threat_actor_id, evidence, created_at
FROM orbguard_lab.correlation_events
WHERE ($1 = '' OR
       type ILIKE '%' || $1 || '%' OR
       strength ILIKE '%' || $1 || '%' OR
       description ILIKE '%' || $1 || '%')
ORDER BY created_at DESC
LIMIT $2
`
	rows, err := r.pool.Query(ctx, query, search, limit)
	if err != nil {
		return nil, fmt.Errorf("list correlation events: %w", err)
	}
	defer rows.Close()

	events := make([]models.CorrelationEvent, 0)
	for rows.Next() {
		var (
			ev            models.CorrelationEvent
			typ, strength string
			indicatorIDs  []byte
			evidence      []byte
		)
		if err := rows.Scan(
			&ev.ID,
			&typ,
			&strength,
			&ev.Confidence,
			&ev.Description,
			&indicatorIDs,
			&ev.CampaignID,
			&ev.ThreatActorID,
			&evidence,
			&ev.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan correlation event: %w", err)
		}

		ev.Type = models.CorrelationType(typ)
		ev.Strength = models.CorrelationStrength(strength)

		ev.Indicators, err = unmarshalUUIDs(indicatorIDs)
		if err != nil {
			return nil, fmt.Errorf("unmarshal correlation indicator ids: %w", err)
		}
		if len(evidence) > 0 {
			if err := json.Unmarshal(evidence, &ev.Evidence); err != nil {
				return nil, fmt.Errorf("unmarshal correlation evidence: %w", err)
			}
		}

		events = append(events, ev)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list correlation events rows: %w", err)
	}

	return events, nil
}

// InsertRun stores the summary of one server-side correlation run.
func (r *CorrelationRepository) InsertRun(ctx context.Context, run *CorrelationRunRecord) error {
	if run.ID == uuid.Nil {
		run.ID = uuid.New()
	}
	if run.CompletedAt.IsZero() {
		run.CompletedAt = time.Now().UTC()
	}

	query := `
INSERT INTO orbguard_lab.correlation_runs
    (id, request_id, requested_by, indicators_analyzed, correlations_found,
     clusters_formed, campaigns_matched, actors_matched,
     average_confidence, strongest_correlation, processing_ms,
     started_at, completed_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
`
	_, err := r.pool.Exec(ctx, query,
		run.ID,
		run.RequestID,
		run.RequestedBy,
		run.IndicatorsAnalyzed,
		run.CorrelationsFound,
		run.ClustersFormed,
		run.CampaignsMatched,
		run.ActorsMatched,
		run.AverageConfidence,
		run.StrongestCorrelation,
		run.ProcessingMS,
		run.StartedAt,
		run.CompletedAt,
	)
	if err != nil {
		return fmt.Errorf("insert correlation run: %w", err)
	}
	return nil
}

// marshalUUIDs serialises a UUID list to a JSON array of strings,
// guaranteeing a non-null jsonb value.
func marshalUUIDs(ids []uuid.UUID) ([]byte, error) {
	strs := make([]string, len(ids))
	for i, id := range ids {
		strs[i] = id.String()
	}
	return json.Marshal(strs)
}

// unmarshalUUIDs parses a JSON array of UUID strings.
func unmarshalUUIDs(data []byte) ([]uuid.UUID, error) {
	if len(data) == 0 {
		return []uuid.UUID{}, nil
	}
	var strs []string
	if err := json.Unmarshal(data, &strs); err != nil {
		return nil, err
	}
	ids := make([]uuid.UUID, 0, len(strs))
	for _, s := range strs {
		id, err := uuid.Parse(s)
		if err != nil {
			return nil, fmt.Errorf("invalid uuid %q: %w", s, err)
		}
		ids = append(ids, id)
	}
	return ids, nil
}
