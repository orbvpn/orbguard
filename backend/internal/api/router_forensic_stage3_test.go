package api

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"encoding/binary"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// SYNTHETIC. The JSON lines follow the documented .ips crash report fields
// (app_name in the header line; procName, procPath, parentProc and
// responsibleProc in the body; procname in stackshots). None is a device file.
func TestProcessNamesInCrashReportsAndLists(t *testing.T) {
	h := newGuardRouter(t)
	loud := map[string]string{
		"ips header app_name":    `{"app_name":"bh","bug_type":"309","os_version":"iPhone OS 17.4"}` + "\n",
		"ips procName bh":        `{"pid":666,"procName":"bh","cpuType":"ARM-64"}` + "\n",
		"ips procName pcsd":      `{"pid":666,"procName" : "pcsd"}` + "\n",
		"ips procPath bh":        `{"procPath":"\/private\/var\/containers\/bh","pid":666}` + "\n",
		"ips procPath pcsd":      `{"procPath":"\/usr\/libexec\/pcsd"}` + "\n",
		"ips parentProc":         `{"parentProc":"bh","parentPid":1}` + "\n",
		"ips responsibleProc":    `{"responsibleProc":"pcsd","responsiblePid":1}` + "\n",
		"stackshot procname":     `{"pid":666,"procname":"bh"}` + "\n",
		"process list with user": "root 666 0.0 0.1 ?? Ss 0:00.01 bh\n",
		"process list without":   "  666 ?? 0:00.01 pcsd\n",
		"process list crlf":      "root 666 0.0 0.1 ?? Ss 0:00.01 bh\r\n",
		"launch daemon plist":    "/System/Library/LaunchDaemons/com.apple.pcsd.plist\n",
		"launch daemon escaped":  `{"path":"\/Library\/LaunchDaemons\/com.apple.bh.plist"}` + "\n",
		"plist program argument": "<string>/usr/libexec/bh</string>\n",
		"text crash process":     "Process:         bh [666]\n",
		"text crash path":        "Path:            /private/var/containers/bh\n",
	}
	quiet := map[string]string{
		"ordinary word":            "subheading\n",
		"ips other name":           `{"procName":"bhx","app_name":"subh"}` + "\n",
		"ips other path":           `{"procPath":"\/usr\/libexec\/bhx"}` + "\n",
		"ips other field":          `{"note":"bh"}` + "\n",
		"name not the last column": "root 666 0.0 bh extra\n",
		"prose ending in the name": "hello bh\n",
		"plist other daemon":       "/System/Library/LaunchDaemons/com.apple.notifyd.plist\n",
	}
	for _, kind := range archiveKinds() {
		for name, content := range loud {
			t.Run(kind.name+"/loud/"+name, func(t *testing.T) {
				assertHasFindings(t, kind.send(t, h, archiveEntry{"x/crashes_and_spins/a.ips", []byte(content)}))
			})
		}
		for name, content := range quiet {
			t.Run(kind.name+"/quiet/"+name, func(t *testing.T) {
				assertExaminedClean(t, kind.send(t, h, archiveEntry{lockdownEntry, []byte(content)}))
			})
		}
	}
}

func tarWithType(t *testing.T, name string, typeflag byte, content []byte, then archiveEntry) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	for _, e := range []struct {
		name     string
		typeflag byte
		content  []byte
	}{{name, typeflag, content}, {then.name, tar.TypeReg, then.content}} {
		if err := tw.WriteHeader(&tar.Header{Name: e.name, Mode: 0o600, Size: int64(len(e.content)), Typeflag: e.typeflag}); err != nil {
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

func TestEverySkippedEntryIsListed(t *testing.T) {
	h := newGuardRouter(t)
	known := archiveEntry{lockdownEntry, []byte("hello")}

	t.Run("an oversized entry at an unknown path", func(t *testing.T) {
		var buf bytes.Buffer
		zw := zip.NewWriter(&buf)
		raw, err := zw.CreateRaw(&zip.FileHeader{Name: "unknown/big.bin", Method: zip.Store, CompressedSize64: 1, UncompressedSize64: 60 << 20})
		if err != nil {
			t.Fatal(err)
		}
		if _, err := raw.Write([]byte{0}); err != nil {
			t.Fatal(err)
		}
		w, err := zw.Create(known.name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write(known.content); err != nil {
			t.Fatal(err)
		}
		if err := zw.Close(); err != nil {
			t.Fatal(err)
		}
		assertPartlyExamined(t, upload(h, sysdiagnoseUpload, "s.zip", buf.Bytes(), asDevice()), "unknown/big.bin")
	})
	t.Run("an unreadable entry at an unknown path", func(t *testing.T) {
		var buf bytes.Buffer
		zw := zip.NewWriter(&buf)
		raw, err := zw.CreateRaw(&zip.FileHeader{Name: "unknown/bad.bin", Method: 99, CompressedSize64: 1, UncompressedSize64: 1})
		if err != nil {
			t.Fatal(err)
		}
		if _, err := raw.Write([]byte{0}); err != nil {
			t.Fatal(err)
		}
		w, err := zw.Create(known.name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write(known.content); err != nil {
			t.Fatal(err)
		}
		if err := zw.Close(); err != nil {
			t.Fatal(err)
		}
		assertPartlyExamined(t, upload(h, sysdiagnoseUpload, "s.zip", buf.Bytes(), asDevice()), "unknown/bad.bin")
	})
	t.Run("a tar entry of a type that holds data", func(t *testing.T) {
		archive := tarWithType(t, shutdownEntry, tar.TypeCont, []byte(deviceLogPegasus), known)
		assertPartlyExamined(t, upload(h, sysdiagnoseUpload, "s.tar.gz", archive, asDevice()), shutdownEntry)
	})
	for name, typeflag := range map[string]byte{"directory": tar.TypeDir, "symlink": tar.TypeSymlink, "hard link": tar.TypeLink, "fifo": tar.TypeFifo} {
		t.Run("a tar "+name+" holds no data", func(t *testing.T) {
			archive := tarWithType(t, "x/link", typeflag, nil, known)
			assertExaminedClean(t, upload(h, sysdiagnoseUpload, "s.tar.gz", archive, asDevice()))
		})
	}
}

func TestUnreadLinesCannotHideAnIndicator(t *testing.T) {
	h := newGuardRouter(t)
	ordinary := strings.Repeat(logcatThreadtime, 90)
	spy := "pegasus implant started in a drifted format\n"
	const unread = "logcat lines in an unread format"

	for _, route := range logcatRoutes() {
		t.Run(route.name+"/90 ordinary and 10 unread with a name", func(t *testing.T) {
			assertPartlyExamined(t, route.send(t, h, ordinary+strings.Repeat(spy, 10)), unread)
		})
		t.Run(route.name+"/banners do not count as read", func(t *testing.T) {
			log := logcatThreadtime + strings.Repeat("--------- beginning of main\n", 9000) + strings.Repeat("in no format\n", 1000)
			assertPartlyExamined(t, route.send(t, h, log), unread)
		})
		t.Run(route.name+"/an unread name in another section", func(t *testing.T) {
			log := "------ SYSTEM LOG (logcat -v threadtime) ------\n" + strings.Repeat(logcatThreadtime, 3) +
				"------ OTHER (/proc/x) ------\n" + strings.Repeat(spy, 500)
			assertPartlyExamined(t, route.send(t, h, log), unread)
		})
		t.Run(route.name+"/too few entries", func(t *testing.T) {
			assertPartlyExamined(t, route.send(t, h, logcatLine), "too few logcat entries to call the log read")
		})
		t.Run(route.name+"/a few noise lines stay clean", func(t *testing.T) {
			assertExaminedClean(t, route.send(t, h, ordinary+strings.Repeat("noise line\n", 10)))
		})
		t.Run(route.name+"/banners stay clean", func(t *testing.T) {
			log := "--------- beginning of main\n--------- beginning of system\n" + strings.Repeat(logcatThreadtime, 3)
			assertExaminedClean(t, route.send(t, h, log))
		})
	}

	clients := strings.Repeat("\t\tremaining client pid: 1 (/usr/libexec/a)\n", 9)
	for _, route := range shutdownRoutes() {
		for name, drifted := range map[string]string{
			"db folder":  "remaining client: 666 /private/var/db/x/y\n",
			"tmp folder": "remaining client: 666 /private/var/tmp/x/y\n",
			"known name": "remaining client: 666 bh\n",
		} {
			t.Run(route.name+"/9 ordinary and 1 drifted, "+name, func(t *testing.T) {
				assertPartlyExamined(t, route.send(t, h, clients+drifted), "shutdown log lines in an unread format")
			})
		}
		t.Run(route.name+"/a marker alone is not a log", func(t *testing.T) {
			rec := route.send(t, h, "SIGTERM: [1700000000]\n")
			assertNothingExamined(t, rec.Code, rec.Body.Bytes())
		})
		t.Run(route.name+"/too few entries", func(t *testing.T) {
			rec := route.send(t, h, "\t\tremaining client pid: 1 (/usr/libexec/a)\nSIGTERM: [1700000000]\n")
			assertPartlyExamined(t, rec, "too few shutdown log entries to call the log read")
		})
		t.Run(route.name+"/an ordinary unread line stays clean", func(t *testing.T) {
			assertExaminedClean(t, route.send(t, h, clients+"some other status line\n"))
		})
		t.Run(route.name+"/the real CommCenter in an unread line stays clean", func(t *testing.T) {
			assertExaminedClean(t, route.send(t, h, clients+"status of CommCenter: running\n"))
		})
	}

	quick := func(platform, log string) *httptest.ResponseRecorder {
		raw, _ := json.Marshal(map[string]string{"platform": platform, "log_data": log})
		return do(h, http.MethodPost, "/api/v1/forensics/quick-check", bytes.NewReader(raw), asDevice())
	}
	t.Run("quick-check/one entry is not a log", func(t *testing.T) {
		rec := quick("android", logcatLine)
		assertNothingExamined(t, rec.Code, rec.Body.Bytes())
	})
	t.Run("quick-check/an unread name is not clean", func(t *testing.T) {
		rec := quick("android", strings.Repeat(logcatThreadtime, 90)+strings.Repeat("cocospy in a drifted format\n", 10))
		assertNothingExamined(t, rec.Code, rec.Body.Bytes())
	})
	t.Run("quick-check/a marker alone is not a log", func(t *testing.T) {
		rec := quick("ios", "SIGTERM: [1700000000]\n")
		assertNothingExamined(t, rec.Code, rec.Body.Bytes())
	})
	t.Run("quick-check/ios unread name is not clean", func(t *testing.T) {
		rec := quick("ios", clients+"remaining client: 666 implant\n")
		assertNothingExamined(t, rec.Code, rec.Body.Bytes())
	})
	t.Run("quick-check/three entries read", func(t *testing.T) {
		rec := quick("android", strings.Repeat(logcatThreadtime, 3))
		if rec.Code != http.StatusOK {
			t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
		}
	})
}

func TestKnownNamesOutsideTheStagingFolders(t *testing.T) {
	h := newGuardRouter(t)
	padding := "\t\tremaining client pid: 2 (/usr/libexec/a)\n\t\tremaining client pid: 3 (/usr/sbin/b)\n"
	for _, route := range shutdownRoutes() {
		for _, spyPath := range []string{"/usr/libexec/bh", "/private/var/mobile/pcsd", "/var/db/x/bh", "/usr/sbin/roleaccountd", "/tmp/implant"} {
			t.Run(route.name+"/"+spyPath, func(t *testing.T) {
				rec := route.send(t, h, padding+"\t\tremaining client pid: 666 ("+spyPath+")\n")
				if rec.Code != http.StatusOK {
					t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
				}
				found := anomaliesOf(t, rec)
				if len(found) != 1 || found[0]["path"] != spyPath || found[0]["severity"] != "critical" {
					t.Fatalf("want one critical finding: %s", rec.Body.String())
				}
			})
		}
		for _, normal := range []string{
			"/usr/libexec/xpcproxy",
			"/usr/sbin/cfprefsd",
			"/System/Library/PrivateFrameworks/Foo.framework/agent",
			"/System/Library/PrivateFrameworks/CoreTelephony.framework/Support/CommCenter",
			"/Applications/MobileMail.app/MobileMail",
		} {
			t.Run(route.name+"/normal "+normal, func(t *testing.T) {
				assertExaminedClean(t, route.send(t, h, padding+"\t\tremaining client pid: 9 ("+normal+")\n"))
			})
		}
	}
}

const logcatLimitNote = "logcat beyond the size, findings or time limit"

func TestLogcatFindingsAreBounded(t *testing.T) {
	h := newGuardRouter(t)
	spy := strings.Repeat("11-21 08:12:33.123  1234  5678 W Agent: pegasus implant started\n", 1500)
	for _, route := range logcatRoutes() {
		t.Run(route.name, func(t *testing.T) {
			rec := route.send(t, h, spy)
			if got := decodeJSON(t, rec.Body.Bytes())["total_anomalies"]; got != float64(1000) {
				t.Fatalf("want 1000 findings, got %v", got)
			}
			assertStrings(t, "not_examined", rawData(t, rec)["not_examined"], []string{logcatLimitNote})
		})
	}
}

func TestLogUploadOverItsLimitIsNeverClean(t *testing.T) {
	h := newGuardRouter(t)
	t.Run("logcat", func(t *testing.T) {
		log := strings.Repeat(logcatThreadtime, (10<<20)/len(logcatThreadtime)+10)
		rec := upload(h, "/api/v1/forensics/android/logcat/upload", "logcat.txt", []byte(log), asDevice())
		assertPartlyExamined(t, rec, logcatLimitNote)
	})
	line := "\t\tremaining client pid: 1 (/usr/libexec/" + strings.Repeat("a", 200) + ")\n"
	t.Run("shutdown log", func(t *testing.T) {
		log := strings.Repeat(line, (10<<20)/len(line)+10)
		rec := upload(h, "/api/v1/forensics/ios/shutdown-log/upload", "shutdown.log", []byte(log), asDevice())
		assertPartlyExamined(t, rec, "shutdown log beyond the upload limit")
	})
	t.Run("shutdown log with a finding keeps it", func(t *testing.T) {
		log := "\t\tremaining client pid: 6 (" + pegasusSamplePath + ")\n" + strings.Repeat(line, (10<<20)/len(line)+10)
		rec := upload(h, "/api/v1/forensics/ios/shutdown-log/upload", "shutdown.log", []byte(log), asDevice())
		assertHasFindings(t, rec)
		assertStrings(t, "not_examined", rawData(t, rec)["not_examined"], []string{"shutdown log beyond the upload limit"})
	})
	t.Run("shutdown log at the limit is read", func(t *testing.T) {
		log := strings.Repeat(line, (10<<20)/len(line))
		assertExaminedClean(t, upload(h, "/api/v1/forensics/ios/shutdown-log/upload", "shutdown.log", []byte(log), asDevice()))
	})
}

// zipOfRecords builds a zip whose directory holds n records of one empty file.
func zipOfRecords(n int) []byte {
	var b bytes.Buffer
	b.Grow(47*n + 53)
	local := make([]byte, 30)
	binary.LittleEndian.PutUint32(local, 0x04034b50)
	binary.LittleEndian.PutUint16(local[26:], 1)
	b.Write(local)
	b.WriteByte('a')
	start := b.Len()
	record := make([]byte, 47)
	binary.LittleEndian.PutUint32(record, 0x02014b50)
	binary.LittleEndian.PutUint16(record[28:], 1)
	record[46] = 'a'
	for i := 0; i < n; i++ {
		b.Write(record)
	}
	end := make([]byte, 22)
	binary.LittleEndian.PutUint32(end, 0x06054b50)
	binary.LittleEndian.PutUint16(end[8:], uint16(n))
	binary.LittleEndian.PutUint16(end[10:], uint16(n))
	binary.LittleEndian.PutUint32(end[12:], uint32(b.Len()-start))
	binary.LittleEndian.PutUint32(end[16:], uint32(start))
	b.Write(end)
	return b.Bytes()
}

func TestZipDirectoryOverTheLimitIsRefused(t *testing.T) {
	h := newGuardRouter(t)
	small := zipOfRecords(200_000)
	assertRefused := func(t *testing.T, rec *httptest.ResponseRecorder) {
		t.Helper()
		if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "directory is over the limit") {
			t.Fatalf("want a clear refusal, got %d: %.200s", rec.Code, rec.Body.String())
		}
	}
	t.Run("bugreport", func(t *testing.T) {
		assertRefused(t, upload(h, "/api/v1/forensics/android/bugreport/upload", "bugreport.zip", small, asDevice()))
	})
	t.Run("backup", func(t *testing.T) {
		assertRefused(t, upload(h, "/api/v1/forensics/ios/backup/upload", "backup.zip", zipOfRecords(800_000), asDevice()))
	})
	t.Run("sysdiagnose", func(t *testing.T) {
		rec := upload(h, sysdiagnoseUpload, "s.zip", small, asDevice())
		assertPartlyExamined(t, rec, "rest of the archive: over the size, entry or findings limit")
		if strings.Contains(rec.Body.String(), "anomalies") {
			t.Fatalf("a refusal must not look like a result: %.200s", rec.Body.String())
		}
	})
}
