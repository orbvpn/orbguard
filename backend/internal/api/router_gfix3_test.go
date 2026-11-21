package api

import (
	"fmt"
	"net/http"
	"strings"
	"testing"

	"github.com/rs/zerolog"

	"orbguard-lab/internal/api/handlers"
	apimiddleware "orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/config"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/pkg/logger"
)

func newGfix3Router(t *testing.T) http.Handler {
	t.Helper()
	log := &logger.Logger{Logger: zerolog.Nop()}
	apimiddleware.ConfigureAuth(memTokenStore{}, "test", log)
	apimiddleware.ConfigureAdminAuth(testAdminToken, newMemLockout(), log)
	playbooks := services.NewPlaybookService(nil, nil, log, &services.PlaybookServiceConfig{WorkerCount: 1, QueueSize: 1})
	t.Cleanup(func() {
		playbooks.Stop()
		apimiddleware.ConfigureAuth(nil, "", nil)
		apimiddleware.ConfigureAdminAuth("", nil, nil)
	})
	cfg := config.Config{}
	cfg.JWT.Secret = guardServiceSecret
	h := &handlers.Handlers{
		Sources:   handlers.NewSourcesHandler(nil, nil, log),
		Playbooks: handlers.NewPlaybookHandler(log, playbooks),
	}
	return NewRouter(cfg, h, nil, log).Setup()
}

func TestSourceWritesAreAdminOnlyAndReadsStayOpen(t *testing.T) {
	h := newGfix3Router(t)
	writes := []struct{ method, path string }{
		{http.MethodPost, "/api/v1/sources"},
		{http.MethodPatch, "/api/v1/sources/some-feed"},
		{http.MethodPost, "/api/v1/intel/sources"},
		{http.MethodPatch, "/api/v1/intel/sources/some-feed"},
	}
	for i, write := range writes {
		ip := fromIP(fmt.Sprintf("192.0.2.%d", 100+i))
		if rec := do(h, write.method, write.path, strings.NewReader(`{"enabled":false}`), asDevice(), ip); rec.Code != http.StatusForbidden {
			t.Errorf("%s %s with a device key: want 403, got %d", write.method, write.path, rec.Code)
		}
		if rec := do(h, write.method, write.path, strings.NewReader(`{"enabled":false}`), asService(), ip); rec.Code != http.StatusForbidden {
			t.Errorf("%s %s with the service secret: want 403, got %d", write.method, write.path, rec.Code)
		}
		// With no repository the handler answers 503: the request got past auth.
		if rec := do(h, write.method, write.path, strings.NewReader(`{"enabled":false}`), append(asAdmin(), ip)...); rec.Code != http.StatusServiceUnavailable {
			t.Errorf("%s %s as admin: want the handler's 503, got %d", write.method, write.path, rec.Code)
		}
	}
	for _, path := range []string{"/api/v1/sources", "/api/v1/intel/sources"} {
		if rec := do(h, http.MethodGet, path, nil, asDevice()); rec.Code != http.StatusOK {
			t.Errorf("GET %s with a device key: want 200, got %d", path, rec.Code)
		}
	}
}

func TestEveryPlaybookRouteIsAdminOnly(t *testing.T) {
	h := newGfix3Router(t)
	routes := []struct{ method, path string }{
		{http.MethodGet, "/api/v1/playbooks"},
		{http.MethodPost, "/api/v1/playbooks"},
		{http.MethodGet, "/api/v1/playbooks/executions"},
		{http.MethodGet, "/api/v1/playbooks/stats"},
		{http.MethodGet, "/api/v1/playbooks/templates"},
		{http.MethodPost, "/api/v1/playbooks/from-template"},
		{http.MethodGet, "/api/v1/playbooks/" + someUUID},
		{http.MethodPut, "/api/v1/playbooks/" + someUUID},
		{http.MethodDelete, "/api/v1/playbooks/" + someUUID},
		{http.MethodPost, "/api/v1/playbooks/" + someUUID + "/enable"},
		{http.MethodPost, "/api/v1/playbooks/" + someUUID + "/disable"},
		{http.MethodPost, "/api/v1/playbooks/" + someUUID + "/execute"},
	}
	for i, route := range routes {
		ip := fromIP(fmt.Sprintf("192.0.2.%d", 120+i))
		if rec := do(h, route.method, route.path, strings.NewReader(`{}`), asDevice(), ip); rec.Code != http.StatusForbidden {
			t.Errorf("%s %s with a device key: want 403, got %d", route.method, route.path, rec.Code)
		}
		if rec := do(h, route.method, route.path, strings.NewReader(`{}`), asService(), ip); rec.Code != http.StatusForbidden {
			t.Errorf("%s %s with the service secret: want 403, got %d", route.method, route.path, rec.Code)
		}
	}
	if rec := do(h, http.MethodGet, "/api/v1/playbooks/templates", nil, append(asAdmin(), fromIP("192.0.2.150"))...); rec.Code != http.StatusOK {
		t.Errorf("templates as admin: want 200, got %d", rec.Code)
	}
}
