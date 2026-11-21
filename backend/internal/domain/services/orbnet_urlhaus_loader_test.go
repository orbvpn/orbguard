package services

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/database/repository"
)

// loaderTestDB creates a throwaway database from the real first migration on
// the local test Postgres named by ORBNET_TEST_PG_PORT. Only 127.0.0.1 is used.
func loaderTestDB(t *testing.T) *pgxpool.Pool {
	t.Helper()
	portText := os.Getenv("ORBNET_TEST_PG_PORT")
	if portText == "" {
		t.Skip("ORBNET_TEST_PG_PORT not set: no local test Postgres")
	}
	port, err := strconv.Atoi(portText)
	if err != nil {
		t.Fatalf("bad test port: %v", err)
	}

	ctx := context.Background()
	address := func(name string) string {
		return fmt.Sprintf("postgres://postgres@127.0.0.1:%d/%s?sslmode=disable", port, name)
	}
	admin, err := pgx.Connect(ctx, address("postgres"))
	if err != nil {
		t.Skipf("local test Postgres not reachable: %v", err)
	}
	name := fmt.Sprintf("gfeed_loader_%d_%d", os.Getpid(), time.Now().UnixNano())
	if _, err := admin.Exec(ctx, "CREATE DATABASE "+name); err != nil {
		admin.Close(ctx)
		t.Fatalf("create test database: %v", err)
	}
	t.Cleanup(func() {
		_, _ = admin.Exec(ctx, "DROP DATABASE IF EXISTS "+name+" WITH (FORCE)")
		admin.Close(ctx)
	})

	migration, err := os.ReadFile("../../../migrations/001_initial_schema.sql")
	if err != nil {
		t.Fatal(err)
	}
	schema, _, _ := strings.Cut(string(migration), "-- +goose Down")
	setup, err := pgx.Connect(ctx, address(name))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := setup.PgConn().Exec(ctx, schema).ReadAll(); err != nil {
		setup.Close(ctx)
		t.Fatalf("apply schema: %v", err)
	}
	setup.Close(ctx)

	pool, err := pgxpool.New(ctx, address(name)+"&search_path=orbguard_lab,public")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	return pool
}

func TestDNSRuleLoaderSkipsStoredURLhausRows(t *testing.T) {
	pool := loaderTestDB(t)
	repos := repository.NewRepositories(pool)
	ctx := context.Background()

	store := func(value string, kind models.IndicatorType, source string) {
		t.Helper()
		_, err := repos.Indicators.Upsert(ctx, &models.Indicator{
			Value: value, Type: kind, Severity: models.SeverityHigh, Confidence: 0.8,
			Tags: []string{source}, SourceID: source, SourceName: source,
		})
		if err != nil {
			t.Fatalf("store %s: %v", value, err)
		}
	}
	const urlhausURL = "http://shared-host.example/one-bad-file.exe"
	store(urlhausURL, models.IndicatorTypeURL, "urlhaus")
	store("http://https://shared-scheme.example/x", models.IndicatorTypeURL, "urlhaus")
	store("http://other-feed.example/x", models.IndicatorTypeURL, "threatfox")
	// A value another feed tagged "urlhaus" is still that feed's own row.
	if _, err := repos.Indicators.Upsert(ctx, &models.Indicator{
		Value: "http://tagged.example/x", Type: models.IndicatorTypeURL, Severity: models.SeverityHigh, Confidence: 0.8,
		Tags: []string{"urlhaus"}, SourceID: "misp", SourceName: "misp",
	}); err != nil {
		t.Fatal(err)
	}
	// Left by the old connector: the owner decided these stay for now.
	store("old-domain-row.example", models.IndicatorTypeDomain, "urlhaus")

	svc := NewOrbNetService(repos, nil, feedRowLog())
	rules := map[string]bool{}
	for _, rule := range svc.blockRules {
		rules[strings.ToLower(rule.Domain)] = true
	}

	for _, blocked := range []string{"shared-host.example", "shared-scheme.example"} {
		if rules[blocked] {
			t.Errorf("a URLhaus URL row became a whole-host rule for %s", blocked)
		}
	}
	for _, kept := range []string{"other-feed.example", "tagged.example", "old-domain-row.example"} {
		if !rules[kept] {
			t.Errorf("rule for %s was lost", kept)
		}
	}

	// Exact-URL matching still sees the row the DNS loader skips.
	found, err := repos.Indicators.GetByValue(ctx, urlhausURL, models.IndicatorTypeURL)
	if err != nil || found == nil {
		t.Fatalf("exact URL lookup: %v, %v", found, err)
	}
}

// URLhaus rows must not use up the loader's row window at the expense of other
// feeds, because they are the newest rows on every fetch.
func TestDNSRuleLoaderWindowIsNotFilledByURLhaus(t *testing.T) {
	pool := loaderTestDB(t)
	repos := repository.NewRepositories(pool)
	ctx := context.Background()

	old := time.Now().Add(-48 * time.Hour)
	_, err := repos.Indicators.Upsert(ctx, &models.Indicator{
		Value: "http://older-feed.example/x", Type: models.IndicatorTypeURL, Severity: models.SeverityHigh,
		Confidence: 0.8, SourceID: "threatfox", SourceName: "threatfox", FirstSeen: old, LastSeen: old,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `
		INSERT INTO indicators (value, value_hash, type, severity, confidence, source_id, source_name)
		SELECT 'http://u' || g || '.example/x', md5(g::text) || md5(g::text), 'url', 'high', 0.8, 'urlhaus', 'URLhaus'
		FROM generate_series(1, 50000) g`); err != nil {
		t.Fatal(err)
	}

	svc := NewOrbNetService(repos, nil, feedRowLog())
	for _, rule := range svc.blockRules {
		if rule.Domain == "older-feed.example" {
			return
		}
	}
	t.Fatal("50000 newer URLhaus rows pushed another feed's rule out of the load window")
}
