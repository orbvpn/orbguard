package services

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"orbguard-lab/internal/config"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/database/db"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// The migrations declare sources.update_interval INTERVAL. Production's table
// returns it as text (OID 25): every read of a source row there failed with
// "cannot scan text (OID 25) in text format into *time.Duration", so the
// aggregator never got its due sources and fetched every source every 15
// minutes. These tests run on a real Postgres with both column types.

// intervalColumnTypes builds the sources table as the migrations do, and as
// production has it.
var intervalColumnTypes = []struct {
	name  string
	alter string
}{
	{name: "interval column, as in the migrations"},
	{name: "text column, as in production", alter: `
		ALTER TABLE orbguard_lab.sources ALTER COLUMN update_interval DROP DEFAULT;
		ALTER TABLE orbguard_lab.sources ALTER COLUMN update_interval TYPE text USING update_interval::text;
		ALTER TABLE orbguard_lab.sources ALTER COLUMN update_interval SET DEFAULT '1 hour'`},
}

func intervalTestDB(t *testing.T, alter string) *pgxpool.Pool {
	t.Helper()
	pool := loaderTestDB(t)
	if alter != "" {
		if _, err := pool.Exec(context.Background(), alter); err != nil {
			t.Fatalf("alter column: %v", err)
		}
	}
	return pool
}

// insertSourceRow writes a row the way production's rows were written: the
// interval is given as the text Postgres or Go would have stored.
func insertSourceRow(t *testing.T, pool *pgxpool.Pool, slug, interval, nextFetch string) uuid.UUID {
	t.Helper()
	var id uuid.UUID
	err := pool.QueryRow(context.Background(), `
		INSERT INTO sources (name, slug, category, type, status, update_interval, next_fetch)
		VALUES ($1, $1, 'abuse_ch', 'api', 'active', `+interval+`, `+nextFetch+`)
		RETURNING id`, slug).Scan(&id)
	if err != nil {
		t.Fatalf("insert %s: %v", slug, err)
	}
	return id
}

// secondsUntilNextFetch returns next_fetch - now() in seconds.
func secondsUntilNextFetch(t *testing.T, pool *pgxpool.Pool, id uuid.UUID) float64 {
	t.Helper()
	var s float64
	if err := pool.QueryRow(context.Background(),
		`SELECT EXTRACT(EPOCH FROM next_fetch - now())::float8 FROM sources WHERE id = $1`, id).Scan(&s); err != nil {
		t.Fatalf("read next_fetch: %v", err)
	}
	return s
}

func near(got float64, want time.Duration) bool {
	d := got - want.Seconds()
	return d > -60 && d < 60
}

func TestSourceRowsWorkWhateverTheUpdateIntervalColumnType(t *testing.T) {
	for _, ct := range intervalColumnTypes {
		t.Run(ct.name, func(t *testing.T) {
			pool := intervalTestDB(t, ct.alter)
			ctx := context.Background()
			repo := repository.NewSourceRepository(pool)

			// Text forms a production row may hold: the seed's words, Go's
			// time.Duration.String(), Postgres's own output, bare seconds.
			want := map[string]time.Duration{
				"words":   15 * time.Minute,
				"short":   4 * time.Hour,
				"gostr":   15 * time.Minute,
				"pgout":   time.Hour,
				"seconds": 15 * time.Minute,
			}
			ids := map[string]uuid.UUID{
				"words":   insertSourceRow(t, pool, "words", "'15 minutes'", "NULL"),
				"short":   insertSourceRow(t, pool, "short", "'4h'", "NULL"),
				"gostr":   insertSourceRow(t, pool, "gostr", "'15m0s'", "now() - interval '1 minute'"),
				"pgout":   insertSourceRow(t, pool, "pgout", "'01:00:00'", "NULL"),
				"seconds": insertSourceRow(t, pool, "seconds", "'900'", "now() + interval '1 hour'"),
			}

			due, err := repo.ListDue(ctx)
			if err != nil {
				t.Fatalf("ListDue: %v", err)
			}
			if len(due) != 4 {
				t.Fatalf("ListDue returned %d rows, want 4 (all but the one fetched later)", len(due))
			}
			for _, s := range due {
				if s.UpdateInterval != want[s.Slug] {
					t.Errorf("ListDue %s: interval %v, want %v", s.Slug, s.UpdateInterval, want[s.Slug])
				}
			}
			for slug, d := range want {
				s, err := repo.GetBySlug(ctx, slug)
				if err != nil || s == nil {
					t.Fatalf("GetBySlug %s: %v %v", slug, s, err)
				}
				if s.UpdateInterval != d {
					t.Errorf("GetBySlug %s: interval %v, want %v", slug, s.UpdateInterval, d)
				}
				if byID, err := repo.GetByID(ctx, ids[slug]); err != nil || byID == nil || byID.UpdateInterval != d {
					t.Errorf("GetByID %s: %v %v", slug, byID, err)
				}
			}
			if all, err := repo.List(ctx); err != nil || len(all) != 5 {
				t.Fatalf("List: %d rows, %v", len(all), err)
			}
			if active, err := repo.ListActive(ctx); err != nil || len(active) != 5 {
				t.Fatalf("ListActive: %d rows, %v", len(active), err)
			}

			// The writers add the row's own interval to now().
			if err := repo.UpdateAfterFetch(ctx, ids["words"], 0); err != nil {
				t.Fatalf("UpdateAfterFetch: %v", err)
			}
			if s := secondsUntilNextFetch(t, pool, ids["words"]); !near(s, 15*time.Minute) {
				t.Errorf("after a fetch next_fetch is %.0fs away, want 900", s)
			}
			if err := repo.UpdateAfterError(ctx, ids["short"], "provider down"); err != nil {
				t.Fatalf("UpdateAfterError: %v", err)
			}
			if s := secondsUntilNextFetch(t, pool, ids["short"]); !near(s, 4*time.Hour) {
				t.Errorf("after an error next_fetch is %.0fs away, want 14400", s)
			}
			if err := repo.MarkPlanLimited(ctx, ids["gostr"], "plan"); err != nil {
				t.Fatalf("MarkPlanLimited: %v", err)
			}
			if s := secondsUntilNextFetch(t, pool, ids["gostr"]); !near(s, 24*time.Hour) {
				t.Errorf("after a plan limit next_fetch is %.0fs away, want 86400", s)
			}
			q := db.New(pool)
			if err := q.UpdateSourceAfterFetch(ctx, ids["pgout"]); err != nil {
				t.Fatalf("sqlc UpdateSourceAfterFetch: %v", err)
			}
			if s := secondsUntilNextFetch(t, pool, ids["pgout"]); !near(s, time.Hour) {
				t.Errorf("after the sqlc fetch update next_fetch is %.0fs away, want 3600", s)
			}
			if err := q.UpdateSourceError(ctx, &db.UpdateSourceErrorParams{ID: ids["seconds"]}); err != nil {
				t.Fatalf("sqlc UpdateSourceError: %v", err)
			}
			if s := secondsUntilNextFetch(t, pool, ids["seconds"]); !near(s, 15*time.Minute) {
				t.Errorf("after the sqlc error update next_fetch is %.0fs away, want 900", s)
			}
			if due, err := repo.ListDue(ctx); err != nil || len(due) != 0 {
				t.Fatalf("after the updates ListDue: %d rows, %v; want none", len(due), err)
			}

			// The admin API's create and update round-trip a time.Duration.
			created, err := repo.Create(ctx, &models.Source{
				Name: "Made", Slug: "made", Category: models.SourceCategoryGeneral,
				Type: models.SourceTypeFeed, Status: models.SourceStatusActive,
				UpdateInterval: 2 * time.Hour,
			})
			if err != nil {
				t.Fatalf("Create: %v", err)
			}
			if got, err := repo.GetBySlug(ctx, "made"); err != nil || got.UpdateInterval != 2*time.Hour {
				t.Fatalf("created row reads back %v, %v", got, err)
			}
			created.UpdateInterval = 30 * time.Minute
			if _, err := repo.Update(ctx, created); err != nil {
				t.Fatalf("Update: %v", err)
			}
			if got, err := repo.GetBySlug(ctx, "made"); err != nil || got.UpdateInterval != 30*time.Minute {
				t.Fatalf("updated row reads back %v, %v", got, err)
			}
		})
	}
}

func TestDueTickFetchesOnlyTheSourcesTheDatabaseSaysAreDue(t *testing.T) {
	for _, ct := range intervalColumnTypes {
		t.Run(ct.name, func(t *testing.T) {
			pool := intervalTestDB(t, ct.alter)
			ctx := context.Background()

			fast := insertSourceRow(t, pool, "fast", "'15 minutes'", "NULL")
			slow := insertSourceRow(t, pool, "slow", "'4h'", "now() - interval '1 minute'")
			insertSourceRow(t, pool, "later", "'1 hour'", "now() + interval '30 minutes'")

			conns := map[string]*stubConnector{}
			for _, slug := range []string{"fast", "slow", "later", "norow"} {
				conns[slug] = &stubConnector{slug: slug}
			}
			agg := NewAggregator(config.AggregationConfig{}, repository.NewRepositories(pool).AggregatorAdapter,
				nil, nil, nil, nil, logger.NewDefault())
			for _, c := range conns {
				agg.RegisterConnector(c)
			}
			calls := func() map[string]int32 {
				m := map[string]int32{}
				for slug, c := range conns {
					m[slug] = c.calls.Load()
				}
				return m
			}

			if err := agg.runDueSources(ctx); err != nil {
				t.Fatalf("first tick: %v", err)
			}
			if got := calls(); got["fast"] != 1 || got["slow"] != 1 || got["later"] != 0 || got["norow"] != 0 {
				t.Fatalf("first tick fetched %v; want only fast and slow, once", got)
			}
			if s := secondsUntilNextFetch(t, pool, fast); !near(s, 15*time.Minute) {
				t.Errorf("fast: next fetch %.0fs away, want 900", s)
			}
			if s := secondsUntilNextFetch(t, pool, slow); !near(s, 4*time.Hour) {
				t.Errorf("slow: next fetch %.0fs away, want 14400", s)
			}

			// Nothing is due now: the tick must not fall back to every source.
			if err := agg.runDueSources(ctx); err != nil {
				t.Fatalf("second tick: %v", err)
			}
			if got := calls(); got["fast"] != 1 || got["slow"] != 1 || got["later"] != 0 || got["norow"] != 0 {
				t.Fatalf("second tick with nothing due fetched %v", got)
			}
		})
	}
}

// A source that fails four due ticks goes to status error and leaves the
// tick. A later success on the Scheduler path must bring the row back.
func TestErrorRowReturnsToTheTickAfterASchedulerSuccess(t *testing.T) {
	for _, ct := range intervalColumnTypes {
		t.Run(ct.name, func(t *testing.T) {
			pool := intervalTestDB(t, ct.alter)
			ctx := context.Background()
			id := insertSourceRow(t, pool, "flaky", "'15 minutes'", "NULL")
			conn := &stubConnector{slug: "flaky", err: errors.New("stream error: stream ID 1; INTERNAL_ERROR; received from peer")}
			agg := NewAggregator(config.AggregationConfig{}, repository.NewRepositories(pool).AggregatorAdapter,
				nil, nil, nil, nil, logger.NewDefault())
			agg.RegisterConnector(conn)

			row := func() (string, int) {
				var status string
				var errs int
				if err := pool.QueryRow(ctx, `SELECT status::text, error_count FROM sources WHERE id = $1`, id).Scan(&status, &errs); err != nil {
					t.Fatal(err)
				}
				return status, errs
			}
			for i := 1; i <= 4; i++ {
				if _, err := pool.Exec(ctx, `UPDATE sources SET next_fetch = now() - interval '1 minute' WHERE id = $1`, id); err != nil {
					t.Fatal(err)
				}
				if err := agg.runDueSources(ctx); err != nil {
					t.Fatal(err)
				}
			}
			if status, errs := row(); status != "error" || errs != 4 {
				t.Fatalf("after four failed ticks: status=%s error_count=%d", status, errs)
			}
			if _, err := pool.Exec(ctx, `UPDATE sources SET next_fetch = now() - interval '1 minute' WHERE id = $1`, id); err != nil {
				t.Fatal(err)
			}
			if err := agg.runDueSources(ctx); err != nil {
				t.Fatal(err)
			}
			if n := conn.calls.Load(); n != 4 {
				t.Fatalf("the tick fetched an error row: %d calls", n)
			}

			conn.err = nil
			if err := agg.RunSource(ctx, "flaky"); err != nil {
				t.Fatalf("Scheduler-path fetch: %v", err)
			}
			if status, errs := row(); status != "active" || errs != 0 {
				t.Fatalf("after a Scheduler success: status=%s error_count=%d", status, errs)
			}
			if s := secondsUntilNextFetch(t, pool, id); !near(s, 15*time.Minute) {
				t.Fatalf("after a Scheduler success next_fetch is %.0fs away, want 900", s)
			}
		})
	}
}

// A NULL or blank interval, which a hand-made table may hold, reads as one
// hour and does not fail the query for the other rows.
func TestNullOrBlankUpdateIntervalReadsAsOneHour(t *testing.T) {
	for _, ct := range intervalColumnTypes {
		t.Run(ct.name, func(t *testing.T) {
			pool := intervalTestDB(t, ct.alter)
			ctx := context.Background()
			if _, err := pool.Exec(ctx, `ALTER TABLE orbguard_lab.sources ALTER COLUMN update_interval DROP NOT NULL`); err != nil {
				t.Fatal(err)
			}
			values := map[string]string{"nullrow": "NULL"}
			if ct.alter != "" {
				values["empty"] = "''"
				values["blank"] = "'   '"
			}
			ids := map[string]uuid.UUID{}
			for slug, v := range values {
				ids[slug] = insertSourceRow(t, pool, slug, v, "NULL")
			}
			insertSourceRow(t, pool, "normal", "'15 minutes'", "NULL")

			repo := repository.NewSourceRepository(pool)
			due, err := repo.ListDue(ctx)
			if err != nil || len(due) != len(values)+1 {
				t.Fatalf("ListDue: %d rows, %v", len(due), err)
			}
			for _, s := range due {
				want := time.Hour
				if s.Slug == "normal" {
					want = 15 * time.Minute
				}
				if s.UpdateInterval != want {
					t.Errorf("%s: interval %v, want %v", s.Slug, s.UpdateInterval, want)
				}
			}
			for slug, id := range ids {
				if err := repo.UpdateAfterFetch(ctx, id, 0); err != nil {
					t.Fatalf("UpdateAfterFetch %s: %v", slug, err)
				}
				if s := secondsUntilNextFetch(t, pool, id); !near(s, time.Hour) {
					t.Errorf("%s: next fetch %.0fs away, want 3600", slug, s)
				}
			}
		})
	}
}

// Each failure in a row pushes the next fetch out by one more interval, up to
// four; the fourth puts the row in error and the fifth still backs off.
func TestErrorBackoffGrowsToFourIntervals(t *testing.T) {
	for _, ct := range intervalColumnTypes {
		t.Run(ct.name, func(t *testing.T) {
			pool := intervalTestDB(t, ct.alter)
			ctx := context.Background()
			id := insertSourceRow(t, pool, "flaky", "'1 hour'", "NULL")
			repo := repository.NewSourceRepository(pool)
			for i, want := range []time.Duration{time.Hour, 2 * time.Hour, 3 * time.Hour, 4 * time.Hour, 4 * time.Hour} {
				if err := repo.UpdateAfterError(ctx, id, "provider down"); err != nil {
					t.Fatal(err)
				}
				if s := secondsUntilNextFetch(t, pool, id); !near(s, want) {
					t.Errorf("failure %d: next fetch %.0fs away, want %.0f", i+1, s, want.Seconds())
				}
				var status string
				if err := pool.QueryRow(ctx, `SELECT status::text FROM sources WHERE id = $1`, id).Scan(&status); err != nil {
					t.Fatal(err)
				}
				if wantStatus := map[bool]string{true: "error", false: "active"}[i >= 3]; status != wantStatus {
					t.Errorf("failure %d: status %s, want %s", i+1, status, wantStatus)
				}
			}
		})
	}
}

// pausingRepo pauses the row right after the aggregator has read it: an
// operator's PATCH landing between recordFetchSuccess's read and its write.
type pausingRepo struct {
	IndicatorRepository
	pool *pgxpool.Pool
}

func (r *pausingRepo) GetSourceBySlug(ctx context.Context, slug string) (*models.Source, error) {
	row, err := r.IndicatorRepository.GetSourceBySlug(ctx, slug)
	if err == nil {
		_, err = r.pool.Exec(ctx, `UPDATE sources SET status = 'paused' WHERE slug = $1`, slug)
	}
	return row, err
}

// A fetch outcome never undoes an operator's pause or disable.
func TestFetchOutcomeLeavesAPausedRowAlone(t *testing.T) {
	pool := intervalTestDB(t, intervalColumnTypes[1].alter)
	ctx := context.Background()
	status := func(id uuid.UUID) string {
		var s string
		if err := pool.QueryRow(ctx, `SELECT status::text FROM sources WHERE id = $1`, id).Scan(&s); err != nil {
			t.Fatal(err)
		}
		return s
	}

	// The race: the row is active when read and paused before the write.
	id := insertSourceRow(t, pool, "raced", "'15 minutes'", "NULL")
	conn := &stubConnector{slug: "raced"}
	agg := NewAggregator(config.AggregationConfig{}, &pausingRepo{repository.NewRepositories(pool).AggregatorAdapter, pool},
		nil, nil, nil, nil, logger.NewDefault())
	agg.RegisterConnector(conn)
	if err := agg.RunSource(ctx, "raced"); err != nil {
		t.Fatal(err)
	}
	if got := status(id); got != "paused" {
		t.Fatalf("a success turned a pause landing mid-fetch into %s", got)
	}

	// Every outcome writer, on rows already paused or disabled.
	repo := repository.NewSourceRepository(pool)
	for _, st := range []string{"paused", "disabled"} {
		id := insertSourceRow(t, pool, "held-"+st, "'15 minutes'", "NULL")
		if _, err := pool.Exec(ctx, `UPDATE sources SET status = $2 WHERE id = $1`, id, st); err != nil {
			t.Fatal(err)
		}
		for i := 0; i < 4; i++ {
			if err := repo.UpdateAfterError(ctx, id, "down"); err != nil {
				t.Fatal(err)
			}
		}
		if err := repo.MarkPlanLimited(ctx, id, "plan"); err != nil {
			t.Fatal(err)
		}
		if err := repo.UpdateAfterFetch(ctx, id, 0); err != nil {
			t.Fatal(err)
		}
		if got := status(id); got != st {
			t.Errorf("a %s row became %s", st, got)
		}
	}
}

// timedFailConnector fails like a real connector does: its result carries the
// fetch time, which update_history needs (started_at is NOT NULL).
type timedFailConnector struct{ stubConnector }

func (c *timedFailConnector) Fetch(context.Context) (*models.SourceFetchResult, error) {
	c.calls.Add(1)
	return &models.SourceFetchResult{SourceSlug: c.slug, FetchedAt: time.Now(), Error: c.err}, c.err
}

// A credential in a fetch error never reaches last_error or update_history.
func TestSecretInAFetchErrorIsNotStored(t *testing.T) {
	pool := intervalTestDB(t, intervalColumnTypes[1].alter)
	ctx := context.Background()
	id := insertSourceRow(t, pool, "leaky", "'15 minutes'", "NULL")
	conn := &timedFailConnector{stubConnector{slug: "leaky", err: errors.New(
		`failed to fetch threat lists: Post "https://safebrowsing.googleapis.com/v4/threatListUpdates:fetch?key=SECRETKEY": dial tcp: i/o timeout`)}}
	agg := NewAggregator(config.AggregationConfig{}, repository.NewRepositories(pool).AggregatorAdapter,
		nil, nil, nil, nil, logger.NewDefault())
	agg.RegisterConnector(conn)
	if err := agg.runDueSources(ctx); err != nil {
		t.Fatal(err)
	}
	if conn.calls.Load() != 1 {
		t.Fatalf("the source was fetched %d times", conn.calls.Load())
	}
	var lastError, historyError string
	if err := pool.QueryRow(ctx, `SELECT COALESCE(last_error, '') FROM sources WHERE id = $1`, id).Scan(&lastError); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `SELECT COALESCE(string_agg(error, ' | '), '') FROM update_history WHERE source_id = $1`, id).Scan(&historyError); err != nil {
		t.Fatal(err)
	}
	for where, text := range map[string]string{"last_error": lastError, "update_history.error": historyError} {
		if !strings.Contains(text, "dial tcp: i/o timeout") || !strings.Contains(text, "[redacted]") {
			t.Errorf("%s = %q, want the cleaned error", where, text)
		}
		if strings.Contains(text, "SECRETKEY") {
			t.Errorf("%s holds the key: %q", where, text)
		}
	}
}
