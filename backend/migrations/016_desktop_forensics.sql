-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Latest desktop security scan results, cached per device and scan type so
-- the read endpoints (GET /desktop/persistence, /desktop/apps,
-- /desktop/firewall) can serve the last known results without re-scanning.
-- Exactly one row per (device_id, scan_type): each new scan replaces the
-- previous snapshot.
CREATE TABLE IF NOT EXISTS orbguard_lab.desktop_scan_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Authenticated device that ran the scan
  device_id VARCHAR(255) NOT NULL,

  -- persistence | apps | firewall
  scan_type VARCHAR(50) NOT NULL CHECK (scan_type IN ('persistence', 'apps', 'firewall')),

  -- JSON array of result items (PersistenceItem / signed-app entries /
  -- FirewallRule), exactly as served back by the cached GET endpoints.
  results JSONB NOT NULL DEFAULT '[]'::jsonb,

  scanned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (device_id, scan_type)
);

CREATE INDEX IF NOT EXISTS idx_desktop_scan_results_device
  ON orbguard_lab.desktop_scan_results (device_id);

-- +goose StatementEnd


-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS orbguard_lab.desktop_scan_results;

-- +goose StatementEnd
