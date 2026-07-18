package middleware

import (
	"strings"
	"sync"

	"github.com/golang-jwt/jwt/v5"
)

// OrbNet JWT verification.
//
// OrbGuard has no account system of its own (its Login is a 501 stub) — user
// identity comes from OrbNet, the shared OrbVPN account backend. OrbNet signs
// its access tokens HS256 with a secret we also hold (ORBNET_JWT_ACCESS_SECRET,
// same value on both services). When that secret is configured, APIKeyAuth also
// accepts a valid OrbNet JWT as a credential and records the account user_id, so
// the web panel (and a logged-in app) can act as the authenticated user for the
// device-ownership routes. If the secret is empty, this path is inert and the
// only accepted credentials remain the device key / session token / S2S secret.

// orbNetIssuer is OrbNet's fixed access-token issuer (a protocol constant, not
// OrbGuard config — OrbGuard signs its own tokens with a different issuer).
const orbNetIssuer = "orbnet"

var (
	orbnetJWTMu     sync.RWMutex
	orbnetJWTSecret []byte
)

// ConfigureOrbNetJWT wires the shared OrbNet access-token secret. Called once at
// startup. An empty secret disables OrbNet-JWT auth entirely.
func ConfigureOrbNetJWT(secret string) {
	orbnetJWTMu.Lock()
	defer orbnetJWTMu.Unlock()
	orbnetJWTSecret = []byte(secret)
}

// OrbNetClaims is the subset of OrbNet's access-token claims OrbGuard reads.
// user_id is the account identity used for device ownership; subscription_valid
// gates premium remote-control actions.
type OrbNetClaims struct {
	UserID            int64  `json:"user_id"`
	Role              string `json:"role"`
	SubscriptionValid bool   `json:"subscription_valid"`
	jwt.RegisteredClaims
}

// verifyOrbNetJWT verifies tokenStr as an OrbNet access token. It returns the
// claims only when the signature (HS256), issuer, and expiry all check out.
// Returns (nil, false) when OrbNet-JWT auth is unconfigured or the token is not
// a valid OrbNet JWT — so a non-JWT device key simply falls through unharmed.
func verifyOrbNetJWT(tokenStr string) (*OrbNetClaims, bool) {
	orbnetJWTMu.RLock()
	secret := orbnetJWTSecret
	orbnetJWTMu.RUnlock()

	if len(secret) == 0 {
		return nil, false
	}
	// Cheap structural reject before the crypto: an opaque device key / session
	// token is not a three-segment JWT.
	if strings.Count(tokenStr, ".") != 2 {
		return nil, false
	}

	claims := &OrbNetClaims{}
	parser := jwt.NewParser(
		jwt.WithValidMethods([]string{"HS256"}), // pin the alg — no "none"/RS confusion
		jwt.WithIssuer(orbNetIssuer),
		jwt.WithExpirationRequired(),
	)
	token, err := parser.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (interface{}, error) {
		return secret, nil
	})
	if err != nil || !token.Valid {
		return nil, false
	}
	if claims.UserID <= 0 {
		return nil, false
	}
	return claims, true
}
