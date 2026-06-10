package repository

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"orbguard-lab/internal/domain/models"
)

// DarkWebRepository persists dark-web monitored assets, breach alerts and
// check statistics (orbguard_lab.darkweb_* tables, migration 009).
type DarkWebRepository struct {
	pool *pgxpool.Pool
}

// NewDarkWebRepository creates a new dark web repository.
func NewDarkWebRepository(pool *pgxpool.Pool) *DarkWebRepository {
	return &DarkWebRepository{pool: pool}
}

// UpsertAsset inserts a monitored asset, or re-activates/updates the existing
// row for the same (user_id, asset_hash). The asset's ID and CreatedAt are
// populated from the database row.
func (r *DarkWebRepository) UpsertAsset(ctx context.Context, asset *models.MonitoredAsset) error {
	query := `
  INSERT INTO orbguard_lab.darkweb_assets
    (user_id, device_id, asset_type, asset_value, asset_hash,
     display_name, is_active, breach_count, last_checked)
  VALUES ($1,$2,$3,$4,$5,$6,TRUE,$7,$8)
  ON CONFLICT (user_id, asset_hash) DO UPDATE
    SET is_active    = TRUE,
        device_id    = EXCLUDED.device_id,
        breach_count = EXCLUDED.breach_count,
        last_checked = COALESCE(EXCLUDED.last_checked, orbguard_lab.darkweb_assets.last_checked),
        updated_at   = NOW()
  RETURNING id, created_at
  `

	return r.pool.QueryRow(
		ctx,
		query,
		asset.UserID,
		asset.DeviceID,
		string(asset.AssetType),
		asset.AssetValue,
		asset.AssetHash,
		asset.DisplayName,
		asset.BreachCount,
		asset.LastChecked,
	).Scan(&asset.ID, &asset.CreatedAt)
}

// DeleteAsset removes a monitored asset owned by userID. Returns true when a
// row was actually deleted (i.e. the asset existed and belonged to the user).
func (r *DarkWebRepository) DeleteAsset(ctx context.Context, userID string, assetID uuid.UUID) (bool, error) {
	tag, err := r.pool.Exec(ctx,
		`DELETE FROM orbguard_lab.darkweb_assets WHERE id = $1 AND user_id = $2`,
		assetID, userID,
	)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

const assetColumns = `
  id, user_id, device_id, asset_type, asset_value, asset_hash,
  display_name, is_active, breach_count, last_checked, created_at
`

// ListAssetsByUser returns all monitored assets owned by userID.
func (r *DarkWebRepository) ListAssetsByUser(ctx context.Context, userID string) ([]models.MonitoredAsset, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT `+assetColumns+`
     FROM orbguard_lab.darkweb_assets
     WHERE user_id = $1
     ORDER BY created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	return scanAssets(rows)
}

// ListActiveAssets returns every active monitored asset (all users), used by
// the periodic refresh job.
func (r *DarkWebRepository) ListActiveAssets(ctx context.Context) ([]models.MonitoredAsset, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT `+assetColumns+`
     FROM orbguard_lab.darkweb_assets
     WHERE is_active
     ORDER BY last_checked NULLS FIRST`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	return scanAssets(rows)
}

func scanAssets(rows pgx.Rows) ([]models.MonitoredAsset, error) {
	assets := []models.MonitoredAsset{}
	for rows.Next() {
		var a models.MonitoredAsset
		var assetType string
		if err := rows.Scan(
			&a.ID,
			&a.UserID,
			&a.DeviceID,
			&assetType,
			&a.AssetValue,
			&a.AssetHash,
			&a.DisplayName,
			&a.IsActive,
			&a.BreachCount,
			&a.LastChecked,
			&a.CreatedAt,
		); err != nil {
			return nil, err
		}
		a.AssetType = models.BreachType(assetType)
		assets = append(assets, a)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return assets, nil
}

// UpdateAssetCheckResult records the outcome of a breach check for an asset.
func (r *DarkWebRepository) UpdateAssetCheckResult(ctx context.Context, assetID uuid.UUID, breachCount int, checkedAt time.Time) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE orbguard_lab.darkweb_assets
     SET breach_count = $2, last_checked = $3, updated_at = NOW()
     WHERE id = $1`,
		assetID, breachCount, checkedAt,
	)
	return err
}

// InsertAlert stores a breach alert for an asset. Duplicate alerts for the
// same (asset, breach name) are ignored. Returns true when a new alert row
// was inserted, false when it already existed.
func (r *DarkWebRepository) InsertAlert(ctx context.Context, userID string, alert *models.BreachAlert, breachDomain string) (bool, error) {
	var breachID *uuid.UUID
	if alert.BreachID != uuid.Nil {
		breachID = &alert.BreachID
	}

	query := `
  INSERT INTO orbguard_lab.darkweb_alerts
    (asset_id, user_id, breach_id, breach_name, breach_domain,
     severity, data_exposed, detected_at, is_read)
  VALUES ($1,$2,$3,$4,$5,$6,$7,$8,FALSE)
  ON CONFLICT (asset_id, breach_name) DO NOTHING
  RETURNING id
  `

	dataExposed := alert.DataExposed
	if dataExposed == nil {
		dataExposed = []string{}
	}

	rows, err := r.pool.Query(
		ctx,
		query,
		alert.AssetID,
		userID,
		breachID,
		alert.BreachName,
		breachDomain,
		string(alert.Severity),
		dataExposed,
		alert.DetectedAt,
	)
	if err != nil {
		return false, err
	}
	defer rows.Close()

	inserted := false
	if rows.Next() {
		if err := rows.Scan(&alert.ID); err != nil {
			return false, err
		}
		inserted = true
	}
	return inserted, rows.Err()
}

const alertColumns = `
  id, asset_id, user_id, breach_id, breach_name, breach_domain,
  severity, data_exposed, detected_at, acked_at, is_read
`

// AlertRecord is a persisted breach alert plus the columns that are not part
// of the API model (owner, breach domain for action links).
type AlertRecord struct {
	Alert        models.BreachAlert
	UserID       string
	BreachDomain string
}

// ListAlertsByUser returns all alerts belonging to assets owned by userID.
func (r *DarkWebRepository) ListAlertsByUser(ctx context.Context, userID string) ([]AlertRecord, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT `+alertColumns+`
     FROM orbguard_lab.darkweb_alerts
     WHERE user_id = $1
     ORDER BY detected_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	return scanAlerts(rows)
}

// ListAlertsByAsset returns all alerts for a single asset.
func (r *DarkWebRepository) ListAlertsByAsset(ctx context.Context, assetID uuid.UUID) ([]AlertRecord, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT `+alertColumns+`
     FROM orbguard_lab.darkweb_alerts
     WHERE asset_id = $1
     ORDER BY detected_at DESC`,
		assetID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	return scanAlerts(rows)
}

func scanAlerts(rows pgx.Rows) ([]AlertRecord, error) {
	records := []AlertRecord{}
	for rows.Next() {
		var rec AlertRecord
		var severity string
		var breachID *uuid.UUID
		if err := rows.Scan(
			&rec.Alert.ID,
			&rec.Alert.AssetID,
			&rec.UserID,
			&breachID,
			&rec.Alert.BreachName,
			&rec.BreachDomain,
			&severity,
			&rec.Alert.DataExposed,
			&rec.Alert.DetectedAt,
			&rec.Alert.AckedAt,
			&rec.Alert.IsRead,
		); err != nil {
			return nil, err
		}
		if breachID != nil {
			rec.Alert.BreachID = *breachID
		}
		rec.Alert.Severity = models.BreachSeverity(severity)
		records = append(records, rec)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return records, nil
}

// AcknowledgeAlert marks an alert as read, verifying that it belongs to
// userID. Returns true when a row was updated.
func (r *DarkWebRepository) AcknowledgeAlert(ctx context.Context, userID string, alertID uuid.UUID) (bool, error) {
	tag, err := r.pool.Exec(ctx,
		`UPDATE orbguard_lab.darkweb_alerts
     SET is_read = TRUE, acked_at = NOW()
     WHERE id = $1 AND user_id = $2`,
		alertID, userID,
	)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

// RecordCheck stores one breach/password check event for statistics.
func (r *DarkWebRepository) RecordCheck(ctx context.Context, kind string, breached bool, breachCount int) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO orbguard_lab.darkweb_check_events (kind, breached, breach_count)
     VALUES ($1, $2, $3)`,
		kind, breached, breachCount,
	)
	return err
}

// CheckStats holds aggregate check statistics computed from real events.
type CheckStats struct {
	TotalChecks      int64
	BreachesFound    int64
	PasswordsChecked int64
	CompromisedCount int64
	Checks24h        int64
	Breaches24h      int64
}

// GetCheckStats computes aggregate statistics from the check-event log.
func (r *DarkWebRepository) GetCheckStats(ctx context.Context) (*CheckStats, error) {
	query := `
  SELECT
    COUNT(*) FILTER (WHERE kind = 'email_check'),
    COALESCE(SUM(breach_count) FILTER (WHERE kind = 'email_check'), 0),
    COUNT(*) FILTER (WHERE kind = 'password_check'),
    COUNT(*) FILTER (WHERE kind = 'password_check' AND breached),
    COUNT(*) FILTER (WHERE checked_at > NOW() - INTERVAL '24 hours'),
    COUNT(*) FILTER (WHERE checked_at > NOW() - INTERVAL '24 hours' AND breached)
  FROM orbguard_lab.darkweb_check_events
  `

	var s CheckStats
	if err := r.pool.QueryRow(ctx, query).Scan(
		&s.TotalChecks,
		&s.BreachesFound,
		&s.PasswordsChecked,
		&s.CompromisedCount,
		&s.Checks24h,
		&s.Breaches24h,
	); err != nil {
		return nil, err
	}
	return &s, nil
}

// CountAssetsByType returns the number of monitored assets per asset type.
func (r *DarkWebRepository) CountAssetsByType(ctx context.Context) (map[string]int64, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT asset_type, COUNT(*)
     FROM orbguard_lab.darkweb_assets
     GROUP BY asset_type`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := make(map[string]int64)
	for rows.Next() {
		var assetType string
		var count int64
		if err := rows.Scan(&assetType, &count); err != nil {
			return nil, err
		}
		result[assetType] = count
	}
	return result, rows.Err()
}

// CountAlertsBySeverity returns the number of alerts per severity.
func (r *DarkWebRepository) CountAlertsBySeverity(ctx context.Context) (map[string]int64, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT severity, COUNT(*)
     FROM orbguard_lab.darkweb_alerts
     GROUP BY severity`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := make(map[string]int64)
	for rows.Next() {
		var severity string
		var count int64
		if err := rows.Scan(&severity, &count); err != nil {
			return nil, err
		}
		result[severity] = count
	}
	return result, rows.Err()
}
