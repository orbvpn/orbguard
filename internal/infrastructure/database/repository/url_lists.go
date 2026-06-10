package repository

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"orbguard-lab/internal/domain/models"
)

// ErrURLListEntryNotFound is returned when a list entry does not exist
// (or is not owned by the requesting user).
var ErrURLListEntryNotFound = errors.New("url list entry not found")

// URLListRepository persists per-user URL whitelist/blacklist entries
// and user-submitted URL reports.
type URLListRepository struct {
	pool *pgxpool.Pool
}

// NewURLListRepository creates a new URL list repository.
func NewURLListRepository(pool *pgxpool.Pool) *URLListRepository {
	return &URLListRepository{pool: pool}
}

// URLReport represents a user-submitted URL report (false positive,
// missed threat, or general feedback).
type URLReport struct {
	ID         uuid.UUID  `json:"id"`
	UserID     string     `json:"user_id,omitempty"`
	DeviceID   string     `json:"device_id,omitempty"`
	URL        string     `json:"url"`
	ReportType string     `json:"report_type"`
	Comment    string     `json:"comment,omitempty"`
	Status     string     `json:"status"`
	CreatedAt  time.Time  `json:"created_at"`
	ReviewedAt *time.Time `json:"reviewed_at,omitempty"`
}

// Add inserts (or re-activates) a list entry for a user. The unique
// constraint on (user_id, list_type, url_pattern) makes the operation
// idempotent: re-adding an existing pattern updates its metadata.
func (r *URLListRepository) Add(ctx context.Context, userID string, listType models.URLListType, pattern, reason, createdBy string) (*models.URLListEntry, error) {
	query := `
  INSERT INTO orbguard_lab.url_list_entries
    (user_id, list_type, url_pattern, reason, created_by, is_active, created_at)
  VALUES ($1, $2, $3, NULLIF($4, ''), NULLIF($5, ''), TRUE, NOW())
  ON CONFLICT (user_id, list_type, url_pattern)
  DO UPDATE SET
    reason     = COALESCE(NULLIF(EXCLUDED.reason, ''), orbguard_lab.url_list_entries.reason),
    is_active  = TRUE
  RETURNING id, created_at
  `

	entry := &models.URLListEntry{
		ListType:  listType,
		Reason:    reason,
		CreatedBy: createdBy,
		IsActive:  true,
	}
	applyPatternToEntry(entry, pattern)

	err := r.pool.QueryRow(ctx, query, userID, string(listType), pattern, reason, createdBy).
		Scan(&entry.ID, &entry.CreatedAt)
	if err != nil {
		return nil, err
	}

	return entry, nil
}

// Remove deletes a list entry by ID, scoped to the owning user.
// Returns ErrURLListEntryNotFound when no matching row exists.
func (r *URLListRepository) Remove(ctx context.Context, userID string, id uuid.UUID) error {
	query := `
  DELETE FROM orbguard_lab.url_list_entries
  WHERE id = $1 AND user_id = $2
  `

	tag, err := r.pool.Exec(ctx, query, id, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrURLListEntryNotFound
	}
	return nil
}

// List returns all active entries of the given type for a user,
// newest first.
func (r *URLListRepository) List(ctx context.Context, userID string, listType models.URLListType) ([]models.URLListEntry, error) {
	query := `
  SELECT id, url_pattern, COALESCE(reason, ''), COALESCE(created_by, ''),
         is_active, expires_at, created_at
  FROM orbguard_lab.url_list_entries
  WHERE user_id = $1
    AND list_type = $2
    AND is_active = TRUE
    AND (expires_at IS NULL OR expires_at > NOW())
  ORDER BY created_at DESC
  `

	rows, err := r.pool.Query(ctx, query, userID, string(listType))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	entries := []models.URLListEntry{}
	for rows.Next() {
		var (
			entry   models.URLListEntry
			pattern string
		)
		if err := rows.Scan(
			&entry.ID,
			&pattern,
			&entry.Reason,
			&entry.CreatedBy,
			&entry.IsActive,
			&entry.ExpiresAt,
			&entry.CreatedAt,
		); err != nil {
			return nil, err
		}
		entry.ListType = listType
		applyPatternToEntry(&entry, pattern)
		entries = append(entries, entry)
	}

	return entries, rows.Err()
}

// ActivePatterns returns the raw active patterns of the given type for
// a user (used for fast match checks and DNS block-rule generation).
func (r *URLListRepository) ActivePatterns(ctx context.Context, userID string, listType models.URLListType) ([]string, error) {
	query := `
  SELECT url_pattern
  FROM orbguard_lab.url_list_entries
  WHERE user_id = $1
    AND list_type = $2
    AND is_active = TRUE
    AND (expires_at IS NULL OR expires_at > NOW())
  `

	rows, err := r.pool.Query(ctx, query, userID, string(listType))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	patterns := []string{}
	for rows.Next() {
		var p string
		if err := rows.Scan(&p); err != nil {
			return nil, err
		}
		patterns = append(patterns, p)
	}

	return patterns, rows.Err()
}

// CountByType returns the number of active entries of a list type
// across all users (used for aggregate stats).
func (r *URLListRepository) CountByType(ctx context.Context, listType models.URLListType) (int64, error) {
	query := `
  SELECT COUNT(*)
  FROM orbguard_lab.url_list_entries
  WHERE list_type = $1
    AND is_active = TRUE
    AND (expires_at IS NULL OR expires_at > NOW())
  `

	var count int64
	err := r.pool.QueryRow(ctx, query, string(listType)).Scan(&count)
	return count, err
}

// GetByID returns a single entry scoped to the owning user.
func (r *URLListRepository) GetByID(ctx context.Context, userID string, id uuid.UUID) (*models.URLListEntry, error) {
	query := `
  SELECT id, list_type, url_pattern, COALESCE(reason, ''), COALESCE(created_by, ''),
         is_active, expires_at, created_at
  FROM orbguard_lab.url_list_entries
  WHERE id = $1 AND user_id = $2
  LIMIT 1
  `

	var (
		entry    models.URLListEntry
		listType string
		pattern  string
	)
	err := r.pool.QueryRow(ctx, query, id, userID).Scan(
		&entry.ID,
		&listType,
		&pattern,
		&entry.Reason,
		&entry.CreatedBy,
		&entry.IsActive,
		&entry.ExpiresAt,
		&entry.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrURLListEntryNotFound
		}
		return nil, err
	}
	entry.ListType = models.URLListType(listType)
	applyPatternToEntry(&entry, pattern)

	return &entry, nil
}

// CreateReport persists a user-submitted URL report.
func (r *URLListRepository) CreateReport(ctx context.Context, report *URLReport) error {
	query := `
  INSERT INTO orbguard_lab.url_reports
    (user_id, device_id, url, report_type, comment, status, created_at)
  VALUES (NULLIF($1, ''), NULLIF($2, ''), $3, $4, NULLIF($5, ''), 'pending', NOW())
  RETURNING id, status, created_at
  `

	return r.pool.QueryRow(
		ctx,
		query,
		report.UserID,
		report.DeviceID,
		report.URL,
		report.ReportType,
		report.Comment,
	).Scan(&report.ID, &report.Status, &report.CreatedAt)
}

// applyPatternToEntry maps the stored url_pattern column onto the most
// appropriate URLListEntry field so API responses stay shape-compatible.
func applyPatternToEntry(entry *models.URLListEntry, pattern string) {
	switch {
	case strings.Contains(pattern, "://") || strings.Contains(pattern, "/"):
		entry.URL = pattern
	case strings.ContainsAny(pattern, "*?^$"):
		entry.Pattern = pattern
	default:
		entry.Domain = pattern
	}
}
