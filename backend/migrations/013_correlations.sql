-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Persisted correlation events produced by the correlation engine.
-- Every event found by an on-demand correlation request or a server-side
-- correlation run is stored here so GET /correlation can return recent
-- results.
CREATE TABLE IF NOT EXISTS orbguard_lab.correlation_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Correlation request that produced this event.
    request_id UUID NOT NULL,

    -- temporal / infrastructure / ttp / behavioral / network / campaign
    type VARCHAR(40) NOT NULL,

    -- weak / moderate / strong / very_strong
    strength VARCHAR(20) NOT NULL,

    confidence DOUBLE PRECISION NOT NULL DEFAULT 0,
    description TEXT NOT NULL DEFAULT '',

    -- JSON array of indicator UUID strings involved in the correlation.
    indicator_ids JSONB NOT NULL DEFAULT '[]'::jsonb,

    -- Optional attribution.
    campaign_id UUID,
    threat_actor_id UUID,

    -- Full evidence payload (models.CorrelationEvidence).
    evidence JSONB NOT NULL DEFAULT '{}'::jsonb,

    -- 'api' for on-demand correlation requests, 'run' for server-side runs.
    triggered_by VARCHAR(40) NOT NULL DEFAULT 'api',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_correlation_events_created
    ON orbguard_lab.correlation_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_correlation_events_type
    ON orbguard_lab.correlation_events(type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_correlation_events_request
    ON orbguard_lab.correlation_events(request_id);
CREATE INDEX IF NOT EXISTS idx_correlation_events_indicators
    ON orbguard_lab.correlation_events USING GIN (indicator_ids);

-- Server-side correlation runs (POST /correlation/run): one row per run
-- with the summary statistics returned to the caller.
CREATE TABLE IF NOT EXISTS orbguard_lab.correlation_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Correlation request id shared by the events the run produced.
    request_id UUID NOT NULL,

    -- User id, device id, or 'service' that requested the run.
    requested_by VARCHAR(255) NOT NULL DEFAULT '',

    indicators_analyzed INTEGER NOT NULL DEFAULT 0,
    correlations_found INTEGER NOT NULL DEFAULT 0,
    clusters_formed INTEGER NOT NULL DEFAULT 0,
    campaigns_matched INTEGER NOT NULL DEFAULT 0,
    actors_matched INTEGER NOT NULL DEFAULT 0,
    average_confidence DOUBLE PRECISION NOT NULL DEFAULT 0,
    strongest_correlation DOUBLE PRECISION NOT NULL DEFAULT 0,
    processing_ms BIGINT NOT NULL DEFAULT 0,

    started_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_correlation_runs_completed
    ON orbguard_lab.correlation_runs(completed_at DESC);

-- +goose StatementEnd


-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS orbguard_lab.correlation_runs;
DROP TABLE IF EXISTS orbguard_lab.correlation_events;

-- +goose StatementEnd
