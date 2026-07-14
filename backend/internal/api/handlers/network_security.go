package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// NetworkSecurityHandler handles network security API requests
type NetworkSecurityHandler struct {
	service   *services.NetworkSecurityService
	repo      *repository.NetworkSecurityRepository
	rogueRepo *repository.RogueAPRepository
	logger    *logger.Logger
}

// NewNetworkSecurityHandler creates a new network security handler
func NewNetworkSecurityHandler(service *services.NetworkSecurityService, log *logger.Logger) *NetworkSecurityHandler {
	return &NetworkSecurityHandler{
		service: service,
		logger:  log.WithComponent("network-security-handler"),
	}
}

// SetRepository wires the Postgres-backed repository used for audit history,
// per-device DNS/VPN configuration and stats aggregation. Without it,
// configuration endpoints return an explicit unavailable error.
func (h *NetworkSecurityHandler) SetRepository(repo *repository.NetworkSecurityRepository) {
	h.repo = repo
}

// SetRogueAPRepository wires the Postgres-backed repository for per-device
// trusted access points and the persisted threat-audit feed. Without it, the
// rogue-AP trusted-list and /network/threats endpoints return an explicit
// unavailable error (the scan endpoint still works, without trusted-AP
// suppression).
func (h *NetworkSecurityHandler) SetRogueAPRepository(repo *repository.RogueAPRepository) {
	h.rogueRepo = repo
}

// auditDeviceID resolves the device identity for persisting audit results:
// the authenticated device takes precedence over a client-supplied value.
func (h *NetworkSecurityHandler) auditDeviceID(ctx context.Context, bodyDeviceID string) string {
	if id := middleware.GetDeviceID(ctx); id != "" {
		return id
	}
	return bodyDeviceID
}

// persistAudit stores a completed audit result; persistence failures are
// logged but do not fail the audit response.
func (h *NetworkSecurityHandler) persistAudit(ctx context.Context, rec repository.NetworkAuditRecord) {
	if h.repo == nil {
		h.logger.Warn().Str("audit_type", rec.AuditType).Msg("network audit not persisted: repository not configured")
		return
	}
	if rec.DeviceID == "" {
		h.logger.Debug().Str("audit_type", rec.AuditType).Msg("network audit not persisted: no device identity")
		return
	}
	if err := h.repo.SaveNetworkAudit(ctx, rec); err != nil {
		h.logger.Error().Err(err).Str("audit_type", rec.AuditType).Msg("failed to persist network audit")
	}
}

// AuditWiFi handles POST /api/v1/network/wifi/audit
func (h *NetworkSecurityHandler) AuditWiFi(w http.ResponseWriter, r *http.Request) {
	var req models.WiFiAuditRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	result, err := h.service.AuditWiFi(r.Context(), &req)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to audit Wi-Fi")
		h.respondError(w, http.StatusInternalServerError, "failed to audit Wi-Fi")
		return
	}

	identity := ""
	if result.Network != nil {
		identity = result.Network.SSID
		if identity == "" {
			identity = result.Network.BSSID
		}
	}
	h.persistAudit(r.Context(), repository.NetworkAuditRecord{
		DeviceID:        h.auditDeviceID(r.Context(), req.DeviceID),
		AuditType:       "wifi",
		NetworkIdentity: identity,
		RiskLevel:       string(result.RiskLevel),
		RiskScore:       result.RiskScore,
		RogueAPCount:    len(result.RogueAPDetected),
		EvilTwinCount:   len(result.EvilTwinDetected),
		Findings:        result,
	})

	h.respondJSON(w, http.StatusOK, result)
}

// GetWiFiSecurityInfo handles GET /api/v1/network/wifi/security-types
func (h *NetworkSecurityHandler) GetWiFiSecurityInfo(w http.ResponseWriter, r *http.Request) {
	securityInfo := make([]map[string]interface{}, 0)

	for secType, risk := range models.WiFiSecurityRisks {
		securityInfo = append(securityInfo, map[string]interface{}{
			"type":        secType,
			"risk_level":  risk.RiskLevel,
			"description": risk.Description,
		})
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"security_types": securityInfo,
	})
}

// dnsCheckRequestBody is the wire body of POST /api/v1/network/dns/check:
// the legacy DNSCheckRequest fields plus the client-resolved canary results
// that drive hijack detection (resolution happens on the DEVICE, through its
// local resolver — the server only verifies the submitted answers).
type dnsCheckRequestBody struct {
	models.DNSCheckRequest
	ClientResolutions []services.ClientCanaryResolution `json:"client_resolutions,omitempty"`
	// LeakCanaryToken is the random token the CLIENT generated and resolved
	// as {token}.{canary zone} through its local resolver before this call
	// (zone discovery: GET /api/v1/network/dns/leak-config). The backend
	// looks the token up in the authoritative canary server's query log to
	// see which resolver IP actually performed the device's lookup.
	LeakCanaryToken string `json:"leak_canary_token,omitempty"`
}

// dnsCheckResponse extends the DNS check result with explicit statuses so a
// client can tell "checked and clean" apart from "check did not run".
type dnsCheckResponse struct {
	*models.DNSCheckResult
	HijackCheckStatus string `json:"hijack_check_status"`
	LeakCheckStatus   string `json:"leak_check_status"`
	// LeakObservation is set when LeakCheckStatus is "performed: ...".
	LeakObservation *services.DNSLeakObservation `json:"leak_observation,omitempty"`
	// LeakCanaryZone echoes the configured canary zone ("" when leak
	// detection is unavailable) so clients also discover it from check
	// responses, not only from GET /network/dns/leak-config.
	LeakCanaryZone string `json:"leak_canary_zone,omitempty"`
}

// CheckDNS handles POST /api/v1/network/dns/check
func (h *NetworkSecurityHandler) CheckDNS(w http.ResponseWriter, r *http.Request) {
	var req dnsCheckRequestBody
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.CurrentDNS == "" && len(req.ClientResolutions) == 0 {
		h.respondError(w, http.StatusBadRequest, "current_dns or client_resolutions is required")
		return
	}

	outcome, err := h.service.CheckDNS(r.Context(), &req.DNSCheckRequest, req.ClientResolutions, req.LeakCanaryToken)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to check DNS")
		h.respondError(w, http.StatusInternalServerError, "failed to check DNS")
		return
	}
	result := outcome.Result

	dnsRiskLevel := string(models.NetworkRiskLevelSafe)
	dnsRiskScore := 0.0
	if result.IsHijacked {
		dnsRiskLevel = string(models.NetworkRiskLevelCritical)
		dnsRiskScore = 0.9
	} else if !result.IsSecure {
		dnsRiskLevel = string(models.NetworkRiskLevelMedium)
		dnsRiskScore = 0.4
	}
	h.persistAudit(r.Context(), repository.NetworkAuditRecord{
		DeviceID:        h.auditDeviceID(r.Context(), req.DeviceID),
		AuditType:       "dns",
		NetworkIdentity: result.CurrentDNS,
		RiskLevel:       dnsRiskLevel,
		RiskScore:       dnsRiskScore,
		HijackDetected:  result.IsHijacked,
		Findings:        result,
	})

	h.respondJSON(w, http.StatusOK, dnsCheckResponse{
		DNSCheckResult:    result,
		HijackCheckStatus: outcome.HijackCheckStatus,
		LeakCheckStatus:   outcome.LeakCheckStatus,
		LeakObservation:   outcome.LeakObservation,
		LeakCanaryZone:    h.service.DNSLeakCanaryZone(),
	})
}

// GetDNSLeakConfig handles GET /api/v1/network/dns/leak-config.
//
// It tells the client whether real DNS leak detection is available and, if
// so, which controlled canary zone to use. The client then generates a
// crypto-random token, resolves {token}.{canary_zone} through its LOCAL
// resolver, and submits the token as leak_canary_token in
// POST /network/dns/check; the backend reports which resolver IP the
// authoritative canary server actually observed for that token.
func (h *NetworkSecurityHandler) GetDNSLeakConfig(w http.ResponseWriter, r *http.Request) {
	zone := h.service.DNSLeakCanaryZone()
	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"leak_check_available": zone != "",
		"canary_zone":          zone,
	})
}

// GetDNSProviders handles GET /api/v1/network/dns/providers
func (h *NetworkSecurityHandler) GetDNSProviders(w http.ResponseWriter, r *http.Request) {
	providers := make([]*models.DNSProvider, 0, len(models.KnownDNSProviders))
	for _, provider := range models.KnownDNSProviders {
		providers = append(providers, provider)
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"providers": providers,
		"count":     len(providers),
	})
}

// GetDNSProvider handles GET /api/v1/network/dns/providers/{ip}
func (h *NetworkSecurityHandler) GetDNSProvider(w http.ResponseWriter, r *http.Request) {
	ip := chi.URLParam(r, "ip")
	if ip == "" {
		h.respondError(w, http.StatusBadRequest, "ip is required")
		return
	}

	provider, ok := models.KnownDNSProviders[ip]
	if !ok {
		h.respondJSON(w, http.StatusOK, map[string]interface{}{
			"found":    false,
			"ip":       ip,
			"provider": nil,
		})
		return
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"found":    true,
		"ip":       ip,
		"provider": provider,
	})
}

// ConfigureDNS handles POST /api/v1/network/dns/configure
func (h *NetworkSecurityHandler) ConfigureDNS(w http.ResponseWriter, r *http.Request) {
	var req models.DNSConfig
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	// Validate provider
	if req.PrimaryDNS == "" {
		h.respondError(w, http.StatusBadRequest, "primary_dns is required")
		return
	}

	if h.repo == nil {
		h.respondError(w, http.StatusServiceUnavailable, "configuration persistence unavailable")
		return
	}

	deviceID := middleware.GetDeviceID(r.Context())
	if deviceID == "" {
		h.respondError(w, http.StatusBadRequest, "device identity required")
		return
	}

	if err := h.repo.UpsertDeviceDNSConfig(r.Context(), deviceID, &req); err != nil {
		h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to persist DNS configuration")
		h.respondError(w, http.StatusInternalServerError, "failed to save DNS configuration")
		return
	}

	// Return what was actually stored.
	stored, err := h.repo.GetDeviceNetworkConfig(r.Context(), deviceID)
	if err != nil || stored == nil || stored.DNS == nil {
		if err != nil {
			h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to read back DNS configuration")
		}
		h.respondError(w, http.StatusInternalServerError, "failed to read back DNS configuration")
		return
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"status":     "configured",
		"config":     stored.DNS,
		"updated_at": stored.UpdatedAt,
		"message":    "DNS configuration saved. Apply on device to take effect.",
	})
}

// CheckARPSpoofing handles POST /api/v1/network/arp/check
func (h *NetworkSecurityHandler) CheckARPSpoofing(w http.ResponseWriter, r *http.Request) {
	var req models.ARPSpoofCheckRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if len(req.ARPTable) == 0 {
		h.respondError(w, http.StatusBadRequest, "arp_table is required")
		return
	}

	result, err := h.service.CheckARPSpoofing(r.Context(), &req)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to check ARP spoofing")
		h.respondError(w, http.StatusInternalServerError, "failed to check ARP spoofing")
		return
	}

	h.respondJSON(w, http.StatusOK, result)
}

// CheckSSL handles POST /api/v1/network/ssl/check
func (h *NetworkSecurityHandler) CheckSSL(w http.ResponseWriter, r *http.Request) {
	var req models.SSLCheckRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.Host == "" {
		h.respondError(w, http.StatusBadRequest, "host is required")
		return
	}

	result, err := h.service.CheckSSL(r.Context(), &req)
	if err != nil {
		h.logger.Error().Err(err).Str("host", req.Host).Msg("failed to check SSL")
		h.respondError(w, http.StatusInternalServerError, "failed to check SSL")
		return
	}

	h.respondJSON(w, http.StatusOK, result)
}

// GetVPNRecommendation handles POST /api/v1/network/vpn/recommend
func (h *NetworkSecurityHandler) GetVPNRecommendation(w http.ResponseWriter, r *http.Request) {
	var req struct {
		WiFiAudit *models.WiFiAuditResult `json:"wifi_audit,omitempty"`
		DNSCheck  *models.DNSCheckResult  `json:"dns_check,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	recommendation := h.service.GetVPNRecommendation(r.Context(), req.WiFiAudit, req.DNSCheck)
	h.respondJSON(w, http.StatusOK, recommendation)
}

// GetVPNConfig handles GET /api/v1/network/vpn/config
func (h *NetworkSecurityHandler) GetVPNConfig(w http.ResponseWriter, r *http.Request) {
	// Return the device's stored configuration when one exists.
	if deviceID := middleware.GetDeviceID(r.Context()); deviceID != "" && h.repo != nil {
		stored, err := h.repo.GetDeviceNetworkConfig(r.Context(), deviceID)
		if err != nil {
			h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to load VPN configuration")
			h.respondError(w, http.StatusInternalServerError, "failed to load VPN configuration")
			return
		}
		if stored != nil && stored.VPN != nil {
			h.respondJSON(w, http.StatusOK, stored.VPN)
			return
		}
	}

	// No stored configuration: return the default VPN configuration for
	// OrbNet integration.
	config := models.VPNConfig{
		AutoConnect:         false,
		AutoConnectOnPublic: true,
		AutoConnectOnMobile: false,
		KillSwitch:          true,
		DNSProtection:       true,
		ThreatBlocking:      true,
		SplitTunneling:      false,
		PreferredProtocol:   "wireguard",
	}

	h.respondJSON(w, http.StatusOK, config)
}

// UpdateVPNConfig handles PUT /api/v1/network/vpn/config
func (h *NetworkSecurityHandler) UpdateVPNConfig(w http.ResponseWriter, r *http.Request) {
	var config models.VPNConfig
	if err := json.NewDecoder(r.Body).Decode(&config); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if h.repo == nil {
		h.respondError(w, http.StatusServiceUnavailable, "configuration persistence unavailable")
		return
	}

	deviceID := middleware.GetDeviceID(r.Context())
	if deviceID == "" {
		h.respondError(w, http.StatusBadRequest, "device identity required")
		return
	}

	if err := h.repo.UpsertDeviceVPNConfig(r.Context(), deviceID, &config); err != nil {
		h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to persist VPN configuration")
		h.respondError(w, http.StatusInternalServerError, "failed to save VPN configuration")
		return
	}

	stored, err := h.repo.GetDeviceNetworkConfig(r.Context(), deviceID)
	if err != nil || stored == nil || stored.VPN == nil {
		if err != nil {
			h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to read back VPN configuration")
		}
		h.respondError(w, http.StatusInternalServerError, "failed to read back VPN configuration")
		return
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"status":     "updated",
		"config":     stored.VPN,
		"updated_at": stored.UpdatedAt,
		"message":    "VPN configuration updated",
	})
}

// GetAttackTypes handles GET /api/v1/network/attacks/types
func (h *NetworkSecurityHandler) GetAttackTypes(w http.ResponseWriter, r *http.Request) {
	attacks := make([]map[string]interface{}, 0, len(models.NetworkAttackDescriptions))

	for attackType, info := range models.NetworkAttackDescriptions {
		attacks = append(attacks, map[string]interface{}{
			"type":        attackType,
			"title":       info.Title,
			"description": info.Description,
			"severity":    info.Severity,
			"mitigation":  info.Mitigation,
		})
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"attack_types": attacks,
		"count":        len(attacks),
	})
}

// GetStats handles GET /api/v1/network/stats. Stats are aggregated from the
// persisted per-device audit history: device-scoped for authenticated devices
// and global for service-to-service callers.
func (h *NetworkSecurityHandler) GetStats(w http.ResponseWriter, r *http.Request) {
	if h.repo == nil {
		h.respondError(w, http.StatusServiceUnavailable, "network stats unavailable: persistence not configured")
		return
	}

	deviceID := middleware.GetDeviceID(r.Context())
	if deviceID == "" && !middleware.IsServiceRequest(r.Context()) {
		h.respondError(w, http.StatusBadRequest, "device identity required")
		return
	}

	agg, err := h.repo.GetNetworkAuditStats(r.Context(), deviceID)
	if err != nil {
		h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to aggregate network stats")
		h.respondError(w, http.StatusInternalServerError, "failed to get stats")
		return
	}

	stats := &models.NetworkSecurityStats{
		TotalScans:         agg.TotalScans,
		WiFiAudits:         agg.WiFiAudits,
		DNSChecks:          agg.DNSChecks,
		AttacksDetected:    agg.AttacksDetected,
		RogueAPsDetected:   agg.RogueAPs,
		EvilTwinsDetected:  agg.EvilTwins,
		DNSHijacksDetected: agg.DNSHijacks,
		UnsecureNetworks:   agg.UnsecureNetworks,
		AttacksByType: map[string]int64{
			"rogue_ap":   agg.RogueAPs,
			"evil_twin":  agg.EvilTwins,
			"dns_hijack": agg.DNSHijacks,
		},
		Last24Hours: &models.NetworkStats24H{
			Scans:           agg.Last24hScans,
			AttacksDetected: agg.Last24hAttacks,
			RogueAPs:        agg.Last24hRogueAPs,
			EvilTwins:       agg.Last24hEvilTwins,
		},
	}

	h.respondJSON(w, http.StatusOK, stats)
}

// FullNetworkAudit handles POST /api/v1/network/audit/full
func (h *NetworkSecurityHandler) FullNetworkAudit(w http.ResponseWriter, r *http.Request) {
	var req struct {
		WiFi     *models.WiFiAuditRequest     `json:"wifi,omitempty"`
		DNS      *dnsCheckRequestBody         `json:"dns,omitempty"`
		ARP      *models.ARPSpoofCheckRequest `json:"arp,omitempty"`
		SSL      []models.SSLCheckRequest     `json:"ssl,omitempty"`
		DeviceID string                       `json:"device_id,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	result := map[string]interface{}{
		"device_id": req.DeviceID,
	}

	// Run Wi-Fi audit
	if req.WiFi != nil {
		wifiResult, err := h.service.AuditWiFi(r.Context(), req.WiFi)
		if err != nil {
			h.logger.Warn().Err(err).Msg("Wi-Fi audit failed")
		} else {
			result["wifi"] = wifiResult
		}
	}

	// Run DNS check (hijack detection driven by client-resolved canaries)
	if req.DNS != nil {
		dnsOutcome, err := h.service.CheckDNS(r.Context(), &req.DNS.DNSCheckRequest, req.DNS.ClientResolutions, req.DNS.LeakCanaryToken)
		if err != nil {
			h.logger.Warn().Err(err).Msg("DNS check failed")
		} else {
			result["dns"] = dnsOutcome.Result
			result["dns_hijack_check_status"] = dnsOutcome.HijackCheckStatus
			result["dns_leak_check_status"] = dnsOutcome.LeakCheckStatus
			if dnsOutcome.LeakObservation != nil {
				result["dns_leak_observation"] = dnsOutcome.LeakObservation
			}
		}
	}

	// Run ARP spoof check
	if req.ARP != nil {
		arpResult, err := h.service.CheckARPSpoofing(r.Context(), req.ARP)
		if err != nil {
			h.logger.Warn().Err(err).Msg("ARP check failed")
		} else {
			result["arp"] = arpResult
		}
	}

	// Run SSL checks
	if len(req.SSL) > 0 {
		sslResults := make([]*models.SSLCheckResult, 0, len(req.SSL))
		for _, sslReq := range req.SSL {
			sslResult, err := h.service.CheckSSL(r.Context(), &sslReq)
			if err != nil {
				h.logger.Warn().Err(err).Str("host", sslReq.Host).Msg("SSL check failed")
				continue
			}
			sslResults = append(sslResults, sslResult)
		}
		result["ssl"] = sslResults
	}

	// Calculate overall network risk
	overallRisk := h.calculateOverallRisk(result)
	result["overall_risk"] = overallRisk

	// Persist the completed full audit for stats aggregation.
	fullIdentity := ""
	rogueAPs := 0
	evilTwins := 0
	hijacked := false
	if wifi, ok := result["wifi"].(*models.WiFiAuditResult); ok {
		if wifi.Network != nil {
			fullIdentity = wifi.Network.SSID
			if fullIdentity == "" {
				fullIdentity = wifi.Network.BSSID
			}
		}
		rogueAPs = len(wifi.RogueAPDetected)
		evilTwins = len(wifi.EvilTwinDetected)
	}
	if dns, ok := result["dns"].(*models.DNSCheckResult); ok {
		hijacked = dns.IsHijacked
		if fullIdentity == "" {
			fullIdentity = dns.CurrentDNS
		}
	}
	riskScore, _ := overallRisk["risk_score"].(float64)
	riskLevel := ""
	if lvl, ok := overallRisk["risk_level"].(models.NetworkRiskLevel); ok {
		riskLevel = string(lvl)
	}
	h.persistAudit(r.Context(), repository.NetworkAuditRecord{
		DeviceID:        h.auditDeviceID(r.Context(), req.DeviceID),
		AuditType:       "full",
		NetworkIdentity: fullIdentity,
		RiskLevel:       riskLevel,
		RiskScore:       riskScore,
		RogueAPCount:    rogueAPs,
		EvilTwinCount:   evilTwins,
		HijackDetected:  hijacked,
		Findings:        result,
	})

	// Get VPN recommendation
	var wifiResult *models.WiFiAuditResult
	var dnsResult *models.DNSCheckResult
	if wifi, ok := result["wifi"].(*models.WiFiAuditResult); ok {
		wifiResult = wifi
	}
	if dns, ok := result["dns"].(*models.DNSCheckResult); ok {
		dnsResult = dns
	}
	result["vpn_recommendation"] = h.service.GetVPNRecommendation(r.Context(), wifiResult, dnsResult)

	h.respondJSON(w, http.StatusOK, result)
}

func (h *NetworkSecurityHandler) calculateOverallRisk(result map[string]interface{}) map[string]interface{} {
	riskScore := 0.0
	riskLevel := models.NetworkRiskLevelSafe

	// Check Wi-Fi risk
	if wifi, ok := result["wifi"].(*models.WiFiAuditResult); ok {
		riskScore += wifi.RiskScore * 0.4
		if wifi.RiskLevel > riskLevel {
			riskLevel = wifi.RiskLevel
		}
	}

	// Check DNS risk
	if dns, ok := result["dns"].(*models.DNSCheckResult); ok {
		if dns.IsHijacked {
			riskScore += 0.4
			riskLevel = models.NetworkRiskLevelCritical
		} else if !dns.IsSecure {
			riskScore += 0.2
		}
	}

	// Check ARP risk
	if arp, ok := result["arp"].(*models.ARPSpoofCheckResult); ok {
		if arp.IsSpoofDetected {
			riskScore += 0.3
			riskLevel = models.NetworkRiskLevelCritical
		}
	}

	// Check SSL risks
	if sslResults, ok := result["ssl"].([]*models.SSLCheckResult); ok {
		for _, ssl := range sslResults {
			if !ssl.IsSecure {
				riskScore += 0.1
			}
		}
	}

	// Normalize
	if riskScore > 1.0 {
		riskScore = 1.0
	}

	return map[string]interface{}{
		"risk_score": riskScore,
		"risk_level": riskLevel,
	}
}

// ---------------------------------------------------------------------------
// Rogue-AP scan + trusted access points
// ---------------------------------------------------------------------------

// rogueAPScanAP is one access point in a rogue-AP scan request. Both
// signal_strength and signal_level are accepted; security may be a plain type
// name ("WPA2") or an Android capabilities string ("[WPA2-PSK-CCMP][ESS]").
type rogueAPScanAP struct {
	SSID           string `json:"ssid"`
	BSSID          string `json:"bssid"`
	SignalStrength *int   `json:"signal_strength,omitempty"`
	SignalLevel    *int   `json:"signal_level,omitempty"`
	Channel        int    `json:"channel"`
	Security       string `json:"security"`
	SecurityType   string `json:"security_type"`
	Frequency      int    `json:"frequency"`
	Capabilities   string `json:"capabilities"`
	IsConnected    bool   `json:"is_connected"`
	IsHidden       bool   `json:"is_hidden"`
}

// rogueAPScanRequest is the body of POST /network/rogue-ap/scan.
type rogueAPScanRequest struct {
	AccessPoints   []rogueAPScanAP `json:"access_points"`
	CurrentNetwork *rogueAPScanAP  `json:"current_network,omitempty"`
	DeviceID       string          `json:"device_id,omitempty"`
}

// toWiFiNetwork converts a scan-request AP to the domain model.
func (ap *rogueAPScanAP) toWiFiNetwork() models.WiFiNetwork {
	signal := -100
	if ap.SignalStrength != nil {
		signal = *ap.SignalStrength
	} else if ap.SignalLevel != nil {
		signal = *ap.SignalLevel
	}

	security := ap.Security
	if security == "" {
		security = ap.SecurityType
	}
	if security == "" {
		security = ap.Capabilities
	}

	return models.WiFiNetwork{
		SSID:         ap.SSID,
		BSSID:        ap.BSSID,
		SecurityType: parseWiFiSecurityType(security),
		SignalLevel:  signal,
		Frequency:    ap.Frequency,
		Channel:      ap.Channel,
		IsConnected:  ap.IsConnected,
		IsHidden:     ap.IsHidden,
		Capabilities: ap.Capabilities,
	}
}

// parseWiFiSecurityType normalizes a security descriptor into a
// models.WiFiSecurityType. Order matters: WPA3 before WPA2 before WPA.
func parseWiFiSecurityType(raw string) models.WiFiSecurityType {
	s := strings.ToLower(strings.TrimSpace(raw))
	switch {
	case s == "":
		return models.WiFiSecurityUnknown
	case strings.Contains(s, "wpa3") || strings.Contains(s, "sae"):
		return models.WiFiSecurityWPA3
	case strings.Contains(s, "wpa2") || strings.Contains(s, "rsn"):
		return models.WiFiSecurityWPA2
	case strings.Contains(s, "wpa"):
		return models.WiFiSecurityWPA
	case strings.Contains(s, "wep"):
		return models.WiFiSecurityWEP
	case s == "open" || s == "none" || s == "[ess]" || s == "ess":
		return models.WiFiSecurityOpen
	default:
		return models.WiFiSecurityUnknown
	}
}

// trustedAPKeys builds lookup sets for trusted-AP suppression: exact
// (ssid, bssid) pairs and bare BSSIDs.
func trustedAPKeys(trusted []repository.TrustedAP) (pairs map[string]bool, bssids map[string]bool) {
	pairs = make(map[string]bool, len(trusted))
	bssids = make(map[string]bool, len(trusted))
	for _, t := range trusted {
		pairs[strings.ToLower(t.SSID)+"|"+strings.ToLower(t.BSSID)] = true
		if t.BSSID != "" {
			bssids[strings.ToLower(t.BSSID)] = true
		}
	}
	return pairs, bssids
}

func isTrustedAP(ssid, bssid string, pairs, bssids map[string]bool) bool {
	if len(pairs) == 0 && len(bssids) == 0 {
		return false
	}
	if bssids[strings.ToLower(bssid)] {
		return true
	}
	return pairs[strings.ToLower(ssid)+"|"+strings.ToLower(bssid)]
}

// recalculateWiFiRisk mirrors the service risk formula so the score stays
// consistent after trusted-AP findings are suppressed: security issues weigh
// 0.4/0.25/0.15/0.05 by severity, each rogue AP adds 0.2, each evil twin 0.3.
func recalculateWiFiRisk(result *models.WiFiAuditResult) {
	score := 0.0
	for _, issue := range result.SecurityIssues {
		switch issue.Severity {
		case models.NetworkRiskLevelCritical:
			score += 0.4
		case models.NetworkRiskLevelHigh:
			score += 0.25
		case models.NetworkRiskLevelMedium:
			score += 0.15
		case models.NetworkRiskLevelLow:
			score += 0.05
		}
	}
	score += float64(len(result.RogueAPDetected)) * 0.2
	score += float64(len(result.EvilTwinDetected)) * 0.3
	if score > 1.0 {
		score = 1.0
	}

	var level models.NetworkRiskLevel
	switch {
	case score >= 0.8:
		level = models.NetworkRiskLevelCritical
	case score >= 0.6:
		level = models.NetworkRiskLevelHigh
	case score >= 0.4:
		level = models.NetworkRiskLevelMedium
	case score >= 0.2:
		level = models.NetworkRiskLevelLow
	default:
		level = models.NetworkRiskLevelSafe
	}

	result.RiskScore = score
	result.RiskLevel = level
}

// ScanRogueAPs handles POST /api/v1/network/rogue-ap/scan. It runs the
// rogue-AP / evil-twin detection over the submitted access points, suppresses
// findings for the device's trusted APs, and returns a per-AP threat
// assessment alongside the raw alerts.
func (h *NetworkSecurityHandler) ScanRogueAPs(w http.ResponseWriter, r *http.Request) {
	var req rogueAPScanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if len(req.AccessPoints) == 0 && req.CurrentNetwork == nil {
		h.respondError(w, http.StatusBadRequest, "access_points is required")
		return
	}

	nearby := make([]models.WiFiNetwork, 0, len(req.AccessPoints))
	var current *models.WiFiNetwork
	for i := range req.AccessPoints {
		network := req.AccessPoints[i].toWiFiNetwork()
		nearby = append(nearby, network)
		if current == nil && network.IsConnected {
			n := network
			current = &n
		}
	}
	if req.CurrentNetwork != nil {
		n := req.CurrentNetwork.toWiFiNetwork()
		n.IsConnected = true
		current = &n
	}

	deviceID := h.auditDeviceID(r.Context(), req.DeviceID)

	result, err := h.service.AuditWiFi(r.Context(), &models.WiFiAuditRequest{
		CurrentNetwork: current,
		NearbyNetworks: nearby,
		DeviceID:       deviceID,
	})
	if err != nil {
		h.logger.Error().Err(err).Msg("rogue-AP scan failed")
		h.respondError(w, http.StatusInternalServerError, "rogue-AP scan failed")
		return
	}

	// Suppress findings against the device's trusted APs.
	var trustedPairs, trustedBSSIDs map[string]bool
	suppressed := 0
	if authDeviceID := middleware.GetDeviceID(r.Context()); authDeviceID != "" && h.rogueRepo != nil {
		trusted, err := h.rogueRepo.ListTrustedAPs(r.Context(), authDeviceID)
		if err != nil {
			h.logger.Error().Err(err).Str("device_id", authDeviceID).Msg("failed to load trusted APs for scan suppression")
		} else {
			trustedPairs, trustedBSSIDs = trustedAPKeys(trusted)
		}
	}
	if len(trustedPairs) > 0 || len(trustedBSSIDs) > 0 {
		keptRogue := result.RogueAPDetected[:0]
		for _, alert := range result.RogueAPDetected {
			if isTrustedAP(alert.SSID, alert.BSSID, trustedPairs, trustedBSSIDs) {
				suppressed++
				continue
			}
			keptRogue = append(keptRogue, alert)
		}
		result.RogueAPDetected = keptRogue

		keptTwins := result.EvilTwinDetected[:0]
		for _, alert := range result.EvilTwinDetected {
			if isTrustedAP(alert.SSID, alert.EvilBSSID, trustedPairs, trustedBSSIDs) {
				suppressed++
				continue
			}
			keptTwins = append(keptTwins, alert)
		}
		result.EvilTwinDetected = keptTwins

		if suppressed > 0 {
			recalculateWiFiRisk(result)
		}
	}

	// Index alerts by offending BSSID for the per-AP assessment.
	rogueByBSSID := make(map[string]models.RogueAPAlert, len(result.RogueAPDetected))
	for _, alert := range result.RogueAPDetected {
		rogueByBSSID[strings.ToLower(alert.BSSID)] = alert
	}
	twinByBSSID := make(map[string]models.EvilTwinAlert, len(result.EvilTwinDetected))
	for _, alert := range result.EvilTwinDetected {
		twinByBSSID[strings.ToLower(alert.EvilBSSID)] = alert
	}

	accessPoints := make([]map[string]interface{}, 0, len(nearby))
	for _, network := range nearby {
		threats := make([]string, 0, 2)
		threatLevel := "safe"
		trusted := isTrustedAP(network.SSID, network.BSSID, trustedPairs, trustedBSSIDs)

		if !trusted {
			key := strings.ToLower(network.BSSID)
			if _, ok := twinByBSSID[key]; ok {
				threats = append(threats, "evil_twin")
				threatLevel = "dangerous"
			}
			if alert, ok := rogueByBSSID[key]; ok {
				if strings.Contains(alert.Reason, "impersonate") {
					threats = append(threats, "suspicious_ssid")
				} else {
					threats = append(threats, "evil_twin")
				}
				threatLevel = "dangerous"
			}
			switch network.SecurityType {
			case models.WiFiSecurityOpen:
				threats = append(threats, "open_network")
				if threatLevel == "safe" {
					threatLevel = "caution"
				}
			case models.WiFiSecurityWEP, models.WiFiSecurityWPA:
				threats = append(threats, "weak_encryption")
				if threatLevel == "safe" {
					threatLevel = "caution"
				}
			}
		}

		id := network.BSSID
		if id == "" {
			id = network.SSID
		}

		accessPoints = append(accessPoints, map[string]interface{}{
			"id":              id,
			"ssid":            network.SSID,
			"bssid":           network.BSSID,
			"signal_strength": network.SignalLevel,
			"security":        string(network.SecurityType),
			"channel":         network.Channel,
			"frequency":       network.Frequency,
			"is_connected":    network.IsConnected,
			"is_trusted":      trusted,
			"threat_level":    threatLevel,
			"threats":         threats,
		})
	}

	// Persist the scan outcome for the threat feed and stats aggregation.
	identity := ""
	if current != nil {
		identity = current.SSID
		if identity == "" {
			identity = current.BSSID
		}
	}
	h.persistAudit(r.Context(), repository.NetworkAuditRecord{
		DeviceID:        deviceID,
		AuditType:       "rogue_ap",
		NetworkIdentity: identity,
		RiskLevel:       string(result.RiskLevel),
		RiskScore:       result.RiskScore,
		RogueAPCount:    len(result.RogueAPDetected),
		EvilTwinCount:   len(result.EvilTwinDetected),
		Findings:        result,
	})

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"access_points":       accessPoints,
		"count":               len(accessPoints),
		"rogue_aps":           result.RogueAPDetected,
		"evil_twins":          result.EvilTwinDetected,
		"security_issues":     result.SecurityIssues,
		"recommendations":     result.Recommendations,
		"risk_level":          result.RiskLevel,
		"risk_score":          result.RiskScore,
		"suppressed_by_trust": suppressed,
		"scanned_at":          result.AuditedAt,
	})
}

// GetTrustedAPs handles GET /api/v1/network/rogue-ap/trusted.
func (h *NetworkSecurityHandler) GetTrustedAPs(w http.ResponseWriter, r *http.Request) {
	if h.rogueRepo == nil {
		h.respondError(w, http.StatusServiceUnavailable, "trusted AP persistence unavailable")
		return
	}
	deviceID := middleware.GetDeviceID(r.Context())
	if deviceID == "" {
		h.respondError(w, http.StatusBadRequest, "device identity required")
		return
	}

	trusted, err := h.rogueRepo.ListTrustedAPs(r.Context(), deviceID)
	if err != nil {
		h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to list trusted APs")
		h.respondError(w, http.StatusInternalServerError, "failed to list trusted APs")
		return
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"trusted_aps": trusted,
		"count":       len(trusted),
	})
}

// AddTrustedAP handles POST /api/v1/network/rogue-ap/trusted.
func (h *NetworkSecurityHandler) AddTrustedAP(w http.ResponseWriter, r *http.Request) {
	if h.rogueRepo == nil {
		h.respondError(w, http.StatusServiceUnavailable, "trusted AP persistence unavailable")
		return
	}
	deviceID := middleware.GetDeviceID(r.Context())
	if deviceID == "" {
		h.respondError(w, http.StatusBadRequest, "device identity required")
		return
	}

	var req struct {
		SSID  string `json:"ssid"`
		BSSID string `json:"bssid"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	req.SSID = strings.TrimSpace(req.SSID)
	req.BSSID = strings.TrimSpace(req.BSSID)
	if req.SSID == "" && req.BSSID == "" {
		h.respondError(w, http.StatusBadRequest, "ssid or bssid is required")
		return
	}

	ap, err := h.rogueRepo.AddTrustedAP(r.Context(), deviceID, req.SSID, req.BSSID)
	if err != nil {
		h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to add trusted AP")
		h.respondError(w, http.StatusInternalServerError, "failed to add trusted AP")
		return
	}

	h.respondJSON(w, http.StatusCreated, ap)
}

// RemoveTrustedAP handles DELETE /api/v1/network/rogue-ap/trusted/{id}.
func (h *NetworkSecurityHandler) RemoveTrustedAP(w http.ResponseWriter, r *http.Request) {
	if h.rogueRepo == nil {
		h.respondError(w, http.StatusServiceUnavailable, "trusted AP persistence unavailable")
		return
	}
	deviceID := middleware.GetDeviceID(r.Context())
	if deviceID == "" {
		h.respondError(w, http.StatusBadRequest, "device identity required")
		return
	}

	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid trusted AP ID")
		return
	}

	deleted, err := h.rogueRepo.DeleteTrustedAP(r.Context(), deviceID, id)
	if err != nil {
		h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to remove trusted AP")
		h.respondError(w, http.StatusInternalServerError, "failed to remove trusted AP")
		return
	}
	if !deleted {
		h.respondError(w, http.StatusNotFound, "trusted AP not found")
		return
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"status": "deleted",
		"id":     id,
	})
}

// ---------------------------------------------------------------------------
// Network threats feed (persisted audit findings)
// ---------------------------------------------------------------------------

// storedWiFiFindings is the subset of a persisted Wi-Fi/rogue-AP audit
// findings document needed to derive threat entries.
type storedWiFiFindings struct {
	RogueAPDetected  []models.RogueAPAlert      `json:"rogue_ap_detected"`
	EvilTwinDetected []models.EvilTwinAlert     `json:"evil_twin_detected"`
	SecurityIssues   []models.WiFiSecurityIssue `json:"security_issues"`
}

// storedDNSFindings is the subset of a persisted DNS audit findings document
// needed to derive threat entries.
type storedDNSFindings struct {
	CurrentDNS string `json:"current_dns"`
	IsHijacked bool   `json:"is_hijacked"`
}

// storedFullFindings is the shape persisted by full audits, nesting the Wi-Fi
// and DNS results.
type storedFullFindings struct {
	WiFi *storedWiFiFindings `json:"wifi"`
	DNS  *storedDNSFindings  `json:"dns"`
}

// appendWiFiThreats converts persisted Wi-Fi findings into threat entries.
func appendWiFiThreats(threats []map[string]interface{}, row repository.ThreatAuditRow, findings *storedWiFiFindings) []map[string]interface{} {
	network := row.NetworkIdentity
	for i, alert := range findings.RogueAPDetected {
		detectedAt := alert.DetectedAt
		if detectedAt.IsZero() {
			detectedAt = row.AuditedAt
		}
		net := alert.SSID
		if net == "" {
			net = network
		}
		threats = append(threats, map[string]interface{}{
			"id":          fmt.Sprintf("%s:rogue_ap:%d", row.ID, i),
			"type":        "rogue_ap",
			"severity":    string(alert.RiskLevel),
			"description": alert.Reason,
			"network":     net,
			"detected_at": detectedAt,
		})
	}
	for i, alert := range findings.EvilTwinDetected {
		detectedAt := alert.DetectedAt
		if detectedAt.IsZero() {
			detectedAt = row.AuditedAt
		}
		net := alert.SSID
		if net == "" {
			net = network
		}
		threats = append(threats, map[string]interface{}{
			"id":          fmt.Sprintf("%s:evil_twin:%d", row.ID, i),
			"type":        "evil_twin",
			"severity":    string(alert.RiskLevel),
			"description": alert.Description,
			"network":     net,
			"detected_at": detectedAt,
		})
	}
	for i, issue := range findings.SecurityIssues {
		if issue.Severity != models.NetworkRiskLevelHigh && issue.Severity != models.NetworkRiskLevelCritical {
			continue
		}
		threats = append(threats, map[string]interface{}{
			"id":          fmt.Sprintf("%s:%s:%d", row.ID, issue.Type, i),
			"type":        issue.Type,
			"severity":    string(issue.Severity),
			"description": issue.Description,
			"network":     network,
			"detected_at": row.AuditedAt,
		})
	}
	return threats
}

// appendDNSThreats converts persisted DNS findings into threat entries.
func appendDNSThreats(threats []map[string]interface{}, row repository.ThreatAuditRow, findings *storedDNSFindings) []map[string]interface{} {
	if findings == nil || !findings.IsHijacked {
		return threats
	}
	network := findings.CurrentDNS
	if network == "" {
		network = row.NetworkIdentity
	}
	return append(threats, map[string]interface{}{
		"id":          fmt.Sprintf("%s:dns_hijack", row.ID),
		"type":        "dns_hijack",
		"severity":    string(models.NetworkRiskLevelCritical),
		"description": fmt.Sprintf("DNS hijacking detected: device DNS resolves through %s", network),
		"network":     network,
		"detected_at": row.AuditedAt,
	})
}

// GetNetworkThreats handles GET /api/v1/network/threats. Threats are derived
// from the persisted per-device audit findings (orbguard_lab.network_audits):
// device-scoped for authenticated devices and global for service callers.
func (h *NetworkSecurityHandler) GetNetworkThreats(w http.ResponseWriter, r *http.Request) {
	if h.rogueRepo == nil {
		h.respondError(w, http.StatusServiceUnavailable, "network threats unavailable: persistence not configured")
		return
	}

	deviceID := middleware.GetDeviceID(r.Context())
	if deviceID == "" && !middleware.IsServiceRequest(r.Context()) {
		h.respondError(w, http.StatusBadRequest, "device identity required")
		return
	}

	rows, err := h.rogueRepo.ListThreatAudits(r.Context(), deviceID, 200)
	if err != nil {
		h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to load network threat audits")
		h.respondError(w, http.StatusInternalServerError, "failed to load network threats")
		return
	}

	threats := make([]map[string]interface{}, 0, len(rows))
	for _, row := range rows {
		if len(row.Findings) == 0 {
			// Audit rows persisted without a findings document still carry the
			// scalar threat flags; surface DNS hijacks recorded that way.
			if row.HijackDetected {
				threats = appendDNSThreats(threats, row, &storedDNSFindings{
					CurrentDNS: row.NetworkIdentity,
					IsHijacked: true,
				})
			}
			continue
		}

		switch row.AuditType {
		case "wifi", "rogue_ap":
			var findings storedWiFiFindings
			if err := json.Unmarshal(row.Findings, &findings); err != nil {
				h.logger.Warn().Err(err).Str("audit_id", row.ID.String()).Msg("failed to decode wifi audit findings")
				continue
			}
			threats = appendWiFiThreats(threats, row, &findings)
		case "dns":
			var findings storedDNSFindings
			if err := json.Unmarshal(row.Findings, &findings); err != nil {
				h.logger.Warn().Err(err).Str("audit_id", row.ID.String()).Msg("failed to decode dns audit findings")
				continue
			}
			threats = appendDNSThreats(threats, row, &findings)
		case "full":
			var findings storedFullFindings
			if err := json.Unmarshal(row.Findings, &findings); err != nil {
				h.logger.Warn().Err(err).Str("audit_id", row.ID.String()).Msg("failed to decode full audit findings")
				continue
			}
			if findings.WiFi != nil {
				threats = appendWiFiThreats(threats, row, findings.WiFi)
			}
			threats = appendDNSThreats(threats, row, findings.DNS)
		}
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"threats": threats,
		"count":   len(threats),
	})
}

func (h *NetworkSecurityHandler) respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func (h *NetworkSecurityHandler) respondError(w http.ResponseWriter, status int, message string) {
	h.respondJSON(w, status, map[string]string{"error": message})
}
