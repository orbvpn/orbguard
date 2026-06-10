package repository

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"orbguard-lab/internal/domain/models"
)

// DeviceSecurityRepository persists anti-theft / device security state:
// tracked devices, location history, SIM state and change events, remote
// commands, thief selfies, and per-device anti-theft settings.
type DeviceSecurityRepository struct {
	pool *pgxpool.Pool
}

// NewDeviceSecurityRepository creates a new device security repository
func NewDeviceSecurityRepository(pool *pgxpool.Pool) *DeviceSecurityRepository {
	return &DeviceSecurityRepository{pool: pool}
}

// DeviceSecurityStats holds aggregate counters sourced from the database.
type DeviceSecurityStats struct {
	DevicesTracked   int64
	CommandsIssued   int64
	CommandsExecuted int64
	SIMAlertsRaised  int64
	SelfiesTaken     int64
}

// ---------------------------------------------------------------------------
// Devices
// ---------------------------------------------------------------------------

const deviceColumns = `id, user_id, device_id, name, model, manufacturer, platform,
	os_version, security_patch, api_level, status, is_rooted, is_encrypted,
	has_screen_lock, biometric_type, push_token, last_location, last_seen,
	registered_at, updated_at`

// UpsertDevice inserts or updates a tracked device keyed by device_id.
func (r *DeviceSecurityRepository) UpsertDevice(ctx context.Context, d *models.SecureDeviceInfo) error {
	if d.ID == uuid.Nil {
		d.ID = uuid.New()
	}

	locJSON, err := marshalNullable(d.LastLocation)
	if err != nil {
		return fmt.Errorf("marshal last_location: %w", err)
	}

	query := `
	INSERT INTO device_security_devices (
		id, user_id, device_id, name, model, manufacturer, platform,
		os_version, security_patch, api_level, status, is_rooted, is_encrypted,
		has_screen_lock, biometric_type, push_token, last_location, last_seen,
		registered_at, updated_at
	) VALUES (
		$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, NOW()
	)
	ON CONFLICT (device_id) DO UPDATE SET
		user_id         = COALESCE(EXCLUDED.user_id, device_security_devices.user_id),
		name            = EXCLUDED.name,
		model           = EXCLUDED.model,
		manufacturer    = EXCLUDED.manufacturer,
		platform        = EXCLUDED.platform,
		os_version      = EXCLUDED.os_version,
		security_patch  = EXCLUDED.security_patch,
		api_level       = EXCLUDED.api_level,
		status          = EXCLUDED.status,
		is_rooted       = EXCLUDED.is_rooted,
		is_encrypted    = EXCLUDED.is_encrypted,
		has_screen_lock = EXCLUDED.has_screen_lock,
		biometric_type  = EXCLUDED.biometric_type,
		push_token      = EXCLUDED.push_token,
		last_location   = COALESCE(EXCLUDED.last_location, device_security_devices.last_location),
		last_seen       = EXCLUDED.last_seen,
		updated_at      = NOW()
	RETURNING id, registered_at, updated_at`

	return r.pool.QueryRow(ctx, query,
		d.ID, nullableUUID(d.UserID), d.DeviceID, d.Name, d.Model, d.Manufacturer, d.Platform,
		d.OSVersion, d.SecurityPatch, d.APILevel, string(d.Status), d.IsRooted, d.IsEncrypted,
		d.HasScreenLock, d.BiometricType, d.PushToken, locJSON, nullableTime(d.LastSeen),
		d.RegisteredAt,
	).Scan(&d.ID, &d.RegisteredAt, &d.UpdatedAt)
}

// GetDevice fetches a tracked device by its client device_id.
func (r *DeviceSecurityRepository) GetDevice(ctx context.Context, deviceID string) (*models.SecureDeviceInfo, error) {
	query := `SELECT ` + deviceColumns + ` FROM device_security_devices WHERE device_id = $1`
	d, err := scanDevice(r.pool.QueryRow(ctx, query, deviceID))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, fmt.Errorf("device not found: %s", deviceID)
	}
	return d, err
}

// UpdateDeviceStatus sets the device status (active/locked/wiped/lost/stolen/...).
func (r *DeviceSecurityRepository) UpdateDeviceStatus(ctx context.Context, deviceID string, status models.DeviceStatus) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE device_security_devices SET status = $2, updated_at = NOW() WHERE device_id = $1`,
		deviceID, string(status))
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("device not found: %s", deviceID)
	}
	return nil
}

func scanDevice(row pgx.Row) (*models.SecureDeviceInfo, error) {
	var (
		d        models.SecureDeviceInfo
		userID   pgtype.UUID
		status   string
		locJSON  []byte
		lastSeen pgtype.Timestamptz
	)
	err := row.Scan(
		&d.ID, &userID, &d.DeviceID, &d.Name, &d.Model, &d.Manufacturer, &d.Platform,
		&d.OSVersion, &d.SecurityPatch, &d.APILevel, &status, &d.IsRooted, &d.IsEncrypted,
		&d.HasScreenLock, &d.BiometricType, &d.PushToken, &locJSON, &lastSeen,
		&d.RegisteredAt, &d.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	d.Status = models.DeviceStatus(status)
	if userID.Valid {
		d.UserID = uuid.UUID(userID.Bytes)
	}
	if lastSeen.Valid {
		d.LastSeen = lastSeen.Time
	}
	if len(locJSON) > 0 {
		var loc models.Location
		if err := json.Unmarshal(locJSON, &loc); err == nil {
			d.LastLocation = &loc
		}
	}
	return &d, nil
}

// ---------------------------------------------------------------------------
// Locations
// ---------------------------------------------------------------------------

// InsertLocation records a location fix, updates the device's last known
// location/last_seen, and trims history to the most recent `keep` entries.
func (r *DeviceSecurityRepository) InsertLocation(ctx context.Context, deviceID string, loc *models.Location, keep int) error {
	if keep <= 0 {
		keep = 100
	}

	locJSON, err := json.Marshal(loc)
	if err != nil {
		return fmt.Errorf("marshal location: %w", err)
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		INSERT INTO device_locations
		  (device_id, lat, lng, accuracy, altitude, speed, bearing, provider, address, battery, recorded_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
		deviceID, loc.Latitude, loc.Longitude, loc.Accuracy, loc.Altitude, loc.Speed,
		loc.Bearing, loc.Provider, loc.Address, loc.Battery, loc.Timestamp)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, `
		UPDATE device_security_devices
		SET last_location = $2, last_seen = NOW(), updated_at = NOW()
		WHERE device_id = $1`,
		deviceID, locJSON)
	if err != nil {
		return err
	}

	// Bound history: keep only the newest `keep` rows per device.
	_, err = tx.Exec(ctx, `
		DELETE FROM device_locations
		WHERE device_id = $1
		  AND id NOT IN (
		    SELECT id FROM device_locations
		    WHERE device_id = $1
		    ORDER BY recorded_at DESC
		    LIMIT $2
		  )`,
		deviceID, keep)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

// GetLocations returns the most recent locations for a device in
// chronological (oldest-first) order, bounded by limit.
func (r *DeviceSecurityRepository) GetLocations(ctx context.Context, deviceID string, limit int) ([]*models.Location, error) {
	if limit <= 0 || limit > 100 {
		limit = 100
	}

	rows, err := r.pool.Query(ctx, `
		SELECT lat, lng, accuracy, altitude, speed, bearing, provider, address, battery, recorded_at
		FROM (
			SELECT lat, lng, accuracy, altitude, speed, bearing, provider, address, battery, recorded_at
			FROM device_locations
			WHERE device_id = $1
			ORDER BY recorded_at DESC
			LIMIT $2
		) recent
		ORDER BY recorded_at ASC`,
		deviceID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	locations := make([]*models.Location, 0)
	for rows.Next() {
		var loc models.Location
		if err := rows.Scan(
			&loc.Latitude, &loc.Longitude, &loc.Accuracy, &loc.Altitude, &loc.Speed,
			&loc.Bearing, &loc.Provider, &loc.Address, &loc.Battery, &loc.Timestamp,
		); err != nil {
			return nil, err
		}
		locations = append(locations, &loc)
	}
	return locations, rows.Err()
}

// ---------------------------------------------------------------------------
// Remote commands
// ---------------------------------------------------------------------------

// InsertCommand persists a new remote command.
func (r *DeviceSecurityRepository) InsertCommand(ctx context.Context, cmd *models.RemoteCommand) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO device_commands
		  (id, user_id, device_id, command, status, payload, result, error, created_at, sent_at, executed_at, expires_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`,
		cmd.ID, nullableUUID(cmd.UserID), cmd.DeviceID, string(cmd.Type), string(cmd.Status),
		payloadToJSONB(cmd.Payload), cmd.Result, cmd.Error, cmd.CreatedAt,
		cmd.SentAt, cmd.ExecutedAt, cmd.ExpiresAt)
	return err
}

// GetPendingCommands returns non-expired pending commands for a device and
// records first delivery time. It also expires stale pending commands.
func (r *DeviceSecurityRepository) GetPendingCommands(ctx context.Context, deviceID string) ([]*models.RemoteCommand, error) {
	// Expire stale commands first so they stop being delivered.
	if _, err := r.pool.Exec(ctx, `
		UPDATE device_commands SET status = 'expired'
		WHERE device_id = $1 AND status = 'pending' AND expires_at <= NOW()`,
		deviceID); err != nil {
		return nil, err
	}

	rows, err := r.pool.Query(ctx, `
		UPDATE device_commands
		SET delivered_at = COALESCE(delivered_at, NOW())
		WHERE device_id = $1 AND status = 'pending' AND expires_at > NOW()
		RETURNING id, user_id, device_id, command, status,
		          COALESCE(payload::text, ''), result, error,
		          created_at, sent_at, executed_at, expires_at`,
		deviceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	commands := make([]*models.RemoteCommand, 0)
	for rows.Next() {
		cmd, err := scanCommand(rows)
		if err != nil {
			return nil, err
		}
		commands = append(commands, cmd)
	}
	return commands, rows.Err()
}

// AckCommand marks a command as executed or failed. Returns false when no
// matching command exists for the device.
func (r *DeviceSecurityRepository) AckCommand(ctx context.Context, deviceID string, commandID uuid.UUID, status models.CommandStatus, result, errMsg string, executedAt time.Time) (bool, error) {
	tag, err := r.pool.Exec(ctx, `
		UPDATE device_commands
		SET status = $3, result = $4, error = $5, executed_at = $6
		WHERE id = $1 AND device_id = $2`,
		commandID, deviceID, string(status), result, errMsg, executedAt)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

// CountPendingCommands counts non-expired pending commands for a device.
func (r *DeviceSecurityRepository) CountPendingCommands(ctx context.Context, deviceID string) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM device_commands
		WHERE device_id = $1 AND status = 'pending' AND expires_at > NOW()`,
		deviceID).Scan(&count)
	return count, err
}

func scanCommand(row pgx.Row) (*models.RemoteCommand, error) {
	var (
		cmd     models.RemoteCommand
		userID  pgtype.UUID
		cmdType string
		status  string
		sentAt  pgtype.Timestamptz
		execAt  pgtype.Timestamptz
	)
	err := row.Scan(
		&cmd.ID, &userID, &cmd.DeviceID, &cmdType, &status, &cmd.Payload,
		&cmd.Result, &cmd.Error, &cmd.CreatedAt, &sentAt, &execAt, &cmd.ExpiresAt,
	)
	if err != nil {
		return nil, err
	}
	cmd.Type = models.CommandType(cmdType)
	cmd.Status = models.CommandStatus(status)
	if userID.Valid {
		cmd.UserID = uuid.UUID(userID.Bytes)
	}
	if sentAt.Valid {
		t := sentAt.Time
		cmd.SentAt = &t
	}
	if execAt.Valid {
		t := execAt.Time
		cmd.ExecutedAt = &t
	}
	return &cmd, nil
}

// ---------------------------------------------------------------------------
// SIM state and events
// ---------------------------------------------------------------------------

// GetSIMs returns SIMs known for a device. When presentOnly is true, only
// SIMs that were present in the latest report are returned.
func (r *DeviceSecurityRepository) GetSIMs(ctx context.Context, deviceID string, presentOnly bool) ([]*models.SIMInfo, error) {
	query := `
		SELECT id, device_id, slot_index, iccid, imsi, carrier, country_code,
		       phone_number, is_active, is_esim, first_seen, last_seen
		FROM device_sims
		WHERE device_id = $1`
	if presentOnly {
		query += ` AND is_present = TRUE`
	}
	query += ` ORDER BY slot_index ASC, first_seen ASC`

	rows, err := r.pool.Query(ctx, query, deviceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	sims := make([]*models.SIMInfo, 0)
	for rows.Next() {
		var sim models.SIMInfo
		if err := rows.Scan(
			&sim.ID, &sim.DeviceID, &sim.SlotIndex, &sim.ICCID, &sim.IMSI, &sim.Carrier,
			&sim.CountryCode, &sim.PhoneNumber, &sim.IsActive, &sim.IsESIM,
			&sim.FirstSeen, &sim.LastSeen,
		); err != nil {
			return nil, err
		}
		sims = append(sims, &sim)
	}
	return sims, rows.Err()
}

// UpsertSIM inserts or refreshes a SIM, marking it present. first_seen is
// preserved on conflict; the model is updated with stored values.
func (r *DeviceSecurityRepository) UpsertSIM(ctx context.Context, sim *models.SIMInfo) error {
	if sim.ID == uuid.Nil {
		sim.ID = uuid.New()
	}
	return r.pool.QueryRow(ctx, `
		INSERT INTO device_sims
		  (id, device_id, slot_index, iccid, imsi, carrier, country_code,
		   phone_number, is_active, is_esim, is_present, first_seen, last_seen)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, TRUE, NOW(), NOW())
		ON CONFLICT (device_id, iccid) DO UPDATE SET
		  slot_index   = EXCLUDED.slot_index,
		  imsi         = EXCLUDED.imsi,
		  carrier      = EXCLUDED.carrier,
		  country_code = EXCLUDED.country_code,
		  phone_number = EXCLUDED.phone_number,
		  is_active    = EXCLUDED.is_active,
		  is_esim      = EXCLUDED.is_esim,
		  is_present   = TRUE,
		  last_seen    = NOW()
		RETURNING id, first_seen, last_seen`,
		sim.ID, sim.DeviceID, sim.SlotIndex, sim.ICCID, sim.IMSI, sim.Carrier,
		sim.CountryCode, sim.PhoneNumber, sim.IsActive, sim.IsESIM,
	).Scan(&sim.ID, &sim.FirstSeen, &sim.LastSeen)
}

// MarkSIMAbsent marks a SIM as no longer present in the device.
func (r *DeviceSecurityRepository) MarkSIMAbsent(ctx context.Context, deviceID, iccid string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE device_sims SET is_present = FALSE, is_active = FALSE, last_seen = NOW()
		WHERE device_id = $1 AND iccid = $2`,
		deviceID, iccid)
	return err
}

// InsertSIMEvent persists a SIM change event.
func (r *DeviceSecurityRepository) InsertSIMEvent(ctx context.Context, ev *models.SIMChangeEvent) error {
	if ev.ID == uuid.Nil {
		ev.ID = uuid.New()
	}

	oldSIM, err := marshalNullable(ev.OldSIM)
	if err != nil {
		return fmt.Errorf("marshal old_sim: %w", err)
	}
	newSIM, err := marshalNullable(ev.NewSIM)
	if err != nil {
		return fmt.Errorf("marshal new_sim: %w", err)
	}
	loc, err := marshalNullable(ev.Location)
	if err != nil {
		return fmt.Errorf("marshal location: %w", err)
	}

	iccid, carrier := "", ""
	switch {
	case ev.NewSIM != nil:
		iccid, carrier = ev.NewSIM.ICCID, ev.NewSIM.Carrier
	case ev.OldSIM != nil:
		iccid, carrier = ev.OldSIM.ICCID, ev.OldSIM.Carrier
	}

	_, err = r.pool.Exec(ctx, `
		INSERT INTO device_sim_events
		  (id, device_id, iccid, carrier, event_type, risk_level, is_alerted,
		   alerted_at, old_sim, new_sim, location, occurred_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`,
		ev.ID, ev.DeviceID, iccid, carrier, string(ev.EventType), string(ev.RiskLevel),
		ev.IsAlerted, ev.AlertedAt, oldSIM, newSIM, loc, ev.DetectedAt)
	return err
}

// GetSIMEvents returns SIM change events for a device, newest first, bounded by limit.
func (r *DeviceSecurityRepository) GetSIMEvents(ctx context.Context, deviceID string, limit int) ([]*models.SIMChangeEvent, error) {
	if limit <= 0 || limit > 500 {
		limit = 200
	}

	rows, err := r.pool.Query(ctx, `
		SELECT id, device_id, event_type, risk_level, is_alerted, alerted_at,
		       old_sim, new_sim, location, occurred_at
		FROM device_sim_events
		WHERE device_id = $1
		ORDER BY occurred_at DESC
		LIMIT $2`,
		deviceID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	events := make([]*models.SIMChangeEvent, 0)
	for rows.Next() {
		var (
			ev        models.SIMChangeEvent
			eventType string
			riskLevel string
			alertedAt pgtype.Timestamptz
			oldSIM    []byte
			newSIM    []byte
			loc       []byte
		)
		if err := rows.Scan(
			&ev.ID, &ev.DeviceID, &eventType, &riskLevel, &ev.IsAlerted, &alertedAt,
			&oldSIM, &newSIM, &loc, &ev.DetectedAt,
		); err != nil {
			return nil, err
		}
		ev.EventType = models.SIMEventType(eventType)
		ev.RiskLevel = models.SIMRiskLevel(riskLevel)
		if alertedAt.Valid {
			t := alertedAt.Time
			ev.AlertedAt = &t
		}
		ev.OldSIM = unmarshalNullable[models.SIMInfo](oldSIM)
		ev.NewSIM = unmarshalNullable[models.SIMInfo](newSIM)
		ev.Location = unmarshalNullable[models.Location](loc)
		events = append(events, &ev)
	}
	return events, rows.Err()
}

// CountAlertedSIMEvents counts SIM events that raised an alert for a device.
func (r *DeviceSecurityRepository) CountAlertedSIMEvents(ctx context.Context, deviceID string) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM device_sim_events
		WHERE device_id = $1 AND is_alerted = TRUE`,
		deviceID).Scan(&count)
	return count, err
}

// ---------------------------------------------------------------------------
// Thief selfies
// ---------------------------------------------------------------------------

// InsertSelfie persists a thief selfie record.
func (r *DeviceSecurityRepository) InsertSelfie(ctx context.Context, s *models.ThiefSelfie) error {
	if s.ID == uuid.Nil {
		s.ID = uuid.New()
	}
	loc, err := marshalNullable(s.Location)
	if err != nil {
		return fmt.Errorf("marshal location: %w", err)
	}

	_, err = r.pool.Exec(ctx, `
		INSERT INTO device_selfies
		  (id, device_id, image_url, image_hash, trigger_type, unlock_attempts, location, captured_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		s.ID, s.DeviceID, s.ImageURL, s.ImageHash, s.TriggerType, s.AttemptCount, loc, s.CapturedAt)
	return err
}

// GetSelfies returns thief selfies for a device, newest first, bounded by limit.
func (r *DeviceSecurityRepository) GetSelfies(ctx context.Context, deviceID string, limit int) ([]*models.ThiefSelfie, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}

	rows, err := r.pool.Query(ctx, `
		SELECT id, device_id, image_url, image_hash, trigger_type, unlock_attempts, location, captured_at
		FROM device_selfies
		WHERE device_id = $1
		ORDER BY captured_at DESC
		LIMIT $2`,
		deviceID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	selfies := make([]*models.ThiefSelfie, 0)
	for rows.Next() {
		var (
			s   models.ThiefSelfie
			loc []byte
		)
		if err := rows.Scan(
			&s.ID, &s.DeviceID, &s.ImageURL, &s.ImageHash, &s.TriggerType,
			&s.AttemptCount, &loc, &s.CapturedAt,
		); err != nil {
			return nil, err
		}
		s.Location = unmarshalNullable[models.Location](loc)
		selfies = append(selfies, &s)
	}
	return selfies, rows.Err()
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

// GetSettings returns anti-theft settings for a device, or (nil, nil) when
// no settings have been stored yet.
func (r *DeviceSecurityRepository) GetSettings(ctx context.Context, deviceID string) (*models.AntiTheftSettings, error) {
	var (
		raw       []byte
		updatedAt time.Time
	)
	err := r.pool.QueryRow(ctx,
		`SELECT settings, updated_at FROM device_security_settings WHERE device_id = $1`,
		deviceID).Scan(&raw, &updatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	var settings models.AntiTheftSettings
	if err := json.Unmarshal(raw, &settings); err != nil {
		return nil, fmt.Errorf("unmarshal settings for device %s: %w", deviceID, err)
	}
	settings.DeviceID = deviceID
	settings.UpdatedAt = updatedAt
	return &settings, nil
}

// UpsertSettings stores anti-theft settings for a device.
func (r *DeviceSecurityRepository) UpsertSettings(ctx context.Context, settings *models.AntiTheftSettings) error {
	raw, err := json.Marshal(settings)
	if err != nil {
		return fmt.Errorf("marshal settings: %w", err)
	}
	_, err = r.pool.Exec(ctx, `
		INSERT INTO device_security_settings (device_id, settings, updated_at)
		VALUES ($1, $2, NOW())
		ON CONFLICT (device_id) DO UPDATE SET
		  settings = EXCLUDED.settings,
		  updated_at = NOW()`,
		settings.DeviceID, raw)
	return err
}

// InsertDefaultSettings stores settings only when none exist for the device.
func (r *DeviceSecurityRepository) InsertDefaultSettings(ctx context.Context, settings *models.AntiTheftSettings) error {
	raw, err := json.Marshal(settings)
	if err != nil {
		return fmt.Errorf("marshal settings: %w", err)
	}
	_, err = r.pool.Exec(ctx, `
		INSERT INTO device_security_settings (device_id, settings, updated_at)
		VALUES ($1, $2, NOW())
		ON CONFLICT (device_id) DO NOTHING`,
		settings.DeviceID, raw)
	return err
}

// ---------------------------------------------------------------------------
// Stats
// ---------------------------------------------------------------------------

// GetStats returns aggregate device security counters from the database.
func (r *DeviceSecurityRepository) GetStats(ctx context.Context) (*DeviceSecurityStats, error) {
	stats := &DeviceSecurityStats{}
	err := r.pool.QueryRow(ctx, `
		SELECT
		  (SELECT COUNT(*) FROM device_security_devices),
		  (SELECT COUNT(*) FROM device_commands),
		  (SELECT COUNT(*) FROM device_commands WHERE status = 'executed'),
		  (SELECT COUNT(*) FROM device_sim_events WHERE is_alerted = TRUE),
		  (SELECT COUNT(*) FROM device_selfies)`,
	).Scan(
		&stats.DevicesTracked,
		&stats.CommandsIssued,
		&stats.CommandsExecuted,
		&stats.SIMAlertsRaised,
		&stats.SelfiesTaken,
	)
	if err != nil {
		return nil, err
	}
	return stats, nil
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// nullableUUID maps uuid.Nil to SQL NULL.
func nullableUUID(id uuid.UUID) pgtype.UUID {
	if id == uuid.Nil {
		return pgtype.UUID{Valid: false}
	}
	return pgtype.UUID{Bytes: id, Valid: true}
}

// nullableTime maps the zero time to SQL NULL.
func nullableTime(t time.Time) pgtype.Timestamptz {
	if t.IsZero() {
		return pgtype.Timestamptz{Valid: false}
	}
	return pgtype.Timestamptz{Time: t, Valid: true}
}

// marshalNullable marshals a pointer value to JSON, returning nil (SQL NULL)
// for nil pointers.
func marshalNullable[T any](v *T) ([]byte, error) {
	if v == nil {
		return nil, nil
	}
	return json.Marshal(v)
}

// unmarshalNullable unmarshals JSONB bytes into *T, returning nil on empty
// input or decode failure.
func unmarshalNullable[T any](raw []byte) *T {
	if len(raw) == 0 {
		return nil
	}
	var v T
	if err := json.Unmarshal(raw, &v); err != nil {
		return nil
	}
	return &v
}

// payloadToJSONB converts a command payload string into a value suitable for
// a JSONB column. Empty payloads become NULL; non-JSON strings are stored as
// a JSON string so the insert never fails.
func payloadToJSONB(payload string) []byte {
	if payload == "" {
		return nil
	}
	if json.Valid([]byte(payload)) {
		return []byte(payload)
	}
	wrapped, err := json.Marshal(payload)
	if err != nil {
		return nil
	}
	return wrapped
}
