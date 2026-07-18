package middleware

import (
	"context"
	"net/http"

	"github.com/go-chi/chi/v5"
)

// OwnerLookup resolves the OrbNet account that owns a device. ownerID is nil
// when the device is unclaimed; found is false when it does not exist.
type OwnerLookup func(ctx context.Context, deviceID string) (ownerID *int64, found bool, err error)

// DeviceOwnership guards per-device routes (`/device/{device_id}/…`). It admits
// three legitimate callers and rejects everyone else:
//
//   - S2S (shared secret) — internal callers, always allowed.
//   - the device itself (device-key auth) — allowed only for its OWN device_id
//     (a pure string compare, so the app's existing self-reporting never hits
//     the database and cannot be broken by it).
//   - an OrbNet account (JWT auth) — allowed only for a device it OWNS; an
//     unclaimed or someone-else's device is reported as 404 (never revealing
//     that it exists).
//
// Routes without a {device_id} param (registration, reference data, the
// my-devices list, and the claim bootstrap) pass straight through — this guard
// is only about acting on an already-identified device.
func DeviceOwnership(lookup OwnerLookup) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			deviceID := chi.URLParam(r, "device_id")
			if deviceID == "" {
				next.ServeHTTP(w, r)
				return
			}
			ctx := r.Context()

			// Internal service-to-service calls are trusted.
			if isService, _ := ctx.Value(ContextKeyIsService).(bool); isService {
				next.ServeHTTP(w, r)
				return
			}

			// The device acting for itself: allow only its own id.
			if devID, _ := ctx.Value(ContextKeyDeviceID).(string); devID != "" {
				if devID == deviceID {
					next.ServeHTTP(w, r)
					return
				}
				forbidden(w, "this credential cannot act on another device")
				return
			}

			// An OrbNet account: allow only a device it owns.
			if uid, ok := ctx.Value(ContextKeyOrbNetUserID).(int64); ok && uid > 0 {
				ownerID, found, err := lookup(ctx, deviceID)
				if err != nil {
					http.Error(w, `{"error":"ownership check failed"}`, http.StatusInternalServerError)
					return
				}
				// Unclaimed, unknown, or owned by someone else all read as 404 so
				// the endpoint never leaks which device ids exist or are claimed.
				if !found || ownerID == nil || *ownerID != uid {
					http.Error(w, `{"error":"device not found"}`, http.StatusNotFound)
					return
				}
				next.ServeHTTP(w, r)
				return
			}

			forbidden(w, "authentication required to act on this device")
		})
	}
}

func forbidden(w http.ResponseWriter, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusForbidden)
	_, _ = w.Write([]byte(`{"error":"` + msg + `"}`))
}

// RequireOrbNetSubscription gates remote-control actions behind an active
// subscription — but ONLY for OrbNet-account (web) callers. Remote control +
// camera are premium (a locked product decision), so a free account gets 402.
// The device acting for itself and internal S2S callers are never gated: the
// phone must always be able to report in, and internal jobs are trusted.
func RequireOrbNetSubscription(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		// Only OrbNet-JWT callers are subject to the premium gate.
		if uid, ok := ctx.Value(ContextKeyOrbNetUserID).(int64); ok && uid > 0 {
			valid, _ := ctx.Value(ContextKeySubscriptionValid).(bool)
			if !valid {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusPaymentRequired)
				_, _ = w.Write([]byte(`{"error":"remote control is a premium feature — subscribe to lock, wipe, ring or locate from the web"}`))
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}
