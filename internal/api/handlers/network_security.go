package handlers

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// NetworkSecurityHandler handles network security API requests
type NetworkSecurityHandler struct {
	service *services.NetworkSecurityService
	repo    *repository.NetworkSecurityRepository
	logger  *logger.Logger
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

// CheckDNS handles POST /api/v1/network/dns/check
func (h *NetworkSecurityHandler) CheckDNS(w http.ResponseWriter, r *http.Request) {
	var req models.DNSCheckRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.CurrentDNS == "" {
		h.respondError(w, http.StatusBadRequest, "current_dns is required")
		return
	}

	result, err := h.service.CheckDNS(r.Context(), &req)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to check DNS")
		h.respondError(w, http.StatusInternalServerError, "failed to check DNS")
		return
	}

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

	h.respondJSON(w, http.StatusOK, result)
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
		DNS      *models.DNSCheckRequest      `json:"dns,omitempty"`
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

	// Run DNS check
	if req.DNS != nil {
		dnsResult, err := h.service.CheckDNS(r.Context(), req.DNS)
		if err != nil {
			h.logger.Warn().Err(err).Msg("DNS check failed")
		} else {
			result["dns"] = dnsResult
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

func (h *NetworkSecurityHandler) respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func (h *NetworkSecurityHandler) respondError(w http.ResponseWriter, status int, message string) {
	h.respondJSON(w, status, map[string]string{"error": message})
}
