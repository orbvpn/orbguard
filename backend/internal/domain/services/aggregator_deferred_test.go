package services

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"

	"orbguard-lab/internal/config"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/sources"
	"orbguard-lab/pkg/logger"
)

// deferredRepo is a repository whose only live methods are the ones a due
// tick may call. Any write method panics through the nil embedded interface,
// except the failure recorders, which count, so a deferred fetch that wrote
// anything fails the test.
type deferredRepo struct {
	IndicatorRepository
	due    []*models.Source
	writes atomic.Int32
}

func (r *deferredRepo) GetDueSources(context.Context) ([]*models.Source, error) {
	return r.due, nil
}

func (r *deferredRepo) UpdateSourceAfterError(context.Context, uuid.UUID, string) error {
	r.writes.Add(1)
	return nil
}

func (r *deferredRepo) UpdateSourceAfterSuccess(context.Context, uuid.UUID) error {
	r.writes.Add(1)
	return nil
}

func (r *deferredRepo) UpdateSourceRateLimited(context.Context, uuid.UUID, time.Time, string) error {
	r.writes.Add(1)
	return nil
}

func (r *deferredRepo) UpdateSourcePlanLimited(context.Context, uuid.UUID, string) error {
	r.writes.Add(1)
	return nil
}

func (r *deferredRepo) RecordFetchHistory(context.Context, *models.SourceFetchResult) error {
	r.writes.Add(1)
	return nil
}

type stubConnector struct {
	slug  string
	err   error
	calls atomic.Int32
}

func (c *stubConnector) Slug() string                  { return c.slug }
func (c *stubConnector) IsEnabled() bool               { return true }
func (c *stubConnector) UpdateInterval() time.Duration { return time.Hour }
func (c *stubConnector) Fetch(context.Context) (*models.SourceFetchResult, error) {
	c.calls.Add(1)
	return &models.SourceFetchResult{SourceSlug: c.slug, Error: c.err}, c.err
}

func newDeferredAggregator(repo IndicatorRepository, conns ...SourceConnector) *Aggregator {
	a := NewAggregator(config.AggregationConfig{}, repo, nil, nil, nil, nil, logger.NewDefault())
	for _, c := range conns {
		a.RegisterConnector(c)
	}
	return a
}

func TestDeferredFetchWritesNothingToTheSourceRow(t *testing.T) {
	paced := &stubConnector{slug: "paced", err: &sources.FetchDeferredError{Provider: "Paced", Wait: time.Minute}}
	repo := &deferredRepo{}
	a := newDeferredAggregator(repo, paced)

	err := a.fetchFromSourceWithDB(context.Background(), paced, &models.Source{ID: uuid.New(), Slug: "paced"})
	if !isFetchDeferred(err) {
		t.Fatalf("want the deferral reported to the tick, got %v", err)
	}
	if n := repo.writes.Load(); n != 0 {
		t.Fatalf("a deferred fetch wrote %d times to the source row", n)
	}
	if err := a.fetchFromSource(context.Background(), paced); err != nil {
		t.Fatalf("the plain path must treat a deferral as no failure, got %v", err)
	}
}

func TestDueTickWithOnlyDeferredSourcesRunsNothingElse(t *testing.T) {
	paced := &stubConnector{slug: "paced", err: &sources.FetchDeferredError{Provider: "Paced", Wait: time.Minute}}
	other := &stubConnector{slug: "other", err: errors.New("provider down")}
	repo := &deferredRepo{due: []*models.Source{{ID: uuid.New(), Slug: "paced"}}}
	a := newDeferredAggregator(repo, paced, other)

	if err := a.runDueSources(context.Background()); err != nil {
		t.Fatalf("runDueSources: %v", err)
	}
	if n := paced.calls.Load(); n != 1 {
		t.Fatalf("the paced connector ran %d times, want 1", n)
	}
	if n := other.calls.Load(); n != 0 {
		t.Fatalf("a connector that was not due ran %d times", n)
	}
}

func TestDueTickWithRealWorkSkipsTheFallback(t *testing.T) {
	due := &stubConnector{slug: "due", err: errors.New("provider down")}
	other := &stubConnector{slug: "other", err: errors.New("provider down")}
	repo := &deferredRepo{due: []*models.Source{{ID: uuid.New(), Slug: "due"}}}
	a := newDeferredAggregator(repo, due, other)

	if err := a.runDueSources(context.Background()); err != nil {
		t.Fatalf("runDueSources: %v", err)
	}
	if n := other.calls.Load(); n != 0 {
		t.Fatalf("the fallback ran although a due source did real work (%d calls)", n)
	}
}
