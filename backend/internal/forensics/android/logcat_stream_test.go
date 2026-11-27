package android

import (
	"context"
	"errors"
	"io"
	"slices"
	"strings"
	"testing"

	"github.com/rs/zerolog"

	"orbguard-lab/internal/forensics/models"
	"orbguard-lab/pkg/logger"
)

const (
	streamLine    = "11-21 08:12:33.123  1234  5678 I Agent: started\n"
	streamSpyLine = "11-21 08:12:33.123  1234  5678 W Agent: pegasus implant started\n"
	streamNote    = "logcat beyond the size, findings or time limit"
)

func streamParser() *LogcatParser {
	return NewLogcatParser(&logger.Logger{Logger: zerolog.Nop()})
}

func assertStreamPartial(t *testing.T, err error) {
	t.Helper()
	var partly *models.PartlyExaminedError
	if !errors.As(err, &partly) || !slices.Contains(partly.NotExamined, streamNote) {
		t.Fatalf("want a partial answer, got %v", err)
	}
}

func TestStreamOverItsByteLimit(t *testing.T) {
	log := strings.Repeat(streamLine, 10)
	_, err := streamParser().ParseStream(context.Background(), strings.NewReader(log), int64(len(log))-1)
	assertStreamPartial(t, err)
	if _, err := streamParser().ParseStream(context.Background(), strings.NewReader(log), int64(len(log))); err != nil {
		t.Fatalf("exactly at the limit must be read: %v", err)
	}
	if _, err := streamParser().ParseStream(context.Background(), strings.NewReader(log), 0); err != nil {
		t.Fatalf("zero means no limit: %v", err)
	}
}

func TestStreamStopsWhenTheContextEnds(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := streamParser().ParseStream(ctx, strings.NewReader(strings.Repeat(streamLine, 10)), 0)
	assertStreamPartial(t, err)
}

type brokenAfter struct {
	r io.Reader
}

func (b *brokenAfter) Read(p []byte) (int, error) {
	n, err := b.r.Read(p)
	if err == io.EOF {
		return n, errors.New("broken stream")
	}
	return n, err
}

func TestStreamThatBreaksIsNotClean(t *testing.T) {
	r := &brokenAfter{r: strings.NewReader(strings.Repeat(streamLine, 5))}
	_, err := streamParser().ParseStream(context.Background(), r, 0)
	assertStreamPartial(t, err)
}

func TestStreamKeepsAFindingReadBeforeItBroke(t *testing.T) {
	r := &brokenAfter{r: strings.NewReader(streamSpyLine)}
	result, err := streamParser().ParseStream(context.Background(), r, 0)
	if err != nil {
		t.Fatal(err)
	}
	listed, _ := result.RawData["not_examined"].([]string)
	if len(result.Anomalies) != 1 || !slices.Contains(listed, streamNote) {
		t.Fatalf("anomalies %d, not examined %v", len(result.Anomalies), listed)
	}
}

// A line longer than the line limit used to fail the whole analysis, and a
// real bug report has such lines outside its logs (one from an emulator held
// three, the longest 388 KiB). It is now read past, counted as unread.
func TestStreamReadsPastALineOverTheLineLimit(t *testing.T) {
	long := strings.Repeat("x", 70*1024) + "\n"
	log := strings.Repeat(streamLine, 9) + long + streamLine
	result, err := streamParser().ParseStream(context.Background(), strings.NewReader(log), 0)
	if err != nil {
		t.Fatalf("a long line must not fail the analysis: %v", err)
	}
	if got := result.RawData["total_entries"]; got != 10 {
		t.Fatalf("entries read: %v", got)
	}
}

func TestStreamOfOnlyALongLineExaminedNothing(t *testing.T) {
	_, err := streamParser().ParseStream(context.Background(), strings.NewReader(strings.Repeat("x", 70*1024)+"\n"), 0)
	if !errors.Is(err, models.ErrNothingExamined) {
		t.Fatalf("want nothing examined, got %v", err)
	}
}

// A spyware name in the part of a long line that is not kept is still never
// tolerated as noise, wherever it falls, including across two pieces.
func TestStreamNameInTheUnkeptPartOfALongLineIsNotNoise(t *testing.T) {
	for name, at := range map[string]int{
		"well past the kept piece":  100 * 1024,
		"across the piece boundary": maxLogcatLineBytes - 4,
	} {
		t.Run(name, func(t *testing.T) {
			line := strings.Repeat("x", at) + "flexispy" + strings.Repeat("x", 30*1024) + "\n"
			log := strings.Repeat(streamLine, 20) + line
			_, err := streamParser().ParseStream(context.Background(), strings.NewReader(log), 0)
			var partly *models.PartlyExaminedError
			if !errors.As(err, &partly) || !slices.Contains(partly.NotExamined, "logcat lines in an unread format") {
				t.Fatalf("want a partial answer for the unread name, got %v", err)
			}
		})
	}
}

func TestStreamLongLineWithoutANameIsTolerated(t *testing.T) {
	log := strings.Repeat(streamLine, 20) + strings.Repeat("y", 200*1024) + "\n"
	if _, err := streamParser().ParseStream(context.Background(), strings.NewReader(log), 0); err != nil {
		t.Fatalf("one unread line in twenty-one is noise: %v", err)
	}
}

func TestStreamStopsInsideALongLineWhenTheContextEnds(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	line := strings.Repeat("z", 16<<20) + "\n"
	r := &cancelAfterBytes{r: strings.NewReader(strings.Repeat(streamLine, 5) + line), cancel: cancel, limit: 1 << 20}
	_, err := streamParser().ParseStream(ctx, r, 0)
	assertStreamPartial(t, err)
	if r.read > 3<<20 {
		t.Fatalf("read %d bytes of a 16 MiB line after the budget ended at 1 MiB", r.read)
	}
}

func TestStreamLastLineWithoutALineEndCounts(t *testing.T) {
	log := streamLine + streamLine + strings.TrimSuffix(streamSpyLine, "\n")
	result, err := streamParser().ParseStream(context.Background(), strings.NewReader(log), 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Anomalies) != 1 {
		t.Fatalf("anomalies %d", len(result.Anomalies))
	}
}

func TestStreamFindingEvidenceIsBounded(t *testing.T) {
	long := "11-21 08:12:33.123  1234  5678 W Agent: pegasus " + strings.Repeat("y", 40*1024) + "\n"
	result, err := streamParser().ParseStream(context.Background(), strings.NewReader(long), 0)
	if err != nil {
		t.Fatal(err)
	}
	message, _ := result.Anomalies[0].Evidence["message"].(string)
	if len(message) > 2048+3 {
		t.Fatalf("evidence holds %d bytes", len(message))
	}
}

// cancelAfterBytes ends the context once limit bytes were read.
type cancelAfterBytes struct {
	r      io.Reader
	cancel context.CancelFunc
	limit  int64
	read   int64
}

func (c *cancelAfterBytes) Read(p []byte) (int, error) {
	n, err := c.r.Read(p)
	c.read += int64(n)
	if c.read >= c.limit {
		c.cancel()
	}
	return n, err
}

func TestStreamChecksTheBudgetOnLongLines(t *testing.T) {
	line := "11-21 08:12:33.123  1234  5678 I Agent: " + strings.Repeat("y", 60*1024) + "\n"
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	r := &cancelAfterBytes{r: strings.NewReader(strings.Repeat(line, 300)), cancel: cancel, limit: 1 << 20}
	_, err := streamParser().ParseStream(ctx, r, 0)
	assertStreamPartial(t, err)
	if r.read > 3<<20 {
		t.Fatalf("read %d bytes after the budget ended at 1 MiB", r.read)
	}
}

func TestStreamFindingKeepsNoLongFields(t *testing.T) {
	tag := strings.Repeat("T", 40*1024)
	line := "11-21 08:12:33.123  1234  5678 W " + tag + ": pegasus started\n"
	result, err := streamParser().ParseStream(context.Background(), strings.NewReader(line), 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Anomalies) != 1 {
		t.Fatalf("anomalies: %d", len(result.Anomalies))
	}
	got, _ := result.Anomalies[0].Evidence["tag"].(string)
	if len(got) > 256+3 {
		t.Fatalf("evidence tag holds %d bytes", len(got))
	}
	if len(result.Timeline) != 1 || len(result.Timeline[0].Title) > 256+3+2+50+3 {
		t.Fatalf("timeline title is unbounded")
	}
}
