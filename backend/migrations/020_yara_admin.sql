-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- User-submitted YARA rules (community rule submissions).
-- Submissions are created via POST /api/v1/yara/submit after passing real
-- parser/compiler validation; admins review them via
-- GET  /api/v1/admin/yara/submissions
-- POST /api/v1/admin/yara/submissions/{id}/approve
-- POST /api/v1/admin/yara/submissions/{id}/reject
--
-- NOTE on activation semantics: the in-process YARA engine has a dynamic
-- load path (YARAService.AddRule), so approval loads the rule into the live
-- engine of the API instance that handled the request. Approved rules are
-- persisted here but are NOT automatically re-loaded into the engine after a
-- process restart; the approve response states this explicitly.
CREATE TABLE orbguard_lab.yara_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Rule identity and source text exactly as submitted
    name VARCHAR(255) NOT NULL,
    rule_text TEXT NOT NULL,

    -- Submitter identity (from auth context; user id or device id)
    submitted_by VARCHAR(255),

    -- Review workflow
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'rejected')),

    -- Result of parser/compiler validation at submission time
    -- (errors, warnings, extracted rule metadata)
    validation JSONB,

    reviewed_by VARCHAR(255),
    review_notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ
);

CREATE INDEX idx_yara_submissions_status ON orbguard_lab.yara_submissions(status);
CREATE INDEX idx_yara_submissions_created_at ON orbguard_lab.yara_submissions(created_at);
CREATE INDEX idx_yara_submissions_submitted_by ON orbguard_lab.yara_submissions(submitted_by);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS orbguard_lab.yara_submissions;

-- +goose StatementEnd
