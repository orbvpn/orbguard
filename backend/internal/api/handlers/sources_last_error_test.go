package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// sourcesTestDB is a throwaway database from the first migration on the local
// test Postgres named by ORBNET_TEST_PG_PORT (127.0.0.1 only).
func sourcesTestDB(t *testing.T) *pgxpool.Pool {
	t.Helper()
	port, err := strconv.Atoi(os.Getenv("ORBNET_TEST_PG_PORT"))
	if err != nil {
		t.Skip("ORBNET_TEST_PG_PORT not set: no local test Postgres")
	}
	ctx := context.Background()
	address := func(name string) string {
		return fmt.Sprintf("postgres://postgres@127.0.0.1:%d/%s?sslmode=disable", port, name)
	}
	admin, err := pgx.Connect(ctx, address("postgres"))
	if err != nil {
		t.Skipf("local test Postgres not reachable: %v", err)
	}
	name := fmt.Sprintf("gsched_handlers_%d_%d", os.Getpid(), time.Now().UnixNano())
	if _, err := admin.Exec(ctx, "CREATE DATABASE "+name); err != nil {
		admin.Close(ctx)
		t.Fatal(err)
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
		t.Fatal(err)
	}
	setup.Close(ctx)
	pool, err := pgxpool.New(ctx, address(name)+"&search_path=orbguard_lab,public")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// The sources reads are open to every device key; last_error is served to
// admins only.
func TestSourcesReadsShowLastErrorToAdminsOnly(t *testing.T) {
	pool := sourcesTestDB(t)
	if _, err := pool.Exec(context.Background(), `
		INSERT INTO sources (name, slug, category, type, status, last_error)
		VALUES ('Feed', 'feed', 'abuse_ch', 'api', 'error', 'provider answered 500')`); err != nil {
		t.Fatal(err)
	}
	h := NewSourcesHandler(repository.NewRepositories(pool), nil, logger.NewDefault())

	call := func(admin bool, handler http.HandlerFunc, path string) map[string]any {
		t.Helper()
		req := httptest.NewRequest(http.MethodGet, path, nil)
		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("slug", "feed")
		ctx := context.WithValue(req.Context(), chi.RouteCtxKey, rctx)
		if admin {
			ctx = context.WithValue(ctx, middleware.ContextKeyIsAdmin, true)
		}
		rec := httptest.NewRecorder()
		handler(rec, req.WithContext(ctx))
		if rec.Code != http.StatusOK {
			t.Fatalf("%s: %d %s", path, rec.Code, rec.Body.String())
		}
		var body map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		if data, ok := body["data"].([]any); ok {
			return data[0].(map[string]any)
		}
		return body
	}

	for _, admin := range []bool{false, true} {
		for path, handler := range map[string]http.HandlerFunc{"/api/v1/sources": h.List, "/api/v1/sources/feed": h.Get} {
			row := call(admin, handler, path)
			_, has := row["last_error"]
			if has != admin {
				t.Errorf("%s admin=%v: last_error present=%v (%v)", path, admin, has, row["last_error"])
			}
			if row["status"] != "error" {
				t.Errorf("%s: status %v", path, row["status"])
			}
		}
	}
}
