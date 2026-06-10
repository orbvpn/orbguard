package repository

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"orbguard-lab/internal/domain/models"
)

// EnterprisePolicyRepository persists Zero Trust conditional access policies
// so they survive restarts (previously they lived only in service memory and
// were re-seeded with fresh IDs on every boot).
//
// The full policy document is stored as JSONB; name/enabled/priority are
// mirrored into columns for ordering.
type EnterprisePolicyRepository struct {
	pool *pgxpool.Pool
}

// NewEnterprisePolicyRepository creates a new enterprise policy repository.
func NewEnterprisePolicyRepository(pool *pgxpool.Pool) *EnterprisePolicyRepository {
	return &EnterprisePolicyRepository{pool: pool}
}

// List returns all stored conditional access policies ordered by priority
// (lower = higher priority).
func (r *EnterprisePolicyRepository) List(ctx context.Context) ([]*models.ConditionalAccessPolicy, error) {
	query := `
SELECT policy
FROM orbguard_lab.conditional_access_policies
ORDER BY priority ASC, created_at ASC
`
	rows, err := r.pool.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("list conditional access policies: %w", err)
	}
	defer rows.Close()

	var policies []*models.ConditionalAccessPolicy
	for rows.Next() {
		var raw []byte
		if err := rows.Scan(&raw); err != nil {
			return nil, fmt.Errorf("scan conditional access policy: %w", err)
		}
		var p models.ConditionalAccessPolicy
		if err := json.Unmarshal(raw, &p); err != nil {
			return nil, fmt.Errorf("decode conditional access policy: %w", err)
		}
		policies = append(policies, &p)
	}
	return policies, rows.Err()
}

// Upsert stores or replaces a conditional access policy.
func (r *EnterprisePolicyRepository) Upsert(ctx context.Context, p *models.ConditionalAccessPolicy) error {
	if p == nil {
		return errors.New("policy is required")
	}
	if p.ID == uuid.Nil {
		return errors.New("policy id is required")
	}

	raw, err := json.Marshal(p)
	if err != nil {
		return fmt.Errorf("marshal conditional access policy: %w", err)
	}

	query := `
INSERT INTO orbguard_lab.conditional_access_policies
  (id, name, enabled, priority, policy, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  enabled = EXCLUDED.enabled,
  priority = EXCLUDED.priority,
  policy = EXCLUDED.policy,
  updated_at = EXCLUDED.updated_at
`
	if _, err := r.pool.Exec(ctx, query,
		p.ID, p.Name, p.Enabled, p.Priority, raw, p.CreatedAt, p.UpdatedAt); err != nil {
		return fmt.Errorf("upsert conditional access policy: %w", err)
	}
	return nil
}

// Delete removes a conditional access policy.
func (r *EnterprisePolicyRepository) Delete(ctx context.Context, id uuid.UUID) error {
	query := `DELETE FROM orbguard_lab.conditional_access_policies WHERE id = $1`
	if _, err := r.pool.Exec(ctx, query, id); err != nil {
		return fmt.Errorf("delete conditional access policy: %w", err)
	}
	return nil
}
