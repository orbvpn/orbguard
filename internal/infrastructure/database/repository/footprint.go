package repository

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"orbguard-lab/internal/domain/models"
)

// ---------------------------------------------------------------------------
// FootprintRepository — data-broker removal requests
// ---------------------------------------------------------------------------

// FootprintRepository persists digital-footprint removal (opt-out) requests.
// It satisfies digital_footprint.RemovalStore.
type FootprintRepository struct {
	pool *pgxpool.Pool
}

// NewFootprintRepository creates a new footprint repository.
func NewFootprintRepository(pool *pgxpool.Pool) *FootprintRepository {
	return &FootprintRepository{pool: pool}
}

// NewFootprintRepositoryFromRepos builds a FootprintRepository reusing the
// shared connection pool held by the existing repositories. Returns nil when
// the repositories (and therefore the pool) are unavailable.
func NewFootprintRepositoryFromRepos(repos *Repositories) *FootprintRepository {
	if repos == nil || repos.Devices == nil || repos.Devices.pool == nil {
		return nil
	}
	return NewFootprintRepository(repos.Devices.pool)
}

// removalLastAttempt is the JSONB document stored in removal_requests.last_attempt.
type removalLastAttempt struct {
	AttemptedAt time.Time `json:"attempted_at"`
	Status      string    `json:"status"`
	Error       string    `json:"error,omitempty"`
	RetryCount  int       `json:"retry_count"`
}

// CreateRemovalRequest inserts a new removal request.
func (r *FootprintRepository) CreateRemovalRequest(ctx context.Context, req *models.RemovalRequest) error {
	doc, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("marshal removal request: %w", err)
	}

	query := `
	INSERT INTO orbguard_lab.removal_requests
	    (id, user_id, broker_id, broker_name, broker_domain, status, method, request, created_at, updated_at)
	VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`

	userID := req.UserID
	_, err = r.pool.Exec(ctx, query,
		req.ID, uuidToNullUUID(&userID), req.BrokerID, req.BrokerName, req.BrokerDomain,
		string(req.Status), string(req.Method), doc, req.CreatedAt, req.UpdatedAt,
	)
	return err
}

// UpdateRemovalRequest persists the current state of a removal request and
// records the latest processing attempt.
func (r *FootprintRepository) UpdateRemovalRequest(ctx context.Context, req *models.RemovalRequest) error {
	doc, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("marshal removal request: %w", err)
	}

	attempt, err := json.Marshal(removalLastAttempt{
		AttemptedAt: time.Now(),
		Status:      string(req.Status),
		Error:       req.FailureReason,
		RetryCount:  req.RetryCount,
	})
	if err != nil {
		return fmt.Errorf("marshal last attempt: %w", err)
	}

	query := `
	UPDATE orbguard_lab.removal_requests
	SET status = $2, method = $3, request = $4, last_attempt = $5, updated_at = NOW()
	WHERE id = $1`

	tag, err := r.pool.Exec(ctx, query,
		req.ID, string(req.Status), string(req.Method), doc, attempt,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("removal request not found: %s", req.ID)
	}
	return nil
}

// GetRemovalRequest fetches a removal request by ID.
func (r *FootprintRepository) GetRemovalRequest(ctx context.Context, id uuid.UUID) (*models.RemovalRequest, error) {
	var doc []byte
	err := r.pool.QueryRow(ctx,
		`SELECT request FROM orbguard_lab.removal_requests WHERE id = $1`, id,
	).Scan(&doc)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, fmt.Errorf("removal request not found: %s", id)
	}
	if err != nil {
		return nil, err
	}

	var req models.RemovalRequest
	if err := json.Unmarshal(doc, &req); err != nil {
		return nil, fmt.Errorf("unmarshal removal request: %w", err)
	}
	return &req, nil
}

// ListRemovalRequestsByUser returns all removal requests for a user, newest first.
func (r *FootprintRepository) ListRemovalRequestsByUser(ctx context.Context, userID uuid.UUID) ([]models.RemovalRequest, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT request FROM orbguard_lab.removal_requests WHERE user_id = $1 ORDER BY created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	requests := make([]models.RemovalRequest, 0)
	for rows.Next() {
		var doc []byte
		if err := rows.Scan(&doc); err != nil {
			return nil, err
		}
		var req models.RemovalRequest
		if err := json.Unmarshal(doc, &req); err != nil {
			return nil, fmt.Errorf("unmarshal removal request: %w", err)
		}
		requests = append(requests, req)
	}
	return requests, rows.Err()
}

// ---------------------------------------------------------------------------
// NetworkSecurityRepository — audits, device network configs, firewall state
// ---------------------------------------------------------------------------

// NetworkSecurityRepository persists per-device network audit results, DNS/VPN
// configuration documents, desktop firewall rules and manually blocked IPs.
// It satisfies desktop_security.FirewallStore.
type NetworkSecurityRepository struct {
	pool *pgxpool.Pool
}

// NewNetworkSecurityRepository creates a new network security repository.
func NewNetworkSecurityRepository(pool *pgxpool.Pool) *NetworkSecurityRepository {
	return &NetworkSecurityRepository{pool: pool}
}

// NewNetworkSecurityRepositoryFromRepos builds a NetworkSecurityRepository
// reusing the shared connection pool held by the existing repositories.
// Returns nil when the repositories (and therefore the pool) are unavailable.
func NewNetworkSecurityRepositoryFromRepos(repos *Repositories) *NetworkSecurityRepository {
	if repos == nil || repos.Devices == nil || repos.Devices.pool == nil {
		return nil
	}
	return NewNetworkSecurityRepository(repos.Devices.pool)
}

// NetworkAuditRecord is a single persisted network security audit outcome.
type NetworkAuditRecord struct {
	DeviceID        string
	AuditType       string // wifi, dns, full
	NetworkIdentity string
	RiskLevel       string
	RiskScore       float64
	RogueAPCount    int
	EvilTwinCount   int
	HijackDetected  bool
	Findings        any // serialized to JSONB
}

// SaveNetworkAudit inserts a completed audit result.
func (r *NetworkSecurityRepository) SaveNetworkAudit(ctx context.Context, rec NetworkAuditRecord) error {
	var findings []byte
	if rec.Findings != nil {
		var err error
		findings, err = json.Marshal(rec.Findings)
		if err != nil {
			return fmt.Errorf("marshal audit findings: %w", err)
		}
	}

	query := `
	INSERT INTO orbguard_lab.network_audits
	    (device_id, audit_type, network_identity, risk_level, risk_score,
	     rogue_ap_count, evil_twin_count, hijack_detected, findings, audited_at)
	VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())`

	_, err := r.pool.Exec(ctx, query,
		rec.DeviceID, rec.AuditType, rec.NetworkIdentity, rec.RiskLevel, rec.RiskScore,
		rec.RogueAPCount, rec.EvilTwinCount, rec.HijackDetected, findings,
	)
	return err
}

// NetworkAuditStats aggregates persisted audit outcomes. When deviceID is
// empty, stats cover all devices.
type NetworkAuditStats struct {
	TotalScans       int64
	WiFiAudits       int64
	DNSChecks        int64
	FullAudits       int64
	AttacksDetected  int64
	RogueAPs         int64
	EvilTwins        int64
	DNSHijacks       int64
	UnsecureNetworks int64
	Last24hScans     int64
	Last24hAttacks   int64
	Last24hRogueAPs  int64
	Last24hEvilTwins int64
}

// GetNetworkAuditStats aggregates audit results. deviceID == "" aggregates
// across all devices (service-level view).
func (r *NetworkSecurityRepository) GetNetworkAuditStats(ctx context.Context, deviceID string) (*NetworkAuditStats, error) {
	query := `
	SELECT
	    COUNT(*),
	    COUNT(*) FILTER (WHERE audit_type = 'wifi'),
	    COUNT(*) FILTER (WHERE audit_type = 'dns'),
	    COUNT(*) FILTER (WHERE audit_type = 'full'),
	    COUNT(*) FILTER (WHERE rogue_ap_count > 0 OR evil_twin_count > 0 OR hijack_detected),
	    COALESCE(SUM(rogue_ap_count), 0),
	    COALESCE(SUM(evil_twin_count), 0),
	    COUNT(*) FILTER (WHERE hijack_detected),
	    COUNT(*) FILTER (WHERE risk_level IN ('high', 'critical')),
	    COUNT(*) FILTER (WHERE audited_at > NOW() - INTERVAL '24 hours'),
	    COUNT(*) FILTER (WHERE audited_at > NOW() - INTERVAL '24 hours'
	        AND (rogue_ap_count > 0 OR evil_twin_count > 0 OR hijack_detected)),
	    COALESCE(SUM(rogue_ap_count) FILTER (WHERE audited_at > NOW() - INTERVAL '24 hours'), 0),
	    COALESCE(SUM(evil_twin_count) FILTER (WHERE audited_at > NOW() - INTERVAL '24 hours'), 0)
	FROM orbguard_lab.network_audits
	WHERE ($1 = '' OR device_id = $1)`

	var s NetworkAuditStats
	err := r.pool.QueryRow(ctx, query, deviceID).Scan(
		&s.TotalScans, &s.WiFiAudits, &s.DNSChecks, &s.FullAudits,
		&s.AttacksDetected, &s.RogueAPs, &s.EvilTwins, &s.DNSHijacks,
		&s.UnsecureNetworks, &s.Last24hScans, &s.Last24hAttacks,
		&s.Last24hRogueAPs, &s.Last24hEvilTwins,
	)
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// DeviceNetworkConfig is the persisted DNS/VPN configuration for one device.
type DeviceNetworkConfig struct {
	DeviceID  string
	DNS       *models.DNSConfig
	VPN       *models.VPNConfig
	UpdatedAt time.Time
}

// UpsertDeviceDNSConfig stores the DNS configuration for a device.
func (r *NetworkSecurityRepository) UpsertDeviceDNSConfig(ctx context.Context, deviceID string, cfg *models.DNSConfig) error {
	doc, err := json.Marshal(cfg)
	if err != nil {
		return fmt.Errorf("marshal dns config: %w", err)
	}

	query := `
	INSERT INTO orbguard_lab.device_network_configs (device_id, dns, updated_at)
	VALUES ($1, $2, NOW())
	ON CONFLICT (device_id) DO UPDATE SET dns = EXCLUDED.dns, updated_at = NOW()`

	_, err = r.pool.Exec(ctx, query, deviceID, doc)
	return err
}

// UpsertDeviceVPNConfig stores the VPN configuration for a device.
func (r *NetworkSecurityRepository) UpsertDeviceVPNConfig(ctx context.Context, deviceID string, cfg *models.VPNConfig) error {
	doc, err := json.Marshal(cfg)
	if err != nil {
		return fmt.Errorf("marshal vpn config: %w", err)
	}

	query := `
	INSERT INTO orbguard_lab.device_network_configs (device_id, vpn, updated_at)
	VALUES ($1, $2, NOW())
	ON CONFLICT (device_id) DO UPDATE SET vpn = EXCLUDED.vpn, updated_at = NOW()`

	_, err = r.pool.Exec(ctx, query, deviceID, doc)
	return err
}

// GetDeviceNetworkConfig fetches the stored DNS/VPN configuration for a
// device. Returns (nil, nil) when no configuration has been stored yet.
func (r *NetworkSecurityRepository) GetDeviceNetworkConfig(ctx context.Context, deviceID string) (*DeviceNetworkConfig, error) {
	var dnsDoc, vpnDoc []byte
	cfg := &DeviceNetworkConfig{DeviceID: deviceID}

	err := r.pool.QueryRow(ctx,
		`SELECT dns, vpn, updated_at FROM orbguard_lab.device_network_configs WHERE device_id = $1`,
		deviceID,
	).Scan(&dnsDoc, &vpnDoc, &cfg.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	if len(dnsDoc) > 0 {
		var dns models.DNSConfig
		if err := json.Unmarshal(dnsDoc, &dns); err != nil {
			return nil, fmt.Errorf("unmarshal dns config: %w", err)
		}
		cfg.DNS = &dns
	}
	if len(vpnDoc) > 0 {
		var vpn models.VPNConfig
		if err := json.Unmarshal(vpnDoc, &vpn); err != nil {
			return nil, fmt.Errorf("unmarshal vpn config: %w", err)
		}
		cfg.VPN = &vpn
	}
	return cfg, nil
}

// ---------------------------------------------------------------------------
// Firewall persistence (desktop_security.FirewallStore)
// ---------------------------------------------------------------------------

// SaveFirewallRule inserts or updates a firewall rule document.
func (r *NetworkSecurityRepository) SaveFirewallRule(ctx context.Context, deviceID string, rule models.FirewallRule) error {
	doc, err := json.Marshal(rule)
	if err != nil {
		return fmt.Errorf("marshal firewall rule: %w", err)
	}

	query := `
	INSERT INTO orbguard_lab.firewall_rules (id, device_id, rule, created_at)
	VALUES ($1, $2, $3, $4)
	ON CONFLICT (id) DO UPDATE SET rule = EXCLUDED.rule`

	createdAt := rule.CreatedAt
	if createdAt.IsZero() {
		createdAt = time.Now()
	}
	_, err = r.pool.Exec(ctx, query, rule.ID, deviceID, doc, createdAt)
	return err
}

// DeleteFirewallRule removes a persisted firewall rule.
func (r *NetworkSecurityRepository) DeleteFirewallRule(ctx context.Context, ruleID uuid.UUID) error {
	_, err := r.pool.Exec(ctx,
		`DELETE FROM orbguard_lab.firewall_rules WHERE id = $1`, ruleID)
	return err
}

// ListFirewallRules returns the persisted firewall rules for a device
// (deviceID == "" for the host the API process runs on).
func (r *NetworkSecurityRepository) ListFirewallRules(ctx context.Context, deviceID string) ([]models.FirewallRule, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT rule FROM orbguard_lab.firewall_rules WHERE device_id = $1 ORDER BY created_at`,
		deviceID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	rules := make([]models.FirewallRule, 0)
	for rows.Next() {
		var doc []byte
		if err := rows.Scan(&doc); err != nil {
			return nil, err
		}
		var rule models.FirewallRule
		if err := json.Unmarshal(doc, &rule); err != nil {
			return nil, fmt.Errorf("unmarshal firewall rule: %w", err)
		}
		rules = append(rules, rule)
	}
	return rules, rows.Err()
}

// SaveBlockedIP persists a manually blocked IP.
func (r *NetworkSecurityRepository) SaveBlockedIP(ctx context.Context, deviceID, ip, reason string) error {
	query := `
	INSERT INTO orbguard_lab.blocked_ips (device_id, ip, reason, created_at)
	VALUES ($1, $2, $3, NOW())
	ON CONFLICT (device_id, ip) DO UPDATE SET reason = EXCLUDED.reason`

	_, err := r.pool.Exec(ctx, query, deviceID, ip, reason)
	return err
}

// ListBlockedIPs returns the persisted blocked IPs (ip -> reason) for a device.
func (r *NetworkSecurityRepository) ListBlockedIPs(ctx context.Context, deviceID string) (map[string]string, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT ip, reason FROM orbguard_lab.blocked_ips WHERE device_id = $1`,
		deviceID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	blocked := make(map[string]string)
	for rows.Next() {
		var ip, reason string
		if err := rows.Scan(&ip, &reason); err != nil {
			return nil, err
		}
		blocked[ip] = reason
	}
	return blocked, rows.Err()
}

// ---------------------------------------------------------------------------
// Device protection state (stats /stats/protection)
// ---------------------------------------------------------------------------

// DeviceProtectionState reflects which protection modules are actually
// enabled / in use for a device, sourced from persisted state.
type DeviceProtectionState struct {
	DNSConfigured      bool // device_network_configs.dns present
	VPNConfigured      bool // device_network_configs.vpn present
	AntiTheftEnabled   bool // device_security_settings with any enable_* flag true
	NetworkAuditRecent bool // network audit within the last 30 days
	SMSActive          bool // SMS analysis within the last 30 days
	AppScanActive      bool // app analysis within the last 30 days
}

// GetDeviceProtectionState reads the real protection-module state for a
// device from the persisted tables.
func (r *NetworkSecurityRepository) GetDeviceProtectionState(ctx context.Context, deviceID string) (*DeviceProtectionState, error) {
	query := `
	SELECT
	    EXISTS(SELECT 1 FROM orbguard_lab.device_network_configs c
	           WHERE c.device_id = $1 AND c.dns IS NOT NULL),
	    EXISTS(SELECT 1 FROM orbguard_lab.device_network_configs c
	           WHERE c.device_id = $1 AND c.vpn IS NOT NULL),
	    EXISTS(SELECT 1 FROM orbguard_lab.device_security_settings s
	           WHERE s.device_id = $1 AND (
	               COALESCE((s.settings->>'enable_remote_locate')::boolean, FALSE) OR
	               COALESCE((s.settings->>'enable_remote_lock')::boolean, FALSE) OR
	               COALESCE((s.settings->>'enable_remote_wipe')::boolean, FALSE) OR
	               COALESCE((s.settings->>'enable_thief_selfie')::boolean, FALSE) OR
	               COALESCE((s.settings->>'enable_sim_alert')::boolean, FALSE))),
	    EXISTS(SELECT 1 FROM orbguard_lab.network_audits a
	           WHERE a.device_id = $1 AND a.audited_at > NOW() - INTERVAL '30 days'),
	    EXISTS(SELECT 1 FROM orbguard_lab.sms_analyses m
	           WHERE m.device_id = $1 AND m.analyzed_at > NOW() - INTERVAL '30 days'),
	    EXISTS(SELECT 1 FROM orbguard_lab.app_analyses p
	           WHERE p.device_id = $1 AND p.analyzed_at > NOW() - INTERVAL '30 days')`

	var state DeviceProtectionState
	err := r.pool.QueryRow(ctx, query, deviceID).Scan(
		&state.DNSConfigured, &state.VPNConfigured, &state.AntiTheftEnabled,
		&state.NetworkAuditRecent, &state.SMSActive, &state.AppScanActive,
	)
	if err != nil {
		return nil, err
	}
	return &state, nil
}

// ---------------------------------------------------------------------------
// Device posture signals (Zero Trust /enterprise/zerotrust/posture)
// ---------------------------------------------------------------------------

// DevicePostureSignals aggregates the real per-device security telemetry
// persisted over the last 30 days. A Has* flag of false means no signal of
// that kind exists for the device — the matching averages/counts are then
// meaningless and posture components built on them must be reported as
// insufficient_data, never scored.
type DevicePostureSignals struct {
	// Network audits (orbguard_lab.network_audits, risk_score 0.0-1.0)
	HasNetworkAudits  bool
	NetworkAuditCount int64
	AvgNetworkRisk    float64
	NetworkAttacks    int64 // audits with rogue AP / evil twin / hijack findings

	// App analyses (orbguard_lab.app_analyses, risk_score 0-100)
	HasAppAnalyses  bool
	AppAnalysisCount int64
	AvgAppRisk      float64
	HighRiskApps    int64 // risk_level high/critical

	// SMS analyses (orbguard_lab.sms_analyses)
	HasSMSAnalyses bool
	SMSCount       int64
	SMSThreats     int64
}

// GetDevicePostureSignals reads the 30-day security telemetry for a device.
func (r *NetworkSecurityRepository) GetDevicePostureSignals(ctx context.Context, deviceID string) (*DevicePostureSignals, error) {
	query := `
	SELECT
	    (SELECT COUNT(*) FROM orbguard_lab.network_audits a
	     WHERE a.device_id = $1 AND a.audited_at > NOW() - INTERVAL '30 days'),
	    (SELECT COALESCE(AVG(a.risk_score), 0) FROM orbguard_lab.network_audits a
	     WHERE a.device_id = $1 AND a.audited_at > NOW() - INTERVAL '30 days'),
	    (SELECT COUNT(*) FROM orbguard_lab.network_audits a
	     WHERE a.device_id = $1 AND a.audited_at > NOW() - INTERVAL '30 days'
	       AND (a.rogue_ap_count > 0 OR a.evil_twin_count > 0 OR a.hijack_detected)),
	    (SELECT COUNT(*) FROM orbguard_lab.app_analyses p
	     WHERE p.device_id = $1 AND p.analyzed_at > NOW() - INTERVAL '30 days'),
	    (SELECT COALESCE(AVG(p.risk_score), 0) FROM orbguard_lab.app_analyses p
	     WHERE p.device_id = $1 AND p.analyzed_at > NOW() - INTERVAL '30 days'),
	    (SELECT COUNT(*) FROM orbguard_lab.app_analyses p
	     WHERE p.device_id = $1 AND p.analyzed_at > NOW() - INTERVAL '30 days'
	       AND p.risk_level IN ('high', 'critical')),
	    (SELECT COUNT(*) FROM orbguard_lab.sms_analyses m
	     WHERE m.device_id = $1 AND m.analyzed_at > NOW() - INTERVAL '30 days'),
	    (SELECT COUNT(*) FROM orbguard_lab.sms_analyses m
	     WHERE m.device_id = $1 AND m.analyzed_at > NOW() - INTERVAL '30 days' AND m.is_threat)`

	var s DevicePostureSignals
	err := r.pool.QueryRow(ctx, query, deviceID).Scan(
		&s.NetworkAuditCount, &s.AvgNetworkRisk, &s.NetworkAttacks,
		&s.AppAnalysisCount, &s.AvgAppRisk, &s.HighRiskApps,
		&s.SMSCount, &s.SMSThreats,
	)
	if err != nil {
		return nil, err
	}
	s.HasNetworkAudits = s.NetworkAuditCount > 0
	s.HasAppAnalyses = s.AppAnalysisCount > 0
	s.HasSMSAnalyses = s.SMSCount > 0
	return &s, nil
}

// ---------------------------------------------------------------------------
// Fleet protection coverage (compliance report assessment)
// ---------------------------------------------------------------------------

// FleetProtectionStats counts, across all active devices, how many have each
// protection capability actually configured or recently active. These are the
// only fleet-level signals compliance controls may be assessed against.
type FleetProtectionStats struct {
	TotalActiveDevices    int64
	WithDNSFiltering      int64 // device_network_configs.dns present
	WithVPN               int64 // device_network_configs.vpn present
	WithAppScanRecent     int64 // app analysis within 30 days
	WithNetworkAuditRecent int64 // network audit within 30 days
	WithSMSScanRecent     int64 // SMS analysis within 30 days
	WithAnyMonitoring     int64 // any of the three recent-analysis signals
}

// GetFleetProtectionStats aggregates real protection coverage across the
// active device fleet.
func (r *NetworkSecurityRepository) GetFleetProtectionStats(ctx context.Context) (*FleetProtectionStats, error) {
	query := `
	SELECT
	    COUNT(*),
	    COUNT(*) FILTER (WHERE EXISTS (
	        SELECT 1 FROM orbguard_lab.device_network_configs c
	        WHERE c.device_id = d.id::text AND c.dns IS NOT NULL)),
	    COUNT(*) FILTER (WHERE EXISTS (
	        SELECT 1 FROM orbguard_lab.device_network_configs c
	        WHERE c.device_id = d.id::text AND c.vpn IS NOT NULL)),
	    COUNT(*) FILTER (WHERE EXISTS (
	        SELECT 1 FROM orbguard_lab.app_analyses p
	        WHERE p.device_id = d.id::text AND p.analyzed_at > NOW() - INTERVAL '30 days')),
	    COUNT(*) FILTER (WHERE EXISTS (
	        SELECT 1 FROM orbguard_lab.network_audits a
	        WHERE a.device_id = d.id::text AND a.audited_at > NOW() - INTERVAL '30 days')),
	    COUNT(*) FILTER (WHERE EXISTS (
	        SELECT 1 FROM orbguard_lab.sms_analyses m
	        WHERE m.device_id = d.id::text AND m.analyzed_at > NOW() - INTERVAL '30 days')),
	    COUNT(*) FILTER (WHERE
	        EXISTS (SELECT 1 FROM orbguard_lab.app_analyses p
	                WHERE p.device_id = d.id::text AND p.analyzed_at > NOW() - INTERVAL '30 days')
	        OR EXISTS (SELECT 1 FROM orbguard_lab.network_audits a
	                   WHERE a.device_id = d.id::text AND a.audited_at > NOW() - INTERVAL '30 days')
	        OR EXISTS (SELECT 1 FROM orbguard_lab.sms_analyses m
	                   WHERE m.device_id = d.id::text AND m.analyzed_at > NOW() - INTERVAL '30 days'))
	FROM orbguard_lab.devices d
	WHERE d.status = 'active' AND NOT d.revoked`

	var s FleetProtectionStats
	err := r.pool.QueryRow(ctx, query).Scan(
		&s.TotalActiveDevices, &s.WithDNSFiltering, &s.WithVPN,
		&s.WithAppScanRecent, &s.WithNetworkAuditRecent, &s.WithSMSScanRecent,
		&s.WithAnyMonitoring,
	)
	if err != nil {
		return nil, err
	}
	return &s, nil
}
