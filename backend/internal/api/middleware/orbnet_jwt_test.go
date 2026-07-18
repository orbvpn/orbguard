package middleware

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const testSecret = "shared-orbnet-secret-value"

// mint signs an OrbNet-style access token for tests.
func mint(t *testing.T, secret string, mutate func(c *OrbNetClaims)) string {
	t.Helper()
	claims := &OrbNetClaims{
		UserID:            42,
		Role:              "USER",
		SubscriptionValid: true,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    orbNetIssuer,
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	if mutate != nil {
		mutate(claims)
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	s, err := tok.SignedString([]byte(secret))
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	return s
}

func TestVerifyOrbNetJWT(t *testing.T) {
	ConfigureOrbNetJWT(testSecret)
	t.Cleanup(func() { ConfigureOrbNetJWT("") })

	t.Run("valid token", func(t *testing.T) {
		claims, ok := verifyOrbNetJWT(mint(t, testSecret, nil))
		if !ok {
			t.Fatal("expected valid")
		}
		if claims.UserID != 42 || !claims.SubscriptionValid {
			t.Fatalf("bad claims: %+v", claims)
		}
	})

	t.Run("wrong secret is rejected", func(t *testing.T) {
		if _, ok := verifyOrbNetJWT(mint(t, "attacker-secret", nil)); ok {
			t.Fatal("token signed with the wrong secret must be rejected")
		}
	})

	t.Run("wrong issuer is rejected", func(t *testing.T) {
		tok := mint(t, testSecret, func(c *OrbNetClaims) { c.Issuer = "someone-else" })
		if _, ok := verifyOrbNetJWT(tok); ok {
			t.Fatal("non-orbnet issuer must be rejected")
		}
	})

	t.Run("expired is rejected", func(t *testing.T) {
		tok := mint(t, testSecret, func(c *OrbNetClaims) {
			c.ExpiresAt = jwt.NewNumericDate(time.Now().Add(-time.Minute))
		})
		if _, ok := verifyOrbNetJWT(tok); ok {
			t.Fatal("expired token must be rejected")
		}
	})

	t.Run("missing expiry is rejected", func(t *testing.T) {
		tok := mint(t, testSecret, func(c *OrbNetClaims) { c.ExpiresAt = nil })
		if _, ok := verifyOrbNetJWT(tok); ok {
			t.Fatal("token without exp must be rejected")
		}
	})

	t.Run("non-positive user_id is rejected", func(t *testing.T) {
		tok := mint(t, testSecret, func(c *OrbNetClaims) { c.UserID = 0 })
		if _, ok := verifyOrbNetJWT(tok); ok {
			t.Fatal("token without a real user_id must be rejected")
		}
	})

	t.Run("opaque device key is not a JWT", func(t *testing.T) {
		if _, ok := verifyOrbNetJWT("dev_9f8c7b6a5e4d3c2b1a0"); ok {
			t.Fatal("a device key must never verify as a JWT")
		}
	})

	t.Run("alg none is rejected", func(t *testing.T) {
		tok := jwt.NewWithClaims(jwt.SigningMethodNone, &OrbNetClaims{
			UserID: 42,
			RegisteredClaims: jwt.RegisteredClaims{
				Issuer:    orbNetIssuer,
				ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
			},
		})
		s, _ := tok.SignedString(jwt.UnsafeAllowNoneSignatureType)
		if _, ok := verifyOrbNetJWT(s); ok {
			t.Fatal("alg=none must be rejected (algorithm confusion)")
		}
	})
}

func TestVerifyOrbNetJWT_Unconfigured(t *testing.T) {
	ConfigureOrbNetJWT("") // secret empty ⇒ path disabled
	if _, ok := verifyOrbNetJWT(mint(t, testSecret, nil)); ok {
		t.Fatal("with no secret configured, no JWT should be accepted")
	}
}
