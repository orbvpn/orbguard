package repository

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

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

// ============================================================================
// Enterprise integration configuration persistence (MDM + SIEM)
// ============================================================================

// Integration kinds stored in orbguard_lab.enterprise_integrations.kind.
const (
	enterpriseIntegrationKindMDM  = "mdm"
	enterpriseIntegrationKindSIEM = "siem"
)

// EnterpriseIntegrationRepository persists MDM and SIEM integration
// configurations so they survive restarts (previously they lived only in
// MDMService / SIEMService memory).
//
// The full config document is stored as JSONB. Credentials are write-only on
// the API models (marshaled as "-" so they never appear in responses), so a
// persistence wrapper re-attaches them for storage and re-hydrates them on
// load — without them, syncs and event forwarding would break after restart.
type EnterpriseIntegrationRepository struct {
	pool *pgxpool.Pool
}

// NewEnterpriseIntegrationRepository creates a new enterprise integration
// repository.
func NewEnterpriseIntegrationRepository(pool *pgxpool.Pool) *EnterpriseIntegrationRepository {
	return &EnterpriseIntegrationRepository{pool: pool}
}

// NewEnterpriseIntegrationRepositoryFromRepos derives an integration
// repository from an existing Repositories set, reusing its pool. Returns
// nil when no database is available.
func NewEnterpriseIntegrationRepositoryFromRepos(repos *Repositories) *EnterpriseIntegrationRepository {
	if repos == nil || repos.Devices == nil || repos.Devices.pool == nil {
		return nil
	}
	return NewEnterpriseIntegrationRepository(repos.Devices.pool)
}

// persistedMDMIntegration wraps the API model so the write-only client
// secret (json:"-" on the model) IS stored in the config JSONB document.
type persistedMDMIntegration struct {
	models.MDMIntegrationConfig
	ClientSecret string `json:"client_secret,omitempty"`
}

// persistedSIEMIntegration wraps the API model so the write-only token and
// password (json:"-" on the model) ARE stored in the config JSONB document.
type persistedSIEMIntegration struct {
	models.SIEMIntegrationConfig
	Token    string `json:"token,omitempty"`
	Password string `json:"password,omitempty"`
}

// upsert stores or replaces an integration row.
func (r *EnterpriseIntegrationRepository) upsert(ctx context.Context, id uuid.UUID, kind, provider, name string, enabled bool, doc interface{}, createdAt, updatedAt time.Time) error {
	raw, err := json.Marshal(doc)
	if err != nil {
		return fmt.Errorf("marshal %s integration config: %w", kind, err)
	}

	query := `
INSERT INTO orbguard_lab.enterprise_integrations
  (id, kind, provider, name, config, enabled, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
ON CONFLICT (id) DO UPDATE SET
  provider = EXCLUDED.provider,
  name = EXCLUDED.name,
  config = EXCLUDED.config,
  enabled = EXCLUDED.enabled,
  updated_at = EXCLUDED.updated_at
`
	if _, err := r.pool.Exec(ctx, query,
		id, kind, provider, name, raw, enabled, createdAt, updatedAt); err != nil {
		return fmt.Errorf("upsert %s integration: %w", kind, err)
	}
	return nil
}

// listConfigs returns the raw config documents for a kind, oldest first.
func (r *EnterpriseIntegrationRepository) listConfigs(ctx context.Context, kind string) ([][]byte, error) {
	query := `
SELECT config
FROM orbguard_lab.enterprise_integrations
WHERE kind = $1
ORDER BY created_at ASC
`
	rows, err := r.pool.Query(ctx, query, kind)
	if err != nil {
		return nil, fmt.Errorf("list %s integrations: %w", kind, err)
	}
	defer rows.Close()

	var docs [][]byte
	for rows.Next() {
		var raw []byte
		if err := rows.Scan(&raw); err != nil {
			return nil, fmt.Errorf("scan %s integration: %w", kind, err)
		}
		docs = append(docs, raw)
	}
	return docs, rows.Err()
}

// UpsertMDM stores or replaces an MDM integration, including its write-only
// credentials.
func (r *EnterpriseIntegrationRepository) UpsertMDM(ctx context.Context, config *models.MDMIntegrationConfig) error {
	if config == nil {
		return errors.New("mdm integration config is required")
	}
	if config.ID == uuid.Nil {
		return errors.New("mdm integration id is required")
	}
	doc := persistedMDMIntegration{
		MDMIntegrationConfig: *config,
		ClientSecret:         config.ClientSecret,
	}
	return r.upsert(ctx, config.ID, enterpriseIntegrationKindMDM,
		string(config.Provider), config.Name, config.Enabled, doc,
		config.CreatedAt, config.UpdatedAt)
}

// ListMDM returns all stored MDM integrations with credentials re-hydrated
// (the API layer hides them again via the model's json:"-" tags).
func (r *EnterpriseIntegrationRepository) ListMDM(ctx context.Context) ([]*models.MDMIntegrationConfig, error) {
	docs, err := r.listConfigs(ctx, enterpriseIntegrationKindMDM)
	if err != nil {
		return nil, err
	}

	configs := make([]*models.MDMIntegrationConfig, 0, len(docs))
	for _, raw := range docs {
		var doc persistedMDMIntegration
		if err := json.Unmarshal(raw, &doc); err != nil {
			return nil, fmt.Errorf("decode mdm integration: %w", err)
		}
		config := doc.MDMIntegrationConfig
		config.ClientSecret = doc.ClientSecret
		configs = append(configs, &config)
	}
	return configs, nil
}

// UpsertSIEM stores or replaces a SIEM integration, including its write-only
// credentials.
func (r *EnterpriseIntegrationRepository) UpsertSIEM(ctx context.Context, config *models.SIEMIntegrationConfig) error {
	if config == nil {
		return errors.New("siem integration config is required")
	}
	if config.ID == uuid.Nil {
		return errors.New("siem integration id is required")
	}
	doc := persistedSIEMIntegration{
		SIEMIntegrationConfig: *config,
		Token:                 config.Token,
		Password:              config.Password,
	}
	return r.upsert(ctx, config.ID, enterpriseIntegrationKindSIEM,
		string(config.Provider), config.Name, config.Enabled, doc,
		config.CreatedAt, config.UpdatedAt)
}

// ListSIEM returns all stored SIEM integrations with credentials re-hydrated
// (the API layer hides them again via the model's json:"-" tags).
func (r *EnterpriseIntegrationRepository) ListSIEM(ctx context.Context) ([]*models.SIEMIntegrationConfig, error) {
	docs, err := r.listConfigs(ctx, enterpriseIntegrationKindSIEM)
	if err != nil {
		return nil, err
	}

	configs := make([]*models.SIEMIntegrationConfig, 0, len(docs))
	for _, raw := range docs {
		var doc persistedSIEMIntegration
		if err := json.Unmarshal(raw, &doc); err != nil {
			return nil, fmt.Errorf("decode siem integration: %w", err)
		}
		config := doc.SIEMIntegrationConfig
		config.Token = doc.Token
		config.Password = doc.Password
		configs = append(configs, &config)
	}
	return configs, nil
}

// Delete removes an integration of either kind.
func (r *EnterpriseIntegrationRepository) Delete(ctx context.Context, id uuid.UUID) error {
	query := `DELETE FROM orbguard_lab.enterprise_integrations WHERE id = $1`
	if _, err := r.pool.Exec(ctx, query, id); err != nil {
		return fmt.Errorf("delete enterprise integration: %w", err)
	}
	return nil
}

// ============================================================================
// SIEM alert feed persistence
// ============================================================================

// SIEMAlertRepository persists every security event that flows through the
// SIEM event path together with its forward-attempt outcome, backing the
// real GET /siem/alerts feed.
type SIEMAlertRepository struct {
	pool *pgxpool.Pool
}

// NewSIEMAlertRepository creates a new SIEM alert repository.
func NewSIEMAlertRepository(pool *pgxpool.Pool) *SIEMAlertRepository {
	return &SIEMAlertRepository{pool: pool}
}

// NewSIEMAlertRepositoryFromRepos derives a SIEM alert repository from an
// existing Repositories set, reusing its pool. Returns nil when no database
// is available.
func NewSIEMAlertRepositoryFromRepos(repos *Repositories) *SIEMAlertRepository {
	if repos == nil || repos.Devices == nil || repos.Devices.pool == nil {
		return nil
	}
	return NewSIEMAlertRepository(repos.Devices.pool)
}

// Insert persists a SIEM alert row.
func (r *SIEMAlertRepository) Insert(ctx context.Context, alert *models.SIEMAlert) error {
	if alert == nil {
		return errors.New("siem alert is required")
	}
	if alert.ID == uuid.Nil {
		return errors.New("siem alert id is required")
	}

	var integrationID interface{}
	if alert.IntegrationID != nil {
		integrationID = *alert.IntegrationID
	}
	var payload interface{}
	if len(alert.Payload) > 0 {
		payload = []byte(alert.Payload)
	}
	var forwardError interface{}
	if alert.ForwardError != "" {
		forwardError = alert.ForwardError
	}

	query := `
INSERT INTO orbguard_lab.siem_alerts
  (id, integration_id, severity, title, description, source, payload, forwarded, forward_error, created_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
`
	if _, err := r.pool.Exec(ctx, query,
		alert.ID, integrationID, string(alert.Severity), alert.Title,
		alert.Description, alert.Source, payload, alert.Forwarded,
		forwardError, alert.CreatedAt); err != nil {
		return fmt.Errorf("insert siem alert: %w", err)
	}
	return nil
}

// SetForwardOutcome records the result of a forward attempt for a set of
// alerts: forwarded=TRUE with the error cleared on success, or the delivery
// error message on failure.
func (r *SIEMAlertRepository) SetForwardOutcome(ctx context.Context, ids []uuid.UUID, forwardErr string) error {
	if len(ids) == 0 {
		return nil
	}

	idStrs := make([]string, len(ids))
	for i, id := range ids {
		idStrs[i] = id.String()
	}

	var query string
	var args []interface{}
	if forwardErr == "" {
		query = `
UPDATE orbguard_lab.siem_alerts
SET forwarded = TRUE, forward_error = NULL
WHERE id = ANY($1::uuid[])
`
		args = []interface{}{idStrs}
	} else {
		query = `
UPDATE orbguard_lab.siem_alerts
SET forwarded = FALSE, forward_error = $2
WHERE id = ANY($1::uuid[])
`
		args = []interface{}{idStrs, forwardErr}
	}

	if _, err := r.pool.Exec(ctx, query, args...); err != nil {
		return fmt.Errorf("set siem alert forward outcome: %w", err)
	}
	return nil
}

// List returns the most recent alerts, newest first, optionally filtered by
// severity. The payload column is intentionally not loaded: the alert feed
// never echoes raw event documents.
func (r *SIEMAlertRepository) List(ctx context.Context, limit int, severity string) ([]*models.SIEMAlert, error) {
	if limit <= 0 {
		limit = 100
	}

	query := `
SELECT id::text, integration_id::text, severity, title, description, source, forwarded,
       COALESCE(forward_error, ''), created_at
FROM orbguard_lab.siem_alerts
`
	args := []interface{}{}
	if severity != "" {
		query += `WHERE severity = $1
`
		args = append(args, severity)
	}
	query += fmt.Sprintf("ORDER BY created_at DESC\nLIMIT $%d", len(args)+1)
	args = append(args, limit)

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list siem alerts: %w", err)
	}
	defer rows.Close()

	alerts := make([]*models.SIEMAlert, 0)
	for rows.Next() {
		var alert models.SIEMAlert
		var id string
		var integrationID *string
		var sev string
		if err := rows.Scan(&id, &integrationID, &sev, &alert.Title,
			&alert.Description, &alert.Source, &alert.Forwarded,
			&alert.ForwardError, &alert.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan siem alert: %w", err)
		}
		parsedID, err := uuid.Parse(id)
		if err != nil {
			return nil, fmt.Errorf("parse siem alert id %q: %w", id, err)
		}
		alert.ID = parsedID
		alert.Severity = models.Severity(sev)
		if integrationID != nil {
			if parsed, perr := uuid.Parse(*integrationID); perr == nil {
				alert.IntegrationID = &parsed
			}
		}
		alerts = append(alerts, &alert)
	}
	return alerts, rows.Err()
}
