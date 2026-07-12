package repository

import (
	"context"
	"database/sql"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"orbguard-lab/internal/infrastructure/database/db"
)

type DeviceRepository struct {
	pool    *pgxpool.Pool
	queries *db.Queries
}

func NewDeviceRepository(pool *pgxpool.Pool) *DeviceRepository {
	return &DeviceRepository{
		pool:    pool,
		queries: db.New(pool),
	}
}

type Device struct {
	ID           string
	HardwareID   string
	Platform     string
	Model        string
	Manufacturer string
	OSVersion    string
	SdkInt       int

	Status    string
	Revoked   bool
	IPAddress sql.NullString

	LastSeen  *time.Time
	CreatedAt time.Time
	UpdatedAt time.Time
}

type CreateDeviceParams struct {
	HardwareID   string
	Platform     string
	Model        string
	Manufacturer string
	OSVersion    string
	SdkInt       int
	IPAddress    string
}

func (r *DeviceRepository) Create(
	ctx context.Context,
	params CreateDeviceParams,
) (*Device, error) {

	query := `
  INSERT INTO devices
  (hardware_id, platform, model, manufacturer,
   os_version, sdk_int, ip_address,
   status, revoked, created_at, updated_at)
  VALUES ($1,$2,$3,$4,$5,$6,$7,'active',FALSE,NOW(),NOW())
  RETURNING id, created_at, updated_at
  `

	var d Device

	err := r.pool.QueryRow(
		ctx,
		query,
		params.HardwareID,
		params.Platform,
		params.Model,
		params.Manufacturer,
		params.OSVersion,
		params.SdkInt,
		params.IPAddress,
	).Scan(
		&d.ID,
		&d.CreatedAt,
		&d.UpdatedAt,
	)

	if err != nil {
		return nil, err
	}

	d.HardwareID = params.HardwareID
	d.Platform = params.Platform
	d.Model = params.Model
	d.Manufacturer = params.Manufacturer
	d.OSVersion = params.OSVersion
	d.SdkInt = params.SdkInt
	d.Status = "active"
	d.Revoked = false

	d.IPAddress = sql.NullString{
		String: params.IPAddress,
		Valid:  params.IPAddress != "",
	}

	return &d, nil
}

func (r *DeviceRepository) FindByHardwareID(
	ctx context.Context,
	hardwareID string,
) (*Device, error) {

	query := `
  SELECT id, hardware_id, platform, model, manufacturer,
         os_version, sdk_int, status, revoked,
         ip_address, last_seen, created_at, updated_at
  FROM devices
  WHERE hardware_id = $1
  LIMIT 1
  `

	var d Device

	err := r.pool.QueryRow(ctx, query, hardwareID).Scan(
		&d.ID,
		&d.HardwareID,
		&d.Platform,
		&d.Model,
		&d.Manufacturer,
		&d.OSVersion,
		&d.SdkInt,
		&d.Status,
		&d.Revoked,
		&d.IPAddress,
		&d.LastSeen,
		&d.CreatedAt,
		&d.UpdatedAt,
	)

	if err != nil {
		return nil, err
	}

	return &d, nil
}

func (r *DeviceRepository) FindByID(
	ctx context.Context,
	id string,
) (*Device, error) {

	query := `
  SELECT id, hardware_id, platform, model, manufacturer,
         os_version, sdk_int, status, revoked,
         ip_address, last_seen, created_at, updated_at
  FROM devices
  WHERE id = $1
  LIMIT 1
  `

	var d Device

	err := r.pool.QueryRow(ctx, query, id).Scan(
		&d.ID,
		&d.HardwareID,
		&d.Platform,
		&d.Model,
		&d.Manufacturer,
		&d.OSVersion,
		&d.SdkInt,
		&d.Status,
		&d.Revoked,
		&d.IPAddress,
		&d.LastSeen,
		&d.CreatedAt,
		&d.UpdatedAt,
	)

	if err != nil {
		return nil, err
	}

	return &d, nil
}

func (r *DeviceRepository) UpdateLastSeen(
	ctx context.Context,
	deviceID string,
	ip string,
) error {

	query := `
  UPDATE devices
  SET last_seen = NOW(),
      ip_address = $2,
      updated_at = NOW()
  WHERE id = $1
  `

	_, err := r.pool.Exec(
		ctx,
		query,
		deviceID,
		ip,
	)

	return err
}

func (r *DeviceRepository) Revoke(
	ctx context.Context,
	deviceID string,
) error {

	query := `
  UPDATE devices
  SET revoked = TRUE,
      status = 'revoked',
      updated_at = NOW()
  WHERE id = $1
  `

	_, err := r.pool.Exec(
		ctx,
		query,
		deviceID,
	)

	return err
}
