package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// QRSecurityRepository persists user feedback on QR scan verdicts.
// Raw QR content is never stored — only the SHA-256 hash of the content.
type QRSecurityRepository struct {
	pool *pgxpool.Pool
}

// NewQRSecurityRepository creates a new QR security repository.
func NewQRSecurityRepository(pool *pgxpool.Pool) *QRSecurityRepository {
	return &QRSecurityRepository{pool: pool}
}

// NewQRSecurityRepositoryFromRepos builds a QRSecurityRepository reusing the
// shared connection pool held by the existing repositories. Returns nil when
// the repositories (and therefore the pool) are unavailable.
func NewQRSecurityRepositoryFromRepos(repos *Repositories) *QRSecurityRepository {
	if repos == nil || repos.Devices == nil || repos.Devices.pool == nil {
		return nil
	}
	return NewQRSecurityRepository(repos.Devices.pool)
}

// QRFalsePositiveRecord is a user report that a QR scan was wrongly flagged.
type QRFalsePositiveRecord struct {
	ID          uuid.UUID
	DeviceID    string
	ContentHash string // SHA-256 hex of the scanned QR content
	Reason      string // optional free-text reason
	ReportedAt  time.Time
}

// InsertFalsePositive stores a user-reported QR false positive.
func (r *QRSecurityRepository) InsertFalsePositive(ctx context.Context, rec *QRFalsePositiveRecord) error {
	if rec.ID == uuid.Nil {
		rec.ID = uuid.New()
	}
	if rec.ReportedAt.IsZero() {
		rec.ReportedAt = time.Now().UTC()
	}

	query := `
INSERT INTO orbguard_lab.qr_false_positives
    (id, device_id, content_hash, reason, reported_at)
VALUES ($1, $2, $3, NULLIF($4, ''), $5)
`
	_, err := r.pool.Exec(ctx, query,
		rec.ID,
		rec.DeviceID,
		rec.ContentHash,
		rec.Reason,
		rec.ReportedAt,
	)
	if err != nil {
		return fmt.Errorf("insert qr false positive: %w", err)
	}
	return nil
}
