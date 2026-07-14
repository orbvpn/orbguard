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

// AppSecurityRepository persists app analysis history and user app reports.
type AppSecurityRepository struct {
	pool *pgxpool.Pool
}

// NewAppSecurityRepository creates a new app security repository.
func NewAppSecurityRepository(pool *pgxpool.Pool) *AppSecurityRepository {
	return &AppSecurityRepository{pool: pool}
}

// AppAnalysisRecord is a persisted app analysis row.
type AppAnalysisRecord struct {
	ID            uuid.UUID
	DeviceID      string
	UserID        string
	PackageName   string
	AppName       string
	Version       string
	InstallSource string
	RiskScore     float64
	RiskLevel     string
	Flags         map[string]interface{}
	AnalyzedAt    time.Time
}

// InsertAnalysis stores an app analysis result row.
func (r *AppSecurityRepository) InsertAnalysis(ctx context.Context, rec *AppAnalysisRecord) error {
	flags := rec.Flags
	if flags == nil {
		flags = map[string]interface{}{}
	}
	flagsJSON, err := json.Marshal(flags)
	if err != nil {
		return fmt.Errorf("failed to marshal analysis flags: %w", err)
	}

	if rec.ID == uuid.Nil {
		rec.ID = uuid.New()
	}
	if rec.AnalyzedAt.IsZero() {
		rec.AnalyzedAt = time.Now()
	}

	query := `
  INSERT INTO orbguard_lab.app_analyses
  (id, device_id, user_id, package_name, app_name, version,
   install_source, risk_score, risk_level, flags, analyzed_at)
  VALUES ($1, NULLIF($2,''), NULLIF($3,''), $4, NULLIF($5,''), NULLIF($6,''),
          NULLIF($7,''), $8, $9, $10, $11)
  `

	_, err = r.pool.Exec(
		ctx,
		query,
		rec.ID,
		rec.DeviceID,
		rec.UserID,
		rec.PackageName,
		rec.AppName,
		rec.Version,
		rec.InstallSource,
		rec.RiskScore,
		rec.RiskLevel,
		flagsJSON,
		rec.AnalyzedAt,
	)
	if err != nil {
		return fmt.Errorf("failed to insert app analysis: %w", err)
	}

	return nil
}

// AppReportRecord is a persisted user app report row.
type AppReportRecord struct {
	ID          uuid.UUID
	PackageName string
	ReportType  string
	Description string
	DeviceID    string
	UserID      string
	Status      string
	CreatedAt   time.Time
}

// InsertReport stores a user-submitted app report and returns its ID.
func (r *AppSecurityRepository) InsertReport(ctx context.Context, rec *AppReportRecord) (*AppReportRecord, error) {
	query := `
  INSERT INTO orbguard_lab.app_reports
  (package_name, report_type, description, device_id, user_id, status)
  VALUES ($1, $2, NULLIF($3,''), NULLIF($4,''), NULLIF($5,''), 'pending')
  RETURNING id, status, created_at
  `

	err := r.pool.QueryRow(
		ctx,
		query,
		rec.PackageName,
		rec.ReportType,
		rec.Description,
		rec.DeviceID,
		rec.UserID,
	).Scan(&rec.ID, &rec.Status, &rec.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("failed to insert app report: %w", err)
	}

	return rec, nil
}

// CountReportsForPackage returns the number of user reports filed against a package.
func (r *AppSecurityRepository) CountReportsForPackage(ctx context.Context, packageName string) (int64, error) {
	var count int64
	err := r.pool.QueryRow(
		ctx,
		`SELECT COUNT(*) FROM orbguard_lab.app_reports WHERE package_name = $1`,
		packageName,
	).Scan(&count)
	if err != nil {
		return 0, fmt.Errorf("failed to count app reports: %w", err)
	}
	return count, nil
}

// PackageAnalysisSummary aggregates the stored analysis history for one package.
type PackageAnalysisSummary struct {
	PackageName     string
	AnalysisCount   int64
	DeviceCount     int64
	AvgRiskScore    float64
	LatestRiskScore float64
	LatestRiskLevel string
	LatestAppName   string
	FirstAnalyzedAt time.Time
	LastAnalyzedAt  time.Time
}

// GetPackageSummary returns aggregated analysis history for a package.
// Returns (nil, nil) when no analysis history exists for the package.
func (r *AppSecurityRepository) GetPackageSummary(ctx context.Context, packageName string) (*PackageAnalysisSummary, error) {
	summary := &PackageAnalysisSummary{PackageName: packageName}

	aggQuery := `
  SELECT COUNT(*),
         COUNT(DISTINCT device_id),
         COALESCE(AVG(risk_score), 0),
         COALESCE(MIN(analyzed_at), NOW()),
         COALESCE(MAX(analyzed_at), NOW())
  FROM orbguard_lab.app_analyses
  WHERE package_name = $1
  `

	err := r.pool.QueryRow(ctx, aggQuery, packageName).Scan(
		&summary.AnalysisCount,
		&summary.DeviceCount,
		&summary.AvgRiskScore,
		&summary.FirstAnalyzedAt,
		&summary.LastAnalyzedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to aggregate app analyses: %w", err)
	}

	if summary.AnalysisCount == 0 {
		return nil, nil
	}

	latestQuery := `
  SELECT COALESCE(app_name, ''), risk_score, risk_level
  FROM orbguard_lab.app_analyses
  WHERE package_name = $1
  ORDER BY analyzed_at DESC
  LIMIT 1
  `

	err = r.pool.QueryRow(ctx, latestQuery, packageName).Scan(
		&summary.LatestAppName,
		&summary.LatestRiskScore,
		&summary.LatestRiskLevel,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			// Race: rows deleted between queries — treat as no history.
			return nil, nil
		}
		return nil, fmt.Errorf("failed to load latest app analysis: %w", err)
	}

	return summary, nil
}

// GetStats aggregates stored analysis rows into overall app security statistics.
// Aggregation is computed over the most recent analysis per package so that
// re-analyses do not double count an app.
func (r *AppSecurityRepository) GetStats(ctx context.Context) (*models.AppSecurityStats, error) {
	stats := &models.AppSecurityStats{
		BySafetyLevel:   make(map[string]int64),
		ByInstallSource: make(map[string]int64),
		TopRiskyApps:    []models.AppRiskSummary{},
	}

	const latestCTE = `
  WITH latest AS (
    SELECT DISTINCT ON (package_name) *
    FROM orbguard_lab.app_analyses
    ORDER BY package_name, analyzed_at DESC
  )
  `

	// Scalar aggregates.
	scalarQuery := latestCTE + `
  SELECT COUNT(*),
         COALESCE(AVG(risk_score), 0),
         COUNT(*) FILTER (WHERE COALESCE((flags->>'known_malware')::boolean, FALSE)),
         COUNT(*) FILTER (WHERE COALESCE((flags->>'sideloaded')::boolean, FALSE)),
         COUNT(*) FILTER (WHERE COALESCE((flags->>'tracker_count')::int, 0) > 0)
  FROM latest
  `

	err := r.pool.QueryRow(ctx, scalarQuery).Scan(
		&stats.TotalAppsAnalyzed,
		&stats.AverageRiskScore,
		&stats.MalwareDetected,
		&stats.SideloadedApps,
		&stats.AppsWithTrackers,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to aggregate app security stats: %w", err)
	}

	// Counts by risk level.
	levelQuery := latestCTE + `
  SELECT risk_level, COUNT(*)
  FROM latest
  GROUP BY risk_level
  `
	levelRows, err := r.pool.Query(ctx, levelQuery)
	if err != nil {
		return nil, fmt.Errorf("failed to aggregate stats by risk level: %w", err)
	}
	defer levelRows.Close()
	for levelRows.Next() {
		var level string
		var count int64
		if err := levelRows.Scan(&level, &count); err != nil {
			return nil, fmt.Errorf("failed to scan risk level row: %w", err)
		}
		stats.BySafetyLevel[level] = count
	}
	if err := levelRows.Err(); err != nil {
		return nil, fmt.Errorf("failed to read risk level rows: %w", err)
	}

	// Counts by install source.
	sourceQuery := latestCTE + `
  SELECT COALESCE(install_source, 'unknown'), COUNT(*)
  FROM latest
  GROUP BY COALESCE(install_source, 'unknown')
  `
	sourceRows, err := r.pool.Query(ctx, sourceQuery)
	if err != nil {
		return nil, fmt.Errorf("failed to aggregate stats by install source: %w", err)
	}
	defer sourceRows.Close()
	for sourceRows.Next() {
		var source string
		var count int64
		if err := sourceRows.Scan(&source, &count); err != nil {
			return nil, fmt.Errorf("failed to scan install source row: %w", err)
		}
		stats.ByInstallSource[source] = count
	}
	if err := sourceRows.Err(); err != nil {
		return nil, fmt.Errorf("failed to read install source rows: %w", err)
	}

	// Top risky apps (latest analysis per package).
	topQuery := latestCTE + `
  SELECT package_name, COALESCE(app_name, ''), risk_level, risk_score
  FROM latest
  WHERE risk_score > 0
  ORDER BY risk_score DESC
  LIMIT 10
  `
	topRows, err := r.pool.Query(ctx, topQuery)
	if err != nil {
		return nil, fmt.Errorf("failed to query top risky apps: %w", err)
	}
	defer topRows.Close()
	for topRows.Next() {
		var summary models.AppRiskSummary
		var level string
		if err := topRows.Scan(&summary.PackageName, &summary.AppName, &level, &summary.RiskScore); err != nil {
			return nil, fmt.Errorf("failed to scan top risky app row: %w", err)
		}
		summary.RiskLevel = models.AppRiskLevel(level)
		stats.TopRiskyApps = append(stats.TopRiskyApps, summary)
	}
	if err := topRows.Err(); err != nil {
		return nil, fmt.Errorf("failed to read top risky app rows: %w", err)
	}

	return stats, nil
}
