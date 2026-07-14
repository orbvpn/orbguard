package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// SMSRepository persists privacy-preserving SMS analysis outcomes and
// user-reported false positives. Raw message content is never stored —
// only the SHA-256 hash of the sender plus derived analysis fields.
type SMSRepository struct {
	pool *pgxpool.Pool
}

// NewSMSRepository creates a new SMS repository.
func NewSMSRepository(pool *pgxpool.Pool) *SMSRepository {
	return &SMSRepository{pool: pool}
}

// NewSMSRepositoryFromRepos builds an SMSRepository reusing the shared
// connection pool held by the existing repositories. Returns nil when the
// repositories (and therefore the pool) are unavailable.
func NewSMSRepositoryFromRepos(repos *Repositories) *SMSRepository {
	if repos == nil || repos.Devices == nil || repos.Devices.pool == nil {
		return nil
	}
	return NewSMSRepository(repos.Devices.pool)
}

// SMSAnalysisRecord is a single persisted analysis outcome.
type SMSAnalysisRecord struct {
	ID          uuid.UUID
	DeviceID    string
	SenderHash  string // SHA-256 hex of sender; empty when no sender provided
	ThreatLevel string
	RiskScore   float64
	IsThreat    bool
	Categories  []string
	AnalyzedAt  time.Time
}

// SMSFalsePositiveRecord is a user report that a message was wrongly flagged.
type SMSFalsePositiveRecord struct {
	ID         uuid.UUID
	DeviceID   string
	MessageID  string // optional client-side message id
	SenderHash string // optional SHA-256 hex of sender
	Reason     string // optional free-text reason
	ReportedAt time.Time
}

// SMSTrendPoint is one day of analysis activity.
type SMSTrendPoint struct {
	Date     string `json:"date"` // YYYY-MM-DD
	Analyzed int64  `json:"analyzed"`
	Threats  int64  `json:"threats"`
}

// SMSDeviceStats aggregates analysis outcomes for one device.
type SMSDeviceStats struct {
	TotalAnalyzed   int64
	ThreatsDetected int64
	ThreatsByLevel  map[string]int64
	ThreatsByType   map[string]int64
	Last24hAnalyzed int64
	Last24hThreats  int64
	Last30DaysTrend []SMSTrendPoint
	FalsePositives  int64
	LastAnalyzedAt  *time.Time
}

const smsAnalysisInsert = `
INSERT INTO orbguard_lab.sms_analyses
    (id, device_id, sender_hash, threat_level, risk_score, is_threat, categories, analyzed_at)
VALUES ($1, $2, NULLIF($3, ''), $4, $5, $6, $7, $8)
`

// InsertAnalysis stores a single analysis outcome.
func (r *SMSRepository) InsertAnalysis(ctx context.Context, rec *SMSAnalysisRecord) error {
	if rec.ID == uuid.Nil {
		rec.ID = uuid.New()
	}
	if rec.AnalyzedAt.IsZero() {
		rec.AnalyzedAt = time.Now().UTC()
	}
	categories, err := marshalCategories(rec.Categories)
	if err != nil {
		return fmt.Errorf("marshal categories: %w", err)
	}

	_, err = r.pool.Exec(ctx, smsAnalysisInsert,
		rec.ID,
		rec.DeviceID,
		rec.SenderHash,
		rec.ThreatLevel,
		rec.RiskScore,
		rec.IsThreat,
		categories,
		rec.AnalyzedAt,
	)
	if err != nil {
		return fmt.Errorf("insert sms analysis: %w", err)
	}
	return nil
}

// InsertAnalysisBatch stores multiple analysis outcomes in one round trip.
func (r *SMSRepository) InsertAnalysisBatch(ctx context.Context, recs []SMSAnalysisRecord) error {
	if len(recs) == 0 {
		return nil
	}

	batch := &pgx.Batch{}
	for i := range recs {
		rec := &recs[i]
		if rec.ID == uuid.Nil {
			rec.ID = uuid.New()
		}
		if rec.AnalyzedAt.IsZero() {
			rec.AnalyzedAt = time.Now().UTC()
		}
		categories, err := marshalCategories(rec.Categories)
		if err != nil {
			return fmt.Errorf("marshal categories: %w", err)
		}
		batch.Queue(smsAnalysisInsert,
			rec.ID,
			rec.DeviceID,
			rec.SenderHash,
			rec.ThreatLevel,
			rec.RiskScore,
			rec.IsThreat,
			categories,
			rec.AnalyzedAt,
		)
	}

	results := r.pool.SendBatch(ctx, batch)
	defer results.Close()

	for range recs {
		if _, err := results.Exec(); err != nil {
			return fmt.Errorf("insert sms analysis batch: %w", err)
		}
	}
	return nil
}

// InsertFalsePositive stores a user-reported false positive.
func (r *SMSRepository) InsertFalsePositive(ctx context.Context, rec *SMSFalsePositiveRecord) error {
	if rec.ID == uuid.Nil {
		rec.ID = uuid.New()
	}
	if rec.ReportedAt.IsZero() {
		rec.ReportedAt = time.Now().UTC()
	}

	query := `
INSERT INTO orbguard_lab.sms_false_positives
    (id, device_id, message_id, sender_hash, reason, reported_at)
VALUES ($1, $2, NULLIF($3, ''), NULLIF($4, ''), NULLIF($5, ''), $6)
`
	_, err := r.pool.Exec(ctx, query,
		rec.ID,
		rec.DeviceID,
		rec.MessageID,
		rec.SenderHash,
		rec.Reason,
		rec.ReportedAt,
	)
	if err != nil {
		return fmt.Errorf("insert sms false positive: %w", err)
	}
	return nil
}

// GetDeviceStats aggregates analysis outcomes for the given device:
// totals, threats by level, threats by category, last-24h activity and
// a per-day trend over the last 30 days.
func (r *SMSRepository) GetDeviceStats(ctx context.Context, deviceID string) (*SMSDeviceStats, error) {
	stats := &SMSDeviceStats{
		ThreatsByLevel: map[string]int64{
			"critical": 0,
			"high":     0,
			"medium":   0,
			"low":      0,
		},
		ThreatsByType:   map[string]int64{},
		Last30DaysTrend: []SMSTrendPoint{},
	}

	// Totals, by-level counts and last-24h activity in a single scan.
	totalsQuery := `
SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE is_threat),
    COUNT(*) FILTER (WHERE is_threat AND threat_level = 'critical'),
    COUNT(*) FILTER (WHERE is_threat AND threat_level = 'high'),
    COUNT(*) FILTER (WHERE is_threat AND threat_level = 'medium'),
    COUNT(*) FILTER (WHERE is_threat AND threat_level = 'low'),
    COUNT(*) FILTER (WHERE analyzed_at > NOW() - INTERVAL '24 hours'),
    COUNT(*) FILTER (WHERE is_threat AND analyzed_at > NOW() - INTERVAL '24 hours'),
    MAX(analyzed_at)
FROM orbguard_lab.sms_analyses
WHERE device_id = $1
`
	var critical, high, medium, low int64
	var lastAnalyzed *time.Time
	err := r.pool.QueryRow(ctx, totalsQuery, deviceID).Scan(
		&stats.TotalAnalyzed,
		&stats.ThreatsDetected,
		&critical,
		&high,
		&medium,
		&low,
		&stats.Last24hAnalyzed,
		&stats.Last24hThreats,
		&lastAnalyzed,
	)
	if err != nil {
		return nil, fmt.Errorf("sms stats totals: %w", err)
	}
	stats.ThreatsByLevel["critical"] = critical
	stats.ThreatsByLevel["high"] = high
	stats.ThreatsByLevel["medium"] = medium
	stats.ThreatsByLevel["low"] = low
	stats.LastAnalyzedAt = lastAnalyzed

	// Threats grouped by category (categories is a JSON array of strings).
	byTypeQuery := `
SELECT cat, COUNT(*)
FROM orbguard_lab.sms_analyses,
     jsonb_array_elements_text(categories) AS cat
WHERE device_id = $1 AND is_threat
GROUP BY cat
ORDER BY COUNT(*) DESC
`
	rows, err := r.pool.Query(ctx, byTypeQuery, deviceID)
	if err != nil {
		return nil, fmt.Errorf("sms stats by type: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var cat string
		var count int64
		if err := rows.Scan(&cat, &count); err != nil {
			return nil, fmt.Errorf("scan sms stats by type: %w", err)
		}
		stats.ThreatsByType[cat] = count
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("sms stats by type rows: %w", err)
	}

	// Daily trend over the last 30 days.
	trendQuery := `
SELECT
    to_char(date_trunc('day', analyzed_at), 'YYYY-MM-DD') AS day,
    COUNT(*),
    COUNT(*) FILTER (WHERE is_threat)
FROM orbguard_lab.sms_analyses
WHERE device_id = $1 AND analyzed_at > NOW() - INTERVAL '30 days'
GROUP BY 1
ORDER BY 1
`
	trendRows, err := r.pool.Query(ctx, trendQuery, deviceID)
	if err != nil {
		return nil, fmt.Errorf("sms stats trend: %w", err)
	}
	defer trendRows.Close()
	for trendRows.Next() {
		var point SMSTrendPoint
		if err := trendRows.Scan(&point.Date, &point.Analyzed, &point.Threats); err != nil {
			return nil, fmt.Errorf("scan sms stats trend: %w", err)
		}
		stats.Last30DaysTrend = append(stats.Last30DaysTrend, point)
	}
	if err := trendRows.Err(); err != nil {
		return nil, fmt.Errorf("sms stats trend rows: %w", err)
	}

	// False-positive reports for this device.
	fpQuery := `SELECT COUNT(*) FROM orbguard_lab.sms_false_positives WHERE device_id = $1`
	if err := r.pool.QueryRow(ctx, fpQuery, deviceID).Scan(&stats.FalsePositives); err != nil {
		return nil, fmt.Errorf("sms stats false positives: %w", err)
	}

	return stats, nil
}

// marshalCategories serialises the category list to a JSON array,
// guaranteeing a non-null jsonb value.
func marshalCategories(categories []string) ([]byte, error) {
	if categories == nil {
		categories = []string{}
	}
	return json.Marshal(categories)
}
