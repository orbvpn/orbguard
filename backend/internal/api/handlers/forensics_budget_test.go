package handlers

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/forensics"
	fmodels "orbguard-lab/internal/forensics/models"
	"orbguard-lab/internal/forensics/safezip"
	"orbguard-lab/pkg/logger"
)

const (
	budgetLogcat   = "11-21 08:12:33.123  1234  5678 I Agent: started\n11-21 08:12:33.123  1234  5678 I Agent: started\n11-21 08:12:33.123  1234  5678 I Agent: started\n"
	timeLimitNote  = "rest of the archive: over the time limit"
	logcatStopNote = "logcat beyond the size, findings or time limit"

	budgetShutdown   = "\t\tremaining client pid: 1 (/usr/libexec/a)\n\t\tremaining client pid: 2 (/usr/libexec/b)\n\t\tremaining client pid: 3 (/usr/libexec/c)\n"
	shutdownStopNote = "shutdown log beyond the line, findings or time limit"
	quickStopNote    = "log beyond the time limit"
)

func budgetHandler(budget time.Duration) *ForensicsHandler {
	log := logger.NewDefault()
	h := NewForensicsHandler(forensics.NewService(log), log)
	h.AnalysisBudget = budget
	return h
}

func multipartBody(t *testing.T, filename string, content []byte) (*bytes.Buffer, string) {
	t.Helper()
	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	part, err := mw.CreateFormFile("file", filename)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := part.Write(content); err != nil {
		t.Fatal(err)
	}
	mw.Close()
	return &body, mw.FormDataContentType()
}

func budgetTarGz(t *testing.T) []byte {
	t.Helper()
	var b bytes.Buffer
	gz := gzip.NewWriter(&b)
	tw := tar.NewWriter(gz)
	content := []byte("hello\n")
	if err := tw.WriteHeader(&tar.Header{Name: "x/logs/lockdownd/a.log", Mode: 0o600, Size: int64(len(content))}); err != nil {
		t.Fatal(err)
	}
	if _, err := tw.Write(content); err != nil {
		t.Fatal(err)
	}
	tw.Close()
	gz.Close()
	return b.Bytes()
}

func assertPartly(t *testing.T, rec *httptest.ResponseRecorder, note string) {
	t.Helper()
	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("want 422, got %d: %s", rec.Code, rec.Body.String())
	}
	var body struct {
		Code        string   `json:"code"`
		NotExamined []string `json:"not_examined"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Code != "partly_examined" || len(body.NotExamined) != 1 || body.NotExamined[0] != note {
		t.Fatalf("want partly_examined naming %q: %s", note, rec.Body.String())
	}
}

func TestEveryAnalysisRouteStopsAtTheBudget(t *testing.T) {
	archive := budgetTarGz(t)
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "logs", "lockdownd"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "logs", "lockdownd", "a.log"), []byte("hello\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	asService := func(r *http.Request) *http.Request {
		return r.WithContext(context.WithValue(r.Context(), middleware.ContextKeyIsService, true))
	}
	jsonReq := func(path string, fields map[string]any) *http.Request {
		raw, _ := json.Marshal(fields)
		return asService(httptest.NewRequest(http.MethodPost, path, bytes.NewReader(raw)))
	}
	uploadReq := func(path, filename string, content []byte) *http.Request {
		body, contentType := multipartBody(t, filename, content)
		r := httptest.NewRequest(http.MethodPost, path, body)
		r.Header.Set("Content-Type", contentType)
		return r
	}

	h := budgetHandler(-time.Second)
	for name, c := range map[string]struct {
		serve func(http.ResponseWriter, *http.Request)
		req   *http.Request
		note  string
	}{
		"sysdiagnose upload": {h.UploadSysdiagnose, uploadReq("/s", "s.tar.gz", archive), timeLimitNote},
		"sysdiagnose path":   {h.AnalyzeSysdiagnose, jsonReq("/p", map[string]any{"archive_path": dir}), timeLimitNote},
		"logcat text":        {h.AnalyzeLogcat, jsonReq("/l", map[string]any{"log_data": budgetLogcat}), logcatStopNote},
		"logcat upload":      {h.UploadLogcat, uploadReq("/u", "logcat.txt", []byte(budgetLogcat)), logcatStopNote},
		"bugreport upload":   {h.UploadBugreport, uploadReq("/b", "bugreport.txt", []byte(budgetLogcat)), logcatStopNote},
		"shutdown text":      {h.AnalyzeShutdownLog, jsonReq("/a", map[string]any{"log_data": budgetShutdown}), shutdownStopNote},
		"shutdown upload":    {h.UploadShutdownLog, uploadReq("/us", "shutdown.log", []byte(budgetShutdown)), shutdownStopNote},
		"quick check":        {h.QuickCheck, jsonReq("/q", map[string]any{"platform": "android", "log_data": budgetLogcat}), quickStopNote},
		"quick check of ios": {h.QuickCheck, jsonReq("/qi", map[string]any{"platform": "ios", "log_data": budgetShutdown}), quickStopNote},
	} {
		t.Run(name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			c.serve(rec, c.req)
			assertPartly(t, rec, c.note)
		})
	}
	for name, fields := range map[string]map[string]any{
		"full analysis of a sysdiagnose":  {"platform": "ios", "device_id": "d", "sysdiagnose_path": dir},
		"full analysis of a shutdown log": {"platform": "ios", "device_id": "d", "shutdown_log": budgetShutdown},
		"full analysis of a logcat":       {"platform": "android", "device_id": "d", "logcat_data": budgetLogcat},
	} {
		t.Run(name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			h.FullAnalysis(rec, jsonReq("/f", fields))
			if rec.Code != http.StatusUnprocessableEntity {
				t.Fatalf("want 422, got %d: %s", rec.Code, rec.Body.String())
			}
		})
	}
}

// slowReader delays the request body, as a slow upload does.
type slowReader struct {
	r     io.Reader
	delay time.Duration
	slept bool
}

func (s *slowReader) Read(p []byte) (int, error) {
	if !s.slept {
		s.slept = true
		time.Sleep(s.delay)
	}
	return s.r.Read(p)
}

func TestBudgetCountsTheUpload(t *testing.T) {
	const budget = 200 * time.Millisecond
	body, contentType := multipartBody(t, "s.tar.gz", budgetTarGz(t))
	req := httptest.NewRequest(http.MethodPost, "/s", &slowReader{r: body, delay: 2 * budget})
	req.Header.Set("Content-Type", contentType)
	rec := httptest.NewRecorder()
	budgetHandler(budget).UploadSysdiagnose(rec, req)
	assertPartly(t, rec, timeLimitNote)
}

func TestClosedConnectionStopsTheAnalysis(t *testing.T) {
	body, contentType := multipartBody(t, "s.tar.gz", budgetTarGz(t))
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	req := httptest.NewRequest(http.MethodPost, "/s", body).WithContext(ctx)
	req.Header.Set("Content-Type", contentType)
	rec := httptest.NewRecorder()
	budgetHandler(time.Minute).UploadSysdiagnose(rec, req)
	assertPartly(t, rec, timeLimitNote)
}

func TestDefaultBudgetFitsTheWriteTimeout(t *testing.T) {
	if got := budgetHandler(0); forensicAnalysisBudget >= 15*time.Second || got == nil {
		t.Fatalf("the budget must end before the 15 s write timeout: %s", forensicAnalysisBudget)
	}
	log := logger.NewDefault()
	if got := NewForensicsHandler(forensics.NewService(log), log).AnalysisBudget; got != forensicAnalysisBudget {
		t.Fatalf("the handler must start with the default budget, got %s", got)
	}
}

func TestBusyAnswerIsARetry(t *testing.T) {
	rec := httptest.NewRecorder()
	if !respondUnexamined(rec, errors.Join(errors.New("wrapped"), forensics.ErrAnalysisBusy)) {
		t.Fatal("the busy error must be answered")
	}
	if rec.Code != http.StatusServiceUnavailable || rec.Header().Get("Retry-After") != "15" {
		t.Fatalf("want 503 with Retry-After, got %d %q", rec.Code, rec.Header().Get("Retry-After"))
	}
	body := rec.Body.String()
	if !strings.Contains(body, `"code":"analysis_busy"`) || !strings.Contains(body, "not an all-clear") || strings.Contains(body, "anomalies") {
		t.Fatalf("body: %s", body)
	}
}

func TestReadCapped(t *testing.T) {
	data, over, err := readCapped(strings.NewReader("abcd"), 4)
	if err != nil || over || string(data) != "abcd" {
		t.Fatalf("at the limit: %q %v %v", data, over, err)
	}
	data, over, err = readCapped(strings.NewReader("abcde"), 4)
	if err != nil || !over || string(data) != "abcd" {
		t.Fatalf("over the limit: %q %v %v", data, over, err)
	}
}

func TestUnreadRestNeverReadsClean(t *testing.T) {
	const note = "rest"
	clean := fmodels.NewForensicResult("", "ios", fmodels.ForensicScanTypeShutdownLog)
	var partly *fmodels.PartlyExaminedError
	if _, err := withUnreadRest(clean, nil, note); !errors.As(err, &partly) {
		t.Fatalf("clean: %v", err)
	}
	if _, err := withUnreadRest(nil, forensics.ErrNothingExamined, note); !errors.As(err, &partly) || partly.NotExamined[0] != note {
		t.Fatalf("nothing examined: %v", err)
	}
	other := errors.New("other")
	if _, err := withUnreadRest(nil, other, note); !errors.Is(err, other) {
		t.Fatalf("other error: %v", err)
	}
	high := fmodels.NewForensicResult("", "ios", fmodels.ForensicScanTypeShutdownLog)
	high.AddAnomaly(fmodels.Anomaly{Severity: fmodels.ForensicSeverityHigh})
	high.RawData["not_examined"] = []string{"earlier"}
	got, err := withUnreadRest(high, nil, note)
	if err != nil {
		t.Fatal(err)
	}
	if listed := got.RawData["not_examined"].([]string); len(listed) != 2 || listed[1] != note {
		t.Fatalf("listed: %v", listed)
	}
}

// holdDirectoryBudget keeps most of the shared zip directory budget in use
// until the test ends.
func holdDirectoryBudget(t *testing.T) {
	t.Helper()
	const records = 1050
	name := bytes.Repeat([]byte("a"), 60000)
	record := make([]byte, 46)
	binary.LittleEndian.PutUint32(record, 0x02014b50)
	binary.LittleEndian.PutUint16(record[28:], uint16(len(name)))

	path := filepath.Join(t.TempDir(), "held.zip")
	f, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < records; i++ {
		f.Write(record)
		f.Write(name)
	}
	end := make([]byte, 22)
	binary.LittleEndian.PutUint32(end, 0x06054b50)
	binary.LittleEndian.PutUint16(end[8:], records)
	binary.LittleEndian.PutUint16(end[10:], records)
	binary.LittleEndian.PutUint32(end[12:], records*uint32(len(record)+len(name)))
	f.Write(end)
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	held, err := safezip.Open(path, 64<<20)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { held.Close() })
}

func smallZip(t *testing.T, name, content string) []byte {
	t.Helper()
	var b bytes.Buffer
	zw := zip.NewWriter(&b)
	w, err := zw.Create(name)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write([]byte(content)); err != nil {
		t.Fatal(err)
	}
	zw.Close()
	return b.Bytes()
}

func TestCapacityAnswerOnEveryArchiveRoute(t *testing.T) {
	holdDirectoryBudget(t)
	h := budgetHandler(time.Minute)
	assertBusy := func(t *testing.T, rec *httptest.ResponseRecorder) {
		t.Helper()
		if rec.Code != http.StatusServiceUnavailable || !strings.Contains(rec.Body.String(), `"code":"analysis_busy"`) {
			t.Fatalf("want the busy answer, got %d: %s", rec.Code, rec.Body.String())
		}
	}
	for name, c := range map[string]struct {
		serve    func(http.ResponseWriter, *http.Request)
		filename string
		entry    string
	}{
		"sysdiagnose": {h.UploadSysdiagnose, "s.zip", "x/logs/lockdownd/a.log"},
		"bugreport":   {h.UploadBugreport, "bugreport.zip", "bugreport-x.txt"},
		"backup":      {h.UploadIOSBackup, "backup.zip", "Manifest.db"},
	} {
		t.Run(name, func(t *testing.T) {
			body, contentType := multipartBody(t, c.filename, smallZip(t, c.entry, budgetLogcat))
			req := httptest.NewRequest(http.MethodPost, "/u", body)
			req.Header.Set("Content-Type", contentType)
			rec := httptest.NewRecorder()
			c.serve(rec, req)
			assertBusy(t, rec)
		})
	}
	t.Run("full analysis", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "s.zip")
		if err := os.WriteFile(path, smallZip(t, "x/logs/lockdownd/a.log", "hello\n"), 0o600); err != nil {
			t.Fatal(err)
		}
		raw, _ := json.Marshal(map[string]any{"platform": "ios", "device_id": "d", "sysdiagnose_path": path})
		req := httptest.NewRequest(http.MethodPost, "/f", bytes.NewReader(raw))
		req = req.WithContext(context.WithValue(req.Context(), middleware.ContextKeyIsService, true))
		rec := httptest.NewRecorder()
		h.FullAnalysis(rec, req)
		assertBusy(t, rec)
	})
}

func TestBugreportStopsAtItsParseLimit(t *testing.T) {
	var b bytes.Buffer
	zw := zip.NewWriter(&b)
	w, err := zw.Create("bugreport-x.txt")
	if err != nil {
		t.Fatal(err)
	}
	line := append(bytes.Repeat([]byte("x"), 60*1024), '\n')
	for written := int64(0); written <= maxBugreportParseBytes; written += int64(len(line)) {
		if _, err := w.Write(line); err != nil {
			t.Fatal(err)
		}
	}
	zw.Close()
	body, contentType := multipartBody(t, "bugreport.zip", b.Bytes())
	req := httptest.NewRequest(http.MethodPost, "/b", body)
	req.Header.Set("Content-Type", contentType)
	rec := httptest.NewRecorder()
	budgetHandler(10*time.Minute).UploadBugreport(rec, req)
	assertPartly(t, rec, logcatStopNote)
}
