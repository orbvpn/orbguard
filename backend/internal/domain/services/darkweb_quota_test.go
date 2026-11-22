package services_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/rs/zerolog"

	"orbguard-lab/internal/api"
	"orbguard-lab/internal/api/handlers"
	apimiddleware "orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/config"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

const (
	quotaIngressPeer   = "100.100.0.7:43210"
	quotaJWTSecret     = "quota-test-orbnet-secret-0123456789abcdef"
	quotaServiceSecret = "quota-test-service-secret-0123456789abcdef"
	deviceKeyTTL       = 365 * 24 * time.Hour
)

// quotaTokens resolves "new-<n>" as a key issued now and "old-<n>" as one
// issued two days ago, each with its own device id.
type quotaTokens struct{}

func (quotaTokens) GetJSON(_ context.Context, key string, dest any) error {
	if session, isSession := strings.CutPrefix(key, "auth:token:"); isSession {
		if !strings.HasPrefix(session, "session-") {
			return errors.New("not found")
		}
		raw, err := json.Marshal(apimiddleware.TokenClaims{DeviceID: "dev-" + session, ExpiresAt: time.Now().Add(time.Hour)})
		if err != nil {
			return err
		}
		return json.Unmarshal(raw, dest)
	}
	token, isDeviceKey := strings.CutPrefix(key, "auth:apikey:")
	if !isDeviceKey {
		return errors.New("not found")
	}
	expires := time.Now().Add(deviceKeyTTL)
	switch {
	case strings.HasPrefix(token, "new-"):
	case strings.HasPrefix(token, "old-"):
		expires = expires.Add(-48 * time.Hour)
	default:
		return errors.New("not found")
	}
	claims := map[string]any{"device_id": "dev-" + token, "expires_at": expires}
	// "old-net<n>-..." is an aged key that was issued on network n.
	if rest, stamped := strings.CutPrefix(token, "old-net"); stamped {
		network, _, _ := strings.Cut(rest, "-")
		claims["issued_from"] = "issuer-" + network
	}
	raw, err := json.Marshal(claims)
	if err != nil {
		return err
	}
	return json.Unmarshal(raw, dest)
}

// memQuota has the semantics of the Redis script.
type memQuota struct {
	mu     sync.Mutex
	counts map[string]int64
	values map[string]string
	ttls   map[string]time.Duration
	err    error
}

func (q *memQuota) ReserveQuota(_ context.Context, keys []string, limits []int64, _ time.Duration) (int, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.err != nil {
		return 0, q.err
	}
	for i, key := range keys {
		if q.counts[key] >= limits[i] {
			return i + 1, nil
		}
	}
	for _, key := range keys {
		q.counts[key]++
	}
	return 0, nil
}

func (q *memQuota) ReleaseQuota(_ context.Context, keys []string) error {
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.err != nil {
		return q.err
	}
	for _, key := range keys {
		if q.counts[key] > 0 {
			q.counts[key]--
		}
	}
	return nil
}

func (q *memQuota) GetJSON(_ context.Context, key string, dest any) error {
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.err != nil {
		return q.err
	}
	raw, ok := q.values[key]
	if !ok {
		return errors.New("not found")
	}
	return json.Unmarshal([]byte(raw), dest)
}

func (q *memQuota) SetJSON(_ context.Context, key string, value any, ttl time.Duration) error {
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.err != nil {
		return q.err
	}
	raw, err := json.Marshal(value)
	if err != nil {
		return err
	}
	q.values[key] = string(raw)
	q.ttls[key] = ttl
	return nil
}

// fakeHIBP counts calls and answers like the provider: 404 means not breached.
type fakeHIBP struct {
	calls  atomic.Int64
	status int
	body   string
	err    error
	paths  sync.Map
	// onCall runs at the start of every request.
	onCall func()
}

func (f *fakeHIBP) RoundTrip(r *http.Request) (*http.Response, error) {
	f.calls.Add(1)
	f.paths.Store(r.URL.Path, true)
	if f.onCall != nil {
		f.onCall()
	}
	if f.err != nil {
		return nil, f.err
	}
	return &http.Response{
		StatusCode: f.status,
		Body:       io.NopCloser(strings.NewReader(f.body)),
		Header:     http.Header{},
		Request:    r,
	}, nil
}

type quotaRig struct {
	h     http.Handler
	store *memQuota
	hibp  *fakeHIBP
	logs  *bytes.Buffer
}

func newQuotaRig(t *testing.T, perDay int64, repo *repository.DarkWebRepository) *quotaRig {
	t.Helper()
	return newProviderRig(t, perDay, repo, nil, nil)
}

// newProviderRig also configures LeakCheck and Intelligence X when their
// transports are given.
func newProviderRig(t *testing.T, perDay int64, repo *repository.DarkWebRepository, leak, intel http.RoundTripper) *quotaRig {
	t.Helper()
	logs := &bytes.Buffer{}
	log := &logger.Logger{Logger: zerolog.New(logs)}
	apimiddleware.ConfigureAuth(quotaTokens{}, "test", log)
	t.Cleanup(func() {
		apimiddleware.ConfigureAuth(nil, "", nil)
		apimiddleware.ConfigureOrbNetJWT("")
	})
	fake := &fakeHIBP{status: http.StatusNotFound}
	client := services.NewHIBPClient(services.HIBPConfig{APIKey: "test-key"}, log)
	client.SetTransportForTest(fake)
	var leakCheck *services.LeakCheckClient
	if leak != nil {
		leakCheck = services.NewLeakCheckClient(services.LeakCheckClientConfig{APIKey: "test-key"}, log)
		leakCheck.SetTransportForTest(leak)
	}
	var intelX *services.IntelXClient
	if intel != nil {
		intelX = services.NewIntelXClient(services.IntelXClientConfig{APIKey: "test-key"}, log)
		intelX.SetTransportForTest(intel)
	}
	monitor := services.NewDarkWebMonitor(client, leakCheck, intelX, repo, nil, log)
	store := &memQuota{counts: map[string]int64{}, values: map[string]string{}, ttls: map[string]time.Duration{}}
	monitor.SetPaidLookupsForTest(store, perDay)
	cfg := config.Config{}
	cfg.JWT.OrbNetAccessSecret = quotaJWTSecret
	cfg.JWT.Secret = quotaServiceSecret
	h := &handlers.Handlers{DarkWeb: handlers.NewDarkWebHandler(monitor, log)}
	return &quotaRig{h: api.NewRouter(cfg, h, nil, log).Setup(), store: store, hibp: fake, logs: logs}
}

func (rig *quotaRig) post(path, bearer, clientIP, forgedHop, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+bearer)
	req.RemoteAddr = quotaIngressPeer
	hops := clientIP
	if forgedHop != "" {
		hops = forgedHop + ", " + clientIP
	}
	req.Header.Set("X-Forwarded-For", hops)
	rec := httptest.NewRecorder()
	rig.h.ServeHTTP(rec, req)
	return rec
}

func (rig *quotaRig) checkEmail(bearer, clientIP, forgedHop string, n int) *httptest.ResponseRecorder {
	return rig.post("/api/v1/darkweb/check/email", bearer, clientIP, forgedHop,
		fmt.Sprintf(`{"email":"user%d@example.com"}`, n))
}

func orbnetJWT(t *testing.T, userID int64, subscribed bool) string {
	t.Helper()
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, apimiddleware.OrbNetClaims{
		UserID:            userID,
		SubscriptionValid: subscribed,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    "orbnet",
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
		},
	})
	signed, err := token.SignedString([]byte(quotaJWTSecret))
	if err != nil {
		t.Fatal(err)
	}
	return signed
}

func TestOneDeviceKeyStopsAtItsDailyLimit(t *testing.T) {
	rig := newQuotaRig(t, 1000, nil)
	for i := 0; i < 8; i++ {
		if rec := rig.checkEmail("old-1", "198.51.100.1", "", i); rec.Code != http.StatusOK {
			t.Fatalf("lookup %d: want 200, got %d: %s", i, rec.Code, rec.Body)
		}
	}
	rec := rig.checkEmail("old-1", "198.51.100.1", "", 11)
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("over the device limit: want 429, got %d", rec.Code)
	}
	if rec.Header().Get("Retry-After") == "" {
		t.Fatal("429 must carry Retry-After")
	}
	if got := rig.hibp.calls.Load(); got != 8 {
		t.Fatalf("upstream calls: want 8, got %d", got)
	}
}

func TestManyFreeKeysWithForgedHopsStopAtTheAddressLimit(t *testing.T) {
	rig := newQuotaRig(t, 1000, nil)
	for i := 0; i < 80; i++ {
		rig.checkEmail(fmt.Sprintf("new-%d", i), "198.51.100.2", fmt.Sprintf("203.0.113.%d", i), i)
	}
	if got := rig.hibp.calls.Load(); got != 5 {
		t.Fatalf("one address with free keys and forged hops: want 5 upstream calls, got %d", got)
	}
}

func TestIPv6ClientCannotRotateInsideItsSlash64(t *testing.T) {
	rig := newQuotaRig(t, 1000, nil)
	for i := 0; i < 80; i++ {
		rig.checkEmail(fmt.Sprintf("new-%d", i), fmt.Sprintf("2001:db8:1:2::%x", i+1), "", i)
	}
	if got := rig.hibp.calls.Load(); got != 5 {
		t.Fatalf("one /64: want 5 upstream calls, got %d", got)
	}
}

func TestFreshKeysCannotSpendTheReserveOfRealUsers(t *testing.T) {
	rig := newQuotaRig(t, 100, nil)
	// A stranger with fresh keys on many addresses stops at the new-key share.
	for i := 0; i < 120; i++ {
		rig.checkEmail(fmt.Sprintf("new-%d", i), fmt.Sprintf("198.51.100.%d", i+1), "", i)
	}
	if got := rig.hibp.calls.Load(); got != 30 {
		t.Fatalf("fresh keys: want 30 upstream calls of 100, got %d", got)
	}
	if rec := rig.checkEmail("old-1", "203.0.113.1", "", 500); rec.Code != http.StatusOK {
		t.Fatalf("an established device after the flood: want 200, got %d", rec.Code)
	}
	if rec := rig.checkEmail(paidClaimsJWT(t, 7, true, false, "STRIPE"), "203.0.113.2", "", 501); rec.Code != http.StatusOK {
		t.Fatalf("a paying account after the flood: want 200, got %d", rec.Code)
	}
}

// A session token expires soon after it is issued, so its expiry must not be
// read as the age of a device key.
func TestSessionTokenDoesNotCountAsAnAgedKey(t *testing.T) {
	rig := newQuotaRig(t, 100, nil)
	for i := 0; i < 40; i++ {
		rig.checkEmail(fmt.Sprintf("new-%d", i), fmt.Sprintf("198.51.100.%d", i+1), "", i)
	}
	if rec := rig.checkEmail("session-1", "203.0.113.5", "", 800); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("a session token after the new-key share is spent: want 429, got %d", rec.Code)
	}
}

func TestAgedKeysLeaveTheLastShareToPayingAccounts(t *testing.T) {
	rig := newQuotaRig(t, 100, nil)
	for i := 0; i < 120; i++ {
		rig.checkEmail(fmt.Sprintf("old-%d", i), fmt.Sprintf("198.51.100.%d", i+1), "", i)
	}
	if got := rig.hibp.calls.Load(); got != 80 {
		t.Fatalf("aged keys: want 80 upstream calls of 100, got %d", got)
	}
	if rec := rig.checkEmail(orbnetJWT(t, 8, false), "203.0.113.3", "", 600); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("a free account must not reach the paying share: got %d", rec.Code)
	}
	if rec := rig.checkEmail(paidClaimsJWT(t, 9, true, false, "STRIPE"), "203.0.113.4", "", 601); rec.Code != http.StatusOK {
		t.Fatalf("a paying account: want 200, got %d", rec.Code)
	}
}

func TestBudgetStoreDownMakesNoPaidCall(t *testing.T) {
	rig := newQuotaRig(t, 1000, nil)
	rig.store.err = errors.New("redis down")
	rec := rig.checkEmail("new-1", "198.51.100.3", "", 1)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("store down: want 503, got %d", rec.Code)
	}
	if got := rig.hibp.calls.Load(); got != 0 {
		t.Fatalf("store down: %d paid calls were made", got)
	}
}

// With a repository that has no pool, reaching the store would panic into a
// 500, so a 429 or 503 here also proves nothing was stored.
func TestMonitorRefusalStoresNothing(t *testing.T) {
	rig := newQuotaRig(t, 1000, &repository.DarkWebRepository{})
	body := `{"asset_type":"email","value":"asset@example.com"}`

	rig.store.err = errors.New("redis down")
	if rec := rig.post("/api/v1/darkweb/monitor", "new-1", "198.51.100.4", "", body); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("budget store down: want 503, got %d", rec.Code)
	}
	rig.store.err = nil

	for i := 0; i < 30; i++ {
		rig.checkEmail(fmt.Sprintf("new-x%d", i), "198.51.100.5", "", 700+i)
	}
	if rec := rig.post("/api/v1/darkweb/monitor", "new-y", "198.51.100.5", "", body); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("over the address limit: want 429, got %d", rec.Code)
	}
}

// A check that failed must not be stored: the app shows a stored asset with no
// breaches as "Safe".
func TestMonitorDoesNotStoreAnEmailItCouldNotCheck(t *testing.T) {
	rig := newQuotaRig(t, 1000, &repository.DarkWebRepository{})
	rig.hibp.err = errors.New("provider down")
	rec := rig.post("/api/v1/darkweb/monitor", "new-1", "198.51.100.6", "", `{"asset_type":"email","value":"asset@example.com"}`)
	if rec.Code == http.StatusCreated {
		t.Fatal("an email that could not be checked was reported as monitored")
	}
	if strings.Contains(rec.Body.String(), "runtime error") {
		t.Fatalf("reached the store: %s", rec.Body)
	}
}

func TestReserveQuotaOnRealRedisIsAllOrNothing(t *testing.T) {
	addr := os.Getenv("ORBGUARD_TEST_REDIS_ADDR")
	if addr == "" {
		t.Skip("ORBGUARD_TEST_REDIS_ADDR not set; skipping Redis-backed test")
	}
	host, port := splitTestRedisAddr(t, addr)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	redisCache, err := cache.NewRedis(ctx, config.RedisConfig{
		Host: host, Port: port, KeyPrefix: fmt.Sprintf("orbguard-test:%d:", time.Now().UnixNano()),
	}, &logger.Logger{Logger: zerolog.Nop()})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = redisCache.Close() })

	var granted atomic.Int64
	var wg sync.WaitGroup
	for i := 0; i < 300; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			exhausted, err := redisCache.ReserveQuota(ctx,
				[]string{"quota:{d}:id:" + fmt.Sprint(i%3), "quota:{d}:total"}, []int64{1000, 50}, time.Minute)
			if err == nil && exhausted == 0 {
				granted.Add(1)
			}
		}(i)
	}
	wg.Wait()
	if got := granted.Load(); got != 50 {
		t.Fatalf("300 concurrent reservations under a limit of 50: granted %d", got)
	}

	// A refusal on the second key must leave the first key untouched.
	exhausted, err := redisCache.ReserveQuota(ctx, []string{"quota:{d}:other", "quota:{d}:total"}, []int64{5, 50}, time.Minute)
	if err != nil || exhausted != 2 {
		t.Fatalf("want refusal on key 2, got %d (err %v)", exhausted, err)
	}
	if n, err := redisCache.Exists(ctx, "quota:{d}:other"); err != nil || n != 0 {
		t.Fatalf("a refused reservation changed another counter: exists=%d err=%v", n, err)
	}
	ttl, err := redisCache.TTL(ctx, "quota:{d}:total")
	if err != nil || ttl <= 0 || ttl > time.Minute {
		t.Fatalf("counter TTL: %v (err %v)", ttl, err)
	}
}

const rangePrefix = "5BAA6"

func rangeSuffix(c byte) string { return strings.Repeat(string(c), 35) }

func TestPasswordRangeTakesOnlyAPrefixAndKeepsItOutOfLogs(t *testing.T) {
	rig := newQuotaRig(t, 1000, nil)
	rig.hibp.status = http.StatusOK
	rig.hibp.body = rangeSuffix('A') + ":3\r\n" + rangeSuffix('B') + ":0\r\n"

	rec := rig.post("/api/v1/darkweb/password/range", "new-1", "198.51.100.7", "", `{"prefix":"`+strings.ToLower(rangePrefix)+`"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	var out struct {
		Suffixes []struct {
			Suffix string `json:"suffix"`
			Count  int    `json:"count"`
		} `json:"suffixes"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if len(out.Suffixes) != 2 || out.Suffixes[0].Suffix != rangeSuffix('A') || out.Suffixes[0].Count != 3 || out.Suffixes[1].Count != 0 {
		t.Fatalf("suffixes: %+v", out.Suffixes)
	}
	if rec.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("the answer must not be cached")
	}
	if _, ok := rig.hibp.paths.Load("/range/" + rangePrefix); !ok {
		t.Fatal("upstream was not asked for exactly the prefix")
	}
	if logs := strings.ToUpper(rig.logs.String()); strings.Contains(logs, rangePrefix) {
		t.Fatalf("the prefix reached the log: %s", rig.logs)
	}
}

func TestPasswordRangeRefusesAnythingButAPrefix(t *testing.T) {
	rig := newQuotaRig(t, 1000, nil)
	rig.hibp.status = http.StatusOK
	rig.hibp.body = rangeSuffix('A') + ":1\r\n"
	full := "5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8"
	for _, body := range []string{
		`{}`, `{"prefix":""}`, `{"prefix":"5BAA"}`, `{"prefix":"5BAA61"}`, `{"prefix":"ZZZZZ"}`,
		`{"prefix":"` + full + `"}`, `{"password":"hunter2"}`, `not json`,
	} {
		if rec := rig.post("/api/v1/darkweb/password/range", "new-1", "198.51.100.8", "", body); rec.Code != http.StatusBadRequest {
			t.Errorf("%s: want 400, got %d", body, rec.Code)
		}
	}
	if got := rig.hibp.calls.Load(); got != 0 {
		t.Fatalf("refused bodies made %d upstream calls", got)
	}
}

func TestPasswordRangeFailureIsNeverACleanAnswer(t *testing.T) {
	cases := map[string]func(*fakeHIBP){
		"transport error": func(f *fakeHIBP) {
			f.err = fmt.Errorf(`Get "https://api.example/range/%s": connection refused`, rangePrefix)
		},
		"upstream 500": func(f *fakeHIBP) { f.status = http.StatusInternalServerError },
		"empty body":   func(f *fakeHIBP) { f.status = http.StatusOK; f.body = "" },
		"malformed":    func(f *fakeHIBP) { f.status = http.StatusOK; f.body = "not a range line\r\n" },
	}
	for name, arrange := range cases {
		t.Run(name, func(t *testing.T) {
			rig := newQuotaRig(t, 1000, nil)
			arrange(rig.hibp)
			rec := rig.post("/api/v1/darkweb/password/range", "new-1", "198.51.100.9", "", `{"prefix":"`+rangePrefix+`"}`)
			if rec.Code != http.StatusBadGateway {
				t.Fatalf("want 502, got %d: %s", rec.Code, rec.Body)
			}
			if strings.Contains(rec.Body.String(), "suffixes") {
				t.Fatalf("a failure carried suffixes: %s", rec.Body)
			}
			if strings.Contains(strings.ToUpper(rig.logs.String()), rangePrefix) {
				t.Fatalf("the prefix reached the log: %s", rig.logs)
			}
		})
	}
}

func splitTestRedisAddr(t *testing.T, addr string) (string, int) {
	t.Helper()
	host, portStr, ok := strings.Cut(addr, ":")
	if !ok {
		t.Fatalf("ORBGUARD_TEST_REDIS_ADDR must be host:port, got %q", addr)
	}
	var port int
	if _, err := fmt.Sscanf(portStr, "%d", &port); err != nil {
		t.Fatalf("ORBGUARD_TEST_REDIS_ADDR port: %v", err)
	}
	return host, port
}
