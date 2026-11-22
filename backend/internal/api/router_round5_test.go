package api

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"regexp"
	"strconv"
	"strings"
	"testing"
	"time"

	apimiddleware "orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/infrastructure/cache"
)

const round5KeyTTL = 365 * 24 * time.Hour

type issuedCredentials struct {
	APIKey       string `json:"api_key"`
	Token        string `json:"token"`
	RefreshToken string `json:"refresh_token"`
}

func credentialsFrom(t *testing.T, rec *httptest.ResponseRecorder) issuedCredentials {
	t.Helper()
	if rec.Code != http.StatusCreated {
		t.Fatalf("registration: want 201, got %d: %s", rec.Code, rec.Body)
	}
	var issued issuedCredentials
	if err := json.Unmarshal(rec.Body.Bytes(), &issued); err != nil || issued.APIKey == "" {
		t.Fatalf("registration body: %v: %s", err, rec.Body)
	}
	return issued
}

func withBearer(token string) reqOpt {
	return func(r *http.Request) { r.Header.Set("Authorization", "Bearer "+token) }
}

func refreshedToken(t *testing.T, h http.Handler, refreshToken, client string) string {
	t.Helper()
	rec := do(h, http.MethodPost, "/api/v1/auth/refresh",
		strings.NewReader(`{"refresh_token":"`+refreshToken+`"}`), fromIP(client))
	if rec.Code != http.StatusOK {
		t.Fatalf("refresh: %d: %s", rec.Code, rec.Body)
	}
	var body struct {
		Token string `json:"token"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil || body.Token == "" {
		t.Fatalf("refresh body: %v", err)
	}
	return body.Token
}

func registrationBucket(address string) string {
	sum := sha256.Sum256([]byte(address))
	return "auth:device-registrations:{" + time.Now().UTC().Format("20060102") + "}:" + hex.EncodeToString(sum[:12])
}

func chargedToday(t *testing.T, redisCache *cache.RedisCache, address string) int {
	t.Helper()
	raw, err := redisCache.Get(context.Background(), registrationBucket(address))
	if err != nil {
		return 0
	}
	count, err := strconv.Atoi(raw)
	if err != nil {
		t.Fatalf("bucket value %q", raw)
	}
	return count
}

func storedKey(t *testing.T, redisCache *cache.RedisCache, apiKey string) apimiddleware.TokenClaims {
	t.Helper()
	var claims apimiddleware.TokenClaims
	if err := redisCache.GetJSON(context.Background(), "auth:apikey:"+apiKey, &claims); err != nil {
		t.Fatal(err)
	}
	return claims
}

func seedCredential(t *testing.T, redisCache *cache.RedisCache, key string, claims apimiddleware.TokenClaims) {
	t.Helper()
	if err := redisCache.SetJSON(context.Background(), key, claims, time.Hour); err != nil {
		t.Fatal(err)
	}
}

func TestDeviceHoldingItsCredentialIsNeverCharged(t *testing.T) {
	forms := map[string]func(t *testing.T, h http.Handler, first issuedCredentials, client string) string{
		"api key": func(_ *testing.T, _ http.Handler, first issuedCredentials, _ string) string {
			return first.APIKey
		},
		"session token": func(_ *testing.T, _ http.Handler, first issuedCredentials, _ string) string {
			return first.Token
		},
		"session token after a refresh": func(t *testing.T, h http.Handler, first issuedCredentials, client string) string {
			return refreshedToken(t, h, first.RefreshToken, client)
		},
	}
	n := 0
	for name, credential := range forms {
		n++
		client := fmt.Sprintf("192.0.2.%d", 60+n)
		t.Run(name, func(t *testing.T) {
			h, redisCache := registrationRouter(t)
			first := credentialsFrom(t, registerDevice(h, "holder", fromIP(client)))
			bearer := credential(t, h, first, client)
			for i := 0; i < 29; i++ {
				credentialsFrom(t, registerDevice(h, fmt.Sprintf("other-%d", i), fromIP(client)))
			}
			if got := chargedToday(t, redisCache, client); got != 30 {
				t.Fatalf("bucket before the holder: %d, want 30", got)
			}
			credentialsFrom(t, registerDevice(h, "holder", withBearer(bearer), fromIP(client)))
			if got := chargedToday(t, redisCache, client); got != 30 {
				t.Errorf("the holder was charged: bucket %d", got)
			}
			if rec := registerDevice(h, "stranger", fromIP(client)); rec.Code != http.StatusTooManyRequests {
				t.Errorf("a new device at the limit: want 429, got %d", rec.Code)
			}
		})
	}
}

func TestHolderDoesNotNeedTheLimitCounter(t *testing.T) {
	h, redisCache := registrationRouter(t)
	const client = "192.0.2.70"
	holder := credentialsFrom(t, registerDevice(h, "counter-holder", fromIP(client)))
	other := credentialsFrom(t, registerDevice(h, "counter-other", fromIP(client)))
	if err := redisCache.Set(context.Background(), registrationBucket(client), "not a number", time.Hour); err != nil {
		t.Fatal(err)
	}

	credentialsFrom(t, registerDevice(h, "counter-holder", withBearer(holder.APIKey), fromIP(client)))
	credentialsFrom(t, registerDevice(h, "counter-holder", withBearer(holder.Token), fromIP(client)))

	for name, opts := range map[string][]reqOpt{
		"no credential":        {fromIP(client)},
		"another device's key": {withBearer(other.APIKey), fromIP(client)},
	} {
		rec := registerDevice(h, "counter-holder", opts...)
		if rec.Code != http.StatusServiceUnavailable {
			t.Errorf("%s: want 503 while the counter cannot be read, got %d", name, rec.Code)
		}
		if strings.Contains(rec.Body.String(), "api_key") {
			t.Errorf("%s: a credential was issued", name)
		}
	}
}

func TestOtherCredentialsAreChargedAsNewRegistrations(t *testing.T) {
	past := time.Now().UTC().Add(-time.Hour)
	cases := map[string]func(t *testing.T, redisCache *cache.RedisCache, other issuedCredentials) string{
		"key of another device":     func(_ *testing.T, _ *cache.RedisCache, other issuedCredentials) string { return other.APIKey },
		"session of another device": func(_ *testing.T, _ *cache.RedisCache, other issuedCredentials) string { return other.Token },
		"expired key of this device": func(t *testing.T, redisCache *cache.RedisCache, _ issuedCredentials) string {
			seedCredential(t, redisCache, "auth:apikey:round5-expired", apimiddleware.TokenClaims{DeviceID: "target", ExpiresAt: past})
			return "round5-expired"
		},
		"expired session of this device": func(t *testing.T, redisCache *cache.RedisCache, _ issuedCredentials) string {
			seedCredential(t, redisCache, "auth:token:round5-expired", apimiddleware.TokenClaims{DeviceID: "target", ExpiresAt: past})
			return "round5-expired"
		},
		"unknown token":  func(*testing.T, *cache.RedisCache, issuedCredentials) string { return "round5-unknown" },
		"service secret": func(*testing.T, *cache.RedisCache, issuedCredentials) string { return "test-secret" },
	}
	n := 0
	for name, credential := range cases {
		n++
		client := fmt.Sprintf("192.0.2.%d", 80+n)
		t.Run(name, func(t *testing.T) {
			h, redisCache := registrationRouter(t)
			other := credentialsFrom(t, registerDevice(h, "other", fromIP(client)))
			bearer := credential(t, redisCache, other)
			credentialsFrom(t, registerDevice(h, "target", withBearer(bearer), fromIP(client)))
			if got := chargedToday(t, redisCache, client); got != 2 {
				t.Fatalf("bucket: %d, want 2", got)
			}
			for i := 0; i < 28; i++ {
				credentialsFrom(t, registerDevice(h, fmt.Sprintf("fill-%d", i), fromIP(client)))
			}
			if rec := registerDevice(h, "target", withBearer(bearer), fromIP(client)); rec.Code != http.StatusTooManyRequests {
				t.Errorf("at the limit: want 429, got %d", rec.Code)
			}
		})
	}
}

func sameInstant(a, b time.Time) bool {
	d := a.Sub(b)
	return d > -time.Second && d < time.Second
}

func TestReRegistrationKeepsTheKeyAge(t *testing.T) {
	h, redisCache := registrationRouter(t)
	const client = "192.0.2.100"
	since := time.Now().UTC().Add(-48 * time.Hour)
	seedCredential(t, redisCache, "auth:apikey:round5-aged", apimiddleware.TokenClaims{
		DeviceID: "aged", ExpiresAt: since.Add(round5KeyTTL), IssuedFrom: "issuer-seed",
	})

	check := func(step string, apiKey string) {
		t.Helper()
		claims := storedKey(t, redisCache, apiKey)
		if !sameInstant(claims.KeySince, since) {
			t.Errorf("%s: key age starts at %v, want %v", step, claims.KeySince, since)
		}
		if claims.IssuedFrom != "issuer-seed" {
			t.Errorf("%s: issuer %q, want the original", step, claims.IssuedFrom)
		}
		if !claims.ExpiresAt.After(time.Now().Add(round5KeyTTL - time.Hour)) {
			t.Errorf("%s: the new key must keep a full lifetime, expires %v", step, claims.ExpiresAt)
		}
	}

	restart := credentialsFrom(t, registerDevice(h, "aged", withBearer("round5-aged"), fromIP(client)))
	check("first restart", restart.APIKey)
	second := credentialsFrom(t, registerDevice(h, "aged", withBearer(restart.APIKey), fromIP(client)))
	check("second restart", second.APIKey)
	viaSession := credentialsFrom(t, registerDevice(h, "aged", withBearer(second.Token), fromIP(client)))
	check("session token", viaSession.APIKey)
	refreshed := refreshedToken(t, h, viaSession.RefreshToken, client)
	viaRefresh := credentialsFrom(t, registerDevice(h, "aged", withBearer(refreshed), fromIP(client)))
	check("session token after a refresh", viaRefresh.APIKey)
}

func TestReRegistrationKeepsAnUntaggedKeyUntagged(t *testing.T) {
	h, redisCache := registrationRouter(t)
	const client = "192.0.2.101"
	since := time.Now().UTC().Add(-72 * time.Hour)
	seedCredential(t, redisCache, "auth:apikey:round5-untagged", apimiddleware.TokenClaims{
		DeviceID: "untagged", ExpiresAt: since.Add(round5KeyTTL),
	})
	first := credentialsFrom(t, registerDevice(h, "untagged", withBearer("round5-untagged"), fromIP(client)))
	claims := storedKey(t, redisCache, first.APIKey)
	if claims.IssuedFrom != "" || !sameInstant(claims.KeySince, since) {
		t.Fatalf("issuer %q since %v: an untagged key must stay untagged and keep its age", claims.IssuedFrom, claims.KeySince)
	}
	again := credentialsFrom(t, registerDevice(h, "untagged", withBearer(first.Token), fromIP(client)))
	claims = storedKey(t, redisCache, again.APIKey)
	if claims.IssuedFrom != "" || !sameInstant(claims.KeySince, since) {
		t.Fatalf("via session: issuer %q since %v", claims.IssuedFrom, claims.KeySince)
	}
}

func TestKeyAgeNeverReachesAnotherDevice(t *testing.T) {
	past := time.Now().UTC().Add(-time.Hour)
	since := time.Now().UTC().Add(-90 * 24 * time.Hour)
	aged := apimiddleware.TokenClaims{DeviceID: "aged", ExpiresAt: since.Add(round5KeyTTL), KeySince: since, IssuedFrom: "issuer-seed"}

	cases := map[string]struct {
		device string
		seed   func(t *testing.T, redisCache *cache.RedisCache)
		bearer string
	}{
		"new device presenting an aged key": {
			device: "fresh-device",
			seed: func(t *testing.T, redisCache *cache.RedisCache) {
				seedCredential(t, redisCache, "auth:apikey:round5-cred", aged)
			},
			bearer: "round5-cred",
		},
		"new device presenting an aged session": {
			device: "fresh-device",
			seed: func(t *testing.T, redisCache *cache.RedisCache) {
				seedCredential(t, redisCache, "auth:token:round5-cred", apimiddleware.TokenClaims{
					DeviceID: "aged", ExpiresAt: time.Now().Add(time.Hour), KeySince: since, IssuedFrom: "issuer-seed",
				})
			},
			bearer: "round5-cred",
		},
		"same device with no credential": {
			device: "aged",
			seed: func(t *testing.T, redisCache *cache.RedisCache) {
				seedCredential(t, redisCache, "auth:apikey:round5-cred", aged)
			},
		},
		"same device with an expired key": {
			device: "aged",
			seed: func(t *testing.T, redisCache *cache.RedisCache) {
				expired := aged
				expired.ExpiresAt = past
				seedCredential(t, redisCache, "auth:apikey:round5-cred", expired)
			},
			bearer: "round5-cred",
		},
		"key with no expiry and no age": {
			device: "aged",
			seed: func(t *testing.T, redisCache *cache.RedisCache) {
				seedCredential(t, redisCache, "auth:apikey:round5-cred", apimiddleware.TokenClaims{DeviceID: "aged", IssuedFrom: "issuer-seed"})
			},
			bearer: "round5-cred",
		},
		"session issued before ages were recorded": {
			device: "aged",
			seed: func(t *testing.T, redisCache *cache.RedisCache) {
				seedCredential(t, redisCache, "auth:token:round5-cred", apimiddleware.TokenClaims{
					DeviceID: "aged", ExpiresAt: time.Now().Add(time.Hour),
				})
			},
			bearer: "round5-cred",
		},
	}
	n := 0
	for name, tc := range cases {
		n++
		client := fmt.Sprintf("192.0.2.%d", 110+n)
		t.Run(name, func(t *testing.T) {
			h, redisCache := registrationRouter(t)
			tc.seed(t, redisCache)
			opts := []reqOpt{fromIP(client)}
			if tc.bearer != "" {
				opts = append(opts, withBearer(tc.bearer))
			}
			issued := credentialsFrom(t, registerDevice(h, tc.device, opts...))
			claims := storedKey(t, redisCache, issued.APIKey)
			if time.Since(claims.KeySince) > time.Minute {
				t.Errorf("the new key inherited an age: %v", claims.KeySince)
			}
			if claims.IssuedFrom == "issuer-seed" || claims.IssuedFrom == "" {
				t.Errorf("issuer %q: want the tag of this registration", claims.IssuedFrom)
			}
		})
	}
}

// The storage routes need a database, so these lines are checked in source.
func TestReportedValuesStayOutOfLogLines(t *testing.T) {
	sites := map[string]*regexp.Regexp{
		"handlers/intelligence.go":               regexp.MustCompile(`Str\("value",\s*req\.IndicatorValue`),
		"handlers/admin.go":                      regexp.MustCompile(`Str\("indicator_value"`),
		"handlers/url.go":                        regexp.MustCompile(`Str\("url",\s*req\.URL\)\.Msg\("failed to persist URL report"`),
		"../domain/services/url_reputation.go":   regexp.MustCompile(`Str\("url",\s*reportURL\)`),
		"handlers/app_security.go":               regexp.MustCompile(`Str\("package",\s*req\.PackageName\)\.(Msg\("failed to save app report"|\s*Str\("type")`),
		"../domain/services/app_analyzer.go":     regexp.MustCompile(`Str\("package",\s*rec\.PackageName\)`),
		"../grpc/threatintel/server.go":          regexp.MustCompile(`Str\("value",\s*req\.IndicatorValue`),
		"../domain/services/network_security.go": regexp.MustCompile(`Str\("value",\s*raw\)`),
	}
	for file, field := range sites {
		source, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		if field.Match(source) {
			t.Errorf("%s logs a reported value", file)
		}
	}
}
