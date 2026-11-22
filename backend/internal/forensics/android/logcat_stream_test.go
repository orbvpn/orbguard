package android

import (
	"bufio"
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

func TestStreamLineOverTheScannerLimitStaysAnError(t *testing.T) {
	_, err := streamParser().ParseStream(context.Background(), strings.NewReader(strings.Repeat("x", 70*1024)+"\n"), 0)
	if !errors.Is(err, bufio.ErrTooLong) {
		t.Fatalf("want the line error, got %v", err)
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
