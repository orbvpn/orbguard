package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services/desktop_security"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// DesktopSecurityDeps holds desktop security handler dependencies
type DesktopSecurityDeps struct {
	PersistenceScanner *desktop_security.PersistenceScanner
	CodeVerifier       *desktop_security.CodeSigningVerifier
	NetworkMonitor     *desktop_security.NetworkMonitor
	BrowserScanner     *desktop_security.BrowserExtensionScanner
	VTClient           *desktop_security.VirusTotalClient
	// Results caches per-device scan output so the GET endpoints can serve
	// the last known results. Optional: when nil, scans still work but the
	// cached GET endpoints report storage as unavailable.
	Results *repository.DesktopResultsRepository
	// Indicators is the threat-intel indicator repository used by the
	// upload-analyze endpoints to match remote IPs and extension IDs against
	// known IOCs. Optional: when nil, intel matching is skipped.
	Indicators *repository.IndicatorRepository
	Logger     *logger.Logger
}

// DesktopSecurityHandler handles desktop security endpoints
type DesktopSecurityHandler struct {
	persistence *desktop_security.PersistenceScanner
	codesign    *desktop_security.CodeSigningVerifier
	network     *desktop_security.NetworkMonitor
	browser     *desktop_security.BrowserExtensionScanner
	vt          *desktop_security.VirusTotalClient
	results     *repository.DesktopResultsRepository
	indicators  *repository.IndicatorRepository
	logger      *logger.Logger
}

// NewDesktopSecurityHandler creates a new DesktopSecurityHandler
func NewDesktopSecurityHandler(deps DesktopSecurityDeps) *DesktopSecurityHandler {
	return &DesktopSecurityHandler{
		persistence: deps.PersistenceScanner,
		codesign:    deps.CodeVerifier,
		network:     deps.NetworkMonitor,
		browser:     deps.BrowserScanner,
		vt:          deps.VTClient,
		results:     deps.Results,
		indicators:  deps.Indicators,
		logger:      deps.Logger.WithComponent("desktop-security-handler"),
	}
}

// signedAppEntry is the per-application code-signing summary persisted by the
// verify endpoints and served by GET /desktop/apps. Field names match what
// the Flutter client parses (SignedApp.fromJson): name, bundle_id, is_signed,
// is_valid, developer, team_id. bundle_id is left empty when the signing
// metadata does not expose one — it is never fabricated.
type signedAppEntry struct {
	Name        string                   `json:"name"`
	BundleID    string                   `json:"bundle_id"`
	Path        string                   `json:"path"`
	IsSigned    bool                     `json:"is_signed"`
	IsValid     bool                     `json:"is_valid"`
	Developer   string                   `json:"developer"`
	TeamID      string                   `json:"team_id,omitempty"`
	Status      models.CodeSigningStatus `json:"status"`
	IsNotarized bool                     `json:"is_notarized"`
}

// newSignedAppEntry converts a code-signing verification result into the
// persisted/served app entry.
func newSignedAppEntry(path string, info *desktop_security.SigningInfo) signedAppEntry {
	name := filepath.Base(path)
	for _, ext := range []string{".app", ".exe", ".dll", ".dylib", ".so"} {
		name = strings.TrimSuffix(name, ext)
	}

	developer := info.SigningIdentity
	if developer == "" {
		developer = info.SigningAuthority
	}

	return signedAppEntry{
		Name:        name,
		BundleID:    "",
		Path:        path,
		IsSigned:    info.IsSigned,
		IsValid:     info.IsValid,
		Developer:   developer,
		TeamID:      info.TeamID,
		Status:      info.Status,
		IsNotarized: info.IsNotarized,
	}
}

// persistScanResults caches scan output for the requesting device. Best
// effort: the scan response is already correct, so persistence failures are
// logged rather than surfaced.
func (h *DesktopSecurityHandler) persistScanResults(r *http.Request, scanType string, results any) {
	if h.results == nil {
		h.logger.Debug().Str("scan_type", scanType).Msg("desktop scan results not cached: storage not configured")
		return
	}
	deviceID := resolveDeviceID(r, "")
	if deviceID == "" {
		h.logger.Debug().Str("scan_type", scanType).Msg("desktop scan results not cached: no device id on request")
		return
	}
	if err := h.results.UpsertScan(r.Context(), deviceID, scanType, results); err != nil {
		h.logger.Error().Err(err).
			Str("scan_type", scanType).
			Str("device_id", deviceID).
			Msg("failed to cache desktop scan results")
	}
}

// serveCachedScan serves the last cached scan results for the requesting
// device under the given wrapper key, with scanned_at alongside. Devices
// that have never run the scan get an honest empty payload with
// scanned_at=null.
func (h *DesktopSecurityHandler) serveCachedScan(w http.ResponseWriter, r *http.Request, scanType, wrapperKey string) {
	if h.results == nil {
		h.logger.Error().Str("scan_type", scanType).Msg("cached desktop results unavailable: storage not configured")
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "desktop scan result storage unavailable"})
		return
	}

	deviceID := resolveDeviceID(r, "")
	if deviceID == "" {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "device ID is required (authenticate as a device or pass device_id)"})
		return
	}

	raw, scannedAt, err := h.results.GetScan(r.Context(), deviceID, scanType)
	if err != nil {
		h.logger.Error().Err(err).
			Str("scan_type", scanType).
			Str("device_id", deviceID).
			Msg("failed to load cached desktop scan results")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to load cached scan results"})
		return
	}

	if raw == nil {
		// Never scanned — honest empty result, scanned_at null.
		respondJSON(w, http.StatusOK, map[string]interface{}{
			wrapperKey:   []interface{}{},
			"scanned_at": nil,
		})
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		wrapperKey:   raw,
		"scanned_at": scannedAt,
	})
}

// GetCachedPersistence handles GET /api/v1/desktop/persistence — last cached
// persistence scan for the requesting device, wrapped as {items, scanned_at}.
func (h *DesktopSecurityHandler) GetCachedPersistence(w http.ResponseWriter, r *http.Request) {
	h.serveCachedScan(w, r, repository.DesktopScanTypePersistence, "items")
}

// GetCachedApps handles GET /api/v1/desktop/apps — last cached code-signing
// verification results for the requesting device, wrapped as
// {apps, scanned_at}.
func (h *DesktopSecurityHandler) GetCachedApps(w http.ResponseWriter, r *http.Request) {
	h.serveCachedScan(w, r, repository.DesktopScanTypeApps, "apps")
}

// GetCachedFirewall handles GET /api/v1/desktop/firewall.
//
// Firewall rules are live configuration rather than scan output, so when the
// network monitor is available this serves the live rules wrapped as
// {rules, scanned_at} (and refreshes the cached snapshot). When the monitor
// is unavailable it falls back to the last cached snapshot. This is distinct
// from GET /desktop/network/rules, which stays a bare live JSON array.
func (h *DesktopSecurityHandler) GetCachedFirewall(w http.ResponseWriter, r *http.Request) {
	if h.network != nil {
		rules := h.network.GetFirewallRules()
		h.persistScanResults(r, repository.DesktopScanTypeFirewall, rules)
		respondJSON(w, http.StatusOK, map[string]interface{}{
			"rules":      rules,
			"scanned_at": time.Now().UTC(),
		})
		return
	}
	h.serveCachedScan(w, r, repository.DesktopScanTypeFirewall, "rules")
}

// snapshotFirewallRules refreshes the cached firewall snapshot after a rule
// mutation so GET /desktop/firewall stays consistent even if the monitor
// later becomes unavailable.
func (h *DesktopSecurityHandler) snapshotFirewallRules(r *http.Request) {
	if h.network == nil {
		return
	}
	h.persistScanResults(r, repository.DesktopScanTypeFirewall, h.network.GetFirewallRules())
}

// ScanPersistence handles POST /api/v1/desktop/persistence/scan
func (h *DesktopSecurityHandler) ScanPersistence(w http.ResponseWriter, r *http.Request) {
	if h.persistence == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "persistence scanner not available"})
		return
	}
	result, err := h.persistence.Scan(r.Context())
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	h.persistScanResults(r, repository.DesktopScanTypePersistence, result.Items)
	respondJSON(w, http.StatusOK, result)
}

// QuickScanPersistence handles POST /api/v1/desktop/persistence/quick-scan
func (h *DesktopSecurityHandler) QuickScanPersistence(w http.ResponseWriter, r *http.Request) {
	if h.persistence == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "persistence scanner not available"})
		return
	}
	result, err := h.persistence.QuickScan(r.Context())
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	h.persistScanResults(r, repository.DesktopScanTypePersistence, result.Items)
	respondJSON(w, http.StatusOK, result)
}

// ScanPath handles POST /api/v1/desktop/persistence/scan-path
//
// Path scans cover a subset of persistence locations, so they intentionally
// do not overwrite the cached full-scan results.
func (h *DesktopSecurityHandler) ScanPath(w http.ResponseWriter, r *http.Request) {
	if h.persistence == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "persistence scanner not available"})
		return
	}
	var req struct {
		Path string `json:"path"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Path == "" {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "path is required"})
		return
	}
	items, err := h.persistence.ScanPath(r.Context(), req.Path)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, items)
}

// VerifyCodeSigning handles POST /api/v1/desktop/codesign/verify
func (h *DesktopSecurityHandler) VerifyCodeSigning(w http.ResponseWriter, r *http.Request) {
	if h.codesign == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "code signing verifier not available"})
		return
	}
	var req struct {
		Path string `json:"path"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Path == "" {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "path is required"})
		return
	}
	info, err := h.codesign.Verify(r.Context(), req.Path)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	h.mergeCachedApp(r, req.Path, info)
	respondJSON(w, http.StatusOK, info)
}

// mergeCachedApp updates a single entry in the cached apps list (keyed by
// path) after a single-binary verification, without discarding the rest of
// the last batch results.
func (h *DesktopSecurityHandler) mergeCachedApp(r *http.Request, path string, info *desktop_security.SigningInfo) {
	if h.results == nil || info == nil {
		return
	}
	deviceID := resolveDeviceID(r, "")
	if deviceID == "" {
		return
	}

	raw, _, err := h.results.GetScan(r.Context(), deviceID, repository.DesktopScanTypeApps)
	if err != nil {
		h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to load cached apps for merge")
		return
	}

	var apps []signedAppEntry
	if raw != nil {
		if err := json.Unmarshal(raw, &apps); err != nil {
			h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to decode cached apps for merge")
			apps = nil
		}
	}

	entry := newSignedAppEntry(path, info)
	replaced := false
	for i := range apps {
		if apps[i].Path == path {
			apps[i] = entry
			replaced = true
			break
		}
	}
	if !replaced {
		apps = append(apps, entry)
	}

	if err := h.results.UpsertScan(r.Context(), deviceID, repository.DesktopScanTypeApps, apps); err != nil {
		h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to cache merged app entry")
	}
}

// VerifyCodeSigningBatch handles POST /api/v1/desktop/codesign/verify-batch
func (h *DesktopSecurityHandler) VerifyCodeSigningBatch(w http.ResponseWriter, r *http.Request) {
	if h.codesign == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "code signing verifier not available"})
		return
	}
	var req struct {
		Paths []string `json:"paths"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || len(req.Paths) == 0 {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "paths are required"})
		return
	}
	results := h.codesign.VerifyBatch(r.Context(), req.Paths)

	// A batch verification is a full apps scan: replace the cached snapshot.
	apps := make([]signedAppEntry, 0, len(results))
	for path, info := range results {
		if info == nil {
			continue
		}
		apps = append(apps, newSignedAppEntry(path, info))
	}
	sort.Slice(apps, func(i, j int) bool { return apps[i].Path < apps[j].Path })
	h.persistScanResults(r, repository.DesktopScanTypeApps, apps)

	respondJSON(w, http.StatusOK, results)
}

// GetNetworkConnections handles GET /api/v1/desktop/network/connections
func (h *DesktopSecurityHandler) GetNetworkConnections(w http.ResponseWriter, r *http.Request) {
	if h.network == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "network monitor not available"})
		return
	}
	conns, err := h.network.GetConnections(r.Context())
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, conns)
}

// GetListeningPorts handles GET /api/v1/desktop/network/listening
func (h *DesktopSecurityHandler) GetListeningPorts(w http.ResponseWriter, r *http.Request) {
	if h.network == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "network monitor not available"})
		return
	}
	ports, err := h.network.GetListeningPorts(r.Context())
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, ports)
}

// GetOutboundConnections handles GET /api/v1/desktop/network/outbound
func (h *DesktopSecurityHandler) GetOutboundConnections(w http.ResponseWriter, r *http.Request) {
	if h.network == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "network monitor not available"})
		return
	}
	conns, err := h.network.GetOutboundConnections(r.Context())
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, conns)
}

// GetFirewallRules handles GET /api/v1/desktop/network/rules — live rules as
// a bare JSON array (the Flutter client parses this shape).
func (h *DesktopSecurityHandler) GetFirewallRules(w http.ResponseWriter, r *http.Request) {
	if h.network == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "network monitor not available"})
		return
	}
	respondJSON(w, http.StatusOK, h.network.GetFirewallRules())
}

// AddFirewallRule handles POST /api/v1/desktop/network/rules
func (h *DesktopSecurityHandler) AddFirewallRule(w http.ResponseWriter, r *http.Request) {
	if h.network == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "network monitor not available"})
		return
	}
	var rule models.FirewallRule
	if err := json.NewDecoder(r.Body).Decode(&rule); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	rule.ID = uuid.New()
	if err := h.network.AddFirewallRule(rule); err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	h.snapshotFirewallRules(r)
	respondJSON(w, http.StatusCreated, map[string]string{"status": "rule added"})
}

// DeleteFirewallRule handles DELETE /api/v1/desktop/network/rules/{id}
func (h *DesktopSecurityHandler) DeleteFirewallRule(w http.ResponseWriter, r *http.Request) {
	if h.network == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "network monitor not available"})
		return
	}
	ruleID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid rule ID"})
		return
	}
	if err := h.network.RemoveFirewallRule(ruleID); err != nil {
		respondJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
		return
	}
	h.snapshotFirewallRules(r)
	respondJSON(w, http.StatusOK, map[string]string{"status": "rule removed"})
}

// BlockIP handles POST /api/v1/desktop/network/block-ip
func (h *DesktopSecurityHandler) BlockIP(w http.ResponseWriter, r *http.Request) {
	if h.network == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "network monitor not available"})
		return
	}
	var req struct {
		IP     string `json:"ip"`
		Reason string `json:"reason"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.IP == "" {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "ip is required"})
		return
	}
	h.network.BlockIP(req.IP, req.Reason)
	h.snapshotFirewallRules(r)
	respondJSON(w, http.StatusOK, map[string]string{"status": "ip blocked"})
}

// ScanBrowserExtensions handles POST /api/v1/desktop/browser/extensions/scan
func (h *DesktopSecurityHandler) ScanBrowserExtensions(w http.ResponseWriter, r *http.Request) {
	if h.browser == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "browser scanner not available"})
		return
	}
	extensions, err := h.browser.Scan(r.Context())
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, map[string]interface{}{
		"extensions": extensions,
		"total":      len(extensions),
		"high_risk":  len(h.browser.GetHighRiskExtensions(extensions)),
		"by_browser": h.browser.GetBrowserCount(extensions),
	})
}

// LookupHash handles GET /api/v1/desktop/virustotal/hash/{hash}
func (h *DesktopSecurityHandler) LookupHash(w http.ResponseWriter, r *http.Request) {
	if h.vt == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "VirusTotal client not available"})
		return
	}
	hash := chi.URLParam(r, "hash")
	report, err := h.vt.LookupHash(r.Context(), hash)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, report)
}

// LookupFile handles POST /api/v1/desktop/virustotal/file
func (h *DesktopSecurityHandler) LookupFile(w http.ResponseWriter, r *http.Request) {
	if h.vt == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "VirusTotal client not available"})
		return
	}
	var req struct {
		Path string `json:"path"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Path == "" {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "path is required"})
		return
	}
	report, err := h.vt.LookupFile(r.Context(), req.Path)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, report)
}

// LookupHashBatch handles POST /api/v1/desktop/virustotal/batch
func (h *DesktopSecurityHandler) LookupHashBatch(w http.ResponseWriter, r *http.Request) {
	if h.vt == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "VirusTotal client not available"})
		return
	}
	var req struct {
		Hashes []string `json:"hashes"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || len(req.Hashes) == 0 {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "hashes are required"})
		return
	}
	results := h.vt.LookupBatch(r.Context(), req.Hashes)
	respondJSON(w, http.StatusOK, results)
}

// LookupIP handles GET /api/v1/desktop/virustotal/ip/{ip}
func (h *DesktopSecurityHandler) LookupIP(w http.ResponseWriter, r *http.Request) {
	if h.vt == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "VirusTotal client not available"})
		return
	}
	ip := chi.URLParam(r, "ip")
	report, err := h.vt.LookupIP(r.Context(), ip)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	respondJSON(w, http.StatusOK, report)
}

// FullSecurityScan handles POST /api/v1/desktop/scan/full
//
// Sub-scan failures are never silently dropped: each section reports its own
// status ("ok", "error", or "unavailable") plus the error message under
// result["sections"], so clients can distinguish "scanned clean" from
// "scan failed".
func (h *DesktopSecurityHandler) FullSecurityScan(w http.ResponseWriter, r *http.Request) {
	sections := map[string]map[string]interface{}{}
	result := map[string]interface{}{
		"scan_type": "full",
		"sections":  sections,
	}

	if h.persistence == nil {
		sections["persistence"] = map[string]interface{}{
			"status": "unavailable",
			"error":  "persistence scanner not available",
		}
	} else if scan, err := h.persistence.Scan(r.Context()); err != nil {
		h.logger.Error().Err(err).Msg("full scan: persistence scan failed")
		sections["persistence"] = map[string]interface{}{
			"status": "error",
			"error":  err.Error(),
		}
	} else {
		sections["persistence"] = map[string]interface{}{"status": "ok"}
		result["persistence"] = scan
		h.persistScanResults(r, repository.DesktopScanTypePersistence, scan.Items)
	}

	if h.browser == nil {
		sections["browser_extensions"] = map[string]interface{}{
			"status": "unavailable",
			"error":  "browser scanner not available",
		}
	} else if exts, err := h.browser.Scan(r.Context()); err != nil {
		h.logger.Error().Err(err).Msg("full scan: browser extension scan failed")
		sections["browser_extensions"] = map[string]interface{}{
			"status": "error",
			"error":  err.Error(),
		}
	} else {
		sections["browser_extensions"] = map[string]interface{}{"status": "ok"}
		result["browser_extensions"] = exts
	}

	if h.network == nil {
		sections["network_connections"] = map[string]interface{}{
			"status": "unavailable",
			"error":  "network monitor not available",
		}
	} else if conns, err := h.network.GetConnections(r.Context()); err != nil {
		h.logger.Error().Err(err).Msg("full scan: network connection scan failed")
		sections["network_connections"] = map[string]interface{}{
			"status": "error",
			"error":  err.Error(),
		}
	} else {
		sections["network_connections"] = map[string]interface{}{"status": "ok"}
		result["network_connections"] = len(conns)
	}

	respondJSON(w, http.StatusOK, result)
}

// maxVTIPLookups bounds how many VirusTotal IP lookups a single
// network-analyze request may trigger. The VT free tier allows 4
// requests/minute (cached reports are free), so this keeps the endpoint
// responsive instead of stalling on the client's whole connection table.
const maxVTIPLookups = 8

// AnalyzeNetworkConnections handles POST /api/v1/desktop/network/analyze.
//
// Desktop clients collect their local connection table (the backend's network
// monitor sees only the SERVER host) and upload it here for server-side
// enrichment: IOC blocklist + C2 heuristics, threat-intel indicator matching
// on remote IPs, and VirusTotal IP reputation. The enriched snapshot is
// persisted as the device's latest "network" scan.
func (h *DesktopSecurityHandler) AnalyzeNetworkConnections(w http.ResponseWriter, r *http.Request) {
	if h.network == nil && h.indicators == nil && h.vt == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "no network analysis capability configured"})
		return
	}

	var req struct {
		Connections []models.NetworkConnection `json:"connections"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || len(req.Connections) == 0 {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "connections are required"})
		return
	}
	conns := req.Connections

	// Local heuristics: IOC blocklist, reverse DNS, C2 / risky-port checks.
	if h.network != nil {
		for i := range conns {
			h.network.AnalyzeConnection(&conns[i])
		}
	}

	publicIPs := uniquePublicRemoteIPs(conns)

	// Threat intel: match remote IPs against the indicator database.
	if h.indicators != nil && len(publicIPs) > 0 {
		matches, err := h.indicators.CheckBatch(r.Context(), publicIPs)
		if err != nil {
			h.logger.Error().Err(err).Msg("network analyze: indicator batch check failed")
		} else {
			byValue := make(map[string]*models.Indicator, len(matches))
			for _, ind := range matches {
				byValue[ind.Value] = ind
			}
			for i := range conns {
				ind, ok := byValue[conns[i].RemoteAddress]
				if !ok {
					continue
				}
				conns[i].IsKnownBad = true
				conns[i].ThreatTags = appendUniqueTag(conns[i].ThreatTags, "threat_intel:"+string(ind.Severity))
				for _, tag := range ind.Tags {
					conns[i].ThreatTags = appendUniqueTag(conns[i].ThreatTags, tag)
				}
				if ind.Confidence > conns[i].ThreatConfidence {
					conns[i].ThreatConfidence = ind.Confidence
				}
			}
		}
	}

	// VirusTotal IP reputation for unique public remote IPs (bounded).
	if h.vt != nil && len(publicIPs) > 0 {
		vtCtx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
		defer cancel()

		reports := make(map[string]*desktop_security.VTIPReport)
		for _, ip := range publicIPs {
			if len(reports) >= maxVTIPLookups {
				break
			}
			report, err := h.vt.LookupIP(vtCtx, ip)
			if err != nil {
				h.logger.Debug().Err(err).Str("ip", ip).Msg("network analyze: VT IP lookup failed")
				if vtCtx.Err() != nil {
					break
				}
				continue
			}
			reports[ip] = report
		}

		for i := range conns {
			report, ok := reports[conns[i].RemoteAddress]
			if !ok {
				continue
			}
			if conns[i].RemoteCountry == "" {
				conns[i].RemoteCountry = report.Country
			}
			if conns[i].RemoteASN == "" && report.ASN != 0 {
				conns[i].RemoteASN = fmt.Sprintf("AS%d %s", report.ASN, report.ASOwner)
			}
			if report.IsKnownBad {
				conns[i].IsKnownBad = true
				conns[i].ThreatTags = appendUniqueTag(conns[i].ThreatTags,
					fmt.Sprintf("virustotal:%d_malicious_%d_suspicious", report.Malicious, report.Suspicious))
				if total := report.Malicious + report.Suspicious + report.Harmless + report.Undetected; total > 0 {
					ratio := float64(report.Malicious+report.Suspicious) / float64(total)
					if ratio > conns[i].ThreatConfidence {
						conns[i].ThreatConfidence = ratio
					}
				}
			}
		}
	}

	h.persistScanResults(r, repository.DesktopScanTypeNetwork, conns)

	flagged := 0
	for i := range conns {
		if conns[i].IsKnownBad || conns[i].IsCnC {
			flagged++
		}
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"connections": conns,
		"total":       len(conns),
		"flagged":     flagged,
		"analyzed_at": time.Now().UTC(),
	})
}

// AnalyzeBrowserExtensions handles POST /api/v1/desktop/browser/analyze.
//
// Desktop clients collect their locally installed browser extensions (the
// backend's browser scanner sees only the SERVER host) and upload them here
// for server-side risk assessment and known-malicious matching against the
// threat-intel indicator database. The assessed snapshot is persisted as the
// device's latest "browser" scan.
func (h *DesktopSecurityHandler) AnalyzeBrowserExtensions(w http.ResponseWriter, r *http.Request) {
	if h.browser == nil && h.indicators == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "no browser analysis capability configured"})
		return
	}

	var req struct {
		Extensions []models.BrowserExtension `json:"extensions"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || len(req.Extensions) == 0 {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "extensions are required"})
		return
	}
	exts := req.Extensions

	// Server-side risk assessment (permissions, store origin, known-bad IDs).
	if h.browser != nil {
		for i := range exts {
			h.browser.Assess(&exts[i])
		}
	}

	// Threat intel: match extension IDs against the indicator database.
	if h.indicators != nil {
		seen := make(map[string]bool, len(exts))
		ids := make([]string, 0, len(exts))
		for i := range exts {
			id := exts[i].ExtensionID
			if id == "" || seen[id] {
				continue
			}
			seen[id] = true
			ids = append(ids, id)
		}

		if len(ids) > 0 {
			matches, err := h.indicators.CheckBatch(r.Context(), ids)
			if err != nil {
				h.logger.Error().Err(err).Msg("browser analyze: indicator batch check failed")
			} else {
				byValue := make(map[string]*models.Indicator, len(matches))
				for _, ind := range matches {
					byValue[ind.Value] = ind
				}
				for i := range exts {
					ind, ok := byValue[exts[i].ExtensionID]
					if !ok {
						continue
					}
					exts[i].IsKnownMalware = true
					exts[i].RiskLevel = models.PersistenceRiskCritical
					reason := "Threat intel: known malicious extension"
					if ind.Description != "" {
						reason = "Threat intel: " + ind.Description
					}
					exts[i].RiskReasons = appendUniqueTag(exts[i].RiskReasons, reason)
				}
			}
		}
	}

	h.persistScanResults(r, repository.DesktopScanTypeBrowser, exts)

	highRisk := 0
	byBrowser := make(map[string]int)
	for i := range exts {
		byBrowser[exts[i].Browser]++
		if exts[i].IsKnownMalware ||
			exts[i].RiskLevel == models.PersistenceRiskHigh ||
			exts[i].RiskLevel == models.PersistenceRiskCritical {
			highRisk++
		}
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"extensions":  exts,
		"total":       len(exts),
		"high_risk":   highRisk,
		"by_browser":  byBrowser,
		"analyzed_at": time.Now().UTC(),
	})
}

// uniquePublicRemoteIPs returns the de-duplicated public, routable remote
// addresses from a connection list. Private/loopback/link-local addresses are
// excluded — they are meaningless to threat intel and VT.
func uniquePublicRemoteIPs(conns []models.NetworkConnection) []string {
	seen := make(map[string]bool, len(conns))
	var ips []string
	for i := range conns {
		addr := conns[i].RemoteAddress
		if addr == "" || seen[addr] || !isPublicRoutableIP(addr) {
			continue
		}
		seen[addr] = true
		ips = append(ips, addr)
	}
	return ips
}

// isPublicRoutableIP reports whether s parses as a public, routable IP.
func isPublicRoutableIP(s string) bool {
	ip := net.ParseIP(s)
	if ip == nil {
		return false
	}
	return !(ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() ||
		ip.IsLinkLocalMulticast() || ip.IsMulticast() || ip.IsUnspecified())
}

// appendUniqueTag appends tag to tags unless already present.
func appendUniqueTag(tags []string, tag string) []string {
	for _, t := range tags {
		if t == tag {
			return tags
		}
	}
	return append(tags, tag)
}
