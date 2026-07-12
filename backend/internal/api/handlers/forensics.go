package handlers

import (
	"archive/zip"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/forensics"
	fmodels "orbguard-lab/internal/forensics/models"
	"orbguard-lab/pkg/logger"
)

const (
	// maxForensicUploadBytes caps uploaded forensic artifacts (iOS backups,
	// sysdiagnose archives, Android bugreports) at ~500MB.
	maxForensicUploadBytes = 500 << 20

	// maxSmallUploadBytes caps small text uploads (shutdown.log, logcat).
	maxSmallUploadBytes = 10 << 20

	// maxBugreportParseBytes caps how much bugreport/logcat text is handed
	// to the parser (which operates on an in-memory byte slice).
	maxBugreportParseBytes = 256 << 20

	// maxBackupExtractBytes caps the total uncompressed size of an
	// extracted iOS backup archive (guards against zip bombs).
	maxBackupExtractBytes = 2 << 30
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

// requireServiceCaller enforces that path-based analysis endpoints — which
// reference files on the SERVER filesystem — are only used by
// service-to-service callers. Mobile/desktop clients cannot reference their
// local files by path; they must use the multipart /upload endpoints.
func (h *ForensicsHandler) requireServiceCaller(w http.ResponseWriter, r *http.Request, uploadEndpoint string) bool {
	if middleware.IsServiceRequest(r.Context()) {
		return true
	}
	respondJSON(w, http.StatusForbidden, map[string]string{
		"error": fmt.Sprintf("path-based analysis references server-side files and is service-only; upload the artifact to %s instead", uploadEndpoint),
	})
	return false
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
	if err := r.ParseMultipartForm(maxSmallUploadBytes); err != nil {
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
	data, err := io.ReadAll(io.LimitReader(file, maxSmallUploadBytes))
	if err != nil {
		http.Error(w, `{"error":"failed to read uploaded file"}`, http.StatusBadRequest)
		return
	}

	result, err := h.service.AnalyzeShutdownLog(r.Context(), data, deviceID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to analyze uploaded shutdown log")
		http.Error(w, `{"error":"analysis failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

// AnalyzeBackup handles POST /api/v1/forensics/analyze/backup
//
// SERVICE-ONLY: backup_path references a directory on the server filesystem.
// Clients upload their backup archive to /forensics/ios/backup/upload.
func (h *ForensicsHandler) AnalyzeBackup(w http.ResponseWriter, r *http.Request) {
	if !h.requireServiceCaller(w, r, "/api/v1/forensics/ios/backup/upload") {
		return
	}

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
//
// SERVICE-ONLY: db_path references a file on the server filesystem.
func (h *ForensicsHandler) AnalyzeDataUsage(w http.ResponseWriter, r *http.Request) {
	if !h.requireServiceCaller(w, r, "/api/v1/forensics/ios/backup/upload") {
		return
	}

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
//
// SERVICE-ONLY: archive_path references a file on the server filesystem.
// Clients upload their archive to /forensics/ios/sysdiagnose/upload.
func (h *ForensicsHandler) AnalyzeSysdiagnose(w http.ResponseWriter, r *http.Request) {
	if !h.requireServiceCaller(w, r, "/api/v1/forensics/ios/sysdiagnose/upload") {
		return
	}

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
	if err := r.ParseMultipartForm(maxSmallUploadBytes); err != nil {
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
	data, err := io.ReadAll(io.LimitReader(file, maxSmallUploadBytes))
	if err != nil {
		http.Error(w, `{"error":"failed to read uploaded file"}`, http.StatusBadRequest)
		return
	}

	result, err := h.service.AnalyzeLogcat(r.Context(), data, deviceID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to analyze uploaded logcat")
		http.Error(w, `{"error":"analysis failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

// ---------------------------------------------------------------------------
// Multipart artifact uploads (client-facing replacements for the path-based
// service-only endpoints above). Uploads are streamed to a temp dir, parsed
// with the existing forensics parsers, and the temp files are deleted
// afterwards. Responses use the same ForensicResult shape as the other
// analysis endpoints.
// ---------------------------------------------------------------------------

// uploadedArtifact is a forensic artifact streamed to a server temp dir.
type uploadedArtifact struct {
	// Path of the streamed artifact inside tempDir.
	Path     string
	DeviceID string
	tempDir  string
}

// Cleanup removes the artifact and its temp dir.
func (a *uploadedArtifact) Cleanup() {
	if a != nil && a.tempDir != "" {
		os.RemoveAll(a.tempDir)
	}
}

// allowedUploadContentType validates the multipart part's declared content
// type. Many HTTP clients send application/octet-stream for binary files, so
// that (and an absent header) is accepted; the file extension is the
// authoritative check.
func allowedUploadContentType(contentType string) bool {
	if contentType == "" {
		return true
	}
	mediaType, _, err := mime.ParseMediaType(contentType)
	if err != nil {
		return false
	}
	switch mediaType {
	case "application/octet-stream",
		"application/zip",
		"application/x-zip-compressed",
		"application/gzip",
		"application/x-gzip",
		"application/x-tar",
		"text/plain":
		return true
	}
	return false
}

// matchAllowedExtension returns the matching allowed extension (longest
// suffixes such as ".tar.gz" must be listed before ".gz") or "" when the
// filename is not an allowed type.
func matchAllowedExtension(filename string, allowed []string) string {
	lower := strings.ToLower(filepath.Base(filename))
	for _, ext := range allowed {
		if strings.HasSuffix(lower, ext) {
			return ext
		}
	}
	return ""
}

// receiveUpload streams a multipart upload ("file" part plus optional
// "device_id" field) to a fresh temp dir without buffering the file in
// memory. The uploaded file is stored under a sanitized fixed name
// ("artifact" + normalized extension) — the client-supplied filename is only
// used to validate the type, never as a filesystem path. On failure the
// response has already been written and (nil, false) is returned.
func (h *ForensicsHandler) receiveUpload(w http.ResponseWriter, r *http.Request, allowed map[string]string) (*uploadedArtifact, bool) {
	r.Body = http.MaxBytesReader(w, r.Body, maxForensicUploadBytes)

	mr, err := r.MultipartReader()
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "multipart/form-data body with a 'file' part is required"})
		return nil, false
	}

	tempDir, err := os.MkdirTemp("", "orbguard-forensics-")
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to create forensics upload temp dir")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to allocate upload storage"})
		return nil, false
	}

	allowedExts := make([]string, 0, len(allowed))
	for ext := range allowed {
		allowedExts = append(allowedExts, ext)
	}
	// Longest extensions first so ".tar.gz" wins over ".gz".
	for i := 0; i < len(allowedExts); i++ {
		for j := i + 1; j < len(allowedExts); j++ {
			if len(allowedExts[j]) > len(allowedExts[i]) {
				allowedExts[i], allowedExts[j] = allowedExts[j], allowedExts[i]
			}
		}
	}

	artifact := &uploadedArtifact{tempDir: tempDir}
	fail := func(status int, msg string) (*uploadedArtifact, bool) {
		artifact.Cleanup()
		respondJSON(w, status, map[string]string{"error": msg})
		return nil, false
	}

	for {
		part, err := mr.NextPart()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			// MaxBytesReader trips mid-stream as a read error.
			return fail(http.StatusRequestEntityTooLarge, fmt.Sprintf("failed to read multipart body (uploads are capped at %d bytes)", int64(maxForensicUploadBytes)))
		}

		switch part.FormName() {
		case "device_id":
			value, err := io.ReadAll(io.LimitReader(part, 1024))
			part.Close()
			if err != nil {
				return fail(http.StatusBadRequest, "failed to read device_id field")
			}
			artifact.DeviceID = strings.TrimSpace(string(value))

		case "file":
			filename := part.FileName()
			ext := matchAllowedExtension(filename, allowedExts)
			if ext == "" {
				part.Close()
				return fail(http.StatusBadRequest, fmt.Sprintf("unsupported file type %q; allowed extensions: %s", filepath.Base(filename), strings.Join(allowedExts, ", ")))
			}
			if !allowedUploadContentType(part.Header.Get("Content-Type")) {
				part.Close()
				return fail(http.StatusBadRequest, fmt.Sprintf("unsupported content type %q", part.Header.Get("Content-Type")))
			}

			// Normalized extension (e.g. .tgz → .tar.gz) so downstream
			// parsers detect the archive format correctly.
			storedExt := allowed[ext]
			destPath := filepath.Join(tempDir, "artifact"+storedExt)
			dst, err := os.Create(destPath)
			if err != nil {
				part.Close()
				h.logger.Error().Err(err).Msg("failed to create forensics upload temp file")
				return fail(http.StatusInternalServerError, "failed to store uploaded file")
			}
			written, copyErr := io.Copy(dst, part)
			closeErr := dst.Close()
			part.Close()
			if copyErr != nil {
				return fail(http.StatusRequestEntityTooLarge, fmt.Sprintf("failed to store uploaded file (uploads are capped at %d bytes)", int64(maxForensicUploadBytes)))
			}
			if closeErr != nil {
				h.logger.Error().Err(closeErr).Msg("failed to flush forensics upload temp file")
				return fail(http.StatusInternalServerError, "failed to store uploaded file")
			}
			if written == 0 {
				return fail(http.StatusBadRequest, "uploaded file is empty")
			}
			artifact.Path = destPath

		default:
			part.Close()
		}
	}

	if artifact.Path == "" {
		return fail(http.StatusBadRequest, "multipart 'file' part is required")
	}
	return artifact, true
}

// extractZipArchive extracts src into dest with zip-slip protection and a
// total uncompressed size cap.
func extractZipArchive(src, dest string, maxBytes int64) error {
	zr, err := zip.OpenReader(src)
	if err != nil {
		return fmt.Errorf("open zip archive: %w", err)
	}
	defer zr.Close()

	destRoot := filepath.Clean(dest) + string(os.PathSeparator)
	var total int64

	for _, f := range zr.File {
		target := filepath.Join(dest, filepath.Clean("/"+f.Name))
		if !strings.HasPrefix(target, destRoot) {
			return fmt.Errorf("archive entry escapes extraction directory: %s", f.Name)
		}

		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(target, 0o700); err != nil {
				return fmt.Errorf("create directory %s: %w", f.Name, err)
			}
			continue
		}

		if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
			return fmt.Errorf("create parent directory for %s: %w", f.Name, err)
		}

		rc, err := f.Open()
		if err != nil {
			return fmt.Errorf("open archive entry %s: %w", f.Name, err)
		}
		out, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
		if err != nil {
			rc.Close()
			return fmt.Errorf("create file %s: %w", f.Name, err)
		}

		// +1 so we can detect the cap being exceeded (don't trust the
		// uncompressed size declared in the header).
		written, err := io.Copy(out, io.LimitReader(rc, maxBytes-total+1))
		out.Close()
		rc.Close()
		if err != nil {
			return fmt.Errorf("extract %s: %w", f.Name, err)
		}
		total += written
		if total > maxBytes {
			return fmt.Errorf("archive exceeds extraction size limit of %d bytes", maxBytes)
		}
	}
	return nil
}

// locateBackupRoot finds the directory inside an extracted backup archive
// that contains Manifest.db (preferred) or Info.plist. Falls back to the
// extraction root, descending through single-directory wrappers (zips of a
// backup folder usually contain one top-level directory).
func locateBackupRoot(extractedRoot string) string {
	var manifestDir, infoDir string
	filepath.Walk(extractedRoot, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return nil
		}
		switch info.Name() {
		case "Manifest.db":
			if manifestDir == "" {
				manifestDir = filepath.Dir(path)
			}
		case "Info.plist":
			if infoDir == "" {
				infoDir = filepath.Dir(path)
			}
		}
		return nil
	})
	if manifestDir != "" {
		return manifestDir
	}
	if infoDir != "" {
		return infoDir
	}

	// Descend through single-directory wrappers.
	root := extractedRoot
	for {
		entries, err := os.ReadDir(root)
		if err != nil || len(entries) != 1 || !entries[0].IsDir() {
			return root
		}
		root = filepath.Join(root, entries[0].Name())
	}
}

// UploadIOSBackup handles POST /api/v1/forensics/ios/backup/upload.
// Accepts a zipped iTunes/Finder backup directory as multipart 'file'
// (+ optional device_id field), extracts it server-side, runs the existing
// backup parser and deletes the temp files.
func (h *ForensicsHandler) UploadIOSBackup(w http.ResponseWriter, r *http.Request) {
	artifact, ok := h.receiveUpload(w, r, map[string]string{".zip": ".zip"})
	if !ok {
		return
	}
	defer artifact.Cleanup()

	extractDir := filepath.Join(artifact.tempDir, "backup")
	if err := os.MkdirAll(extractDir, 0o700); err != nil {
		h.logger.Error().Err(err).Msg("failed to create backup extraction dir")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to extract backup archive"})
		return
	}
	if err := extractZipArchive(artifact.Path, extractDir, maxBackupExtractBytes); err != nil {
		h.logger.Error().Err(err).Msg("failed to extract uploaded iOS backup archive")
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": fmt.Sprintf("invalid backup archive: %v", err)})
		return
	}

	backupRoot := locateBackupRoot(extractDir)
	result, err := h.service.AnalyzeBackup(r.Context(), backupRoot, artifact.DeviceID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to analyze uploaded iOS backup")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": "analysis failed"})
		return
	}

	h.logger.Info().
		Str("device_id", artifact.DeviceID).
		Int("anomalies", result.TotalAnomalies).
		Msg("uploaded iOS backup analyzed")
	respondJSON(w, http.StatusOK, result)
}

// UploadSysdiagnose handles POST /api/v1/forensics/ios/sysdiagnose/upload.
// Accepts a sysdiagnose .tar.gz/.tgz/.zip archive as multipart 'file'
// (+ optional device_id field); the existing sysdiagnose parser performs the
// extraction itself.
func (h *ForensicsHandler) UploadSysdiagnose(w http.ResponseWriter, r *http.Request) {
	artifact, ok := h.receiveUpload(w, r, map[string]string{
		".tar.gz": ".tar.gz",
		".tgz":    ".tar.gz", // normalize so the parser detects gzip+tar
		".zip":    ".zip",
	})
	if !ok {
		return
	}
	defer artifact.Cleanup()

	result, err := h.service.AnalyzeSysdiagnose(r.Context(), artifact.Path, artifact.DeviceID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to analyze uploaded sysdiagnose archive")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": "analysis failed"})
		return
	}

	h.logger.Info().
		Str("device_id", artifact.DeviceID).
		Int("anomalies", result.TotalAnomalies).
		Msg("uploaded sysdiagnose archive analyzed")
	respondJSON(w, http.StatusOK, result)
}

// extractBugreportText pulls the bugreport text out of an Android bugreport
// zip: the largest entry named bugreport*.txt, falling back to the largest
// .txt entry. Reads at most maxBytes.
func extractBugreportText(archivePath string, maxBytes int64) ([]byte, error) {
	zr, err := zip.OpenReader(archivePath)
	if err != nil {
		return nil, fmt.Errorf("open bugreport archive: %w", err)
	}
	defer zr.Close()

	var best, bestTxt *zip.File
	for _, f := range zr.File {
		if f.FileInfo().IsDir() {
			continue
		}
		name := strings.ToLower(filepath.Base(f.Name))
		if !strings.HasSuffix(name, ".txt") {
			continue
		}
		if bestTxt == nil || f.UncompressedSize64 > bestTxt.UncompressedSize64 {
			bestTxt = f
		}
		if strings.HasPrefix(name, "bugreport") {
			if best == nil || f.UncompressedSize64 > best.UncompressedSize64 {
				best = f
			}
		}
	}
	if best == nil {
		best = bestTxt
	}
	if best == nil {
		return nil, errors.New("no .txt bugreport entry found in archive")
	}

	rc, err := best.Open()
	if err != nil {
		return nil, fmt.Errorf("open bugreport entry %s: %w", best.Name, err)
	}
	defer rc.Close()

	data, err := io.ReadAll(io.LimitReader(rc, maxBytes))
	if err != nil {
		return nil, fmt.Errorf("read bugreport entry %s: %w", best.Name, err)
	}
	return data, nil
}

// UploadBugreport handles POST /api/v1/forensics/android/bugreport/upload.
// Accepts an Android bugreport as multipart 'file' (+ optional device_id
// field) — either the bugreport zip produced by `adb bugreport` or the plain
// bugreport .txt — and runs the existing logcat/bugreport parser on it.
func (h *ForensicsHandler) UploadBugreport(w http.ResponseWriter, r *http.Request) {
	artifact, ok := h.receiveUpload(w, r, map[string]string{
		".zip": ".zip",
		".txt": ".txt",
	})
	if !ok {
		return
	}
	defer artifact.Cleanup()

	var data []byte
	if strings.HasSuffix(artifact.Path, ".zip") {
		var err error
		data, err = extractBugreportText(artifact.Path, maxBugreportParseBytes)
		if err != nil {
			h.logger.Error().Err(err).Msg("failed to extract uploaded bugreport archive")
			respondJSON(w, http.StatusBadRequest, map[string]string{"error": fmt.Sprintf("invalid bugreport archive: %v", err)})
			return
		}
	} else {
		f, err := os.Open(artifact.Path)
		if err != nil {
			h.logger.Error().Err(err).Msg("failed to open uploaded bugreport")
			respondJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to read uploaded file"})
			return
		}
		data, err = io.ReadAll(io.LimitReader(f, maxBugreportParseBytes))
		f.Close()
		if err != nil {
			h.logger.Error().Err(err).Msg("failed to read uploaded bugreport")
			respondJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to read uploaded file"})
			return
		}
	}

	if len(data) == 0 {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "bugreport contains no text to analyze"})
		return
	}

	result, err := h.service.AnalyzeLogcat(r.Context(), data, artifact.DeviceID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to analyze uploaded bugreport")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": "analysis failed"})
		return
	}

	h.logger.Info().
		Str("device_id", artifact.DeviceID).
		Int("anomalies", result.TotalAnomalies).
		Msg("uploaded bugreport analyzed")
	respondJSON(w, http.StatusOK, result)
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

	// Path fields reference server-side files — service callers only.
	// Inline data fields (shutdown_log, logcat_data) are open to clients.
	if (req.BackupPath != "" || req.DataUsagePath != "" || req.SysdiagnosePath != "") &&
		!middleware.IsServiceRequest(r.Context()) {
		respondJSON(w, http.StatusForbidden, map[string]string{
			"error": "path-based analysis references server-side files and is service-only; upload artifacts to the /api/v1/forensics/.../upload endpoints instead",
		})
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
