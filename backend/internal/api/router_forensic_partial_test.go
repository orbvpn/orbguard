package api

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

const (
	sysdiagnoseUpload = "/api/v1/forensics/ios/sysdiagnose/upload"
	shutdownEntry     = "sysdiagnose_2026/logs/shutdown/shutdown.log"
	lockdownEntry     = "sysdiagnose_2026/logs/lockdownd/lockdownd.log"
	stickyLine        = "2024-05-01 10:11:12.123 +0000 101 roleaccountd[101]: client exiting path: /private/var/db/abc delay: 3.5\n"
	stickyTitle       = "Suspicious Sticky Process Detected"
	spywareInText     = "seen /private/var/db/0123456789abcdef0123456789abcdef here"
)

type archiveEntry struct {
	name    string
	content []byte
}

// Unlike zipOf and tarGzOf, these keep the entry order, which decides which
// file a shared name would keep.
func zipEntries(t *testing.T, entries []archiveEntry) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for _, e := range entries {
		w, err := zw.Create(e.name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write(e.content); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func tarEntries(t *testing.T, entries []archiveEntry) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	for _, e := range entries {
		if err := tw.WriteHeader(&tar.Header{Name: e.name, Mode: 0o600, Size: int64(len(e.content)), Typeflag: tar.TypeReg}); err != nil {
			t.Fatal(err)
		}
		if _, err := tw.Write(e.content); err != nil {
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

type archiveKind struct {
	name, filename string
	build          func(*testing.T, []archiveEntry) []byte
}

func archiveKinds() []archiveKind {
	return []archiveKind{
		{"tar.gz", "sysdiagnose.tar.gz", tarEntries},
		{"tgz", "sysdiagnose.tgz", tarEntries},
		{"zip", "sysdiagnose.zip", zipEntries},
	}
}

func (k archiveKind) send(t *testing.T, h http.Handler, entries ...archiveEntry) *httptest.ResponseRecorder {
	t.Helper()
	return upload(h, sysdiagnoseUpload, k.filename, k.build(t, entries), asDevice())
}

func assertPartlyExamined(t *testing.T, rec *httptest.ResponseRecorder, want ...string) {
	t.Helper()
	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("want 422, got %d: %s", rec.Code, rec.Body.String())
	}
	body := decodeJSON(t, rec.Body.Bytes())
	if body["code"] != "partly_examined" {
		t.Fatalf("code: %s", rec.Body.String())
	}
	msg, _ := body["error"].(string)
	if !strings.Contains(msg, "could not be read") || !strings.Contains(msg, "not an all-clear") {
		t.Fatalf("message: %q", msg)
	}
	if _, ok := body["anomalies"]; ok {
		t.Fatalf("a refusal must not look like a result: %s", rec.Body.String())
	}
	assertStrings(t, "not_examined", body["not_examined"], want)
}

func assertStrings(t *testing.T, label string, got any, want []string) {
	t.Helper()
	list, _ := got.([]any)
	names := make([]string, 0, len(list))
	for _, v := range list {
		s, _ := v.(string)
		names = append(names, s)
	}
	if !reflect.DeepEqual(names, want) {
		t.Fatalf("%s: want %v, got %v", label, want, names)
	}
}

func rawData(t *testing.T, rec *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	raw, _ := decodeJSON(t, rec.Body.Bytes())["raw_data"].(map[string]any)
	return raw
}

func countTitle(t *testing.T, rec *httptest.ResponseRecorder, title string) int {
	t.Helper()
	anomalies, _ := decodeJSON(t, rec.Body.Bytes())["anomalies"].([]any)
	n := 0
	for _, a := range anomalies {
		if m, _ := a.(map[string]any); m["title"] == title {
			n++
		}
	}
	return n
}

func TestSysdiagnoseArchiveReportsAFindingInItsShutdownLog(t *testing.T) {
	h := newGuardRouter(t)
	log := archiveEntry{shutdownEntry, []byte(stickyLine)}
	other := archiveEntry{lockdownEntry, []byte("hello")}
	for _, kind := range archiveKinds() {
		for name, entries := range map[string][]archiveEntry{"log first": {log, other}, "log last": {other, log}} {
			t.Run(kind.name+"/"+name, func(t *testing.T) {
				rec := kind.send(t, h, entries...)
				assertHasFindings(t, rec)
				if got := countTitle(t, rec, stickyTitle); got != 1 {
					t.Fatalf("want the shutdown finding once, got %d: %s", got, rec.Body.String())
				}
			})
		}
	}
}

func TestSysdiagnoseArchiveWithUnparseableShutdownLogIsNotClean(t *testing.T) {
	h := newGuardRouter(t)
	log := archiveEntry{shutdownEntry, []byte("this is not a log\n")}
	other := archiveEntry{lockdownEntry, []byte("hello")}
	for _, kind := range archiveKinds() {
		for name, entries := range map[string][]archiveEntry{"log first": {log, other}, "log last": {other, log}} {
			t.Run(kind.name+"/"+name, func(t *testing.T) {
				rec := kind.send(t, h, entries...)
				if rec.Code != http.StatusUnprocessableEntity {
					t.Fatalf("want 422, got %d: %s", rec.Code, rec.Body.String())
				}
				body := decodeJSON(t, rec.Body.Bytes())
				if body["code"] != "partly_examined" {
					t.Fatalf("code: %s", rec.Body.String())
				}
				list, _ := body["not_examined"].([]any)
				if len(list) != 1 || !strings.HasSuffix(fmt.Sprint(list[0]), "shutdown.log") {
					t.Fatalf("not_examined: %v", list)
				}
			})
		}

		t.Run(kind.name+"/a finding elsewhere stands and lists the skipped log", func(t *testing.T) {
			rec := kind.send(t, h, log, archiveEntry{lockdownEntry, []byte(spywareInText)})
			assertHasFindings(t, rec)
			list, _ := rawData(t, rec)["not_examined"].([]any)
			if len(list) != 1 || !strings.HasSuffix(fmt.Sprint(list[0]), "shutdown.log") {
				t.Fatalf("not_examined: %v", list)
			}
		})
	}
}

func TestSysdiagnoseCleanArchiveKeepsItsResult(t *testing.T) {
	h := newGuardRouter(t)
	for _, kind := range archiveKinds() {
		for name, entries := range map[string][]archiveEntry{
			"log and known file": {{shutdownEntry, []byte(iosEntry)}, {lockdownEntry, []byte("hello")}},
			"log alone":          {{shutdownEntry, []byte(iosEntry)}},
			"known file alone":   {{lockdownEntry, []byte("hello")}},
			"file named as key":  {{"sysdiagnose_2026/logs/lockdownd/lockdownd", []byte("hello")}},
			"empty log":          {{shutdownEntry, nil}, {lockdownEntry, []byte("hello")}},
			"unrelated file too": {{"notes.txt", []byte("hello")}, {lockdownEntry, []byte("hello")}},
		} {
			t.Run(kind.name+"/"+name, func(t *testing.T) {
				rec := kind.send(t, h, entries...)
				assertExaminedClean(t, rec)
				if _, ok := rawData(t, rec)["not_examined"]; ok {
					t.Fatalf("nothing was skipped: %s", rec.Body.String())
				}
			})
		}
	}
}

// Some patterns apply only to the artifact's key ("springboard"), so a matched
// entry must stay reachable under its key as well as its basename.
func TestSysdiagnoseFindingThatOnlyTheKeyCanReach(t *testing.T) {
	h := newGuardRouter(t)
	entry := archiveEntry{"sysdiagnose_2026/logs/SpringBoard/x.log", []byte("launchd suspicious entry")}
	for _, kind := range archiveKinds() {
		t.Run(kind.name, func(t *testing.T) {
			assertHasFindings(t, kind.send(t, h, entry))
		})
	}
}

func TestSysdiagnoseEntriesThatShareANameAreAllExamined(t *testing.T) {
	h := newGuardRouter(t)
	clean := archiveEntry{"a/logs/lockdownd/x.log", []byte("hello")}
	found := archiveEntry{"b/logs/lockdownd/x.log", []byte(spywareInText)}
	current := archiveEntry{shutdownEntry, []byte(iosEntry)}
	rotated := archiveEntry{shutdownEntry + ".1", []byte(stickyLine)}
	for _, kind := range archiveKinds() {
		for name, entries := range map[string][]archiveEntry{
			"finding first": {found, clean},
			"finding last":  {clean, found},
		} {
			t.Run(kind.name+"/"+name, func(t *testing.T) {
				assertHasFindings(t, kind.send(t, h, entries...))
			})
		}
		for name, entries := range map[string][]archiveEntry{
			"rotated log first": {rotated, current},
			"rotated log last":  {current, rotated},
		} {
			t.Run(kind.name+"/"+name, func(t *testing.T) {
				rec := kind.send(t, h, entries...)
				if got := countTitle(t, rec, stickyTitle); got != 1 {
					t.Fatalf("the rotated log was not parsed: %d findings: %s", got, rec.Body.String())
				}
			})
		}
		t.Run(kind.name+"/one log in two slots is parsed once", func(t *testing.T) {
			rec := kind.send(t, h, rotated)
			if got := countTitle(t, rec, stickyTitle); got != 1 {
				t.Fatalf("want one shutdown finding, got %d: %s", got, rec.Body.String())
			}
		})
	}
}

func TestSysdiagnoseEntryOverTheCapIsNotExamined(t *testing.T) {
	h := newGuardRouter(t)
	const huge = "sysdiagnose_2026/logs/SpringBoard/huge.log"
	content := make([]byte, 50*1024*1024+1)
	for _, kind := range []archiveKind{archiveKinds()[0], archiveKinds()[2]} {
		t.Run(kind.name+"/no finding", func(t *testing.T) {
			rec := kind.send(t, h, archiveEntry{huge, content}, archiveEntry{lockdownEntry, []byte("hello")})
			assertPartlyExamined(t, rec, huge)
		})
		t.Run(kind.name+"/finding", func(t *testing.T) {
			rec := kind.send(t, h, archiveEntry{huge, content}, archiveEntry{lockdownEntry, []byte(spywareInText)})
			assertHasFindings(t, rec)
			assertStrings(t, "not_examined", rawData(t, rec)["not_examined"], []string{huge})
		})
		t.Run(kind.name+"/only the oversized file", func(t *testing.T) {
			rec := kind.send(t, h, archiveEntry{huge, content})
			assertNothingExamined(t, rec.Code, rec.Body.Bytes())
		})
		t.Run(kind.name+"/oversized unrelated file does not block a result", func(t *testing.T) {
			rec := kind.send(t, h, archiveEntry{"notes.bin", content}, archiveEntry{lockdownEntry, []byte("hello")})
			assertExaminedClean(t, rec)
		})
	}
}

func sysdiagnoseDir(t *testing.T, files map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	for name, content := range files {
		path := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func TestSysdiagnoseDirectoryRouteAppliesTheSameRule(t *testing.T) {
	h := newGuardRouter(t)
	send := func(dir string) *httptest.ResponseRecorder {
		body := fmt.Sprintf(`{"device_id":"d","archive_path":%q}`, dir)
		return do(h, http.MethodPost, "/api/v1/forensics/analyze/sysdiagnose", strings.NewReader(body), asService())
	}
	const log = "logs/shutdown/shutdown.log"
	const known = "logs/lockdownd/lockdownd.log"

	rec := send(sysdiagnoseDir(t, map[string]string{log: "this is not a log\n", known: "hello"}))
	if rec.Code != http.StatusUnprocessableEntity || decodeJSON(t, rec.Body.Bytes())["code"] != "partly_examined" {
		t.Fatalf("want partly_examined, got %d: %s", rec.Code, rec.Body.String())
	}
	assertExaminedClean(t, send(sysdiagnoseDir(t, map[string]string{log: iosEntry, known: "hello"})))
	assertHasFindings(t, send(sysdiagnoseDir(t, map[string]string{log: stickyLine, known: "hello"})))
}

func TestFullAnalysisNeverCleanWithSomethingUnexamined(t *testing.T) {
	h := newGuardRouter(t)
	send := func(fields map[string]any) *httptest.ResponseRecorder {
		fields["device_id"] = "d"
		fields["platform"] = "ios"
		raw, _ := json.Marshal(fields)
		return do(h, http.MethodPost, "/api/v1/forensics/full-analysis", bytes.NewReader(raw), asService())
	}

	backup := t.TempDir()
	if err := os.WriteFile(filepath.Join(backup, "Manifest.db"), readFile(t, manifestWithRow(t)), 0o600); err != nil {
		t.Fatal(err)
	}
	emptyBackup := t.TempDir()
	missing := filepath.Join(t.TempDir(), "absent")
	const notALog = "this is not a log\n"
	partialDiag := sysdiagnoseDir(t, map[string]string{"logs/shutdown/shutdown.log": notALog, "logs/lockdownd/lockdownd.log": "hello"})
	partialDiagFinding := sysdiagnoseDir(t, map[string]string{"logs/shutdown/shutdown.log": notALog, "logs/lockdownd/lockdownd.log": spywareInText})

	for _, c := range []struct {
		name   string
		fields map[string]any
		want   []string
	}{
		{"unrecognised log beside a real backup", map[string]any{"shutdown_log": notALog, "backup_path": backup}, []string{"shutdown_log"}},
		{"real log beside an empty backup", map[string]any{"shutdown_log": iosEntry, "backup_path": emptyBackup}, []string{"backup"}},
		{"real log beside a missing backup", map[string]any{"shutdown_log": iosEntry, "backup_path": missing}, []string{"backup"}},
		{"real log beside a missing data usage file", map[string]any{"shutdown_log": iosEntry, "data_usage_path": missing}, []string{"data_usage"}},
		{"real log beside a partly read sysdiagnose", map[string]any{"shutdown_log": iosEntry, "sysdiagnose_path": partialDiag}, []string{"sysdiagnose"}},
	} {
		t.Run(c.name, func(t *testing.T) {
			assertPartlyExamined(t, send(c.fields), c.want...)
		})
	}

	t.Run("a finding stands and lists what was skipped", func(t *testing.T) {
		rec := send(map[string]any{"shutdown_log": stickyLine, "backup_path": emptyBackup})
		assertHasFindings(t, rec)
		raw := rawData(t, rec)
		assertStrings(t, "not_examined", raw["not_examined"], []string{"backup"})
		assertStrings(t, "scans_performed", raw["scans_performed"], []string{"shutdown_log"})
	})
	t.Run("a finding in a partly read sysdiagnose stands", func(t *testing.T) {
		rec := send(map[string]any{"sysdiagnose_path": partialDiagFinding})
		assertHasFindings(t, rec)
		raw := rawData(t, rec)
		assertStrings(t, "not_examined", raw["not_examined"], []string{"sysdiagnose"})
		assertStrings(t, "scans_performed", raw["scans_performed"], []string{"sysdiagnose"})
	})
	t.Run("everything examined has no list", func(t *testing.T) {
		rec := send(map[string]any{"shutdown_log": iosEntry, "backup_path": backup})
		if rec.Code != http.StatusOK {
			t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
		}
		if _, ok := rawData(t, rec)["not_examined"]; ok {
			t.Fatalf("nothing was skipped: %s", rec.Body.String())
		}
	})
}
