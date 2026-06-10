package repository

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ---------------------------------------------------------------------------
// RogueAPRepository — trusted access points + persisted network threat audits
// ---------------------------------------------------------------------------

// RogueAPRepository persists per-device trusted access points and reads the
// persisted network audit findings used by GET /network/threats.
type RogueAPRepository struct {
	pool *pgxpool.Pool
}

// NewRogueAPRepository creates a new rogue-AP repository.
func NewRogueAPRepository(pool *pgxpool.Pool) *RogueAPRepository {
	return &RogueAPRepository{pool: pool}
}

// NewRogueAPRepositoryFromRepos builds a RogueAPRepository reusing the shared
// connection pool held by the existing repositories. Returns nil when the
// repositories (and therefore the pool) are unavailable.
func NewRogueAPRepositoryFromRepos(repos *Repositories) *RogueAPRepository {
	if repos == nil || repos.Devices == nil || repos.Devices.pool == nil {
		return nil
	}
	return NewRogueAPRepository(repos.Devices.pool)
}

// TrustedAP is a per-device trusted access point.
type TrustedAP struct {
	ID       uuid.UUID `json:"id"`
	DeviceID string    `json:"device_id"`
	SSID     string    `json:"ssid"`
	BSSID    string    `json:"bssid"`
	AddedAt  time.Time `json:"added_at"`
}

// AddTrustedAP inserts a trusted AP for a device. Adding the same
// (device, ssid, bssid) pair again is idempotent and returns the existing row.
func (r *RogueAPRepository) AddTrustedAP(ctx context.Context, deviceID, ssid, bssid string) (*TrustedAP, error) {
	query := `
	INSERT INTO orbguard_lab.trusted_aps (device_id, ssid, bssid)
	VALUES ($1, $2, $3)
	ON CONFLICT (device_id, ssid, bssid) DO UPDATE SET ssid = EXCLUDED.ssid
	RETURNING id, device_id, ssid, bssid, added_at`

	var ap TrustedAP
	err := r.pool.QueryRow(ctx, query, deviceID, ssid, bssid).Scan(
		&ap.ID, &ap.DeviceID, &ap.SSID, &ap.BSSID, &ap.AddedAt,
	)
	if err != nil {
		return nil, err
	}
	return &ap, nil
}

// ListTrustedAPs returns the trusted APs for a device, newest first.
func (r *RogueAPRepository) ListTrustedAPs(ctx context.Context, deviceID string) ([]TrustedAP, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, device_id, ssid, bssid, added_at
		 FROM orbguard_lab.trusted_aps
		 WHERE device_id = $1
		 ORDER BY added_at DESC`,
		deviceID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	aps := make([]TrustedAP, 0)
	for rows.Next() {
		var ap TrustedAP
		if err := rows.Scan(&ap.ID, &ap.DeviceID, &ap.SSID, &ap.BSSID, &ap.AddedAt); err != nil {
			return nil, err
		}
		aps = append(aps, ap)
	}
	return aps, rows.Err()
}

// DeleteTrustedAP removes a trusted AP, scoped to the owning device. Returns
// false when no matching row existed.
func (r *RogueAPRepository) DeleteTrustedAP(ctx context.Context, deviceID string, id uuid.UUID) (bool, error) {
	tag, err := r.pool.Exec(ctx,
		`DELETE FROM orbguard_lab.trusted_aps WHERE id = $1 AND device_id = $2`,
		id, deviceID,
	)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

// ThreatAuditRow is a persisted network audit that contains at least one
// threat-relevant finding (rogue AP, evil twin, DNS hijack, or a high/critical
// overall risk). Findings holds the raw JSONB findings document.
type ThreatAuditRow struct {
	ID              uuid.UUID
	AuditType       string
	NetworkIdentity string
	RiskLevel       string
	RiskScore       float64
	HijackDetected  bool
	Findings        []byte
	AuditedAt       time.Time
}

// ListThreatAudits returns recent persisted audits with threat-relevant
// findings, newest first. deviceID == "" aggregates across all devices
// (service-level view).
func (r *RogueAPRepository) ListThreatAudits(ctx context.Context, deviceID string, limit int) ([]ThreatAuditRow, error) {
	if limit <= 0 {
		limit = 200
	}

	query := `
	SELECT id, audit_type, network_identity, risk_level, risk_score,
	       hijack_detected, findings, audited_at
	FROM orbguard_lab.network_audits
	WHERE ($1 = '' OR device_id = $1)
	  AND (rogue_ap_count > 0 OR evil_twin_count > 0 OR hijack_detected
	       OR risk_level IN ('high', 'critical'))
	ORDER BY audited_at DESC
	LIMIT $2`

	rows, err := r.pool.Query(ctx, query, deviceID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	audits := make([]ThreatAuditRow, 0)
	for rows.Next() {
		var row ThreatAuditRow
		if err := rows.Scan(
			&row.ID, &row.AuditType, &row.NetworkIdentity, &row.RiskLevel,
			&row.RiskScore, &row.HijackDetected, &row.Findings, &row.AuditedAt,
		); err != nil {
			return nil, err
		}
		audits = append(audits, row)
	}
	return audits, rows.Err()
}
