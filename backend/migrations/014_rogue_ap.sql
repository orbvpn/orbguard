-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Per-device trusted access points. APs on this list are suppressed from
-- rogue-AP / evil-twin findings in POST /network/rogue-ap/scan.
CREATE TABLE IF NOT EXISTS orbguard_lab.trusted_aps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id VARCHAR(255) NOT NULL,
  ssid VARCHAR(255) NOT NULL DEFAULT '',
  bssid VARCHAR(64) NOT NULL DEFAULT '',
  added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (device_id, ssid, bssid)
);

CREATE INDEX idx_trusted_aps_device
  ON orbguard_lab.trusted_aps(device_id, added_at DESC);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS orbguard_lab.trusted_aps;

-- +goose StatementEnd
