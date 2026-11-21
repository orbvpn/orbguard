package services_test

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/rs/zerolog"

	"orbguard-lab/internal/config"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/pkg/logger"
)

// Two monitors sharing one real Redis stand in for two replicas. Runs only when
// ORBGUARD_TEST_REDIS_ADDR (host:port) names a test Redis.
func TestRefreshLockHoldsAcrossReplicasOnRealRedis(t *testing.T) {
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
	log := &logger.Logger{Logger: zerolog.Nop()}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	redisCache, err := cache.NewRedis(ctx, config.RedisConfig{
		Host:      host,
		Port:      port,
		KeyPrefix: fmt.Sprintf("orbguard-test:%d:", time.Now().UnixNano()),
	}, log)
	if err != nil {
		t.Fatalf("connect to test Redis: %v", err)
	}
	t.Cleanup(func() { _ = redisCache.Close() })

	started := make(chan struct{})
	finish := make(chan struct{})
	replicaA := services.NewDarkWebMonitor(nil, nil, nil, nil, redisCache, log)
	replicaA.SetRefreshForTest(func(context.Context) error {
		close(started)
		<-finish
		return nil
	}, redisCache)

	var replicaBSweeps int
	replicaB := services.NewDarkWebMonitor(nil, nil, nil, nil, redisCache, log)
	replicaB.SetRefreshForTest(func(context.Context) error { replicaBSweeps++; return nil }, redisCache)

	first := make(chan error, 1)
	go func() { first <- replicaA.RefreshMonitoredAssets(ctx) }()
	select {
	case <-started:
	case <-ctx.Done():
		t.Fatal("first sweep did not start")
	}

	ttl, err := redisCache.TTL(ctx, cache.KeySchedulerLock+"darkweb:refresh")
	if err != nil || ttl <= 0 || ttl > 10*time.Minute {
		t.Fatalf("the lock must carry a TTL of at most 10 minutes, got %v (err %v)", ttl, err)
	}
	if err := replicaB.RefreshMonitoredAssets(ctx); !errors.Is(err, services.ErrRefreshInProgress) {
		t.Fatalf("other replica during a sweep: want ErrRefreshInProgress, got %v", err)
	}
	if replicaBSweeps != 0 {
		t.Fatalf("other replica started %d sweep(s)", replicaBSweeps)
	}

	close(finish)
	if err := <-first; err != nil {
		t.Fatalf("first sweep: %v", err)
	}
	if err := replicaB.RefreshMonitoredAssets(ctx); err != nil {
		t.Fatalf("other replica after the sweep ended: %v", err)
	}
	if replicaBSweeps != 1 {
		t.Fatalf("other replica: want 1 sweep after the lock was released, got %d", replicaBSweeps)
	}
}

// A sweep that outlives the lock TTL must leave the next holder's lock alone.
func TestRefreshReleaseKeepsANewerHoldersLock(t *testing.T) {
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
	log := &logger.Logger{Logger: zerolog.Nop()}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	redisCache, err := cache.NewRedis(ctx, config.RedisConfig{
		Host:      host,
		Port:      port,
		KeyPrefix: fmt.Sprintf("orbguard-test:%d:", time.Now().UnixNano()),
	}, log)
	if err != nil {
		t.Fatalf("connect to test Redis: %v", err)
	}
	t.Cleanup(func() { _ = redisCache.Close() })

	lockKey := cache.KeySchedulerLock + "darkweb:refresh"
	m := services.NewDarkWebMonitor(nil, nil, nil, nil, redisCache, log)
	m.SetRefreshForTest(func(context.Context) error {
		// The sweep outlived its TTL and another replica now holds the lock.
		if err := redisCache.Delete(ctx, lockKey); err != nil {
			return err
		}
		return redisCache.Set(ctx, lockKey, "newer-holder", time.Minute)
	}, redisCache)

	if err := m.RefreshMonitoredAssets(ctx); err != nil {
		t.Fatalf("refresh: %v", err)
	}
	got, err := redisCache.Get(ctx, lockKey)
	if err != nil || got != "newer-holder" {
		t.Fatalf("the newer holder's lock must survive the old holder's release, got %q (err %v)", got, err)
	}
}
