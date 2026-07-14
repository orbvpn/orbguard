-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- User-submitted threat reports (community intelligence).
-- Reports are created via POST /api/v1/intelligence/report and reviewed by
-- admins; approved reports surface in GET /api/v1/intelligence/community.
CREATE TABLE orbguard_lab.threat_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Reporter identity (from auth context; at least one is set for
    -- user/device tokens, both may be NULL for service-to-service calls)
    user_id VARCHAR(255),
    device_id VARCHAR(255),

    -- Indicator data
    indicator_value TEXT NOT NULL,
    indicator_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) NOT NULL DEFAULT 'medium',
    description TEXT NOT NULL,
    tags TEXT[],

    -- Platform / device info
    platform VARCHAR(50),
    device_model VARCHAR(100),
    os_version VARCHAR(50),
    app_version VARCHAR(50),

    -- Evidence
    evidence_data JSONB,

    -- Review workflow
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'reviewing', 'approved', 'rejected', 'duplicate')),
    reviewed_by VARCHAR(255),
    review_notes TEXT,
    reviewed_at TIMESTAMPTZ,

    -- Link to the indicator created when the report is approved
    indicator_id UUID REFERENCES orbguard_lab.indicators(id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_threat_reports_status ON orbguard_lab.threat_reports(status);
CREATE INDEX idx_threat_reports_created_at ON orbguard_lab.threat_reports(created_at);
CREATE INDEX idx_threat_reports_user_id ON orbguard_lab.threat_reports(user_id);
CREATE INDEX idx_threat_reports_device_id ON orbguard_lab.threat_reports(device_id);
CREATE INDEX idx_threat_reports_indicator_value ON orbguard_lab.threat_reports(indicator_value);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS orbguard_lab.threat_reports;

-- +goose StatementEnd
