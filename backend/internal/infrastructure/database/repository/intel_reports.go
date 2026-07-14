package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ThreatReportRepository handles persistence for user-submitted threat
// reports (orbguard_lab.threat_reports).
type ThreatReportRepository struct {
	pool *pgxpool.Pool
}

// NewThreatReportRepository creates a new threat report repository.
func NewThreatReportRepository(pool *pgxpool.Pool) *ThreatReportRepository {
	return &ThreatReportRepository{pool: pool}
}

// ThreatReport is a user-submitted threat report row.
// Reporter identity fields are never serialized to API consumers.
type ThreatReport struct {
	ID       uuid.UUID `json:"id"`
	UserID   *string   `json:"-"`
	DeviceID *string   `json:"-"`

	IndicatorValue string   `json:"indicator_value"`
	IndicatorType  string   `json:"indicator_type"`
	Severity       string   `json:"severity"`
	Description    string   `json:"description"`
	Tags           []string `json:"tags,omitempty"`

	Platform    string `json:"platform,omitempty"`
	DeviceModel string `json:"device_model,omitempty"`
	OSVersion   string `json:"os_version,omitempty"`
	AppVersion  string `json:"app_version,omitempty"`

	EvidenceData []byte `json:"evidence_data,omitempty"`

	Status      string     `json:"status"`
	ReviewedBy  *string    `json:"-"`
	ReviewNotes *string    `json:"review_notes,omitempty"`
	ReviewedAt  *time.Time `json:"reviewed_at,omitempty"`

	IndicatorID *uuid.UUID `json:"indicator_id,omitempty"`

	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// CreateThreatReportParams holds the fields needed to persist a new report.
type CreateThreatReportParams struct {
	UserID         string
	DeviceID       string
	IndicatorValue string
	IndicatorType  string
	Severity       string
	Description    string
	Tags           []string
	Platform       string
	DeviceModel    string
	OSVersion      string
	AppVersion     string
	EvidenceData   []byte
}

const threatReportColumns = `
	id, user_id, device_id, indicator_value, indicator_type, severity,
	description, tags, platform, device_model, os_version, app_version,
	evidence_data, status, reviewed_by, review_notes, reviewed_at,
	indicator_id, created_at, updated_at`

// Create inserts a new threat report with status 'pending'.
func (r *ThreatReportRepository) Create(ctx context.Context, params CreateThreatReportParams) (*ThreatReport, error) {
	query := fmt.Sprintf(`
	INSERT INTO threat_reports
	(user_id, device_id, indicator_value, indicator_type, severity,
	 description, tags, platform, device_model, os_version, app_version,
	 evidence_data, status, created_at, updated_at)
	VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, 'pending', NOW(), NOW())
	RETURNING %s`, threatReportColumns)

	row := r.pool.QueryRow(
		ctx,
		query,
		nullIfEmpty(params.UserID),
		nullIfEmpty(params.DeviceID),
		params.IndicatorValue,
		params.IndicatorType,
		params.Severity,
		params.Description,
		params.Tags,
		nullIfEmpty(params.Platform),
		nullIfEmpty(params.DeviceModel),
		nullIfEmpty(params.OSVersion),
		nullIfEmpty(params.AppVersion),
		params.EvidenceData,
	)

	report, err := scanThreatReport(row)
	if err != nil {
		return nil, fmt.Errorf("failed to create threat report: %w", err)
	}
	return report, nil
}

// GetByID returns a single report, or nil if it does not exist.
func (r *ThreatReportRepository) GetByID(ctx context.Context, id uuid.UUID) (*ThreatReport, error) {
	query := fmt.Sprintf(`SELECT %s FROM threat_reports WHERE id = $1`, threatReportColumns)

	report, err := scanThreatReport(r.pool.QueryRow(ctx, query, id))
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to get threat report: %w", err)
	}
	return report, nil
}

// ListByStatus returns reports with the given status, newest first, plus the
// total count for pagination.
func (r *ThreatReportRepository) ListByStatus(ctx context.Context, status string, limit, offset int) ([]*ThreatReport, int64, error) {
	if limit <= 0 {
		limit = 100
	}

	var total int64
	if err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM threat_reports WHERE status = $1`, status,
	).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("failed to count threat reports: %w", err)
	}

	query := fmt.Sprintf(`
	SELECT %s FROM threat_reports
	WHERE status = $1
	ORDER BY created_at DESC
	LIMIT $2 OFFSET $3`, threatReportColumns)

	rows, err := r.pool.Query(ctx, query, status, limit, offset)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to list threat reports: %w", err)
	}
	defer rows.Close()

	reports := make([]*ThreatReport, 0)
	for rows.Next() {
		report, err := scanThreatReport(rows)
		if err != nil {
			return nil, 0, err
		}
		reports = append(reports, report)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("failed to iterate threat reports: %w", err)
	}

	return reports, total, nil
}

// CountByStatus returns the number of reports with the given status.
func (r *ThreatReportRepository) CountByStatus(ctx context.Context, status string) (int64, error) {
	var count int64
	if err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM threat_reports WHERE status = $1`, status,
	).Scan(&count); err != nil {
		return 0, fmt.Errorf("failed to count threat reports by status: %w", err)
	}
	return count, nil
}

// CountAll returns the total number of threat reports across all statuses.
func (r *ThreatReportRepository) CountAll(ctx context.Context) (int64, error) {
	var count int64
	if err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM threat_reports`,
	).Scan(&count); err != nil {
		return 0, fmt.Errorf("failed to count threat reports: %w", err)
	}
	return count, nil
}

// ListByReporter returns reports submitted by the given user and/or device,
// newest first, plus the total count.
func (r *ThreatReportRepository) ListByReporter(ctx context.Context, userID, deviceID string, limit, offset int) ([]*ThreatReport, int64, error) {
	if limit <= 0 {
		limit = 100
	}
	if userID == "" && deviceID == "" {
		return []*ThreatReport{}, 0, nil
	}

	where := `(($1::text IS NOT NULL AND user_id = $1) OR ($2::text IS NOT NULL AND device_id = $2))`

	var total int64
	if err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM threat_reports WHERE `+where,
		nullIfEmpty(userID), nullIfEmpty(deviceID),
	).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("failed to count reporter threat reports: %w", err)
	}

	query := fmt.Sprintf(`
	SELECT %s FROM threat_reports
	WHERE %s
	ORDER BY created_at DESC
	LIMIT $3 OFFSET $4`, threatReportColumns, where)

	rows, err := r.pool.Query(ctx, query, nullIfEmpty(userID), nullIfEmpty(deviceID), limit, offset)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to list reporter threat reports: %w", err)
	}
	defer rows.Close()

	reports := make([]*ThreatReport, 0)
	for rows.Next() {
		report, err := scanThreatReport(rows)
		if err != nil {
			return nil, 0, err
		}
		reports = append(reports, report)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("failed to iterate reporter threat reports: %w", err)
	}

	return reports, total, nil
}

// CountRecentByReporter returns how many reports the given reporter has
// submitted since the supplied time. Used for abuse/rate limiting.
func (r *ThreatReportRepository) CountRecentByReporter(ctx context.Context, userID, deviceID string, since time.Time) (int64, error) {
	if userID == "" && deviceID == "" {
		return 0, nil
	}

	var count int64
	err := r.pool.QueryRow(ctx, `
	SELECT COUNT(*) FROM threat_reports
	WHERE created_at >= $3
	  AND (($1::text IS NOT NULL AND user_id = $1) OR ($2::text IS NOT NULL AND device_id = $2))`,
		nullIfEmpty(userID), nullIfEmpty(deviceID), since,
	).Scan(&count)
	if err != nil {
		return 0, fmt.Errorf("failed to count recent threat reports: %w", err)
	}
	return count, nil
}

// HasPendingDuplicate reports whether the reporter already has a pending
// report for the same indicator value.
func (r *ThreatReportRepository) HasPendingDuplicate(ctx context.Context, userID, deviceID, indicatorValue string) (bool, error) {
	if userID == "" && deviceID == "" {
		return false, nil
	}

	var exists bool
	err := r.pool.QueryRow(ctx, `
	SELECT EXISTS (
		SELECT 1 FROM threat_reports
		WHERE indicator_value = $3
		  AND status = 'pending'
		  AND (($1::text IS NOT NULL AND user_id = $1) OR ($2::text IS NOT NULL AND device_id = $2))
	)`,
		nullIfEmpty(userID), nullIfEmpty(deviceID), indicatorValue,
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("failed to check duplicate threat report: %w", err)
	}
	return exists, nil
}

// UpdateStatus transitions a report through the review workflow. indicatorID
// may be nil; it links the report to the indicator created on approval.
func (r *ThreatReportRepository) UpdateStatus(ctx context.Context, id uuid.UUID, status, reviewedBy, reviewNotes string, indicatorID *uuid.UUID) error {
	tag, err := r.pool.Exec(ctx, `
	UPDATE threat_reports
	SET status = $2,
	    reviewed_by = $3,
	    review_notes = $4,
	    indicator_id = COALESCE($5, indicator_id),
	    reviewed_at = NOW(),
	    updated_at = NOW()
	WHERE id = $1`,
		id, status, nullIfEmpty(reviewedBy), nullIfEmpty(reviewNotes), indicatorID,
	)
	if err != nil {
		return fmt.Errorf("failed to update threat report status: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("threat report %s not found", id)
	}
	return nil
}

// nullIfEmpty converts empty strings to nil so they are stored as NULL.
func nullIfEmpty(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

// scanThreatReport scans a single threat_reports row.
func scanThreatReport(row pgx.Row) (*ThreatReport, error) {
	var report ThreatReport
	var platform, deviceModel, osVersion, appVersion *string

	err := row.Scan(
		&report.ID,
		&report.UserID,
		&report.DeviceID,
		&report.IndicatorValue,
		&report.IndicatorType,
		&report.Severity,
		&report.Description,
		&report.Tags,
		&platform,
		&deviceModel,
		&osVersion,
		&appVersion,
		&report.EvidenceData,
		&report.Status,
		&report.ReviewedBy,
		&report.ReviewNotes,
		&report.ReviewedAt,
		&report.IndicatorID,
		&report.CreatedAt,
		&report.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}

	if platform != nil {
		report.Platform = *platform
	}
	if deviceModel != nil {
		report.DeviceModel = *deviceModel
	}
	if osVersion != nil {
		report.OSVersion = *osVersion
	}
	if appVersion != nil {
		report.AppVersion = *appVersion
	}

	return &report, nil
}
