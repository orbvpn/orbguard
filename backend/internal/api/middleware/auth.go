package middleware

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	chimw "github.com/go-chi/chi/v5/middleware"

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
	// ContextKeyOrbNetUserID holds the int64 OrbNet account user_id when the
	// request is authenticated with a valid OrbNet JWT (web panel or a
	// logged-in app acting as the account user). Absent for device-key/S2S auth.
	ContextKeyOrbNetUserID ContextKey = "orbnet_user_id"
	// ContextKeySubscriptionValid holds the bool subscription_valid claim from
	// an OrbNet JWT — used to gate premium remote-control actions.
	ContextKeySubscriptionValid ContextKey = "subscription_valid"
	// ContextKeyPeerAddr holds the TCP peer address (host:port) exactly as the
	// listener saw it, recorded by PeerAddress before RealIP rewrites
	// RemoteAddr from client-supplied headers.
	ContextKeyPeerAddr ContextKey = "peer_addr"
	// ContextKeyDeviceKeyExpiry holds the expiry of the device API key the
	// request authenticated with. Absent for every other credential.
	ContextKeyDeviceKeyExpiry ContextKey = "device_key_expiry"
	// ContextKeyPayingAccount is true for an OrbNet JWT that shows a paid plan.
	ContextKeyPayingAccount ContextKey = "paying_account"
	// ContextKeyDeviceKeyIssuer holds the IssuedFrom tag of that key.
	ContextKeyDeviceKeyIssuer ContextKey = "device_key_issuer"
)

const (
	// AdminTokenEnvVar is the environment variable holding the admin
	// credential. There is intentionally no default: unset or weak, admin
	// routes are disabled (fail closed).
	AdminTokenEnvVar = "ORBGUARD_ADMIN_TOKEN"

	// adminTokenHeader is the ONLY place the admin credential is read from.
	// Query strings end up in access logs, proxies and browser history, and
	// bodies belong to the handler, so neither is accepted as a fallback.
	adminTokenHeader = "X-Admin-Token"

	// adminTokenMinLen is the shortest admin token accepted. The lockout
	// pauses whenever Redis is unreachable, so the token on its own has to
	// make online guessing absurd; a real secret is 40+ random characters.
	adminTokenMinLen = 32

	// adminLockoutThreshold wrong tokens from one address (see lockoutAddress)
	// within adminLockoutWindow lock that address out of every admin route,
	// the right token included, until the window closes; each further
	// failure re-arms the window.
	adminLockoutThreshold = 5
	adminLockoutWindow    = 15 * time.Minute
	adminLockoutKeyPrefix = "auth:admin:fail:"

	// xForwardedFor is the header the ingress appends the peer address to.
	xForwardedFor = "X-Forwarded-For"
)

// adminTokenPlaceholders are values that have appeared in examples, dev
// configs or docs. None of them is a credential, whatever its length.
var adminTokenPlaceholders = map[string]bool{
	"dev-admin-token": true,
	"changeme":        true,
	"admin":           true,
}

// AdminLockoutStore is the failure-counter interface behind the admin
// lockout. *cache.RedisCache satisfies it with an atomic INCR+EXPIRE.
//
// RecordFailure adds one failure to key, (re)arms its expiry to window and
// returns the new count. FailureCount returns the live count and the time the
// counter still has to live; a negative duration means the counter exists but
// has NO expiry, which the caller must treat as damaged rather than as a lock
// of unknown length. ClearFailures forgets the counter.
type AdminLockoutStore interface {
	RecordFailure(ctx context.Context, key string, window time.Duration) (int64, error)
	FailureCount(ctx context.Context, key string) (int64, time.Duration, error)
	ClearFailures(ctx context.Context, key string) error
}

// TokenClaims is the canonical payload stored in Redis for both session
// tokens (auth:token:<token>) and device API keys (auth:apikey:<key>).
// Handlers that issue credentials must store this exact shape so middleware
// lookups resolve identity consistently.
type TokenClaims struct {
	UserID    string    `json:"user_id,omitempty"`
	DeviceID  string    `json:"device_id,omitempty"`
	ExpiresAt time.Time `json:"expires_at,omitempty"`
	// IssuedFrom tags the client network a device key was issued on.
	IssuedFrom string `json:"issued_from,omitempty"`
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

	// adminToken is the accepted credential; "" disables admin routes.
	adminToken   string
	adminLockout AdminLockoutStore
	adminLog     *logger.Logger
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

// adminTokenWeak reports whether token is unusable as the admin credential
// and why: not set, shorter than adminTokenMinLen, or a known placeholder.
// The reason is safe to log; it never includes the token itself.
func adminTokenWeak(token string) (reason string, weak bool) {
	token = strings.TrimSpace(token)
	switch {
	case token == "":
		return "not set", true
	case adminTokenPlaceholders[strings.ToLower(token)]:
		return "known placeholder value", true
	case len(token) < adminTokenMinLen:
		return "shorter than " + strconv.Itoa(adminTokenMinLen) + " characters", true
	}
	return "", false
}

// ConfigureAdminAuth installs the admin credential (normally the value of
// AdminTokenEnvVar) and the counter store behind the per-address lockout.
// It runs once at startup. A weak token is refused HERE, not at request
// time: admin routes then answer 403 exactly as if nothing were configured,
// and the ERROR log says why, so the process keeps serving device traffic
// instead of starting with a guessable credential. A nil lockout store
// disables the lockout (logged) and leaves the constant-time compare as the
// only brake on guessing.
func ConfigureAdminAuth(token string, lockout AdminLockoutStore, log *logger.Logger) {
	token = strings.TrimSpace(token)
	reason, weak := adminTokenWeak(token)
	if weak {
		token = ""
	}

	authMu.Lock()
	adminToken = token
	adminLockout = lockout
	adminLog = log
	authMu.Unlock()

	if log == nil {
		return
	}
	l := log.WithComponent("auth-middleware")
	switch {
	case weak && reason == "not set":
		l.Warn().Msg(AdminTokenEnvVar + " is not set; admin routes are disabled")
	case weak:
		l.Error().Str("reason", reason).
			Msg(AdminTokenEnvVar + " rejected as weak; admin routes are disabled until it holds a strong value")
	default:
		l.Info().
			Int("token_len", len(token)).
			Bool("lockout_enabled", lockout != nil).
			Msg("admin auth configured")
	}
	if lockout == nil {
		l.Warn().Msg("no lockout store wired; wrong admin tokens are refused but not counted")
	}
}

// adminState snapshots the admin configuration for one request.
func adminState() (string, AdminLockoutStore, *logger.Logger) {
	authMu.RLock()
	defer authMu.RUnlock()
	return adminToken, adminLockout, adminLog
}

// PeerAddress records the connection's real peer address in the request
// context before anything rewrites RemoteAddr. chi's RealIP replaces
// RemoteAddr with whatever the client put in True-Client-IP, X-Real-IP or the
// first X-Forwarded-For hop: right for access logs behind a trusted ingress,
// useless for anything a hostile client must not be able to steer. It must be
// registered ahead of RealIP.
func PeerAddress(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := context.WithValue(r.Context(), ContextKeyPeerAddr, r.RemoteAddr)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// hostOnly strips the port from a host:port address; a bare address (RealIP
// leaves no port, IPv6 literals have no brackets) comes back unchanged.
func hostOnly(addr string) string {
	if host, _, err := net.SplitHostPort(addr); err == nil {
		return host
	}
	return addr
}

// peerIP is the TCP peer's address without the port: the one PeerAddress
// recorded before RealIP ran, or RemoteAddr itself when that middleware is
// not in the chain (bare handlers in tests).
func peerIP(r *http.Request) string {
	addr := r.RemoteAddr
	if peer, ok := r.Context().Value(ContextKeyPeerAddr).(string); ok && peer != "" {
		addr = peer
	}
	return hostOnly(addr)
}

// sharedAddressSpace is RFC 6598 (100.64.0.0/10). Internet clients never
// appear from it, infrastructure does: the Container Apps ingress connects to
// the app from such addresses.
var sharedAddressSpace = &net.IPNet{IP: net.IPv4(100, 64, 0, 0).To4(), Mask: net.CIDRMask(10, 32)}

// infrastructureAddr reports whether ip belongs to our own network path (an
// ingress or proxy) rather than to an Internet client.
func infrastructureAddr(ip net.IP) bool {
	return ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() ||
		ip.IsUnspecified() || sharedAddressSpace.Contains(ip)
}

// lockoutAddress is the client address the admin lockout is keyed on. It has
// to be one the caller cannot choose: keyed on RemoteAddr after RealIP, a
// guesser would rotate X-Real-IP per attempt and never trip the lock, and any
// device key could name an operator's address to lock the operator out.
//
// Forwarding headers only mean something when the TCP peer is our own
// infrastructure. A public peer connected directly, and every hop it sent is
// its own claim, so the peer is the answer. Behind the ingress (Envoy, which
// APPENDS the address it accepted the connection from to X-Forwarded-For),
// the hops are read from the right, past any infrastructure hop a further
// internal proxy appended, and the first public address is the client as the
// ingress saw it; whatever the client wrote sits to its left and is never
// reached. True-Client-IP and X-Real-IP pass the ingress untouched and are
// ignored. A hop that is not an address was not written by a proxy, so the
// walk stops there, as it does when no hop is public, and the peer is used.
func lockoutAddress(r *http.Request) string {
	peer := peerIP(r)
	peerAddr := net.ParseIP(peer)
	if peerAddr != nil && !infrastructureAddr(peerAddr) {
		return peerAddr.String()
	}
	hops := strings.Split(strings.Join(r.Header.Values(xForwardedFor), ","), ",")
	for i := len(hops) - 1; i >= 0; i-- {
		ip := net.ParseIP(hostOnly(strings.TrimSpace(hops[i])))
		if ip == nil {
			break
		}
		if !infrastructureAddr(ip) {
			return ip.String()
		}
	}
	if peerAddr != nil {
		return peerAddr.String()
	}
	return peer
}

// ClientAddress is the client's address as the ingress saw it (see
// lockoutAddress). Unlike RemoteAddr after RealIP, a client cannot choose it.
func ClientAddress(r *http.Request) string {
	return lockoutAddress(r)
}

// ClientSubscriber is the client address reduced to what one subscriber
// controls: the IPv4 address, or the IPv6 /64.
func ClientSubscriber(r *http.Request) string {
	addr := ClientAddress(r)
	if ip := net.ParseIP(addr); ip != nil && ip.To4() == nil {
		return ip.Mask(net.CIDRMask(64, 128)).String() + "/64"
	}
	return addr
}

// ClientSite is the client address for a limit shared by keys that cannot be
// told apart otherwise: the IPv4 address, or the IPv6 /48.
func ClientSite(r *http.Request) string {
	addr := ClientAddress(r)
	if ip := net.ParseIP(addr); ip != nil && ip.To4() == nil {
		return ClientNetwork(r)
	}
	return addr
}

// KeyIssuerTag is the value stored on a new device key: a hash of the client
// network it was issued on, so the stored key holds no address.
func KeyIssuerTag(r *http.Request) string {
	network := ClientNetwork(r)
	if network == "" {
		return ""
	}
	sum := sha256.Sum256([]byte(network))
	return hex.EncodeToString(sum[:8])
}

// ClientNetwork is the client's network (IPv4 /24, IPv6 /48), the unit that
// counts as one reporter: one host can usually change its address inside it.
// It is empty when the client address cannot be parsed.
func ClientNetwork(r *http.Request) string {
	ip := net.ParseIP(ClientAddress(r))
	if ip == nil {
		return ""
	}
	if v4 := ip.To4(); v4 != nil {
		return v4.Mask(net.CIDRMask(24, 32)).String() + "/24"
	}
	return ip.Mask(net.CIDRMask(48, 128)).String() + "/48"
}

// lockoutKey is the failure-counter key for a client address. An IPv6 client
// picks the low 64 bits of its own address, so IPv6 is counted per /64, the
// smallest block a subscriber is handed; per address, one host could spread
// its guesses over 2^64 counters.
func lockoutKey(addr string) string {
	if ip := net.ParseIP(addr); ip != nil && ip.To4() == nil {
		return adminLockoutKeyPrefix + ip.Mask(net.CIDRMask(64, 128)).String() + "/64"
	}
	return adminLockoutKeyPrefix + addr
}

// adminLockedOut reports whether the counter at key (client address ip) has
// reached the failure threshold in its live window, how long that lock still
// has to run, and the failure count. A store error is logged and treated as
// "not locked": an unreachable Redis must neither wave a wrong token through
// (the constant-time compare still runs) nor shut every admin out, so the
// lockout simply pauses. A counter that has lost its expiry would lock the
// address forever (the right token is refused while locked, so nothing else
// could ever clear it); it is dropped and logged instead.
func adminLockedOut(ctx context.Context, store AdminLockoutStore, key, ip string, log *logger.Logger) (bool, time.Duration, int64) {
	if store == nil {
		return false, 0, 0
	}
	count, remaining, err := store.FailureCount(ctx, key)
	if err != nil {
		if log != nil {
			log.WithComponent("auth-middleware").Warn().Err(err).
				Str("remote_ip", ip).
				Msg("admin lockout store unavailable; proceeding without lockout")
		}
		return false, 0, 0
	}
	if count < adminLockoutThreshold {
		return false, 0, count
	}
	if remaining < 0 {
		if log != nil {
			log.WithComponent("auth-middleware").Warn().
				Str("remote_ip", ip).
				Int64("failures", count).
				Msg("admin failure counter had no expiry; cleared instead of locking the address indefinitely")
		}
		if err := store.ClearFailures(ctx, key); err != nil && log != nil {
			log.WithComponent("auth-middleware").Warn().Err(err).
				Str("remote_ip", ip).
				Msg("could not clear damaged admin failure counter")
		}
		return false, 0, 0
	}
	return true, remaining, count
}

// recordAdminFailure counts a wrong token against key (client address ip) and
// returns the new count, or 0 when the store is absent or failing (logged;
// see adminLockedOut).
func recordAdminFailure(ctx context.Context, store AdminLockoutStore, key, ip string, log *logger.Logger) int64 {
	if store == nil {
		return 0
	}
	count, err := store.RecordFailure(ctx, key, adminLockoutWindow)
	if err != nil {
		if log != nil {
			log.WithComponent("auth-middleware").Warn().Err(err).
				Str("remote_ip", ip).
				Msg("admin lockout store unavailable; failure not counted")
		}
		return 0
	}
	return count
}

// writeAdminLocked answers a locked-out address. Retry-After carries the
// time left on the lock so a legitimate operator knows how long to wait.
func writeAdminLocked(w http.ResponseWriter, retryAfter time.Duration) {
	secs := int64(retryAfter / time.Second)
	if secs < 1 {
		secs = 1
	}
	w.Header().Set("Retry-After", strconv.FormatInt(secs, 10))
	http.Error(w, `{"error":"too many invalid admin tokens from this address; try again later"}`, http.StatusTooManyRequests)
}

// lookupToken resolves a presented bearer token against the token store.
// It checks session tokens first, then device API keys, and reports whether a
// device API key matched. Expiry is enforced both by the Redis TTL (a missing
// key) and the explicit expires_at field.
func lookupToken(ctx context.Context, store TokenStore, token string) (claims TokenClaims, deviceKey, ok bool) {
	for _, key := range []string{"auth:token:" + token, "auth:apikey:" + token} {
		var found TokenClaims
		if err := store.GetJSON(ctx, key, &found); err != nil {
			continue
		}
		if !found.ExpiresAt.IsZero() && time.Now().After(found.ExpiresAt) {
			continue
		}
		return found, strings.HasPrefix(key, "auth:apikey:"), true
	}
	return TokenClaims{}, false, false
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

			// OrbNet account JWT (web panel / logged-in app acting as the user).
			// Structurally distinct from a device key, so this never shadows the
			// store lookup below; inert unless the shared secret is configured.
			if claims, ok := verifyOrbNetJWT(token); ok {
				ctx := context.WithValue(r.Context(), ContextKeyAPIKey, token)
				ctx = context.WithValue(ctx, ContextKeyOrbNetUserID, claims.UserID)
				ctx = context.WithValue(ctx, ContextKeySubscriptionValid, claims.SubscriptionValid)
				ctx = context.WithValue(ctx, ContextKeyPayingAccount, claims.IsPaying())
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

			claims, deviceKey, ok := lookupToken(r.Context(), store, token)
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
			if deviceKey && !claims.ExpiresAt.IsZero() {
				ctx = context.WithValue(ctx, ContextKeyDeviceKeyExpiry, claims.ExpiresAt)
			}
			if deviceKey && claims.IssuedFrom != "" {
				ctx = context.WithValue(ctx, ContextKeyDeviceKeyIssuer, claims.IssuedFrom)
			}
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// AdminAuth returns middleware that requires admin privileges. The admin
// credential is installed by ConfigureAdminAuth (from ORBGUARD_ADMIN_TOKEN);
// if it is unset or weak, admin routes are disabled entirely (fail closed).
// The secret parameter is retained for call-site compatibility but is not a
// valid admin credential.
//
// Per request: a bearer credential must already have passed APIKeyAuth; an
// address (lockoutAddress: the client as the ingress saw it, never a header
// the client wrote; IPv6 per /64) with adminLockoutThreshold recent wrong
// tokens is refused with 429 before the token is even compared; the token is
// read from the X-Admin-Token header only; a mismatch is counted and answered
// 403 (429 once the threshold is reached); a match resets the counter and the
// call is written to the "admin-audit" log with its outcome, never with the
// token.
func AdminAuth(_ string) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Get API key from context (set by APIKeyAuth)
			apiKey, ok := r.Context().Value(ContextKeyAPIKey).(string)
			if !ok || apiKey == "" {
				http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
				return
			}

			expected, lockout, log := adminState()
			if expected == "" {
				if log != nil {
					log.WithComponent("auth-middleware").Error().
						Str("path", r.URL.Path).
						Msg("admin access attempted but " + AdminTokenEnvVar + " is not configured or was rejected as weak; admin routes are disabled")
				}
				http.Error(w, `{"error":"admin access is not configured"}`, http.StatusForbidden)
				return
			}

			ip := lockoutAddress(r)
			key := lockoutKey(ip)
			locked, retryAfter, failures := adminLockedOut(r.Context(), lockout, key, ip, log)
			if locked {
				if log != nil {
					log.WithComponent("auth-middleware").Warn().
						Str("path", r.URL.Path).
						Str("remote_ip", ip).
						Int64("failures", failures).
						Msg("admin request from a locked-out address refused")
				}
				writeAdminLocked(w, retryAfter)
				return
			}

			adminToken := r.Header.Get(adminTokenHeader)
			if adminToken == "" {
				http.Error(w, `{"error":"admin token required"}`, http.StatusForbidden)
				return
			}

			if subtle.ConstantTimeCompare([]byte(adminToken), []byte(expected)) != 1 {
				count := recordAdminFailure(r.Context(), lockout, key, ip, log)
				if log != nil {
					log.WithComponent("auth-middleware").Warn().
						Str("path", r.URL.Path).
						Str("remote_ip", ip).
						Int("presented_len", len(adminToken)).
						Int64("failures", count).
						Msg("invalid admin token presented")
				}
				if count >= adminLockoutThreshold {
					writeAdminLocked(w, adminLockoutWindow)
					return
				}
				http.Error(w, `{"error":"invalid admin token"}`, http.StatusForbidden)
				return
			}

			// A correct token forgives earlier typos from the same address so
			// an operator is not locked out by their own slips.
			if failures > 0 && lockout != nil {
				if err := lockout.ClearFailures(r.Context(), key); err != nil && log != nil {
					log.WithComponent("auth-middleware").Warn().Err(err).
						Str("remote_ip", ip).
						Msg("could not reset admin failure counter")
				}
			}

			// Add admin flag to context
			ctx := context.WithValue(r.Context(), ContextKeyIsAdmin, true)
			ww := chimw.NewWrapResponseWriter(w, r.ProtoMajor)
			start := time.Now()
			next.ServeHTTP(ww, r.WithContext(ctx))

			// Whoever the bearer credential identified: a session user, a
			// device, an OrbNet account (web panel JWT) or the service secret.
			if log != nil {
				log.WithComponent("admin-audit").Info().
					Str("method", r.Method).
					Str("path", r.URL.Path).
					Str("user_id", GetUserID(ctx)).
					Str("device_id", GetDeviceID(ctx)).
					Int64("orbnet_user_id", GetOrbNetUserID(ctx)).
					Bool("service", IsServiceRequest(ctx)).
					Str("remote_ip", ip).
					Int("status", ww.Status()).
					Dur("duration", time.Since(start)).
					Msg("admin call")
			}
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

// GetDeviceKeyExpiry returns the expiry of the device API key the request
// authenticated with.
func GetDeviceKeyExpiry(ctx context.Context) (time.Time, bool) {
	expiry, ok := ctx.Value(ContextKeyDeviceKeyExpiry).(time.Time)
	return expiry, ok
}

// IsPayingAccount reports whether the request carries a verified OrbNet JWT
// that shows a paid plan.
func IsPayingAccount(ctx context.Context) bool {
	paying, _ := ctx.Value(ContextKeyPayingAccount).(bool)
	return paying
}

// GetDeviceKeyIssuer returns the IssuedFrom tag of the device API key the
// request authenticated with, or "" when it has none.
func GetDeviceKeyIssuer(ctx context.Context) string {
	issuer, _ := ctx.Value(ContextKeyDeviceKeyIssuer).(string)
	return issuer
}

// CallerIdentity names the authenticated credential: one name for all keys of
// one device.
func CallerIdentity(ctx context.Context) string {
	switch {
	case IsServiceRequest(ctx):
		return "service"
	case GetOrbNetUserID(ctx) > 0:
		return "account:" + strconv.FormatInt(GetOrbNetUserID(ctx), 10)
	case GetDeviceID(ctx) != "":
		return "device:" + GetDeviceID(ctx)
	case GetUserID(ctx) != "":
		return "user:" + GetUserID(ctx)
	case GetAPIKey(ctx) != "":
		return "key:" + GetAPIKey(ctx)
	}
	return ""
}

// GetOrbNetUserID returns the OrbNet account id the request authenticated
// as (OrbNet JWT), or 0 for every other credential type.
func GetOrbNetUserID(ctx context.Context) int64 {
	if id, ok := ctx.Value(ContextKeyOrbNetUserID).(int64); ok && id > 0 {
		return id
	}
	return 0
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
