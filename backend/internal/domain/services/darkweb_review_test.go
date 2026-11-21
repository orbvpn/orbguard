package services_test

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/rs/zerolog"

	"orbguard-lab/internal/api"
	"orbguard-lab/internal/api/handlers"
	apimiddleware "orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/config"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/domain/services/ai"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

const reviewEmail = "person404@example.com"

// statusTransport answers every request with one status and body, or an error.
type statusTransport struct {
	calls  atomic.Int64
	status int
	body   string
	err    error
}

func (f *statusTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	f.calls.Add(1)
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

// intelXTransport plays a search whose result endpoint answers resultBody.
type intelXTransport struct {
	resultBody string
}

func (f *intelXTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	body := `{}`
	switch {
	case r.Method == http.MethodPost:
		body = `{"id":"search-1","status":0}`
	case strings.HasSuffix(r.URL.Path, "/result"):
		body = f.resultBody
	}
	return &http.Response{
		StatusCode: http.StatusOK,
		Body:       io.NopCloser(strings.NewReader(body)),
		Header:     http.Header{},
		Request:    r,
	}, nil
}

func (rig *quotaRig) checkOne(bearer, clientIP, email string) *httptest.ResponseRecorder {
	return rig.post("/api/v1/darkweb/check/email", bearer, clientIP, "", `{"email":"`+email+`"}`)
}

// A subscription_valid token does not prove payment: free plans carry it too.
func TestAccountTokensGetTheDeviceBudgetNotTheServiceBudget(t *testing.T) {
	rig := newQuotaRig(t, 500, nil)
	for account := int64(1); account <= 10; account++ {
		token := orbnetJWT(t, account, true)
		for i := 0; i < 20; i++ {
			rig.checkEmail(token, "198.51.100.50", "", int(account)*1000+i)
		}
	}
	if got := rig.hibp.calls.Load(); got > 8 {
		t.Fatalf("accounts on one address made %d paid lookups", got)
	}
	if rec := rig.checkEmail("old-bystander", "203.0.113.10", "", 999); rec.Code != http.StatusOK {
		t.Fatalf("a device after the accounts: want 200, got %d", rec.Code)
	}
}

func TestServiceCredentialReachesTheWholeBudget(t *testing.T) {
	rig := newQuotaRig(t, 10, nil)
	for i := 0; i < 8; i++ {
		rig.checkEmail(fmt.Sprintf("old-%d", i), fmt.Sprintf("198.51.100.%d", i+1), "", i)
	}
	if rec := rig.checkEmail(quotaServiceSecret, "203.0.113.11", "", 100); rec.Code != http.StatusOK {
		t.Fatalf("service credential above the device share: want 200, got %d", rec.Code)
	}
}

func TestOldPasswordRouteAlwaysRefuses(t *testing.T) {
	rig := newQuotaRig(t, 500, nil)
	const password = "marker-password-value"
	sum := sha1.Sum([]byte(password))
	full := strings.ToUpper(hex.EncodeToString(sum[:]))
	rig.hibp.status = http.StatusOK
	rig.hibp.body = full[5:] + ":7\r\n"
	for _, body := range []string{
		`{"password":"` + password + `"}`,
		`{"password_hash_prefix":"` + full[:5] + `"}`,
		`{}`,
		`not json`,
	} {
		rec := rig.post("/api/v1/darkweb/check/password", "old-1", "198.51.100.60", "", body)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s: want 400, got %d: %s", body, rec.Code, rec.Body)
		}
	}
	if got := rig.hibp.calls.Load(); got != 0 {
		t.Fatalf("the refused route made %d upstream calls", got)
	}
	if logs := strings.ToUpper(rig.logs.String()); strings.Contains(logs, full[:5]) {
		t.Fatal("the hash prefix reached the log")
	}
}

func TestNoProviderFailurePutsTheEmailInALog(t *testing.T) {
	const email = "marker.person@example.com"
	down := func() *statusTransport { return &statusTransport{err: errors.New("dial tcp: i/o timeout")} }
	rig := newProviderRig(t, 500, &repository.DarkWebRepository{}, down(), down())
	rig.hibp.err = errors.New("dial tcp: i/o timeout")

	rig.post("/api/v1/darkweb/check/email", "old-2", "198.51.100.62", "", `{"email":"`+email+`"}`)
	rig.post("/api/v1/darkweb/monitor", "old-3", "198.51.100.63", "", `{"asset_type":"email","value":"`+email+`"}`)

	logs := rig.logs.String()
	if logs == "" {
		t.Fatal("expected failure log lines")
	}
	for _, needle := range []string{email, "marker.person", "marker.person%40"} {
		if strings.Contains(logs, needle) {
			t.Fatalf("%q reached the log", needle)
		}
	}
}

func TestProviderFailureNeverReadsAsNoBreaches(t *testing.T) {
	cases := map[string]func(t *testing.T) *quotaRig{
		"hibp unreachable with 404 in the address": func(t *testing.T) *quotaRig {
			rig := newQuotaRig(t, 500, nil)
			rig.hibp.err = errors.New("dial tcp: i/o timeout")
			return rig
		},
		"hibp 500 with 404 in the body": func(t *testing.T) *quotaRig {
			rig := newQuotaRig(t, 500, nil)
			rig.hibp.status = http.StatusInternalServerError
			rig.hibp.body = "upstream 404"
			return rig
		},
		"hibp failed, leakcheck found nothing": func(t *testing.T) *quotaRig {
			clean := &statusTransport{status: http.StatusOK, body: `{"success":true,"found":0,"result":[]}`}
			rig := newProviderRig(t, 500, nil, clean, nil)
			rig.hibp.err = errors.New("dial tcp: i/o timeout")
			return rig
		},
		"leakcheck 200 with an error envelope": func(t *testing.T) *quotaRig {
			leak := &statusTransport{status: http.StatusOK, body: `{"success":false,"error":"Not found"}`}
			return newProviderRig(t, 500, nil, leak, nil)
		},
		"leakcheck 404 that is not its envelope": func(t *testing.T) *quotaRig {
			leak := &statusTransport{status: http.StatusNotFound, body: `<html>gateway</html>`}
			return newProviderRig(t, 500, nil, leak, nil)
		},
		"intelx lost the search": func(t *testing.T) *quotaRig {
			intel := &intelXTransport{resultBody: `{"records":[],"status":2}`}
			return newProviderRig(t, 500, nil, nil, intel)
		},
	}
	for name, arrange := range cases {
		t.Run(name, func(t *testing.T) {
			rig := arrange(t)
			rec := rig.checkOne("old-4", "198.51.100.65", reviewEmail)
			if rec.Code == http.StatusOK {
				t.Fatalf("an unchecked address was answered as checked: %s", rec.Body)
			}
		})
	}
}

func TestRealNotFoundStillReadsAsNoBreaches(t *testing.T) {
	leak := &statusTransport{status: http.StatusNotFound, body: `{"success":false,"error":"Not found"}`}
	rig := newProviderRig(t, 500, nil, leak, &intelXTransport{resultBody: `{"records":[],"status":1}`})
	rec := rig.checkOne("old-5", "198.51.100.66", "clean@example.com")
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	var body struct {
		IsBreached bool `json:"is_breached"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.IsBreached {
		t.Fatal("a clean address was reported as breached")
	}
}

func TestBreachFoundIsShownEvenIfAnotherProviderFailed(t *testing.T) {
	found := &statusTransport{status: http.StatusOK, body: `{"success":true,"found":1,"result":[{"source":{"name":"ExampleLeak","breach_date":"2020-01"},"fields":["email"]}]}`}
	rig := newProviderRig(t, 500, nil, found, nil)
	rig.hibp.err = errors.New("dial tcp: i/o timeout")
	rec := rig.checkOne("old-6", "198.51.100.67", "found@example.com")
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "ExampleLeak") {
		t.Fatalf("want the breach from the working provider, got %d: %s", rec.Code, rec.Body)
	}
}

// The released app resends a failed POST up to three times.
func TestReleasedAppRetriesCostOneCallAndNoBudget(t *testing.T) {
	rig := newQuotaRig(t, 500, nil)
	rig.hibp.status = http.StatusBadGateway
	for tap := 0; tap < 3; tap++ {
		for attempt := 0; attempt < 4; attempt++ {
			rig.checkEmail("old-retry", "198.51.100.64", "", tap)
		}
	}
	if got := rig.hibp.calls.Load(); got != 3 {
		t.Fatalf("3 taps with retries: want 3 provider calls, got %d", got)
	}
	for key, count := range rig.store.counts {
		if strings.Contains(key, ":id:") && !strings.Contains(key, ":refund:") && count != 0 {
			t.Fatalf("a provider failure consumed budget on %s: %d", key, count)
		}
	}
	rig.hibp.status = http.StatusNotFound
	if rec := rig.checkEmail("old-retry", "198.51.100.64", "", 50); rec.Code != http.StatusOK {
		t.Fatalf("after recovery: want 200, got %d", rec.Code)
	}
}

func TestSameCallerAndEmailReuseTheFirstAnswer(t *testing.T) {
	rig := newQuotaRig(t, 500, nil)
	for i := 0; i < 4; i++ {
		if rec := rig.checkOne("old-memo", "198.51.100.68", "same@example.com"); rec.Code != http.StatusOK {
			t.Fatalf("attempt %d: %d", i, rec.Code)
		}
	}
	if got := rig.hibp.calls.Load(); got != 1 {
		t.Fatalf("same caller, same email: want 1 provider call, got %d", got)
	}
	if rec := rig.checkOne("old-memo-2", "198.51.100.68", "same@example.com"); rec.Code != http.StatusOK {
		t.Fatalf("other caller: %d", rec.Code)
	}
	if got := rig.hibp.calls.Load(); got != 2 {
		t.Fatalf("another caller must get its own lookup: %d calls", got)
	}
	found := false
	for key, ttl := range rig.store.ttls {
		if strings.Contains(key, ":memo:") {
			found = true
			if ttl.Minutes() != 10 {
				t.Fatalf("memo lifetime: %v", ttl)
			}
		}
		if strings.Contains(key, "same@example.com") || strings.Contains(rig.store.values[key], "same@example.com") {
			t.Fatalf("the clear email reached the store under %s", key)
		}
	}
	if !found {
		t.Fatal("no remembered answer in the store")
	}
}

func TestRefundsAreBoundedSoFailuresCannotBuyFreeCalls(t *testing.T) {
	rig := newQuotaRig(t, 500, nil)
	rig.hibp.status = http.StatusBadGateway
	for i := 0; i < 40; i++ {
		rig.checkEmail("old-failing", "198.51.100.69", "", i)
	}
	if got := rig.hibp.calls.Load(); got > 13 {
		t.Fatalf("one caller with failing lookups reached %d provider calls", got)
	}
}

// One client must not lock out another user behind the same VPN exit.
func TestAgedKeysOnASharedExitAreLimitedPerKey(t *testing.T) {
	rig := newQuotaRig(t, 500, nil)
	const exit = "198.51.100.70"
	for key := 0; key < 12; key++ {
		for i := 0; i < 10; i++ {
			rig.checkEmail(fmt.Sprintf("old-abuser-%d", key), exit, "", key*100+i)
		}
	}
	if rec := rig.checkEmail("old-innocent", exit, "", 9000); rec.Code != http.StatusOK {
		t.Fatalf("another user on the same exit: want 200, got %d", rec.Code)
	}
}

func TestNewKeysFromOneAddressStopAtALowNumber(t *testing.T) {
	rig := newQuotaRig(t, 500, nil)
	for i := 0; i < 20; i++ {
		rig.checkEmail(fmt.Sprintf("new-%d", i), "198.51.100.71", "", i)
	}
	if got := rig.hibp.calls.Load(); got != 5 {
		t.Fatalf("new keys on one address: want 5 lookups, got %d", got)
	}
	if rec := rig.checkEmail("old-on-same-exit", "198.51.100.71", "", 99); rec.Code != http.StatusOK {
		t.Fatalf("an older key on that address: want 200, got %d", rec.Code)
	}
}

// Keys issued on one network and aged a day spend from one small allowance,
// wherever they spend from.
func TestKeysIssuedOnOneNetworkShareOneAllowance(t *testing.T) {
	rig := newQuotaRig(t, 500, nil)
	for key := 0; key < 30; key++ {
		for i := 0; i < 8; i++ {
			rig.checkEmail(fmt.Sprintf("old-net7-%d", key), fmt.Sprintf("198.51.%d.9", key), "", key*100+i)
		}
	}
	if got := rig.hibp.calls.Load(); got != 20 {
		t.Fatalf("keys issued on one network: want 20 lookups, got %d", got)
	}
	if rec := rig.checkEmail("old-net8-1", "203.0.113.40", "", 7); rec.Code != http.StatusOK {
		t.Fatalf("a key issued elsewhere: want 200, got %d", rec.Code)
	}
}

func sweepAssets(n int) []models.MonitoredAsset {
	assets := make([]models.MonitoredAsset, n)
	for i := range assets {
		assets[i] = models.MonitoredAsset{
			ID:         uuid.New(),
			AssetType:  models.BreachTypeEmail,
			AssetValue: fmt.Sprintf("sweep%d@example.com", i),
		}
	}
	return assets
}

func sweepRig(t *testing.T, perDay int64) (*services.DarkWebMonitor, *fakeHIBP, *memQuota) {
	t.Helper()
	log := &logger.Logger{Logger: zerolog.Nop()}
	fake := &fakeHIBP{status: http.StatusNotFound}
	client := services.NewHIBPClient(services.HIBPConfig{APIKey: "test-key"}, log)
	client.SetTransportForTest(fake)
	monitor := services.NewDarkWebMonitor(client, nil, nil, nil, nil, log)
	store := &memQuota{counts: map[string]int64{}, values: map[string]string{}, ttls: map[string]time.Duration{}}
	monitor.SetPaidLookupsForTest(store, perDay)
	return monitor, fake, store
}

func TestRefreshSweepSpendsFromTheDailyBudget(t *testing.T) {
	monitor, fake, _ := sweepRig(t, 100)
	stored, err := monitor.SweepAssetsForTest(context.Background(), sweepAssets(90))
	if !errors.Is(err, services.ErrPaidLookupLimited) {
		t.Fatalf("want the budget to stop the sweep, got %v", err)
	}
	if got := fake.calls.Load(); got != 50 || stored != 50 {
		t.Fatalf("sweep ceiling is half the budget: %d calls, %d stored", got, stored)
	}
}

func TestRefreshSweepStopsDuringAProviderOutage(t *testing.T) {
	monitor, fake, store := sweepRig(t, 100)
	fake.status = http.StatusBadGateway
	stored, err := monitor.SweepAssetsForTest(context.Background(), sweepAssets(40))
	if !errors.Is(err, services.ErrBreachProvidersFailed) {
		t.Fatalf("want the outage to stop the sweep, got %v", err)
	}
	if got := fake.calls.Load(); got != 3 || stored != 0 {
		t.Fatalf("outage: %d provider calls, %d stored", got, stored)
	}
	for key, count := range store.counts {
		if strings.HasSuffix(key, ":total") && !strings.Contains(key, ":refund:") && count != 0 {
			t.Fatalf("failed sweep lookups kept budget on %s: %d", key, count)
		}
	}
}

func reviewRedis(t *testing.T) *cache.RedisCache {
	t.Helper()
	redisCache, _ := reviewRedisScoped(t)
	return redisCache
}

// reviewRedisScoped also returns the key prefix of this test's connection, so
// a scan sees only what this test wrote.
func reviewRedisScoped(t *testing.T) (*cache.RedisCache, string) {
	t.Helper()
	addr := os.Getenv("ORBGUARD_TEST_REDIS_ADDR")
	if addr == "" {
		t.Skip("ORBGUARD_TEST_REDIS_ADDR not set; skipping Redis-backed test")
	}
	host, port := splitTestRedisAddr(t, addr)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	prefix := fmt.Sprintf("orbguard-test:%d:", time.Now().UnixNano())
	redisCache, err := cache.NewRedis(ctx, config.RedisConfig{
		Host: host, Port: port, KeyPrefix: prefix,
	}, &logger.Logger{Logger: zerolog.Nop()})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = redisCache.Close() })
	return redisCache, prefix
}

func TestReleaseQuotaGivesBackOneUnitAndNeverGoesNegative(t *testing.T) {
	redisCache := reviewRedis(t)
	ctx := context.Background()
	keys := []string{"release:a", "release:b"}
	if at, err := redisCache.ReserveQuota(ctx, keys, []int64{1, 1}, time.Minute); err != nil || at != 0 {
		t.Fatalf("reserve: %d %v", at, err)
	}
	if at, _ := redisCache.ReserveQuota(ctx, keys, []int64{1, 1}, time.Minute); at == 0 {
		t.Fatal("the limit did not hold")
	}
	for i := 0; i < 3; i++ {
		if err := redisCache.ReleaseQuota(ctx, keys); err != nil {
			t.Fatal(err)
		}
	}
	if at, err := redisCache.ReserveQuota(ctx, keys, []int64{1, 1}, time.Minute); err != nil || at != 0 {
		t.Fatalf("after release: %d %v", at, err)
	}
	if at, _ := redisCache.ReserveQuota(ctx, keys, []int64{1, 1}, time.Minute); at == 0 {
		t.Fatal("extra releases created budget")
	}
}

func TestPasswordRangeLimitUsesTheTrustedAddress(t *testing.T) {
	redisCache := reviewRedis(t)
	log := &logger.Logger{Logger: zerolog.Nop()}
	apimiddleware.ConfigureAuth(quotaTokens{}, "test", log)
	t.Cleanup(func() { apimiddleware.ConfigureAuth(nil, "", nil) })
	fake := &fakeHIBP{status: http.StatusOK, body: strings.Repeat("A", 35) + ":1\r\n"}
	client := services.NewHIBPClient(services.HIBPConfig{APIKey: "test-key"}, log)
	client.SetTransportForTest(fake)
	monitor := services.NewDarkWebMonitor(client, nil, nil, nil, nil, log)
	cfg := config.Config{}
	cfg.RateLimit.Enabled = true
	cfg.RateLimit.RequestsPerMinute = 5
	rig := &quotaRig{h: api.NewRouter(cfg, &handlers.Handlers{DarkWeb: handlers.NewDarkWebHandler(monitor, log)}, redisCache, log).Setup()}

	var last *httptest.ResponseRecorder
	for i := 0; i < 20; i++ {
		last = rig.post("/api/v1/darkweb/password/range", "old-range", "198.51.100.72",
			fmt.Sprintf("203.0.113.%d", i), `{"prefix":"ABCDE"}`)
	}
	if got := fake.calls.Load(); got != 5 {
		t.Fatalf("rotating a forged hop reached upstream %d times, limit 5", got)
	}
	if last.Code != http.StatusTooManyRequests || last.Header().Get("Retry-After") == "" {
		t.Fatalf("want 429 with Retry-After, got %d", last.Code)
	}
	if rec := rig.post("/api/v1/darkweb/password/range", "old-range", "198.51.100.73", "", `{"prefix":"ABCDE"}`); rec.Code != http.StatusOK {
		t.Fatalf("another address: want 200, got %d", rec.Code)
	}
}

func TestNewDeviceKeyCarriesAHashedIssuer(t *testing.T) {
	redisCache := reviewRedis(t)
	log := &logger.Logger{Logger: zerolog.Nop()}
	auth := handlers.NewAuthHandler(redisCache, nil, "test-secret", log)
	t.Cleanup(func() { apimiddleware.ConfigureAuth(nil, "", nil) })
	router := api.NewRouter(config.Config{}, &handlers.Handlers{Auth: auth}, redisCache, log).Setup()

	register := func(device, clientIP string) apimiddleware.TokenClaims {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/device",
			strings.NewReader(`{"device_id":"`+device+`","platform":"android"}`))
		req.Header.Set("Content-Type", "application/json")
		req.RemoteAddr = quotaIngressPeer
		req.Header.Set("X-Forwarded-For", clientIP)
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, req)
		var body struct {
			APIKey string `json:"api_key"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil || body.APIKey == "" {
			t.Fatalf("register: %d %s", rec.Code, rec.Body)
		}
		var claims apimiddleware.TokenClaims
		if err := redisCache.GetJSON(context.Background(), "auth:apikey:"+body.APIKey, &claims); err != nil {
			t.Fatal(err)
		}
		return claims
	}
	first := register("device-a", "198.51.100.74")
	sameNetwork := register("device-b", "198.51.100.75")
	otherNetwork := register("device-c", "203.0.113.76")
	if first.IssuedFrom == "" || first.IssuedFrom != sameNetwork.IssuedFrom {
		t.Fatalf("one network must give one tag: %q %q", first.IssuedFrom, sameNetwork.IssuedFrom)
	}
	if first.IssuedFrom == otherNetwork.IssuedFrom {
		t.Fatal("two networks gave the same tag")
	}
	if strings.Contains(first.IssuedFrom, "198.51") {
		t.Fatal("the stored tag holds the address")
	}
}

func phoneRiskThroughRoute(t *testing.T, rig *quotaRig, number string) float64 {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/scam/phone/"+number, nil)
	req.Header.Set("Authorization", "Bearer old-reader")
	req.RemoteAddr = quotaIngressPeer
	req.Header.Set("X-Forwarded-For", "203.0.113.99")
	rec := httptest.NewRecorder()
	rig.h.ServeHTTP(rec, req)
	var body struct {
		Risk float64 `json:"risk_score"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("lookup: %d %s", rec.Code, rec.Body)
	}
	return body.Risk
}

func TestPhoneReportRouteCountsTheCredentialAndTheNetwork(t *testing.T) {
	log := &logger.Logger{Logger: zerolog.Nop()}
	apimiddleware.ConfigureAuth(quotaTokens{}, "test", log)
	t.Cleanup(func() { apimiddleware.ConfigureAuth(nil, "", nil) })
	detector := ai.NewScamDetector(log, ai.ScamDetectorConfig{EnablePhoneRep: true})
	rig := &quotaRig{h: api.NewRouter(config.Config{}, &handlers.Handlers{
		ScamDetection: handlers.NewScamDetectionHandler(log, detector),
	}, nil, log).Setup()}
	const number = "+4915112349999"
	before := phoneRiskThroughRoute(t, rig, number)

	report := func(key string, network int) {
		rec := rig.post("/api/v1/scam/phone/report", key, fmt.Sprintf("198.51.%d.7", network), "",
			`{"phone_number":"`+number+`"}`)
		if rec.Code != http.StatusCreated {
			t.Fatalf("report: %d %s", rec.Code, rec.Body)
		}
	}
	for network := 0; network < 8; network++ {
		report("old-single-key", network)
	}
	if got := phoneRiskThroughRoute(t, rig, number); got != before {
		t.Fatalf("one key on many networks moved the risk: %.2f to %.2f", before, got)
	}
	for key := 1; key < 5; key++ {
		report(fmt.Sprintf("old-reporter-%d", key), 0)
	}
	if got := phoneRiskThroughRoute(t, rig, number); got <= before {
		t.Fatalf("five keys and five networks must raise the risk: %.2f to %.2f", before, got)
	}
}

func paidClaimsJWT(t *testing.T, userID int64, valid, adSupported bool, gateway string) string {
	t.Helper()
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, apimiddleware.OrbNetClaims{
		UserID:            userID,
		SubscriptionValid: valid,
		IsAdSupported:     adSupported,
		PaymentGateway:    gateway,
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

func TestOnlyAPlanPaidWithMoneyGetsTheAccountBudget(t *testing.T) {
	cases := []struct {
		name        string
		valid       bool
		adSupported bool
		gateway     string
		want        int64
	}{
		{"card", true, false, "STRIPE", 12},
		{"store", true, false, "GOOGLE_PLAY", 12},
		{"free plan", true, false, "FREE", 5},
		{"token plan", true, false, "TOKEN_BASED", 5},
		{"gift card", true, false, "GIFT_CARD", 5},
		{"manual grant", true, false, "MANUAL", 5},
		{"reseller grant", true, false, "RESELLER_CREDIT", 5},
		{"no gateway", true, false, "", 5},
		{"ad-supported on a gateway", true, true, "STRIPE", 5},
		{"expired paid plan", false, false, "STRIPE", 5},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rig := newQuotaRig(t, 500, nil)
			token := paidClaimsJWT(t, 7, tc.valid, tc.adSupported, tc.gateway)
			for i := 0; i < 12; i++ {
				rig.checkEmail(token, "198.51.100.80", "", i)
			}
			if got := rig.hibp.calls.Load(); got != tc.want {
				t.Fatalf("want %d lookups, got %d", tc.want, got)
			}
		})
	}
}

func TestPaidAccountStopsAtItsOwnDailyLimit(t *testing.T) {
	rig := newQuotaRig(t, 500, nil)
	token := paidClaimsJWT(t, 8, true, false, "STRIPE")
	for i := 0; i < 60; i++ {
		rig.checkEmail(token, "198.51.100.81", "", i)
	}
	if got := rig.hibp.calls.Load(); got != 50 {
		t.Fatalf("want 50 lookups, got %d", got)
	}
}

// Another caller's lookup can answer from the cache, but registering the email
// still takes a unit, and the cache holds no clear address.
func TestCachedAnswerChargesARegistrationAndKeepsNoClearEmail(t *testing.T) {
	redisCache, prefix := reviewRedisScoped(t)
	log := &logger.Logger{Logger: zerolog.Nop()}
	apimiddleware.ConfigureAuth(quotaTokens{}, "test", log)
	t.Cleanup(func() { apimiddleware.ConfigureAuth(nil, "", nil) })
	fake := &fakeHIBP{status: http.StatusNotFound}
	client := services.NewHIBPClient(services.HIBPConfig{APIKey: "test-key"}, log)
	client.SetTransportForTest(fake)
	store := &memQuota{counts: map[string]int64{}, values: map[string]string{}, ttls: map[string]time.Duration{}}
	cfg := config.Config{}
	cfg.JWT.OrbNetAccessSecret = quotaJWTSecret
	// Two replicas on one Redis: checks need no database, and a registration
	// needs a repository to get as far as its charge.
	replica := func(repo *repository.DarkWebRepository) *quotaRig {
		monitor := services.NewDarkWebMonitor(client, nil, nil, repo, redisCache, log)
		monitor.SetPaidLookupsForTest(store, 500)
		h := &handlers.Handlers{DarkWeb: handlers.NewDarkWebHandler(monitor, log)}
		return &quotaRig{h: api.NewRouter(cfg, h, nil, log).Setup(), store: store, hibp: fake}
	}
	rig, registering := replica(nil), replica(&repository.DarkWebRepository{})

	const email = "cached.person@example.com"
	total := func() int64 {
		for key, count := range store.counts {
			if strings.HasSuffix(key, ":total") && !strings.Contains(key, ":refund:") {
				return count
			}
		}
		return 0
	}
	if rec := rig.checkOne("old-c1", "198.51.100.90", email); rec.Code != http.StatusOK {
		t.Fatalf("first lookup: %d", rec.Code)
	}
	rec := rig.checkOne("old-c2", "198.51.100.91", email)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), email) {
		t.Fatalf("cached answer must name the requested address: %d %s", rec.Code, rec.Body)
	}
	if got := total(); got != 1 || fake.calls.Load() != 1 {
		t.Fatalf("a cache hit on a check: %d units, %d calls", got, fake.calls.Load())
	}
	// The repository has no pool, so the request ends with a 500 after the
	// charge; only the charge is under test here.
	registering.post("/api/v1/darkweb/monitor", "old-c3", "198.51.100.92", "",
		`{"asset_type":"email","value":"`+email+`"}`)
	if got := total(); got != 2 || fake.calls.Load() != 1 {
		t.Fatalf("registering a cached email: %d units, %d calls", got, fake.calls.Load())
	}

	ctx := context.Background()
	keys, err := redisCache.Client().Keys(ctx, prefix+"*").Result()
	if err != nil {
		t.Fatal(err)
	}
	if len(keys) == 0 {
		t.Fatal("the scan found none of this test's keys")
	}
	for _, key := range keys {
		if strings.Contains(key, email) {
			t.Fatalf("clear email in key %s", key)
		}
		if kind, _ := redisCache.Client().Type(ctx, key).Result(); kind == "string" {
			if value, _ := redisCache.Client().Get(ctx, key).Result(); strings.Contains(value, email) {
				t.Fatalf("clear email in the value of %s", key)
			}
		}
	}
}
