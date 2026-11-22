package middleware

import (
	"net/http"
	"testing"
)

func TestOptionalAdmin(t *testing.T) {
	configureAdmin(t, strongToken, newMemLockout())
	var reached, admin bool
	h := OptionalAdmin(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reached, admin = true, IsAdmin(r.Context())
		w.WriteHeader(http.StatusOK)
	}))

	cases := []struct {
		name, token  string
		code         int
		reach, admin bool
	}{
		{"no header: served, not admin", "", http.StatusOK, true, false},
		{"right token: served as admin", strongToken, http.StatusOK, true, true},
		{"wrong token: refused like any admin route", strongToken + "x", http.StatusForbidden, false, false},
	}
	for i, c := range cases {
		reached, admin = false, false
		rec := serve(h, adminReq(http.MethodGet, "/api/v1/sources", "10.0.9."+string(rune('1'+i))+":1", c.token, ""))
		if rec.Code != c.code || reached != c.reach || admin != c.admin {
			t.Errorf("%s: code=%d reached=%v admin=%v", c.name, rec.Code, reached, admin)
		}
	}
}
