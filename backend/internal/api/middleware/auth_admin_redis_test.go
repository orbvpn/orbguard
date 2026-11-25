package middleware

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"orbguard-lab/internal/config"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/pkg/logger"
)

// These run AdminAuth against the store production uses, a real Redis named
// by ORBGUARD_TEST_REDIS_ADDR (host:port) under a unique key prefix; without
// it they skip. The in-memory fake elsewhere in this package pins the policy,
// these pin that *cache.RedisCache gives the policy the semantics it assumes.
func testRedisLockout(t *testing.T) *cache.RedisCache {
	t.Helper()
	addr := os.Getenv("ORBGUARD_TEST_REDIS_ADDR")
	if addr == "" {
		t.Skip("ORBGUARD_TEST_REDIS_ADDR not set; skipping Redis-backed test")
	}
	host, portStr, err := net.SplitHostPort(addr)
	if err != nil {
		t.Fatalf("ORBGUARD_TEST_REDIS_ADDR must be host:port, got %q", addr)
	}
	port, err := strconv.Atoi(portStr)
	if err != nil {
		t.Fatalf("ORBGUARD_TEST_REDIS_ADDR port: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	c, err := cache.NewRedis(ctx, config.RedisConfig{
		Host:      host,
		Port:      port,
		KeyPrefix: fmt.Sprintf("orbguard-test:%d:", time.Now().UnixNano()),
	}, logger.NewDefault())
	if err != nil {
		t.Fatalf("connect to test Redis: %v", err)
	}
	t.Cleanup(func() { _ = c.Close() })
	return c
}

func TestAdminAuthLockoutWithRedis(t *testing.T) {
	c := testRedisLockout(t)
	configureAdmin(t, strongToken, c)
	h, reached := adminHandler(t)
	const attacker, other = "203.0.113.200", "198.51.100.201"
	t.Cleanup(func() {
		_ = c.Delete(context.Background(), adminLockoutKeyPrefix+attacker, adminLockoutKeyPrefix+other)
	})

	for i := 1; i < adminLockoutThreshold; i++ {
		if rec := serve(h, adminReq(http.MethodPost, "/admin/x", attacker+":1", "wrong", "")); rec.Code != http.StatusForbidden {
			t.Fatalf("failure %d: want 403, got %d", i, rec.Code)
		}
	}
	rec := serve(h, adminReq(http.MethodPost, "/admin/x", attacker+":1", "wrong", ""))
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("failure %d: want 429, got %d", adminLockoutThreshold, rec.Code)
	}
	if secs, err := strconv.Atoi(rec.Header().Get("Retry-After")); err != nil || secs < 1 || secs > int(adminLockoutWindow/time.Second) {
		t.Fatalf("Retry-After must be within the 15 minute window, got %q", rec.Header().Get("Retry-After"))
	}

	// Locked: the next request is refused on the stored count alone, with
	// the time Redis has left on the key.
	*reached = false
	rec = serve(h, adminReq(http.MethodPost, "/admin/x", attacker+":1", strongToken, ""))
	if rec.Code != http.StatusTooManyRequests || *reached {
		t.Fatalf("correct token while locked: want 429, got %d reached=%v", rec.Code, *reached)
	}
	secs, err := strconv.Atoi(rec.Header().Get("Retry-After"))
	if err != nil || secs < int(adminLockoutWindow/time.Second)-5 || secs > int(adminLockoutWindow/time.Second) {
		t.Fatalf("Retry-After should be the key's remaining TTL (~900s), got %q", rec.Header().Get("Retry-After"))
	}

	// A successful call from another address leaves no counter behind.
	if rec := serve(h, adminReq(http.MethodPost, "/admin/x", other+":1", "typo", "")); rec.Code != http.StatusForbidden {
		t.Fatalf("typo from other address: want 403, got %d", rec.Code)
	}
	if rec := serve(h, adminReq(http.MethodPost, "/admin/x", other+":1", strongToken, "")); rec.Code != http.StatusOK {
		t.Fatalf("correct token from other address: want 200, got %d", rec.Code)
	}
	if n, _, err := c.FailureCount(context.Background(), adminLockoutKeyPrefix+other); err != nil || n != 0 {
		t.Fatalf("success must delete the counter: count %d err %v", n, err)
	}
}

func TestAdminAuthHealsRedisCounterWithoutExpiry(t *testing.T) {
	c := testRedisLockout(t)
	buf := configureAdmin(t, strongToken, c)
	h, reached := adminHandler(t)
	ctx := context.Background()
	const ip = "192.0.2.202"
	key := adminLockoutKeyPrefix + ip
	t.Cleanup(func() { _ = c.Delete(ctx, key) })

	// Past the threshold and without a TTL: the state an INCR whose EXPIRE
	// was lost would leave. Treated as a lock it would never lapse, because
	// the correct token is refused while locked and nothing else clears it.
	if err := c.Set(ctx, key, strconv.Itoa(adminLockoutThreshold+4), 0); err != nil {
		t.Fatalf("seed: %v", err)
	}
	rec := serve(h, adminReq(http.MethodPost, "/admin/x", ip+":1", strongToken, ""))
	if rec.Code != http.StatusOK || !*reached {
		t.Fatalf("correct token against a counter without expiry: want 200, got %d reached=%v", rec.Code, *reached)
	}
	if n, remaining, err := c.FailureCount(ctx, key); err != nil || n != 0 || remaining != 0 {
		t.Fatalf("the damaged counter must be gone: (%d, %s, %v)", n, remaining, err)
	}
	if !strings.Contains(buf.String(), "had no expiry") {
		t.Fatalf("the repair must be logged:\n%s", buf.String())
	}

	// Below the threshold the same damage heals on the next failure, which
	// gives the key its window back.
	if err := c.Set(ctx, key, "2", 0); err != nil {
		t.Fatalf("seed: %v", err)
	}
	if rec := serve(h, adminReq(http.MethodPost, "/admin/x", ip+":1", "wrong", "")); rec.Code != http.StatusForbidden {
		t.Fatalf("wrong token: want 403, got %d", rec.Code)
	}
	n, remaining, err := c.FailureCount(ctx, key)
	if err != nil || n != 3 || remaining <= 0 || remaining > adminLockoutWindow {
		t.Fatalf("next failure must count and re-arm the window: (%d, %s, %v)", n, remaining, err)
	}
}
