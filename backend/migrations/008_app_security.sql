-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- App analysis history: one row per analysis performed for an app.
CREATE TABLE IF NOT EXISTS orbguard_lab.app_analyses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Scoping (device/user that submitted the analysis)
  device_id VARCHAR(255),
  user_id VARCHAR(255),

  -- App identity
  package_name VARCHAR(512) NOT NULL,
  app_name VARCHAR(512),
  version VARCHAR(255),
  install_source VARCHAR(50),

  -- Analysis outcome
  risk_score DOUBLE PRECISION NOT NULL DEFAULT 0,
  risk_level VARCHAR(20) NOT NULL,
  flags JSONB NOT NULL DEFAULT '{}'::jsonb,

  analyzed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_app_analyses_package ON orbguard_lab.app_analyses(package_name);
CREATE INDEX IF NOT EXISTS idx_app_analyses_device ON orbguard_lab.app_analyses(device_id);
CREATE INDEX IF NOT EXISTS idx_app_analyses_analyzed_at ON orbguard_lab.app_analyses(analyzed_at);
CREATE INDEX IF NOT EXISTS idx_app_analyses_risk_level ON orbguard_lab.app_analyses(risk_level);
CREATE INDEX IF NOT EXISTS idx_app_analyses_pkg_time ON orbguard_lab.app_analyses(package_name, analyzed_at DESC);

-- User-submitted reports about suspicious apps.
CREATE TABLE IF NOT EXISTS orbguard_lab.app_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  package_name VARCHAR(512) NOT NULL,
  report_type VARCHAR(50) NOT NULL,   -- malware / privacy / scam / fraud / other
  description TEXT,

  device_id VARCHAR(255),
  user_id VARCHAR(255),

  status VARCHAR(30) NOT NULL DEFAULT 'pending',  -- pending / reviewed / confirmed / dismissed

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_app_reports_package ON orbguard_lab.app_reports(package_name);
CREATE INDEX IF NOT EXISTS idx_app_reports_created_at ON orbguard_lab.app_reports(created_at);
CREATE INDEX IF NOT EXISTS idx_app_reports_status ON orbguard_lab.app_reports(status);

-- +goose StatementEnd


-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS orbguard_lab.app_reports;
DROP TABLE IF EXISTS orbguard_lab.app_analyses;

-- +goose StatementEnd
