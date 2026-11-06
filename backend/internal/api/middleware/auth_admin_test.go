package middleware

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"

	"orbguard-lab/pkg/logger"
)

// strongToken is 48 characters of nothing special; only its length matters.
const strongToken = "unit-test-admin-token-0123456789abcdef0123456789"

// memLockout is an in-memory AdminLockoutStore with Redis semantics (count
// with an expiry re-armed on every failure). failErr, when set, makes every
// call fail so the fail-open path can be exercised.
type memLockout struct {
	mu      sync.Mutex
	counts  map[string]int64
	expires map[string]time.Time
	// noExpiry marks counters that exist without an expiry, the damaged
	// state a half-applied Redis write would leave behind.
	noExpiry map[string]bool
	failErr  error
	now      func() time.Time
}

func newMemLockout() *memLockout {
	return &memLockout{
		counts:   map[string]int64{},
		expires:  map[string]time.Time{},
		noExpiry: map[string]bool{},
		now:      time.Now,
	}
}

// seedWithoutExpiry plants a counter with no expiry, as `SET key n` would.
func (m *memLockout) seedWithoutExpiry(key string, count int64) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.counts[key] = count
	m.noExpiry[key] = true
	delete(m.expires, key)
}

func (m *memLockout) RecordFailure(_ context.Context, key string, window time.Duration) (int64, error) {
	if m.failErr != nil {
		return 0, m.failErr
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if exp, ok := m.expires[key]; ok && m.now().After(exp) {
		delete(m.counts, key)
	}
	m.counts[key]++
	m.expires[key] = m.now().Add(window)
	delete(m.noExpiry, key)
	return m.counts[key], nil
}

func (m *memLockout) FailureCount(_ context.Context, key string) (int64, time.Duration, error) {
	if m.failErr != nil {
		return 0, 0, m.failErr
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.noExpiry[key] {
		return m.counts[key], -1, nil
	}
	exp, ok := m.expires[key]
	if !ok || m.now().After(exp) {
		return 0, 0, nil
	}
	return m.counts[key], exp.Sub(m.now()), nil
}

func (m *memLockout) ClearFailures(_ context.Context, key string) error {
	if m.failErr != nil {
		return m.failErr
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.counts, key)
	delete(m.expires, key)
	delete(m.noExpiry, key)
	return nil
}

// captureLogger returns a JSON logger writing into buf so tests can assert
// on what was (and was not) logged.
func captureLogger() (*logger.Logger, *bytes.Buffer) {
	buf := &bytes.Buffer{}
	return &logger.Logger{Logger: zerolog.New(buf)}, buf
}

// configureAdmin installs the admin state for one test and restores the
// disabled state afterwards so tests do not leak into each other.
func configureAdmin(t *testing.T, token string, lockout AdminLockoutStore) *bytes.Buffer {
	t.Helper()
	log, buf := captureLogger()
	ConfigureAdminAuth(token, lockout, log)
	t.Cleanup(func() { ConfigureAdminAuth("", nil, nil) })
	return buf
}

// adminHandler is AdminAuth in front of a handler that records it was reached.
func adminHandler(t *testing.T) (http.Handler, *bool) {
	t.Helper()
	reached := false
	h := AdminAuth("ignored")(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reached = true
		if !IsAdmin(r.Context()) {
			t.Error("handler reached without the admin flag in context")
		}
		w.WriteHeader(http.StatusOK)
	}))
	return h, &reached
}

// adminReq builds a request that already passed APIKeyAuth as device dev-1
// from remoteAddr, presenting token in the X-Admin-Token header ("" = none).
func adminReq(method, target, remoteAddr, token, body string) *http.Request {
	var rdr io.Reader
	if body != "" {
		rdr = strings.NewReader(body)
	}
	req := httptest.NewRequest(method, target, rdr)
	req.RemoteAddr = remoteAddr
	if token != "" {
		req.Header.Set("X-Admin-Token", token)
	}
	ctx := context.WithValue(req.Context(), ContextKeyAPIKey, "device-api-key")
	ctx = context.WithValue(ctx, ContextKeyDeviceID, "dev-1")
	return req.WithContext(ctx)
}

func serve(h http.Handler, req *http.Request) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestAdminTokenWeak(t *testing.T) {
	tests := []struct {
		name  string
		token string
		weak  bool
	}{
		{"empty is not set", "", true},
		{"whitespace only is not set", "   \n", true},
		{"dev placeholder", "dev-admin-token", true},
		{"dev placeholder, upper case", "DEV-ADMIN-TOKEN", true},
		{"changeme placeholder", "changeme", true},
		{"admin placeholder", "admin", true},
		{"31 characters is too short", strings.Repeat("x", 31), true},
		{"32 characters is the floor", strings.Repeat("x", 32), false},
		{"surrounding whitespace is trimmed before measuring", "  " + strings.Repeat("x", 31) + "  ", true},
		{"strong token", strongToken, false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			reason, weak := adminTokenWeak(tc.token)
			if weak != tc.weak {
				t.Fatalf("adminTokenWeak(%q) weak=%v, want %v", tc.token, weak, tc.weak)
			}
			if weak && reason == "" {
				t.Fatal("a weak verdict must carry a reason for the log")
			}
			if !weak && reason != "" {
				t.Fatalf("a strong token must not carry a reason, got %q", reason)
			}
			if strings.Contains(reason, strings.TrimSpace(tc.token)) && strings.TrimSpace(tc.token) != "" {
				t.Fatalf("reason %q leaks the token", reason)
			}
		})
	}
}

func TestConfigureAdminAuthWeakTokenDisablesAdmin(t *testing.T) {
	for _, weak := range []string{"changeme", "dev-admin-token", "short-token-value"} {
		t.Run(weak, func(t *testing.T) {
			buf := configureAdmin(t, weak, newMemLockout())

			if !strings.Contains(buf.String(), `"level":"error"`) || !strings.Contains(buf.String(), "rejected as weak") {
				t.Fatalf("expected an ERROR log naming the weak token at configure time, got:\n%s", buf.String())
			}
			if strings.Contains(buf.String(), weak) {
				t.Fatalf("configure-time log leaks the token value:\n%s", buf.String())
			}

			h, reached := adminHandler(t)
			// Even the (weak) configured value is refused: the routes are off.
			rec := serve(h, adminReq(http.MethodPost, "/admin/x", "10.0.0.1:1", weak, ""))
			if rec.Code != http.StatusForbidden {
				t.Fatalf("weak configured token: want 403, got %d", rec.Code)
			}
			if *reached {
				t.Fatal("handler must not run while admin is disabled")
			}
			if !strings.Contains(buf.String(), "admin routes are disabled") {
				t.Fatalf("expected the request-time log to say admin routes are disabled, got:\n%s", buf.String())
			}
		})
	}
}

func TestConfigureAdminAuthUnsetDisablesAdmin(t *testing.T) {
	buf := configureAdmin(t, "", nil)
	if !strings.Contains(buf.String(), "is not set") {
		t.Fatalf("expected a log that the token is not set, got:\n%s", buf.String())
	}
	h, _ := adminHandler(t)
	rec := serve(h, adminReq(http.MethodPost, "/admin/x", "10.0.0.1:1", "anything", ""))
	if rec.Code != http.StatusForbidden {
		t.Fatalf("unset token: want 403, got %d", rec.Code)
	}
}

func TestAdminAuthRequiresAPIKeyFirst(t *testing.T) {
	configureAdmin(t, strongToken, newMemLockout())
	h, reached := adminHandler(t)

	req := httptest.NewRequest(http.MethodPost, "/admin/x", nil)
	req.Header.Set("X-Admin-Token", strongToken)
	rec := serve(h, req) // no APIKeyAuth context
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("admin token without a bearer credential: want 401, got %d", rec.Code)
	}
	if *reached {
		t.Fatal("handler must not run without a bearer credential")
	}
}

func TestAdminAuthAcceptsHeaderOnly(t *testing.T) {
	configureAdmin(t, strongToken, newMemLockout())
	h, reached := adminHandler(t)

	t.Run("header is accepted", func(t *testing.T) {
		*reached = false
		rec := serve(h, adminReq(http.MethodPost, "/admin/x", "10.0.0.1:1", strongToken, ""))
		if rec.Code != http.StatusOK || !*reached {
			t.Fatalf("want 200 and handler reached, got %d reached=%v", rec.Code, *reached)
		}
	})

	t.Run("query string is not a fallback", func(t *testing.T) {
		*reached = false
		for _, q := range []string{"X-Admin-Token", "x-admin-token", "admin_token", "token"} {
			rec := serve(h, adminReq(http.MethodPost, "/admin/x?"+q+"="+strongToken, "10.0.0.2:1", "", ""))
			if rec.Code != http.StatusForbidden || *reached {
				t.Fatalf("token in query param %q: want 403 and handler not reached, got %d reached=%v", q, rec.Code, *reached)
			}
		}
	})

	t.Run("body is not a fallback", func(t *testing.T) {
		*reached = false
		body := `{"admin_token":"` + strongToken + `","X-Admin-Token":"` + strongToken + `"}`
		req := adminReq(http.MethodPost, "/admin/x", "10.0.0.3:1", "", body)
		req.Header.Set("Content-Type", "application/json")
		rec := serve(h, req)
		if rec.Code != http.StatusForbidden || *reached {
			t.Fatalf("token in body: want 403 and handler not reached, got %d reached=%v", rec.Code, *reached)
		}
	})

	t.Run("wrong header value is refused", func(t *testing.T) {
		*reached = false
		rec := serve(h, adminReq(http.MethodPost, "/admin/x", "10.0.0.4:1", strongToken+"x", ""))
		if rec.Code != http.StatusForbidden || *reached {
			t.Fatalf("wrong token: want 403, got %d reached=%v", rec.Code, *reached)
		}
	})
}

func TestAdminAuthLockout(t *testing.T) {
	store := newMemLockout()
	buf := configureAdmin(t, strongToken, store)
	h, reached := adminHandler(t)
	const attacker = "203.0.113.9:40000"

	for i := 1; i <= adminLockoutThreshold-1; i++ {
		rec := serve(h, adminReq(http.MethodPost, "/admin/x", attacker, "wrong-guess", ""))
		if rec.Code != http.StatusForbidden {
			t.Fatalf("failure %d: want 403, got %d", i, rec.Code)
		}
	}

	// The attempt that reaches the threshold is already answered 429.
	rec := serve(h, adminReq(http.MethodPost, "/admin/x", attacker, "wrong-guess", ""))
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("failure %d: want 429, got %d", adminLockoutThreshold, rec.Code)
	}
	if rec.Header().Get("Retry-After") == "" {
		t.Fatal("429 must carry Retry-After")
	}

	// Locked: the RIGHT token is refused too, and never reaches the handler.
	*reached = false
	rec = serve(h, adminReq(http.MethodPost, "/admin/x", attacker, strongToken, ""))
	if rec.Code != http.StatusTooManyRequests || *reached {
		t.Fatalf("correct token while locked: want 429 and handler not reached, got %d reached=%v", rec.Code, *reached)
	}

	// Another address is unaffected.
	*reached = false
	rec = serve(h, adminReq(http.MethodPost, "/admin/x", "198.51.100.7:1", strongToken, ""))
	if rec.Code != http.StatusOK || !*reached {
		t.Fatalf("other address with the correct token: want 200, got %d reached=%v", rec.Code, *reached)
	}

	// The lock lapses with the window.
	store.now = func() time.Time { return time.Now().Add(adminLockoutWindow + time.Second) }
	*reached = false
	rec = serve(h, adminReq(http.MethodPost, "/admin/x", attacker, strongToken, ""))
	if rec.Code != http.StatusOK || !*reached {
		t.Fatalf("after the window: want 200, got %d reached=%v", rec.Code, *reached)
	}

	if strings.Contains(buf.String(), "wrong-guess") || strings.Contains(buf.String(), strongToken) {
		t.Fatalf("logs must never contain a presented or configured token:\n%s", buf.String())
	}
	if !strings.Contains(buf.String(), "invalid admin token presented") {
		t.Fatalf("expected a WARN per failure, got:\n%s", buf.String())
	}
}

func TestAdminAuthSuccessResetsFailures(t *testing.T) {
	store := newMemLockout()
	configureAdmin(t, strongToken, store)
	h, _ := adminHandler(t)
	const operator = "192.0.2.50:5000"

	for i := 0; i < 2; i++ {
		if rec := serve(h, adminReq(http.MethodPost, "/admin/x", operator, "typo", "")); rec.Code != http.StatusForbidden {
			t.Fatalf("typo %d: want 403, got %d", i+1, rec.Code)
		}
	}
	if rec := serve(h, adminReq(http.MethodPost, "/admin/x", operator, strongToken, "")); rec.Code != http.StatusOK {
		t.Fatalf("correct token after typos: want 200, got %d", rec.Code)
	}
	if n, _, _ := store.FailureCount(context.Background(), adminLockoutKeyPrefix+"192.0.2.50"); n != 0 {
		t.Fatalf("success must reset the counter, still %d", n)
	}
	// Four more typos stay below the threshold only because the reset happened.
	for i := 0; i < adminLockoutThreshold-1; i++ {
		if rec := serve(h, adminReq(http.MethodPost, "/admin/x", operator, "typo", "")); rec.Code != http.StatusForbidden {
			t.Fatalf("post-reset typo %d: want 403, got %d", i+1, rec.Code)
		}
	}
}

func TestAdminAuthLockoutFailsOpenWhenStoreIsDown(t *testing.T) {
	store := newMemLockout()
	store.failErr = errors.New("redis: connection refused")
	buf := configureAdmin(t, strongToken, store)
	h, reached := adminHandler(t)

	for i := 0; i < adminLockoutThreshold+2; i++ {
		if rec := serve(h, adminReq(http.MethodPost, "/admin/x", "10.9.9.9:1", "wrong", "")); rec.Code != http.StatusForbidden {
			t.Fatalf("wrong token with store down: want plain 403, got %d", rec.Code)
		}
	}
	rec := serve(h, adminReq(http.MethodPost, "/admin/x", "10.9.9.9:1", strongToken, ""))
	if rec.Code != http.StatusOK || !*reached {
		t.Fatalf("correct token with store down: want 200, got %d reached=%v", rec.Code, *reached)
	}
	if !strings.Contains(buf.String(), "lockout store unavailable") {
		t.Fatalf("store failures must be logged, got:\n%s", buf.String())
	}
}

func TestAdminAuthWithoutLockoutStore(t *testing.T) {
	buf := configureAdmin(t, strongToken, nil)
	if !strings.Contains(buf.String(), "no lockout store wired") {
		t.Fatalf("missing lockout store must be logged at configure time, got:\n%s", buf.String())
	}
	h, _ := adminHandler(t)
	for i := 0; i < adminLockoutThreshold+3; i++ {
		if rec := serve(h, adminReq(http.MethodPost, "/admin/x", "10.1.1.1:1", "wrong", "")); rec.Code != http.StatusForbidden {
			t.Fatalf("no store: wrong token must stay a plain 403, got %d", rec.Code)
		}
	}
	if rec := serve(h, adminReq(http.MethodPost, "/admin/x", "10.1.1.1:1", strongToken, "")); rec.Code != http.StatusOK {
		t.Fatalf("no store: correct token want 200, got %d", rec.Code)
	}
}

func TestAdminAuthAuditLog(t *testing.T) {
	buf := configureAdmin(t, strongToken, newMemLockout())
	h, _ := adminHandler(t)

	req := adminReq(http.MethodDelete, "/api/v1/yara/rules/abc", "203.0.113.5:7777", strongToken, "")
	ctx := context.WithValue(req.Context(), ContextKeyUserID, "user-42")
	if rec := serve(h, req.WithContext(ctx)); rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", rec.Code)
	}

	audit := lastAuditLine(buf)
	if audit == "" {
		t.Fatalf("no admin-audit line logged:\n%s", buf.String())
	}
	for _, want := range []string{
		`"method":"DELETE"`,
		`"path":"/api/v1/yara/rules/abc"`,
		`"device_id":"dev-1"`,
		`"user_id":"user-42"`,
		`"orbnet_user_id":0`,
		`"remote_ip":"203.0.113.5"`,
		`"status":200`,
	} {
		if !strings.Contains(audit, want) {
			t.Errorf("audit line missing %s: %s", want, audit)
		}
	}
	if strings.Contains(buf.String(), strongToken) || strings.Contains(buf.String(), "device-api-key") {
		t.Fatalf("audit log must not contain credentials:\n%s", buf.String())
	}

	// A caller authenticated with an OrbNet account JWT carries its identity
	// in ContextKeyOrbNetUserID only; the audit line must still name it.
	buf.Reset()
	jwtReq := httptest.NewRequest(http.MethodPost, "/api/v1/admin/yara/reload", nil)
	jwtReq.RemoteAddr = "203.0.113.6:7777"
	jwtReq.Header.Set("X-Admin-Token", strongToken)
	jwtCtx := context.WithValue(jwtReq.Context(), ContextKeyAPIKey, "eyJ.orbnet.jwt")
	jwtCtx = context.WithValue(jwtCtx, ContextKeyOrbNetUserID, int64(4711))
	if rec := serve(h, jwtReq.WithContext(jwtCtx)); rec.Code != http.StatusOK {
		t.Fatalf("JWT caller: want 200, got %d", rec.Code)
	}
	audit = lastAuditLine(buf)
	for _, want := range []string{`"orbnet_user_id":4711`, `"user_id":""`, `"device_id":""`, `"remote_ip":"203.0.113.6"`} {
		if !strings.Contains(audit, want) {
			t.Errorf("JWT audit line missing %s: %s", want, audit)
		}
	}
	if strings.Contains(buf.String(), "eyJ.orbnet.jwt") {
		t.Fatal("audit log must not contain the bearer credential")
	}

	// A refused call is not an audit entry.
	buf.Reset()
	serve(h, adminReq(http.MethodDelete, "/api/v1/yara/rules/abc", "203.0.113.5:7777", "wrong", ""))
	if strings.Contains(buf.String(), `"component":"admin-audit"`) {
		t.Fatalf("a refused call must not produce an admin-audit line:\n%s", buf.String())
	}
}

// lastAuditLine returns the most recent admin-audit log line in buf, or "".
func lastAuditLine(buf *bytes.Buffer) string {
	var audit string
	for _, line := range strings.Split(strings.TrimSpace(buf.String()), "\n") {
		if strings.Contains(line, `"component":"admin-audit"`) {
			audit = line
		}
	}
	return audit
}

func TestPeerIP(t *testing.T) {
	tests := map[string]string{
		"192.0.2.1:1234":            "192.0.2.1",
		"192.0.2.1":                 "192.0.2.1", // RealIP leaves no port
		"[2001:db8::1]:443":         "2001:db8::1",
		"2001:db8::1":               "2001:db8::1",
		"198.51.100.7:0":            "198.51.100.7",
		"203.0.113.9:40000":         "203.0.113.9",
		"[::ffff:192.0.2.128]:8080": "::ffff:192.0.2.128",
	}
	for addr, want := range tests {
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		req.RemoteAddr = addr
		if got := peerIP(req); got != want {
			t.Errorf("peerIP(%q) = %q, want %q", addr, got, want)
		}
	}

	// With PeerAddress in the chain the recorded peer wins over a RemoteAddr
	// that RealIP has since rewritten from a header.
	var got string
	h := PeerAddress(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.RemoteAddr = "6.6.6.6" // what RealIP would do with X-Real-IP: 6.6.6.6
		got = peerIP(r)
	}))
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = "198.51.100.7:5555"
	serve(h, req)
	if got != "198.51.100.7" {
		t.Fatalf("peerIP behind PeerAddress = %q, want the recorded TCP peer 198.51.100.7", got)
	}
}

func TestLockoutAddress(t *testing.T) {
	const (
		// ingress is where the Container Apps ingress connects from (RFC 6598
		// shared space); public is a client that reached the app directly.
		ingress = "100.100.0.7:43210"
		public  = "198.51.100.7:5555"
	)
	xff := func(v ...string) map[string][]string { return map[string][]string{"X-Forwarded-For": v} }
	tests := []struct {
		name    string
		peer    string
		headers map[string][]string
		want    string
	}{
		// Behind the ingress: the client as the ingress saw it.
		{"ingress, no forwarding header: the peer", ingress, nil, "100.100.0.7"},
		{"ingress-appended hop alone", ingress, xff("203.0.113.9"), "203.0.113.9"},
		{"client-prepended fakes, ingress hop last", ingress, xff("10.0.0.1, 192.0.2.44 , 203.0.113.9"), "203.0.113.9"},
		{"several header lines: last hop of the last line", ingress, xff("10.0.0.1", "192.0.2.44, 203.0.113.9"), "203.0.113.9"},
		{"internal proxies after the ingress are skipped", ingress, xff("192.0.2.44, 203.0.113.9, 10.240.0.4, 100.100.0.9"), "203.0.113.9"},
		{"only infrastructure hops: the peer", ingress, xff("10.0.0.1, 172.16.0.2"), "100.100.0.7"},
		{"hop with a port", ingress, xff("10.0.0.1, 203.0.113.9:4321"), "203.0.113.9"},
		{"IPv6 hop", ingress, xff("10.0.0.1, 2001:db8::9"), "2001:db8::9"},
		{"IPv6 hop in brackets with port", ingress, xff("[2001:db8::9]:443"), "2001:db8::9"},
		{"IPv4-mapped hop is canonicalised", ingress, xff("::ffff:203.0.113.9"), "203.0.113.9"},
		{"X-Real-IP is ignored", ingress, map[string][]string{"X-Real-IP": {"6.6.6.6"}}, "100.100.0.7"},
		{"True-Client-IP is ignored", ingress, map[string][]string{"True-Client-IP": {"6.6.6.6"}}, "100.100.0.7"},
		{"X-Real-IP does not override the forwarded hop", ingress, map[string][]string{"X-Real-IP": {"6.6.6.6"}, "X-Forwarded-For": {"203.0.113.9"}}, "203.0.113.9"},
		{"garbage hop was not written by a proxy: the peer", ingress, xff("203.0.113.9, unknown"), "100.100.0.7"},
		{"garbage behind an internal hop: the peer", ingress, xff("203.0.113.9, unknown, 10.0.0.5"), "100.100.0.7"},
		{"empty header: the peer", ingress, xff(""), "100.100.0.7"},
		{"trailing comma: the peer", ingress, xff("203.0.113.9,"), "100.100.0.7"},
		{"loopback peer counts as infrastructure", "127.0.0.1:9000", xff("203.0.113.9"), "203.0.113.9"},
		{"private peer counts as infrastructure", "10.1.0.5:1", xff("203.0.113.9"), "203.0.113.9"},
		// Connected directly: nothing in front of us wrote the header, so
		// every hop in it is the client's own claim.
		{"public peer: X-Forwarded-For is ignored", public, xff("203.0.113.9"), "198.51.100.7"},
		{"public peer: X-Real-IP is ignored", public, map[string][]string{"X-Real-IP": {"6.6.6.6"}}, "198.51.100.7"},
		{"public IPv6 peer is canonicalised", "[2001:DB8::1]:443", xff("203.0.113.9"), "2001:db8::1"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/admin/x", nil)
			req.RemoteAddr = tc.peer
			for k, vs := range tc.headers {
				for _, v := range vs {
					req.Header.Add(k, v)
				}
			}
			if got := lockoutAddress(req); got != tc.want {
				t.Fatalf("lockoutAddress = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestLockoutKey(t *testing.T) {
	tests := map[string]string{
		"203.0.113.9":             adminLockoutKeyPrefix + "203.0.113.9",
		"2001:db8:1:2:3:4:5:6":    adminLockoutKeyPrefix + "2001:db8:1:2::/64",
		"2001:db8:1:2:ffff::1":    adminLockoutKeyPrefix + "2001:db8:1:2::/64",
		"2001:db8:1:3::1":         adminLockoutKeyPrefix + "2001:db8:1:3::/64",
		"100.100.0.7":             adminLockoutKeyPrefix + "100.100.0.7",
		"not-an-address (socket)": adminLockoutKeyPrefix + "not-an-address (socket)",
	}
	for addr, want := range tests {
		if got := lockoutKey(addr); got != want {
			t.Errorf("lockoutKey(%q) = %q, want %q", addr, got, want)
		}
	}
}

// TestAdminAuthLockoutCountsIPv6PerPrefix: an IPv6 client owns its whole /64,
// so walking through addresses in it must not reset the count.
func TestAdminAuthLockoutCountsIPv6PerPrefix(t *testing.T) {
	store := newMemLockout()
	buf := configureAdmin(t, strongToken, store)
	h, reached := adminHandler(t)

	for i := 1; i <= adminLockoutThreshold; i++ {
		addr := "[2001:db8:aa:bb::" + strconv.Itoa(i) + "]:443"
		rec := serve(h, adminReq(http.MethodPost, "/admin/x", addr, "wrong", ""))
		want := http.StatusForbidden
		if i == adminLockoutThreshold {
			want = http.StatusTooManyRequests
		}
		if rec.Code != want {
			t.Fatalf("failure %d from %s: want %d, got %d", i, addr, want, rec.Code)
		}
	}
	// Another address of the same /64 is locked with it...
	*reached = false
	if rec := serve(h, adminReq(http.MethodPost, "/admin/x", "[2001:db8:aa:bb:1234::99]:443", strongToken, "")); rec.Code != http.StatusTooManyRequests || *reached {
		t.Fatalf("same /64 with the correct token: want 429, got %d reached=%v", rec.Code, *reached)
	}
	// ...a neighbouring /64 is not.
	if rec := serve(h, adminReq(http.MethodPost, "/admin/x", "[2001:db8:aa:bc::1]:443", strongToken, "")); rec.Code != http.StatusOK || !*reached {
		t.Fatalf("neighbouring /64 with the correct token: want 200, got %d reached=%v", rec.Code, *reached)
	}
	// The log names the address that failed, the key groups it.
	if !strings.Contains(buf.String(), `"remote_ip":"2001:db8:aa:bb::5"`) {
		t.Fatalf("failure log should carry the full client address:\n%s", buf.String())
	}
}

// TestAdminAuthLockoutIgnoresSpoofableHeaders is the attack the per-address
// lockout must survive: rotating X-Real-IP (or the first X-Forwarded-For hop)
// must not spread one guesser's failures over fake addresses, and naming an
// operator's address in a header must not lock the operator out.
func TestAdminAuthLockoutIgnoresSpoofableHeaders(t *testing.T) {
	store := newMemLockout()
	configureAdmin(t, strongToken, store)
	h, reached := adminHandler(t)

	// Simulates the ingress appending the real peer to the client's header.
	viaIngress := func(token, realPeer, clientPrefix string, extra map[string]string) *http.Request {
		req := adminReq(http.MethodPost, "/admin/x", "10.1.0.5:1", token, "")
		xff := realPeer
		if clientPrefix != "" {
			xff = clientPrefix + ", " + realPeer
		}
		req.Header.Set("X-Forwarded-For", xff)
		for k, v := range extra {
			req.Header.Set(k, v)
		}
		return req
	}
	const attacker, operator = "203.0.113.9", "198.51.100.20"

	// Four wrong tokens, each with a fresh X-Real-IP and a fresh first XFF
	// hop; the fifth must still trip the lock on the real hop.
	for i := 1; i <= adminLockoutThreshold-1; i++ {
		req := viaIngress("wrong", attacker, "192.0.2."+strconv.Itoa(i), map[string]string{
			"X-Real-IP": "10.9." + strconv.Itoa(i) + ".1", "True-Client-IP": "10.8." + strconv.Itoa(i) + ".1",
		})
		if rec := serve(h, req); rec.Code != http.StatusForbidden {
			t.Fatalf("rotating headers, failure %d: want 403, got %d", i, rec.Code)
		}
	}
	req := viaIngress("wrong", attacker, "192.0.2.99", map[string]string{"X-Real-IP": "10.9.99.1"})
	if rec := serve(h, req); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("5th failure with rotated headers: want 429 on the real hop, got %d", rec.Code)
	}
	if n, _, _ := store.FailureCount(context.Background(), adminLockoutKeyPrefix+attacker); n != adminLockoutThreshold {
		t.Fatalf("all failures must land on the real hop %s, counted %d", attacker, n)
	}

	// Naming the operator's address in X-Real-IP, True-Client-IP or the first
	// X-Forwarded-For hop lands nothing on the operator's counter...
	for i := 0; i < adminLockoutThreshold+2; i++ {
		req := viaIngress("wrong", "203.0.113.10", operator, map[string]string{"X-Real-IP": operator, "True-Client-IP": operator})
		serve(h, req)
	}
	if n, _, _ := store.FailureCount(context.Background(), adminLockoutKeyPrefix+operator); n != 0 {
		t.Fatalf("spoofed headers must not touch the operator's counter, found %d", n)
	}
	// ...and the operator, arriving through the ingress, keeps working.
	*reached = false
	if rec := serve(h, viaIngress(strongToken, operator, "", nil)); rec.Code != http.StatusOK || !*reached {
		t.Fatalf("operator after spoofed attempts: want 200, got %d reached=%v", rec.Code, *reached)
	}
}

func TestAdminAuthStaleCounterWithoutExpiryIsCleared(t *testing.T) {
	store := newMemLockout()
	buf := configureAdmin(t, strongToken, store)
	h, reached := adminHandler(t)
	const ip = "192.0.2.77"

	// A counter past the threshold but with no expiry would otherwise lock
	// the address forever (the right token is refused while locked).
	store.seedWithoutExpiry(adminLockoutKeyPrefix+ip, adminLockoutThreshold+3)

	rec := serve(h, adminReq(http.MethodPost, "/admin/x", ip+":1", strongToken, ""))
	if rec.Code != http.StatusOK || !*reached {
		t.Fatalf("correct token against a damaged counter: want 200, got %d reached=%v", rec.Code, *reached)
	}
	if !strings.Contains(buf.String(), "had no expiry") {
		t.Fatalf("the repair must be logged, got:\n%s", buf.String())
	}
	if n, remaining, _ := store.FailureCount(context.Background(), adminLockoutKeyPrefix+ip); n != 0 || remaining != 0 {
		t.Fatalf("damaged counter must be cleared, still (%d, %s)", n, remaining)
	}

	// A live lock about to lapse is still a lock, with a 1-second floor on
	// Retry-After rather than a fresh full window.
	store.now = func() time.Time { return time.Now() }
	for i := 0; i < adminLockoutThreshold; i++ {
		serve(h, adminReq(http.MethodPost, "/admin/x", ip+":1", "wrong", ""))
	}
	store.now = func() time.Time { return time.Now().Add(adminLockoutWindow - 200*time.Millisecond) }
	rec = serve(h, adminReq(http.MethodPost, "/admin/x", ip+":1", strongToken, ""))
	if rec.Code != http.StatusTooManyRequests || rec.Header().Get("Retry-After") != "1" {
		t.Fatalf("lock in its last 200ms: want 429 with Retry-After 1, got %d %q", rec.Code, rec.Header().Get("Retry-After"))
	}
}
