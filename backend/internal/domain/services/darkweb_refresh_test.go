package services_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
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

// These drive POST /api/v1/darkweb/refresh through the real route table, auth
// middleware, handler and monitor. Only the sweep and the lock are fakes, so no
// provider, database or Redis is ever contacted.

const (
	refreshDeviceKey  = "device-key-for-refresh-tests"
	refreshAdminToken = "refresh-test-admin-token-0123456789abcdef012345"
)

type refreshTokenStore struct{}

func (refreshTokenStore) GetJSON(_ context.Context, key string, dest any) error {
	if key != "auth:apikey:"+refreshDeviceKey {
		return errors.New("not found")
	}
	raw, err := json.Marshal(apimiddleware.TokenClaims{DeviceID: "dev-1", ExpiresAt: time.Now().Add(time.Hour)})
	if err != nil {
		return err
	}
	return json.Unmarshal(raw, dest)
}

type refreshNoLockout struct{}

func (refreshNoLockout) RecordFailure(context.Context, string, time.Duration) (int64, error) {
	return 1, nil
}
func (refreshNoLockout) FailureCount(context.Context, string) (int64, time.Duration, error) {
	return 0, 0, nil
}
func (refreshNoLockout) ClearFailures(context.Context, string) error { return nil }

// fakeRefreshLock behaves like the Redis SET NX lock.
type fakeRefreshLock struct {
	mu            sync.Mutex
	held          bool
	acquireErr    error
	acquires      int
	releases      int
	releaseCtxErr error
}

func (l *fakeRefreshLock) AcquireOwnedLock(context.Context, string, time.Duration) (string, bool, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.acquires++
	if l.acquireErr != nil {
		return "", false, l.acquireErr
	}
	if l.held {
		return "", false, nil
	}
	l.held = true
	return "fake-owner", true, nil
}

func (l *fakeRefreshLock) ReleaseOwnedLock(ctx context.Context, _, _ string) (bool, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.releases++
	l.releaseCtxErr = ctx.Err()
	l.held = false
	return true, nil
}

func (l *fakeRefreshLock) snapshot() (held bool, releases int) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.held, l.releases
}

func newRefreshMonitor(sweep func(context.Context) error, lock *fakeRefreshLock) *services.DarkWebMonitor {
	log := &logger.Logger{Logger: zerolog.Nop()}
	m := services.NewDarkWebMonitor(nil, nil, nil, nil, nil, log)
	m.SetRefreshForTest(sweep, lock)
	return m
}

func newRefreshRouter(t *testing.T, sweep func(context.Context) error, lock *fakeRefreshLock) http.Handler {
	t.Helper()
	log := &logger.Logger{Logger: zerolog.Nop()}
	apimiddleware.ConfigureAuth(refreshTokenStore{}, "test", log)
	apimiddleware.ConfigureAdminAuth(refreshAdminToken, refreshNoLockout{}, log)
	t.Cleanup(func() {
		apimiddleware.ConfigureAuth(nil, "", nil)
		apimiddleware.ConfigureAdminAuth("", nil, nil)
		apimiddleware.ConfigureOrbNetJWT("")
	})
	h := &handlers.Handlers{DarkWeb: handlers.NewDarkWebHandler(newRefreshMonitor(sweep, lock), log)}
	return api.NewRouter(config.Config{}, h, nil, log).Setup()
}

func postRefresh(h http.Handler, bearer, admin string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, "/api/v1/darkweb/refresh", nil)
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	if admin != "" {
		req.Header.Set("X-Admin-Token", admin)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestRefreshRequiresAdminAndRefusalsStartNoSweep(t *testing.T) {
	var sweeps atomic.Int32
	lock := &fakeRefreshLock{}
	h := newRefreshRouter(t, func(context.Context) error { sweeps.Add(1); return nil }, lock)

	refused := []struct {
		name          string
		bearer, admin string
		want          int
	}{
		{"no credential", "", "", http.StatusUnauthorized},
		{"device key", refreshDeviceKey, "", http.StatusForbidden},
		{"device key and wrong admin token", refreshDeviceKey, "wrong", http.StatusForbidden},
		{"admin token without bearer", "", refreshAdminToken, http.StatusUnauthorized},
	}
	for _, c := range refused {
		if rec := postRefresh(h, c.bearer, c.admin); rec.Code != c.want {
			t.Fatalf("%s: want %d, got %d: %s", c.name, c.want, rec.Code, rec.Body.String())
		}
	}
	if n := sweeps.Load(); n != 0 {
		t.Fatalf("a refused call started %d sweep(s)", n)
	}
	if lock.acquires != 0 {
		t.Fatalf("a refused call touched the lock %d time(s)", lock.acquires)
	}

	rec := postRefresh(h, refreshDeviceKey, refreshAdminToken)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "refreshed") {
		t.Fatalf("admin: want 200 refreshed, got %d: %s", rec.Code, rec.Body.String())
	}
	if n := sweeps.Load(); n != 1 {
		t.Fatalf("admin call: want 1 sweep, got %d", n)
	}
	if held, releases := lock.snapshot(); held || releases != 1 {
		t.Fatalf("lock after sweep: held=%v releases=%d", held, releases)
	}
}

func TestConcurrentRefreshStartsNoSecondSweep(t *testing.T) {
	var sweeps atomic.Int32
	started := make(chan struct{})
	finish := make(chan struct{})
	lock := &fakeRefreshLock{}
	h := newRefreshRouter(t, func(context.Context) error {
		if sweeps.Add(1) == 1 {
			close(started)
			<-finish
		}
		return nil
	}, lock)

	first := make(chan *httptest.ResponseRecorder, 1)
	go func() { first <- postRefresh(h, refreshDeviceKey, refreshAdminToken) }()
	select {
	case <-started:
	case <-time.After(5 * time.Second):
		t.Fatal("first sweep did not start")
	}

	var wg sync.WaitGroup
	codes := make([]int, 16)
	for i := range codes {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			codes[i] = postRefresh(h, refreshDeviceKey, refreshAdminToken).Code
		}(i)
	}
	wg.Wait()
	for i, code := range codes {
		if code != http.StatusConflict {
			t.Fatalf("concurrent call %d: want 409, got %d", i, code)
		}
	}
	if n := sweeps.Load(); n != 1 {
		t.Fatalf("want 1 sweep while one runs, got %d", n)
	}
	if held, releases := lock.snapshot(); !held || releases != 0 {
		t.Fatalf("a refused call disturbed the running sweep's lock: held=%v releases=%d", held, releases)
	}

	close(finish)
	if rec := <-first; rec.Code != http.StatusOK {
		t.Fatalf("first call: want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// The gate opens again once the sweep is over.
	if rec := postRefresh(h, refreshDeviceKey, refreshAdminToken); rec.Code != http.StatusOK {
		t.Fatalf("call after the sweep ended: want 200, got %d", rec.Code)
	}
	if n := sweeps.Load(); n != 2 {
		t.Fatalf("want 2 sweeps in total, got %d", n)
	}
}

// Without a shared lock the in-process gate alone must hold.
func TestConcurrentRefreshWithoutSharedLock(t *testing.T) {
	var sweeps atomic.Int32
	started := make(chan struct{})
	finish := make(chan struct{})
	m := newRefreshMonitor(nil, nil)
	m.SetRefreshForTest(func(context.Context) error {
		sweeps.Add(1)
		close(started)
		<-finish
		return nil
	}, nil)

	first := make(chan error, 1)
	go func() { first <- m.RefreshMonitoredAssets(context.Background()) }()
	<-started
	if err := m.RefreshMonitoredAssets(context.Background()); !errors.Is(err, services.ErrRefreshInProgress) {
		t.Fatalf("second call: want ErrRefreshInProgress, got %v", err)
	}
	close(finish)
	if err := <-first; err != nil {
		t.Fatalf("first call: %v", err)
	}
	if n := sweeps.Load(); n != 1 {
		t.Fatalf("want 1 sweep, got %d", n)
	}
}

func TestRefreshRunningOnAnotherReplicaIsRefused(t *testing.T) {
	var sweeps atomic.Int32
	lock := &fakeRefreshLock{held: true}
	h := newRefreshRouter(t, func(context.Context) error { sweeps.Add(1); return nil }, lock)

	if rec := postRefresh(h, refreshDeviceKey, refreshAdminToken); rec.Code != http.StatusConflict {
		t.Fatalf("want 409, got %d: %s", rec.Code, rec.Body.String())
	}
	if n := sweeps.Load(); n != 0 {
		t.Fatalf("started %d sweep(s) while another replica holds the lock", n)
	}
	if held, releases := lock.snapshot(); !held || releases != 0 {
		t.Fatalf("the other replica's lock was released: held=%v releases=%d", held, releases)
	}
}

func TestRefreshLockFailureStartsNoSweep(t *testing.T) {
	var sweeps atomic.Int32
	lock := &fakeRefreshLock{acquireErr: errors.New("redis unavailable")}
	h := newRefreshRouter(t, func(context.Context) error { sweeps.Add(1); return nil }, lock)

	rec := postRefresh(h, refreshDeviceKey, refreshAdminToken)
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("want 500, got %d: %s", rec.Code, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "redis") {
		t.Fatalf("the lock error reached the client: %s", rec.Body.String())
	}
	if n := sweeps.Load(); n != 0 {
		t.Fatalf("started %d sweep(s) without the lock", n)
	}

	// The in-process gate did not stay shut after the failure.
	lock.mu.Lock()
	lock.acquireErr = nil
	lock.mu.Unlock()
	if rec := postRefresh(h, refreshDeviceKey, refreshAdminToken); rec.Code != http.StatusOK {
		t.Fatalf("after the lock recovered: want 200, got %d", rec.Code)
	}
}

func TestRefreshReleasesLockAfterRequestContextEnds(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	lock := &fakeRefreshLock{}
	sweepErr := errors.New("sweep failed")
	m := newRefreshMonitor(func(context.Context) error { cancel(); return sweepErr }, lock)

	if err := m.RefreshMonitoredAssets(ctx); !errors.Is(err, sweepErr) {
		t.Fatalf("want the sweep's error, got %v", err)
	}
	lock.mu.Lock()
	defer lock.mu.Unlock()
	if lock.held || lock.releases != 1 {
		t.Fatalf("lock not released: held=%v releases=%d", lock.held, lock.releases)
	}
	if lock.releaseCtxErr != nil {
		t.Fatalf("release used the cancelled request context: %v", lock.releaseCtxErr)
	}
}

func TestRefreshWithoutStorageStillReportsIt(t *testing.T) {
	log := &logger.Logger{Logger: zerolog.Nop()}
	m := services.NewDarkWebMonitor(nil, nil, nil, nil, nil, log)
	if err := m.RefreshMonitoredAssets(context.Background()); !errors.Is(err, services.ErrDarkWebStorageUnavailable) {
		t.Fatalf("want ErrDarkWebStorageUnavailable, got %v", err)
	}
}
