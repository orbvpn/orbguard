package api

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"encoding/json"
	"math/rand"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// SYNTHETIC. These lines follow the format Kaspersky's public iShutdown parser
// reads (`remaining client pid: (\d+) \((.*?)\)`, `SIGTERM: \[(\d+)\]`). They
// were not captured from a device.
const (
	deviceLogClean = "After 0.12s, these clients are still here:\n" +
		"\t\tremaining client pid: 101 (/usr/libexec/xpcproxy)\n" +
		"\t\tremaining client pid: 102 (/usr/sbin/cfprefsd)\n" +
		"\t\tremaining client pid: 103 (/System/Library/PrivateFrameworks/Foo.framework/agent)\n" +
		"SIGTERM: [1763712000]\n" +
		"After 0.09s, these clients are still here:\n" +
		"\t\tremaining client pid: 201 (/usr/libexec/xpcproxy)\n" +
		"SIGTERM: [1763798400]\n"
	pegasusSamplePath = "/private/var/db/com.apple.xpc.roleaccountd.staging/rolexd"
	deviceLogPegasus  = "After 0.12s, these clients are still here:\n" +
		"\t\tremaining client pid: 101 (/usr/libexec/xpcproxy)\n" +
		"\t\tremaining client pid: 666 (" + pegasusSamplePath + ")\n" +
		"\t\tremaining client pid: 666 (" + pegasusSamplePath + ")\n" +
		"SIGTERM: [1763712000]\n" +
		"\t\tremaining client pid: 667 (" + pegasusSamplePath + ")\n" +
		"SIGTERM: [1763798400]\n"
	deviceLogTmp = "\t\tremaining client pid: 7 (/private/var/tmp/x/implant)\nSIGTERM: [1763712000]\n"
)

func anomaliesOf(t *testing.T, rec *httptest.ResponseRecorder) []map[string]any {
	t.Helper()
	list, _ := decodeJSON(t, rec.Body.Bytes())["anomalies"].([]any)
	out := make([]map[string]any, 0, len(list))
	for _, a := range list {
		m, _ := a.(map[string]any)
		out = append(out, m)
	}
	return out
}

func countDescription(t *testing.T, rec *httptest.ResponseRecorder, description string) int {
	t.Helper()
	n := 0
	for _, a := range anomaliesOf(t, rec) {
		if a["description"] == description {
			n++
		}
	}
	return n
}

func TestDeviceShutdownLogFormat(t *testing.T) {
	h := newGuardRouter(t)

	for _, route := range shutdownRoutes() {
		t.Run(route.name+"/system clients are clean", func(t *testing.T) {
			rec := route.send(t, h, deviceLogClean)
			assertExaminedClean(t, rec)
			if got := rawData(t, rec)["reboot_count"]; got != float64(2) {
				t.Fatalf("reboot_count: want 2, got %v", got)
			}
		})
		t.Run(route.name+"/client in the db folder is the finding", func(t *testing.T) {
			rec := route.send(t, h, deviceLogPegasus)
			if rec.Code != http.StatusOK {
				t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
			}
			found := anomaliesOf(t, rec)
			if len(found) != 1 || found[0]["path"] != pegasusSamplePath ||
				found[0]["severity"] != "critical" || found[0]["process_name"] != "rolexd" {
				t.Fatalf("want one critical finding on the sample path: %s", rec.Body.String())
			}
			evidence, _ := found[0]["evidence"].(map[string]any)
			if evidence["reboot_count"] != float64(2) {
				t.Fatalf("lines in one shutdown must count as one reboot: %v", evidence)
			}
		})
		t.Run(route.name+"/client in the tmp folder is the finding", func(t *testing.T) {
			found := anomaliesOf(t, route.send(t, h, deviceLogTmp))
			if len(found) != 1 || found[0]["path"] != "/private/var/tmp/x/implant" {
				t.Fatalf("want one finding: %v", found)
			}
		})
		t.Run(route.name+"/a forged marker still encodes", func(t *testing.T) {
			rec := route.send(t, h, "\t\tremaining client pid: 1 (/usr/libexec/a)\nSIGTERM: [99999999999999]\n")
			assertExaminedClean(t, rec)
		})
		t.Run(route.name+"/a header alone is not a log", func(t *testing.T) {
			rec := route.send(t, h, "After 0.12s, these clients are still here:\n")
			assertNothingExamined(t, rec.Code, rec.Body.Bytes())
		})
		t.Run(route.name+"/the old format still reads", func(t *testing.T) {
			assertHasFindings(t, route.send(t, h, stickyLine))
		})
	}

	for _, kind := range archiveKinds() {
		t.Run(kind.name+"/clean device log in an archive", func(t *testing.T) {
			assertExaminedClean(t, kind.send(t, h,
				archiveEntry{shutdownEntry, []byte(deviceLogClean)},
				archiveEntry{lockdownEntry, []byte("hello")}))
		})
		t.Run(kind.name+"/spyware client in an archive", func(t *testing.T) {
			rec := kind.send(t, h,
				archiveEntry{lockdownEntry, []byte("hello")},
				archiveEntry{shutdownEntry, []byte(deviceLogPegasus)})
			if got := countTitle(t, rec, stickyTitle); got != 1 {
				t.Fatalf("want the client finding once, got %d: %s", got, rec.Body.String())
			}
		})
	}
}

func TestEveryFileOfAKindIsAnalysedOnce(t *testing.T) {
	h := newGuardRouter(t)
	rules := []struct{ name, dir, hit, reason string }{
		{"springboard", "logs/SpringBoard", "launchd suspicious", "Unknown daemon registered"},
		{"mobile_installation", "logs/MobileInstallation", "install failed signature", "Failed signature check"},
		{"wifi", "WiFi", "captive portal bypass", "Network security bypass"},
		{"network_usage", "logs/Networking", "exfiltration", "Unusual network activity"},
		{"locationd", "logs/locationd", "unauthorized location", "Location access anomaly"},
		{"crashes", "crashes_and_spins", "SIGSEGV", "Crash possibly indicating exploit"},
	}
	for _, kind := range archiveKinds() {
		for _, rule := range rules {
			first := "sysdiagnose_2026/" + rule.dir + "/a.log"
			last := "sysdiagnose_2026/" + rule.dir + "/b.log"
			for name, c := range map[string]struct {
				entries []archiveEntry
				want    int
			}{
				"hit in the first file": {[]archiveEntry{{first, []byte(rule.hit)}, {last, []byte("hello")}}, 1},
				"hit in the last file":  {[]archiveEntry{{first, []byte("hello")}, {last, []byte(rule.hit)}}, 1},
				"hit in both files":     {[]archiveEntry{{first, []byte(rule.hit)}, {last, []byte(rule.hit + " ")}}, 2},
				"same name, two dirs": {[]archiveEntry{
					{"x/" + rule.dir + "/a.log", []byte(rule.hit)},
					{"y/" + rule.dir + "/a.log", []byte("hello")},
				}, 1},
			} {
				t.Run(kind.name+"/"+rule.name+"/"+name, func(t *testing.T) {
					rec := kind.send(t, h, c.entries...)
					if rec.Code != http.StatusOK {
						t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
					}
					if got := countDescription(t, rec, rule.reason); got != c.want {
						t.Fatalf("want %d findings, got %d: %s", c.want, got, rec.Body.String())
					}
				})
			}
		}
		t.Run(kind.name+"/a path of two artifacts keeps both rules", func(t *testing.T) {
			rec := kind.send(t, h, archiveEntry{"x/logs/Networking/netusage.sqlite", []byte("exfiltration")})
			if got := countDescription(t, rec, "Unusual network activity"); got != 1 {
				t.Fatalf("want 1, got %d: %s", got, rec.Body.String())
			}
		})
		t.Run(kind.name+"/one finding is counted once", func(t *testing.T) {
			rec := kind.send(t, h, archiveEntry{lockdownEntry, []byte(spywareInText)})
			if got := countDescription(t, rec, "Suspicious path pattern (Pegasus)"); got != 1 {
				t.Fatalf("want 1, got %d: %s", got, rec.Body.String())
			}
		})
	}
}

// overBudgetTar and overBudgetZip declare one entry larger than the archive budget. Reading
// must stop at the declaration, so the bytes never have to exist.
func overBudgetTar(t *testing.T, first archiveEntry) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	if err := tw.WriteHeader(&tar.Header{Name: first.name, Mode: 0o600, Size: int64(len(first.content)), Typeflag: tar.TypeReg}); err != nil {
		t.Fatal(err)
	}
	if _, err := tw.Write(first.content); err != nil {
		t.Fatal(err)
	}
	if err := tw.WriteHeader(&tar.Header{Name: "x/logs/SpringBoard/huge.log", Mode: 0o600, Size: 300 << 20, Typeflag: tar.TypeReg}); err != nil {
		t.Fatal(err)
	}
	if err := tw.Flush(); err == nil {
		t.Fatal("the entry is meant to stay unwritten")
	}
	if err := gz.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func overBudgetZip(t *testing.T, first archiveEntry) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, err := zw.Create(first.name)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write(first.content); err != nil {
		t.Fatal(err)
	}
	raw, err := zw.CreateRaw(&zip.FileHeader{
		Name:               "x/logs/SpringBoard/huge.log",
		Method:             zip.Store,
		CompressedSize64:   1,
		UncompressedSize64: 300 << 20,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := raw.Write([]byte{0}); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestSysdiagnoseOverTheTotalBudgetIsNeverClean(t *testing.T) {
	h := newGuardRouter(t)
	const rest = "rest of the archive: over the size, entry or findings limit"
	for _, c := range []struct {
		name, filename string
		build          func(*testing.T, archiveEntry) []byte
	}{
		{"tar.gz", "sysdiagnose.tar.gz", overBudgetTar},
		{"zip", "sysdiagnose.zip", overBudgetZip},
	} {
		t.Run(c.name+"/no finding", func(t *testing.T) {
			archive := c.build(t, archiveEntry{lockdownEntry, []byte("hello")})
			assertPartlyExamined(t, upload(h, sysdiagnoseUpload, c.filename, archive, asDevice()), rest)
		})
		t.Run(c.name+"/a critical finding stands and lists the rest", func(t *testing.T) {
			archive := c.build(t, archiveEntry{lockdownEntry, []byte(spywareInText)})
			rec := upload(h, sysdiagnoseUpload, c.filename, archive, asDevice())
			assertHasFindings(t, rec)
			assertStrings(t, "not_examined", rawData(t, rec)["not_examined"], []string{rest})
		})
	}
}

func TestSpywareNameRulesDoNotFireOnJunk(t *testing.T) {
	h := newGuardRouter(t)

	random := make([]byte, 8<<20)
	rand.New(rand.NewSource(20261121)).Read(random)

	quiet := map[string][]byte{
		"random bytes":            random,
		"bh inside junk":          []byte("\x00\xffbh\x00 abh xbh. oh-bh, 0bh\n"),
		"pcsd inside junk":        []byte("\x01pcsd\x02 xpcsd.\n"),
		"bh as a directory":       []byte("/usr/bh/tool\n"),
		"db daemon":               []byte("/private/var/db/analyticsd\n"),
		"db apple folder":         []byte("/private/var/db/com.apple.xpc.foo/bar\n"),
		"tmp folder":              []byte("/private/var/tmp/abc\n"),
		"short hex is not a path": []byte("/private/var/db/abc123\n/private/var/tmp/deadbeef\n"),
	}
	loud := map[string]string{
		"32 hex under db":  "/private/var/db/0123456789abcdef0123456789abcdef\n",
		"32 hex under tmp": "/private/var/tmp/0123456789abcdef0123456789abcdef\n",
		"bh as a path":     "launched /usr/libexec/bh now\n",
		"bh at line end":   "/private/var/x/bh\n",
		"bh with a pid":    "2026 host bh[123]: started\n",
		"bh process field": "Process:         bh [123]\n",
		"pcsd as a path":   "/usr/sbin/pcsd\n",
		"pcsd with a pid":  "pcsd[9]: started\n",
		"roleaccount":      "com.apple.xpc.roleaccountd\n",
	}
	for _, kind := range archiveKinds() {
		for name, content := range quiet {
			t.Run(kind.name+"/quiet/"+name, func(t *testing.T) {
				rec := kind.send(t, h, archiveEntry{lockdownEntry, content})
				assertExaminedClean(t, rec)
			})
		}
		for name, content := range loud {
			t.Run(kind.name+"/loud/"+name, func(t *testing.T) {
				assertHasFindings(t, kind.send(t, h, archiveEntry{lockdownEntry, []byte(content)}))
			})
		}
	}
}

func TestOneRecognisedLineDoesNotMakeALogExamined(t *testing.T) {
	h := newGuardRouter(t)
	junk := strings.Repeat("this line is in no format the parser reads\n", 500)

	for _, route := range shutdownRoutes() {
		t.Run(route.name+"/500 unread lines and one entry", func(t *testing.T) {
			assertPartlyExamined(t, route.send(t, h, junk+iosEntry), "shutdown log lines in an unread format")
		})
		t.Run(route.name+"/500 unread lines and one device line", func(t *testing.T) {
			rec := route.send(t, h, junk+"\t\tremaining client pid: 1 (/usr/libexec/a)\n")
			assertPartlyExamined(t, rec, "shutdown log lines in an unread format")
		})
		t.Run(route.name+"/a critical finding stands and lists the skipped lines", func(t *testing.T) {
			rec := route.send(t, h, junk+deviceLogPegasus)
			assertHasFindings(t, rec)
			assertStrings(t, "not_examined", rawData(t, rec)["not_examined"], []string{"shutdown log lines in an unread format"})
		})
	}
	for _, route := range logcatRoutes() {
		t.Run(route.name+"/500 unread lines and one entry", func(t *testing.T) {
			assertPartlyExamined(t, route.send(t, h, junk+logcatThreadtime), "logcat lines in an unread format")
		})
		t.Run(route.name+"/a medium finding does not stand", func(t *testing.T) {
			rec := route.send(t, h, junk+"11-21 08:12:33.123  1234  5678 W Agent: location tracking on\n")
			assertPartlyExamined(t, rec, "logcat lines in an unread format")
		})
		t.Run(route.name+"/a critical finding stands and lists the skipped lines", func(t *testing.T) {
			rec := route.send(t, h, junk+"11-21 08:12:33.123  1234  5678 W Agent: pegasus implant started\n")
			assertHasFindings(t, rec)
			assertStrings(t, "not_examined", rawData(t, rec)["not_examined"], []string{"logcat lines in an unread format"})
		})
		t.Run(route.name+"/uid column lines are read", func(t *testing.T) {
			spy := strings.Repeat("11-21 08:12:33.123  1000  1234  5678 W Agent: pegasus implant started\n", 500)
			rec := route.send(t, h, spy+logcatThreadtime)
			if got := decodeJSON(t, rec.Body.Bytes())["total_anomalies"]; got != float64(500) {
				t.Fatalf("want all 500 lines read, got %v", got)
			}
			if _, ok := rawData(t, rec)["not_examined"]; ok {
				t.Fatalf("nothing was skipped: %v", rawData(t, rec)["not_examined"])
			}
		})
		t.Run(route.name+"/named uid column lines are read", func(t *testing.T) {
			rec := route.send(t, h, "11-21 08:12:33.123 u0_a123  1234  5678 I ActivityManager: Displayed\n")
			assertExaminedClean(t, rec)
		})
	}

	// SYNTHETIC bugreport layout: only its log sections are logs.
	dumps := strings.Repeat("  mService=Foo{1234 bar}\n", 500)
	bugreport := func(log string) string {
		return "== dumpstate: 2026-11-21 08:00:00\n" +
			"------ MEMORY INFO (/proc/meminfo) ------\n" + dumps +
			"------ SYSTEM LOG (logcat -v threadtime -v printable -v uid -d *:v) ------\n" +
			"--------- beginning of main\n" + log +
			"------ 0.123s was the duration of 'SYSTEM LOG' ------\n" +
			"------ DUMPSYS (/system/bin/dumpsys) ------\n" + dumps
	}
	uidLine := "11-21 08:12:33.123  1000  1234  5678 I ActivityManager: Displayed\n"
	for _, name := range []string{"bugreport.txt", "bugreport.zip"} {
		send := func(text string) *httptest.ResponseRecorder {
			content := []byte(text)
			if strings.HasSuffix(name, ".zip") {
				content = zipOf(t, map[string][]byte{"bugreport-device.txt": content})
			}
			return upload(h, "/api/v1/forensics/android/bugreport/upload", name, content, asDevice())
		}
		t.Run(name+"/other sections do not count", func(t *testing.T) {
			assertExaminedClean(t, send(bugreport(strings.Repeat(uidLine, 20))))
		})
		t.Run(name+"/an unread log section is not clean", func(t *testing.T) {
			rec := send(bugreport(uidLine + strings.Repeat("in no format\n", 20)))
			assertPartlyExamined(t, rec, "logcat lines in an unread format")
		})
	}

	send := func(platform, log string) *httptest.ResponseRecorder {
		raw, _ := json.Marshal(map[string]string{"platform": platform, "log_data": log})
		return do(h, http.MethodPost, "/api/v1/forensics/quick-check", bytes.NewReader(raw), asDevice())
	}
	for platform, line := range map[string]string{"ios": iosEntry, "android": logcatThreadtime} {
		t.Run("quick-check/"+platform+"/500 unread lines and one entry", func(t *testing.T) {
			rec := send(platform, strings.Repeat("in no format\n", 500)+line)
			assertNothingExamined(t, rec.Code, rec.Body.Bytes())
		})
	}
	t.Run("quick-check/device format is read", func(t *testing.T) {
		rec := send("ios", "\t\tremaining client pid: 1 (/usr/sbin/cfprefsd)\nSIGTERM: [1763712000]\n")
		if rec.Code != http.StatusOK {
			t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
		}
	})
}

func TestPartialResultNeedsAHighFinding(t *testing.T) {
	h := newGuardRouter(t)
	medium := archiveEntry{"x/WiFi/a.log", []byte("resolved host.duckdns.org")}
	unreadable := archiveEntry{shutdownEntry, []byte("this is not a log\n")}
	for _, kind := range archiveKinds() {
		t.Run(kind.name+"/medium finding and an unread log", func(t *testing.T) {
			rec := kind.send(t, h, medium, unreadable)
			if rec.Code != http.StatusUnprocessableEntity || decodeJSON(t, rec.Body.Bytes())["code"] != "partly_examined" {
				t.Fatalf("want partly_examined, got %d: %s", rec.Code, rec.Body.String())
			}
		})
		t.Run(kind.name+"/medium finding and nothing skipped", func(t *testing.T) {
			assertHasFindings(t, kind.send(t, h, medium))
		})
		t.Run(kind.name+"/critical finding and an unread log", func(t *testing.T) {
			rec := kind.send(t, h, archiveEntry{lockdownEntry, []byte(spywareInText)}, unreadable)
			assertHasFindings(t, rec)
			if _, ok := rawData(t, rec)["not_examined"]; !ok {
				t.Fatalf("the skipped log must be listed: %s", rec.Body.String())
			}
		})
	}

	full := func(fields map[string]any) *httptest.ResponseRecorder {
		fields["device_id"] = "d"
		fields["platform"] = "ios"
		raw, _ := json.Marshal(fields)
		return do(h, http.MethodPost, "/api/v1/forensics/full-analysis", bytes.NewReader(raw), asService())
	}
	empty := t.TempDir()
	t.Run("full analysis/medium finding and a skipped backup", func(t *testing.T) {
		dir := sysdiagnoseDir(t, map[string]string{"WiFi/a.log": "resolved host.duckdns.org"})
		assertPartlyExamined(t, full(map[string]any{"sysdiagnose_path": dir, "backup_path": empty}), "backup")
	})
	t.Run("full analysis/a log read in part is listed", func(t *testing.T) {
		rec := full(map[string]any{"shutdown_log": strings.Repeat("in no format\n", 50) + deviceLogPegasus})
		assertHasFindings(t, rec)
		assertStrings(t, "not_examined", rawData(t, rec)["not_examined"], []string{"shutdown_log"})
	})
	t.Run("full analysis/a logcat read in part is listed", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"device_id": "d", "platform": "android",
			"logcat_data": strings.Repeat("in no format\n", 50) + "11-21 08:12:33.123  1234  5678 W Agent: pegasus implant started\n",
		})
		rec := do(h, http.MethodPost, "/api/v1/forensics/full-analysis", bytes.NewReader(body), asService())
		assertHasFindings(t, rec)
		assertStrings(t, "not_examined", rawData(t, rec)["not_examined"], []string{"logcat"})
	})
}

func TestSysdiagnoseDirectoryKeepsEveryFile(t *testing.T) {
	h := newGuardRouter(t)
	dir := t.TempDir()
	for name, content := range map[string]string{"logs/SpringBoard/a.log": "launchd suspicious", "logs/SpringBoard/b.log": "hello"} {
		path := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	body, _ := json.Marshal(map[string]string{"device_id": "d", "archive_path": dir})
	rec := do(h, http.MethodPost, "/api/v1/forensics/analyze/sysdiagnose", bytes.NewReader(body), asService())
	if got := countDescription(t, rec, "Unknown daemon registered"); got != 1 {
		t.Fatalf("want 1, got %d: %s", got, rec.Body.String())
	}
}
