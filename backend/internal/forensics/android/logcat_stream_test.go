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
