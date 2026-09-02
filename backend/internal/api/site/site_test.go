package site

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
)

func TestPagesServe(t *testing.T) {
	r := chi.NewRouter()
	Register(r)
	for path, want := range map[string]string{
		"/terms":   "ORB GLOBAL LTD",
		"/privacy": "ORB GLOBAL LTD",
		"/pricing": "$3.99",
	} {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s: status %d", path, rec.Code)
		}
		if !strings.Contains(rec.Body.String(), want) {
			t.Fatalf("%s: missing %q", path, want)
		}
		if strings.Contains(rec.Body.String(), "orbvpn.com/terms") {
			t.Fatalf("%s: stale orbvpn.com link", path)
		}
	}
}
