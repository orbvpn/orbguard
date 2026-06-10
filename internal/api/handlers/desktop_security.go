package handlers

import (
	"encoding/json"
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
	Logger  *logger.Logger
}

// DesktopSecurityHandler handles desktop security endpoints
type DesktopSecurityHandler struct {
	persistence *desktop_security.PersistenceScanner
	codesign    *desktop_security.CodeSigningVerifier
	network     *desktop_security.NetworkMonitor
	browser     *desktop_security.BrowserExtensionScanner
	vt          *desktop_security.VirusTotalClient
	results     *repository.DesktopResultsRepository
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
func (h *DesktopSecurityHandler) FullSecurityScan(w http.ResponseWriter, r *http.Request) {
	result := map[string]interface{}{
		"scan_type": "full",
	}

	if h.persistence != nil {
		if scan, err := h.persistence.Scan(r.Context()); err == nil {
			result["persistence"] = scan
			h.persistScanResults(r, repository.DesktopScanTypePersistence, scan.Items)
		}
	}
	if h.browser != nil {
		if exts, err := h.browser.Scan(r.Context()); err == nil {
			result["browser_extensions"] = exts
		}
	}
	if h.network != nil {
		if conns, err := h.network.GetConnections(r.Context()); err == nil {
			result["network_connections"] = len(conns)
		}
	}

	respondJSON(w, http.StatusOK, result)
}
