-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

-- Zero Trust conditional access policies.
--
-- Policies were previously held only in ZeroTrustService memory and were
-- lost (and re-seeded with fresh UUIDs) on every restart. The full policy
-- document is stored as JSONB (the model is deeply nested: conditions,
-- grant controls, session controls, assignments); name/enabled/priority are
-- extracted into columns for listing and ordering.
CREATE TABLE IF NOT EXISTS orbguard_lab.conditional_access_policies (
  id UUID PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  priority INT NOT NULL DEFAULT 0,
  policy JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_conditional_access_policies_priority
  ON orbguard_lab.conditional_access_policies (priority);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS orbguard_lab.conditional_access_policies;

-- +goose StatementEnd
