package handlers

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

// POST /api/v1/auth/device is public and takes device_id on trust, and
// DeviceOwnership then admits any credential whose device_id matches. So the
// only thing standing between an attacker and someone else's thief selfies,
// location history and mark-stolen/lock/wipe is that a CLAIMED device cannot
// be re-registered without proof that the caller already holds its key.
//
// These cover every branch that resolves before the Redis lookup; the
// key-matches-device path needs a live cache and is exercised in integration.
func TestCallerHoldsDeviceKey(t *testing.T) {
	const serviceSecret = "service-secret-value"

	newReq := func(authHeader string) *http.Request {
		r := httptest.NewRequest(http.MethodPost, "/api/v1/auth/device", nil)
		if authHeader != "" {
			r.Header.Set("Authorization", authHeader)
		}
		return r
	}

	tests := []struct {
		name   string
		secret string
		header string
		want   bool
	}{
		{
			name:   "no authorization header is not proof of possession",
			secret: serviceSecret,
			want:   false,
		},
		{
			name:   "bare token without the Bearer scheme is rejected",
			secret: serviceSecret,
			header: serviceSecret,
			want:   false,
		},
		{
			name:   "Bearer with an empty token is rejected",
			secret: serviceSecret,
			header: "Bearer ",
			want:   false,
		},
		{
			name:   "the configured service secret is accepted",
			secret: serviceSecret,
			header: "Bearer " + serviceSecret,
			want:   true,
		},
		{
			name:   "the scheme match is case-insensitive, per RFC 7235",
			secret: serviceSecret,
			header: "bearer " + serviceSecret,
			want:   true,
		},
		{
			name: "an empty configured secret never matches an empty-ish token",
			// Guards against "" == "" letting any caller through when the
			// service secret is not configured.
			secret: "",
			header: "Bearer x",
			want:   false,
		},
		{
			name:   "an unknown token with no cache wired is rejected, not fatal",
			secret: serviceSecret,
			header: "Bearer some-other-devices-key",
			want:   false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			h := &AuthHandler{secret: tc.secret} // nil cache: must not panic
			if got := h.callerHoldsDeviceKey(newReq(tc.header), "device-abc"); got != tc.want {
				t.Fatalf("callerHoldsDeviceKey = %v, want %v", got, tc.want)
			}
		})
	}
}
