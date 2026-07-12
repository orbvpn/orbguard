-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

-- FCM push token registry for real-time anti-theft command delivery.
--
-- The anti-theft device record (device_security_devices.push_token) already
-- carries a token for backwards compatibility, but this dedicated table tracks
-- the richer push state needed by the FCM HTTP v1 sender: the current token,
-- the platform that produced it (android/ios), and the time it was last
-- refreshed. The sender clears the token here (and on the device record) when
-- FCM reports it as UNREGISTERED/invalid, so a stale token is never reused.
--
-- Keyed one-row-per-device by device_id. Token rotation is an UPSERT.
CREATE TABLE IF NOT EXISTS orbguard_lab.device_push_tokens (
    device_id VARCHAR(255) PRIMARY KEY,

    -- Current FCM registration token for this device. May be empty after the
    -- sender clears an UNREGISTERED token; an empty token means "push disabled
    -- for this device, fall back to polling".
    fcm_token TEXT NOT NULL DEFAULT '',

    -- Platform that registered the token ("android", "ios"). Recorded for
    -- diagnostics; FCM HTTP v1 data messages are platform-agnostic.
    platform VARCHAR(50) NOT NULL DEFAULT '',

    fcm_token_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_push_tokens_updated_at
    ON orbguard_lab.device_push_tokens(fcm_token_updated_at);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS orbguard_lab.device_push_tokens;

-- +goose StatementEnd
