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
	"orbguard-lab/internal/domain/services/ai"
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
	detector := ai.NewScamDetector(log, ai.ScamDetectorConfig{EnablePhoneRep: true})
	h := &handlers.Handlers{
		Sources:       handlers.NewSourcesHandler(nil, nil, log),
		Playbooks:     handlers.NewPlaybookHandler(log, playbooks),
		ScamDetection: handlers.NewScamDetectionHandler(log, detector),
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

// phoneRisk reads the risk score. is_suspicious cannot tell the states apart:
// it is already true for any unknown number, whose base risk is 0.5.
func phoneRisk(t *testing.T, h http.Handler, number string) (risk float64, isScam bool) {
	t.Helper()
	rec := do(h, http.MethodGet, "/api/v1/scam/phone/"+number, nil, asDevice())
	if rec.Code != http.StatusOK {
		t.Fatalf("phone reputation: want 200, got %d: %s", rec.Code, rec.Body)
	}
	body := decodeJSON(t, rec.Body.Bytes())
	return body["risk_score"].(float64), body["is_scam"].(bool)
}

// A forged X-Forwarded-For must not make one client count as many reporters.
func TestPhoneReportsFromOneClientWithForgedHopsDoNotFlag(t *testing.T) {
	h := newGfix3Router(t)
	const number = "+4915112340001"
	baseline, _ := phoneRisk(t, h, number)
	for _, route := range []string{"/api/v1/scam/phone/report", "/api/v1/scam/report"} {
		for i := 0; i < 20; i++ {
			forged := clientHeader("X-Forwarded-For", fmt.Sprintf("203.0.%d.9", i))
			rec := do(h, http.MethodPost, route, strings.NewReader(`{"phone_number":"`+number+`"}`), asDevice(), forged, fromIP("198.51.100.7"))
			if rec.Code != http.StatusCreated {
				t.Fatalf("%s: want 201, got %d", route, rec.Code)
			}
		}
	}
	if risk, isScam := phoneRisk(t, h, number); isScam || risk != baseline {
		t.Fatalf("one client changed the number for every other user: risk %v (baseline %v), scam %v", risk, baseline, isScam)
	}
}

// One credential is one reporter however many networks it reports from.
func TestOneKeyOnFiveNetworksDoesNotFlagANumber(t *testing.T) {
	h := newGfix3Router(t)
	const number = "+4915112340002"
	baseline, _ := phoneRisk(t, h, number)
	for i := 0; i < 5; i++ {
		rec := do(h, http.MethodPost, "/api/v1/scam/phone/report", strings.NewReader(`{"phone_number":"`+number+`"}`), asDevice(), fromIP(fmt.Sprintf("198.51.%d.7", i)))
		if rec.Code != http.StatusCreated {
			t.Fatalf("report: want 201, got %d", rec.Code)
		}
	}
	if risk, isScam := phoneRisk(t, h, number); isScam || risk != baseline {
		t.Fatalf("one key changed the number: risk %v (baseline %v), scam %v", risk, baseline, isScam)
	}
}

// Addresses inside one /24 are one reporter: a host can often change its
// address within its network.
func TestPhoneReportsFromOneNetworkDoNotFlag(t *testing.T) {
	h := newGfix3Router(t)
	const number = "+4915112340003"
	baseline, _ := phoneRisk(t, h, number)
	for i := 1; i <= 20; i++ {
		rec := do(h, http.MethodPost, "/api/v1/scam/phone/report", strings.NewReader(`{"phone_number":"`+number+`"}`), asDevice(), fromIP(fmt.Sprintf("198.51.100.%d", i)))
		if rec.Code != http.StatusCreated {
			t.Fatalf("report: want 201, got %d", rec.Code)
		}
	}
	if risk, isScam := phoneRisk(t, h, number); isScam || risk != baseline {
		t.Fatalf("one /24 changed the number: risk %v (baseline %v), scam %v", risk, baseline, isScam)
	}
}
