-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Device registry for anti-theft / device security tracking.
-- (Separate from orbguard_lab.devices which is the API auth device table.)
CREATE TABLE IF NOT EXISTS orbguard_lab.device_security_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,
  device_id VARCHAR(255) NOT NULL UNIQUE,
  name VARCHAR(255) NOT NULL DEFAULT '',
  model VARCHAR(255) NOT NULL DEFAULT '',
  manufacturer VARCHAR(255) NOT NULL DEFAULT '',
  platform VARCHAR(50) NOT NULL DEFAULT '',
  os_version VARCHAR(100) NOT NULL DEFAULT '',
  security_patch VARCHAR(50) NOT NULL DEFAULT '',
  api_level INT NOT NULL DEFAULT 0,
  status VARCHAR(50) NOT NULL DEFAULT 'active',
  is_rooted BOOLEAN NOT NULL DEFAULT FALSE,
  is_encrypted BOOLEAN NOT NULL DEFAULT FALSE,
  has_screen_lock BOOLEAN NOT NULL DEFAULT FALSE,
  biometric_type VARCHAR(50) NOT NULL DEFAULT '',
  push_token TEXT NOT NULL DEFAULT '',
  last_location JSONB,
  last_seen TIMESTAMPTZ,
  registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_devsec_devices_user ON orbguard_lab.device_security_devices(user_id);
CREATE INDEX IF NOT EXISTS idx_devsec_devices_status ON orbguard_lab.device_security_devices(status);

-- Location history (bounded to the most recent N rows per device by the service).
CREATE TABLE IF NOT EXISTS orbguard_lab.device_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id VARCHAR(255) NOT NULL,
  lat DOUBLE PRECISION NOT NULL,
  lng DOUBLE PRECISION NOT NULL,
  accuracy DOUBLE PRECISION NOT NULL DEFAULT 0,
  altitude DOUBLE PRECISION NOT NULL DEFAULT 0,
  speed DOUBLE PRECISION NOT NULL DEFAULT 0,
  bearing DOUBLE PRECISION NOT NULL DEFAULT 0,
  provider VARCHAR(50) NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '',
  battery INT NOT NULL DEFAULT 0,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_devsec_locations_device_time
  ON orbguard_lab.device_locations(device_id, recorded_at DESC);

-- Current SIM state per device (is_present = SIM was in the latest report).
CREATE TABLE IF NOT EXISTS orbguard_lab.device_sims (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id VARCHAR(255) NOT NULL,
  slot_index INT NOT NULL DEFAULT 0,
  iccid VARCHAR(64) NOT NULL,
  imsi VARCHAR(64) NOT NULL DEFAULT '',
  carrier VARCHAR(255) NOT NULL DEFAULT '',
  country_code VARCHAR(10) NOT NULL DEFAULT '',
  phone_number VARCHAR(32) NOT NULL DEFAULT '',
  is_active BOOLEAN NOT NULL DEFAULT FALSE,
  is_esim BOOLEAN NOT NULL DEFAULT FALSE,
  is_present BOOLEAN NOT NULL DEFAULT TRUE,
  first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_devsec_sims_device_iccid UNIQUE (device_id, iccid)
);

CREATE INDEX IF NOT EXISTS idx_devsec_sims_device ON orbguard_lab.device_sims(device_id);

-- SIM change / swap events.
CREATE TABLE IF NOT EXISTS orbguard_lab.device_sim_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id VARCHAR(255) NOT NULL,
  iccid VARCHAR(64) NOT NULL DEFAULT '',
  carrier VARCHAR(255) NOT NULL DEFAULT '',
  event_type VARCHAR(32) NOT NULL,
  risk_level VARCHAR(32) NOT NULL DEFAULT 'medium',
  is_alerted BOOLEAN NOT NULL DEFAULT FALSE,
  alerted_at TIMESTAMPTZ,
  old_sim JSONB,
  new_sim JSONB,
  location JSONB,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_devsec_sim_events_device_time
  ON orbguard_lab.device_sim_events(device_id, occurred_at DESC);

-- Remote commands (locate / lock / wipe / ring / take_selfie / ...).
CREATE TABLE IF NOT EXISTS orbguard_lab.device_commands (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,
  device_id VARCHAR(255) NOT NULL,
  command VARCHAR(32) NOT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'sent', 'delivered', 'executed', 'failed', 'expired')),
  payload JSONB,
  result TEXT NOT NULL DEFAULT '',
  error TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  executed_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_devsec_commands_device_status
  ON orbguard_lab.device_commands(device_id, status);
CREATE INDEX IF NOT EXISTS idx_devsec_commands_expires
  ON orbguard_lab.device_commands(expires_at);

-- Thief selfies captured on unauthorized unlock attempts (stored as URL/storage path).
CREATE TABLE IF NOT EXISTS orbguard_lab.device_selfies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id VARCHAR(255) NOT NULL,
  image_url TEXT NOT NULL DEFAULT '',
  image_hash VARCHAR(128) NOT NULL DEFAULT '',
  trigger_type VARCHAR(50) NOT NULL DEFAULT '',
  unlock_attempts INT NOT NULL DEFAULT 0,
  location JSONB,
  captured_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_devsec_selfies_device_time
  ON orbguard_lab.device_selfies(device_id, captured_at DESC);

-- Anti-theft settings (full settings document as JSONB, incl. trusted SIM ICCIDs).
CREATE TABLE IF NOT EXISTS orbguard_lab.device_security_settings (
  device_id VARCHAR(255) PRIMARY KEY,
  settings JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- +goose StatementEnd


-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS device_security_settings;
DROP TABLE IF EXISTS device_selfies;
DROP TABLE IF EXISTS device_commands;
DROP TABLE IF EXISTS device_sim_events;
DROP TABLE IF EXISTS device_sims;
DROP TABLE IF EXISTS device_locations;
DROP TABLE IF EXISTS device_security_devices;

-- +goose StatementEnd
