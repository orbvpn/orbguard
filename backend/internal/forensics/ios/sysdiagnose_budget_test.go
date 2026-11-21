package ios

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"context"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"sync/atomic"
	"testing"

	"orbguard-lab/internal/forensics/models"
)

const budgetSpyware = "seen /private/var/db/0123456789abcdef0123456789abcdef here\n"

func canceledContext() context.Context {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	return ctx
}

// endsAfter is a context whose Err turns non-nil after n calls.
type endsAfter struct {
	context.Context
	calls atomic.Int64
	n     int64
}

func (c *endsAfter) Err() error {
	if c.calls.Add(1) > c.n {
		return context.DeadlineExceeded
	}
	return nil
}

func budgetArchives(t *testing.T, content string) map[string]string {
	t.Helper()
	dir := t.TempDir()

	tgz := filepath.Join(dir, "a.tar.gz")
	var tb bytes.Buffer
	gz := gzip.NewWriter(&tb)
	tw := tar.NewWriter(gz)
	if err := tw.WriteHeader(&tar.Header{Name: "logs/lockdownd/a.log", Mode: 0o600, Size: int64(len(content))}); err != nil {
		t.Fatal(err)
	}
	if _, err := tw.Write([]byte(content)); err != nil {
		t.Fatal(err)
	}
	tw.Close()
	gz.Close()
	if err := os.WriteFile(tgz, tb.Bytes(), 0o600); err != nil {
		t.Fatal(err)
	}

	zipPath := filepath.Join(dir, "a.zip")
	var zb bytes.Buffer
	zw := zip.NewWriter(&zb)
	w, err := zw.Create("logs/lockdownd/a.log")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write([]byte(content)); err != nil {
		t.Fatal(err)
	}
	zw.Close()
	if err := os.WriteFile(zipPath, zb.Bytes(), 0o600); err != nil {
		t.Fatal(err)
	}

	folder := filepath.Join(dir, "folder", "logs", "lockdownd")
	if err := os.MkdirAll(folder, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(folder, "a.log"), []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return map[string]string{"tar.gz": tgz, "zip": zipPath, "directory": filepath.Join(dir, "folder")}
}

func TestEndedContextIsNeverClean(t *testing.T) {
	p := NewSysdiagnoseParser(testParserLogger())
	for name, path := range budgetArchives(t, "hello\n") {
		t.Run(name, func(t *testing.T) {
			_, err := p.ParseContext(canceledContext(), path)
			var partly *models.PartlyExaminedError
			if !errors.As(err, &partly) || !slices.Contains(partly.NotExamined, sysdiagnoseOutOfTime) {
				t.Fatalf("want a partial answer naming the time limit, got %v", err)
			}
		})
		t.Run(name+"/a live context reads it", func(t *testing.T) {
			if _, err := p.ParseContext(context.Background(), path); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestTimeBudgetStopsBetweenEntries(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	visited := 0
	x := &sysdiagnoseExtraction{ctx: ctx, unread: make(map[string]bool), visit: func(sysdiagnoseEntry) bool {
		visited++
		cancel()
		return true
	}}
	if !x.add("logs/lockdownd/a.log", 1, openBytes([]byte("a"))) {
		t.Fatal("the first entry must be read")
	}
	if x.add("logs/lockdownd/b.log", 1, openBytes([]byte("b"))) {
		t.Fatal("reading must stop once the budget has ended")
	}
	if visited != 1 || !x.stoppedEarly {
		t.Fatalf("visited %d, stopped early %v", visited, x.stoppedEarly)
	}
	if got := x.notExamined(); len(got) != 1 || got[0] != sysdiagnoseOutOfTime {
		t.Fatalf("not examined: %v", got)
	}
}

func TestTimeBudgetStopsInsideALargeEntry(t *testing.T) {
	p := NewSysdiagnoseParser(testParserLogger())
	content := bytes.Repeat([]byte("ordinary log line\n"), 3*ruleScanChunk/18)
	result := models.NewForensicResult("", "ios", models.ForensicScanTypeSysdiagnose)
	if p.analyzeFile(&endsAfter{Context: context.Background(), n: 1}, sysdiagnoseEntry{name: "a.log", content: content}, result, models.NewTimeline()) {
		t.Fatal("the scan must report that it stopped")
	}

	x := &sysdiagnoseExtraction{ctx: &endsAfter{Context: context.Background(), n: 1}, unread: make(map[string]bool)}
	p.examineEntry(sysdiagnoseEntry{name: "logs/lockdownd/big.log", content: content}, x, result, models.NewTimeline())
	if got := x.notExamined(); len(got) != 1 || got[0] != "logs/lockdownd/big.log" {
		t.Fatalf("the entry cut short must be listed: %v", got)
	}
}

func TestTimeBudgetStopsAfterTheRules(t *testing.T) {
	p := NewSysdiagnoseParser(testParserLogger())
	calls := &endsAfter{Context: context.Background(), n: 1 << 40}
	x := &sysdiagnoseExtraction{ctx: calls, unread: make(map[string]bool)}
	result := models.NewForensicResult("", "ios", models.ForensicScanTypeSysdiagnose)
	p.examineEntry(sysdiagnoseEntry{name: "logs/lockdownd/a.log", content: []byte("hello\n")}, x, result, models.NewTimeline())
	used := calls.calls.Load()

	// Err first fails at the check that follows the rule scans.
	x = &sysdiagnoseExtraction{ctx: &endsAfter{Context: context.Background(), n: used - 1}, unread: make(map[string]bool)}
	p.examineEntry(sysdiagnoseEntry{name: "logs/lockdownd/a.log", content: []byte("hello\n")}, x, result, models.NewTimeline())
	if got := x.notExamined(); len(got) != 1 {
		t.Fatalf("the entry must be listed: %v", got)
	}
}

func TestShutdownParseStopsAtTheBudget(t *testing.T) {
	p := NewShutdownLogParser(testParserLogger())
	log := bytes.Repeat([]byte("\t\tremaining client pid: 1 (/usr/libexec/a)\n"), 3000)
	_, err := p.parse(canceledContext(), log)
	var partly *models.PartlyExaminedError
	if !errors.As(err, &partly) {
		t.Fatalf("want a partial answer, got %v", err)
	}
	if _, err := p.parse(context.Background(), log); err != nil {
		t.Fatal(err)
	}
}

func TestRuleScanAcrossChunks(t *testing.T) {
	re := regexp.MustCompile(`(?m)\bneedle\b|^start`)
	find := func(content []byte) [][]int {
		t.Helper()
		found, complete := findRuleMatches(context.Background(), re, content, 20)
		if !complete {
			t.Fatal("the scan must finish")
		}
		return found
	}
	filler := func(n int) []byte { return bytes.Repeat([]byte("x"), n) }

	t.Run("a hit across the cut is found once", func(t *testing.T) {
		content := append(filler(ruleScanChunk-3), []byte(" needle ")...)
		content = append(content, filler(ruleScanChunk)...)
		got := find(content)
		if len(got) != 1 || string(content[got[0][0]:got[0][1]]) != "needle" {
			t.Fatalf("got %v", got)
		}
	})
	t.Run("a hit inside the overlap is found once", func(t *testing.T) {
		content := append(filler(ruleScanChunk-100), []byte(" needle ")...)
		content = append(content, filler(ruleScanChunk)...)
		if got := find(content); len(got) != 1 {
			t.Fatalf("got %v", got)
		}
	})
	t.Run("a word cut at the chunk end is not a hit", func(t *testing.T) {
		content := append(filler(ruleScanChunk-7), []byte(" needles")...)
		content = append(content, filler(ruleScanChunk)...)
		if got := find(content); len(got) != 0 {
			t.Fatalf("got %v", got)
		}
	})
	t.Run("a word cut at the chunk start is not a hit", func(t *testing.T) {
		content := append(filler(ruleScanChunk-ruleScanOverlap-1), []byte("xneedle ")...)
		content = append(content, filler(ruleScanChunk)...)
		if got := find(content); len(got) != 0 {
			t.Fatalf("got %v", got)
		}
	})
	t.Run("a chunk start inside a line is not a line start", func(t *testing.T) {
		content := append(filler(ruleScanChunk-ruleScanOverlap), []byte("start")...)
		content = append(content, filler(ruleScanChunk)...)
		if got := find(content); len(got) != 0 {
			t.Fatalf("got %v", got)
		}
	})
	t.Run("hits on both sides of a cut", func(t *testing.T) {
		line := []byte("a needle b\n")
		content := bytes.Repeat(line, 2*ruleScanChunk/len(line))
		found, _ := findRuleMatches(context.Background(), re, content, len(content))
		if len(found) != len(content)/len(line) {
			t.Fatalf("want %d hits, got %d", len(content)/len(line), len(found))
		}
		for i := 1; i < len(found); i++ {
			if found[i][0] <= found[i-1][0] {
				t.Fatalf("a hit was repeated at %d", found[i][0])
			}
		}
	})
	t.Run("the limit holds", func(t *testing.T) {
		if got := find(bytes.Repeat([]byte("a needle b\n"), 100)); len(got) != 20 {
			t.Fatalf("got %d", len(got))
		}
	})
	t.Run("an ended context stops the scan", func(t *testing.T) {
		if _, complete := findRuleMatches(canceledContext(), re, []byte("needle"), 20); complete {
			t.Fatal("must report that it stopped")
		}
	})
}

func TestCapacityIsNotBlamedOnTheFile(t *testing.T) {
	p := NewSysdiagnoseParser(testParserLogger())
	defer sysdiagnoseInFlight.Store(0)

	t.Run("refused with no finding", func(t *testing.T) {
		sysdiagnoseInFlight.Store(maxSysdiagnoseInFlightBytes)
		defer sysdiagnoseInFlight.Store(0)
		for name, path := range budgetArchives(t, "hello\n") {
			if _, err := p.Parse(path); !errors.Is(err, models.ErrAnalysisBusy) {
				t.Fatalf("%s: want the busy answer, got %v", name, err)
			}
		}
	})
	t.Run("a critical finding read before the refusal stands", func(t *testing.T) {
		dir := t.TempDir()
		if err := os.WriteFile(filepath.Join(dir, "a.log"), []byte(budgetSpyware), 0o600); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, "b.log"), bytes.Repeat([]byte("x"), 4096), 0o600); err != nil {
			t.Fatal(err)
		}
		sysdiagnoseInFlight.Store(maxSysdiagnoseInFlightBytes - 1024)
		defer sysdiagnoseInFlight.Store(0)
		result, err := p.Parse(dir)
		if err != nil {
			t.Fatal(err)
		}
		listed, _ := result.RawData["not_examined"].([]string)
		if !slices.Contains(listed, sysdiagnoseRestOfArchive) {
			t.Fatalf("not examined: %v", listed)
		}
	})
}

func TestDirectoryListsWhatItCouldNotRead(t *testing.T) {
	p := NewSysdiagnoseParser(testParserLogger())
	dir := t.TempDir()
	known := filepath.Join(dir, "logs", "lockdownd")
	if err := os.MkdirAll(known, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(known, "a.log"), []byte("hello\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(known, "a.log"), filepath.Join(dir, "link")); err != nil {
		t.Fatal(err)
	}
	if _, err := p.Parse(dir); err != nil {
		t.Fatalf("a symlink holds no data of its own: %v", err)
	}

	locked := filepath.Join(dir, "locked")
	if err := os.Mkdir(locked, 0o000); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(locked, 0o700)
	if _, err := os.ReadDir(locked); err == nil {
		t.Skip("running with rights that ignore the folder mode")
	}
	_, err := p.Parse(dir)
	var partly *models.PartlyExaminedError
	if !errors.As(err, &partly) || !slices.Contains(partly.NotExamined, "locked") {
		t.Fatalf("want the unreadable folder listed, got %v", err)
	}
}

func TestOversizedDirectoryInAZipIsNotExamined(t *testing.T) {
	var b bytes.Buffer
	zw := zip.NewWriter(&b)
	name := strings.Repeat("n", 1000)
	for i := 0; i < 9000; i++ {
		if _, err := zw.Create(name); err != nil {
			t.Fatal(err)
		}
	}
	zw.Close()
	path := filepath.Join(t.TempDir(), "a.zip")
	if err := os.WriteFile(path, b.Bytes(), 0o600); err != nil {
		t.Fatal(err)
	}
	_, err := NewSysdiagnoseParser(testParserLogger()).Parse(path)
	var partly *models.PartlyExaminedError
	if !errors.As(err, &partly) || !slices.Contains(partly.NotExamined, sysdiagnoseRestOfArchive) {
		t.Fatalf("want a partial answer, got %v", err)
	}
}
