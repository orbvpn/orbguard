package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"orbguard-lab/internal/api/middleware"
	yaradet "orbguard-lab/internal/detection/yara"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// YARAHandler handles YARA-related HTTP requests
type YARAHandler struct {
	yaraService *services.YARAService
	// parser is the same rule parser/compiler used by the live scan path;
	// ParseRule and SubmitRule validate through it so results are real.
	parser      *yaradet.Loader
	submissions *repository.YARASubmissionRepository
	logger      *logger.Logger
}

// NewYARAHandler creates a new YARA handler
func NewYARAHandler(yaraService *services.YARAService, log *logger.Logger) *YARAHandler {
	return &YARAHandler{
		yaraService: yaraService,
		parser:      yaradet.NewLoader(log),
		logger:      log.WithComponent("yara-handler"),
	}
}

// WithRepositories wires the database-backed submission store. When the
// repositories are unavailable, submission endpoints return an explicit 503.
func (h *YARAHandler) WithRepositories(repos *repository.Repositories) *YARAHandler {
	h.submissions = repository.NewYARASubmissionRepositoryFromRepos(repos)
	return h
}

// respondJSON sends a JSON response
func (h *YARAHandler) respondJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

// respondError sends an error response
func (h *YARAHandler) respondError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"error": message})
}

// Scan performs a YARA scan on provided data
// @Summary Scan data with YARA rules
// @Description Scan binary data, base64, or hex-encoded data against YARA rules
// @Tags yara
// @Accept json
// @Produce json
// @Param body body models.YARAScanRequest true "Scan request"
// @Success 200 {object} models.YARAScanResult
// @Router /api/v1/yara/scan [post]
func (h *YARAHandler) Scan(w http.ResponseWriter, r *http.Request) {
	var req models.YARAScanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	// Validate request has data
	if len(req.Data) == 0 && req.Base64Data == "" && req.HexData == "" && req.FilePath == "" {
		h.respondError(w, http.StatusBadRequest, "no data provided for scanning")
		return
	}

	result, err := h.yaraService.Scan(r.Context(), &req)
	if err != nil {
		h.logger.Error().Err(err).Msg("YARA scan failed")
		h.respondError(w, http.StatusInternalServerError, "scan failed: "+err.Error())
		return
	}

	h.respondJSON(w, http.StatusOK, result)
}

// ScanAPK scans an Android APK
// @Summary Scan APK with YARA rules
// @Description Scan an Android APK file for malware indicators
// @Tags yara
// @Accept json
// @Produce json
// @Param body body ScanAPKRequest true "APK scan request"
// @Success 200 {object} models.YARAScanResult
// @Router /api/v1/yara/scan/apk [post]
func (h *YARAHandler) ScanAPK(w http.ResponseWriter, r *http.Request) {
	var req ScanAPKRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.Base64Data == "" && len(req.Data) == 0 {
		h.respondError(w, http.StatusBadRequest, "APK data is required")
		return
	}

	scanReq := &models.YARAScanRequest{
		Data:        req.Data,
		Base64Data:  req.Base64Data,
		PackageName: req.PackageName,
		Platform:    "android",
		FileType:    "apk",
	}

	result, err := h.yaraService.Scan(r.Context(), scanReq)
	if err != nil {
		h.logger.Error().Err(err).Str("package", req.PackageName).Msg("APK scan failed")
		h.respondError(w, http.StatusInternalServerError, "scan failed")
		return
	}

	h.respondJSON(w, http.StatusOK, result)
}

// ScanAPKRequest represents a request to scan an APK
type ScanAPKRequest struct {
	Data        []byte `json:"data,omitempty"`
	Base64Data  string `json:"base64_data,omitempty"`
	PackageName string `json:"package_name,omitempty"`
}

// ScanIPA scans an iOS IPA
// @Summary Scan IPA with YARA rules
// @Description Scan an iOS IPA file for malware indicators
// @Tags yara
// @Accept json
// @Produce json
// @Param body body ScanIPARequest true "IPA scan request"
// @Success 200 {object} models.YARAScanResult
// @Router /api/v1/yara/scan/ipa [post]
func (h *YARAHandler) ScanIPA(w http.ResponseWriter, r *http.Request) {
	var req ScanIPARequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.Base64Data == "" && len(req.Data) == 0 {
		h.respondError(w, http.StatusBadRequest, "IPA data is required")
		return
	}

	scanReq := &models.YARAScanRequest{
		Data:        req.Data,
		Base64Data:  req.Base64Data,
		PackageName: req.BundleID,
		Platform:    "ios",
		FileType:    "ipa",
	}

	result, err := h.yaraService.Scan(r.Context(), scanReq)
	if err != nil {
		h.logger.Error().Err(err).Str("bundle", req.BundleID).Msg("IPA scan failed")
		h.respondError(w, http.StatusInternalServerError, "scan failed")
		return
	}

	h.respondJSON(w, http.StatusOK, result)
}

// ScanIPARequest represents a request to scan an IPA
type ScanIPARequest struct {
	Data       []byte `json:"data,omitempty"`
	Base64Data string `json:"base64_data,omitempty"`
	BundleID   string `json:"bundle_id,omitempty"`
}

// ListRules returns all YARA rules
// @Summary List YARA rules
// @Description Get all loaded YARA detection rules
// @Tags yara
// @Accept json
// @Produce json
// @Param category query string false "Filter by category"
// @Param severity query string false "Filter by severity"
// @Param platform query string false "Filter by platform"
// @Param limit query int false "Limit results" default(50)
// @Param offset query int false "Offset for pagination" default(0)
// @Success 200 {object} ListRulesResponse
// @Router /api/v1/yara/rules [get]
func (h *YARAHandler) ListRules(w http.ResponseWriter, r *http.Request) {
	filter := &models.YARARuleFilter{}

	// Parse query parameters
	if cat := r.URL.Query().Get("category"); cat != "" {
		filter.Categories = []models.YARARuleCategory{models.YARARuleCategory(cat)}
	}
	if sev := r.URL.Query().Get("severity"); sev != "" {
		filter.Severities = []models.Severity{models.Severity(sev)}
	}
	if platform := r.URL.Query().Get("platform"); platform != "" {
		filter.Platforms = []string{platform}
	}

	limit := 50
	if l := r.URL.Query().Get("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil && parsed > 0 && parsed <= 200 {
			limit = parsed
		}
	}
	filter.Limit = limit

	offset := 0
	if o := r.URL.Query().Get("offset"); o != "" {
		if parsed, err := strconv.Atoi(o); err == nil && parsed >= 0 {
			offset = parsed
		}
	}
	filter.Offset = offset

	rules := h.yaraService.GetRules(filter)

	h.respondJSON(w, http.StatusOK, ListRulesResponse{
		Rules: rules,
		Total: len(rules),
		Limit: limit,
		Offset: offset,
	})
}

// ListRulesResponse represents the response for listing rules
type ListRulesResponse struct {
	Rules  []*models.YARARule `json:"rules"`
	Total  int                `json:"total"`
	Limit  int                `json:"limit"`
	Offset int                `json:"offset"`
}

// GetRule returns a specific YARA rule
// @Summary Get YARA rule
// @Description Get a specific YARA rule by ID
// @Tags yara
// @Accept json
// @Produce json
// @Param id path string true "Rule UUID"
// @Success 200 {object} models.YARARule
// @Router /api/v1/yara/rules/{id} [get]
func (h *YARAHandler) GetRule(w http.ResponseWriter, r *http.Request) {
	idStr := chi.URLParam(r, "id")
	ruleID, err := uuid.Parse(idStr)
	if err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid rule ID")
		return
	}

	rule := h.yaraService.GetRule(ruleID)
	if rule == nil {
		h.respondError(w, http.StatusNotFound, "rule not found")
		return
	}

	h.respondJSON(w, http.StatusOK, rule)
}

// AddRule adds a new YARA rule
// @Summary Add YARA rule
// @Description Add a new YARA detection rule
// @Tags yara
// @Accept json
// @Produce json
// @Param body body models.YARARule true "Rule to add"
// @Success 201 {object} models.YARARule
// @Router /api/v1/yara/rules [post]
func (h *YARAHandler) AddRule(w http.ResponseWriter, r *http.Request) {
	var rule models.YARARule
	if err := json.NewDecoder(r.Body).Decode(&rule); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	// Generate ID if not provided
	if rule.ID == uuid.Nil {
		rule.ID = uuid.New()
	}

	if err := h.yaraService.AddRule(&rule); err != nil {
		h.logger.Error().Err(err).Str("rule", rule.Name).Msg("failed to add rule")
		h.respondError(w, http.StatusBadRequest, err.Error())
		return
	}

	h.respondJSON(w, http.StatusCreated, rule)
}

// DeleteRule removes a YARA rule
// @Summary Delete YARA rule
// @Description Remove a YARA detection rule
// @Tags yara
// @Accept json
// @Produce json
// @Param id path string true "Rule UUID"
// @Success 204 "No Content"
// @Router /api/v1/yara/rules/{id} [delete]
func (h *YARAHandler) DeleteRule(w http.ResponseWriter, r *http.Request) {
	idStr := chi.URLParam(r, "id")
	ruleID, err := uuid.Parse(idStr)
	if err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid rule ID")
		return
	}

	if err := h.yaraService.RemoveRule(ruleID); err != nil {
		h.respondError(w, http.StatusInternalServerError, "failed to remove rule")
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// ParseRule parses and validates a YARA rule without adding it
// @Summary Parse YARA rule
// @Description Parse and validate a YARA rule string
// @Tags yara
// @Accept json
// @Produce json
// @Param body body ParseRuleRequest true "Rule to parse"
// @Success 200 {object} ParseRuleResponse
// @Router /api/v1/yara/parse [post]
func (h *YARAHandler) ParseRule(w http.ResponseWriter, r *http.Request) {
	var req ParseRuleRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.RuleContent == "" {
		h.respondError(w, http.StatusBadRequest, "rule_content is required")
		return
	}

	// Validate using the same parser and pattern compiler the live
	// /yara/scan path uses (internal/detection/yara), so a rule that
	// validates here is guaranteed to load into the engine.
	validation := h.parser.ValidateSource(req.RuleContent)

	resp := ParseRuleResponse{
		Valid:    validation.Valid,
		Errors:   validation.Errors,
		Warnings: validation.Warnings,
		Rules:    validation.Rules,
	}
	if validation.Valid {
		resp.Message = "rule parsed and compiled successfully"
	} else {
		resp.Message = "rule validation failed"
		if len(validation.Errors) > 0 {
			resp.Error = validation.Errors[0]
		}
	}

	h.respondJSON(w, http.StatusOK, resp)
}

// ParseRuleRequest represents a request to parse a rule
type ParseRuleRequest struct {
	RuleContent string `json:"rule_content"`
}

// ParseRuleResponse represents the response from parsing a rule
type ParseRuleResponse struct {
	Valid    bool                   `json:"valid"`
	Message  string                 `json:"message,omitempty"`
	Errors   []string               `json:"errors,omitempty"`
	Warnings []string               `json:"warnings,omitempty"`
	Rules    []yaradet.RuleMetadata `json:"rules,omitempty"`
	// Error carries the first error for backwards compatibility with
	// clients that read a single error string.
	Error string `json:"error,omitempty"`
}

// ReloadRules reloads all YARA rules
// @Summary Reload YARA rules
// @Description Reload all YARA rules from disk and built-in sources
// @Tags yara
// @Accept json
// @Produce json
// @Success 200 {object} map[string]string
// @Router /api/v1/yara/reload [post]
func (h *YARAHandler) ReloadRules(w http.ResponseWriter, r *http.Request) {
	if err := h.yaraService.ReloadRules(); err != nil {
		h.logger.Error().Err(err).Msg("failed to reload rules")
		h.respondError(w, http.StatusInternalServerError, "failed to reload rules")
		return
	}

	h.respondJSON(w, http.StatusOK, map[string]string{
		"status":  "success",
		"message": "rules reloaded",
	})
}

// GetStats returns YARA scanning statistics
// @Summary Get YARA statistics
// @Description Get YARA scanning and rule statistics
// @Tags yara
// @Accept json
// @Produce json
// @Success 200 {object} models.YARAScanStats
// @Router /api/v1/yara/stats [get]
func (h *YARAHandler) GetStats(w http.ResponseWriter, r *http.Request) {
	stats := h.yaraService.GetStats()
	h.respondJSON(w, http.StatusOK, stats)
}

// GetCategories returns available rule categories
// @Summary Get rule categories
// @Description Get list of available YARA rule categories
// @Tags yara
// @Accept json
// @Produce json
// @Success 200 {array} CategoryInfo
// @Router /api/v1/yara/categories [get]
func (h *YARAHandler) GetCategories(w http.ResponseWriter, r *http.Request) {
	categories := []CategoryInfo{
		{ID: "pegasus", Name: "Pegasus", Description: "NSO Group Pegasus spyware detection"},
		{ID: "stalkerware", Name: "Stalkerware", Description: "Commercial stalkerware/spouseware detection"},
		{ID: "spyware", Name: "Spyware", Description: "Generic spyware detection"},
		{ID: "trojan", Name: "Trojan", Description: "Trojan/RAT detection"},
		{ID: "ransomware", Name: "Ransomware", Description: "Ransomware detection"},
		{ID: "adware", Name: "Adware", Description: "Aggressive adware detection"},
		{ID: "rootkit", Name: "Rootkit", Description: "Rootkit detection"},
		{ID: "exploit", Name: "Exploit", Description: "Exploit/vulnerability detection"},
		{ID: "generic", Name: "Generic", Description: "Generic malware detection"},
	}

	h.respondJSON(w, http.StatusOK, categories)
}

// CategoryInfo represents information about a rule category
type CategoryInfo struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
}

// SubmitRule handles user-submitted rules
// @Summary Submit YARA rule
// @Description Submit a new YARA rule for review
// @Tags yara
// @Accept json
// @Produce json
// @Param body body models.YARARuleSubmission true "Rule submission"
// @Success 201 {object} map[string]string
// @Router /api/v1/yara/submit [post]
func (h *YARAHandler) SubmitRule(w http.ResponseWriter, r *http.Request) {
	var submission models.YARARuleSubmission
	if err := json.NewDecoder(r.Body).Decode(&submission); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	// Validate required fields
	if submission.RawRule == "" {
		h.respondError(w, http.StatusBadRequest, "raw_rule is required")
		return
	}
	if submission.Name == "" {
		h.respondError(w, http.StatusBadRequest, "name is required")
		return
	}

	if h.submissions == nil {
		h.logger.Error().Str("path", r.URL.Path).
			Msg("yara submission repository not configured; submission endpoint unavailable")
		h.respondError(w, http.StatusServiceUnavailable, "rule submission storage is not configured")
		return
	}

	// Validate first with the real parser/compiler; invalid rules are
	// rejected immediately with the actual parse errors and not stored.
	validation := h.parser.ValidateSource(submission.RawRule)
	if !validation.Valid {
		h.respondJSON(w, http.StatusUnprocessableEntity, map[string]any{
			"error":    "rule validation failed",
			"errors":   validation.Errors,
			"warnings": validation.Warnings,
		})
		return
	}

	validationJSON, err := json.Marshal(validation)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to encode validation result")
		h.respondError(w, http.StatusInternalServerError, "failed to encode validation result")
		return
	}

	// Submitter identity from the auth context (user or device token).
	submittedBy := middleware.GetUserID(r.Context())
	if submittedBy == "" {
		submittedBy = middleware.GetDeviceID(r.Context())
	}

	stored, err := h.submissions.Create(r.Context(), submission.Name, submission.RawRule, submittedBy, validationJSON)
	if err != nil {
		h.logger.Error().Err(err).Str("name", submission.Name).Msg("failed to store rule submission")
		h.respondError(w, http.StatusInternalServerError, "failed to store rule submission")
		return
	}

	h.logger.Info().
		Str("submission_id", stored.ID.String()).
		Str("name", submission.Name).
		Int("rules", len(validation.Rules)).
		Msg("stored rule submission for review")

	h.respondJSON(w, http.StatusCreated, map[string]any{
		"status":        "pending",
		"submission_id": stored.ID.String(),
		"message":       "rule validated and submitted for review",
		"warnings":      validation.Warnings,
	})
}

// submissionStoreAvailable returns true when the submission repository is
// wired; otherwise it writes an explicit 503 and logs the gap.
func (h *YARAHandler) submissionStoreAvailable(w http.ResponseWriter, r *http.Request) bool {
	if h.submissions == nil {
		h.logger.Error().Str("path", r.URL.Path).
			Msg("yara submission repository not configured; admin submission endpoint unavailable")
		h.respondError(w, http.StatusServiceUnavailable, "rule submission storage is not configured")
		return false
	}
	return true
}

// ListSubmissions handles GET /api/v1/admin/yara/submissions
// Lists community rule submissions filtered by status (default: pending).
func (h *YARAHandler) ListSubmissions(w http.ResponseWriter, r *http.Request) {
	if !h.submissionStoreAvailable(w, r) {
		return
	}

	status := r.URL.Query().Get("status")
	if status == "" {
		status = string(models.SubmissionStatusPending)
	}
	switch models.SubmissionStatus(status) {
	case models.SubmissionStatusPending, models.SubmissionStatusApproved, models.SubmissionStatusRejected:
	default:
		h.respondError(w, http.StatusBadRequest, "invalid status: must be one of pending, approved, rejected")
		return
	}

	limit, offset := parsePagination(r, 50, 200)

	submissions, total, err := h.submissions.ListByStatus(r.Context(), status, limit, offset)
	if err != nil {
		h.logger.Error().Err(err).Str("status", status).Msg("failed to list rule submissions")
		h.respondError(w, http.StatusInternalServerError, "failed to list submissions")
		return
	}

	h.respondJSON(w, http.StatusOK, map[string]any{
		"data":   submissions,
		"total":  total,
		"status": status,
		"limit":  limit,
		"offset": offset,
	})
}

// loadPendingSubmission fetches a submission and verifies it is still
// pending. It writes the error response itself and returns nil on failure.
func (h *YARAHandler) loadPendingSubmission(w http.ResponseWriter, r *http.Request) *repository.YARASubmission {
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid submission id")
		return nil
	}

	submission, err := h.submissions.GetByID(r.Context(), id)
	if err != nil {
		h.logger.Error().Err(err).Str("submission_id", id.String()).Msg("failed to load rule submission")
		h.respondError(w, http.StatusInternalServerError, "failed to load submission")
		return nil
	}
	if submission == nil {
		h.respondError(w, http.StatusNotFound, "submission not found")
		return nil
	}
	if submission.Status != string(models.SubmissionStatusPending) {
		h.respondError(w, http.StatusConflict, "submission has already been reviewed (status: "+submission.Status+")")
		return nil
	}
	return submission
}

// ApproveSubmission handles POST /api/v1/admin/yara/submissions/{id}/approve
// Re-validates the stored rule text, loads the rule(s) into the live engine
// via the service's dynamic-load path (YARAService.AddRule), and marks the
// submission approved.
//
// NOTE: the engine load is per-process. Approved rules persist in
// orbguard_lab.yara_submissions but are not automatically re-loaded into the
// engine after a restart; the response states this explicitly.
func (h *YARAHandler) ApproveSubmission(w http.ResponseWriter, r *http.Request) {
	if !h.submissionStoreAvailable(w, r) {
		return
	}

	submission := h.loadPendingSubmission(w, r)
	if submission == nil {
		return
	}

	var body struct {
		Notes string `json:"notes,omitempty"`
	}
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&body)
	}

	// Re-parse the stored text; this also guards against rules that were
	// valid at submission time but fail under a newer compiler.
	rules, err := h.parser.ParseRules(submission.RuleText)
	if err != nil || len(rules) == 0 {
		h.logger.Error().Err(err).Str("submission_id", submission.ID.String()).
			Msg("stored submission no longer parses; cannot approve")
		h.respondError(w, http.StatusUnprocessableEntity, "stored rule text no longer parses; cannot approve")
		return
	}

	loaded := make([]string, 0, len(rules))
	for _, rule := range rules {
		if rule.ID == uuid.Nil {
			rule.ID = uuid.New()
		}
		if err := h.yaraService.AddRule(rule); err != nil {
			h.logger.Error().Err(err).
				Str("submission_id", submission.ID.String()).
				Str("rule", rule.Name).
				Msg("failed to load approved rule into live engine")
			h.respondError(w, http.StatusUnprocessableEntity, "rule failed engine validation: "+err.Error())
			return
		}
		loaded = append(loaded, rule.Name)
	}

	reviewer := adminIdentity(r.Context())
	if err := h.submissions.UpdateStatus(r.Context(), submission.ID, string(models.SubmissionStatusApproved), reviewer, body.Notes); err != nil {
		h.logger.Error().Err(err).Str("submission_id", submission.ID.String()).Msg("failed to mark submission approved")
		h.respondError(w, http.StatusInternalServerError, "failed to update submission status")
		return
	}

	h.logger.Info().
		Str("submission_id", submission.ID.String()).
		Strs("rules", loaded).
		Str("reviewer", reviewer).
		Msg("submission approved; rules loaded into live engine")

	h.respondJSON(w, http.StatusOK, map[string]any{
		"success":       true,
		"submission_id": submission.ID.String(),
		"rules_loaded":  loaded,
		"message": "submission approved; rule(s) loaded into the live engine of this instance. " +
			"Approved rules are persisted but are not automatically re-loaded after a process restart.",
	})
}

// RejectSubmission handles POST /api/v1/admin/yara/submissions/{id}/reject
func (h *YARAHandler) RejectSubmission(w http.ResponseWriter, r *http.Request) {
	if !h.submissionStoreAvailable(w, r) {
		return
	}

	submission := h.loadPendingSubmission(w, r)
	if submission == nil {
		return
	}

	var body struct {
		Notes string `json:"notes,omitempty"`
	}
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&body)
	}

	reviewer := adminIdentity(r.Context())
	if err := h.submissions.UpdateStatus(r.Context(), submission.ID, string(models.SubmissionStatusRejected), reviewer, body.Notes); err != nil {
		h.logger.Error().Err(err).Str("submission_id", submission.ID.String()).Msg("failed to mark submission rejected")
		h.respondError(w, http.StatusInternalServerError, "failed to update submission status")
		return
	}

	h.logger.Info().
		Str("submission_id", submission.ID.String()).
		Str("reviewer", reviewer).
		Msg("submission rejected")

	h.respondJSON(w, http.StatusOK, map[string]any{
		"success":       true,
		"submission_id": submission.ID.String(),
		"message":       "submission rejected",
	})
}

// QuickScan performs a quick scan with text/string data
// @Summary Quick scan
// @Description Perform a quick YARA scan on text data
// @Tags yara
// @Accept json
// @Produce json
// @Param body body QuickScanRequest true "Quick scan request"
// @Success 200 {object} models.YARAScanResult
// @Router /api/v1/yara/quick-scan [post]
func (h *YARAHandler) QuickScan(w http.ResponseWriter, r *http.Request) {
	var req QuickScanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.Content == "" {
		h.respondError(w, http.StatusBadRequest, "content is required")
		return
	}

	scanReq := &models.YARAScanRequest{
		Data:     []byte(req.Content),
		FileName: "quick-scan",
	}

	// Apply filters
	if req.Category != "" {
		scanReq.Categories = []models.YARARuleCategory{models.YARARuleCategory(req.Category)}
	}
	if req.Platform != "" {
		scanReq.Platform = req.Platform
	}

	result, err := h.yaraService.Scan(r.Context(), scanReq)
	if err != nil {
		h.logger.Error().Err(err).Msg("quick scan failed")
		h.respondError(w, http.StatusInternalServerError, "scan failed")
		return
	}

	h.respondJSON(w, http.StatusOK, result)
}

// QuickScanRequest represents a quick scan request
type QuickScanRequest struct {
	Content  string `json:"content"`
	Category string `json:"category,omitempty"`
	Platform string `json:"platform,omitempty"`
}
