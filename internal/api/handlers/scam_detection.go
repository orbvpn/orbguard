package handlers

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services/ai"
	"orbguard-lab/pkg/logger"
)

// ScamDetectionHandler handles AI-powered scam detection endpoints
type ScamDetectionHandler struct {
	detector *ai.ScamDetector
	logger   *logger.Logger
}

// NewScamDetectionHandler creates a new ScamDetectionHandler
func NewScamDetectionHandler(log *logger.Logger, detector *ai.ScamDetector) *ScamDetectionHandler {
	return &ScamDetectionHandler{
		detector: detector,
		logger:   log.WithComponent("scam-detection-handler"),
	}
}

// RegisterRoutes registers scam detection routes
func (h *ScamDetectionHandler) RegisterRoutes(r chi.Router) {
	r.Route("/scam", func(scam chi.Router) {
		scam.Post("/analyze", h.Analyze)
		scam.Get("/patterns", h.GetPatterns)
		scam.Post("/report", h.Report)
		scam.Get("/phone/{number}", h.GetPhoneReputation)
		scam.Post("/phone/report", h.ReportPhone)
	})
}

// Analyze handles POST /api/v1/scam/analyze
func (h *ScamDetectionHandler) Analyze(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Content     string `json:"content"`
		ContentType string `json:"content_type"`
		Sender      string `json:"sender,omitempty"`
		PhoneNumber string `json:"phone_number,omitempty"`
		URL         string `json:"url,omitempty"`
		Language    string `json:"language,omitempty"`
		DeviceID    string `json:"device_id,omitempty"`
		MimeType    string `json:"mime_type,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	if req.Content == "" {
		http.Error(w, `{"error":"content is required"}`, http.StatusBadRequest)
		return
	}

	// Build ScamAnalysisRequest
	analysisReq := &models.ScamAnalysisRequest{
		ID:          uuid.New().String(),
		Content:     req.Content,
		ContentType: models.ContentType(req.ContentType),
		URL:         req.URL,
		PhoneNumber: req.PhoneNumber,
		Language:    req.Language,
		DeviceID:    req.DeviceID,
		Timestamp:   time.Now(),
	}
	if req.Sender != "" {
		analysisReq.SenderInfo = &models.SenderInfo{
			PhoneNumber: req.Sender,
		}
	}

	// Default to text content type
	if analysisReq.ContentType == "" {
		analysisReq.ContentType = models.ContentTypeText
	}

	// For image/voice analysis the client sends the media base64-encoded in
	// `content` (the model documents Content as "text content or base64 for
	// images"). Decode it into the raw byte fields the detector consumes.
	if analysisReq.ContentType == models.ContentTypeImage ||
		analysisReq.ContentType == models.ContentTypeVoice {
		data, err := base64.StdEncoding.DecodeString(req.Content)
		if err != nil {
			http.Error(w, `{"error":"content must be base64-encoded for image/voice analysis"}`, http.StatusBadRequest)
			return
		}
		analysisReq.MimeType = req.MimeType
		if analysisReq.ContentType == models.ContentTypeImage {
			analysisReq.ImageData = data
		} else {
			analysisReq.AudioData = data
		}
		// The base64 blob is not text; don't run language detection on it.
		analysisReq.Content = ""
	}

	result, err := h.detector.Analyze(r.Context(), analysisReq)
	if err != nil {
		h.logger.Error().Err(err).Msg("scam analysis failed")
		// Do NOT fabricate a "safe" verdict on failure — surface the error so
		// clients can show an error state instead of a false negative.
		w.Header().Set("Content-Type", "application/json")
		msg := err.Error()
		if strings.Contains(msg, "not enabled") {
			// Vision/speech analyzers are config-gated: this is a capability
			// gap, not a server fault — surface it as a typed 503.
			w.WriteHeader(http.StatusServiceUnavailable)
			json.NewEncoder(w).Encode(map[string]interface{}{
				"error": msg,
				"code":  "analyzer_not_enabled",
			})
			return
		}
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"error": "scam analysis failed",
		})
		return
	}

	h.logger.Info().
		Bool("is_scam", result.IsScam).
		Float64("score", result.RiskScore).
		Str("type", string(result.ScamType)).
		Msg("scam analyzed")

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

// GetPatterns handles GET /api/v1/scam/patterns
func (h *ScamDetectionHandler) GetPatterns(w http.ResponseWriter, r *http.Request) {
	patterns := map[string]interface{}{
		"version":      "1.0.0",
		"last_updated": time.Now().UTC().Format(time.RFC3339),
		"scam_types": []map[string]interface{}{
			{"type": "phishing", "description": "Attempts to steal personal information through fake communications", "indicators": []string{"urgency", "fake links", "personal info requests"}},
			{"type": "romance", "description": "Emotional manipulation for financial gain", "indicators": []string{"quick emotional connection", "financial requests", "avoids meeting"}},
			{"type": "investment", "description": "Fake investment opportunities promising high returns", "indicators": []string{"guaranteed returns", "urgency to invest", "unregistered platform"}},
			{"type": "tech_support", "description": "Fake technical support claiming device issues", "indicators": []string{"unsolicited contact", "remote access requests", "payment demands"}},
			{"type": "lottery", "description": "Fake lottery or prize winning notifications", "indicators": []string{"unexpected prize", "fee to claim", "urgency"}},
			{"type": "impersonation", "description": "Impersonating a known person, company, or authority", "indicators": []string{"authority claim", "unusual requests", "pressure tactics"}},
			{"type": "shipping", "description": "Fake delivery notifications with malicious links", "indicators": []string{"unexpected package", "tracking link", "fee required"}},
			{"type": "banking", "description": "Fake banking alerts to steal credentials", "indicators": []string{"account alert", "verify identity", "suspicious link"}},
		},
		"risk_indicators": []string{
			"urgency_pressure", "financial_request", "personal_info_request",
			"suspicious_links", "grammar_errors", "too_good_to_be_true",
			"emotional_manipulation", "authority_impersonation",
			"unsolicited_contact", "payment_unusual_method",
		},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(patterns)
}

// Report handles POST /api/v1/scam/report
func (h *ScamDetectionHandler) Report(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Content     string `json:"content"`
		ContentType string `json:"content_type"`
		ScamType    string `json:"scam_type"`
		PhoneNumber string `json:"phone_number,omitempty"`
		URL         string `json:"url,omitempty"`
		Description string `json:"description,omitempty"`
		DeviceID    string `json:"device_id,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	if req.Content == "" && req.PhoneNumber == "" && req.URL == "" {
		http.Error(w, `{"error":"at least content, phone_number, or url is required"}`, http.StatusBadRequest)
		return
	}

	report := &models.ScamReport{
		ID:          uuid.New(),
		ContentType: models.ContentType(req.ContentType),
		Content:     req.Content,
		URL:         req.URL,
		PhoneNumber: req.PhoneNumber,
		ScamType:    models.ScamType(req.ScamType),
		Description: req.Description,
		ReportedAt:  time.Now(),
	}

	if err := h.detector.ReportScam(r.Context(), report); err != nil {
		h.logger.Warn().Err(err).Msg("failed to process scam report")
	}

	h.logger.Info().
		Str("content_type", req.ContentType).
		Str("scam_type", req.ScamType).
		Msg("scam reported")

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message":     "Scam report submitted successfully",
		"reported_at": time.Now().UTC().Format(time.RFC3339),
	})
}

// GetPhoneReputation handles GET /api/v1/scam/phone/{number}
func (h *ScamDetectionHandler) GetPhoneReputation(w http.ResponseWriter, r *http.Request) {
	number := chi.URLParam(r, "number")
	if number == "" {
		http.Error(w, `{"error":"phone number is required"}`, http.StatusBadRequest)
		return
	}

	// Analyze as phone content type
	analysisReq := &models.ScamAnalysisRequest{
		ID:          uuid.New().String(),
		Content:     number,
		ContentType: models.ContentTypePhone,
		PhoneNumber: number,
		Timestamp:   time.Now(),
	}

	result, err := h.detector.Analyze(r.Context(), analysisReq)
	if err != nil {
		h.logger.Error().Err(err).Str("number", number).Msg("phone reputation lookup failed")
		// Do NOT fabricate a clean reputation on failure — surface the error
		// so clients can show an error state instead of a false "clean".
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"error": "phone reputation lookup failed",
		})
		return
	}

	resp := map[string]interface{}{
		"phone_number":     number,
		"reputation_score": 100 - (result.RiskScore * 100),
		"is_scam":          result.IsScam,
		"is_suspicious":    result.RiskScore >= 0.4,
		"risk_score":       result.RiskScore,
		"scam_type":        result.ScamType,
		"severity":         result.Severity,
		"explanation":      result.Explanation,
		"indicators":       result.Indicators,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// ReportPhone handles POST /api/v1/scam/phone/report
func (h *ScamDetectionHandler) ReportPhone(w http.ResponseWriter, r *http.Request) {
	var req struct {
		PhoneNumber string `json:"phone_number"`
		ScamType    string `json:"scam_type"`
		Description string `json:"description,omitempty"`
		DeviceID    string `json:"device_id,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	if req.PhoneNumber == "" {
		http.Error(w, `{"error":"phone_number is required"}`, http.StatusBadRequest)
		return
	}

	report := &models.ScamReport{
		ID:          uuid.New(),
		ContentType: models.ContentTypePhone,
		Content:     req.PhoneNumber,
		PhoneNumber: req.PhoneNumber,
		ScamType:    models.ScamType(req.ScamType),
		Description: req.Description,
		ReportedAt:  time.Now(),
	}

	if err := h.detector.ReportScam(r.Context(), report); err != nil {
		h.logger.Warn().Err(err).Msg("failed to process phone report")
	}

	h.logger.Info().
		Str("phone", req.PhoneNumber).
		Str("scam_type", req.ScamType).
		Msg("phone number reported as scam")

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message":     "Phone number report submitted",
		"reported_at": time.Now().UTC().Format(time.RFC3339),
	})
}
