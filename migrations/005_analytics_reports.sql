-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE orbguard_lab.analytics_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Identity
    name VARCHAR(255) NOT NULL,
    type VARCHAR(100) NOT NULL,
    format VARCHAR(20) NOT NULL DEFAULT 'json',

    -- Lifecycle: pending / generating / completed / failed / expired
    status VARCHAR(20) NOT NULL DEFAULT 'pending',

    -- Request parameters
    params JSONB,
    time_range_start TIMESTAMP WITH TIME ZONE NOT NULL,
    time_range_end TIMESTAMP WITH TIME ZONE NOT NULL,

    -- Generated output: structured payload + rendered file bytes
    content JSONB,
    file_data BYTEA,
    file_size BIGINT NOT NULL DEFAULT 0,

    -- Failure info
    error TEXT,

    -- Ownership / audit
    created_by VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_analytics_reports_status ON orbguard_lab.analytics_reports(status);
CREATE INDEX idx_analytics_reports_created_by ON orbguard_lab.analytics_reports(created_by);
CREATE INDEX idx_analytics_reports_created_at ON orbguard_lab.analytics_reports(created_at DESC);
CREATE INDEX idx_analytics_reports_expires_at ON orbguard_lab.analytics_reports(expires_at) WHERE expires_at IS NOT NULL;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS orbguard_lab.analytics_reports;

-- +goose StatementEnd
