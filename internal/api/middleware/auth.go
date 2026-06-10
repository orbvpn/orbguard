package middleware

import (
	"context"
	"crypto/subtle"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"orbguard-lab/pkg/logger"
)

// ContextKey is a type for context keys
type ContextKey string

const (
	// ContextKeyAPIKey is the context key for the API key
	ContextKeyAPIKey ContextKey = "api_key"
	// ContextKeyUserID is the context key for the user ID
	ContextKeyUserID ContextKey = "user_id"
	// ContextKeyDeviceID is the context key for the device ID
	ContextKeyDeviceID ContextKey = "device_id"
	// ContextKeyIsAdmin is the context key for admin status
	ContextKeyIsAdmin ContextKey = "is_admin"
	// ContextKeyIsService is the context key for service-to-service requests
	// authenticated with the configured shared secret.
	ContextKeyIsService ContextKey = "is_service"
)

// adminTokenEnvVar is the environment variable holding the admin credential.
// There is intentionally no default: if it is unset, admin routes are disabled.
const adminTokenEnvVar = "ORBGUARD_ADMIN_TOKEN"

// TokenClaims is the canonical payload stored in Redis for both session
// tokens (auth:token:<token>) and device API keys (auth:apikey:<key>).
// Handlers that issue credentials must store this exact shape so middleware
// lookups resolve identity consistently.
type TokenClaims struct {
	UserID    string    `json:"user_id,omitempty"`
	DeviceID  string    `json:"device_id,omitempty"`
	ExpiresAt time.Time `json:"expires_at,omitempty"`
}

// TokenStore is the read interface the auth middleware needs to validate
// tokens. *cache.RedisCache satisfies it.
type TokenStore interface {
	GetJSON(ctx context.Context, key string, dest any) error
}

var (
	authMu          sync.RWMutex
	authStore       TokenStore
	authEnvironment string
	authLogger      *logger.Logger

	adminTokenOnce  sync.Once
	adminTokenValue string
)

// ConfigureAuth wires the token store used by APIKeyAuth to validate
// bearer tokens. It must be called once at startup (NewAuthHandler does
// this) before the server starts accepting requests.
func ConfigureAuth(store TokenStore, environment string, log *logger.Logger) {
	authMu.Lock()
	defer authMu.Unlock()
	authStore = store
	authEnvironment = strings.ToLower(strings.TrimSpace(environment))
	authLogger = log
	if log != nil {
		log.WithComponent("auth-middleware").Info().
			Str("environment", authEnvironment).
			Bool("token_store_configured", store != nil).
			Msg("auth middleware configured")
	}
}

func authState() (TokenStore, string, *logger.Logger) {
	authMu.RLock()
	defer authMu.RUnlock()
	return authStore, authEnvironment, authLogger
}

// adminCredential returns the env-configured admin token. Empty means
// admin authentication is disabled (fail closed).
func adminCredential() string {
	adminTokenOnce.Do(func() {
		adminTokenValue = strings.TrimSpace(os.Getenv(adminTokenEnvVar))
	})
	return adminTokenValue
}

// lookupToken resolves a presented bearer token against the token store.
// It checks session tokens first, then device API keys. Expiry is enforced
// both by the Redis TTL (a missing key) and the explicit expires_at field.
func lookupToken(ctx context.Context, store TokenStore, token string) (TokenClaims, bool) {
	for _, key := range []string{"auth:token:" + token, "auth:apikey:" + token} {
		var claims TokenClaims
		if err := store.GetJSON(ctx, key, &claims); err != nil {
			continue
		}
		if !claims.ExpiresAt.IsZero() && time.Now().After(claims.ExpiresAt) {
			continue
		}
		return claims, true
	}
	return TokenClaims{}, false
}

// APIKeyAuth returns middleware that validates bearer token authentication.
// Accepted credentials:
//   - the configured service secret (service-to-service calls), if non-empty
//   - a session token issued by Refresh/RegisterDevice (auth:token:<token>)
//   - a device API key issued by RegisterDevice (auth:apikey:<key>)
//
// Anything else is rejected with 401.
func APIKeyAuth(secret string) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Skip auth for OPTIONS requests (CORS preflight)
			if r.Method == http.MethodOptions {
				next.ServeHTTP(w, r)
				return
			}

			// Get API key from header
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				http.Error(w, `{"error":"missing authorization header"}`, http.StatusUnauthorized)
				return
			}

			// Check Bearer token format
			parts := strings.SplitN(authHeader, " ", 2)
			if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
				http.Error(w, `{"error":"invalid authorization header format"}`, http.StatusUnauthorized)
				return
			}

			token := parts[1]
			if token == "" {
				http.Error(w, `{"error":"invalid API key"}`, http.StatusUnauthorized)
				return
			}

			// Service-to-service: the configured shared secret, only when configured.
			if secret != "" && subtle.ConstantTimeCompare([]byte(token), []byte(secret)) == 1 {
				ctx := context.WithValue(r.Context(), ContextKeyAPIKey, token)
				ctx = context.WithValue(ctx, ContextKeyIsService, true)
				next.ServeHTTP(w, r.WithContext(ctx))
				return
			}

			store, env, log := authState()
			if store == nil {
				// Development-only shortcut: allow requests through when no
				// token store is wired (e.g. local runs without Redis).
				if env == "development" {
					if log != nil {
						log.WithComponent("auth-middleware").Warn().
							Str("path", r.URL.Path).
							Msg("token store not configured; accepting token in development mode only")
					}
					ctx := context.WithValue(r.Context(), ContextKeyAPIKey, token)
					next.ServeHTTP(w, r.WithContext(ctx))
					return
				}
				if log != nil {
					log.WithComponent("auth-middleware").Error().
						Str("path", r.URL.Path).
						Msg("token store not configured; rejecting request")
				}
				http.Error(w, `{"error":"authentication unavailable"}`, http.StatusServiceUnavailable)
				return
			}

			claims, ok := lookupToken(r.Context(), store, token)
			if !ok {
				http.Error(w, `{"error":"invalid or expired token"}`, http.StatusUnauthorized)
				return
			}

			ctx := context.WithValue(r.Context(), ContextKeyAPIKey, token)
			if claims.UserID != "" {
				ctx = context.WithValue(ctx, ContextKeyUserID, claims.UserID)
			}
			if claims.DeviceID != "" {
				ctx = context.WithValue(ctx, ContextKeyDeviceID, claims.DeviceID)
			}
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// AdminAuth returns middleware that requires admin privileges. The admin
// credential is the ORBGUARD_ADMIN_TOKEN environment variable; if it is not
// set, admin routes are disabled entirely (fail closed). The secret parameter
// is retained for call-site compatibility but is not a valid admin credential.
func AdminAuth(_ string) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Get API key from context (set by APIKeyAuth)
			apiKey, ok := r.Context().Value(ContextKeyAPIKey).(string)
			if !ok || apiKey == "" {
				http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
				return
			}

			expected := adminCredential()
			if expected == "" {
				_, _, log := authState()
				if log != nil {
					log.WithComponent("auth-middleware").Error().
						Str("path", r.URL.Path).
						Msg("admin access attempted but " + adminTokenEnvVar + " is not configured; admin routes are disabled")
				}
				http.Error(w, `{"error":"admin access is not configured"}`, http.StatusForbidden)
				return
			}

			adminToken := r.Header.Get("X-Admin-Token")
			if adminToken == "" {
				http.Error(w, `{"error":"admin token required"}`, http.StatusForbidden)
				return
			}

			if subtle.ConstantTimeCompare([]byte(adminToken), []byte(expected)) != 1 {
				_, _, log := authState()
				if log != nil {
					log.WithComponent("auth-middleware").Warn().
						Str("path", r.URL.Path).
						Str("remote", r.RemoteAddr).
						Msg("invalid admin token presented")
				}
				http.Error(w, `{"error":"invalid admin token"}`, http.StatusForbidden)
				return
			}

			// Add admin flag to context
			ctx := context.WithValue(r.Context(), ContextKeyIsAdmin, true)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// GetAPIKey returns the API key from context
func GetAPIKey(ctx context.Context) string {
	if key, ok := ctx.Value(ContextKeyAPIKey).(string); ok {
		return key
	}
	return ""
}

// GetUserID returns the authenticated user ID from context
func GetUserID(ctx context.Context) string {
	if id, ok := ctx.Value(ContextKeyUserID).(string); ok {
		return id
	}
	return ""
}

// GetDeviceID returns the authenticated device ID from context
func GetDeviceID(ctx context.Context) string {
	if id, ok := ctx.Value(ContextKeyDeviceID).(string); ok {
		return id
	}
	return ""
}

// IsServiceRequest returns whether the request authenticated with the
// configured service-to-service secret.
func IsServiceRequest(ctx context.Context) bool {
	if isService, ok := ctx.Value(ContextKeyIsService).(bool); ok {
		return isService
	}
	return false
}

// IsAdmin returns whether the request is from an admin
func IsAdmin(ctx context.Context) bool {
	if isAdmin, ok := ctx.Value(ContextKeyIsAdmin).(bool); ok {
		return isAdmin
	}
	return false
}
