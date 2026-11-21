package ios

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"orbguard-lab/internal/forensics/models"
)

const shutdownLimitNote = "shutdown log beyond the line or findings limit"

func TestStatusLinesAloneAreNotAShutdownLog(t *testing.T) {
	p := NewShutdownLogParser(testParserLogger())
	status := "After 0.12s, these clients are still here:\n"
	if p.Recognises([]byte(strings.Repeat(status, 5))) {
		t.Fatal("status lines alone must not read as a shutdown log")
	}
	if !p.Recognises([]byte(status + strings.Repeat("\t\tremaining client pid: 1 (/usr/libexec/a)\n", 3))) {
		t.Fatal("a status line and a client line read as a shutdown log")
	}
}

func TestClientFindingCapIsNotClean(t *testing.T) {
	p := NewShutdownLogParser(testParserLogger())
	var log bytes.Buffer
	for i := 0; i < maxShutdownFindings+5; i++ {
		fmt.Fprintf(&log, "\t\tremaining client pid: %d (/private/var/db/x/p%d)\n", i, i)
	}
	result, err := p.Parse(log.Bytes())
	if err != nil {
		t.Fatal(err)
	}
	if got := len(result.Anomalies); got != maxShutdownFindings {
		t.Fatalf("want %d findings, got %d", maxShutdownFindings, got)
	}
	listed, _ := result.RawData["not_examined"].([]string)
	if !slices.Contains(listed, shutdownLimitNote) {
		t.Fatalf("not examined: %v", listed)
	}
}

func TestStickyFindingCapIsNotClean(t *testing.T) {
	p := NewShutdownLogParser(testParserLogger())
	var log bytes.Buffer
	log.WriteString("\t\tremaining client pid: 1 (/private/var/db/x/first)\n")
	for i := 0; i < maxShutdownFindings+5; i++ {
		fmt.Fprintf(&log, "2026-11-21 08:12:33.123 +0000 %d proc%d[%d]: path: /private/var/tmp/s%d\n", i, i, i, i)
	}
	result, err := p.Parse(log.Bytes())
	if err != nil {
		t.Fatal(err)
	}
	if got := len(result.Anomalies); got != maxShutdownFindings {
		t.Fatalf("want %d findings, got %d", maxShutdownFindings, got)
	}
	listed, _ := result.RawData["not_examined"].([]string)
	if !slices.Contains(listed, shutdownLimitNote) {
		t.Fatalf("not examined: %v", listed)
	}
}

func TestClientPathNamedRebootIsNotARebootEvent(t *testing.T) {
	p := NewShutdownLogParser(testParserLogger())
	result, err := p.Parse([]byte(strings.Repeat("\t\tremaining client pid: 1 (/usr/libexec/rebootd)\n", 3) + "SIGTERM: [1763712000]\n"))
	if err != nil {
		t.Fatal(err)
	}
	if got := result.RawData["reboot_count"]; got != 1 {
		t.Fatalf("reboot_count: want 1, got %v", got)
	}
	if got := len(result.Timeline); got != 1 {
		t.Fatalf("timeline: want the marker only, got %d events", got)
	}
}

func TestRuleMatchesTheKeyOrTheBaseName(t *testing.T) {
	for _, c := range []struct {
		name  string
		entry sysdiagnoseEntry
		want  bool
	}{
		{"key", sysdiagnoseEntry{name: "logs/x/a.log", keys: []string{"wifi"}}, true},
		{"base name", sysdiagnoseEntry{name: "other/wifi_status.txt"}, true},
		{"folder only", sysdiagnoseEntry{name: "wifi/a.log"}, false},
	} {
		if got := c.entry.matchesRule("wifi"); got != c.want {
			t.Errorf("%s: got %v", c.name, got)
		}
	}
}

func TestFindingFloodStopsReadingTheArchive(t *testing.T) {
	dir := t.TempDir()
	hits := strings.Repeat("com.apple.xpc.roleaccountd\n", maxRuleMatchesPerEntry)
	files := maxSysdiagnoseFindings/maxRuleMatchesPerEntry + 10
	for i := 0; i < files; i++ {
		if err := os.WriteFile(filepath.Join(dir, fmt.Sprintf("f%03d.log", i)), []byte(hits), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	result, err := NewSysdiagnoseParser(testParserLogger()).Parse(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got := len(result.Anomalies); got >= files*maxRuleMatchesPerEntry {
		t.Fatalf("reading did not stop: %d findings", got)
	}
	listed, _ := result.RawData["not_examined"].([]string)
	if !slices.Contains(listed, sysdiagnoseRestOfArchive) {
		t.Fatalf("not examined: %v", listed)
	}
}

func TestShutdownMergeKeepsTheCaps(t *testing.T) {
	p := NewSysdiagnoseParser(testParserLogger())
	result := models.NewForensicResult("", "ios", models.ForensicScanTypeSysdiagnose)
	for i := 0; i < maxSysdiagnoseFindings-1; i++ {
		result.AddAnomaly(models.Anomaly{ID: fmt.Sprint(i), Severity: models.ForensicSeverityCritical})
	}
	timeline := models.NewTimeline()
	for i := 0; i < maxSysdiagnoseFindings; i++ {
		timeline.AddEvent(models.TimelineEvent{ID: fmt.Sprint(i)})
	}
	var log bytes.Buffer
	for i := 0; i < 5; i++ {
		fmt.Fprintf(&log, "\t\tremaining client pid: %d (/private/var/db/x/p%d)\n", i, i)
	}
	log.WriteString("SIGTERM: [1763712000]\n")

	const name = "logs/shutdown/shutdown.log"
	x := &sysdiagnoseExtraction{unread: make(map[string]bool)}
	p.examineEntry(sysdiagnoseEntry{name: name, keys: []string{"shutdown.log"}, content: log.Bytes()}, x, result, timeline)

	if got := len(result.Anomalies); got != maxSysdiagnoseFindings {
		t.Fatalf("findings: want %d, got %d", maxSysdiagnoseFindings, got)
	}
	if got := len(timeline.Events); got != maxSysdiagnoseFindings {
		t.Fatalf("timeline: want %d, got %d", maxSysdiagnoseFindings, got)
	}
	if got := x.notExamined(); !slices.Contains(got, name) {
		t.Fatalf("the dropped findings must be listed: %v", got)
	}
}
