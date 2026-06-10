package handlers

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// SMSHandler handles SMS analysis endpoints
type SMSHandler struct {
	analyzer *services.SMSAnalyzer
	repo     *repository.SMSRepository
	cache    *cache.RedisCache
	logger   *logger.Logger
}

// NewSMSHandler creates a new SMS handler
func NewSMSHandler(repos *repository.Repositories, cache *cache.RedisCache, log *logger.Logger) *SMSHandler {
	return &SMSHandler{
		analyzer: services.NewSMSAnalyzer(repos, cache, log),
		repo:     repository.NewSMSRepositoryFromRepos(repos),
		cache:    cache,
		logger:   log.WithComponent("sms-handler"),
	}
}

// AnalyzeRequest is the request body for SMS analysis
type AnalyzeRequest struct {
	Sender    string    `json:"sender"`
	Body      string    `json:"body"`
	Timestamp time.Time `json:"timestamp,omitempty"`
	DeviceID  string    `json:"device_id,omitempty"`
}

// AnalyzeBatchRequest is the request body for batch SMS analysis
type AnalyzeBatchRequest struct {
	Messages []AnalyzeRequest `json:"messages"`
	DeviceID string           `json:"device_id,omitempty"`
}

// hashSender returns the SHA-256 hex digest of a sender identifier.
// The raw sender is never persisted — only this hash.
func hashSender(sender string) string {
	sender = strings.TrimSpace(sender)
	if sender == "" {
		return ""
	}
	sum := sha256.Sum256([]byte(strings.ToLower(sender)))
	return hex.EncodeToString(sum[:])
}

// resolveDeviceID returns the device ID for the request: the authenticated
// device from the auth context takes precedence; service callers may supply
// an explicit device ID (request field or query parameter).
func resolveDeviceID(r *http.Request, explicit string) string {
	if id := middleware.GetDeviceID(r.Context()); id != "" {
		return id
	}
	if explicit != "" {
		return explicit
	}
	return r.URL.Query().Get("device_id")
}

// analysisCategories derives the persisted category list from an analysis
// result: threat type, intent flags and URL-based flags. Only derived
// metadata — never message content.
func analysisCategories(result *models.SMSAnalysisResult) []string {
	seen := make(map[string]bool)
	categories := []string{}
	add := func(c string) {
		if c == "" || seen[c] {
			return
		}
		seen[c] = true
		categories = append(categories, c)
	}

	add(string(result.ThreatType))
	if result.IntentAnalysis != nil {
		for _, flag := range result.IntentAnalysis.SuspiciousFlags {
			add(flag)
		}
	}
	for _, u := range result.URLs {
		if u.IsMalicious {
			add("malicious_url")
		}
		if u.IsShortened {
			add("shortened_url")
		}
	}
	if result.SenderAnalysis != nil && result.SenderAnalysis.IsSpoofed {
		add("spoofed_sender")
	}

	return categories
}

// persistAnalysis stores the analysis outcome. Persistence failures are
// logged but do not fail the analysis response — the analysis itself is
// still valid and returned to the caller.
func (h *SMSHandler) persistAnalysis(r *http.Request, msg *models.SMSMessage, result *models.SMSAnalysisResult) {
	if h.repo == nil {
		h.logger.Error().Msg("SMS analysis persistence unavailable: repository not configured")
		return
	}

	deviceID := resolveDeviceID(r, msg.DeviceID)
	if deviceID == "" {
		deviceID = "unknown"
	}

	rec := &repository.SMSAnalysisRecord{
		ID:          result.ID,
		DeviceID:    deviceID,
		SenderHash:  hashSender(msg.Sender),
		ThreatLevel: string(result.ThreatLevel),
		RiskScore:   result.Confidence,
		IsThreat:    result.IsThreat,
		Categories:  analysisCategories(result),
		AnalyzedAt:  result.AnalyzedAt,
	}

	if err := h.repo.InsertAnalysis(r.Context(), rec); err != nil {
		h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to persist SMS analysis")
	}
}

// Analyze handles POST /api/v1/sms/analyze - analyzes a single SMS message
func (h *SMSHandler) Analyze(w http.ResponseWriter, r *http.Request) {
	var req AnalyzeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.logger.Debug().Err(err).Msg("invalid request body")
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.Body == "" {
		http.Error(w, "Message body is required", http.StatusBadRequest)
		return
	}

	// Create SMS message
	msg := &models.SMSMessage{
		ID:        uuid.New(),
		Sender:    req.Sender,
		Body:      req.Body,
		Timestamp: req.Timestamp,
		DeviceID:  req.DeviceID,
	}

	if msg.Timestamp.IsZero() {
		msg.Timestamp = time.Now()
	}

	// Analyze
	result, err := h.analyzer.Analyze(r.Context(), msg)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to analyze SMS")
		http.Error(w, "Analysis failed", http.StatusInternalServerError)
		return
	}

	// Persist the outcome (hashed sender + derived fields only).
	h.persistAnalysis(r, msg, result)

	h.logger.Info().
		Bool("is_threat", result.IsThreat).
		Str("threat_level", string(result.ThreatLevel)).
		Str("threat_type", string(result.ThreatType)).
		Msg("SMS analyzed")

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

// AnalyzeBatch handles POST /api/v1/sms/analyze/batch - analyzes multiple SMS messages
func (h *SMSHandler) AnalyzeBatch(w http.ResponseWriter, r *http.Request) {
	var req AnalyzeBatchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.logger.Debug().Err(err).Msg("invalid request body")
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if len(req.Messages) == 0 {
		http.Error(w, "At least one message is required", http.StatusBadRequest)
		return
	}

	if len(req.Messages) > 100 {
		http.Error(w, "Maximum 100 messages per batch", http.StatusBadRequest)
		return
	}

	// Convert to models
	messages := make([]models.SMSMessage, len(req.Messages))
	for i, m := range req.Messages {
		messages[i] = models.SMSMessage{
			ID:        uuid.New(),
			Sender:    m.Sender,
			Body:      m.Body,
			Timestamp: m.Timestamp,
			DeviceID:  req.DeviceID,
		}
		if messages[i].Timestamp.IsZero() {
			messages[i].Timestamp = time.Now()
		}
	}

	// Analyze batch
	batchReq := &models.SMSBatchAnalysisRequest{
		Messages: messages,
		DeviceID: req.DeviceID,
	}

	result, err := h.analyzer.AnalyzeBatch(r.Context(), batchReq)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to analyze SMS batch")
		http.Error(w, "Analysis failed", http.StatusInternalServerError)
		return
	}

	// Persist all outcomes (hashed senders + derived fields only).
	h.persistBatch(r, messages, result)

	h.logger.Info().
		Int("total", result.TotalCount).
		Int("threats", result.ThreatCount).
		Msg("SMS batch analyzed")

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

// persistBatch stores all batch analysis outcomes in one database round trip.
func (h *SMSHandler) persistBatch(r *http.Request, messages []models.SMSMessage, result *models.SMSBatchAnalysisResult) {
	if h.repo == nil {
		h.logger.Error().Msg("SMS analysis persistence unavailable: repository not configured")
		return
	}

	// Index messages by ID so each result can be matched to its sender.
	senderByMsgID := make(map[uuid.UUID]string, len(messages))
	deviceByMsgID := make(map[uuid.UUID]string, len(messages))
	for _, m := range messages {
		senderByMsgID[m.ID] = m.Sender
		deviceByMsgID[m.ID] = m.DeviceID
	}

	recs := make([]repository.SMSAnalysisRecord, 0, len(result.Results))
	for i := range result.Results {
		res := &result.Results[i]

		deviceID := resolveDeviceID(r, deviceByMsgID[res.MessageID])
		if deviceID == "" {
			deviceID = "unknown"
		}

		recs = append(recs, repository.SMSAnalysisRecord{
			ID:          res.ID,
			DeviceID:    deviceID,
			SenderHash:  hashSender(senderByMsgID[res.MessageID]),
			ThreatLevel: string(res.ThreatLevel),
			RiskScore:   res.Confidence,
			IsThreat:    res.IsThreat,
			Categories:  analysisCategories(res),
			AnalyzedAt:  res.AnalyzedAt,
		})
	}

	if err := h.repo.InsertAnalysisBatch(r.Context(), recs); err != nil {
		h.logger.Error().Err(err).Int("count", len(recs)).Msg("failed to persist SMS batch analyses")
	}
}

// CheckURL handles POST /api/v1/sms/check-url - checks if a URL is malicious
func (h *SMSHandler) CheckURL(w http.ResponseWriter, r *http.Request) {
	var req struct {
		URL string `json:"url"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.URL == "" {
		http.Error(w, "URL is required", http.StatusBadRequest)
		return
	}

	// Create a minimal message with just the URL
	msg := &models.SMSMessage{
		ID:   uuid.New(),
		Body: req.URL,
	}

	// Analyze - the analyzer will extract and check the URL
	result, err := h.analyzer.Analyze(r.Context(), msg)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to check URL")
		http.Error(w, "Check failed", http.StatusInternalServerError)
		return
	}

	// Return just the URL analysis part
	response := struct {
		URL         string                   `json:"url"`
		IsMalicious bool                     `json:"is_malicious"`
		Category    models.URLCategory       `json:"category"`
		ThreatLevel models.ThreatLevel       `json:"threat_level"`
		Confidence  float64                  `json:"confidence"`
		Details     string                   `json:"details,omitempty"`
		URLs        []models.SMSExtractedURL `json:"urls,omitempty"`
	}{
		URL:         req.URL,
		IsMalicious: result.IsThreat,
		ThreatLevel: result.ThreatLevel,
		Confidence:  result.Confidence,
		URLs:        result.URLs,
	}

	if len(result.URLs) > 0 {
		response.Category = result.URLs[0].Category
		response.Details = result.URLs[0].ThreatDetails
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// GetPatterns handles GET /api/v1/sms/patterns - returns detection patterns for mobile
func (h *SMSHandler) GetPatterns(w http.ResponseWriter, r *http.Request) {
	// Return pattern info for mobile app to use for local detection
	patterns := struct {
		Version        string   `json:"version"`
		LastUpdated    string   `json:"last_updated"`
		UrgencyWords   []string `json:"urgency_words"`
		FearWords      []string `json:"fear_words"`
		RewardWords    []string `json:"reward_words"`
		PersonalWords  []string `json:"personal_words"`
		FinancialWords []string `json:"financial_words"`
		URLShorteners  []string `json:"url_shorteners"`
		SuspiciousTLDs []string `json:"suspicious_tlds"`
	}{
		Version:     "1.0.0",
		LastUpdated: time.Now().Format(time.RFC3339),
		UrgencyWords: []string{
			"urgent", "immediately", "now", "asap", "expire", "today only",
			"limited time", "act now", "don't wait", "hurry",
		},
		FearWords: []string{
			"suspended", "blocked", "limit", "unusual", "unauthorized",
			"fraud", "stolen", "hacked", "compromised", "alert", "warning",
			"verify your", "confirm your",
		},
		RewardWords: []string{
			"won", "winner", "prize", "gift", "free", "reward",
			"cash", "money", "bonus", "lucky",
		},
		PersonalWords: []string{
			"ssn", "social security", "password", "pin", "dob",
			"date of birth", "mother's maiden", "address",
		},
		FinancialWords: []string{
			"credit card", "debit card", "bank account", "routing number",
			"cvv", "expir", "billing",
		},
		URLShorteners: []string{
			"bit.ly", "tinyurl.com", "t.co", "goo.gl", "ow.ly",
			"is.gd", "buff.ly", "j.mp", "rb.gy", "cutt.ly",
		},
		SuspiciousTLDs: []string{
			".xyz", ".top", ".club", ".work", ".click", ".link",
			".gq", ".ml", ".cf", ".tk", ".ga",
		},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(patterns)
}

// GetStats handles GET /api/v1/sms/stats - returns SMS threat statistics
// aggregated from persisted analysis outcomes for the requesting device.
func (h *SMSHandler) GetStats(w http.ResponseWriter, r *http.Request) {
	if h.repo == nil {
		h.logger.Error().Msg("SMS stats unavailable: repository not configured")
		http.Error(w, "SMS statistics storage unavailable", http.StatusServiceUnavailable)
		return
	}

	// Per-device scoping: authenticated device from context; service
	// callers may scope explicitly via ?device_id=.
	deviceID := middleware.GetDeviceID(r.Context())
	if deviceID == "" && middleware.IsServiceRequest(r.Context()) {
		deviceID = r.URL.Query().Get("device_id")
	}
	if deviceID == "" {
		http.Error(w, "Device ID is required (authenticate as a device or pass device_id)", http.StatusBadRequest)
		return
	}

	stats, err := h.repo.GetDeviceStats(r.Context(), deviceID)
	if err != nil {
		h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to load SMS stats")
		http.Error(w, "Failed to load statistics", http.StatusInternalServerError)
		return
	}

	type windowStats struct {
		Analyzed int64 `json:"analyzed"`
		Threats  int64 `json:"threats"`
	}

	response := struct {
		DeviceID               string                     `json:"device_id"`
		TotalAnalyzed          int64                      `json:"total_analyzed"`
		ThreatsDetected        int64                      `json:"threats_detected"`
		ThreatsByType          map[string]int64           `json:"threats_by_type"`
		ThreatsByLevel         map[string]int64           `json:"threats_by_level"`
		FalsePositivesReported int64                      `json:"false_positives_reported"`
		Last24Hours            windowStats                `json:"last_24_hours"`
		Last30DaysTrend        []repository.SMSTrendPoint `json:"last_30_days_trend"`
		LastAnalyzedAt         *time.Time                 `json:"last_analyzed_at,omitempty"`
	}{
		DeviceID:               deviceID,
		TotalAnalyzed:          stats.TotalAnalyzed,
		ThreatsDetected:        stats.ThreatsDetected,
		ThreatsByType:          stats.ThreatsByType,
		ThreatsByLevel:         stats.ThreatsByLevel,
		FalsePositivesReported: stats.FalsePositives,
		Last24Hours: windowStats{
			Analyzed: stats.Last24hAnalyzed,
			Threats:  stats.Last24hThreats,
		},
		Last30DaysTrend: stats.Last30DaysTrend,
		LastAnalyzedAt:  stats.LastAnalyzedAt,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

var senderHashPattern = regexp.MustCompile(`^[0-9a-fA-F]{64}$`)

// ReportFalsePositiveRequest is the request body for false-positive reports.
type ReportFalsePositiveRequest struct {
	MessageID  string `json:"message_id,omitempty"`
	Sender     string `json:"sender,omitempty"`      // raw sender; hashed server-side
	SenderHash string `json:"sender_hash,omitempty"` // pre-hashed SHA-256 hex
	Reason     string `json:"reason,omitempty"`
	DeviceID   string `json:"device_id,omitempty"` // service callers only
}

// ReportFalsePositive handles POST /api/v1/sms/report-false-positive -
// records a user report that a message was incorrectly flagged.
func (h *SMSHandler) ReportFalsePositive(w http.ResponseWriter, r *http.Request) {
	if h.repo == nil {
		h.logger.Error().Msg("false-positive reporting unavailable: repository not configured")
		http.Error(w, "Report storage unavailable", http.StatusServiceUnavailable)
		return
	}

	var req ReportFalsePositiveRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Resolve the sender hash: prefer an explicit pre-computed hash,
	// otherwise hash the raw sender server-side (raw value is discarded).
	senderHash := strings.ToLower(strings.TrimSpace(req.SenderHash))
	if senderHash != "" && !senderHashPattern.MatchString(senderHash) {
		http.Error(w, "sender_hash must be a 64-character SHA-256 hex digest", http.StatusBadRequest)
		return
	}
	if senderHash == "" {
		senderHash = hashSender(req.Sender)
	}

	if req.MessageID == "" && senderHash == "" {
		http.Error(w, "At least one of message_id, sender or sender_hash is required", http.StatusBadRequest)
		return
	}

	deviceID := middleware.GetDeviceID(r.Context())
	if deviceID == "" && middleware.IsServiceRequest(r.Context()) {
		deviceID = req.DeviceID
	}
	if deviceID == "" {
		http.Error(w, "Device ID is required (authenticate as a device or pass device_id)", http.StatusBadRequest)
		return
	}

	rec := &repository.SMSFalsePositiveRecord{
		ID:         uuid.New(),
		DeviceID:   deviceID,
		MessageID:  req.MessageID,
		SenderHash: senderHash,
		Reason:     req.Reason,
		ReportedAt: time.Now().UTC(),
	}

	if err := h.repo.InsertFalsePositive(r.Context(), rec); err != nil {
		h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to record SMS false positive")
		http.Error(w, "Failed to record report", http.StatusInternalServerError)
		return
	}

	h.logger.Info().
		Str("device_id", deviceID).
		Str("report_id", rec.ID.String()).
		Msg("SMS false positive recorded")

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]any{
		"id":          rec.ID,
		"status":      "recorded",
		"reported_at": rec.ReportedAt,
	})
}
