-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- QR scan false-positive reports (privacy preserving: only the SHA-256
-- hash of the scanned QR content is stored, never the raw content).
CREATE TABLE IF NOT EXISTS orbguard_lab.qr_false_positives (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Reporting device (device id from auth middleware, or device_id field
  -- on service-to-service requests)
  device_id VARCHAR(255) NOT NULL,

  -- SHA-256 hex digest of the QR content that was flagged
  content_hash CHAR(64) NOT NULL,

  reason TEXT,
  reported_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_qr_false_positives_hash
  ON orbguard_lab.qr_false_positives (content_hash);

CREATE INDEX IF NOT EXISTS idx_qr_false_positives_device
  ON orbguard_lab.qr_false_positives (device_id, reported_at DESC);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS orbguard_lab.qr_false_positives;

-- +goose StatementEnd
