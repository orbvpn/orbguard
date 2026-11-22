package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

const healthFeedError = "provider answered 500 for healthfeed"

// analyticsTestHandler is an analytics handler on a throwaway database that
// holds one source in error, with the analytics_reports table added.
func analyticsTestHandler(t *testing.T) *AnalyticsHandler {
	t.Helper()
	pool := sourcesTestDB(t)
	ctx := context.Background()
	migration, err := os.ReadFile("../../../migrations/005_analytics_reports.sql")
	if err != nil {
		t.Fatal(err)
	}
	up, _, _ := strings.Cut(string(migration), "-- +goose Down")
	if _, err := pool.Exec(ctx, up); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `
		INSERT INTO sources (name, slug, category, type, status, last_error)
		VALUES ('Health Feed', 'healthfeed', 'abuse_ch', 'api', 'error', $1)`, healthFeedError); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { waitForReports(pool) })
	log := logger.NewDefault()
	return NewAnalyticsHandler(log, services.NewAnalyticsService(repository.NewRepositories(pool), nil, log))
}

// waitForReports lets background report generation finish before the
// database is dropped.
func waitForReports(pool *pgxpool.Pool) {
	for i := 0; i < 100; i++ {
		var busy int
		if err := pool.QueryRow(context.Background(),
			`SELECT COUNT(*) FROM analytics_reports WHERE status IN ('pending', 'generating')`).Scan(&busy); err != nil || busy == 0 {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
}

func analyticsRequest(admin bool, method, path, body, id string) *http.Request {
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	rctx := chi.NewRouteContext()
	if id != "" {
		rctx.URLParams.Add("id", id)
	}
	ctx := context.WithValue(req.Context(), chi.RouteCtxKey, rctx)
	if admin {
		ctx = context.WithValue(ctx, middleware.ContextKeyIsAdmin, true)
	}
	return req.WithContext(ctx)
}

// GET /analytics/sources serves last_error to admins only.
func TestSourceHealthShowsLastErrorToAdminsOnly(t *testing.T) {
	h := analyticsTestHandler(t)
	for _, admin := range []bool{false, true} {
		rec := httptest.NewRecorder()
		h.GetSourceHealth(rec, analyticsRequest(admin, http.MethodGet, "/api/v1/analytics/sources", "", ""))
		if rec.Code != http.StatusOK {
			t.Fatalf("admin=%v: %d %s", admin, rec.Code, rec.Body.String())
		}
		var report models.SourceHealthReport
		if err := json.Unmarshal(rec.Body.Bytes(), &report); err != nil {
			t.Fatal(err)
		}
		if len(report.Sources) != 1 || report.Sources[0].Slug != "healthfeed" {
			t.Fatalf("admin=%v: sources %+v", admin, report.Sources)
		}
		want := ""
		if admin {
			want = healthFeedError
		}
		if got := report.Sources[0].LastError; got != want {
			t.Errorf("admin=%v: last_error %q, want %q", admin, got, want)
		}
	}
}

// A source_health report never holds a last error, in any format, whoever
// asked for it: report generation has no caller to check.
func TestSourceHealthReportNeverHoldsLastError(t *testing.T) {
	h := analyticsTestHandler(t)
	for _, format := range []string{"json", "csv", "html"} {
		for _, admin := range []bool{false, true} {
			rec := httptest.NewRecorder()
			h.CreateReport(rec, analyticsRequest(admin, http.MethodPost, "/api/v1/analytics/reports",
				`{"report_type":"source_health","format":"`+format+`"}`, ""))
			if rec.Code != http.StatusCreated {
				t.Fatalf("%s admin=%v: create %d %s", format, admin, rec.Code, rec.Body.String())
			}
			var created models.AnalyticsReport
			if err := json.Unmarshal(rec.Body.Bytes(), &created); err != nil {
				t.Fatal(err)
			}

			deadline := time.Now().Add(10 * time.Second)
			for {
				rec = httptest.NewRecorder()
				h.GetReport(rec, analyticsRequest(admin, http.MethodGet, "/api/v1/analytics/reports/"+created.ID, "", created.ID))
				var report models.AnalyticsReport
				if err := json.Unmarshal(rec.Body.Bytes(), &report); err != nil {
					t.Fatalf("%s: %d %s", format, rec.Code, rec.Body.String())
				}
				if report.Status == models.AnalyticsReportStatusCompleted {
					break
				}
				if report.Status == models.AnalyticsReportStatusFailed {
					t.Fatalf("%s admin=%v: report failed: %s", format, admin, report.Error)
				}
				if time.Now().After(deadline) {
					t.Fatalf("%s admin=%v: report still %s", format, admin, report.Status)
				}
				time.Sleep(50 * time.Millisecond)
			}

			rec = httptest.NewRecorder()
			h.DownloadReport(rec, analyticsRequest(admin, http.MethodGet, "/api/v1/analytics/reports/"+created.ID+"/download", "", created.ID))
			if rec.Code != http.StatusOK {
				t.Fatalf("%s admin=%v: download %d %s", format, admin, rec.Code, rec.Body.String())
			}
			body := rec.Body.String()
			if !strings.Contains(body, "healthfeed") {
				t.Errorf("%s admin=%v: the source is missing from the report: %s", format, admin, body)
			}
			if strings.Contains(body, healthFeedError) {
				t.Errorf("%s admin=%v: the report holds the last error: %s", format, admin, body)
			}
			if strings.Contains(body, "last_error") {
				t.Errorf("%s admin=%v: the report has a last_error field or column: %s", format, admin, body)
			}
		}
	}
}
