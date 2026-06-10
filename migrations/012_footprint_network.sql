-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Data-broker removal (opt-out) requests. The full request document is kept
-- as JSONB (authoritative), with scalar columns extracted for querying.
CREATE TABLE IF NOT EXISTS orbguard_lab.removal_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,
  broker_id UUID NOT NULL,
  broker_name VARCHAR(255) NOT NULL DEFAULT '',
  broker_domain VARCHAR(255) NOT NULL DEFAULT '',
  status VARCHAR(32) NOT NULL DEFAULT 'pending',
  method VARCHAR(32) NOT NULL DEFAULT '',
  request JSONB NOT NULL,
  last_attempt JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_removal_requests_user
  ON orbguard_lab.removal_requests(user_id, created_at DESC);
CREATE INDEX idx_removal_requests_status
  ON orbguard_lab.removal_requests(status);
CREATE INDEX idx_removal_requests_broker
  ON orbguard_lab.removal_requests(broker_id);

-- Per-device network security audit results (Wi-Fi audits, DNS checks and
-- full audits). Source of truth for /network/stats aggregation.
CREATE TABLE IF NOT EXISTS orbguard_lab.network_audits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id VARCHAR(255) NOT NULL,
  audit_type VARCHAR(32) NOT NULL DEFAULT 'wifi',
  network_identity VARCHAR(255) NOT NULL DEFAULT '',
  risk_level VARCHAR(32) NOT NULL DEFAULT 'safe',
  risk_score DOUBLE PRECISION NOT NULL DEFAULT 0,
  rogue_ap_count INT NOT NULL DEFAULT 0,
  evil_twin_count INT NOT NULL DEFAULT 0,
  hijack_detected BOOLEAN NOT NULL DEFAULT FALSE,
  findings JSONB,
  audited_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_network_audits_device_time
  ON orbguard_lab.network_audits(device_id, audited_at DESC);
CREATE INDEX idx_network_audits_type
  ON orbguard_lab.network_audits(audit_type);

-- Per-device DNS and VPN configuration documents.
CREATE TABLE IF NOT EXISTS orbguard_lab.device_network_configs (
  device_id VARCHAR(255) PRIMARY KEY,
  dns JSONB,
  vpn JSONB,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Desktop firewall rules (rule document stored as JSONB; device_id is empty
-- for rules owned by the host the API process runs on).
CREATE TABLE IF NOT EXISTS orbguard_lab.firewall_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id VARCHAR(255) NOT NULL DEFAULT '',
  rule JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_firewall_rules_device
  ON orbguard_lab.firewall_rules(device_id, created_at);

-- Manually blocked IPs (IOC feed entries are reloaded from feeds and are
-- intentionally not persisted here).
CREATE TABLE IF NOT EXISTS orbguard_lab.blocked_ips (
  device_id VARCHAR(255) NOT NULL DEFAULT '',
  ip VARCHAR(64) NOT NULL,
  reason TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (device_id, ip)
);

-- +goose StatementEnd


-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS blocked_ips;
DROP TABLE IF EXISTS firewall_rules;
DROP TABLE IF EXISTS device_network_configs;
DROP TABLE IF EXISTS network_audits;
DROP TABLE IF EXISTS removal_requests;

-- +goose StatementEnd
