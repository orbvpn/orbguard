package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// YARASubmissionRepository handles persistence for community-submitted YARA
// rules (orbguard_lab.yara_submissions, migration 020).
type YARASubmissionRepository struct {
	pool *pgxpool.Pool
}

// NewYARASubmissionRepository creates a new YARA submission repository.
func NewYARASubmissionRepository(pool *pgxpool.Pool) *YARASubmissionRepository {
	return &YARASubmissionRepository{pool: pool}
}

// NewYARASubmissionRepositoryFromRepos builds a YARASubmissionRepository
// reusing the shared connection pool held by the existing repositories.
// Returns nil when the repositories (and therefore the pool) are unavailable.
func NewYARASubmissionRepositoryFromRepos(repos *Repositories) *YARASubmissionRepository {
	if repos == nil || repos.Devices == nil || repos.Devices.pool == nil {
		return nil
	}
	return NewYARASubmissionRepository(repos.Devices.pool)
}

// YARASubmission is a community-submitted YARA rule row.
// Submitter identity is never serialized to API consumers.
type YARASubmission struct {
	ID          uuid.UUID `json:"id"`
	Name        string    `json:"name"`
	RuleText    string    `json:"rule_text"`
	SubmittedBy *string   `json:"-"`

	Status     string `json:"status"`
	Validation []byte `json:"validation,omitempty"`

	ReviewedBy  *string    `json:"-"`
	ReviewNotes *string    `json:"review_notes,omitempty"`
	ReviewedAt  *time.Time `json:"reviewed_at,omitempty"`

	CreatedAt time.Time `json:"created_at"`
}

const yaraSubmissionColumns = `
	id, name, rule_text, submitted_by, status, validation,
	reviewed_by, review_notes, created_at, reviewed_at`

// Create inserts a new submission with status 'pending'. validation holds
// the JSON-encoded result of parser/compiler validation at submission time.
func (r *YARASubmissionRepository) Create(ctx context.Context, name, ruleText, submittedBy string, validation []byte) (*YARASubmission, error) {
	query := fmt.Sprintf(`
	INSERT INTO yara_submissions
	(name, rule_text, submitted_by, status, validation, created_at)
	VALUES ($1, $2, $3, 'pending', $4, NOW())
	RETURNING %s`, yaraSubmissionColumns)

	row := r.pool.QueryRow(ctx, query, name, ruleText, nullIfEmpty(submittedBy), validation)

	submission, err := scanYARASubmission(row)
	if err != nil {
		return nil, fmt.Errorf("failed to create yara submission: %w", err)
	}
	return submission, nil
}

// GetByID returns a single submission, or nil if it does not exist.
func (r *YARASubmissionRepository) GetByID(ctx context.Context, id uuid.UUID) (*YARASubmission, error) {
	query := fmt.Sprintf(`SELECT %s FROM yara_submissions WHERE id = $1`, yaraSubmissionColumns)

	submission, err := scanYARASubmission(r.pool.QueryRow(ctx, query, id))
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to get yara submission: %w", err)
	}
	return submission, nil
}

// ListByStatus returns submissions with the given status, newest first, plus
// the total count for pagination.
func (r *YARASubmissionRepository) ListByStatus(ctx context.Context, status string, limit, offset int) ([]*YARASubmission, int64, error) {
	if limit <= 0 {
		limit = 100
	}

	var total int64
	if err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM yara_submissions WHERE status = $1`, status,
	).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("failed to count yara submissions: %w", err)
	}

	query := fmt.Sprintf(`
	SELECT %s FROM yara_submissions
	WHERE status = $1
	ORDER BY created_at DESC
	LIMIT $2 OFFSET $3`, yaraSubmissionColumns)

	rows, err := r.pool.Query(ctx, query, status, limit, offset)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to list yara submissions: %w", err)
	}
	defer rows.Close()

	submissions := make([]*YARASubmission, 0)
	for rows.Next() {
		submission, err := scanYARASubmission(rows)
		if err != nil {
			return nil, 0, err
		}
		submissions = append(submissions, submission)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("failed to iterate yara submissions: %w", err)
	}

	return submissions, total, nil
}

// UpdateStatus transitions a submission through the review workflow.
func (r *YARASubmissionRepository) UpdateStatus(ctx context.Context, id uuid.UUID, status, reviewedBy, reviewNotes string) error {
	tag, err := r.pool.Exec(ctx, `
	UPDATE yara_submissions
	SET status = $2,
	    reviewed_by = $3,
	    review_notes = $4,
	    reviewed_at = NOW()
	WHERE id = $1`,
		id, status, nullIfEmpty(reviewedBy), nullIfEmpty(reviewNotes),
	)
	if err != nil {
		return fmt.Errorf("failed to update yara submission status: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("yara submission %s not found", id)
	}
	return nil
}

// scanYARASubmission scans a single yara_submissions row.
func scanYARASubmission(row pgx.Row) (*YARASubmission, error) {
	var s YARASubmission
	err := row.Scan(
		&s.ID,
		&s.Name,
		&s.RuleText,
		&s.SubmittedBy,
		&s.Status,
		&s.Validation,
		&s.ReviewedBy,
		&s.ReviewNotes,
		&s.CreatedAt,
		&s.ReviewedAt,
	)
	if err != nil {
		return nil, err
	}
	return &s, nil
}
