package cache

import (
	"context"
	"fmt"
	"net"
	"os"
	"strconv"
	"testing"
	"time"

	"orbguard-lab/internal/config"
	"orbguard-lab/pkg/logger"
)

// testRedis connects to the Redis named by ORBGUARD_TEST_REDIS_ADDR
// (host:port) under a unique key prefix, or skips the test. The admin lockout
// behind AdminAuth depends on these exact semantics, so they are checked
// against a real server rather than a fake.
func testRedis(t *testing.T) *RedisCache {
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
	c, err := NewRedis(ctx, config.RedisConfig{
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

func TestFailureCounter(t *testing.T) {
	c := testRedis(t)
	ctx := context.Background()
	const key = "auth:admin:fail:203.0.113.9"
	t.Cleanup(func() { _ = c.Delete(ctx, key) })

	count, remaining, err := c.FailureCount(ctx, key)
	if err != nil || count != 0 || remaining != 0 {
		t.Fatalf("fresh key: want (0, 0, nil), got (%d, %s, %v)", count, remaining, err)
	}

	for want := int64(1); want <= 3; want++ {
		got, err := c.RecordFailure(ctx, key, time.Minute)
		if err != nil || got != want {
			t.Fatalf("RecordFailure #%d: want %d, got %d (err %v)", want, want, got, err)
		}
	}

	count, remaining, err = c.FailureCount(ctx, key)
	if err != nil || count != 3 {
		t.Fatalf("after 3 failures: want count 3, got %d (err %v)", count, err)
	}
	if remaining <= 0 || remaining > time.Minute {
		t.Fatalf("remaining window must be within (0, 1m], got %s", remaining)
	}

	if err := c.ClearFailures(ctx, key); err != nil {
		t.Fatalf("ClearFailures: %v", err)
	}
	count, remaining, err = c.FailureCount(ctx, key)
	if err != nil || count != 0 || remaining != 0 {
		t.Fatalf("after clear: want (0, 0, nil), got (%d, %s, %v)", count, remaining, err)
	}
}

func TestFailureCounterWindowReArmsAndExpires(t *testing.T) {
	c := testRedis(t)
	ctx := context.Background()
	const key = "auth:admin:fail:198.51.100.7"
	t.Cleanup(func() { _ = c.Delete(ctx, key) })

	if _, err := c.RecordFailure(ctx, key, time.Second); err != nil {
		t.Fatalf("RecordFailure: %v", err)
	}
	// A later failure re-arms the window: the lock holds after the LAST
	// failure, so the TTL must be back near the full second.
	time.Sleep(600 * time.Millisecond)
	if _, err := c.RecordFailure(ctx, key, time.Second); err != nil {
		t.Fatalf("RecordFailure: %v", err)
	}
	count, remaining, err := c.FailureCount(ctx, key)
	if err != nil || count != 2 {
		t.Fatalf("want count 2, got %d (err %v)", count, err)
	}
	if remaining < 700*time.Millisecond {
		t.Fatalf("second failure must re-arm the window; remaining only %s", remaining)
	}

	// And the counter vanishes once the window closes.
	time.Sleep(1200 * time.Millisecond)
	count, remaining, err = c.FailureCount(ctx, key)
	if err != nil || count != 0 || remaining != 0 {
		t.Fatalf("after expiry: want (0, 0, nil), got (%d, %s, %v)", count, remaining, err)
	}
}

// TestFailureCounterWithoutExpiry covers the damaged state a half-applied
// INCR (count written, EXPIRE lost) would leave: FailureCount must report it
// with a negative duration rather than as a lock about to lapse, and the next
// RecordFailure must give the key an expiry again.
func TestFailureCounterWithoutExpiry(t *testing.T) {
	c := testRedis(t)
	ctx := context.Background()
	const key = "auth:admin:fail:192.0.2.66"
	t.Cleanup(func() { _ = c.Delete(ctx, key) })

	if err := c.Set(ctx, key, "7", 0); err != nil {
		t.Fatalf("seed counter without expiry: %v", err)
	}
	count, remaining, err := c.FailureCount(ctx, key)
	if err != nil || count != 7 {
		t.Fatalf("want count 7, got %d (err %v)", count, err)
	}
	if remaining >= 0 {
		t.Fatalf("a counter without expiry must report a negative duration, got %s", remaining)
	}

	got, err := c.RecordFailure(ctx, key, time.Minute)
	if err != nil || got != 8 {
		t.Fatalf("RecordFailure on the damaged key: want 8, got %d (err %v)", got, err)
	}
	count, remaining, err = c.FailureCount(ctx, key)
	if err != nil || count != 8 || remaining <= 0 || remaining > time.Minute {
		t.Fatalf("RecordFailure must re-arm the expiry: got (%d, %s, %v)", count, remaining, err)
	}

	if err := c.ClearFailures(ctx, key); err != nil {
		t.Fatalf("ClearFailures: %v", err)
	}
	if count, remaining, err = c.FailureCount(ctx, key); err != nil || count != 0 || remaining != 0 {
		t.Fatalf("after clear: want (0, 0, nil), got (%d, %s, %v)", count, remaining, err)
	}
}
