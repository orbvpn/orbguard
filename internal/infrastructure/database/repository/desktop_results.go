package repository

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Desktop scan types persisted by the desktop security handlers. Each device
// keeps exactly one cached snapshot per type (the latest scan wins).
const (
	DesktopScanTypePersistence = "persistence"
	DesktopScanTypeApps        = "apps"
	DesktopScanTypeFirewall    = "firewall"
	DesktopScanTypeNetwork     = "network"
	DesktopScanTypeBrowser     = "browser"
)

// DesktopResultsRepository persists the most recent desktop security scan
// results per device so the cached read endpoints (GET /desktop/persistence,
// /desktop/apps, /desktop/firewall) can serve the last known results without
// re-running a scan.
type DesktopResultsRepository struct {
	pool *pgxpool.Pool
}

// NewDesktopResultsRepository creates a new desktop scan results repository.
func NewDesktopResultsRepository(pool *pgxpool.Pool) *DesktopResultsRepository {
	return &DesktopResultsRepository{pool: pool}
}

// NewDesktopResultsRepositoryFromRepos builds a DesktopResultsRepository
// reusing the shared connection pool held by the existing repositories.
// Returns nil when the repositories (and therefore the pool) are unavailable.
func NewDesktopResultsRepositoryFromRepos(repos *Repositories) *DesktopResultsRepository {
	if repos == nil || repos.Devices == nil || repos.Devices.pool == nil {
		return nil
	}
	return NewDesktopResultsRepository(repos.Devices.pool)
}

// UpsertScan stores the latest results for (deviceID, scanType), replacing
// any previous snapshot. results must marshal to a JSON value — by
// convention a JSON array of result items.
func (r *DesktopResultsRepository) UpsertScan(ctx context.Context, deviceID, scanType string, results any) error {
	if deviceID == "" {
		return errors.New("device id is required")
	}

	payload, err := json.Marshal(results)
	if err != nil {
		return fmt.Errorf("marshal desktop scan results: %w", err)
	}

	query := `
INSERT INTO orbguard_lab.desktop_scan_results (device_id, scan_type, results, scanned_at)
VALUES ($1, $2, $3, NOW())
ON CONFLICT (device_id, scan_type)
DO UPDATE SET results = EXCLUDED.results, scanned_at = EXCLUDED.scanned_at
`
	if _, err := r.pool.Exec(ctx, query, deviceID, scanType, payload); err != nil {
		return fmt.Errorf("upsert desktop scan results: %w", err)
	}
	return nil
}

// GetScan returns the cached results and scan time for (deviceID, scanType).
// Returns (nil, nil, nil) when the device has never run that scan — callers
// distinguish "never scanned" from an empty result set this way.
func (r *DesktopResultsRepository) GetScan(ctx context.Context, deviceID, scanType string) (json.RawMessage, *time.Time, error) {
	query := `
SELECT results, scanned_at
FROM orbguard_lab.desktop_scan_results
WHERE device_id = $1 AND scan_type = $2
`
	var results []byte
	var scannedAt time.Time
	err := r.pool.QueryRow(ctx, query, deviceID, scanType).Scan(&results, &scannedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil, nil
	}
	if err != nil {
		return nil, nil, fmt.Errorf("get desktop scan results: %w", err)
	}
	return json.RawMessage(results), &scannedAt, nil
}
