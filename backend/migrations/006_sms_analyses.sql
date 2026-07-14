-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Stores the privacy-preserving outcome of every SMS analysis.
-- No raw message content is ever stored: only the SHA-256 hash of the
-- sender and the derived analysis fields.
CREATE TABLE IF NOT EXISTS orbguard_lab.sms_analyses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Device that requested the analysis (auth context or explicit param).
    device_id VARCHAR(255) NOT NULL,

    -- SHA-256 hex digest of the sender. NULL when no sender was provided.
    sender_hash VARCHAR(64),

    -- Derived analysis outcome.
    threat_level VARCHAR(20) NOT NULL,        -- safe / low / medium / high / critical
    risk_score DOUBLE PRECISION NOT NULL DEFAULT 0,
    is_threat BOOLEAN NOT NULL DEFAULT FALSE,

    -- JSON array of category strings (threat type + suspicious flags).
    categories JSONB NOT NULL DEFAULT '[]'::jsonb,

    analyzed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sms_analyses_device_analyzed
    ON orbguard_lab.sms_analyses(device_id, analyzed_at DESC);
CREATE INDEX IF NOT EXISTS idx_sms_analyses_threat
    ON orbguard_lab.sms_analyses(device_id, is_threat);
CREATE INDEX IF NOT EXISTS idx_sms_analyses_categories
    ON orbguard_lab.sms_analyses USING GIN (categories);

-- User reports that a message was incorrectly flagged as a threat.
CREATE TABLE IF NOT EXISTS orbguard_lab.sms_false_positives (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    device_id VARCHAR(255) NOT NULL,

    -- Optional reference to the analysed message (client-side message id).
    message_id VARCHAR(255),

    -- SHA-256 hex digest of the sender (hashed server-side for privacy).
    sender_hash VARCHAR(64),

    -- Optional free-text reason supplied by the user.
    reason TEXT,

    reported_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sms_false_positives_device
    ON orbguard_lab.sms_false_positives(device_id, reported_at DESC);
CREATE INDEX IF NOT EXISTS idx_sms_false_positives_sender
    ON orbguard_lab.sms_false_positives(sender_hash);

-- +goose StatementEnd


-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS orbguard_lab.sms_false_positives;
DROP TABLE IF EXISTS orbguard_lab.sms_analyses;

-- +goose StatementEnd
