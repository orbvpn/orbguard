package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services/desktop_security"
	"orbguard-lab/pkg/logger"
)

// DesktopSecurityDeps holds desktop security handler dependencies
type DesktopSecurityDeps struct {
	PersistenceScanner *desktop_security.PersistenceScanner
	CodeVerifier       *desktop_security.CodeSigningVerifier
	NetworkMonitor     *desktop_security.NetworkMonitor
	BrowserScanner     *desktop_security.BrowserExtensionScanner
	VTClient           *desktop_security.VirusTotalClient
	Logger             *logger.Logger
}

// DesktopSecurityHandler handles desktop security endpoints
type DesktopSecurityHandler struct {
	persistence *desktop_security.PersistenceScanner
	codesign    *desktop_security.CodeSigningVerifier
	network     *desktop_security.NetworkMonitor
	browser     *desktop_security.BrowserExtensionScanner
	vt          *desktop_security.VirusTotalClient
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
		logger:      deps.Logger.WithComponent("desktop-security-handler"),
	}
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
	respondJSON(w, http.StatusOK, result)
}

// ScanPath handles POST /api/v1/desktop/persistence/scan-path
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
	respondJSON(w, http.StatusOK, info)
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

// GetFirewallRules handles GET /api/v1/desktop/network/rules
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
