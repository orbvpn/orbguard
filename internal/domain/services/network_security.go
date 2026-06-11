package services

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"orbguard-lab/internal/dnscanary"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// gatewayBaseline records the gateway MAC observed by a specific device for a
// specific gateway IP. Baselines are scoped per device because gateway IPs are
// not globally unique: nearly every home router is 192.168.1.1, so a global
// IP -> MAC map would compare gateways across unrelated users and raise false
// CRITICAL "ARP spoofing" alerts.
type gatewayBaseline struct {
	GatewayMAC string    `json:"gateway_mac"`
	FirstSeen  time.Time `json:"first_seen"`
	LastSeen   time.Time `json:"last_seen"`
}

const (
	// gatewayBaselineKeyPrefix is the Redis key prefix for persisted gateway baselines.
	gatewayBaselineKeyPrefix = "network:gateway-baseline:"
	// gatewayBaselineTTL bounds how long a gateway baseline is remembered.
	// A legitimate router replacement stops alerting once the old baseline expires.
	gatewayBaselineTTL = 30 * 24 * time.Hour
)

// NetworkSecurityService handles network security analysis
type NetworkSecurityService struct {
	repos            *repository.Repositories
	cache            *cache.RedisCache
	logger           *logger.Logger
	gatewayBaselines map[string]gatewayBaseline // L1: "deviceID|gatewayIP" -> baseline (L2 persisted in Redis)
	gatewaysMu       sync.RWMutex

	// DNS leak-check canary (set once at startup via ConfigureDNSLeakCanary;
	// both stay zero-valued when no canary zone is deployed, in which case
	// the leak check is reported explicitly unavailable).
	dnsLeakCanaryZone  string
	dnsLeakCanaryStore DNSCanaryQueryStore
}

// DNSCanaryQueryStore looks up canary queries observed by the authoritative
// canary DNS server (cmd/dnscanary). Implemented by *dnscanary.Store.
type DNSCanaryQueryStore interface {
	LookupToken(ctx context.Context, token string) ([]dnscanary.ObservedQuery, error)
}

// NewNetworkSecurityService creates a new network security service
func NewNetworkSecurityService(repos *repository.Repositories, cache *cache.RedisCache, log *logger.Logger) *NetworkSecurityService {
	return &NetworkSecurityService{
		repos:            repos,
		cache:            cache,
		logger:           log.WithComponent("network-security"),
		gatewayBaselines: make(map[string]gatewayBaseline),
	}
}

// ConfigureDNSLeakCanary enables real DNS leak detection against a
// controlled canary zone. zone is the NS-delegated domain served by the
// authoritative responder in cmd/dnscanary; store reads the query log that
// responder writes. Must be called during startup wiring, before the service
// handles requests.
func (s *NetworkSecurityService) ConfigureDNSLeakCanary(zone string, store DNSCanaryQueryStore) {
	s.dnsLeakCanaryZone = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(zone)), ".")
	s.dnsLeakCanaryStore = store
}

// DNSLeakCanaryZone returns the configured canary zone ("" when leak
// detection is unavailable). Clients resolve {token}.{zone} through their
// local resolver before submitting the token to CheckDNS.
func (s *NetworkSecurityService) DNSLeakCanaryZone() string {
	if s.dnsLeakCanaryStore == nil {
		return ""
	}
	return s.dnsLeakCanaryZone
}

func gatewayBaselineCacheKey(deviceID, gatewayIP string) string {
	return gatewayBaselineKeyPrefix + deviceID + ":" + gatewayIP
}

// loadGatewayBaseline returns the recorded gateway baseline for a device,
// checking the in-process map first and falling back to Redis so baselines
// survive process restarts.
func (s *NetworkSecurityService) loadGatewayBaseline(ctx context.Context, deviceID, gatewayIP string) (gatewayBaseline, bool) {
	l1Key := deviceID + "|" + gatewayIP

	s.gatewaysMu.RLock()
	baseline, ok := s.gatewayBaselines[l1Key]
	s.gatewaysMu.RUnlock()
	if ok {
		return baseline, true
	}

	if s.cache == nil {
		return gatewayBaseline{}, false
	}

	var cached gatewayBaseline
	if err := s.cache.GetJSON(ctx, gatewayBaselineCacheKey(deviceID, gatewayIP), &cached); err != nil {
		if !errors.Is(err, redis.Nil) {
			s.logger.Warn().Err(err).
				Str("device_id", deviceID).
				Str("gateway_ip", gatewayIP).
				Msg("failed to load gateway baseline from cache")
		}
		return gatewayBaseline{}, false
	}

	s.gatewaysMu.Lock()
	s.gatewayBaselines[l1Key] = cached
	s.gatewaysMu.Unlock()

	return cached, true
}

// storeGatewayBaseline persists a gateway baseline to the in-process map and Redis.
func (s *NetworkSecurityService) storeGatewayBaseline(ctx context.Context, deviceID, gatewayIP string, baseline gatewayBaseline) {
	s.gatewaysMu.Lock()
	s.gatewayBaselines[deviceID+"|"+gatewayIP] = baseline
	s.gatewaysMu.Unlock()

	if s.cache == nil {
		return
	}

	if err := s.cache.SetJSON(ctx, gatewayBaselineCacheKey(deviceID, gatewayIP), baseline, gatewayBaselineTTL); err != nil {
		s.logger.Warn().Err(err).
			Str("device_id", deviceID).
			Str("gateway_ip", gatewayIP).
			Msg("failed to persist gateway baseline to cache")
	}
}

// AuditWiFi performs a comprehensive Wi-Fi security audit
func (s *NetworkSecurityService) AuditWiFi(ctx context.Context, req *models.WiFiAuditRequest) (*models.WiFiAuditResult, error) {
	result := &models.WiFiAuditResult{
		ID:               uuid.New(),
		Network:          req.CurrentNetwork,
		SecurityIssues:   make([]models.WiFiSecurityIssue, 0),
		RogueAPDetected:  make([]models.RogueAPAlert, 0),
		EvilTwinDetected: make([]models.EvilTwinAlert, 0),
		Recommendations:  make([]models.NetworkRecommendation, 0),
		AuditedAt:        time.Now(),
	}

	// Check current network security
	if req.CurrentNetwork != nil {
		s.auditNetworkSecurity(result, req.CurrentNetwork)
	}

	// Check for rogue APs
	if len(req.NearbyNetworks) > 0 {
		s.detectRogueAPs(result, req.NearbyNetworks)
	}

	// Check for evil twin attacks
	if req.CurrentNetwork != nil && len(req.NearbyNetworks) > 0 {
		s.detectEvilTwin(result, req.CurrentNetwork, req.NearbyNetworks)
	}

	// Calculate overall risk
	result.RiskScore, result.RiskLevel = s.calculateWiFiRisk(result)

	// Generate recommendations
	s.generateWiFiRecommendations(result)

	s.logger.Info().
		Str("ssid", s.getSSID(req.CurrentNetwork)).
		Str("risk_level", string(result.RiskLevel)).
		Float64("risk_score", result.RiskScore).
		Int("issues", len(result.SecurityIssues)).
		Msg("Wi-Fi audit completed")

	return result, nil
}

func (s *NetworkSecurityService) getSSID(network *models.WiFiNetwork) string {
	if network == nil {
		return "unknown"
	}
	return network.SSID
}

func (s *NetworkSecurityService) auditNetworkSecurity(result *models.WiFiAuditResult, network *models.WiFiNetwork) {
	// Check security type
	if secRisk, ok := models.WiFiSecurityRisks[network.SecurityType]; ok {
		if secRisk.RiskLevel == models.NetworkRiskLevelCritical || secRisk.RiskLevel == models.NetworkRiskLevelHigh {
			result.SecurityIssues = append(result.SecurityIssues, models.WiFiSecurityIssue{
				Type:        "weak_encryption",
				Severity:    secRisk.RiskLevel,
				Title:       fmt.Sprintf("Weak Wi-Fi Security: %s", network.SecurityType),
				Description: secRisk.Description,
				Mitigation:  s.getSecurityMitigation(network.SecurityType),
			})
		}
	}

	// Check for hidden SSID (can indicate rogue AP)
	if network.IsHidden {
		result.SecurityIssues = append(result.SecurityIssues, models.WiFiSecurityIssue{
			Type:        "hidden_ssid",
			Severity:    models.NetworkRiskLevelLow,
			Title:       "Hidden Network SSID",
			Description: "This network hides its SSID. While sometimes used for security, this can also indicate a rogue access point.",
			Mitigation:  "Verify this is a known trusted network before using",
		})
	}

	// Check for common vulnerable SSID names
	vulnerableSSIDs := []string{"Free WiFi", "FREE_WIFI", "Public WiFi", "Guest", "Airport", "Hotel", "Starbucks"}
	ssidUpper := strings.ToUpper(network.SSID)
	for _, vulnSSID := range vulnerableSSIDs {
		if strings.Contains(ssidUpper, strings.ToUpper(vulnSSID)) {
			result.SecurityIssues = append(result.SecurityIssues, models.WiFiSecurityIssue{
				Type:        "public_network",
				Severity:    models.NetworkRiskLevelMedium,
				Title:       "Public Wi-Fi Network",
				Description: "This appears to be a public Wi-Fi network. Public networks are common targets for attackers.",
				Mitigation:  "Use VPN when connected to public Wi-Fi, avoid sensitive transactions",
			})
			break
		}
	}
}

func (s *NetworkSecurityService) getSecurityMitigation(secType models.WiFiSecurityType) string {
	switch secType {
	case models.WiFiSecurityOpen:
		return "Use VPN immediately. Do not transmit sensitive data. Consider using mobile data instead."
	case models.WiFiSecurityWEP:
		return "Upgrade to WPA2 or WPA3 if this is your network. Use VPN if connecting."
	case models.WiFiSecurityWPA:
		return "Upgrade to WPA2 or WPA3 for better security."
	default:
		return "Keep your device and router firmware updated."
	}
}

func (s *NetworkSecurityService) detectRogueAPs(result *models.WiFiAuditResult, networks []models.WiFiNetwork) {
	// Group networks by SSID
	ssidGroups := make(map[string][]models.WiFiNetwork)
	for _, network := range networks {
		ssidGroups[network.SSID] = append(ssidGroups[network.SSID], network)
	}

	// Check for suspicious patterns
	for ssid, nets := range ssidGroups {
		if len(nets) > 1 {
			// Multiple APs with same SSID - check for inconsistencies
			for i := 1; i < len(nets); i++ {
				if nets[i].SecurityType != nets[0].SecurityType {
					// Different security types for same SSID - suspicious
					result.RogueAPDetected = append(result.RogueAPDetected, models.RogueAPAlert{
						SSID:              ssid,
						BSSID:             nets[i].BSSID,
						SignalStrength:    nets[i].SignalLevel,
						SecurityType:      nets[i].SecurityType,
						RiskLevel:         models.NetworkRiskLevelHigh,
						Reason:            fmt.Sprintf("Same SSID '%s' but different security type than other APs", ssid),
						LegitimateNetwork: &nets[0],
						DetectedAt:        time.Now(),
					})
				}
			}
		}

		// Check for SSIDs that impersonate known networks
		s.checkSSIDImpersonation(result, ssid, nets)
	}
}

func (s *NetworkSecurityService) checkSSIDImpersonation(result *models.WiFiAuditResult, ssid string, networks []models.WiFiNetwork) {
	// Known legitimate SSIDs that are commonly impersonated
	knownSSIDs := map[string]bool{
		"attwifi":              true,
		"xfinitywifi":          true,
		"Starbucks WiFi":       true,
		"Google Starbucks":     true,
		"McDonald's Free WiFi": true,
	}

	// Check for typosquatting
	ssidLower := strings.ToLower(ssid)
	for known := range knownSSIDs {
		knownLower := strings.ToLower(known)
		if ssidLower != knownLower && s.isSimilar(ssidLower, knownLower) {
			for _, network := range networks {
				result.RogueAPDetected = append(result.RogueAPDetected, models.RogueAPAlert{
					SSID:           ssid,
					BSSID:          network.BSSID,
					SignalStrength: network.SignalLevel,
					SecurityType:   network.SecurityType,
					RiskLevel:      models.NetworkRiskLevelHigh,
					Reason:         fmt.Sprintf("SSID '%s' appears to impersonate legitimate network '%s'", ssid, known),
					DetectedAt:     time.Now(),
				})
			}
		}
	}
}

func (s *NetworkSecurityService) isSimilar(a, b string) bool {
	// Simple similarity check - could be improved with Levenshtein distance
	if len(a) == 0 || len(b) == 0 {
		return false
	}

	// Check for common substitutions
	substitutions := map[string]string{
		"1": "l", "l": "1",
		"0": "o", "o": "0",
		"_": "-", "-": "_",
		" ": "", "": " ",
	}

	normalizedA := a
	normalizedB := b
	for old, new := range substitutions {
		normalizedA = strings.ReplaceAll(normalizedA, old, new)
		normalizedB = strings.ReplaceAll(normalizedB, old, new)
	}

	// Check if one contains the other (after normalization)
	if strings.Contains(normalizedA, normalizedB) || strings.Contains(normalizedB, normalizedA) {
		return len(a) != len(b) // Only similar if lengths differ
	}

	return false
}

func (s *NetworkSecurityService) detectEvilTwin(result *models.WiFiAuditResult, current *models.WiFiNetwork, nearby []models.WiFiNetwork) {
	for _, network := range nearby {
		// Same SSID but different BSSID
		if network.SSID == current.SSID && network.BSSID != current.BSSID {
			confidence := 0.5

			// Higher confidence if security types differ
			if network.SecurityType != current.SecurityType {
				confidence += 0.3
			}

			// Higher confidence if the other AP has weaker security
			if s.isWeakerSecurity(network.SecurityType, current.SecurityType) {
				confidence += 0.2
			}

			// Higher confidence if signal strength is unusually high
			if network.SignalLevel > current.SignalLevel+10 {
				confidence += 0.1
			}

			if confidence >= 0.6 {
				result.EvilTwinDetected = append(result.EvilTwinDetected, models.EvilTwinAlert{
					SSID:           current.SSID,
					LegitBSSID:     current.BSSID,
					EvilBSSID:      network.BSSID,
					SignalDiff:     network.SignalLevel - current.SignalLevel,
					SecurityDiff:   network.SecurityType != current.SecurityType,
					RiskLevel:      models.NetworkRiskLevelCritical,
					Confidence:     confidence,
					Description:    fmt.Sprintf("Potential evil twin detected for '%s'", current.SSID),
					Recommendation: "Do not connect to this network. If already connected, use VPN immediately.",
					DetectedAt:     time.Now(),
				})
			}
		}
	}
}

func (s *NetworkSecurityService) isWeakerSecurity(a, b models.WiFiSecurityType) bool {
	securityOrder := map[models.WiFiSecurityType]int{
		models.WiFiSecurityOpen:    0,
		models.WiFiSecurityWEP:     1,
		models.WiFiSecurityWPA:     2,
		models.WiFiSecurityWPA2:    3,
		models.WiFiSecurityWPA3:    4,
		models.WiFiSecurityUnknown: 0,
	}
	return securityOrder[a] < securityOrder[b]
}

func (s *NetworkSecurityService) calculateWiFiRisk(result *models.WiFiAuditResult) (float64, models.NetworkRiskLevel) {
	score := 0.0

	// Base score from security issues
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

	// Add score for detected attacks
	score += float64(len(result.RogueAPDetected)) * 0.2
	score += float64(len(result.EvilTwinDetected)) * 0.3

	// Normalize score
	if score > 1.0 {
		score = 1.0
	}

	// Determine risk level
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

	return score, level
}

func (s *NetworkSecurityService) generateWiFiRecommendations(result *models.WiFiAuditResult) {
	// Critical: Evil twin detected
	if len(result.EvilTwinDetected) > 0 {
		result.Recommendations = append(result.Recommendations, models.NetworkRecommendation{
			Priority:    "critical",
			Title:       "Evil Twin Attack Detected",
			Description: "A malicious access point is impersonating this network. Do not transmit sensitive data.",
			Action:      "enable_vpn",
		})
	}

	// Critical: Rogue AP detected
	if len(result.RogueAPDetected) > 0 {
		result.Recommendations = append(result.Recommendations, models.NetworkRecommendation{
			Priority:    "critical",
			Title:       "Rogue Access Point Detected",
			Description: "Unauthorized access points detected. Verify you're connected to the legitimate network.",
			Action:      "verify_network",
		})
	}

	// High: Weak encryption
	for _, issue := range result.SecurityIssues {
		if issue.Type == "weak_encryption" && (issue.Severity == models.NetworkRiskLevelCritical || issue.Severity == models.NetworkRiskLevelHigh) {
			result.Recommendations = append(result.Recommendations, models.NetworkRecommendation{
				Priority:    "high",
				Title:       "Enable VPN Protection",
				Description: "This network uses weak encryption. Enable VPN to protect your data.",
				Action:      "enable_vpn",
			})
			break
		}
	}

	// Medium: Public network
	for _, issue := range result.SecurityIssues {
		if issue.Type == "public_network" {
			result.Recommendations = append(result.Recommendations, models.NetworkRecommendation{
				Priority:    "medium",
				Title:       "Public Wi-Fi Detected",
				Description: "Use VPN when on public Wi-Fi and avoid sensitive transactions.",
				Action:      "enable_vpn",
			})
			break
		}
	}

	// Low: Consider WPA3
	if result.Network != nil && result.Network.SecurityType == models.WiFiSecurityWPA2 {
		result.Recommendations = append(result.Recommendations, models.NetworkRecommendation{
			Priority:    "low",
			Title:       "Consider WPA3 Upgrade",
			Description: "WPA3 provides stronger security than WPA2 if your router supports it.",
			Action:      "upgrade_security",
		})
	}
}

// ClientCanaryResolution is one canary domain that the CLIENT resolved through
// its own local resolver and submitted for verification. Hijack detection must
// run against the client's resolver: the server resolving canaries only proves
// something about the server's resolver, which says nothing about the device.
type ClientCanaryResolution struct {
	// Canary is the well-known hostname the client resolved (e.g. "one.one.one.one").
	Canary string `json:"canary"`
	// ResolvedIPs are the answers the client's local resolver returned.
	ResolvedIPs []string `json:"resolved_ips"`
	// ResolverHint is the client's best-effort report of which resolver it
	// used (e.g. the configured DNS server IP). Informational only.
	ResolverHint string `json:"resolver_hint,omitempty"`
}

// DNSCheckOutcome wraps the DNS check result with explicit per-check status
// strings so callers can distinguish "checked and clean" from "not checked".
type DNSCheckOutcome struct {
	Result *models.DNSCheckResult
	// HijackCheckStatus describes whether the hijack check actually ran:
	// "performed: ...", "not_performed: ..." or "not_requested".
	HijackCheckStatus string
	// LeakCheckStatus describes the leak check state. Leak detection requires
	// a controlled canary zone (randomized subdomain whose authoritative
	// queries we observe via cmd/dnscanary). When no zone is configured the
	// status is dnsLeakCheckUnavailable rather than a fabricated result;
	// when configured it is "performed: ...", "not_observed: ..." or
	// "not_performed: ...".
	LeakCheckStatus string
	// LeakObservation carries the authoritative-server observation when
	// LeakCheckStatus is "performed: ..."; nil otherwise.
	LeakObservation *DNSLeakObservation
}

// DNSLeakObservation is what the authoritative canary server actually saw
// for the client's random token: the egress IP of whichever recursive
// resolver really performed the device's lookup.
type DNSLeakObservation struct {
	// Token is the client-generated random label that was resolved.
	Token string `json:"token"`
	// CanaryZone is the controlled zone the token was resolved under.
	CanaryZone string `json:"canary_zone"`
	// ObservedResolverIP is the source IP of the first query observed at the
	// authoritative server — the resolver that actually handled the lookup.
	ObservedResolverIP string `json:"observed_resolver_ip"`
	// ObservedResolverIPs lists every distinct resolver source IP observed
	// (resolver farms may retry from multiple egress addresses).
	ObservedResolverIPs []string `json:"observed_resolver_ips"`
	// ResolverASN is the autonomous system of ObservedResolverIP when the
	// canary recorded one; nil otherwise — never guessed.
	ResolverASN *int `json:"resolver_asn,omitempty"`
	// MatchesConfiguredResolver is true when an observed resolver IP exactly
	// equals the device's configured resolver (current_dns / resolver_hint).
	// NOTE: public resolvers (1.1.1.1, 8.8.8.8) legitimately egress from
	// provider-owned ranges that differ from their anycast service address,
	// so false here is informational, not proof of a leak by itself.
	MatchesConfiguredResolver bool `json:"matches_configured_resolver"`
	// QueryCount is how many canary queries were observed for the token.
	QueryCount int `json:"query_count"`
	// FirstQueryAt is when the first query reached the authoritative server.
	FirstQueryAt time.Time `json:"first_query_at"`
}

const (
	dnsCheckNotRequested = "not_requested"
	// dnsLeakCheckUnavailable is returned when a leak check is requested but
	// no controlled canary zone is configured: honest leak detection needs a
	// randomized-subdomain canary under a domain whose authoritative resolver
	// logs the backend controls (dns_canary.zone / ORBGUARD_DNS_CANARY_ZONE,
	// served by cmd/dnscanary). Without it the check is reported unavailable
	// instead of being faked from provider capabilities.
	dnsLeakCheckUnavailable = "unavailable: leak detection requires a controlled canary domain, which is not deployed"

	// dnsLeakLookupMaxWait bounds how long CheckDNS waits for the client's
	// canary query to appear in the authoritative query log. The client
	// resolves the token BEFORE submitting it, so the observation normally
	// already exists on the first lookup; the retry window only covers
	// stragglers (slow resolver chains, async log insert). Kept under the
	// HTTP server write timeout.
	dnsLeakLookupMaxWait = 8 * time.Second
	// dnsLeakLookupRetryEvery is the polling interval within the wait window.
	dnsLeakLookupRetryEvery = 2 * time.Second
)

// dnsCanaryAnswerSets maps verifiable canary hostnames to their published,
// long-term-stable answer sets. Both canaries are operated by the resolver
// vendors themselves and have not changed their A/AAAA records in years:
//   - one.one.one.one  -> Cloudflare public DNS service addresses
//   - dns.google       -> Google Public DNS service addresses
//
// Any answer outside these sets means the client's resolver is rewriting
// responses (hijack/captive portal/filtering middlebox).
var dnsCanaryAnswerSets = map[string]map[string]bool{
	"one.one.one.one": {
		"1.1.1.1":              true,
		"1.0.0.1":              true,
		"2606:4700:4700::1111": true,
		"2606:4700:4700::1001": true,
	},
	"dns.google": {
		"8.8.8.8":              true,
		"8.8.4.4":              true,
		"2001:4860:4860::8888": true,
		"2001:4860:4860::8844": true,
	},
}

// dnsCanaryExpected renders the known-good answer set for hijack details.
func dnsCanaryExpected(known map[string]bool) string {
	ips := make([]string, 0, len(known))
	for ip := range known {
		ips = append(ips, ip)
	}
	sort.Strings(ips)
	return strings.Join(ips, ", ")
}

// CheckDNS performs a DNS security check. Hijack detection is driven entirely
// by client-submitted canary resolutions (resolved on the device through its
// local resolver) compared against known-good answer sets and threat intel.
// Leak detection is driven by leakCanaryToken: the client generates a random
// token, resolves {token}.{canary zone} through its local resolver, and the
// backend reports which resolver IP the authoritative canary server actually
// observed for that token ("" = client performed no canary resolution).
func (s *NetworkSecurityService) CheckDNS(ctx context.Context, req *models.DNSCheckRequest, clientResolutions []ClientCanaryResolution, leakCanaryToken string) (*DNSCheckOutcome, error) {
	result := &models.DNSCheckResult{
		ID:              uuid.New(),
		CurrentDNS:      req.CurrentDNS,
		SecurityIssues:  make([]models.DNSSecurityIssue, 0),
		Recommendations: make([]models.NetworkRecommendation, 0),
		CheckedAt:       time.Now(),
	}
	outcome := &DNSCheckOutcome{
		Result:            result,
		HijackCheckStatus: dnsCheckNotRequested,
		LeakCheckStatus:   dnsCheckNotRequested,
	}

	// Classify the resolver the client reports it is using.
	switch {
	case req.CurrentDNS == "":
		// The client could not determine its configured resolver. Provider
		// trust cannot be assessed; say so instead of guessing.
		result.IsSecure = false
		result.SecurityIssues = append(result.SecurityIssues, models.DNSSecurityIssue{
			Type:        "resolver_unknown",
			Severity:    models.NetworkRiskLevelLow,
			Title:       "DNS Resolver Address Unknown",
			Description: "The device did not report its configured DNS server, so the resolver's provider and trust level cannot be assessed",
			Mitigation:  "Configure an explicit trusted DNS provider like Cloudflare (1.1.1.1) or Quad9 (9.9.9.9)",
		})
	default:
		if provider, ok := models.KnownDNSProviders[req.CurrentDNS]; ok {
			result.Provider = provider
			result.IsSecure = provider.IsTrusted
			result.IsEncrypted = provider.SupportsDoH || provider.SupportsDoT
			if provider.SupportsDoH {
				result.EncryptionType = "doh"
			} else if provider.SupportsDoT {
				result.EncryptionType = "dot"
			}
		} else {
			// Unknown DNS - could be ISP or potentially malicious
			result.IsSecure = false
			result.SecurityIssues = append(result.SecurityIssues, models.DNSSecurityIssue{
				Type:        "unknown_dns",
				Severity:    models.NetworkRiskLevelMedium,
				Title:       "Unknown DNS Server",
				Description: fmt.Sprintf("DNS server %s is not a recognized trusted provider", req.CurrentDNS),
				Mitigation:  "Consider switching to a trusted DNS provider like Cloudflare (1.1.1.1) or Quad9 (9.9.9.9)",
			})
		}
	}

	// Verify the client's canary resolutions for hijacking if requested.
	if req.CheckHijack {
		outcome.HijackCheckStatus = s.verifyClientCanaryResolutions(ctx, result, clientResolutions)
	}

	// Leak detection: look the client's canary token up in the authoritative
	// canary server's query log. Without a configured canary zone the check
	// is reported unavailable instead of inferring a "leak" from provider
	// capabilities (which proves nothing about actual query paths).
	if req.CheckLeaks {
		outcome.LeakCheckStatus, outcome.LeakObservation = s.performDNSLeakCheck(ctx, req, clientResolutions, leakCanaryToken)
	}

	// Generate recommendations
	s.generateDNSRecommendations(result)

	s.logger.Info().
		Str("dns", req.CurrentDNS).
		Bool("is_secure", result.IsSecure).
		Bool("is_hijacked", result.IsHijacked).
		Str("hijack_check", outcome.HijackCheckStatus).
		Str("leak_check", outcome.LeakCheckStatus).
		Int("client_resolutions", len(clientResolutions)).
		Msg("DNS check completed")

	return outcome, nil
}

// performDNSLeakCheck resolves the leak-check outcome from the authoritative
// canary query log. Returns the status string and, when a query was
// observed, the observation details.
func (s *NetworkSecurityService) performDNSLeakCheck(ctx context.Context, req *models.DNSCheckRequest, clientResolutions []ClientCanaryResolution, token string) (string, *DNSLeakObservation) {
	if s.dnsLeakCanaryZone == "" || s.dnsLeakCanaryStore == nil {
		s.logger.Info().Msg("DNS leak check requested but unavailable: no controlled canary zone configured")
		return dnsLeakCheckUnavailable, nil
	}

	token = strings.ToLower(strings.TrimSpace(token))
	if token == "" {
		return "not_performed: client did not submit a leak canary token (resolve {token}." + s.dnsLeakCanaryZone + " and pass it as leak_canary_token)", nil
	}
	if !dnscanary.ValidToken(token) {
		s.logger.Warn().Str("token", token).Msg("DNS leak check: invalid canary token format")
		return "not_performed: leak canary token has an invalid format", nil
	}

	queries, err := s.lookupCanaryQueriesWithRetry(ctx, token)
	if err != nil {
		s.logger.Error().Err(err).Str("token", token).Msg("DNS leak check: canary query log lookup failed")
		return "not_performed: canary query log lookup failed", nil
	}
	if len(queries) == 0 {
		// The device resolved the token (or tried to) but no query ever
		// reached the authoritative server. That itself is signal: the
		// resolver path either failed, served a forged answer without
		// recursing, or is blocked from reaching the canary.
		return fmt.Sprintf("not_observed: no query for the canary token reached the authoritative canary server within %s", dnsLeakLookupMaxWait), nil
	}

	// Distinct resolver egress IPs, first-seen order.
	seen := make(map[string]bool, len(queries))
	distinct := make([]string, 0, len(queries))
	for _, q := range queries {
		if !seen[q.ResolverIP] {
			seen[q.ResolverIP] = true
			distinct = append(distinct, q.ResolverIP)
		}
	}

	// The device's expected resolver addresses: the configured resolver plus
	// any resolver hints submitted with the hijack canaries.
	expected := make(map[string]bool)
	if ip := net.ParseIP(strings.TrimSpace(req.CurrentDNS)); ip != nil {
		expected[ip.String()] = true
	}
	for _, res := range clientResolutions {
		for _, hint := range strings.Split(res.ResolverHint, ",") {
			if ip := net.ParseIP(strings.TrimSpace(hint)); ip != nil {
				expected[ip.String()] = true
			}
		}
	}
	matches := false
	for _, ip := range distinct {
		if expected[ip] {
			matches = true
			break
		}
	}

	obs := &DNSLeakObservation{
		Token:                     token,
		CanaryZone:                s.dnsLeakCanaryZone,
		ObservedResolverIP:        queries[0].ResolverIP,
		ObservedResolverIPs:       distinct,
		ResolverASN:               queries[0].ResolverASN,
		MatchesConfiguredResolver: matches,
		QueryCount:                len(queries),
		FirstQueryAt:              queries[0].QueriedAt,
	}

	s.logger.Info().
		Str("token", token).
		Str("observed_resolver_ip", obs.ObservedResolverIP).
		Int("query_count", obs.QueryCount).
		Bool("matches_configured_resolver", matches).
		Msg("DNS leak check: canary query observed")

	return fmt.Sprintf("performed: canary query observed at authoritative server from %d resolver IP(s)", len(distinct)), obs
}

// lookupCanaryQueriesWithRetry polls the canary query log until queries for
// the token appear or the wait window elapses. The client resolves the token
// before submitting it, so the first lookup normally succeeds immediately;
// the window only covers slow resolver chains and the canary's async insert.
func (s *NetworkSecurityService) lookupCanaryQueriesWithRetry(ctx context.Context, token string) ([]dnscanary.ObservedQuery, error) {
	deadline := time.Now().Add(dnsLeakLookupMaxWait)
	for {
		queries, err := s.dnsLeakCanaryStore.LookupToken(ctx, token)
		if err != nil {
			return nil, err
		}
		if len(queries) > 0 {
			return queries, nil
		}
		remaining := time.Until(deadline)
		if remaining <= 0 {
			return nil, nil
		}
		wait := dnsLeakLookupRetryEvery
		if wait > remaining {
			wait = remaining
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(wait):
		}
	}
}

// verifyClientCanaryResolutions compares the canary answers the CLIENT's local
// resolver returned against the published answer sets, escalating deviations
// with threat intelligence on the resolved IPs. Returns the check status.
func (s *NetworkSecurityService) verifyClientCanaryResolutions(ctx context.Context, result *models.DNSCheckResult, resolutions []ClientCanaryResolution) string {
	if len(resolutions) == 0 {
		return "not_performed: client submitted no canary resolutions"
	}

	verified := 0
	for _, res := range resolutions {
		canary := strings.ToLower(strings.TrimSuffix(strings.TrimSpace(res.Canary), "."))
		known, ok := dnsCanaryAnswerSets[canary]
		if !ok {
			s.logger.Warn().Str("canary", res.Canary).Msg("client submitted canary with no known answer set; skipping")
			continue
		}
		if len(res.ResolvedIPs) == 0 {
			// The client's resolver returned nothing for a domain that always
			// resolves. That is a resolution failure, not proof of hijacking.
			s.logger.Info().Str("canary", canary).Str("resolver_hint", res.ResolverHint).
				Msg("client reported empty answer set for canary (local resolution failure)")
			continue
		}

		verified++
		for _, raw := range res.ResolvedIPs {
			ip := net.ParseIP(strings.TrimSpace(raw))
			if ip == nil {
				s.logger.Warn().Str("canary", canary).Str("value", raw).Msg("client submitted unparseable canary answer; skipping")
				continue
			}
			if known[ip.String()] {
				continue
			}

			// Deviation from the published answer set: the client's resolver
			// is rewriting answers for this canary.
			confidence := 0.8
			description := fmt.Sprintf("Device resolver returned %s for %s, outside the provider's published answer set", ip.String(), canary)
			if s.isSuspiciousIP(ip) {
				confidence = 0.95
				description = fmt.Sprintf("Device resolver returned private/loopback address %s for public canary %s (captive portal or local DNS interception)", ip.String(), canary)
			} else if ind := s.lookupIPIndicator(ctx, ip); ind != nil {
				confidence = 0.95
				description = fmt.Sprintf("Device resolver returned %s for %s, which matches a known threat indicator (severity %s)", ip.String(), canary, ind.Severity)
			}
			if res.ResolverHint != "" {
				description += fmt.Sprintf(" [client resolver: %s]", res.ResolverHint)
			}

			result.IsHijacked = true
			if result.HijackDetails == nil || confidence > result.HijackDetails.Confidence {
				result.HijackDetails = &models.DNSHijackDetails{
					ExpectedIP:  dnsCanaryExpected(known),
					ResolvedIP:  ip.String(),
					TestDomain:  canary,
					Confidence:  confidence,
					Description: description,
					DetectedAt:  time.Now(),
				}
			}
		}
	}

	if result.IsHijacked {
		result.SecurityIssues = append(result.SecurityIssues, models.DNSSecurityIssue{
			Type:        "dns_hijacking",
			Severity:    models.NetworkRiskLevelCritical,
			Title:       "DNS Hijacking Detected",
			Description: "The device's DNS resolver is rewriting answers for well-known domains",
			Mitigation:  "Switch to encrypted DNS (DoH) immediately. Consider using VPN.",
		})
	}

	if verified == 0 {
		return "not_performed: no verifiable canary resolutions submitted"
	}
	return fmt.Sprintf("performed: %d canary domain(s) verified against known answer sets", verified)
}

func (s *NetworkSecurityService) isSuspiciousIP(ip net.IP) bool {
	// Private/loopback/unspecified addresses must never be the answer for a
	// public canary domain; they indicate local interception.
	return ip.IsPrivate() || ip.IsLoopback() || ip.IsUnspecified() || ip.IsLinkLocalUnicast()
}

// lookupIPIndicator checks the threat-intelligence indicator store for a
// resolved IP. Returns nil when no indicator exists or lookup fails (failures
// are logged, never silently treated as "clean with certainty").
func (s *NetworkSecurityService) lookupIPIndicator(ctx context.Context, ip net.IP) *models.Indicator {
	if s.repos == nil || s.repos.Indicators == nil {
		s.logger.Warn().Msg("indicator repository unavailable; skipping threat-intel check on resolved IP")
		return nil
	}

	types := []models.IndicatorType{models.IndicatorTypeIP, models.IndicatorTypeIPv4}
	if ip.To4() == nil {
		types = []models.IndicatorType{models.IndicatorTypeIP, models.IndicatorTypeIPv6}
	}
	for _, iocType := range types {
		ind, err := s.repos.Indicators.GetByValue(ctx, ip.String(), iocType)
		if err != nil {
			s.logger.Warn().Err(err).Str("ip", ip.String()).Str("type", string(iocType)).
				Msg("threat-intel lookup on resolved IP failed")
			continue
		}
		if ind != nil {
			return ind
		}
	}
	return nil
}

func (s *NetworkSecurityService) generateDNSRecommendations(result *models.DNSCheckResult) {
	// Critical: DNS hijacking
	if result.IsHijacked {
		result.Recommendations = append(result.Recommendations, models.NetworkRecommendation{
			Priority:    "critical",
			Title:       "Switch DNS Immediately",
			Description: "Your DNS is being hijacked. Switch to encrypted DNS (1.1.1.1 or 9.9.9.9) now.",
			Action:      "change_dns",
		})
	}

	// High: Not using encrypted DNS
	if !result.IsEncrypted {
		result.Recommendations = append(result.Recommendations, models.NetworkRecommendation{
			Priority:    "high",
			Title:       "Enable Encrypted DNS",
			Description: "Use DNS-over-HTTPS (DoH) for privacy. Recommended: Cloudflare (1.1.1.1) or Quad9 (9.9.9.9).",
			Action:      "enable_doh",
		})
	}

	// Medium: Not using malware-blocking DNS
	if result.Provider != nil && !result.Provider.BlocksMalware {
		result.Recommendations = append(result.Recommendations, models.NetworkRecommendation{
			Priority:    "medium",
			Title:       "Consider Malware-Blocking DNS",
			Description: "Use DNS that blocks malicious domains (Quad9, Cloudflare 1.1.1.2, or AdGuard).",
			Action:      "change_dns",
		})
	}

	// Low: Unknown provider
	if result.Provider == nil {
		result.Recommendations = append(result.Recommendations, models.NetworkRecommendation{
			Priority:    "medium",
			Title:       "Switch to Trusted DNS",
			Description: "Your current DNS provider is unknown. Consider switching to a trusted provider.",
			Action:      "change_dns",
		})
	}
}

// CheckARPSpoofing checks for ARP spoofing attacks
func (s *NetworkSecurityService) CheckARPSpoofing(ctx context.Context, req *models.ARPSpoofCheckRequest) (*models.ARPSpoofCheckResult, error) {
	result := &models.ARPSpoofCheckResult{
		ID:              uuid.New(),
		Alerts:          make([]models.NetworkAttackAlert, 0),
		SuspiciousMACs:  make([]string, 0),
		DuplicateIPs:    make([]string, 0),
		Recommendations: make([]models.NetworkRecommendation, 0),
		CheckedAt:       time.Now(),
	}

	// Check for multiple IPs with same MAC (normal for routers, suspicious otherwise)
	macToIPs := make(map[string][]string)
	for _, entry := range req.ARPTable {
		macToIPs[entry.MACAddress] = append(macToIPs[entry.MACAddress], entry.IPAddress)
	}

	for mac, ips := range macToIPs {
		if len(ips) > 1 {
			// Check if this is the gateway (multiple IPs normal)
			isGateway := false
			for _, ip := range ips {
				if ip == req.GatewayIP {
					isGateway = true
					break
				}
			}

			if !isGateway {
				result.SuspiciousMACs = append(result.SuspiciousMACs, mac)
				result.DuplicateIPs = append(result.DuplicateIPs, ips...)
			}
		}
	}

	// Check for multiple MACs claiming same IP (definitely suspicious)
	ipToMACs := make(map[string][]string)
	for _, entry := range req.ARPTable {
		ipToMACs[entry.IPAddress] = append(ipToMACs[entry.IPAddress], entry.MACAddress)
	}

	for ip, macs := range ipToMACs {
		if len(macs) > 1 {
			result.IsSpoofDetected = true
			attackInfo := models.NetworkAttackDescriptions[models.NetworkAttackARPSpoofing]
			result.Alerts = append(result.Alerts, models.NetworkAttackAlert{
				ID:          uuid.New(),
				Type:        models.NetworkAttackARPSpoofing,
				Severity:    attackInfo.Severity,
				Title:       attackInfo.Title,
				Description: fmt.Sprintf("Multiple MAC addresses claiming IP %s: %v", ip, macs),
				Evidence:    []string{fmt.Sprintf("IP %s has MACs: %v", ip, macs)},
				Mitigation:  attackInfo.Mitigation,
				DetectedAt:  time.Now(),
			})
		}
	}

	// Check if gateway MAC has changed against this device's own baseline.
	// Without a device identifier there is no safe scoping key, so the
	// history check is skipped rather than risking cross-user false positives.
	if req.GatewayIP != "" && req.GatewayMAC != "" {
		if req.DeviceID == "" {
			s.logger.Debug().
				Str("gateway_ip", req.GatewayIP).
				Msg("skipping gateway MAC baseline check: request has no device_id")
		} else {
			baseline, exists := s.loadGatewayBaseline(ctx, req.DeviceID, req.GatewayIP)
			switch {
			case exists && baseline.GatewayMAC != req.GatewayMAC:
				result.IsSpoofDetected = true
				attackInfo := models.NetworkAttackDescriptions[models.NetworkAttackARPSpoofing]
				result.Alerts = append(result.Alerts, models.NetworkAttackAlert{
					ID:          uuid.New(),
					Type:        models.NetworkAttackARPSpoofing,
					Severity:    models.NetworkRiskLevelCritical,
					Title:       "Gateway MAC Address Changed",
					Description: fmt.Sprintf("Gateway %s MAC changed from %s to %s", req.GatewayIP, baseline.GatewayMAC, req.GatewayMAC),
					Evidence:    []string{fmt.Sprintf("Previous: %s, Current: %s", baseline.GatewayMAC, req.GatewayMAC)},
					Mitigation:  attackInfo.Mitigation,
					DetectedAt:  time.Now(),
				})
				// Keep the existing baseline: the new MAC may belong to an
				// attacker and must not silently become the trusted value.
				// If the change is legitimate (router replaced), the old
				// baseline ages out via TTL.
			case exists:
				// MAC matches the baseline - refresh last-seen and TTL.
				baseline.LastSeen = time.Now()
				s.storeGatewayBaseline(ctx, req.DeviceID, req.GatewayIP, baseline)
			default:
				now := time.Now()
				s.storeGatewayBaseline(ctx, req.DeviceID, req.GatewayIP, gatewayBaseline{
					GatewayMAC: req.GatewayMAC,
					FirstSeen:  now,
					LastSeen:   now,
				})
			}
		}
	}

	// Generate recommendations
	if result.IsSpoofDetected {
		result.Recommendations = append(result.Recommendations, models.NetworkRecommendation{
			Priority:    "critical",
			Title:       "ARP Spoofing Detected - Enable VPN",
			Description: "An attacker may be intercepting your traffic. Enable VPN immediately.",
			Action:      "enable_vpn",
		})
		result.Recommendations = append(result.Recommendations, models.NetworkRecommendation{
			Priority:    "high",
			Title:       "Avoid Sensitive Activities",
			Description: "Do not perform banking or enter passwords on this network.",
			Action:      "avoid_sensitive",
		})
	}

	s.logger.Info().
		Bool("spoof_detected", result.IsSpoofDetected).
		Int("alerts", len(result.Alerts)).
		Msg("ARP spoof check completed")

	return result, nil
}

// CheckSSL checks SSL/TLS security for a host
func (s *NetworkSecurityService) CheckSSL(ctx context.Context, req *models.SSLCheckRequest) (*models.SSLCheckResult, error) {
	port := req.Port
	if port == 0 {
		port = 443
	}

	result := &models.SSLCheckResult{
		ID:              uuid.New(),
		Host:            req.Host,
		Port:            port,
		SecurityIssues:  make([]models.SSLSecurityIssue, 0),
		Recommendations: make([]models.NetworkRecommendation, 0),
		CheckedAt:       time.Now(),
	}

	// Connect with TLS
	conn, err := tls.DialWithDialer(
		&net.Dialer{Timeout: 10 * time.Second},
		"tcp",
		fmt.Sprintf("%s:%d", req.Host, port),
		&tls.Config{
			InsecureSkipVerify: true, // We want to inspect even invalid certs
		},
	)
	if err != nil {
		result.IsSecure = false
		result.SecurityIssues = append(result.SecurityIssues, models.SSLSecurityIssue{
			Type:        "connection_failed",
			Severity:    models.NetworkRiskLevelHigh,
			Title:       "TLS Connection Failed",
			Description: fmt.Sprintf("Could not establish TLS connection: %v", err),
			Mitigation:  "The server may not support HTTPS or may be down",
		})
		return result, nil
	}
	defer conn.Close()

	// Get connection state
	state := conn.ConnectionState()

	// Check TLS version
	result.TLSVersion = s.tlsVersionString(state.Version)
	if state.Version < tls.VersionTLS12 {
		result.SecurityIssues = append(result.SecurityIssues, models.SSLSecurityIssue{
			Type:        "old_tls",
			Severity:    models.NetworkRiskLevelHigh,
			Title:       "Outdated TLS Version",
			Description: fmt.Sprintf("Server uses %s which has known vulnerabilities", result.TLSVersion),
			Mitigation:  "Server should be upgraded to TLS 1.2 or higher",
		})
	}

	// Check cipher suite
	result.CipherSuite = tls.CipherSuiteName(state.CipherSuite)

	// Check certificate
	if len(state.PeerCertificates) > 0 {
		cert := state.PeerCertificates[0]
		result.Certificate = &models.SSLCertificate{
			Subject:      cert.Subject.String(),
			Issuer:       cert.Issuer.String(),
			SerialNumber: cert.SerialNumber.String(),
			NotBefore:    cert.NotBefore,
			NotAfter:     cert.NotAfter,
			IsExpired:    time.Now().After(cert.NotAfter),
			IsSelfSigned: cert.Subject.String() == cert.Issuer.String(),
			IsValid:      !time.Now().After(cert.NotAfter) && !time.Now().Before(cert.NotBefore),
			PublicKeyAlg: cert.PublicKeyAlgorithm.String(),
		}

		// Check for issues
		if result.Certificate.IsExpired {
			result.SecurityIssues = append(result.SecurityIssues, models.SSLSecurityIssue{
				Type:        "expired_cert",
				Severity:    models.NetworkRiskLevelCritical,
				Title:       "Expired Certificate",
				Description: fmt.Sprintf("Certificate expired on %s", cert.NotAfter.Format(time.RFC3339)),
				Mitigation:  "Do not proceed - this could indicate a MITM attack",
			})
		}

		if result.Certificate.IsSelfSigned {
			result.SecurityIssues = append(result.SecurityIssues, models.SSLSecurityIssue{
				Type:        "self_signed",
				Severity:    models.NetworkRiskLevelHigh,
				Title:       "Self-Signed Certificate",
				Description: "Certificate is not signed by a trusted authority",
				Mitigation:  "Only proceed if you trust this server explicitly",
			})
		}

		// Verify certificate chain
		result.IsValidChain = len(state.VerifiedChains) > 0
	}

	// Determine overall security
	result.IsSecure = len(result.SecurityIssues) == 0

	// Generate recommendations
	if !result.IsSecure {
		result.Recommendations = append(result.Recommendations, models.NetworkRecommendation{
			Priority:    "high",
			Title:       "Proceed with Caution",
			Description: "This connection has security issues. Verify you're connecting to the correct server.",
			Action:      "verify_connection",
		})
	}

	s.logger.Info().
		Str("host", req.Host).
		Bool("is_secure", result.IsSecure).
		Str("tls_version", result.TLSVersion).
		Msg("SSL check completed")

	return result, nil
}

func (s *NetworkSecurityService) tlsVersionString(version uint16) string {
	switch version {
	case tls.VersionTLS10:
		return "TLS 1.0"
	case tls.VersionTLS11:
		return "TLS 1.1"
	case tls.VersionTLS12:
		return "TLS 1.2"
	case tls.VersionTLS13:
		return "TLS 1.3"
	default:
		return fmt.Sprintf("Unknown (0x%04x)", version)
	}
}

// GetVPNRecommendation returns VPN usage recommendation based on network conditions
func (s *NetworkSecurityService) GetVPNRecommendation(ctx context.Context, wifiAudit *models.WiFiAuditResult, dnsCheck *models.DNSCheckResult) *models.VPNRecommendation {
	rec := &models.VPNRecommendation{
		ShouldConnect: false,
		Priority:      "optional",
		NetworkRisk:   models.NetworkRiskLevelSafe,
	}

	// Check Wi-Fi audit results
	if wifiAudit != nil {
		rec.NetworkRisk = wifiAudit.RiskLevel

		if len(wifiAudit.EvilTwinDetected) > 0 {
			rec.ShouldConnect = true
			rec.Priority = "required"
			rec.Reason = "Evil twin attack detected - VPN required for protection"
			return rec
		}

		if len(wifiAudit.RogueAPDetected) > 0 {
			rec.ShouldConnect = true
			rec.Priority = "required"
			rec.Reason = "Rogue access point detected - VPN strongly recommended"
			return rec
		}

		if wifiAudit.RiskLevel == models.NetworkRiskLevelCritical || wifiAudit.RiskLevel == models.NetworkRiskLevelHigh {
			rec.ShouldConnect = true
			rec.Priority = "recommended"
			rec.Reason = "Network has significant security risks - VPN recommended"
			return rec
		}

		// Check for weak encryption
		for _, issue := range wifiAudit.SecurityIssues {
			if issue.Type == "weak_encryption" && issue.Severity == models.NetworkRiskLevelCritical {
				rec.ShouldConnect = true
				rec.Priority = "required"
				rec.Reason = "Network uses weak/no encryption - VPN required"
				return rec
			}
		}

		// Check for public network
		for _, issue := range wifiAudit.SecurityIssues {
			if issue.Type == "public_network" {
				rec.ShouldConnect = true
				rec.Priority = "recommended"
				rec.Reason = "Public Wi-Fi detected - VPN recommended for privacy"
				return rec
			}
		}
	}

	// Check DNS results
	if dnsCheck != nil {
		if dnsCheck.IsHijacked {
			rec.ShouldConnect = true
			rec.Priority = "required"
			rec.Reason = "DNS hijacking detected - VPN required"
			return rec
		}

		if !dnsCheck.IsSecure {
			rec.ShouldConnect = true
			rec.Priority = "recommended"
			rec.Reason = "DNS is not secure - VPN recommended"
			return rec
		}
	}

	rec.Reason = "Network appears safe - VPN optional"
	return rec
}

// GetStats returns network security statistics
func (s *NetworkSecurityService) GetStats(ctx context.Context) (*models.NetworkSecurityStats, error) {
	stats := &models.NetworkSecurityStats{
		AttacksByType: make(map[string]int64),
	}

	// In production, these would come from database
	// For now, return placeholder data
	if s.cache != nil {
		// Try to get cached stats
		// Implementation would use cache.Get()
	}

	return stats, nil
}
