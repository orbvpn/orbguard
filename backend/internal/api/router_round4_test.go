package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"

	"orbguard-lab/internal/api/handlers"
	apimiddleware "orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/config"
	"orbguard-lab/internal/domain/services/ai"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/pkg/logger"
)

const (
	privateDigits = "4915112340099"
	privateNumber = "+" + privateDigits
	privateNote   = "marker-private-report-text"
)

// round4Log collects log lines from every goroutine of a request.
type round4Log struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (l *round4Log) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.Write(p)
}

func (l *round4Log) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.String()
}

func round4Redis(t *testing.T) *cache.RedisCache {
	t.Helper()
	addr := os.Getenv("ORBGUARD_TEST_REDIS_ADDR")
	if addr == "" {
		t.Skip("ORBGUARD_TEST_REDIS_ADDR not set; skipping Redis-backed test")
	}
	host, portText, _ := strings.Cut(addr, ":")
	port, err := strconv.Atoi(portText)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	redisCache, err := cache.NewRedis(ctx, config.RedisConfig{
		Host: host, Port: port, KeyPrefix: fmt.Sprintf("orbguard-test:%d:", time.Now().UnixNano()),
	}, &logger.Logger{Logger: zerolog.Nop()})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = redisCache.Close() })
	return redisCache
}

// awayFromMinuteEdge keeps a run of requests inside one limiter window.
func awayFromMinuteEdge() {
	if s := time.Now().Second(); s >= 55 {
		time.Sleep(time.Duration(61-s) * time.Second)
	}
}

func fromPeer(addr string) reqOpt {
	return func(r *http.Request) { r.RemoteAddr = addr }
}

func limitedRouter(t *testing.T, perMinute int) http.Handler {
	t.Helper()
	redisCache := round4Redis(t)
	cfg := config.Config{}
	cfg.RateLimit.Enabled = true
	cfg.RateLimit.RequestsPerMinute = perMinute
	t.Cleanup(func() { apimiddleware.ConfigureAuth(nil, "", nil) })
	return NewRouter(cfg, &handlers.Handlers{}, redisCache, &logger.Logger{Logger: zerolog.Nop()}).Setup()
}

// probe asks for a path no route serves: past the limiter it is a 404.
func probe(h http.Handler, opts ...reqOpt) *httptest.ResponseRecorder {
	return do(h, http.MethodGet, "/round4-probe", nil, opts...)
}

func TestGlobalLimiterIgnoresForwardingHeadersAClientSends(t *testing.T) {
	h := limitedRouter(t, 5)
	awayFromMinuteEdge()
	const client = "192.0.2.10"
	forged := func(i int) []reqOpt {
		return []reqOpt{
			clientHeader("X-Forwarded-For", fmt.Sprintf("203.0.113.%d", i+1)),
			clientHeader("X-Real-IP", fmt.Sprintf("198.51.100.%d", i+1)),
			fromIP(client),
		}
	}
	for i := 0; i < 5; i++ {
		if rec := probe(h, forged(i)...); rec.Code != http.StatusNotFound {
			t.Fatalf("request %d inside the limit: want 404, got %d", i+1, rec.Code)
		}
	}
	rec := probe(h, forged(6)...)
	if rec.Code != http.StatusTooManyRequests || rec.Header().Get("Retry-After") == "" {
		t.Fatalf("over the limit with a new forged address: want 429 with Retry-After, got %d", rec.Code)
	}
	if rec := probe(h, fromIP("192.0.2.11")); rec.Code != http.StatusNotFound {
		t.Fatalf("another client: want 404, got %d", rec.Code)
	}
}

func TestGlobalLimiterIgnoresHeadersFromADirectPeer(t *testing.T) {
	h := limitedRouter(t, 3)
	awayFromMinuteEdge()
	for i := 0; i < 3; i++ {
		rec := probe(h, fromPeer("192.0.2.20:4000"),
			clientHeader("X-Forwarded-For", fmt.Sprintf("203.0.113.%d", i+1)))
		if rec.Code != http.StatusNotFound {
			t.Fatalf("request %d: want 404, got %d", i+1, rec.Code)
		}
	}
	rec := probe(h, fromPeer("192.0.2.20:4000"), clientHeader("X-Forwarded-For", "203.0.113.200"))
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("over the limit: want 429, got %d", rec.Code)
	}
}

func TestGlobalLimiterGroupsAnIPv6SubscriberOnly(t *testing.T) {
	h := limitedRouter(t, 3)
	awayFromMinuteEdge()
	for i := 0; i < 3; i++ {
		if rec := probe(h, fromIP(fmt.Sprintf("2001:db8:1:2::%x", i+1))); rec.Code != http.StatusNotFound {
			t.Fatalf("request %d: want 404, got %d", i+1, rec.Code)
		}
	}
	if rec := probe(h, fromIP("2001:db8:1:2::ff")); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("same /64: want 429, got %d", rec.Code)
	}
	if rec := probe(h, fromIP("2001:db8:1:3::1")); rec.Code != http.StatusNotFound {
		t.Fatalf("next /64: want 404, got %d", rec.Code)
	}
}

// A health probe or an internal caller has no public address. Each of its
// connections keeps its own count, as it did before, so internal traffic can
// never share one bucket and start seeing 429.
func TestGlobalLimiterKeepsInternalCallersPerConnection(t *testing.T) {
	h := limitedRouter(t, 3)
	awayFromMinuteEdge()
	for i := 0; i < 12; i++ {
		rec := probe(h, fromPeer(fmt.Sprintf("100.100.0.7:%d", 41000+i)))
		if rec.Code != http.StatusNotFound {
			t.Fatalf("internal connection %d: want 404, got %d", i, rec.Code)
		}
	}
	for i := 0; i < 3; i++ {
		if rec := probe(h, fromPeer("100.100.0.7:42000")); rec.Code != http.StatusNotFound {
			t.Fatalf("one connection, request %d: want 404, got %d", i+1, rec.Code)
		}
	}
	if rec := probe(h, fromPeer("100.100.0.7:42000")); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("one connection over the limit: want 429, got %d", rec.Code)
	}
}

func registrationRouter(t *testing.T) (http.Handler, *cache.RedisCache) {
	t.Helper()
	redisCache := round4Redis(t)
	log := &logger.Logger{Logger: zerolog.Nop()}
	auth := handlers.NewAuthHandler(redisCache, nil, "test-secret", log)
	t.Cleanup(func() { apimiddleware.ConfigureAuth(nil, "", nil) })
	return NewRouter(config.Config{}, &handlers.Handlers{Auth: auth}, redisCache, log).Setup(), redisCache
}

func registerDevice(h http.Handler, device string, opts ...reqOpt) *httptest.ResponseRecorder {
	return do(h, http.MethodPost, "/api/v1/auth/device",
		strings.NewReader(`{"device_id":"`+device+`","platform":"android"}`), opts...)
}

func TestDeviceRegistrationLimitPerAddressPerDay(t *testing.T) {
	h, redisCache := registrationRouter(t)
	const client = "192.0.2.30"
	for i := 0; i < 30; i++ {
		if rec := registerDevice(h, fmt.Sprintf("limit-%d", i), fromIP(client)); rec.Code != http.StatusCreated {
			t.Fatalf("registration %d: want 201, got %d: %s", i+1, rec.Code, rec.Body)
		}
	}
	rec := registerDevice(h, "limit-refused", clientHeader("X-Forwarded-For", "203.0.113.9"), fromIP(client))
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("registration 31 with a forged hop: want 429, got %d", rec.Code)
	}
	retry, err := strconv.Atoi(rec.Header().Get("Retry-After"))
	if err != nil || retry < 1 || retry > 86401 {
		t.Fatalf("Retry-After = %q, want seconds until the next UTC day", rec.Header().Get("Retry-After"))
	}
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
		t.Fatalf("Content-Type = %q: the app reads the message from a JSON body", ct)
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("body is not JSON: %s", rec.Body)
	}
	if body["error"] == nil || body["api_key"] != nil || body["token"] != nil {
		t.Fatalf("refusal must carry an error and no credential: %s", rec.Body)
	}
	var stored map[string]any
	if err := redisCache.GetJSON(context.Background(), "auth:device:limit-refused", &stored); err == nil {
		t.Fatal("a refused registration stored a device record")
	}
	if rec := registerDevice(h, "limit-other", fromIP("192.0.2.31")); rec.Code != http.StatusCreated {
		t.Fatalf("another address: want 201, got %d", rec.Code)
	}
}

func TestDeviceRegistrationLimitGroupsIPv6BySite(t *testing.T) {
	h, _ := registrationRouter(t)
	for i := 0; i < 30; i++ {
		ip := fmt.Sprintf("2001:db8:5:%x::1", i+1)
		if rec := registerDevice(h, fmt.Sprintf("site-%d", i), fromIP(ip)); rec.Code != http.StatusCreated {
			t.Fatalf("registration %d: want 201, got %d", i+1, rec.Code)
		}
	}
	if rec := registerDevice(h, "site-refused", fromIP("2001:db8:5:ff::1")); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("same /48: want 429, got %d", rec.Code)
	}
	if rec := registerDevice(h, "site-other", fromIP("2001:db8:6::1")); rec.Code != http.StatusCreated {
		t.Fatalf("next /48: want 201, got %d", rec.Code)
	}
}

func TestInvalidRegistrationsDoNotUseTheDailyLimit(t *testing.T) {
	h, _ := registrationRouter(t)
	const client = "192.0.2.32"
	for i := 0; i < 40; i++ {
		rec := do(h, http.MethodPost, "/api/v1/auth/device", strings.NewReader(`{"platform":"android"}`), fromIP(client))
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("invalid request: want 400, got %d", rec.Code)
		}
	}
	for i := 0; i < 30; i++ {
		if rec := registerDevice(h, fmt.Sprintf("valid-%d", i), fromIP(client)); rec.Code != http.StatusCreated {
			t.Fatalf("registration %d after invalid requests: want 201, got %d", i+1, rec.Code)
		}
	}
}

func TestDeviceRegistrationWithoutRedisIssuesNothing(t *testing.T) {
	h, redisCache := registrationRouter(t)
	if err := redisCache.Close(); err != nil {
		t.Fatal(err)
	}
	rec := registerDevice(h, "no-redis", fromIP("192.0.2.33"))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("Redis down: want 503, got %d", rec.Code)
	}
	if strings.Contains(rec.Body.String(), "api_key") {
		t.Fatalf("Redis down: response holds a credential: %s", rec.Body)
	}
}

func TestPhoneAndReportTextNeverReachALog(t *testing.T) {
	logs := &round4Log{}
	log := &logger.Logger{Logger: zerolog.New(logs).Level(zerolog.DebugLevel)}
	apimiddleware.ConfigureAuth(memTokenStore{}, "test", log)
	t.Cleanup(func() { apimiddleware.ConfigureAuth(nil, "", nil) })
	cfg := config.Config{}
	cfg.JWT.Secret = guardServiceSecret
	detector := ai.NewScamDetector(log, ai.ScamDetectorConfig{EnablePhoneRep: true})
	h := NewRouter(cfg, &handlers.Handlers{
		ScamDetection: handlers.NewScamDetectionHandler(log, detector),
		SMS:           handlers.NewSMSHandler(nil, nil, log),
	}, nil, log).Setup()

	if rec := do(h, http.MethodGet, "/api/v1/scam/phone/"+privateNumber, nil, asDevice()); rec.Code != http.StatusOK {
		t.Fatalf("lookup: want 200, got %d: %s", rec.Code, rec.Body)
	}
	do(h, http.MethodGet, "/api/v1/scam/phone/%2B"+privateDigits, nil, asDevice())
	report := fmt.Sprintf(`{"phone_number":%q,"scam_type":%q,"description":%q}`, privateNumber, privateNote, privateNote)
	if rec := do(h, http.MethodPost, "/api/v1/scam/phone/report", strings.NewReader(report), asDevice()); rec.Code != http.StatusCreated {
		t.Fatalf("phone report: want 201, got %d: %s", rec.Code, rec.Body)
	}
	full := fmt.Sprintf(`{"content":%q,"content_type":%q,"phone_number":%q,"scam_type":%q,"description":%q}`,
		privateNote, privateNote, privateNumber, privateNote, privateNote)
	if rec := do(h, http.MethodPost, "/api/v1/scam/report", strings.NewReader(full), asDevice()); rec.Code != http.StatusCreated {
		t.Fatalf("scam report: want 201, got %d: %s", rec.Code, rec.Body)
	}
	do(h, http.MethodPost, "/api/v1/scam/analyze",
		strings.NewReader(fmt.Sprintf(`{"content":"hello there","content_type":%q}`, privateNote)), asDevice())
	// The time parser's error quotes the value it could not read.
	for path, body := range map[string]string{
		"/api/v1/sms/analyze":       `{"body":"hello","timestamp":"` + privateNumber + `"}`,
		"/api/v1/sms/analyze/batch": `{"messages":[{"body":"hello","timestamp":"` + privateNumber + `"}]}`,
	} {
		if rec := do(h, http.MethodPost, path, strings.NewReader(body), asDevice()); rec.Code != http.StatusBadRequest {
			t.Fatalf("%s with a malformed time: want 400, got %d", path, rec.Code)
		}
	}

	text := logs.String()
	if strings.Contains(text, privateDigits) {
		t.Errorf("a full phone number reached the log")
	}
	if strings.Contains(text, privateNote) {
		t.Errorf("report text reached the log")
	}
	for _, kept := range []string{`"country_code":"DE"`, `"scam_type":"other"`, `/api/v1/scam/phone/{number}`, `/api/v1/scam/phone/report`} {
		if !strings.Contains(text, kept) {
			t.Errorf("log lost %s", kept)
		}
	}
}

func TestAuthLogsHoldNoPhoneNumber(t *testing.T) {
	for _, env := range []string{"production", "development"} {
		t.Run(env, func(t *testing.T) {
			logs := &round4Log{}
			log := &logger.Logger{Logger: zerolog.New(logs).Level(zerolog.DebugLevel)}
			apimiddleware.ConfigureAuth(nil, env, log)
			t.Cleanup(func() { apimiddleware.ConfigureAuth(nil, "", nil) })
			detector := ai.NewScamDetector(log, ai.ScamDetectorConfig{EnablePhoneRep: true})
			h := NewRouter(config.Config{}, &handlers.Handlers{
				ScamDetection: handlers.NewScamDetectionHandler(log, detector),
			}, nil, log).Setup()
			do(h, http.MethodGet, "/api/v1/scam/phone/"+privateNumber, nil, asDevice())
			text := logs.String()
			if strings.Contains(text, privateDigits) {
				t.Errorf("a full phone number reached the log")
			}
			if !strings.Contains(text, "token store not configured") {
				t.Errorf("the auth log line is gone")
			}
		})
	}
}

func TestFailedPhoneLookupLogHoldsNoNumber(t *testing.T) {
	logs := &round4Log{}
	log := &logger.Logger{Logger: zerolog.New(logs).Level(zerolog.DebugLevel)}
	apimiddleware.ConfigureAuth(memTokenStore{}, "test", log)
	t.Cleanup(func() { apimiddleware.ConfigureAuth(nil, "", nil) })
	cfg := config.Config{}
	cfg.JWT.Secret = guardServiceSecret
	detector := ai.NewScamDetector(log, ai.ScamDetectorConfig{})
	h := NewRouter(cfg, &handlers.Handlers{
		ScamDetection: handlers.NewScamDetectionHandler(log, detector),
	}, nil, log).Setup()
	rec := do(h, http.MethodGet, "/api/v1/scam/phone/"+privateNumber, nil, asDevice())
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("lookup with the service off: want 500, got %d", rec.Code)
	}
	text := logs.String()
	if strings.Contains(text, privateDigits) {
		t.Errorf("a full phone number reached the log")
	}
	if !strings.Contains(text, "phone reputation lookup failed") {
		t.Errorf("the failure left no log line")
	}
}

// These two call sites cannot be reached today: the services behind them never
// return an error. The check keeps the field from coming back with one.
func TestUnreachableLogSitesCarryNoPrivateField(t *testing.T) {
	sites := map[string]*regexp.Regexp{
		"handlers/qr_security.go":                   regexp.MustCompile(`Str\("content"`),
		"../domain/services/ai/phone_reputation.go": regexp.MustCompile(`Str\("(number|phone)"`),
	}
	for file, field := range sites {
		source, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		if field.Match(source) {
			t.Errorf("%s logs a private field", file)
		}
	}
}
