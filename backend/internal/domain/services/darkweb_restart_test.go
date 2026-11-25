package services_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"

	"orbguard-lab/internal/api"
	"orbguard-lab/internal/api/handlers"
	apimiddleware "orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/config"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/pkg/logger"
)

type restartRig struct {
	t *testing.T
	h http.Handler
}

func newRestartRig(t *testing.T, seed map[string]apimiddleware.TokenClaims) *restartRig {
	t.Helper()
	redisCache := reviewRedis(t)
	log := &logger.Logger{Logger: zerolog.Nop()}
	auth := handlers.NewAuthHandler(redisCache, nil, quotaServiceSecret, log)
	t.Cleanup(func() { apimiddleware.ConfigureAuth(nil, "", nil) })
	client := services.NewHIBPClient(services.HIBPConfig{APIKey: "test-key"}, log)
	client.SetTransportForTest(&fakeHIBP{status: http.StatusNotFound})
	monitor := services.NewDarkWebMonitor(client, nil, nil, nil, nil, log)
	monitor.SetPaidLookupsForTest(redisCache, 500)
	cfg := config.Config{}
	cfg.JWT.Secret = quotaServiceSecret
	for key, claims := range seed {
		if err := redisCache.SetJSON(context.Background(), key, claims, time.Hour); err != nil {
			t.Fatal(err)
		}
	}
	return &restartRig{t: t, h: api.NewRouter(cfg, &handlers.Handlers{
		Auth: auth, DarkWeb: handlers.NewDarkWebHandler(monitor, log),
	}, nil, log).Setup()}
}

func (rig *restartRig) send(path, bearer, client, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	req.RemoteAddr = quotaIngressPeer
	req.Header.Set("X-Forwarded-For", client)
	rec := httptest.NewRecorder()
	rig.h.ServeHTTP(rec, req)
	return rec
}

func (rig *restartRig) register(bearer, device, client string) (apiKey, session string) {
	rig.t.Helper()
	rec := rig.send("/api/v1/auth/device", bearer, client, `{"device_id":"`+device+`","platform":"android"}`)
	if rec.Code != http.StatusCreated {
		rig.t.Fatalf("register %s: %d", device, rec.Code)
	}
	var body struct {
		APIKey string `json:"api_key"`
		Token  string `json:"token"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		rig.t.Fatal(err)
	}
	return body.APIKey, body.Token
}

func (rig *restartRig) lookup(bearer, client string, n int) int {
	return rig.send("/api/v1/darkweb/check/email", bearer, client,
		fmt.Sprintf(`{"email":"restart%d@example.com"}`, n)).Code
}

// spendNewDeviceLimit uses up what new keys may spend on this address today.
func (rig *restartRig) spendNewDeviceLimit(client string) {
	rig.t.Helper()
	for i := 0; i < 5; i++ {
		key, _ := rig.register("", fmt.Sprintf("spend-%d", i), client)
		if code := rig.lookup(key, client, i); code != http.StatusOK {
			rig.t.Fatalf("new install %d: %d", i, code)
		}
	}
}

func agedClaims(device string) apimiddleware.TokenClaims {
	return apimiddleware.TokenClaims{
		DeviceID:   device,
		ExpiresAt:  time.Now().Add(deviceKeyTTL - 48*time.Hour),
		IssuedFrom: "issuer-seed",
	}
}

func TestAppRestartKeepsTheEstablishedTier(t *testing.T) {
	const client = "203.0.113.90"
	rig := newRestartRig(t, map[string]apimiddleware.TokenClaims{"auth:apikey:restart-aged": agedClaims("restart-device")})
	rig.spendNewDeviceLimit(client)

	key, session := rig.register("restart-aged", "restart-device", client)
	if code := rig.lookup(key, client, 100); code != http.StatusOK {
		t.Errorf("after a restart: got %d", code)
	}
	viaSession, _ := rig.register(session, "restart-device", client)
	if code := rig.lookup(viaSession, client, 101); code != http.StatusOK {
		t.Errorf("after a restart that presented a session token: got %d", code)
	}
}

func TestSessionTokenStaysOnTheNewDeviceTier(t *testing.T) {
	const client = "203.0.113.92"
	rig := newRestartRig(t, map[string]apimiddleware.TokenClaims{"auth:apikey:restart-aged": agedClaims("restart-device")})
	rig.spendNewDeviceLimit(client)

	_, session := rig.register("restart-aged", "restart-device", client)
	if code := rig.lookup(session, client, 103); code != http.StatusTooManyRequests {
		t.Errorf("a session token is not a device key: want 429, got %d", code)
	}
}

func TestNewDeviceGainsNoTierFromAnAgedKey(t *testing.T) {
	const client = "203.0.113.91"
	rig := newRestartRig(t, map[string]apimiddleware.TokenClaims{"auth:apikey:restart-aged": agedClaims("restart-device")})
	rig.spendNewDeviceLimit(client)

	key, _ := rig.register("restart-aged", "another-device", client)
	if code := rig.lookup(key, client, 102); code != http.StatusTooManyRequests {
		t.Errorf("a new device presenting an aged key of another device: want 429, got %d", code)
	}
}
