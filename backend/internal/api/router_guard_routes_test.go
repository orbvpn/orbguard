package api

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/rs/zerolog"

	"orbguard-lab/internal/api/handlers"
	apimiddleware "orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/config"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/forensics"
	"orbguard-lab/pkg/logger"
)

// These drive the real route table, auth middleware, handlers and in-memory
// services. Nothing here reaches a database, Redis or the network.

const guardServiceSecret = "guard-routes-test-service-secret-0123456789abcdef"

func newGuardRouter(t *testing.T) http.Handler {
	t.Helper()
	log := &logger.Logger{Logger: zerolog.Nop()}
	apimiddleware.ConfigureAuth(memTokenStore{}, "test", log)
	apimiddleware.ConfigureAdminAuth(testAdminToken, newMemLockout(), log)
	t.Cleanup(func() {
		apimiddleware.ConfigureAuth(nil, "", nil)
		apimiddleware.ConfigureAdminAuth("", nil, nil)
		apimiddleware.ConfigureOrbNetJWT("")
	})

	cfg := config.Config{}
	cfg.JWT.Secret = guardServiceSecret
	cfg.STIX.Enabled = true
	cfg.STIX.TAXIIServer.Enabled = true

	// Results here must not depend on how busy the test machine is.
	forensicsHandler := handlers.NewForensicsHandler(forensics.NewService(log), log)
	forensicsHandler.AnalysisBudget = time.Hour
	h := &handlers.Handlers{
		DarkWeb:   handlers.NewDarkWebHandler(services.NewDarkWebMonitor(nil, nil, nil, nil, nil, log), log),
		OrbNet:    handlers.NewOrbNetHandler(services.NewOrbNetService(nil, nil, log), log),
		TAXII:     handlers.NewTAXIIHandler(services.NewSTIXTAXIIService(nil, nil, log), log),
		Forensics: forensicsHandler,
	}
	return NewRouter(cfg, h, nil, log).Setup()
}

// countingBody records how many bytes anything read from a request body. It
// has no known length, so a request built with it is sent as chunked.
type countingBody struct {
	r io.Reader
	n atomic.Int64
}

func (b *countingBody) Read(p []byte) (int, error) {
	n, err := b.r.Read(p)
	b.n.Add(int64(n))
	return n, err
}

func asAdmin() []reqOpt { return []reqOpt{asDevice(), withAdminToken(testAdminToken)} }

func asService() reqOpt {
	return func(r *http.Request) { r.Header.Set("Authorization", "Bearer "+guardServiceSecret) }
}

func decodeJSON(t *testing.T, raw []byte) map[string]any {
	t.Helper()
	var out map[string]any
	if err := json.Unmarshal(raw, &out); err != nil {
		t.Fatalf("response is not a JSON object: %v: %s", err, raw)
	}
	return out
}

func orbnetCount(t *testing.T, h http.Handler, path string) int {
	t.Helper()
	rec := do(h, http.MethodGet, path, nil, asDevice())
	if rec.Code != http.StatusOK {
		t.Fatalf("GET %s with a device key: want 200, got %d", path, rec.Code)
	}
	return int(decodeJSON(t, rec.Body.Bytes())["count"].(float64))
}

const (
	stixIndicator = `{"type":"indicator","id":"indicator--00000000-0000-4000-8000-000000000001","pattern":"[domain-name:value = 'router-test.invalid']","labels":["test"],"confidence":50}`
	stixEnvelope  = `{"objects":[` + stixIndicator + `]}`
	someUUID      = "00000000-0000-4000-8000-000000000002"
)

func TestGuardMutationsRefuseWithoutAdminAndNeverReachHandler(t *testing.T) {
	h := newGuardRouter(t)
	rulesBefore := orbnetCount(t, h, "/api/v1/orbnet/rules")

	routes := []struct{ method, path, body string }{
		{http.MethodPost, "/api/v1/darkweb/refresh", `{}`},
		{http.MethodPost, "/api/v1/orbnet/rules", `{"domain":"refused.invalid"}`},
		{http.MethodDelete, "/api/v1/orbnet/rules/" + someUUID, `{}`},
		{http.MethodPost, "/api/v1/orbnet/emergency-block", `{"domains":["refused.invalid"],"reason":"test"}`},
		{http.MethodPost, "/api/v1/orbnet/servers", `{"hostname":"refused.invalid"}`},
		{http.MethodPut, "/api/v1/orbnet/servers/" + someUUID + "/status", `{"status":"offline"}`},
		{http.MethodPost, "/taxii2/collections/community/objects", stixEnvelope},
		{http.MethodPost, "/taxii2/collections/collection--community/objects", stixEnvelope},
	}
	for i, route := range routes {
		ip := fromIP(fmt.Sprintf("192.0.2.%d", 40+i))
		cases := []struct {
			name string
			opts []reqOpt
			want int
		}{
			{"no credential", []reqOpt{ip}, http.StatusUnauthorized},
			{"device key", []reqOpt{ip, asDevice()}, http.StatusForbidden},
			{"service secret alone", []reqOpt{ip, asService()}, http.StatusForbidden},
			{"device key and wrong admin token", []reqOpt{ip, asDevice(), withAdminToken("not-the-token")}, http.StatusForbidden},
			{"admin token without bearer", []reqOpt{ip, withAdminToken(testAdminToken)}, http.StatusUnauthorized},
		}
		for _, c := range cases {
			t.Run(route.method+" "+route.path+"/"+c.name, func(t *testing.T) {
				body := &countingBody{r: strings.NewReader(route.body)}
				rec := do(h, route.method, route.path, body, c.opts...)
				if rec.Code != c.want {
					t.Fatalf("want %d, got %d: %s", c.want, rec.Code, rec.Body.String())
				}
				if n := body.n.Load(); n != 0 {
					t.Fatalf("the handler was reached: %d body bytes read", n)
				}
			})
		}
	}

	if got := orbnetCount(t, h, "/api/v1/orbnet/rules"); got != rulesBefore {
		t.Fatalf("refused calls changed the block rules: %d -> %d", rulesBefore, got)
	}
	if got := orbnetCount(t, h, "/api/v1/orbnet/servers"); got != 0 {
		t.Fatalf("a refused call registered a server: %d", got)
	}
}

func TestDarkWebRefreshAdminReachesHandler(t *testing.T) {
	h := newGuardRouter(t)
	// This router has no database, so reaching the sweep gives the handler's 500.
	rec := do(h, http.MethodPost, "/api/v1/darkweb/refresh", nil, asAdmin()...)
	if rec.Code != http.StatusInternalServerError || !strings.Contains(rec.Body.String(), "failed to refresh") {
		t.Fatalf("admin: want the handler's 500, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestOrbNetAdminCanManageRulesAndServers(t *testing.T) {
	h := newGuardRouter(t)
	admin := asAdmin()
	before := orbnetCount(t, h, "/api/v1/orbnet/rules")

	rec := do(h, http.MethodPost, "/api/v1/orbnet/rules", strings.NewReader(`{"domain":"admin-rule.invalid","category":"malware"}`), admin...)
	if rec.Code != http.StatusCreated {
		t.Fatalf("add rule: want 201, got %d: %s", rec.Code, rec.Body.String())
	}
	ruleID, _ := decodeJSON(t, rec.Body.Bytes())["id"].(string)
	if got := orbnetCount(t, h, "/api/v1/orbnet/rules"); got != before+1 {
		t.Fatalf("after add: want %d rules, got %d", before+1, got)
	}
	if rec := do(h, http.MethodDelete, "/api/v1/orbnet/rules/"+ruleID, nil, asDevice()); rec.Code != http.StatusForbidden {
		t.Fatalf("delete with a device key: want 403, got %d", rec.Code)
	}
	if got := orbnetCount(t, h, "/api/v1/orbnet/rules"); got != before+1 {
		t.Fatalf("a refused delete removed the rule: %d", got)
	}
	if rec := do(h, http.MethodDelete, "/api/v1/orbnet/rules/"+ruleID, nil, admin...); rec.Code != http.StatusNoContent {
		t.Fatalf("delete rule: want 204, got %d: %s", rec.Code, rec.Body.String())
	}

	rec = do(h, http.MethodPost, "/api/v1/orbnet/emergency-block", strings.NewReader(`{"domains":["emergency.invalid"],"reason":"test"}`), admin...)
	if rec.Code != http.StatusOK {
		t.Fatalf("emergency block: want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if got := orbnetCount(t, h, "/api/v1/orbnet/rules"); got != before+1 {
		t.Fatalf("after emergency block: want %d rules, got %d", before+1, got)
	}

	rec = do(h, http.MethodPost, "/api/v1/orbnet/servers", strings.NewReader(`{"hostname":"node.invalid"}`), admin...)
	if rec.Code != http.StatusCreated {
		t.Fatalf("register server: want 201, got %d: %s", rec.Code, rec.Body.String())
	}
	serverID, _ := decodeJSON(t, rec.Body.Bytes())["id"].(string)

	statusPath := "/api/v1/orbnet/servers/" + serverID + "/status"
	if rec := do(h, http.MethodPut, statusPath, strings.NewReader(`{"status":"offline"}`), asDevice()); rec.Code != http.StatusForbidden {
		t.Fatalf("status with a device key: want 403, got %d", rec.Code)
	}
	rec = do(h, http.MethodGet, "/api/v1/orbnet/servers/"+serverID, nil, asDevice())
	if got := decodeJSON(t, rec.Body.Bytes())["status"]; got != "online" {
		t.Fatalf("a refused status update changed the server: %v", got)
	}
	if rec := do(h, http.MethodPut, statusPath, strings.NewReader(`{"status":"offline"}`), admin...); rec.Code != http.StatusOK {
		t.Fatalf("status: want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	rec = do(h, http.MethodGet, "/api/v1/orbnet/servers/"+serverID, nil, asDevice())
	if got := decodeJSON(t, rec.Body.Bytes())["status"]; got != "offline" {
		t.Fatalf("admin status update not applied: %v", got)
	}
}

func TestOrbNetReadsStayOpenToDeviceKeys(t *testing.T) {
	h := newGuardRouter(t)
	rec := do(h, http.MethodPost, "/api/v1/orbnet/servers", strings.NewReader(`{"hostname":"node.invalid"}`), asAdmin()...)
	serverID, _ := decodeJSON(t, rec.Body.Bytes())["id"].(string)

	reads := []struct{ method, path, body string }{
		{http.MethodGet, "/api/v1/orbnet/rules", ""},
		{http.MethodGet, "/api/v1/orbnet/servers", ""},
		{http.MethodGet, "/api/v1/orbnet/servers/" + serverID, ""},
		{http.MethodGet, "/api/v1/orbnet/dashboard", ""},
		{http.MethodGet, "/api/v1/orbnet/categories", ""},
		{http.MethodGet, "/api/v1/vpn/servers", ""},
		{http.MethodGet, "/api/v1/vpn/blocked", ""},
		{http.MethodGet, "/api/v1/vpn/stats", ""},
		{http.MethodPost, "/api/v1/orbnet/dns/block", `{"domain":"example.invalid"}`},
		{http.MethodPost, "/api/v1/orbnet/dns/block/batch", `{"domains":["example.invalid"]}`},
		{http.MethodPost, "/api/v1/orbnet/sync", `{"server_id":"` + serverID + `"}`},
	}
	for _, read := range reads {
		var body io.Reader
		if read.body != "" {
			body = strings.NewReader(read.body)
		}
		if rec := do(h, read.method, read.path, body, asDevice()); rec.Code != http.StatusOK {
			t.Errorf("%s %s with a device key: want 200, got %d: %s", read.method, read.path, rec.Code, rec.Body.String())
		}
	}
}

func TestTAXIIPublicReadsWorkAndAdvertiseNoWrite(t *testing.T) {
	h := newGuardRouter(t)

	for _, path := range []string{"/taxii2/", "/taxii2/collections", "/taxii2/collections/community/objects"} {
		if rec := do(h, http.MethodGet, path, nil); rec.Code != http.StatusOK {
			t.Fatalf("anonymous GET %s: want 200, got %d: %s", path, rec.Code, rec.Body.String())
		}
	}

	rec := do(h, http.MethodGet, "/taxii2/collections", nil)
	var list struct {
		Collections []struct {
			ID       string `json:"id"`
			CanRead  bool   `json:"can_read"`
			CanWrite bool   `json:"can_write"`
		} `json:"collections"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &list); err != nil {
		t.Fatalf("decode collections: %v", err)
	}
	if len(list.Collections) != 5 {
		t.Fatalf("want 5 collections, got %d", len(list.Collections))
	}
	for _, c := range list.Collections {
		if c.CanWrite || !c.CanRead {
			t.Errorf("%s: can_read=%v can_write=%v", c.ID, c.CanRead, c.CanWrite)
		}
		one := do(h, http.MethodGet, "/taxii2/collections/"+c.ID, nil)
		if one.Code != http.StatusOK {
			t.Fatalf("anonymous GET collection %s: want 200, got %d", c.ID, one.Code)
		}
		if got := decodeJSON(t, one.Body.Bytes())["can_write"]; got != false {
			t.Errorf("%s: single-collection view has can_write=%v", c.ID, got)
		}
	}
}

func TestTAXIIAdminWrite(t *testing.T) {
	h := newGuardRouter(t)

	rec := do(h, http.MethodPost, "/taxii2/collections/community/objects", strings.NewReader(stixEnvelope), asAdmin()...)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("admin write: want 202, got %d: %s", rec.Code, rec.Body.String())
	}
	if got := decodeJSON(t, rec.Body.Bytes())["success_count"]; got != float64(1) {
		t.Fatalf("admin write: want success_count 1, got %v: %s", got, rec.Body.String())
	}

	// A collection that is not writable stays refused, even for the admin.
	rec = do(h, http.MethodPost, "/taxii2/collections/pegasus/objects", strings.NewReader(stixEnvelope), asAdmin()...)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("admin write to a read-only collection: want 403, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestTAXIIBodyLimitIsEnforcedBeforeDecoding(t *testing.T) {
	const limit = 10 << 20
	h := newGuardRouter(t)
	path := "/taxii2/collections/community/objects"

	// Chunked: no declared length, one byte over the limit inside a JSON string.
	prefix := `{"objects":[{"type":"indicator","description":"`
	over := &countingBody{r: io.MultiReader(strings.NewReader(prefix), io.LimitReader(zeroReader{}, limit), strings.NewReader(`"}]}`))}
	rec := do(h, http.MethodPost, path, over, asAdmin()...)
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized chunked body: want 413, got %d: %s", rec.Code, rec.Body.String())
	}
	if n := over.n.Load(); n > limit+1 {
		t.Fatalf("read %d bytes, past the %d limit", n, limit)
	}

	// A declared oversize length is refused without reading anything.
	declared := &countingBody{r: strings.NewReader(stixEnvelope)}
	opts := append(asAdmin(), func(r *http.Request) { r.ContentLength = limit + 1 })
	rec = do(h, http.MethodPost, path, declared, opts...)
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("declared oversize: want 413, got %d: %s", rec.Code, rec.Body.String())
	}
	if n := declared.n.Load(); n != 0 {
		t.Fatalf("declared oversize: read %d bytes", n)
	}

	// Under the limit it is an ordinary write, and bad JSON stays a 400.
	suffix := `","pattern":"[domain-name:value = 'large.invalid']"}]}`
	under := io.MultiReader(strings.NewReader(prefix), io.LimitReader(zeroReader{}, limit-int64(len(prefix)+len(suffix))), strings.NewReader(suffix))
	rec = do(h, http.MethodPost, path, under, asAdmin()...)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("body at the limit: want 202, got %d: %s", rec.Code, rec.Body.String())
	}
	rec = do(h, http.MethodPost, path, strings.NewReader(`{"objects":`), asAdmin()...)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("malformed body: want 400, got %d: %s", rec.Code, rec.Body.String())
	}
}

func assertNothingExamined(t *testing.T, code int, raw []byte) {
	t.Helper()
	if code != http.StatusUnprocessableEntity {
		t.Fatalf("want 422, got %d: %s", code, raw)
	}
	body := decodeJSON(t, raw)
	msg, _ := body["error"].(string)
	if !strings.Contains(msg, "Nothing was examined") || !strings.Contains(msg, "not an all-clear") {
		t.Fatalf("message must say nothing was examined: %q", msg)
	}
	if body["code"] != "nothing_examined" {
		t.Fatalf("code: %v", body["code"])
	}
	// The app treats these keys as a completed analysis.
	for _, key := range []string{"anomalies", "total_anomalies", "detected_threats", "infection_likelihood"} {
		if _, present := body[key]; present {
			t.Fatalf("a failure must not carry %q: %s", key, raw)
		}
	}
}

func TestFullAnalysisWithNothingToExamineIsAFailure(t *testing.T) {
	h := newGuardRouter(t)
	for _, body := range []string{
		`{"device_id":"d","platform":"ios","include_timeline":true}`,
		`{"device_id":"d","platform":"android","include_timeline":true}`,
		`{"device_id":"d","platform":"windows","include_timeline":true}`,
		`{"device_id":"d","platform":"","include_timeline":true}`,
		// Artifacts for the other platform are never parsed.
		`{"device_id":"d","platform":"android","shutdown_log":"data"}`,
		`{"device_id":"d","platform":"ios","logcat_data":"data"}`,
	} {
		rec := do(h, http.MethodPost, "/api/v1/forensics/full-analysis", strings.NewReader(body), asDevice())
		assertNothingExamined(t, rec.Code, rec.Body.Bytes())
	}
}

func TestFullAnalysisWhoseOnlyArtifactFailsIsAFailure(t *testing.T) {
	h := newGuardRouter(t)
	body := `{"device_id":"d","platform":"ios","backup_path":"/nonexistent/gfix-test-backup"}`
	rec := do(h, http.MethodPost, "/api/v1/forensics/full-analysis", strings.NewReader(body), asService())
	assertNothingExamined(t, rec.Code, rec.Body.Bytes())
}

func TestFullAnalysisWithARealScanIsUnchanged(t *testing.T) {
	h := newGuardRouter(t)
	cases := []struct {
		name, body, scan string
	}{
		{"ios shutdown log", `{"device_id":"d","platform":"ios","include_timeline":true,"shutdown_log":"2024-05-01 10:11:12.123 +0000 101 SpringBoard[101]: client exiting\n2024-05-01 10:11:12.123 +0000 101 SpringBoard[101]: client exiting\n2024-05-01 10:11:12.123 +0000 101 SpringBoard[101]: client exiting\n"}`, "shutdown_log"},
		{"android logcat", `{"device_id":"d","platform":"android","include_timeline":true,"logcat_data":"01-01 00:00:00.000  1000  1000 I ActivityManager: Start proc 1234:com.example/u0a1\n01-01 00:00:00.000  1000  1000 I ActivityManager: Start proc 1234:com.example/u0a1\n01-01 00:00:00.000  1000  1000 I ActivityManager: Start proc 1234:com.example/u0a1\n"}`, "logcat"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			rec := do(h, http.MethodPost, "/api/v1/forensics/full-analysis", strings.NewReader(c.body), asService())
			if rec.Code != http.StatusOK {
				t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
			}
			body := decodeJSON(t, rec.Body.Bytes())
			if _, ok := body["anomalies"].([]any); !ok {
				t.Fatalf("a real scan must carry an anomalies list: %s", rec.Body.String())
			}
			if _, ok := body["total_anomalies"].(float64); !ok {
				t.Fatalf("a real scan must carry total_anomalies: %s", rec.Body.String())
			}
			raw, _ := body["raw_data"].(map[string]any)
			scans, _ := raw["scans_performed"].([]any)
			if len(scans) != 1 || scans[0] != c.scan {
				t.Fatalf("scans_performed: want [%s], got %v", c.scan, scans)
			}
		})
	}
}
