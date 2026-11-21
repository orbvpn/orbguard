package api

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"database/sql"
	"encoding/json"
	"fmt"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The repository holds no captured device log, so these lines are written to
// the formats the parsers declare. The Android threadtime line is the format
// the app's own capture requests (logcat -d -v threadtime).
const (
	iosEntry         = "2024-05-01 10:11:12.123 +0000 101 SpringBoard[101]: client exiting\n"
	logcatThreadtime = "11-21 08:12:33.123  1234  5678 I ActivityManager: Displayed com.example/.Main\n"
	logcatBrief      = "I/ActivityManager( 1234): Displayed com.example/.Main\n"
	logcatTime       = "11-21 08:12:33.123 I/ActivityManager( 1234): Displayed com.example/.Main\n"
)

// Text the parsers do not read, including line shapes other tools produce.
var unrecognisedLogs = map[string]string{
	"prose":             "this is not a log\n",
	"logcat banner":     "--------- beginning of main\n",
	"status lines only": "After 2.34s, these clients are still here:\nSIGTERM: [client:123]\n",
	"logcat with year":  "2026-11-21 08:12:33.123  1234  5678 I ActivityManager: Displayed com.example/.Main\n",
	"whitespace only":   " \n\t\n",
	"shutdown no zone":  "2024-05-01 10:11:12.123 101 SpringBoard[101]: client exiting\n",
	"shutdown no milli": "2024-05-01 10:11:12 +0000 101 SpringBoard[101]: client exiting\n",
}

func upload(h http.Handler, path, filename string, content []byte, opts ...reqOpt) *httptest.ResponseRecorder {
	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	_ = mw.WriteField("device_id", "d")
	part, _ := mw.CreateFormFile("file", filename)
	_, _ = part.Write(content)
	_ = mw.Close()
	contentType := mw.FormDataContentType()
	opts = append(opts, func(r *http.Request) { r.Header.Set("Content-Type", contentType) })
	return do(h, http.MethodPost, path, &body, opts...)
}

func postLog(h http.Handler, path, logData string) *httptest.ResponseRecorder {
	raw, _ := json.Marshal(map[string]string{"device_id": "d", "log_data": logData})
	return do(h, http.MethodPost, path, bytes.NewReader(raw), asDevice())
}

func zipOf(t *testing.T, files map[string][]byte) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for name, content := range files {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write(content); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func tarGzOf(t *testing.T, files map[string][]byte) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	for name, content := range files {
		if err := tw.WriteHeader(&tar.Header{Name: name, Mode: 0o600, Size: int64(len(content)), Typeflag: tar.TypeReg}); err != nil {
			t.Fatal(err)
		}
		if _, err := tw.Write(content); err != nil {
			t.Fatal(err)
		}
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gz.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func sqliteFile(t *testing.T, statements ...string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "fixture.db")
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	for _, stmt := range statements {
		if _, err := db.Exec(stmt); err != nil {
			t.Fatalf("%s: %v", stmt, err)
		}
	}
	return path
}

const manifestSchema = `CREATE TABLE Files (fileID TEXT, domain TEXT, relativePath TEXT, flags INTEGER, file BLOB)`

func manifestWithRow(t *testing.T) string {
	return sqliteFile(t, manifestSchema,
		`INSERT INTO Files VALUES ('abc123', 'AppDomain-com.example', 'Documents/note.txt', 1, x'00')`)
}

func readFile(t *testing.T, path string) []byte {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

// assertExaminedClean: a real result with no findings, in the normal shape.
func assertExaminedClean(t *testing.T, rec *httptest.ResponseRecorder) {
	t.Helper()
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	body := decodeJSON(t, rec.Body.Bytes())
	anomalies, ok := body["anomalies"].([]any)
	if !ok || len(anomalies) != 0 || body["total_anomalies"] != float64(0) {
		t.Fatalf("want an empty anomalies list and total 0: %s", rec.Body.String())
	}
	if _, ok := body["error"]; ok {
		t.Fatalf("a clean result must not carry an error: %s", rec.Body.String())
	}
}

func assertHasFindings(t *testing.T, rec *httptest.ResponseRecorder) {
	t.Helper()
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if got, _ := decodeJSON(t, rec.Body.Bytes())["total_anomalies"].(float64); got < 1 {
		t.Fatalf("a finding was lost: %s", rec.Body.String())
	}
}

type logRoute struct {
	name string
	send func(t *testing.T, h http.Handler, log string) *httptest.ResponseRecorder
}

func shutdownRoutes() []logRoute {
	return []logRoute{
		{"analyze/shutdown-log", func(_ *testing.T, h http.Handler, log string) *httptest.ResponseRecorder {
			return postLog(h, "/api/v1/forensics/analyze/shutdown-log", log)
		}},
		{"ios/shutdown-log/upload", func(_ *testing.T, h http.Handler, log string) *httptest.ResponseRecorder {
			return upload(h, "/api/v1/forensics/ios/shutdown-log/upload", "shutdown.log", []byte(log), asDevice())
		}},
	}
}

func logcatRoutes() []logRoute {
	return []logRoute{
		{"analyze/logcat", func(_ *testing.T, h http.Handler, log string) *httptest.ResponseRecorder {
			return postLog(h, "/api/v1/forensics/analyze/logcat", log)
		}},
		{"android/logcat/upload", func(_ *testing.T, h http.Handler, log string) *httptest.ResponseRecorder {
			return upload(h, "/api/v1/forensics/android/logcat/upload", "logcat.txt", []byte(log), asDevice())
		}},
		{"android/bugreport/upload txt", func(_ *testing.T, h http.Handler, log string) *httptest.ResponseRecorder {
			return upload(h, "/api/v1/forensics/android/bugreport/upload", "bugreport.txt", []byte(log), asDevice())
		}},
		{"android/bugreport/upload zip", func(t *testing.T, h http.Handler, log string) *httptest.ResponseRecorder {
			archive := zipOf(t, map[string][]byte{"bugreport-device-2026.txt": []byte(log)})
			return upload(h, "/api/v1/forensics/android/bugreport/upload", "bugreport.zip", archive, asDevice())
		}},
	}
}

func TestLogRoutesRefuseWhatTheyDoNotRecognise(t *testing.T) {
	h := newGuardRouter(t)
	for _, route := range append(shutdownRoutes(), logcatRoutes()...) {
		for name, log := range unrecognisedLogs {
			t.Run(route.name+"/"+name, func(t *testing.T) {
				rec := route.send(t, h, log)
				assertNothingExamined(t, rec.Code, rec.Body.Bytes())
			})
		}
	}
}

func TestLogRoutesKeepACleanResultForRecognisedLogs(t *testing.T) {
	h := newGuardRouter(t)
	noise := "some line the parser skips\n"
	nineOf := func(line string) string { return strings.Repeat(line, 9) }
	for _, route := range shutdownRoutes() {
		for name, log := range map[string]string{"entry": iosEntry, "entry with one noise line": noise + nineOf(iosEntry)} {
			t.Run(route.name+"/"+name, func(t *testing.T) {
				assertExaminedClean(t, route.send(t, h, log))
			})
		}
	}
	for _, route := range logcatRoutes() {
		for name, log := range map[string]string{
			"threadtime":             logcatThreadtime,
			"brief":                  logcatBrief,
			"time":                   logcatTime,
			"threadtime with one noise line": "--------- beginning of main\n" + nineOf(logcatThreadtime) + noise,
		} {
			t.Run(route.name+"/"+name, func(t *testing.T) {
				assertExaminedClean(t, route.send(t, h, log))
			})
		}
	}
}

func TestLogRoutesKeepFindings(t *testing.T) {
	h := newGuardRouter(t)
	suspicious := "11-21 08:12:33.123  1234  5678 W Agent: pegasus implant started\n"
	for _, route := range logcatRoutes() {
		t.Run(route.name, func(t *testing.T) { assertHasFindings(t, route.send(t, h, suspicious)) })
	}
	sticky := "2024-05-01 10:11:12.123 +0000 101 roleaccountd[101]: client exiting path: /private/var/db/abc delay: 3.5\n"
	for _, route := range shutdownRoutes() {
		t.Run(route.name, func(t *testing.T) { assertHasFindings(t, route.send(t, h, sticky)) })
	}
}

func TestBackupUploadRecognition(t *testing.T) {
	h := newGuardRouter(t)
	const path = "/api/v1/forensics/ios/backup/upload"

	refused := map[string]map[string][]byte{
		"not a backup":         {"notes.txt": []byte("hello")},
		"info plist only":      {"backup/Info.plist": []byte("<plist><dict></dict></plist>")},
		"unreadable manifest":  {"backup/Manifest.db": []byte("encrypted or corrupt, not sqlite")},
		"manifest with no row": {"backup/Manifest.db": readFile(t, sqliteFile(t, manifestSchema))},
	}
	for name, files := range refused {
		t.Run(name, func(t *testing.T) {
			rec := upload(h, path, "backup.zip", zipOf(t, files), asDevice())
			assertNothingExamined(t, rec.Code, rec.Body.Bytes())
		})
	}

	t.Run("readable manifest", func(t *testing.T) {
		archive := zipOf(t, map[string][]byte{"backup/Manifest.db": readFile(t, manifestWithRow(t))})
		assertExaminedClean(t, upload(h, path, "backup.zip", archive, asDevice()))
	})
}

func TestBackupPathRouteRecognition(t *testing.T) {
	h := newGuardRouter(t)
	empty := t.TempDir()
	body := fmt.Sprintf(`{"device_id":"d","backup_path":%q}`, empty)
	rec := do(h, http.MethodPost, "/api/v1/forensics/analyze/backup", strings.NewReader(body), asService())
	assertNothingExamined(t, rec.Code, rec.Body.Bytes())

	real := t.TempDir()
	if err := os.WriteFile(filepath.Join(real, "Manifest.db"), readFile(t, manifestWithRow(t)), 0o600); err != nil {
		t.Fatal(err)
	}
	body = fmt.Sprintf(`{"device_id":"d","backup_path":%q}`, real)
	assertExaminedClean(t, do(h, http.MethodPost, "/api/v1/forensics/analyze/backup", strings.NewReader(body), asService()))
}

func TestDataUsageRecognition(t *testing.T) {
	h := newGuardRouter(t)
	const schema = `CREATE TABLE ZPROCESS (ZPROCNAME TEXT, ZBUNDLENAME TEXT, ZWIFIIN INTEGER, ZWIFIOUT INTEGER, ZWWANIN INTEGER, ZWWANOUT INTEGER, ZFIRSTTIMESTAMP REAL, ZLASTTIMESTAMP REAL)`
	send := func(path string) *httptest.ResponseRecorder {
		body := fmt.Sprintf(`{"device_id":"d","db_path":%q}`, path)
		return do(h, http.MethodPost, "/api/v1/forensics/analyze/data-usage", strings.NewReader(body), asService())
	}

	rec := send(sqliteFile(t, schema))
	assertNothingExamined(t, rec.Code, rec.Body.Bytes())
	rec = send(sqliteFile(t, schema, `INSERT INTO ZPROCESS VALUES ('SpringBoard','com.apple.springboard',0,0,0,0,1,2)`))
	assertNothingExamined(t, rec.Code, rec.Body.Bytes())

	assertExaminedClean(t, send(sqliteFile(t, schema, `INSERT INTO ZPROCESS VALUES ('ExampleApp','com.example.app',100,100,0,0,700000000,700000100)`)))

	// A file that is not this database stays an error, and never a clean result.
	notDB := filepath.Join(t.TempDir(), "x.sqlite")
	if err := os.WriteFile(notDB, []byte("not a database"), 0o600); err != nil {
		t.Fatal(err)
	}
	if rec := send(notDB); rec.Code != http.StatusInternalServerError {
		t.Fatalf("not a database: want 500, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestSysdiagnoseUploadRecognition(t *testing.T) {
	h := newGuardRouter(t)
	const path = "/api/v1/forensics/ios/sysdiagnose/upload"
	archives := map[string]struct {
		filename string
		build    func(*testing.T, map[string][]byte) []byte
	}{
		"zip":    {"sysdiagnose.zip", zipOf},
		"tar.gz": {"sysdiagnose.tar.gz", tarGzOf},
		"tgz":    {"sysdiagnose.tgz", tarGzOf},
	}

	for kind, archive := range archives {
		send := func(t *testing.T, files map[string][]byte) *httptest.ResponseRecorder {
			return upload(h, path, archive.filename, archive.build(t, files), asDevice())
		}
		t.Run(kind+"/unrelated file", func(t *testing.T) {
			rec := send(t, map[string][]byte{"notes.txt": []byte("hello")})
			assertNothingExamined(t, rec.Code, rec.Body.Bytes())
		})
		t.Run(kind+"/unreadable shutdown log only", func(t *testing.T) {
			rec := send(t, map[string][]byte{"sysdiagnose_2026/logs/shutdown/shutdown.log": []byte("this is not a log\n")})
			assertNothingExamined(t, rec.Code, rec.Body.Bytes())
		})
		t.Run(kind+"/empty known file", func(t *testing.T) {
			rec := send(t, map[string][]byte{"sysdiagnose_2026/logs/lockdownd/lockdownd.log": {}})
			assertNothingExamined(t, rec.Code, rec.Body.Bytes())
		})
		t.Run(kind+"/known file", func(t *testing.T) {
			assertExaminedClean(t, send(t, map[string][]byte{"sysdiagnose_2026/logs/lockdownd/lockdownd.log": []byte("hello")}))
		})
		t.Run(kind+"/finding in an unrelated file is kept", func(t *testing.T) {
			assertHasFindings(t, send(t, map[string][]byte{"notes.txt": []byte(spywareInText)}))
		})
	}

	t.Run("zip/readable shutdown log only", func(t *testing.T) {
		archive := zipOf(t, map[string][]byte{"sysdiagnose_2026/logs/shutdown/shutdown.log": []byte(iosEntry)})
		assertExaminedClean(t, upload(h, path, "sysdiagnose.zip", archive, asDevice()))
	})
}

func TestSysdiagnosePathRouteRecognition(t *testing.T) {
	h := newGuardRouter(t)
	send := func(dir string) *httptest.ResponseRecorder {
		body := fmt.Sprintf(`{"device_id":"d","archive_path":%q}`, dir)
		return do(h, http.MethodPost, "/api/v1/forensics/analyze/sysdiagnose", strings.NewReader(body), asService())
	}

	unrelated := t.TempDir()
	if err := os.WriteFile(filepath.Join(unrelated, "notes.txt"), []byte("hello"), 0o600); err != nil {
		t.Fatal(err)
	}
	rec := send(unrelated)
	assertNothingExamined(t, rec.Code, rec.Body.Bytes())

	known := t.TempDir()
	logDir := filepath.Join(known, "logs", "lockdownd")
	if err := os.MkdirAll(logDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(logDir, "lockdownd.log"), []byte("hello"), 0o600); err != nil {
		t.Fatal(err)
	}
	assertExaminedClean(t, send(known))
}

func TestQuickCheckRecognition(t *testing.T) {
	h := newGuardRouter(t)
	send := func(platform, log string) *httptest.ResponseRecorder {
		raw, _ := json.Marshal(map[string]string{"platform": platform, "log_data": log})
		return do(h, http.MethodPost, "/api/v1/forensics/quick-check", bytes.NewReader(raw), asDevice())
	}

	for _, c := range []struct{ platform, log string }{
		{"ios", ""},
		{"android", ""},
		{"ios", "this is not a log\n"},
		{"android", "this is not a log\n"},
		{"windows", logcatThreadtime},
		{"", iosEntry},
	} {
		rec := send(c.platform, c.log)
		assertNothingExamined(t, rec.Code, rec.Body.Bytes())
	}

	for _, c := range []struct{ platform, log string }{{"ios", iosEntry}, {"android", logcatThreadtime}} {
		rec := send(c.platform, c.log)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s recognised log: want 200, got %d: %s", c.platform, rec.Code, rec.Body.String())
		}
		body := decodeJSON(t, rec.Body.Bytes())
		if body["is_suspicious"] != false || body["indicators_found"] != float64(0) {
			t.Fatalf("%s recognised log: want a clean answer: %s", c.platform, rec.Body.String())
		}
	}

	// An indicator is reported whatever the format of the text around it.
	rec := send("android", "pegasus mentioned in plain text")
	if rec.Code != http.StatusOK || decodeJSON(t, rec.Body.Bytes())["is_suspicious"] != true {
		t.Fatalf("indicator in plain text: got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestFullAnalysisCountsOnlyWhatItRecognised(t *testing.T) {
	h := newGuardRouter(t)
	send := func(fields map[string]any) *httptest.ResponseRecorder {
		fields["device_id"] = "d"
		raw, _ := json.Marshal(fields)
		return do(h, http.MethodPost, "/api/v1/forensics/full-analysis", bytes.NewReader(raw), asService())
	}
	scans := func(t *testing.T, rec *httptest.ResponseRecorder) []any {
		t.Helper()
		if rec.Code != http.StatusOK {
			t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
		}
		raw, _ := decodeJSON(t, rec.Body.Bytes())["raw_data"].(map[string]any)
		list, _ := raw["scans_performed"].([]any)
		return list
	}

	for name, log := range unrecognisedLogs {
		t.Run("ios only/"+name, func(t *testing.T) {
			rec := send(map[string]any{"platform": "ios", "shutdown_log": log})
			assertNothingExamined(t, rec.Code, rec.Body.Bytes())
		})
		t.Run("android only/"+name, func(t *testing.T) {
			rec := send(map[string]any{"platform": "android", "logcat_data": log})
			assertNothingExamined(t, rec.Code, rec.Body.Bytes())
		})
	}

	backup := t.TempDir()
	if err := os.WriteFile(filepath.Join(backup, "Manifest.db"), readFile(t, manifestWithRow(t)), 0o600); err != nil {
		t.Fatal(err)
	}
	emptyBackup := t.TempDir()

	t.Run("both real", func(t *testing.T) {
		got := scans(t, send(map[string]any{"platform": "ios", "shutdown_log": iosEntry, "backup_path": backup}))
		if len(got) != 2 {
			t.Fatalf("scans_performed: want both, got %v", got)
		}
	})
	t.Run("neither real", func(t *testing.T) {
		rec := send(map[string]any{"platform": "ios", "shutdown_log": "this is not a log\n", "backup_path": emptyBackup})
		assertNothingExamined(t, rec.Code, rec.Body.Bytes())
	})
}
