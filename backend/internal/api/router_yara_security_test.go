package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/rs/zerolog"

	"orbguard-lab/internal/api/handlers"
	apimiddleware "orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/config"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/pkg/logger"
)

// These tests drive the REAL route table (Router.Setup) with the real
// APIKeyAuth/AdminAuth middleware and the real YARA handler and engine; only
// the token store and the lockout counter are in-memory. They pin down the
// permission model for the global YARA rule set: any device key may read and
// scan, only the admin token may add, delete or reload.

const (
	testDeviceKey  = "device-key-for-router-tests"
	testAdminToken = "router-test-admin-token-0123456789abcdef0123456789"
)

// memTokenStore knows exactly one device API key.
type memTokenStore struct{}

func (memTokenStore) GetJSON(_ context.Context, key string, dest any) error {
	if key != "auth:apikey:"+testDeviceKey {
		return errors.New("not found")
	}
	raw, err := json.Marshal(apimiddleware.TokenClaims{
		DeviceID:  "dev-1",
		ExpiresAt: time.Now().Add(time.Hour),
	})
	if err != nil {
		return err
	}
	return json.Unmarshal(raw, dest)
}

// memLockout is an in-memory AdminLockoutStore with Redis semantics.
type memLockout struct {
	mu      sync.Mutex
	counts  map[string]int64
	expires map[string]time.Time
}

func newMemLockout() *memLockout {
	return &memLockout{counts: map[string]int64{}, expires: map[string]time.Time{}}
}

func (m *memLockout) RecordFailure(_ context.Context, key string, window time.Duration) (int64, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if exp, ok := m.expires[key]; ok && time.Now().After(exp) {
		delete(m.counts, key)
	}
	m.counts[key]++
	m.expires[key] = time.Now().Add(window)
	return m.counts[key], nil
}

func (m *memLockout) FailureCount(_ context.Context, key string) (int64, time.Duration, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	exp, ok := m.expires[key]
	if !ok || time.Now().After(exp) {
		return 0, 0, nil
	}
	return m.counts[key], time.Until(exp), nil
}

func (m *memLockout) ClearFailures(_ context.Context, key string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.counts, key)
	delete(m.expires, key)
	return nil
}

// newTestRouter builds the production router around a real YARA handler
// (built-in rules loaded, no Redis, no database) with the given admin token
// installed, and returns it with the buffer every log line lands in.
func newTestRouter(t *testing.T, adminToken string) (http.Handler, *bytes.Buffer) {
	return newTestRouterWith(t, adminToken, config.Config{})
}

// newTestRouterWith is newTestRouter with a config of the caller's choosing.
func newTestRouterWith(t *testing.T, adminToken string, cfg config.Config) (http.Handler, *bytes.Buffer) {
	t.Helper()
	buf := &bytes.Buffer{}
	log := &logger.Logger{Logger: zerolog.New(buf)}

	apimiddleware.ConfigureAuth(memTokenStore{}, "test", log)
	apimiddleware.ConfigureAdminAuth(adminToken, newMemLockout(), log)
	t.Cleanup(func() {
		apimiddleware.ConfigureAuth(nil, "", nil)
		apimiddleware.ConfigureAdminAuth("", nil, nil)
		apimiddleware.ConfigureOrbNetJWT("") // Setup installs cfg's secret
	})

	// Only the YARA handler is real; Setup takes method values from the other
	// (nil) handlers without dereferencing them, and no test calls them.
	h := &handlers.Handlers{
		YARA: handlers.NewYARAHandler(services.NewYARAService("", nil, log), log),
	}
	return NewRouter(cfg, h, nil, log).Setup(), buf
}

type reqOpt func(*http.Request)

func asDevice() reqOpt {
	return func(r *http.Request) { r.Header.Set("Authorization", "Bearer "+testDeviceKey) }
}

func withAdminToken(token string) reqOpt {
	return func(r *http.Request) { r.Header.Set("X-Admin-Token", token) }
}

// ingressPeer is where the Container Apps ingress connects to the app from.
const ingressPeer = "100.100.0.7:43210"

// clientHeader is a header exactly as the client sent it. Use it before
// fromIP, which plays the ingress and appends to what the client wrote.
func clientHeader(key, value string) reqOpt {
	return func(r *http.Request) { r.Header.Add(key, value) }
}

// fromIP delivers the request the way production traffic arrives: through
// the ingress, which connects from an internal address and appends the
// client's real address to whatever X-Forwarded-For the client sent.
func fromIP(ip string) reqOpt {
	return func(r *http.Request) {
		r.RemoteAddr = ingressPeer
		hops := ip
		if prior := r.Header.Get("X-Forwarded-For"); prior != "" {
			hops = prior + ", " + ip
		}
		r.Header.Set("X-Forwarded-For", hops)
	}
}

func do(h http.Handler, method, path string, body io.Reader, opts ...reqOpt) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, body)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	for _, opt := range opts {
		opt(req)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

// sampleRule is a rule the engine accepts: at least one string and a condition.
func sampleRule(name string) io.Reader {
	return strings.NewReader(fmt.Sprintf(`{
		"name": %q,
		"description": "router test rule",
		"category": "spyware",
		"severity": "high",
		"strings": [{"id": "$a", "value": "com.example.router-test", "type": "text"}],
		"conditions": [{"expression": "any of them"}]
	}`, name))
}

func createdRuleID(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	var created struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &created); err != nil || created.ID == "" {
		t.Fatalf("201 body must carry the rule id, got %q (err %v)", rec.Body.String(), err)
	}
	return created.ID
}

func TestYARAReadIsOpenToDeviceKeys(t *testing.T) {
	h, _ := newTestRouter(t, testAdminToken)

	if rec := do(h, http.MethodGet, "/api/v1/yara/rules", nil, asDevice()); rec.Code != http.StatusOK {
		t.Fatalf("GET /yara/rules with a device key: want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if rec := do(h, http.MethodGet, "/api/v1/yara/categories", nil, asDevice()); rec.Code != http.StatusOK {
		t.Fatalf("GET /yara/categories: want 200, got %d", rec.Code)
	}
	if rec := do(h, http.MethodGet, "/api/v1/yara/stats", nil, asDevice()); rec.Code != http.StatusOK {
		t.Fatalf("GET /yara/stats: want 200, got %d", rec.Code)
	}
	parse := strings.NewReader(`{"rule_content":"rule R { strings: $a = \"x\" condition: any of them }"}`)
	if rec := do(h, http.MethodPost, "/api/v1/yara/parse", parse, asDevice()); rec.Code != http.StatusOK {
		t.Fatalf("POST /yara/parse with a device key: want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	scan := strings.NewReader(`{"content":"nothing suspicious here"}`)
	if rec := do(h, http.MethodPost, "/api/v1/yara/quick-scan", scan, asDevice()); rec.Code != http.StatusOK {
		t.Fatalf("POST /yara/quick-scan with a device key: want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if rec := do(h, http.MethodGet, "/api/v1/yara/rules", nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("GET /yara/rules without a credential: want 401, got %d", rec.Code)
	}
}

func TestYARAMutationsRequireAdmin(t *testing.T) {
	h, _ := newTestRouter(t, testAdminToken)

	mutations := []struct{ method, path string }{
		{http.MethodPost, "/api/v1/yara/rules"},
		{http.MethodDelete, "/api/v1/yara/rules/00000000-0000-0000-0000-000000000001"},
		{http.MethodPost, "/api/v1/yara/reload"},
		{http.MethodPost, "/api/v1/admin/yara/rules"},
		{http.MethodDelete, "/api/v1/admin/yara/rules/00000000-0000-0000-0000-000000000001"},
		{http.MethodPost, "/api/v1/admin/yara/reload"},
	}
	for i, m := range mutations {
		// One address per route: the wrong-token probe below counts toward
		// that address's lockout, and this test is about 403, not 429.
		ip := fromIP(fmt.Sprintf("192.0.2.%d", 10+i))
		t.Run(m.method+" "+m.path, func(t *testing.T) {
			if rec := do(h, m.method, m.path, sampleRule("Nope"), ip); rec.Code != http.StatusUnauthorized {
				t.Fatalf("no credential: want 401, got %d", rec.Code)
			}
			if rec := do(h, m.method, m.path, sampleRule("Nope"), ip, asDevice()); rec.Code != http.StatusForbidden {
				t.Fatalf("device key alone: want 403, got %d: %s", rec.Code, rec.Body.String())
			}
			if rec := do(h, m.method, m.path, sampleRule("Nope"), ip, asDevice(), withAdminToken("not-the-token")); rec.Code != http.StatusForbidden {
				t.Fatalf("device key + wrong admin token: want 403, got %d", rec.Code)
			}
			// The admin token on its own is not a bearer credential.
			if rec := do(h, m.method, m.path, sampleRule("Nope"), ip, withAdminToken(testAdminToken)); rec.Code != http.StatusUnauthorized {
				t.Fatalf("admin token without a bearer credential: want 401, got %d", rec.Code)
			}
		})
	}
	// None of the refusals changed the rule set: the rule never appeared.
	rec := do(h, http.MethodGet, "/api/v1/yara/rules?limit=200", nil, asDevice())
	if strings.Contains(rec.Body.String(), `"name":"Nope"`) {
		t.Fatal("a refused POST must not add a rule")
	}
}

func TestYARAAdminCanManageRules(t *testing.T) {
	for _, prefix := range []string{"/api/v1/yara", "/api/v1/admin/yara"} {
		t.Run(prefix, func(t *testing.T) {
			h, buf := newTestRouter(t, testAdminToken)
			admin := []reqOpt{asDevice(), withAdminToken(testAdminToken)}

			rec := do(h, http.MethodPost, prefix+"/rules", sampleRule("Router_Test_Rule"), admin...)
			if rec.Code != http.StatusCreated {
				t.Fatalf("POST %s/rules with admin: want 201, got %d: %s", prefix, rec.Code, rec.Body.String())
			}
			id := createdRuleID(t, rec)

			// Visible to the app through the ordinary read path.
			if rec := do(h, http.MethodGet, "/api/v1/yara/rules/"+id, nil, asDevice()); rec.Code != http.StatusOK {
				t.Fatalf("GET new rule: want 200, got %d", rec.Code)
			}

			if rec := do(h, http.MethodPost, prefix+"/reload", nil, admin...); rec.Code != http.StatusOK {
				t.Fatalf("POST %s/reload with admin: want 200, got %d: %s", prefix, rec.Code, rec.Body.String())
			}

			if rec := do(h, http.MethodDelete, prefix+"/rules/"+id, nil, admin...); rec.Code != http.StatusNoContent {
				t.Fatalf("DELETE %s/rules/{id} with admin: want 204, got %d: %s", prefix, rec.Code, rec.Body.String())
			}
			if rec := do(h, http.MethodGet, "/api/v1/yara/rules/"+id, nil, asDevice()); rec.Code != http.StatusNotFound {
				t.Fatalf("GET deleted rule: want 404, got %d", rec.Code)
			}

			// Every admin call left an audit line naming the caller, never the token.
			logs := buf.String()
			for _, want := range []string{
				`"component":"admin-audit"`,
				`"method":"POST"`,
				`"path":"` + prefix + `/rules"`,
				`"device_id":"dev-1"`,
				`"status":201`,
				`"method":"DELETE"`,
				`"status":204`,
			} {
				if !strings.Contains(logs, want) {
					t.Errorf("audit log missing %s", want)
				}
			}
			if strings.Contains(logs, testAdminToken) || strings.Contains(logs, testDeviceKey) {
				t.Fatal("logs must never contain the admin token or the device key")
			}
		})
	}
}

func TestYARAAdminLockoutAfterRepeatedWrongTokens(t *testing.T) {
	h, _ := newTestRouter(t, testAdminToken)
	attacker := fromIP("203.0.113.77")

	for i := 1; i <= 4; i++ {
		rec := do(h, http.MethodPost, "/api/v1/yara/reload", nil, asDevice(), attacker, withAdminToken(fmt.Sprintf("guess-%d", i)))
		if rec.Code != http.StatusForbidden {
			t.Fatalf("wrong token %d: want 403, got %d", i, rec.Code)
		}
	}
	rec := do(h, http.MethodPost, "/api/v1/yara/reload", nil, asDevice(), attacker, withAdminToken("guess-5"))
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("5th wrong token: want 429, got %d: %s", rec.Code, rec.Body.String())
	}
	if rec.Header().Get("Retry-After") == "" {
		t.Fatal("429 must carry Retry-After")
	}

	// Locked out: the right token from that address is refused as well...
	rec = do(h, http.MethodPost, "/api/v1/yara/reload", nil, asDevice(), attacker, withAdminToken(testAdminToken))
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("correct token from locked address: want 429, got %d", rec.Code)
	}
	// ...on the alias paths too, since the lock is per address not per route...
	rec = do(h, http.MethodPost, "/api/v1/admin/yara/reload", nil, asDevice(), attacker, withAdminToken(testAdminToken))
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("correct token on alias from locked address: want 429, got %d", rec.Code)
	}
	// ...while another address keeps working, and reads were never affected.
	rec = do(h, http.MethodPost, "/api/v1/yara/reload", nil, asDevice(), fromIP("198.51.100.20"), withAdminToken(testAdminToken))
	if rec.Code != http.StatusOK {
		t.Fatalf("correct token from another address: want 200, got %d", rec.Code)
	}
	if rec := do(h, http.MethodGet, "/api/v1/yara/rules", nil, asDevice(), attacker); rec.Code != http.StatusOK {
		t.Fatalf("locked address reading rules: want 200, got %d", rec.Code)
	}
}

// TestYARAAdminLockoutSurvivesHeaderSpoofing runs the two attacks on the
// lockout through the real middleware chain (PeerAddress, RealIP, APIKeyAuth,
// AdminAuth): forged forwarding headers must neither spread one guesser's
// failures over invented addresses nor let anyone lock an operator out by
// naming the operator's address.
func TestYARAAdminLockoutSurvivesHeaderSpoofing(t *testing.T) {
	h, _ := newTestRouter(t, testAdminToken)
	const attacker, operator = "203.0.113.90", "198.51.100.90"

	// Every guess claims a fresh address in X-Real-IP, True-Client-IP and the
	// client's own X-Forwarded-For; the ingress still appends the real one.
	for i := 1; i <= 5; i++ {
		spoof := fmt.Sprintf("192.0.2.%d", 100+i)
		rec := do(h, http.MethodPost, "/api/v1/yara/reload", nil, asDevice(),
			clientHeader("X-Real-IP", spoof), clientHeader("True-Client-IP", spoof), clientHeader("X-Forwarded-For", spoof),
			fromIP(attacker), withAdminToken(fmt.Sprintf("guess-%d", i)))
		want := http.StatusForbidden
		if i == 5 {
			want = http.StatusTooManyRequests
		}
		if rec.Code != want {
			t.Fatalf("guess %d with rotated headers: want %d, got %d", i, want, rec.Code)
		}
	}
	// The real address is locked whatever it claims to be.
	rec := do(h, http.MethodPost, "/api/v1/admin/yara/reload", nil, asDevice(),
		clientHeader("X-Real-IP", operator), fromIP(attacker), withAdminToken(testAdminToken))
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("locked attacker claiming the operator's address: want 429, got %d", rec.Code)
	}

	// Naming the operator in every spoofable header, ten times over...
	for i := 0; i < 10; i++ {
		do(h, http.MethodPost, "/api/v1/admin/yara/reload", nil, asDevice(),
			clientHeader("X-Real-IP", operator), clientHeader("True-Client-IP", operator), clientHeader("X-Forwarded-For", operator),
			fromIP("203.0.113.91"), withAdminToken("wrong"))
	}
	// ...leaves the operator, arriving through the ingress, able to work.
	rec = do(h, http.MethodPost, "/api/v1/admin/yara/reload", nil, asDevice(), fromIP(operator), withAdminToken(testAdminToken))
	if rec.Code != http.StatusOK {
		t.Fatalf("operator after spoofed lock attempts: want 200, got %d: %s", rec.Code, rec.Body.String())
	}
}

// TestYARAAdminAuditNamesOrbNetAccount: a web-panel caller authenticates
// with an OrbNet account JWT, whose identity lives only in the OrbNet user
// id; its admin calls must still be attributable in the audit log.
func TestYARAAdminAuditNamesOrbNetAccount(t *testing.T) {
	const secret = "router-test-orbnet-secret-0123456789abcdef"
	cfg := config.Config{}
	cfg.JWT.OrbNetAccessSecret = secret
	h, buf := newTestRouterWith(t, testAdminToken, cfg)

	signed, err := jwt.NewWithClaims(jwt.SigningMethodHS256, apimiddleware.OrbNetClaims{
		UserID: 4711,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    "orbnet",
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
		},
	}).SignedString([]byte(secret))
	if err != nil {
		t.Fatalf("sign test JWT: %v", err)
	}
	asAccount := func(r *http.Request) { r.Header.Set("Authorization", "Bearer "+signed) }

	rec := do(h, http.MethodPost, "/api/v1/admin/yara/reload", nil, asAccount, fromIP("198.51.100.44"), withAdminToken(testAdminToken))
	if rec.Code != http.StatusOK {
		t.Fatalf("OrbNet JWT + admin token: want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var audit string
	for _, line := range strings.Split(buf.String(), "\n") {
		if strings.Contains(line, `"component":"admin-audit"`) {
			audit = line
		}
	}
	for _, want := range []string{`"orbnet_user_id":4711`, `"path":"/api/v1/admin/yara/reload"`, `"remote_ip":"198.51.100.44"`, `"status":200`} {
		if !strings.Contains(audit, want) {
			t.Errorf("audit line missing %s: %s", want, audit)
		}
	}
	if strings.Contains(buf.String(), signed) || strings.Contains(buf.String(), testAdminToken) {
		t.Fatal("logs must never contain the JWT or the admin token")
	}
}

func TestYARAWeakAdminTokenDisablesAdminRoutes(t *testing.T) {
	const weak = "changeme"
	h, buf := newTestRouter(t, weak)

	if !strings.Contains(buf.String(), `"level":"error"`) || !strings.Contains(buf.String(), "rejected as weak") {
		t.Fatalf("expected an ERROR log at startup for the weak token, got:\n%s", buf.String())
	}

	rec := do(h, http.MethodPost, "/api/v1/yara/rules", sampleRule("Weak"), asDevice(), withAdminToken(weak))
	if rec.Code != http.StatusForbidden {
		t.Fatalf("weak configured token presented: want 403, got %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "not configured") {
		t.Fatalf("expected the 'admin access is not configured' answer, got %s", rec.Body.String())
	}
	if !strings.Contains(buf.String(), "admin routes are disabled") {
		t.Fatalf("expected a request-time log that admin routes are disabled, got:\n%s", buf.String())
	}
	if strings.Contains(buf.String(), `"component":"admin-audit"`) {
		t.Fatal("no admin-audit line may be written while admin is disabled")
	}
}

func TestYARARuleBodiesAreCapped(t *testing.T) {
	h, _ := newTestRouter(t, testAdminToken)

	// 300 KiB of rule text: over the 256 KiB cap for parse and submit.
	huge := strings.Repeat("a", 300<<10)

	rec := do(h, http.MethodPost, "/api/v1/yara/parse", strings.NewReader(`{"rule_content":"`+huge+`"}`), asDevice())
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized /yara/parse: want 413, got %d: %s", rec.Code, rec.Body.String())
	}
	rec = do(h, http.MethodPost, "/api/v1/yara/submit", strings.NewReader(`{"name":"big","raw_rule":"`+huge+`"}`), asDevice())
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized /yara/submit: want 413, got %d: %s", rec.Code, rec.Body.String())
	}

	// Garbage under the cap is a plain 400, and a normal rule still parses.
	rec = do(h, http.MethodPost, "/api/v1/yara/parse", strings.NewReader(`{"rule_content":`), asDevice())
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("malformed /yara/parse body: want 400, got %d", rec.Code)
	}
	small := strings.NewReader(`{"rule_content":"rule Small { strings: $a = \"indicator\" condition: any of them }"}`)
	rec = do(h, http.MethodPost, "/api/v1/yara/parse", small, asDevice())
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"valid":true`) {
		t.Fatalf("normal /yara/parse: want 200 valid, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestYARAScanBodiesAreCapped(t *testing.T) {
	h, _ := newTestRouter(t, testAdminToken)

	// One byte over 64 MiB, as a streaming body so the test does not hold a
	// second copy; the handler must stop reading at the cap and answer 413.
	const over = (64 << 20) + 1
	prefix := `{"base64_data":"`
	body := io.MultiReader(strings.NewReader(prefix), io.LimitReader(zeroReader{}, over-int64(len(prefix))), strings.NewReader(`"}`))

	for _, path := range []string{"/api/v1/yara/scan", "/api/v1/yara/scan/apk", "/api/v1/yara/scan/ipa"} {
		rec := do(h, http.MethodPost, path, body, asDevice())
		if rec.Code != http.StatusRequestEntityTooLarge {
			t.Fatalf("oversized %s: want 413, got %d: %s", path, rec.Code, rec.Body.String())
		}
		body = io.MultiReader(strings.NewReader(prefix), io.LimitReader(zeroReader{}, over-int64(len(prefix))), strings.NewReader(`"}`))
	}
}

// zeroReader yields an endless run of 'A' (valid base64) for size tests.
type zeroReader struct{}

func (zeroReader) Read(p []byte) (int, error) {
	for i := range p {
		p[i] = 'A'
	}
	return len(p), nil
}
