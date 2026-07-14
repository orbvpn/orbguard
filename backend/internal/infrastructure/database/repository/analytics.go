package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"orbguard-lab/internal/domain/models"
)

// ============================================================================
// AnalyticsRepository - read-only aggregation queries over indicators,
// campaigns, sources, update_history and community_reports.
// ============================================================================

// AnalyticsRepository provides aggregation queries for analytics endpoints
type AnalyticsRepository struct {
	pool *pgxpool.Pool
}

// NewAnalyticsRepository creates a new analytics repository
func NewAnalyticsRepository(pool *pgxpool.Pool) *AnalyticsRepository {
	return &AnalyticsRepository{pool: pool}
}

// NewAnalyticsRepositoryFromRepos derives an analytics repository from an
// existing Repositories bundle (re-uses the indicator repository's pool).
func NewAnalyticsRepositoryFromRepos(repos *Repositories) *AnalyticsRepository {
	if repos == nil || repos.Indicators == nil || repos.Indicators.pool == nil {
		return nil
	}
	return NewAnalyticsRepository(repos.Indicators.pool)
}

// CategoryCountRow is a generic (category, count) aggregation row
type CategoryCountRow struct {
	Category string
	Count    int64
}

// TrendBucketRow is one time bucket of new-indicator counts split by severity
type TrendBucketRow struct {
	Bucket   int
	Count    int64
	Critical int64
	High     int64
	Medium   int64
	Low      int64
}

// TopIndicatorRow is a top-indicator aggregation row
type TopIndicatorRow struct {
	Value       string
	Type        string
	Severity    string
	Confidence  float64
	ReportCount int64
	FirstSeen   time.Time
	LastSeen    time.Time
	Campaign    string
	Tags        []string
	Country     string
	ASN         string
}

// MitreCountRow is a MITRE technique aggregation row
type MitreCountRow struct {
	TechniqueID string
	Count       int64
	Campaigns   int64
}

// CampaignInsightRow is an active-campaign aggregation row
type CampaignInsightRow struct {
	ID             uuid.UUID
	Name           string
	Status         string
	IndicatorCount int64
	NewIndicators  int64
	TopSeverity    string
	TargetSectors  []string
	TargetRegions  []string
	FirstSeen      time.Time
	LastSeen       time.Time
	MitreTactics   []string
}

// SourceHealthRow is a per-source health aggregation row
type SourceHealthRow struct {
	ID             uuid.UUID
	Slug           string
	Name           string
	SourceStatus   string
	LastFetched    *time.Time
	NextFetch      *time.Time
	LastError      string
	ErrorCount     int64
	IndicatorCount int64
	Attempts       int64
	Successes      int64
	AvgLatencyMs   float64
	LastSuccess    *time.Time
	LastFailure    *time.Time
	NewToday       int64
}

// GeoCountryRow is a per-country aggregation row
type GeoCountryRow struct {
	CountryCode string
	Count       int64
	TopSeverity string
}

// ReportReviewMetrics aggregates community report review outcomes
type ReportReviewMetrics struct {
	Total             int64
	Pending           int64
	Reviewing         int64
	Approved          int64
	Rejected          int64
	Duplicate         int64
	AvgResolveMinutes *float64
}

// rangeOverlap is the WHERE fragment for "indicator was alive within range"
const rangeOverlap = "last_seen >= $1 AND first_seen <= $2"

// SeverityDistribution returns indicator counts grouped by severity for the range
func (r *AnalyticsRepository) SeverityDistribution(ctx context.Context, start, end time.Time) ([]CategoryCountRow, error) {
	query := fmt.Sprintf(`
		SELECT severity::text, COUNT(*)
		FROM indicators
		WHERE %s
		GROUP BY severity
		ORDER BY COUNT(*) DESC`, rangeOverlap)
	return r.queryCategoryCounts(ctx, query, start, end)
}

// TypeDistribution returns indicator counts grouped by type for the range
func (r *AnalyticsRepository) TypeDistribution(ctx context.Context, start, end time.Time) ([]CategoryCountRow, error) {
	query := fmt.Sprintf(`
		SELECT type::text, COUNT(*)
		FROM indicators
		WHERE %s
		GROUP BY type
		ORDER BY COUNT(*) DESC`, rangeOverlap)
	return r.queryCategoryCounts(ctx, query, start, end)
}

// PlatformDistribution returns indicator counts grouped by platform for the range
func (r *AnalyticsRepository) PlatformDistribution(ctx context.Context, start, end time.Time) ([]CategoryCountRow, error) {
	query := fmt.Sprintf(`
		SELECT p::text, COUNT(*)
		FROM indicators, unnest(platforms) AS p
		WHERE %s
		GROUP BY p
		ORDER BY COUNT(*) DESC`, rangeOverlap)
	return r.queryCategoryCounts(ctx, query, start, end)
}

// SourceDistribution returns indicator counts grouped by source name for the range
func (r *AnalyticsRepository) SourceDistribution(ctx context.Context, start, end time.Time) ([]CategoryCountRow, error) {
	query := fmt.Sprintf(`
		SELECT source_name, COUNT(*)
		FROM indicators
		WHERE %s
		GROUP BY source_name
		ORDER BY COUNT(*) DESC
		LIMIT 20`, rangeOverlap)
	return r.queryCategoryCounts(ctx, query, start, end)
}

func (r *AnalyticsRepository) queryCategoryCounts(ctx context.Context, query string, args ...interface{}) ([]CategoryCountRow, error) {
	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to query category counts: %w", err)
	}
	defer rows.Close()

	var result []CategoryCountRow
	for rows.Next() {
		var row CategoryCountRow
		if err := rows.Scan(&row.Category, &row.Count); err != nil {
			return nil, fmt.Errorf("failed to scan category count: %w", err)
		}
		result = append(result, row)
	}
	return result, rows.Err()
}

// TrendBuckets returns new-indicator counts (by first_seen) grouped into
// fixed-size time buckets within [start, end)
func (r *AnalyticsRepository) TrendBuckets(ctx context.Context, start, end time.Time, bucketSeconds int64) ([]TrendBucketRow, error) {
	if bucketSeconds <= 0 {
		return nil, fmt.Errorf("bucketSeconds must be positive")
	}
	query := `
		SELECT FLOOR(EXTRACT(EPOCH FROM (first_seen - $1)) / $3)::int AS bucket,
		       COUNT(*),
		       COUNT(*) FILTER (WHERE severity = 'critical'),
		       COUNT(*) FILTER (WHERE severity = 'high'),
		       COUNT(*) FILTER (WHERE severity = 'medium'),
		       COUNT(*) FILTER (WHERE severity = 'low')
		FROM indicators
		WHERE first_seen >= $1 AND first_seen < $2
		GROUP BY bucket
		ORDER BY bucket`

	rows, err := r.pool.Query(ctx, query, start, end, bucketSeconds)
	if err != nil {
		return nil, fmt.Errorf("failed to query trend buckets: %w", err)
	}
	defer rows.Close()

	var result []TrendBucketRow
	for rows.Next() {
		var row TrendBucketRow
		if err := rows.Scan(&row.Bucket, &row.Count, &row.Critical, &row.High, &row.Medium, &row.Low); err != nil {
			return nil, fmt.Errorf("failed to scan trend bucket: %w", err)
		}
		result = append(result, row)
	}
	return result, rows.Err()
}

// NewIndicatorCounts returns counts of indicators first seen within the range
func (r *AnalyticsRepository) NewIndicatorCounts(ctx context.Context, start, end time.Time) (total, critical int64, err error) {
	query := `
		SELECT COUNT(*),
		       COUNT(*) FILTER (WHERE severity = 'critical')
		FROM indicators
		WHERE first_seen >= $1 AND first_seen < $2`
	if err = r.pool.QueryRow(ctx, query, start, end).Scan(&total, &critical); err != nil {
		return 0, 0, fmt.Errorf("failed to count new indicators: %w", err)
	}
	return total, critical, nil
}

// ActiveCampaignCount returns the number of campaigns with activity in the range
func (r *AnalyticsRepository) ActiveCampaignCount(ctx context.Context, start, end time.Time) (int64, error) {
	var count int64
	query := `SELECT COUNT(*) FROM campaigns WHERE last_seen >= $1 AND first_seen <= $2`
	if err := r.pool.QueryRow(ctx, query, start, end).Scan(&count); err != nil {
		return 0, fmt.Errorf("failed to count active campaigns: %w", err)
	}
	return count, nil
}

// ActiveExpiredCounts returns counts of non-expired and expired indicators
func (r *AnalyticsRepository) ActiveExpiredCounts(ctx context.Context) (active, expired int64, err error) {
	query := `
		SELECT COUNT(*) FILTER (WHERE expires_at IS NULL OR expires_at > NOW()),
		       COUNT(*) FILTER (WHERE expires_at IS NOT NULL AND expires_at <= NOW())
		FROM indicators`
	if err = r.pool.QueryRow(ctx, query).Scan(&active, &expired); err != nil {
		return 0, 0, fmt.Errorf("failed to count active/expired indicators: %w", err)
	}
	return active, expired, nil
}

// TopIndicators returns the most reported indicators alive within the range
func (r *AnalyticsRepository) TopIndicators(ctx context.Context, start, end time.Time, limit int) ([]TopIndicatorRow, error) {
	query := `
		SELECT i.value, i.type::text, i.severity::text, COALESCE(i.confidence, 0),
		       i.report_count, i.first_seen, i.last_seen,
		       COALESCE(c.name, ''), COALESCE(i.tags, '{}')
		FROM indicators i
		LEFT JOIN campaigns c ON i.campaign_id = c.id
		WHERE i.last_seen >= $1 AND i.first_seen <= $2
		ORDER BY i.report_count DESC, i.confidence DESC NULLS LAST, i.last_seen DESC
		LIMIT $3`

	rows, err := r.pool.Query(ctx, query, start, end, limit)
	if err != nil {
		return nil, fmt.Errorf("failed to query top indicators: %w", err)
	}
	defer rows.Close()

	var result []TopIndicatorRow
	for rows.Next() {
		var row TopIndicatorRow
		var reportCount int32
		if err := rows.Scan(&row.Value, &row.Type, &row.Severity, &row.Confidence,
			&reportCount, &row.FirstSeen, &row.LastSeen, &row.Campaign, &row.Tags); err != nil {
			return nil, fmt.Errorf("failed to scan top indicator: %w", err)
		}
		row.ReportCount = int64(reportCount)
		result = append(result, row)
	}
	return result, rows.Err()
}

// TopIndicatorsByType returns the most reported indicators of the given types
// alive within the range. Country/ASN are taken from indicator metadata when present.
func (r *AnalyticsRepository) TopIndicatorsByType(ctx context.Context, start, end time.Time, types []string, limit int) ([]TopIndicatorRow, error) {
	query := `
		SELECT i.value, i.type::text, i.severity::text, COALESCE(i.confidence, 0),
		       i.report_count, i.first_seen, i.last_seen,
		       COALESCE(i.tags, '{}'),
		       COALESCE(i.metadata->>'country', ''), COALESCE(i.metadata->>'asn', '')
		FROM indicators i
		WHERE i.last_seen >= $1 AND i.first_seen <= $2 AND i.type = ANY($3::indicator_type[])
		ORDER BY i.report_count DESC, i.confidence DESC NULLS LAST, i.last_seen DESC
		LIMIT $4`

	rows, err := r.pool.Query(ctx, query, start, end, types, limit)
	if err != nil {
		return nil, fmt.Errorf("failed to query top indicators by type: %w", err)
	}
	defer rows.Close()

	var result []TopIndicatorRow
	for rows.Next() {
		var row TopIndicatorRow
		var reportCount int32
		if err := rows.Scan(&row.Value, &row.Type, &row.Severity, &row.Confidence,
			&reportCount, &row.FirstSeen, &row.LastSeen, &row.Tags, &row.Country, &row.ASN); err != nil {
			return nil, fmt.Errorf("failed to scan top indicator by type: %w", err)
		}
		row.ReportCount = int64(reportCount)
		result = append(result, row)
	}
	return result, rows.Err()
}

// MitreTechniqueCounts returns indicator counts per MITRE technique within the
// range, merged with the number of campaigns referencing each technique
func (r *AnalyticsRepository) MitreTechniqueCounts(ctx context.Context, start, end time.Time, limit int) ([]MitreCountRow, error) {
	query := `
		SELECT t, COUNT(*)
		FROM indicators, unnest(mitre_techniques) AS t
		WHERE last_seen >= $1 AND first_seen <= $2
		GROUP BY t
		ORDER BY COUNT(*) DESC
		LIMIT $3`

	rows, err := r.pool.Query(ctx, query, start, end, limit)
	if err != nil {
		return nil, fmt.Errorf("failed to query mitre technique counts: %w", err)
	}
	defer rows.Close()

	var result []MitreCountRow
	for rows.Next() {
		var row MitreCountRow
		if err := rows.Scan(&row.TechniqueID, &row.Count); err != nil {
			return nil, fmt.Errorf("failed to scan mitre technique count: %w", err)
		}
		result = append(result, row)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	if len(result) == 0 {
		return result, nil
	}

	// Campaign counts per technique
	campaignCounts := make(map[string]int64)
	cRows, err := r.pool.Query(ctx, `
		SELECT t, COUNT(DISTINCT id)
		FROM campaigns, unnest(mitre_techniques) AS t
		GROUP BY t`)
	if err != nil {
		return nil, fmt.Errorf("failed to query campaign technique counts: %w", err)
	}
	defer cRows.Close()
	for cRows.Next() {
		var technique string
		var count int64
		if err := cRows.Scan(&technique, &count); err != nil {
			return nil, fmt.Errorf("failed to scan campaign technique count: %w", err)
		}
		campaignCounts[technique] = count
	}
	if err := cRows.Err(); err != nil {
		return nil, err
	}

	for i := range result {
		result[i].Campaigns = campaignCounts[result[i].TechniqueID]
	}
	return result, nil
}

// ActiveCampaignInsights returns active campaigns with new-indicator counts in
// the range and the highest severity among their indicators
func (r *AnalyticsRepository) ActiveCampaignInsights(ctx context.Context, start, end time.Time) ([]CampaignInsightRow, error) {
	query := `
		SELECT c.id, c.name, c.status::text, c.indicator_count,
		       COALESCE(c.target_sectors, '{}'), COALESCE(c.target_regions, '{}'),
		       COALESCE(c.first_seen, c.created_at), COALESCE(c.last_seen, c.updated_at),
		       COALESCE(c.mitre_tactics, '{}'),
		       COALESCE(n.new_count, 0),
		       COALESCE(s.top_severity, '')
		FROM campaigns c
		LEFT JOIN LATERAL (
			SELECT COUNT(*) AS new_count
			FROM indicators i
			WHERE i.campaign_id = c.id AND i.first_seen >= $1 AND i.first_seen < $2
		) n ON TRUE
		LEFT JOIN LATERAL (
			SELECT i.severity::text AS top_severity
			FROM indicators i
			WHERE i.campaign_id = c.id
			ORDER BY CASE i.severity::text
				WHEN 'critical' THEN 0
				WHEN 'high' THEN 1
				WHEN 'medium' THEN 2
				WHEN 'low' THEN 3
				ELSE 4 END
			LIMIT 1
		) s ON TRUE
		WHERE c.status = 'active'
		ORDER BY c.last_seen DESC NULLS LAST`

	rows, err := r.pool.Query(ctx, query, start, end)
	if err != nil {
		return nil, fmt.Errorf("failed to query campaign insights: %w", err)
	}
	defer rows.Close()

	var result []CampaignInsightRow
	for rows.Next() {
		var row CampaignInsightRow
		var indicatorCount int32
		if err := rows.Scan(&row.ID, &row.Name, &row.Status, &indicatorCount,
			&row.TargetSectors, &row.TargetRegions, &row.FirstSeen, &row.LastSeen,
			&row.MitreTactics, &row.NewIndicators, &row.TopSeverity); err != nil {
			return nil, fmt.Errorf("failed to scan campaign insight: %w", err)
		}
		row.IndicatorCount = int64(indicatorCount)
		result = append(result, row)
	}
	return result, rows.Err()
}

// SourceHealth returns per-source fetch health derived from sources and the
// last 7 days of update_history
func (r *AnalyticsRepository) SourceHealth(ctx context.Context) ([]SourceHealthRow, error) {
	query := `
		SELECT s.id, s.slug, s.name, s.status::text,
		       s.last_fetched, s.next_fetch, COALESCE(s.last_error, ''), s.error_count, s.indicator_count,
		       COALESCE(h.attempts, 0), COALESCE(h.successes, 0), COALESCE(h.avg_ms, 0)::float8,
		       h.last_success, h.last_failure,
		       COALESCE(t.new_today, 0)
		FROM sources s
		LEFT JOIN LATERAL (
			SELECT COUNT(*) AS attempts,
			       COUNT(*) FILTER (WHERE success) AS successes,
			       AVG(EXTRACT(EPOCH FROM duration) * 1000) AS avg_ms,
			       MAX(completed_at) FILTER (WHERE success) AS last_success,
			       MAX(completed_at) FILTER (WHERE NOT success) AS last_failure
			FROM update_history uh
			WHERE uh.source_id = s.id AND uh.started_at >= NOW() - INTERVAL '7 days'
		) h ON TRUE
		LEFT JOIN LATERAL (
			SELECT SUM(new_indicators) AS new_today
			FROM update_history uh2
			WHERE uh2.source_id = s.id AND uh2.started_at >= date_trunc('day', NOW())
		) t ON TRUE
		ORDER BY s.name`

	rows, err := r.pool.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to query source health: %w", err)
	}
	defer rows.Close()

	var result []SourceHealthRow
	for rows.Next() {
		var row SourceHealthRow
		var errorCount, indicatorCount int32
		if err := rows.Scan(&row.ID, &row.Slug, &row.Name, &row.SourceStatus,
			&row.LastFetched, &row.NextFetch, &row.LastError, &errorCount, &indicatorCount,
			&row.Attempts, &row.Successes, &row.AvgLatencyMs,
			&row.LastSuccess, &row.LastFailure, &row.NewToday); err != nil {
			return nil, fmt.Errorf("failed to scan source health: %w", err)
		}
		row.ErrorCount = int64(errorCount)
		row.IndicatorCount = int64(indicatorCount)
		result = append(result, row)
	}
	return result, rows.Err()
}

// GeoCountryDistribution aggregates indicators by the country recorded in
// their enrichment metadata. Indicators without country metadata are excluded.
func (r *AnalyticsRepository) GeoCountryDistribution(ctx context.Context, start, end time.Time, limit int) ([]GeoCountryRow, error) {
	query := `
		SELECT UPPER(metadata->>'country') AS cc,
		       COUNT(*),
		       MIN(CASE severity::text
		           WHEN 'critical' THEN 0
		           WHEN 'high' THEN 1
		           WHEN 'medium' THEN 2
		           WHEN 'low' THEN 3
		           ELSE 4 END)
		FROM indicators
		WHERE last_seen >= $1 AND first_seen <= $2
		  AND metadata IS NOT NULL
		  AND COALESCE(metadata->>'country', '') <> ''
		GROUP BY cc
		ORDER BY COUNT(*) DESC
		LIMIT $3`

	rows, err := r.pool.Query(ctx, query, start, end, limit)
	if err != nil {
		return nil, fmt.Errorf("failed to query geo distribution: %w", err)
	}
	defer rows.Close()

	severityNames := []string{"critical", "high", "medium", "low", "info"}
	var result []GeoCountryRow
	for rows.Next() {
		var row GeoCountryRow
		var sevRank int
		if err := rows.Scan(&row.CountryCode, &row.Count, &sevRank); err != nil {
			return nil, fmt.Errorf("failed to scan geo row: %w", err)
		}
		if sevRank >= 0 && sevRank < len(severityNames) {
			row.TopSeverity = severityNames[sevRank]
		}
		result = append(result, row)
	}
	return result, rows.Err()
}

// CommunityReportMetrics aggregates community report review outcomes for the range
func (r *AnalyticsRepository) CommunityReportMetrics(ctx context.Context, start, end time.Time) (*ReportReviewMetrics, error) {
	query := `
		SELECT COUNT(*),
		       COUNT(*) FILTER (WHERE status = 'pending'),
		       COUNT(*) FILTER (WHERE status = 'reviewing'),
		       COUNT(*) FILTER (WHERE status = 'approved'),
		       COUNT(*) FILTER (WHERE status = 'rejected'),
		       COUNT(*) FILTER (WHERE status = 'duplicate'),
		       (AVG(EXTRACT(EPOCH FROM (reviewed_at - reported_at)) / 60.0)
		           FILTER (WHERE reviewed_at IS NOT NULL))::float8
		FROM community_reports
		WHERE reported_at >= $1 AND reported_at < $2`

	m := &ReportReviewMetrics{}
	var avgResolve pgtype.Float8
	err := r.pool.QueryRow(ctx, query, start, end).Scan(
		&m.Total, &m.Pending, &m.Reviewing, &m.Approved, &m.Rejected, &m.Duplicate, &avgResolve)
	if err != nil {
		return nil, fmt.Errorf("failed to query community report metrics: %w", err)
	}
	if avgResolve.Valid {
		v := avgResolve.Float64
		m.AvgResolveMinutes = &v
	}
	return m, nil
}

// CommunityReportsBySeverity returns community report counts grouped by severity
func (r *AnalyticsRepository) CommunityReportsBySeverity(ctx context.Context, start, end time.Time) ([]CategoryCountRow, error) {
	return r.queryCategoryCounts(ctx, `
		SELECT severity::text, COUNT(*)
		FROM community_reports
		WHERE reported_at >= $1 AND reported_at < $2
		GROUP BY severity
		ORDER BY COUNT(*) DESC`, start, end)
}

// CommunityReportsByType returns community report counts grouped by indicator type
func (r *AnalyticsRepository) CommunityReportsByType(ctx context.Context, start, end time.Time) ([]CategoryCountRow, error) {
	return r.queryCategoryCounts(ctx, `
		SELECT indicator_type::text, COUNT(*)
		FROM community_reports
		WHERE reported_at >= $1 AND reported_at < $2
		GROUP BY indicator_type
		ORDER BY COUNT(*) DESC`, start, end)
}

// CommunityReportTrend returns community report counts grouped into fixed-size
// time buckets within [start, end), split by severity
func (r *AnalyticsRepository) CommunityReportTrend(ctx context.Context, start, end time.Time, bucketSeconds int64) ([]TrendBucketRow, error) {
	if bucketSeconds <= 0 {
		return nil, fmt.Errorf("bucketSeconds must be positive")
	}
	query := `
		SELECT FLOOR(EXTRACT(EPOCH FROM (reported_at - $1)) / $3)::int AS bucket,
		       COUNT(*),
		       COUNT(*) FILTER (WHERE severity = 'critical'),
		       COUNT(*) FILTER (WHERE severity = 'high'),
		       COUNT(*) FILTER (WHERE severity = 'medium'),
		       COUNT(*) FILTER (WHERE severity = 'low')
		FROM community_reports
		WHERE reported_at >= $1 AND reported_at < $2
		GROUP BY bucket
		ORDER BY bucket`

	rows, err := r.pool.Query(ctx, query, start, end, bucketSeconds)
	if err != nil {
		return nil, fmt.Errorf("failed to query community report trend: %w", err)
	}
	defer rows.Close()

	var result []TrendBucketRow
	for rows.Next() {
		var row TrendBucketRow
		if err := rows.Scan(&row.Bucket, &row.Count, &row.Critical, &row.High, &row.Medium, &row.Low); err != nil {
			return nil, fmt.Errorf("failed to scan community report trend: %w", err)
		}
		result = append(result, row)
	}
	return result, rows.Err()
}

// ============================================================================
// AnalyticsReportRepository - persistence for generated analytics reports
// ============================================================================

// AnalyticsReportRepository persists generated analytics reports
type AnalyticsReportRepository struct {
	pool *pgxpool.Pool
}

// NewAnalyticsReportRepository creates a new analytics report repository
func NewAnalyticsReportRepository(pool *pgxpool.Pool) *AnalyticsReportRepository {
	return &AnalyticsReportRepository{pool: pool}
}

// NewAnalyticsReportRepositoryFromRepos derives a report repository from an
// existing Repositories bundle (re-uses the indicator repository's pool).
func NewAnalyticsReportRepositoryFromRepos(repos *Repositories) *AnalyticsReportRepository {
	if repos == nil || repos.Indicators == nil || repos.Indicators.pool == nil {
		return nil
	}
	return NewAnalyticsReportRepository(repos.Indicators.pool)
}

// Create inserts a new pending report row
func (r *AnalyticsReportRepository) Create(ctx context.Context, report *models.AnalyticsReport) error {
	id, err := uuid.Parse(report.ID)
	if err != nil {
		return fmt.Errorf("invalid report id: %w", err)
	}

	var params []byte
	if report.Parameters != nil {
		params, err = json.Marshal(report.Parameters)
		if err != nil {
			return fmt.Errorf("failed to marshal report params: %w", err)
		}
	}

	_, err = r.pool.Exec(ctx, `
		INSERT INTO analytics_reports
			(id, name, type, format, status, params, time_range_start, time_range_end, created_by, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
		id, report.Name, string(report.Type), string(report.Format), string(report.Status),
		params, report.TimeRange.Start, report.TimeRange.End,
		textOrNull(report.CreatedBy), report.CreatedAt)
	if err != nil {
		return fmt.Errorf("failed to insert analytics report: %w", err)
	}
	return nil
}

// SetStatus updates the lifecycle status of a report
func (r *AnalyticsReportRepository) SetStatus(ctx context.Context, id uuid.UUID, status models.AnalyticsReportStatus) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE analytics_reports SET status = $2 WHERE id = $1`, id, string(status))
	if err != nil {
		return fmt.Errorf("failed to update report status: %w", err)
	}
	return nil
}

// Complete marks a report as completed and stores its generated output
func (r *AnalyticsReportRepository) Complete(ctx context.Context, id uuid.UUID, content []byte, fileData []byte, expiresAt time.Time) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE analytics_reports
		SET status = 'completed',
		    content = $2,
		    file_data = $3,
		    file_size = $4,
		    completed_at = NOW(),
		    expires_at = $5,
		    error = NULL
		WHERE id = $1`,
		id, content, fileData, len(fileData), expiresAt)
	if err != nil {
		return fmt.Errorf("failed to complete report: %w", err)
	}
	return nil
}

// Fail marks a report as failed with the given error message
func (r *AnalyticsReportRepository) Fail(ctx context.Context, id uuid.UUID, errMsg string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE analytics_reports
		SET status = 'failed', error = $2, completed_at = NOW()
		WHERE id = $1`, id, errMsg)
	if err != nil {
		return fmt.Errorf("failed to mark report failed: %w", err)
	}
	return nil
}

const reportColumns = `id, name, type, format, status, params,
	time_range_start, time_range_end, file_size, error, created_by,
	created_at, completed_at, expires_at`

// GetByID retrieves a report's metadata (without file bytes)
func (r *AnalyticsReportRepository) GetByID(ctx context.Context, id uuid.UUID) (*models.AnalyticsReport, error) {
	row := r.pool.QueryRow(ctx,
		fmt.Sprintf(`SELECT %s FROM analytics_reports WHERE id = $1`, reportColumns), id)
	report, err := scanAnalyticsReport(row)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to get analytics report: %w", err)
	}
	return report, nil
}

// List returns reports, optionally filtered by creator, newest first
func (r *AnalyticsReportRepository) List(ctx context.Context, createdBy string, limit int) ([]*models.AnalyticsReport, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}

	var (
		rows pgx.Rows
		err  error
	)
	if createdBy != "" {
		rows, err = r.pool.Query(ctx, fmt.Sprintf(
			`SELECT %s FROM analytics_reports WHERE created_by = $1 ORDER BY created_at DESC LIMIT $2`,
			reportColumns), createdBy, limit)
	} else {
		rows, err = r.pool.Query(ctx, fmt.Sprintf(
			`SELECT %s FROM analytics_reports ORDER BY created_at DESC LIMIT $1`,
			reportColumns), limit)
	}
	if err != nil {
		return nil, fmt.Errorf("failed to list analytics reports: %w", err)
	}
	defer rows.Close()

	var reports []*models.AnalyticsReport
	for rows.Next() {
		report, err := scanAnalyticsReport(rows)
		if err != nil {
			return nil, fmt.Errorf("failed to scan analytics report: %w", err)
		}
		reports = append(reports, report)
	}
	return reports, rows.Err()
}

// GetFile retrieves the rendered file bytes plus the metadata needed to serve it
func (r *AnalyticsReportRepository) GetFile(ctx context.Context, id uuid.UUID) (data []byte, report *models.AnalyticsReport, err error) {
	row := r.pool.QueryRow(ctx, `
		SELECT file_data, name, type, format, status, created_by, expires_at
		FROM analytics_reports WHERE id = $1`, id)

	report = &models.AnalyticsReport{ID: id.String()}
	var (
		name, typeStr, formatStr, statusStr string
		createdBy                           pgtype.Text
		expiresAt                           pgtype.Timestamptz
	)
	if err = row.Scan(&data, &name, &typeStr, &formatStr, &statusStr, &createdBy, &expiresAt); err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil, nil
		}
		return nil, nil, fmt.Errorf("failed to get report file: %w", err)
	}
	report.Name = name
	report.Type = models.ReportType(typeStr)
	report.Format = models.ReportFormat(formatStr)
	report.Status = models.AnalyticsReportStatus(statusStr)
	report.CreatedBy = nullTextToString(createdBy)
	if expiresAt.Valid {
		report.ExpiresAt = expiresAt.Time
	}
	return data, report, nil
}

// DeleteExpired removes reports past their expiry
func (r *AnalyticsReportRepository) DeleteExpired(ctx context.Context) (int64, error) {
	tag, err := r.pool.Exec(ctx,
		`DELETE FROM analytics_reports WHERE expires_at IS NOT NULL AND expires_at < NOW()`)
	if err != nil {
		return 0, fmt.Errorf("failed to delete expired reports: %w", err)
	}
	return tag.RowsAffected(), nil
}

// scanAnalyticsReport scans a metadata row into a model
func scanAnalyticsReport(row pgx.Row) (*models.AnalyticsReport, error) {
	var (
		id                    uuid.UUID
		name, typeStr         string
		formatStr, statusStr  string
		params                []byte
		start, end            time.Time
		fileSize              int64
		errText, createdBy    pgtype.Text
		createdAt             time.Time
		completedAt, expireAt pgtype.Timestamptz
	)
	if err := row.Scan(&id, &name, &typeStr, &formatStr, &statusStr, &params,
		&start, &end, &fileSize, &errText, &createdBy,
		&createdAt, &completedAt, &expireAt); err != nil {
		return nil, err
	}

	report := &models.AnalyticsReport{
		ID:        id.String(),
		Name:      name,
		Type:      models.ReportType(typeStr),
		Format:    models.ReportFormat(formatStr),
		Status:    models.AnalyticsReportStatus(statusStr),
		TimeRange: models.AnalyticsTimeRange{Start: start, End: end},
		FileSize:  fileSize,
		Error:     nullTextToString(errText),
		CreatedBy: nullTextToString(createdBy),
		CreatedAt: createdAt,
	}
	if len(params) > 0 {
		_ = json.Unmarshal(params, &report.Parameters)
	}
	if completedAt.Valid {
		report.GeneratedAt = completedAt.Time
	}
	if expireAt.Valid {
		report.ExpiresAt = expireAt.Time
	}
	if report.Status == models.AnalyticsReportStatusCompleted {
		report.DownloadURL = "/api/v1/analytics/reports/" + report.ID + "/download"
	}
	return report, nil
}
