-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

-- Real SIEM alert feed.
--
-- Every security event that flows through the SIEM event path
-- (POST /enterprise/siem/events and internal audit forwarding) is persisted
-- here, one row per (event, target integration). The forward attempt outcome
-- is recorded on the same row: forwarded=TRUE on a successful delivery,
-- forward_error set when delivery failed. Events that matched no enabled
-- integration are stored with integration_id NULL so nothing is silently
-- dropped.
CREATE TABLE IF NOT EXISTS orbguard_lab.siem_alerts (
  id UUID PRIMARY KEY,
  integration_id UUID,
  severity VARCHAR(32) NOT NULL,
  title VARCHAR(512) NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  source VARCHAR(255) NOT NULL DEFAULT '',
  payload JSONB,
  forwarded BOOLEAN NOT NULL DEFAULT FALSE,
  forward_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_siem_alerts_created_at
  ON orbguard_lab.siem_alerts (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_siem_alerts_severity
  ON orbguard_lab.siem_alerts (severity);

-- MDM / SIEM integration configuration persistence.
--
-- Integrations previously lived only in MDMService / SIEMService memory and
-- were lost on every restart. The full config document is stored as JSONB
-- (including write-only credentials, which the API models marshal as "-" so
-- they are never echoed in responses); kind/provider/name/enabled are
-- mirrored into columns for listing.
CREATE TABLE IF NOT EXISTS orbguard_lab.enterprise_integrations (
  id UUID PRIMARY KEY,
  kind VARCHAR(8) NOT NULL CHECK (kind IN ('mdm', 'siem')),
  provider VARCHAR(64) NOT NULL,
  name VARCHAR(255) NOT NULL,
  config JSONB NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_enterprise_integrations_kind
  ON orbguard_lab.enterprise_integrations (kind);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS orbguard_lab.enterprise_integrations;
DROP TABLE IF EXISTS orbguard_lab.siem_alerts;

-- +goose StatementEnd
