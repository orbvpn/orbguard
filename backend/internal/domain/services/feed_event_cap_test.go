package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/rs/zerolog"

	"orbguard-lab/internal/config"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/pkg/logger"
)

const feedEventCapMessage = "new threat events capped for this fetch"

type countingPublisher struct {
	mu     sync.Mutex
	values []string
}

func (p *countingPublisher) PublishNewThreat(_ context.Context, i *models.Indicator, _, _ string) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.values = append(p.values, i.Value)
	return nil
}

func (p *countingPublisher) PublishSourceUpdate(context.Context, string, string, bool, int, int, time.Duration, error) error {
	return nil
}

type lockedBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *lockedBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

// capLogLines returns the cap log lines written so far.
func (b *lockedBuffer) capLogLines(t *testing.T) []map[string]any {
	t.Helper()
	b.mu.Lock()
	defer b.mu.Unlock()
	var lines []map[string]any
	for _, line := range strings.Split(b.buf.String(), "\n") {
		if !strings.Contains(line, feedEventCapMessage) {
			continue
		}
		var fields map[string]any
		if err := json.Unmarshal([]byte(line), &fields); err != nil {
			t.Fatal(err)
		}
		lines = append(lines, fields)
	}
	return lines
}

type capFeedBase struct{ rows int }

func (capFeedBase) IsEnabled() bool               { return true }
func (capFeedBase) UpdateInterval() time.Duration { return time.Hour }
func (f capFeedBase) fetch(slug string) (*models.SourceFetchResult, error) {
	raw := make([]models.RawIndicator, 0, f.rows)
	for i := 0; i < f.rows; i++ {
		raw = append(raw, models.RawIndicator{
			Value: fmt.Sprintf("http://cap%d.example/a", i), Type: models.IndicatorTypeURL,
			SourceID: slug, SourceName: slug,
		})
	}
	return &models.SourceFetchResult{SourceSlug: slug, RawIndicators: raw}, nil
}

// capTrackedFeed opts in or out through TracksSourceRow.
type capTrackedFeed struct {
	capFeedBase
	tracked bool
}

func (capTrackedFeed) Slug() string            { return "capfeed" }
func (f capTrackedFeed) TracksSourceRow() bool { return f.tracked }
func (f capTrackedFeed) Fetch(context.Context) (*models.SourceFetchResult, error) {
	return f.fetch("capfeed")
}

// capPlainFeed does not implement TracksSourceRow at all.
type capPlainFeed struct{ capFeedBase }

func (capPlainFeed) Slug() string { return "capfeed" }
func (f capPlainFeed) Fetch(context.Context) (*models.SourceFetchResult, error) {
	return f.fetch("capfeed")
}

type capRun struct {
	repo *feedRowRepo
	pub  *countingPublisher
	logs *lockedBuffer
}

// runCapFeed runs one fetch on the job path or the due-tick path.
func runCapFeed(t *testing.T, conn SourceConnector, dueTick bool, failStores int) capRun {
	t.Helper()
	logs := &lockedBuffer{}
	log := &logger.Logger{Logger: zerolog.New(logs)}
	rc := feedRowRedis(t)
	row := &models.Source{ID: uuid.New(), Slug: "capfeed", Name: "capfeed", Status: models.SourceStatusActive}
	repo := &feedRowRepo{row: row, failStores: failStores}
	agg := NewAggregator(config.AggregationConfig{}, repo, NewNormalizer(log),
		NewDeduplicator(rc, log), NewScorer(config.ScoringConfig{}, log), rc, log)
	pub := &countingPublisher{}
	agg.SetEventPublisher(pub)
	agg.RegisterConnector(conn)

	var err error
	if dueTick {
		err = agg.fetchFromSourceWithDB(context.Background(), conn, row)
	} else {
		err = agg.RunSource(context.Background(), "capfeed")
	}
	if err != nil {
		t.Fatal(err)
	}
	return capRun{repo: repo, pub: pub, logs: logs}
}

func capPaths(t *testing.T, run func(t *testing.T, dueTick bool)) {
	t.Run("job", func(t *testing.T) { run(t, false) })
	t.Run("due tick", func(t *testing.T) { run(t, true) })
}

func TestTrackedFeedThreatEventsAreCapped(t *testing.T) {
	for _, tc := range []struct{ rows, published, suppressed int }{
		{101, 100, 1},
		{250, 100, 150},
	} {
		t.Run(fmt.Sprint(tc.rows), func(t *testing.T) {
			capPaths(t, func(t *testing.T, dueTick bool) {
				got := runCapFeed(t, capTrackedFeed{capFeedBase{tc.rows}, true}, dueTick, 0)
				if got.repo.stored != tc.rows {
					t.Fatalf("stored %d of %d", got.repo.stored, tc.rows)
				}
				if len(got.pub.values) != tc.published {
					t.Fatalf("published %d, want %d", len(got.pub.values), tc.published)
				}
				lines := got.logs.capLogLines(t)
				if len(lines) != 1 {
					t.Fatalf("%d cap log lines, want 1", len(lines))
				}
				if lines[0]["suppressed"] != float64(tc.suppressed) || lines[0]["published"] != float64(tc.published) {
					t.Fatalf("log fields %v, want published %d and suppressed %d", lines[0], tc.published, tc.suppressed)
				}
			})
		})
	}
}

func TestTrackedFeedAtOrBelowTheCapPublishesAll(t *testing.T) {
	for _, rows := range []int{1, 99, 100} {
		t.Run(fmt.Sprint(rows), func(t *testing.T) {
			capPaths(t, func(t *testing.T, dueTick bool) {
				got := runCapFeed(t, capTrackedFeed{capFeedBase{rows}, true}, dueTick, 0)
				if got.repo.stored != rows || len(got.pub.values) != rows {
					t.Fatalf("stored=%d published=%d, want %d", got.repo.stored, len(got.pub.values), rows)
				}
				if lines := got.logs.capLogLines(t); len(lines) != 0 {
					t.Fatalf("unexpected cap log: %v", lines)
				}
			})
		})
	}
}

// A row that was not stored is not announced, so it uses none of the cap.
func TestTrackedFeedCapCountsStoredRowsOnly(t *testing.T) {
	capPaths(t, func(t *testing.T, dueTick bool) {
		got := runCapFeed(t, capTrackedFeed{capFeedBase{150}, true}, dueTick, 30)
		if got.repo.stored != 120 || len(got.pub.values) != 100 {
			t.Fatalf("stored=%d published=%d, want 120 and 100", got.repo.stored, len(got.pub.values))
		}
		lines := got.logs.capLogLines(t)
		if len(lines) != 1 || lines[0]["suppressed"] != float64(20) {
			t.Fatalf("cap log %v, want one line with 20 suppressed", lines)
		}
	})
}

func TestOtherFeedsPublishEveryThreatEvent(t *testing.T) {
	const rows = 150
	for name, conn := range map[string]SourceConnector{
		"opted out":      capTrackedFeed{capFeedBase{rows}, false},
		"no such method": capPlainFeed{capFeedBase{rows}},
	} {
		t.Run(name, func(t *testing.T) {
			capPaths(t, func(t *testing.T, dueTick bool) {
				got := runCapFeed(t, conn, dueTick, 0)
				if got.repo.stored != rows || len(got.pub.values) != rows {
					t.Fatalf("stored=%d published=%d, want %d", got.repo.stored, len(got.pub.values), rows)
				}
				if lines := got.logs.capLogLines(t); len(lines) != 0 {
					t.Fatalf("unexpected cap log: %v", lines)
				}
			})
		})
	}
}
