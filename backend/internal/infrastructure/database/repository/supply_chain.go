package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// SupplyChainRepository persists supply-chain vulnerability records
// (cached from OSV.dev), per-package lookup freshness markers, and the
// curated tracker-signature dataset seeded by migration 015.
type SupplyChainRepository struct {
	pool *pgxpool.Pool
}

// NewSupplyChainRepository creates a new supply-chain repository.
func NewSupplyChainRepository(pool *pgxpool.Pool) *SupplyChainRepository {
	return &SupplyChainRepository{pool: pool}
}

// NewSupplyChainRepositoryFromRepos builds a SupplyChainRepository reusing
// the shared connection pool held by the existing repositories. Returns nil
// when the repositories (and therefore the pool) are unavailable.
func NewSupplyChainRepositoryFromRepos(repos *Repositories) *SupplyChainRepository {
	if repos == nil || repos.Devices == nil || repos.Devices.pool == nil {
		return nil
	}
	return NewSupplyChainRepository(repos.Devices.pool)
}

// SupplyChainVulnRecord is one cached advisory affecting one package.
type SupplyChainVulnRecord struct {
	ID          uuid.UUID
	Ecosystem   string
	PackageName string
	// VersionRange holds the OSV affected ranges/versions for the package
	// as JSON text: {"ranges":[{"type":"SEMVER","events":[...]}],"versions":[...]}
	VersionRange string
	CVEID        string
	Severity     string
	CVSSScore    float64
	Summary      string
	Source       string
	PublishedAt  *time.Time
	FetchedAt    time.Time
}

// KnownTracker is one curated tracker SDK signature.
type KnownTracker struct {
	ID            uuid.UUID `json:"id"`
	Name          string    `json:"name"`
	CodeSignature string    `json:"code_signature"`
	Category      string    `json:"category"`
	Website       string    `json:"website"`
}

const supplyChainVulnUpsert = `
INSERT INTO orbguard_lab.supply_chain_vulns
    (id, ecosystem, package_name, version_range, cve_id, severity, cvss_score, summary, source, published_at, fetched_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
ON CONFLICT (ecosystem, package_name, cve_id) DO UPDATE SET
    version_range = EXCLUDED.version_range,
    severity      = EXCLUDED.severity,
    cvss_score    = EXCLUDED.cvss_score,
    summary       = EXCLUDED.summary,
    source        = EXCLUDED.source,
    published_at  = EXCLUDED.published_at,
    fetched_at    = EXCLUDED.fetched_at
`

// UpsertVulns stores (or refreshes) advisory records in one round trip,
// keyed by (ecosystem, package_name, cve_id).
func (r *SupplyChainRepository) UpsertVulns(ctx context.Context, recs []SupplyChainVulnRecord) error {
	if len(recs) == 0 {
		return nil
	}

	batch := &pgx.Batch{}
	for i := range recs {
		rec := &recs[i]
		if rec.ID == uuid.Nil {
			rec.ID = uuid.New()
		}
		if rec.FetchedAt.IsZero() {
			rec.FetchedAt = time.Now().UTC()
		}
		if rec.Source == "" {
			rec.Source = "osv.dev"
		}
		if rec.Severity == "" {
			rec.Severity = "unknown"
		}
		batch.Queue(supplyChainVulnUpsert,
			rec.ID,
			rec.Ecosystem,
			rec.PackageName,
			rec.VersionRange,
			rec.CVEID,
			rec.Severity,
			rec.CVSSScore,
			rec.Summary,
			rec.Source,
			rec.PublishedAt,
			rec.FetchedAt,
		)
	}

	results := r.pool.SendBatch(ctx, batch)
	defer results.Close()

	for range recs {
		if _, err := results.Exec(); err != nil {
			return fmt.Errorf("upsert supply chain vuln: %w", err)
		}
	}
	return nil
}

const supplyChainVulnColumns = `
id, ecosystem, package_name, version_range, cve_id, severity, cvss_score, summary, source, published_at, fetched_at
`

func scanSupplyChainVulns(rows pgx.Rows) ([]SupplyChainVulnRecord, error) {
	defer rows.Close()

	recs := []SupplyChainVulnRecord{}
	for rows.Next() {
		var rec SupplyChainVulnRecord
		if err := rows.Scan(
			&rec.ID,
			&rec.Ecosystem,
			&rec.PackageName,
			&rec.VersionRange,
			&rec.CVEID,
			&rec.Severity,
			&rec.CVSSScore,
			&rec.Summary,
			&rec.Source,
			&rec.PublishedAt,
			&rec.FetchedAt,
		); err != nil {
			return nil, fmt.Errorf("scan supply chain vuln: %w", err)
		}
		recs = append(recs, rec)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("supply chain vuln rows: %w", err)
	}
	return recs, nil
}

// ListVulns returns cached advisories, optionally filtered by ecosystem
// and/or package name, newest publications first.
func (r *SupplyChainRepository) ListVulns(ctx context.Context, ecosystem, packageName string, limit int) ([]SupplyChainVulnRecord, error) {
	if limit <= 0 {
		limit = 500
	}

	query := `
SELECT ` + supplyChainVulnColumns + `
FROM orbguard_lab.supply_chain_vulns
WHERE ($1 = '' OR LOWER(ecosystem) = LOWER($1))
  AND ($2 = '' OR LOWER(package_name) = LOWER($2))
ORDER BY published_at DESC NULLS LAST, fetched_at DESC
LIMIT $3
`
	rows, err := r.pool.Query(ctx, query, ecosystem, packageName, limit)
	if err != nil {
		return nil, fmt.Errorf("list supply chain vulns: %w", err)
	}
	return scanSupplyChainVulns(rows)
}

// GetVulnsForPackage returns all cached advisories for one package.
func (r *SupplyChainRepository) GetVulnsForPackage(ctx context.Context, ecosystem, packageName string) ([]SupplyChainVulnRecord, error) {
	query := `
SELECT ` + supplyChainVulnColumns + `
FROM orbguard_lab.supply_chain_vulns
WHERE LOWER(ecosystem) = LOWER($1) AND LOWER(package_name) = LOWER($2)
`
	rows, err := r.pool.Query(ctx, query, ecosystem, packageName)
	if err != nil {
		return nil, fmt.Errorf("get supply chain vulns for package: %w", err)
	}
	return scanSupplyChainVulns(rows)
}

// GetPackageLastChecked returns when the package was last successfully
// queried against OSV, or nil when it has never been checked.
func (r *SupplyChainRepository) GetPackageLastChecked(ctx context.Context, ecosystem, packageName string) (*time.Time, error) {
	query := `
SELECT last_checked_at
FROM orbguard_lab.supply_chain_package_checks
WHERE LOWER(ecosystem) = LOWER($1) AND LOWER(package_name) = LOWER($2)
`
	var checkedAt time.Time
	err := r.pool.QueryRow(ctx, query, ecosystem, packageName).Scan(&checkedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("get package last checked: %w", err)
	}
	return &checkedAt, nil
}

// PackageRef identifies one (ecosystem, package) pair.
type PackageRef struct {
	Ecosystem   string
	PackageName string
}

// MarkPackagesChecked records a successful OSV lookup for each package in
// one round trip.
func (r *SupplyChainRepository) MarkPackagesChecked(ctx context.Context, pkgs []PackageRef, checkedAt time.Time) error {
	if len(pkgs) == 0 {
		return nil
	}
	if checkedAt.IsZero() {
		checkedAt = time.Now().UTC()
	}

	query := `
INSERT INTO orbguard_lab.supply_chain_package_checks (ecosystem, package_name, last_checked_at)
VALUES ($1, $2, $3)
ON CONFLICT (ecosystem, package_name) DO UPDATE SET last_checked_at = EXCLUDED.last_checked_at
`
	batch := &pgx.Batch{}
	for _, p := range pkgs {
		batch.Queue(query, p.Ecosystem, p.PackageName, checkedAt)
	}

	results := r.pool.SendBatch(ctx, batch)
	defer results.Close()

	for range pkgs {
		if _, err := results.Exec(); err != nil {
			return fmt.Errorf("mark package checked: %w", err)
		}
	}
	return nil
}

// ListTrackers returns the curated tracker-signature dataset.
func (r *SupplyChainRepository) ListTrackers(ctx context.Context) ([]KnownTracker, error) {
	query := `
SELECT id, name, code_signature, category, website
FROM orbguard_lab.known_trackers
ORDER BY name
`
	rows, err := r.pool.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("list known trackers: %w", err)
	}
	defer rows.Close()

	trackers := []KnownTracker{}
	for rows.Next() {
		var t KnownTracker
		if err := rows.Scan(&t.ID, &t.Name, &t.CodeSignature, &t.Category, &t.Website); err != nil {
			return nil, fmt.Errorf("scan known tracker: %w", err)
		}
		trackers = append(trackers, t)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("known tracker rows: %w", err)
	}
	return trackers, nil
}
