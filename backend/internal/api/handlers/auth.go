package handlers

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

const (
	authAPIKeyTTL       = 365 * 24 * time.Hour
	authSessionTokenTTL = 24 * time.Hour
	authRefreshTokenTTL = 30 * 24 * time.Hour

	// deviceRegistrationsPerDay limits new credentials per client address and
	// UTC day. IPv6 counts per /48, the range one site can rotate through.
	deviceRegistrationsPerDay = 30
)

// refreshClaims is the payload stored under auth:refresh:<token>. It tracks
// the identity the refresh token was issued for and the session token it can
// rotate, so Refresh can revoke the previous session.
type refreshClaims struct {
	UserID    string    `json:"user_id,omitempty"`
	DeviceID  string    `json:"device_id,omitempty"`
	Token     string    `json:"token,omitempty"`
	ExpiresAt time.Time `json:"expires_at"`
	// KeySince and IssuedFrom carry the origin of the device's key across a
	// refresh.
	KeySince   time.Time `json:"key_since,omitempty"`
	IssuedFrom string    `json:"issued_from,omitempty"`
}

// credentialOrigin is when a device's first key was issued and the network tag
// it was issued on. It stays with one device id.
type credentialOrigin struct {
	since  time.Time
	issuer string
}

// AuthHandler handles authentication endpoints
type AuthHandler struct {
	cache   *cache.RedisCache
	devices *repository.DeviceRepository
	logger  *logger.Logger
	secret  string
	// Resolves the OrbNet account that owns a device, so RegisterDevice can
	// refuse to mint a fresh credential for a phone somebody else has claimed.
	// nil disables the check (no device-security service wired).
	ownerLookup middleware.OwnerLookup
}

// NewAuthHandler creates a new AuthHandler. It also wires the shared Redis
// cache into the auth middleware so bearer tokens issued here are the only
// tokens that validate on protected routes, and installs the admin
// credential plus the Redis-backed per-address lockout behind AdminAuth.
func NewAuthHandler(c *cache.RedisCache, devices *repository.DeviceRepository, secret string, log *logger.Logger) *AuthHandler {
	middleware.ConfigureAuth(c, os.Getenv("ORBGUARD_APP_ENVIRONMENT"), log)
	// A nil *RedisCache must stay a nil interface, or the middleware would
	// call methods on a nil receiver instead of disabling the lockout.
	var lockout middleware.AdminLockoutStore
	if c != nil {
		lockout = c
	}
	middleware.ConfigureAdminAuth(os.Getenv(middleware.AdminTokenEnvVar), lockout, log)
	return &AuthHandler{
		cache:   c,
		devices: devices,
		logger:  log.WithComponent("auth-handler"),
		secret:  secret,
	}
}

// newAuthHandler creates AuthHandler from Dependencies, handling nil Repos safely
func newAuthHandler(deps Dependencies) *AuthHandler {
	var devices *repository.DeviceRepository
	if deps.Repos != nil {
		devices = deps.Repos.Devices
	}
	h := NewAuthHandler(deps.Cache, devices, deps.JWTSecret, deps.Logger)
	if deps.DeviceSecurityService != nil {
		h.ownerLookup = deps.DeviceSecurityService.GetOrbNetOwner
	}
	return h
}

func authGenerateToken(length int) string {
	b := make([]byte, length)
	rand.Read(b)
	return hex.EncodeToString(b)
}

// issueSession creates a session token + refresh token pair for the given
// identity and stores both in Redis with the canonical TokenClaims shape the
// auth middleware validates against.
func (h *AuthHandler) issueSession(r *http.Request, userID, deviceID string, origin credentialOrigin) (token, refreshToken string, tokenExpiresAt time.Time, err error) {
	token = authGenerateToken(32)
	refreshToken = authGenerateToken(48)
	now := time.Now().UTC()
	tokenExpiresAt = now.Add(authSessionTokenTTL)

	if err = h.cache.SetJSON(r.Context(), "auth:token:"+token, middleware.TokenClaims{
		UserID:     userID,
		DeviceID:   deviceID,
		ExpiresAt:  tokenExpiresAt,
		KeySince:   origin.since,
		IssuedFrom: origin.issuer,
	}, authSessionTokenTTL); err != nil {
		return "", "", time.Time{}, err
	}

	if err = h.cache.SetJSON(r.Context(), "auth:refresh:"+refreshToken, refreshClaims{
		UserID:     userID,
		DeviceID:   deviceID,
		Token:      token,
		ExpiresAt:  now.Add(authRefreshTokenTTL),
		KeySince:   origin.since,
		IssuedFrom: origin.issuer,
	}, authRefreshTokenTTL); err != nil {
		return "", "", time.Time{}, err
	}

	return token, refreshToken, tokenExpiresAt, nil
}

// Login handles POST /api/v1/auth/login
//
// This service has no user credential store: device registration
// (POST /api/v1/auth/device) is the real authentication model and issues the
// API key the app uses. Issuing tokens for unverified email/password pairs
// would be fake authentication, so this endpoint honestly reports that
// credential login is not implemented.
func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
		DeviceID string `json:"device_id,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	h.logger.Warn().
		Str("device_id", req.DeviceID).
		Msg("credential login attempted but no user store is configured; directing client to device registration")

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusNotImplemented)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"error":   "credential login is not supported by this service",
		"details": "register the device via POST /api/v1/auth/device to obtain an API key",
	})
}

// Refresh handles POST /api/v1/auth/refresh
func (h *AuthHandler) Refresh(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	if req.RefreshToken == "" {
		http.Error(w, `{"error":"refresh_token is required"}`, http.StatusBadRequest)
		return
	}

	// Verify refresh token
	refreshKey := "auth:refresh:" + req.RefreshToken
	var claims refreshClaims
	if err := h.cache.GetJSON(r.Context(), refreshKey, &claims); err != nil {
		http.Error(w, `{"error":"invalid or expired refresh token"}`, http.StatusUnauthorized)
		return
	}
	if !claims.ExpiresAt.IsZero() && time.Now().After(claims.ExpiresAt) {
		_ = h.cache.Delete(r.Context(), refreshKey)
		http.Error(w, `{"error":"invalid or expired refresh token"}`, http.StatusUnauthorized)
		return
	}
	if claims.UserID == "" && claims.DeviceID == "" {
		// Legacy entry without a bound identity: it cannot be rotated into a
		// valid session, so revoke it and force re-registration.
		_ = h.cache.Delete(r.Context(), refreshKey)
		http.Error(w, `{"error":"invalid or expired refresh token"}`, http.StatusUnauthorized)
		return
	}

	// Rotate: revoke the previous session token and the used refresh token,
	// then issue a fresh pair bound to the same identity.
	if claims.Token != "" {
		_ = h.cache.Delete(r.Context(), "auth:token:"+claims.Token)
	}
	if err := h.cache.Delete(r.Context(), refreshKey); err != nil {
		h.logger.Warn().Err(err).Msg("failed to delete used refresh token")
	}

	newToken, newRefreshToken, _, err := h.issueSession(r, claims.UserID, claims.DeviceID,
		credentialOrigin{since: claims.KeySince, issuer: claims.IssuedFrom})
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to store rotated session tokens")
		http.Error(w, `{"error":"failed to refresh token"}`, http.StatusInternalServerError)
		return
	}

	h.logger.Info().
		Str("user_id", claims.UserID).
		Str("device_id", claims.DeviceID).
		Msg("token refreshed")

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"token":         newToken,
		"refresh_token": newRefreshToken,
		"expires_in":    int(authSessionTokenTTL.Seconds()),
		"token_type":    "Bearer",
	})
}

// callerHoldsDeviceKey reports whether the request carries a credential that
// already belongs to deviceID — i.e. the caller genuinely controls the device
// it is re-registering.
//
// Accepts either the configured service secret (internal callers) or a live
// device API key resolving to this same device_id, validated against the same
// `auth:apikey:<key>` records middleware.APIKeyAuth reads. The endpoint is
// public, so no middleware has populated the context by this point and the
// header must be parsed here.
func (h *AuthHandler) callerHoldsDeviceKey(r *http.Request, deviceID string) bool {
	parts := strings.SplitN(r.Header.Get("Authorization"), " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "bearer") || parts[1] == "" {
		return false
	}
	token := parts[1]

	if h.secret != "" &&
		subtle.ConstantTimeCompare([]byte(token), []byte(h.secret)) == 1 {
		return true
	}

	if h.cache == nil {
		return false
	}
	var claims middleware.TokenClaims
	if err := h.cache.GetJSON(r.Context(), "auth:apikey:"+token, &claims); err != nil {
		return false
	}
	if !claims.ExpiresAt.IsZero() && time.Now().UTC().After(claims.ExpiresAt) {
		return false
	}
	return claims.DeviceID != "" && claims.DeviceID == deviceID
}

// heldCredentialOrigin reports whether the request presents a live API key or
// session token of this device id, and returns that credential's origin. The
// service secret is not a credential of a device. If Redis cannot answer, the
// caller is not proven and takes the charged path.
//
// A session from before origins were recorded proves the device but has a
// zero origin.
func (h *AuthHandler) heldCredentialOrigin(r *http.Request, deviceID string) (credentialOrigin, bool) {
	parts := strings.SplitN(r.Header.Get("Authorization"), " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "bearer") || parts[1] == "" || h.cache == nil {
		return credentialOrigin{}, false
	}
	for _, prefix := range []string{"auth:apikey:", "auth:token:"} {
		var claims middleware.TokenClaims
		if err := h.cache.GetJSON(r.Context(), prefix+parts[1], &claims); err != nil {
			continue
		}
		if claims.DeviceID == "" || claims.DeviceID != deviceID {
			continue
		}
		if !claims.ExpiresAt.IsZero() && time.Now().UTC().After(claims.ExpiresAt) {
			continue
		}
		origin := credentialOrigin{since: claims.KeySince, issuer: claims.IssuedFrom}
		if origin.since.IsZero() && prefix == "auth:apikey:" && !claims.ExpiresAt.IsZero() {
			origin.since = claims.ExpiresAt.Add(-authAPIKeyTTL)
		}
		return origin, true
	}
	return credentialOrigin{}, false
}

// refuseRegistration takes one unit of the address's daily allowance. It
// answers the request and returns true when none is left or the count cannot
// be read; a refused request takes nothing. Registration stores its credential
// in Redis, so without Redis it could not complete in any case.
func (h *AuthHandler) refuseRegistration(w http.ResponseWriter, r *http.Request) bool {
	now := time.Now().UTC()
	sum := sha256.Sum256([]byte(middleware.ClientSite(r)))
	key := "auth:device-registrations:{" + now.Format("20060102") + "}:" + hex.EncodeToString(sum[:12])
	exhausted, err := h.cache.ReserveQuota(r.Context(), []string{key}, []int64{deviceRegistrationsPerDay}, 48*time.Hour)
	if err != nil {
		h.logger.Error().Err(err).Msg("device registration limit could not be read")
		writeRegistrationRefusal(w, http.StatusServiceUnavailable, "device registration is temporarily unavailable")
		return true
	}
	if exhausted != 0 {
		w.Header().Set("Retry-After", strconv.FormatInt(int64(services.PaidLookupRetryAfter(now)/time.Second)+1, 10))
		writeRegistrationRefusal(w, http.StatusTooManyRequests, "too many device registrations from this network today, please try again tomorrow")
		return true
	}
	return false
}

func writeRegistrationRefusal(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"error": message})
}

// RegisterDevice handles POST /api/v1/auth/device
func (h *AuthHandler) RegisterDevice(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DeviceID     string `json:"device_id"`
		DeviceName   string `json:"device_name"`
		Platform     string `json:"platform"`
		OSVersion    string `json:"os_version"`
		AppVersion   string `json:"app_version"`
		Model        string `json:"model,omitempty"`
		Manufacturer string `json:"manufacturer,omitempty"`
		PushToken    string `json:"push_token,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	if req.DeviceID == "" {
		http.Error(w, `{"error":"device_id is required"}`, http.StatusBadRequest)
		return
	}

	// A device_id that an OrbNet account has already CLAIMED must not be
	// re-registered by an anonymous caller. This endpoint is public and takes
	// device_id on trust, and DeviceOwnership admits any credential whose
	// device_id matches (device_ownership.go:45-51) — so without this check,
	// posting somebody else's device_id returned a working key for their
	// phone: thief selfies, location history, and mark-stolen/lock/wipe.
	//
	// Unknown and unclaimed device ids are unaffected, which is how a new
	// install bootstraps. A genuine re-registration by the device itself
	// presents its existing key and passes.
	if h.ownerLookup != nil {
		ownerID, found, err := h.ownerLookup(r.Context(), req.DeviceID)
		if err != nil {
			h.logger.Error().Err(err).Str("device_id", req.DeviceID).
				Msg("device ownership check failed during registration")
			http.Error(w, `{"error":"failed to register device"}`, http.StatusInternalServerError)
			return
		}
		if found && ownerID != nil && !h.callerHoldsDeviceKey(r, req.DeviceID) {
			h.logger.Warn().Str("device_id", req.DeviceID).Str("ip", r.RemoteAddr).
				Msg("rejected re-registration of a claimed device without proof of possession")
			// 404 rather than 403, matching DeviceOwnership: registration must
			// not become an oracle for which device ids exist or are claimed.
			http.Error(w, `{"error":"device not found"}`, http.StatusNotFound)
			return
		}
	}

	origin, holder := h.heldCredentialOrigin(r, req.DeviceID)
	if !holder && h.refuseRegistration(w, r) {
		return
	}
	if origin.since.IsZero() {
		origin = credentialOrigin{since: time.Now().UTC(), issuer: middleware.KeyIssuerTag(r)}
	}

	apiKey := authGenerateToken(32)
	expiresAt := time.Now().UTC().Add(authAPIKeyTTL)

	// Persist to PostgreSQL if repository available
	if h.devices != nil {
		// Check if device already exists
		existing, _ := h.devices.FindByHardwareID(r.Context(), req.DeviceID)
		if existing != nil {
			// Update last seen
			_ = h.devices.UpdateLastSeen(r.Context(), existing.ID, r.RemoteAddr)
			h.logger.Info().Str("device_id", req.DeviceID).Msg("existing device re-registered")
		} else {
			// Create new device
			_, err := h.devices.Create(r.Context(), repository.CreateDeviceParams{
				HardwareID:   req.DeviceID,
				Platform:     req.Platform,
				Model:        req.Model,
				Manufacturer: req.Manufacturer,
				OSVersion:    req.OSVersion,
				IPAddress:    r.RemoteAddr,
			})
			if err != nil {
				h.logger.Warn().Err(err).Str("device_id", req.DeviceID).Msg("failed to persist device to DB, continuing with cache only")
			}
		}
	}

	// Store device metadata in Redis cache
	if err := h.cache.SetJSON(r.Context(), "auth:device:"+req.DeviceID, map[string]interface{}{
		"device_id":    req.DeviceID,
		"device_name":  req.DeviceName,
		"platform":     req.Platform,
		"os_version":   req.OSVersion,
		"app_version":  req.AppVersion,
		"model":        req.Model,
		"manufacturer": req.Manufacturer,
		"push_token":   req.PushToken,
		"api_key":      apiKey,
		"registered":   time.Now().UTC().Format(time.RFC3339),
	}, authAPIKeyTTL); err != nil {
		h.logger.Error().Err(err).Str("device_id", req.DeviceID).Msg("failed to store device record")
		http.Error(w, `{"error":"failed to register device"}`, http.StatusInternalServerError)
		return
	}

	// Store the API key with the canonical claims shape the auth middleware
	// validates (auth:apikey:<key> -> {device_id, expires_at}).
	if err := h.cache.SetJSON(r.Context(), "auth:apikey:"+apiKey, middleware.TokenClaims{
		DeviceID:   req.DeviceID,
		ExpiresAt:  expiresAt,
		IssuedFrom: origin.issuer,
		KeySince:   origin.since,
	}, authAPIKeyTTL); err != nil {
		h.logger.Error().Err(err).Str("device_id", req.DeviceID).Msg("failed to store API key")
		http.Error(w, `{"error":"failed to register device"}`, http.StatusInternalServerError)
		return
	}

	// Also issue a short-lived session token + refresh token so the full
	// token lifecycle (refresh rotation) is available to device clients.
	token, refreshToken, _, err := h.issueSession(r, "", req.DeviceID, origin)
	if err != nil {
		h.logger.Error().Err(err).Str("device_id", req.DeviceID).Msg("failed to store session tokens")
		http.Error(w, `{"error":"failed to register device"}`, http.StatusInternalServerError)
		return
	}

	h.logger.Info().Str("device_id", req.DeviceID).Str("platform", req.Platform).Msg("device registered")

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"device_id":     req.DeviceID,
		"api_key":       apiKey,
		"expires_at":    expiresAt.Format(time.RFC3339),
		"token":         token,
		"refresh_token": refreshToken,
		"expires_in":    int(authSessionTokenTTL.Seconds()),
		"token_type":    "Bearer",
		"message":       "Device registered successfully",
	})
}
