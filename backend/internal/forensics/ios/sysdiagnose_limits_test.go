package ios

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"math"
	"testing"

	"github.com/rs/zerolog"

	"orbguard-lab/internal/forensics/models"
	"orbguard-lab/pkg/logger"
)

func testParserLogger() *logger.Logger {
	return &logger.Logger{Logger: zerolog.Nop()}
}

func newLimitExtraction(visited *int) *sysdiagnoseExtraction {
	return &sysdiagnoseExtraction{
		unread: make(map[string]bool),
		visit: func(sysdiagnoseEntry) bool {
			*visited++
			return true
		},
	}
}

func openBytes(content []byte) func() (io.ReadCloser, error) {
	return func() (io.ReadCloser, error) {
		return io.NopCloser(bytes.NewReader(content)), nil
	}
}

func TestEntryCountCapStopsReading(t *testing.T) {
	visited := 0
	x := newLimitExtraction(&visited)
	for i := 0; i < maxSysdiagnoseEntries; i++ {
		if !x.add("notes.txt", 0, openBytes(nil)) {
			t.Fatalf("stopped early at entry %d", i)
		}
	}
	if x.add("notes.txt", 0, openBytes(nil)) {
		t.Fatal("the entry over the cap must stop reading")
	}
	if visited != maxSysdiagnoseEntries {
		t.Fatalf("visited %d entries", visited)
	}
	if got := x.notExamined(); len(got) != 1 || got[0] != sysdiagnoseRestOfArchive {
		t.Fatalf("not examined: %v", got)
	}
}

func TestTotalBudgetCountsEntriesItDidNotRead(t *testing.T) {
	visited := 0
	x := newLimitExtraction(&visited)
	refuse := func() (io.ReadCloser, error) {
		t.Fatal("an entry over the cap must not be opened")
		return nil, nil
	}
	total := int64(0)
	for total+maxSysdiagnoseEntryBytes+1 <= maxSysdiagnoseTotalBytes {
		if !x.add("notes.bin", maxSysdiagnoseEntryBytes+1, refuse) {
			t.Fatal("stopped before the budget")
		}
		total += maxSysdiagnoseEntryBytes + 1
	}
	if x.add("notes.bin", maxSysdiagnoseEntryBytes+1, refuse) {
		t.Fatal("the entry over the budget must stop reading")
	}
	if got := x.notExamined(); len(got) != 1 || got[0] != sysdiagnoseRestOfArchive {
		t.Fatalf("not examined: %v", got)
	}
}

func TestTotalBudgetSurvivesAHugeDeclaredSize(t *testing.T) {
	visited := 0
	x := newLimitExtraction(&visited)
	if !x.add("notes.txt", 4, openBytes([]byte("four"))) {
		t.Fatal("stopped on a small entry")
	}
	if x.add("logs/lockdownd/a.log", math.MaxInt64, openBytes(nil)) {
		t.Fatal("a size that would overflow the total must stop reading")
	}
	if x.totalBytes != 4 {
		t.Fatalf("total: %d", x.totalBytes)
	}
}

func TestInFlightBudgetIsSharedAndReleased(t *testing.T) {
	if got := sysdiagnoseInFlight.Load(); got != 0 {
		t.Fatalf("in flight at start: %d", got)
	}
	visited := 0
	x := newLimitExtraction(&visited)

	sysdiagnoseInFlight.Store(maxSysdiagnoseInFlightBytes - 3)
	defer sysdiagnoseInFlight.Store(0)
	if x.add("logs/lockdownd/a.log", 4, openBytes([]byte("four"))) {
		t.Fatal("an entry over the shared budget must stop reading")
	}
	if visited != 0 {
		t.Fatal("the entry must not be analysed")
	}
	if got := sysdiagnoseInFlight.Load(); got != maxSysdiagnoseInFlightBytes-3 {
		t.Fatalf("a refused reservation must be returned: %d", got)
	}

	sysdiagnoseInFlight.Store(0)
	y := newLimitExtraction(&visited)
	y.visit = func(e sysdiagnoseEntry) bool {
		if got := sysdiagnoseInFlight.Load(); got != int64(len(e.content)) {
			t.Fatalf("held while analysed: %d", got)
		}
		return true
	}
	if !y.add("logs/lockdownd/a.log", 4, openBytes([]byte("four"))) {
		t.Fatal("stopped")
	}
	if got := sysdiagnoseInFlight.Load(); got != 0 {
		t.Fatalf("not released: %d", got)
	}
}

func TestEntryWithAWrongSizeIsNotExamined(t *testing.T) {
	for name, c := range map[string]struct {
		declared int64
		content  string
	}{
		"holds more than declared": {3, "four"},
		"holds less than declared": {9, "four"},
	} {
		t.Run(name, func(t *testing.T) {
			visited := 0
			x := newLimitExtraction(&visited)
			if !x.add("logs/lockdownd/a.log", c.declared, openBytes([]byte(c.content))) {
				t.Fatal("one bad entry must not stop the archive")
			}
			if visited != 0 {
				t.Fatal("the entry must not be analysed")
			}
			if got := x.notExamined(); len(got) != 1 || got[0] != "logs/lockdownd/a.log" {
				t.Fatalf("not examined: %v", got)
			}
		})
	}
}

func TestUnreadableEntryIsListed(t *testing.T) {
	visited := 0
	x := newLimitExtraction(&visited)
	broken := func() (io.ReadCloser, error) { return nil, errors.New("broken") }
	x.add("logs/lockdownd/a.log", 4, broken)
	x.add("notes.txt", 4, broken)
	if got := x.notExamined(); len(got) != 1 || got[0] != "logs/lockdownd/a.log" {
		t.Fatalf("only the known artifact is listed: %v", got)
	}
}

func TestNotExaminedListIsBounded(t *testing.T) {
	visited := 0
	x := newLimitExtraction(&visited)
	for i := 0; i < maxListedNotExamined+5; i++ {
		x.skip(fmt.Sprintf("logs/lockdownd/%d.log", i))
	}
	x.skip(string(bytes.Repeat([]byte("n"), 4096)))
	got := x.notExamined()
	if len(got) != maxListedNotExamined+1 || got[len(got)-1] != "and 6 more" {
		t.Fatalf("list of %d ending %q", len(got), got[len(got)-1])
	}
	y := newLimitExtraction(&visited)
	y.skip(string(bytes.Repeat([]byte("n"), 4096)))
	if len(y.notExamined()[0]) != 256 {
		t.Fatal("a long name must be cut")
	}
}

func TestFindingFloodIsBounded(t *testing.T) {
	p := NewSysdiagnoseParser(testParserLogger())
	dir := t.TempDir()
	var hits bytes.Buffer
	for i := 0; i < maxRuleMatchesPerEntry*3; i++ {
		hits.WriteString("com.apple.xpc.roleaccountd\n")
	}
	result := models.NewForensicResult("", "ios", models.ForensicScanTypeSysdiagnose)
	x := &sysdiagnoseExtraction{unread: make(map[string]bool)}
	p.analyzeFile(sysdiagnoseEntry{name: dir + "/a.log", content: hits.Bytes()}, result, models.NewTimeline())
	if got := len(result.Anomalies); got != maxRuleMatchesPerEntry {
		t.Fatalf("one rule in one file: want %d findings, got %d", maxRuleMatchesPerEntry, got)
	}

	big := models.NewForensicResult("", "ios", models.ForensicScanTypeSysdiagnose)
	var log bytes.Buffer
	for i := 0; i < maxSysdiagnoseFindings+50; i++ {
		fmt.Fprintf(&log, "\t\tremaining client pid: %d (/private/var/db/x/p%d)\n", i, i)
	}
	p.examineEntry(sysdiagnoseEntry{name: "logs/shutdown/shutdown.log", keys: []string{"shutdown.log"}, content: log.Bytes()}, x, big, models.NewTimeline())
	if got := len(big.Anomalies); got > maxSysdiagnoseFindings {
		t.Fatalf("findings over the cap: %d", got)
	}
	if got := x.notExamined(); len(got) != 1 {
		t.Fatalf("what the cap dropped must be listed: %v", got)
	}
}

func TestShutdownLogLineCapIsNotClean(t *testing.T) {
	p := NewShutdownLogParser(testParserLogger())
	line := []byte("\t\tremaining client pid: 1 (/usr/libexec/a)\n")
	if _, err := p.Parse(bytes.Repeat(line, maxShutdownLogLines)); err != nil {
		t.Fatalf("at the cap: %v", err)
	}
	_, err := p.Parse(bytes.Repeat(line, maxShutdownLogLines+1))
	var partly *models.PartlyExaminedError
	if !errors.As(err, &partly) {
		t.Fatalf("over the cap: want a partial answer, got %v", err)
	}

	withFinding := append(bytes.Repeat(line, maxShutdownLogLines-1), []byte("\t\tremaining client pid: 2 (/private/var/db/x/y)\n")...)
	withFinding = append(withFinding, line...)
	result, err := p.Parse(withFinding)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := result.RawData["not_examined"]; !ok {
		t.Fatal("the lines beyond the cap must be listed")
	}
}

func TestRecognisedEnoughBoundary(t *testing.T) {
	for _, c := range []struct {
		read, total int
		want        bool
	}{
		{0, 0, false}, {1, 1, true}, {9, 10, true}, {8, 10, false}, {1, 501, false}, {90, 100, true}, {89, 100, false},
	} {
		if got := models.RecognisedEnough(c.read, c.total); got != c.want {
			t.Fatalf("%d of %d: got %v", c.read, c.total, got)
		}
	}
}
