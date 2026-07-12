-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Assets monitored for dark-web / breach exposure (emails, phones, ...).
-- Previously held in an in-memory map inside DarkWebMonitor.
CREATE TABLE IF NOT EXISTS orbguard_lab.darkweb_assets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Owning identity (user id, falling back to device id for anonymous
  -- device-scoped auth). Always derived from the auth context server-side.
  user_id VARCHAR(255) NOT NULL,
  device_id VARCHAR(255) NOT NULL DEFAULT '',

  asset_type VARCHAR(50) NOT NULL,        -- email / phone / username / ...
  asset_value TEXT NOT NULL,
  asset_hash VARCHAR(64) NOT NULL,        -- sha256(lower(value)) for lookup
  display_name VARCHAR(255) NOT NULL,     -- masked value for display

  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  breach_count INT NOT NULL DEFAULT 0,
  last_checked TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT darkweb_assets_user_hash_uniq UNIQUE (user_id, asset_hash)
);

CREATE INDEX idx_darkweb_assets_user ON orbguard_lab.darkweb_assets(user_id);
CREATE INDEX idx_darkweb_assets_active ON orbguard_lab.darkweb_assets(is_active);

-- Breach alerts raised for monitored assets.
CREATE TABLE IF NOT EXISTS orbguard_lab.darkweb_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  asset_id UUID NOT NULL REFERENCES orbguard_lab.darkweb_assets(id) ON DELETE CASCADE,
  user_id VARCHAR(255) NOT NULL,          -- denormalised owner for fast scoping

  breach_id UUID,                          -- provider breach id when available
  breach_name VARCHAR(255) NOT NULL,
  breach_domain VARCHAR(255) NOT NULL DEFAULT '',
  severity VARCHAR(20) NOT NULL,           -- low / medium / high / critical
  data_exposed TEXT[] NOT NULL DEFAULT '{}',

  detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  acked_at TIMESTAMPTZ,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,

  -- One alert per breach per asset; refresh runs dedupe on this.
  CONSTRAINT darkweb_alerts_asset_breach_uniq UNIQUE (asset_id, breach_name)
);

CREATE INDEX idx_darkweb_alerts_user ON orbguard_lab.darkweb_alerts(user_id);
CREATE INDEX idx_darkweb_alerts_asset ON orbguard_lab.darkweb_alerts(asset_id);
CREATE INDEX idx_darkweb_alerts_unread ON orbguard_lab.darkweb_alerts(user_id) WHERE NOT is_read;

-- One row per breach/password check, used for real (non-fabricated)
-- aggregate statistics including 24h windows.
CREATE TABLE IF NOT EXISTS orbguard_lab.darkweb_check_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kind VARCHAR(32) NOT NULL,               -- email_check / password_check
  breached BOOLEAN NOT NULL DEFAULT FALSE,
  breach_count INT NOT NULL DEFAULT 0,
  checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_darkweb_check_events_time ON orbguard_lab.darkweb_check_events(checked_at);
CREATE INDEX idx_darkweb_check_events_kind ON orbguard_lab.darkweb_check_events(kind);

-- +goose StatementEnd


-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS orbguard_lab.darkweb_check_events;
DROP TABLE IF EXISTS orbguard_lab.darkweb_alerts;
DROP TABLE IF EXISTS orbguard_lab.darkweb_assets;

-- +goose StatementEnd
