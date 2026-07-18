package middleware

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-chi/chi/v5"
)

// ownedBy makes a lookup that reports the device owned by ownerID (nil =
// unclaimed, missing=true → device does not exist).
func ownedBy(ownerID *int64, missing bool) OwnerLookup {
	return func(ctx context.Context, deviceID string) (*int64, bool, error) {
		if missing {
			return nil, false, nil
		}
		return ownerID, true, nil
	}
}

// run drives the DeviceOwnership guard for a request to /device/{id}/lock with
// the given context values, returning the resulting status (200 = allowed).
func run(t *testing.T, deviceID string, lookup OwnerLookup, seed func(ctx context.Context) context.Context) int {
	t.Helper()
	reached := false
	h := DeviceOwnership(lookup)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reached = true
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodPost, "/device/"+deviceID+"/lock", nil)
	rctx := chi.NewRouteContext()
	if deviceID != "" {
		rctx.URLParams.Add("device_id", deviceID)
	}
	ctx := context.WithValue(req.Context(), chi.RouteCtxKey, rctx)
	if seed != nil {
		ctx = seed(ctx)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req.WithContext(ctx))
	if rec.Code == http.StatusOK && !reached {
		t.Fatal("200 but handler not reached")
	}
	return rec.Code
}

func i64(v int64) *int64 { return &v }

func TestDeviceOwnership(t *testing.T) {
	owner := int64(7)

	t.Run("service caller is always allowed", func(t *testing.T) {
		code := run(t, "dev-1", ownedBy(i64(owner), false), func(ctx context.Context) context.Context {
			return context.WithValue(ctx, ContextKeyIsService, true)
		})
		if code != http.StatusOK {
			t.Fatalf("want 200, got %d", code)
		}
	})

	t.Run("device acting for its own id is allowed", func(t *testing.T) {
		code := run(t, "dev-1", ownedBy(i64(owner), false), func(ctx context.Context) context.Context {
			return context.WithValue(ctx, ContextKeyDeviceID, "dev-1")
		})
		if code != http.StatusOK {
			t.Fatalf("want 200, got %d", code)
		}
	})

	t.Run("device acting for a DIFFERENT id is forbidden", func(t *testing.T) {
		code := run(t, "dev-2", ownedBy(i64(owner), false), func(ctx context.Context) context.Context {
			return context.WithValue(ctx, ContextKeyDeviceID, "dev-1")
		})
		if code != http.StatusForbidden {
			t.Fatalf("want 403, got %d", code)
		}
	})

	t.Run("owner account is allowed", func(t *testing.T) {
		code := run(t, "dev-1", ownedBy(i64(owner), false), func(ctx context.Context) context.Context {
			return context.WithValue(ctx, ContextKeyOrbNetUserID, owner)
		})
		if code != http.StatusOK {
			t.Fatalf("want 200, got %d", code)
		}
	})

	t.Run("non-owner account gets 404 (no existence leak)", func(t *testing.T) {
		code := run(t, "dev-1", ownedBy(i64(owner), false), func(ctx context.Context) context.Context {
			return context.WithValue(ctx, ContextKeyOrbNetUserID, int64(999))
		})
		if code != http.StatusNotFound {
			t.Fatalf("want 404, got %d", code)
		}
	})

	t.Run("account cannot act on an unclaimed device", func(t *testing.T) {
		code := run(t, "dev-1", ownedBy(nil, false), func(ctx context.Context) context.Context {
			return context.WithValue(ctx, ContextKeyOrbNetUserID, owner)
		})
		if code != http.StatusNotFound {
			t.Fatalf("want 404 for unclaimed, got %d", code)
		}
	})

	t.Run("unknown device is 404", func(t *testing.T) {
		code := run(t, "ghost", ownedBy(nil, true), func(ctx context.Context) context.Context {
			return context.WithValue(ctx, ContextKeyOrbNetUserID, owner)
		})
		if code != http.StatusNotFound {
			t.Fatalf("want 404, got %d", code)
		}
	})

	t.Run("no identity is forbidden", func(t *testing.T) {
		code := run(t, "dev-1", ownedBy(i64(owner), false), nil)
		if code != http.StatusForbidden {
			t.Fatalf("want 403, got %d", code)
		}
	})

	t.Run("route without a device_id passes through", func(t *testing.T) {
		// e.g. /device/register — no ownership concept.
		code := run(t, "", ownedBy(nil, true), nil)
		if code != http.StatusOK {
			t.Fatalf("want 200 passthrough, got %d", code)
		}
	})
}

func TestRequireOrbNetSubscription(t *testing.T) {
	guard := RequireOrbNetSubscription(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	call := func(seed func(ctx context.Context) context.Context) int {
		req := httptest.NewRequest(http.MethodPost, "/device/dev-1/lock", nil)
		ctx := req.Context()
		if seed != nil {
			ctx = seed(ctx)
		}
		rec := httptest.NewRecorder()
		guard.ServeHTTP(rec, req.WithContext(ctx))
		return rec.Code
	}

	t.Run("subscribed account passes", func(t *testing.T) {
		code := call(func(ctx context.Context) context.Context {
			ctx = context.WithValue(ctx, ContextKeyOrbNetUserID, int64(7))
			return context.WithValue(ctx, ContextKeySubscriptionValid, true)
		})
		if code != http.StatusOK {
			t.Fatalf("want 200, got %d", code)
		}
	})

	t.Run("free account is blocked with 402", func(t *testing.T) {
		code := call(func(ctx context.Context) context.Context {
			ctx = context.WithValue(ctx, ContextKeyOrbNetUserID, int64(7))
			return context.WithValue(ctx, ContextKeySubscriptionValid, false)
		})
		if code != http.StatusPaymentRequired {
			t.Fatalf("want 402, got %d", code)
		}
	})

	t.Run("device self-report is never gated", func(t *testing.T) {
		code := call(func(ctx context.Context) context.Context {
			return context.WithValue(ctx, ContextKeyDeviceID, "dev-1")
		})
		if code != http.StatusOK {
			t.Fatalf("want 200 (device exempt), got %d", code)
		}
	})
}
