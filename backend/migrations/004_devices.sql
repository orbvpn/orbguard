-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

-- Pastikan extension uuid aktif
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DROP TABLE IF EXISTS orbguard_lab.devices;

CREATE TABLE orbguard_lab.devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Unique hardware identifier dari device
  hardware_id VARCHAR(255) NOT NULL UNIQUE,

  -- Platform info
  platform VARCHAR(50) NOT NULL,          -- android / ios
  model VARCHAR(255),
  manufacturer VARCHAR(255),
  os_version VARCHAR(100),
  sdk_int INT,

  -- Security & status
  status VARCHAR(50) DEFAULT 'active',    -- active / revoked / blocked
  revoked BOOLEAN DEFAULT FALSE,

  -- Network info
  ip_address INET,

  -- Tracking
  last_seen TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_devices_platform ON orbguard_lab.devices(platform);
CREATE INDEX idx_devices_status ON orbguard_lab.devices(status);
CREATE INDEX idx_devices_last_seen ON orbguard_lab.devices(last_seen);

-- +goose StatementEnd


-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS devices;

-- +goose StatementEnd