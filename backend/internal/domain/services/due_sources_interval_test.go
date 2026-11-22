package services

import (
	"context"
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
