-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Per-user URL whitelist / blacklist entries (Safe Web protection)
CREATE TABLE IF NOT EXISTS orbguard_lab.url_list_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Owner of the entry (authenticated user id from auth middleware)
  user_id VARCHAR(255) NOT NULL,

  -- whitelist | blacklist
  list_type VARCHAR(20) NOT NULL CHECK (list_type IN ('whitelist', 'blacklist')),

  -- Domain, full URL, or wildcard pattern (e.g. *.example.com)
  url_pattern TEXT NOT NULL,

  reason TEXT,
  created_by VARCHAR(255),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (user_id, list_type, url_pattern)
);

CREATE INDEX IF NOT EXISTS idx_url_list_entries_user
  ON orbguard_lab.url_list_entries (user_id, list_type);

CREATE INDEX IF NOT EXISTS idx_url_list_entries_active
  ON orbguard_lab.url_list_entries (list_type)
  WHERE is_active = TRUE;

-- User-submitted URL reports (false positives, missed threats, feedback)
CREATE TABLE IF NOT EXISTS orbguard_lab.url_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  user_id VARCHAR(255),
  device_id VARCHAR(255),

  url TEXT NOT NULL,
  report_type VARCHAR(50) NOT NULL,
  comment TEXT,

  -- pending | reviewed | accepted | rejected
  status VARCHAR(20) NOT NULL DEFAULT 'pending',

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_url_reports_status
  ON orbguard_lab.url_reports (status);

CREATE INDEX IF NOT EXISTS idx_url_reports_user
  ON orbguard_lab.url_reports (user_id);

CREATE INDEX IF NOT EXISTS idx_url_reports_created
  ON orbguard_lab.url_reports (created_at);

-- +goose StatementEnd


-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS orbguard_lab.url_reports;
DROP TABLE IF EXISTS orbguard_lab.url_list_entries;

-- +goose StatementEnd
