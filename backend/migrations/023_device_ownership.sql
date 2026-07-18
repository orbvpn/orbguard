-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

-- Device ownership by OrbNet account.
--
-- OrbGuard has no account system of its own; user identity comes from OrbNet
-- (the shared OrbVPN account backend), whose JWT identifies a user by an INTEGER
-- user_id. The existing device_security_devices.user_id is a UUID (OrbGuard's
-- own would-be identity, never populated), so we add a dedicated column that
-- stores OrbNet's integer id. Ownership — enforced on every /device/{id}/*
-- route so a web caller can only act on devices they own — is checked on THIS
-- column. NULL means "unclaimed": the first logged-in owner claims the device.

ALTER TABLE orbguard_lab.device_security_devices
    ADD COLUMN IF NOT EXISTS orbnet_user_id BIGINT;

CREATE INDEX IF NOT EXISTS idx_devsec_devices_orbnet_user
    ON orbguard_lab.device_security_devices(orbnet_user_id);

COMMENT ON COLUMN orbguard_lab.device_security_devices.orbnet_user_id IS
    'OrbNet account user_id (integer) that owns this device. NULL = unclaimed. Ownership for remote anti-theft control is enforced on this column.';

-- Mirror onto the command log so an owner''s issued commands are attributable
-- to their OrbNet identity (the UUID user_id here is likewise unused).
ALTER TABLE orbguard_lab.device_commands
    ADD COLUMN IF NOT EXISTS orbnet_user_id BIGINT;

CREATE INDEX IF NOT EXISTS idx_devcmd_orbnet_user
    ON orbguard_lab.device_commands(orbnet_user_id);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
SET search_path TO orbguard_lab, public;
DROP INDEX IF EXISTS orbguard_lab.idx_devcmd_orbnet_user;
ALTER TABLE orbguard_lab.device_commands DROP COLUMN IF EXISTS orbnet_user_id;
DROP INDEX IF EXISTS orbguard_lab.idx_devsec_devices_orbnet_user;
ALTER TABLE orbguard_lab.device_security_devices DROP COLUMN IF EXISTS orbnet_user_id;
-- +goose StatementEnd
