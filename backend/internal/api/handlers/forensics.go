package handlers

import (
	"encoding/json"
	"net/http"

	"orbguard-lab/internal/forensics"
	fmodels "orbguard-lab/internal/forensics/models"
	"orbguard-lab/pkg/logger"
)

// ForensicsHandler handles forensic analysis endpoints
type ForensicsHandler struct {
	service *forensics.Service
	logger  *logger.Logger
}

// NewForensicsHandler creates a new ForensicsHandler
func NewForensicsHandler(service *forensics.Service, log *logger.Logger) *ForensicsHandler {
	return &ForensicsHandler{
		service: service,
		logger:  log.WithComponent("forensics-handler"),
	}
}

// GetCapabilities handles GET /api/v1/forensics/capabilities
func (h *ForensicsHandler) GetCapabilities(w http.ResponseWriter, r *http.Request) {
	capabilities := map[string]interface{}{
		"ios": map[string]interface{}{
			"shutdown_log": true,
			"backup":       true,
			"data_usage":   true,
			"sysdiagnose":  true,
		},
		"android": map[string]interface{}{
			"logcat":       true,
			"app_analysis": true,
		},
		"general": map[string]interface{}{
			"full_analysis": true,
			"quick_check":   true,
			"ioc_scanning":  true,
		},
		"version":             "1.0.0",
		"supported_platforms": []string{"ios", "android"},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(capabilities)
}

// GetIOCStats handles GET /api/v1/forensics/iocs/stats
func (h *ForensicsHandler) GetIOCStats(w http.ResponseWriter, r *http.Request) {
	stats := h.service.GetIOCStats()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(stats)
}

// AnalyzeShutdownLog handles POST /api/v1/forensics/analyze/shutdown-log
func (h *ForensicsHandler) AnalyzeShutdownLog(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DeviceID string `json:"device_id"`
		LogData  string `json:"log_data"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	if req.LogData == "" {
		http.Error(w, `{"error":"log_data is required"}`, http.StatusBadRequest)
		return
	}

	result, err := h.service.AnalyzeShutdownLog(r.Context(), []byte(req.LogData), req.DeviceID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to analyze shutdown log")
		http.Error(w, `{"error":"analysis failed"}`, http.StatusInternalServerError)
		return
	}

	h.logger.Info().
		Str("device_id", req.DeviceID).
		Int("anomalies", result.TotalAnomalies).
		Msg("shutdown log analyzed")

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

// UploadShutdownLog handles POST /api/v1/forensics/ios/shutdown-log/upload
func (h *ForensicsHandler) UploadShutdownLog(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(10 << 20); err != nil {
		http.Error(w, `{"error":"failed to parse form data"}`, http.StatusBadRequest)
		return
	}

	file, _, err := r.FormFile("file")
	if err != nil {
		http.Error(w, `{"error":"file is required"}`, http.StatusBadRequest)
		return
	}
	defer file.Close()

	deviceID := r.FormValue("device_id")
	buf := make([]byte, 10<<20)
	n, _ := file.Read(buf)

	result, err := h.service.AnalyzeShutdownLog(r.Context(), buf[:n], deviceID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to analyze uploaded shutdown log")
		http.Error(w, `{"error":"analysis failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

// AnalyzeBackup handles POST /api/v1/forensics/analyze/backup
func (h *ForensicsHandler) AnalyzeBackup(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DeviceID   string `json:"device_id"`
		BackupPath string `json:"backup_path"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	result, err := h.service.AnalyzeBackup(r.Context(), req.BackupPath, req.DeviceID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to analyze backup")
		http.Error(w, `{"error":"analysis failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

// AnalyzeDataUsage handles POST /api/v1/forensics/analyze/data-usage
func (h *ForensicsHandler) AnalyzeDataUsage(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DeviceID string `json:"device_id"`
		DBPath   string `json:"db_path"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	result, err := h.service.AnalyzeDataUsage(r.Context(), req.DBPath, req.DeviceID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to analyze data usage")
		http.Error(w, `{"error":"analysis failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

// AnalyzeSysdiagnose handles POST /api/v1/forensics/analyze/sysdiagnose
func (h *ForensicsHandler) AnalyzeSysdiagnose(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DeviceID    string `json:"device_id"`
		ArchivePath string `json:"archive_path"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	result, err := h.service.AnalyzeSysdiagnose(r.Context(), req.ArchivePath, req.DeviceID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to analyze sysdiagnose")
		http.Error(w, `{"error":"analysis failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

// AnalyzeLogcat handles POST /api/v1/forensics/analyze/logcat
func (h *ForensicsHandler) AnalyzeLogcat(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DeviceID string `json:"device_id"`
		LogData  string `json:"log_data"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	if req.LogData == "" {
		http.Error(w, `{"error":"log_data is required"}`, http.StatusBadRequest)
		return
	}

	result, err := h.service.AnalyzeLogcat(r.Context(), []byte(req.LogData), req.DeviceID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to analyze logcat")
		http.Error(w, `{"error":"analysis failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

// UploadLogcat handles POST /api/v1/forensics/android/logcat/upload
func (h *ForensicsHandler) UploadLogcat(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(10 << 20); err != nil {
		http.Error(w, `{"error":"failed to parse form data"}`, http.StatusBadRequest)
		return
	}

	file, _, err := r.FormFile("file")
	if err != nil {
		http.Error(w, `{"error":"file is required"}`, http.StatusBadRequest)
		return
	}
	defer file.Close()

	deviceID := r.FormValue("device_id")
	buf := make([]byte, 10<<20)
	n, _ := file.Read(buf)

	result, err := h.service.AnalyzeLogcat(r.Context(), buf[:n], deviceID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to analyze uploaded logcat")
		http.Error(w, `{"error":"analysis failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

// FullAnalysis handles POST /api/v1/forensics/full-analysis
func (h *ForensicsHandler) FullAnalysis(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DeviceID        string `json:"device_id"`
		Platform        string `json:"platform"`
		ShutdownLog     string `json:"shutdown_log,omitempty"`
		LogcatData      string `json:"logcat_data,omitempty"`
		BackupPath      string `json:"backup_path,omitempty"`
		DataUsagePath   string `json:"data_usage_path,omitempty"`
		SysdiagnosePath string `json:"sysdiagnose_path,omitempty"`
		IncludeTimeline bool   `json:"include_timeline"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	scanReq := fmodels.ForensicScanRequest{
		DeviceID:        req.DeviceID,
		Platform:        req.Platform,
		ShutdownLogData: []byte(req.ShutdownLog),
		LogcatData:      []byte(req.LogcatData),
		BackupPath:      req.BackupPath,
		DataUsagePath:   req.DataUsagePath,
		SysdiagnosePath: req.SysdiagnosePath,
		IncludeTimeline: req.IncludeTimeline,
	}

	result, err := h.service.RunFullAnalysis(r.Context(), scanReq)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to run full analysis")
		http.Error(w, `{"error":"analysis failed"}`, http.StatusInternalServerError)
		return
	}

	h.logger.Info().
		Str("device_id", req.DeviceID).
		Str("platform", req.Platform).
		Int("anomalies", result.TotalAnomalies).
		Float64("infection_likelihood", result.InfectionLikelihood).
		Msg("full forensic analysis completed")

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

// QuickCheck handles POST /api/v1/forensics/quick-check
func (h *ForensicsHandler) QuickCheck(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Platform string `json:"platform"`
		LogData  string `json:"log_data"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	result, err := h.service.QuickCheck(r.Context(), req.Platform, []byte(req.LogData))
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to run quick check")
		http.Error(w, `{"error":"check failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}
