package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/pkg/logger"
)

// DarkWebHandler handles dark web monitoring API requests
type DarkWebHandler struct {
	monitor *services.DarkWebMonitor
	logger  *logger.Logger
}

// NewDarkWebHandler creates a new dark web handler
func NewDarkWebHandler(monitor *services.DarkWebMonitor, log *logger.Logger) *DarkWebHandler {
	return &DarkWebHandler{
		monitor: monitor,
		logger:  log.WithComponent("darkweb-handler"),
	}
}

// authorizedIdentity resolves the identity that owns dark-web monitoring
// data for this request. Identity always comes from the authenticated
// context (user_id, falling back to device_id) — never from client input.
// A client-supplied user ID is only accepted when it matches the
// authenticated identity, or when the caller authenticated with the
// service-to-service secret (trusted internal callers acting on behalf of a
// user). On failure it writes the error response and returns ok=false.
func (h *DarkWebHandler) authorizedIdentity(w http.ResponseWriter, r *http.Request, requested string) (string, bool) {
	ctx := r.Context()
	userID := middleware.GetUserID(ctx)
	deviceID := middleware.GetDeviceID(ctx)

	if middleware.IsServiceRequest(ctx) {
		if requested != "" {
			return requested, true
		}
		h.respondError(w, http.StatusBadRequest, "user_id is required for service requests")
		return "", false
	}

	identity := userID
	if identity == "" {
		identity = deviceID
	}
	if identity == "" {
		h.respondError(w, http.StatusUnauthorized, "authenticated identity required")
		return "", false
	}
	if requested != "" && requested != userID && requested != deviceID {
		h.respondError(w, http.StatusForbidden, "user_id does not match authenticated identity")
		return "", false
	}
	return identity, true
}

// establishedDeviceKeyAge is how old a device key must be before it may reach
// the larger share of the paid lookup budget.
const establishedDeviceKeyAge = 24 * time.Hour

// passwordRangeBodyLimit bounds the password range request body.
const passwordRangeBodyLimit = 256

var passwordHashPrefix = regexp.MustCompile(`^[0-9A-Fa-f]{5}$`)

// deviceKeyIssuedAt is when the device's first key was issued. Keys from before
// that was recorded count from their own issue time.
func deviceKeyIssuedAt(ctx context.Context) (time.Time, bool) {
	if since, ok := middleware.GetDeviceKeySince(ctx); ok {
		return since, true
	}
	expiry, ok := middleware.GetDeviceKeyExpiry(ctx)
	return expiry.Add(-authAPIKeyTTL), ok
}

// paidLookupCaller decides who a paid lookup is charged to, from the
// authenticated context and the trusted client address only.
//
// The released app authenticates with a self-issued device key, so its users
// cannot be told from strangers by plan. An OrbNet account counts as paying
// only when its token shows a plan paid for with money; any other account gets
// the budget of a new device.
func paidLookupCaller(r *http.Request) services.PaidLookupCaller {
	ctx := r.Context()
	if middleware.IsServiceRequest(ctx) {
		return services.PaidLookupCaller{Tier: services.PaidLookupService, Identity: services.PaidLookupServiceIdentity}
	}
	caller := services.PaidLookupCaller{
		Tier:     services.PaidLookupNewDevice,
		Identity: middleware.CallerIdentity(ctx),
		Address:  middleware.ClientSubscriber(r),
	}
	if middleware.IsPayingAccount(ctx) {
		caller.Tier = services.PaidLookupPaid
		return caller
	}
	if issued, ok := deviceKeyIssuedAt(ctx); ok && time.Since(issued) >= establishedDeviceKeyAge {
		caller.Tier = services.PaidLookupEstablished
		caller.Issuer = middleware.GetDeviceKeyIssuer(ctx)
		if caller.Issuer == "" {
			caller.Address = middleware.ClientSite(r)
		}
	}
	return caller
}

// respondPaidLookupError answers a refused paid lookup and reports whether err
// was one. Both answers are failures, so no client can read them as "no breach".
func (h *DarkWebHandler) respondPaidLookupError(w http.ResponseWriter, err error) bool {
	switch {
	case errors.Is(err, services.ErrPaidLookupLimited):
		w.Header().Set("Retry-After", strconv.FormatInt(int64(services.PaidLookupRetryAfter(time.Now())/time.Second), 10))
		h.respondError(w, http.StatusTooManyRequests, "daily breach check limit reached, please try again tomorrow")
	case errors.Is(err, services.ErrPaidLookupUnavailable), errors.Is(err, services.ErrBreachProvidersFailed):
		h.respondError(w, http.StatusServiceUnavailable, "breach checking is temporarily unavailable")
	case errors.Is(err, services.ErrNoBreachProviders):
		h.respondError(w, http.StatusServiceUnavailable, "breach checking is not available: no breach data providers configured")
	default:
		return false
	}
	return true
}

// PasswordRange handles POST /api/v1/darkweb/password/range. It takes only a
// five character SHA-1 prefix, in the body so that it stays out of access
// logs, and returns the known suffixes. The client compares on the device.
func (h *DarkWebHandler) PasswordRange(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Prefix string `json:"prefix"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, passwordRangeBodyLimit)).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if !passwordHashPrefix.MatchString(req.Prefix) {
		h.respondError(w, http.StatusBadRequest, "prefix must be exactly 5 hex characters")
		return
	}

	entries, err := h.monitor.PasswordRange(r.Context(), strings.ToUpper(req.Prefix))
	if err != nil {
		h.logger.Warn().Msg("password range lookup failed")
		h.respondError(w, http.StatusBadGateway, "password check is temporarily unavailable")
		return
	}

	w.Header().Set("Cache-Control", "no-store")
	h.respondJSON(w, http.StatusOK, map[string]interface{}{"suffixes": entries})
}

// CheckEmail handles POST /api/v1/darkweb/check/email
func (h *DarkWebHandler) CheckEmail(w http.ResponseWriter, r *http.Request) {
	var req models.BreachCheckRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.Email == "" {
		h.respondError(w, http.StatusBadRequest, "email is required")
		return
	}

	ctx := services.WithPaidLookupCaller(r.Context(), paidLookupCaller(r))
	result, err := h.monitor.CheckEmail(ctx, &req)
	if err != nil {
		if h.respondPaidLookupError(w, err) {
			return
		}
		h.logger.Error().Err(err).Msg("failed to check email")
		h.respondError(w, http.StatusInternalServerError, "failed to check email")
		return
	}

	h.respondJSON(w, http.StatusOK, result)
}

// CheckPassword handles POST /api/v1/darkweb/check/password. The route is
// closed: a password must not reach the server. It reads nothing and keeps the
// answer released apps already get. Clients use /darkweb/password/range.
func (h *DarkWebHandler) CheckPassword(w http.ResponseWriter, r *http.Request) {
	h.respondError(w, http.StatusBadRequest, "password is required")
}

// AddMonitoredAsset handles POST /api/v1/darkweb/monitor
func (h *DarkWebHandler) AddMonitoredAsset(w http.ResponseWriter, r *http.Request) {
	var req struct {
		AssetType string `json:"asset_type"` // "email", "phone", etc.
		Value     string `json:"value"`
		UserID    string `json:"user_id,omitempty"`
		DeviceID  string `json:"device_id,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.Value == "" {
		h.respondError(w, http.StatusBadRequest, "value is required")
		return
	}

	assetType := models.BreachType(req.AssetType)
	if assetType == "" {
		assetType = models.BreachTypeEmail
	}

	identity, ok := h.authorizedIdentity(w, r, req.UserID)
	if !ok {
		return
	}

	deviceID := middleware.GetDeviceID(r.Context())
	if deviceID == "" && middleware.IsServiceRequest(r.Context()) {
		deviceID = req.DeviceID
	}

	ctx := services.WithPaidLookupCaller(r.Context(), paidLookupCaller(r))
	asset, err := h.monitor.AddMonitoredAsset(ctx, identity, deviceID, assetType, req.Value)
	if err != nil {
		if h.respondPaidLookupError(w, err) {
			return
		}
		h.logger.Error().Err(err).Msg("failed to add monitored asset")
		h.respondError(w, http.StatusInternalServerError, "failed to add monitored asset")
		return
	}

	h.respondJSON(w, http.StatusCreated, asset)
}

// RemoveMonitoredAsset handles DELETE /api/v1/darkweb/monitor/{id}
func (h *DarkWebHandler) RemoveMonitoredAsset(w http.ResponseWriter, r *http.Request) {
	idStr := chi.URLParam(r, "id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid id")
		return
	}

	identity, ok := h.authorizedIdentity(w, r, r.URL.Query().Get("user_id"))
	if !ok {
		return
	}

	if err := h.monitor.RemoveMonitoredAsset(r.Context(), identity, id); err != nil {
		if errors.Is(err, services.ErrAssetNotFound) {
			h.respondError(w, http.StatusNotFound, "monitored asset not found")
			return
		}
		h.logger.Error().Err(err).Msg("failed to remove monitored asset")
		h.respondError(w, http.StatusInternalServerError, "failed to remove monitored asset")
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// GetMonitoredAssets handles GET /api/v1/darkweb/monitor
func (h *DarkWebHandler) GetMonitoredAssets(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.authorizedIdentity(w, r, r.URL.Query().Get("user_id"))
	if !ok {
		return
	}

	assets, err := h.monitor.GetMonitoredAssets(r.Context(), userID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to get monitored assets")
		h.respondError(w, http.StatusInternalServerError, "failed to get monitored assets")
		return
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"assets": assets,
		"count":  len(assets),
	})
}

// GetMonitoringStatus handles GET /api/v1/darkweb/status
func (h *DarkWebHandler) GetMonitoringStatus(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.authorizedIdentity(w, r, r.URL.Query().Get("user_id"))
	if !ok {
		return
	}

	status, err := h.monitor.GetMonitoringStatus(r.Context(), userID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to get monitoring status")
		h.respondError(w, http.StatusInternalServerError, "failed to get status")
		return
	}

	h.respondJSON(w, http.StatusOK, status)
}

// GetAlerts handles GET /api/v1/darkweb/alerts
func (h *DarkWebHandler) GetAlerts(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.authorizedIdentity(w, r, r.URL.Query().Get("user_id"))
	if !ok {
		return
	}

	alerts, err := h.monitor.GetAlerts(r.Context(), userID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to get alerts")
		h.respondError(w, http.StatusInternalServerError, "failed to get alerts")
		return
	}

	// Separate by read status
	unread := []models.BreachAlert{}
	read := []models.BreachAlert{}
	for _, alert := range alerts {
		if alert.IsRead {
			read = append(read, alert)
		} else {
			unread = append(unread, alert)
		}
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"unread":       unread,
		"read":         read,
		"unread_count": len(unread),
		"total_count":  len(alerts),
	})
}

// AcknowledgeAlert handles POST /api/v1/darkweb/alerts/{id}/ack
func (h *DarkWebHandler) AcknowledgeAlert(w http.ResponseWriter, r *http.Request) {
	idStr := chi.URLParam(r, "id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid id")
		return
	}

	identity, ok := h.authorizedIdentity(w, r, r.URL.Query().Get("user_id"))
	if !ok {
		return
	}

	if err := h.monitor.AcknowledgeAlert(r.Context(), identity, id); err != nil {
		if errors.Is(err, services.ErrAlertNotFound) {
			h.respondError(w, http.StatusNotFound, "alert not found")
			return
		}
		h.logger.Error().Err(err).Msg("failed to acknowledge alert")
		h.respondError(w, http.StatusInternalServerError, "failed to acknowledge alert")
		return
	}

	h.respondJSON(w, http.StatusOK, map[string]string{"status": "acknowledged"})
}

// GetStats handles GET /api/v1/darkweb/stats
func (h *DarkWebHandler) GetStats(w http.ResponseWriter, r *http.Request) {
	stats, err := h.monitor.GetStats(r.Context())
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to get stats")
		h.respondError(w, http.StatusInternalServerError, "failed to get stats")
		return
	}

	h.respondJSON(w, http.StatusOK, stats)
}

// GetBreaches handles GET /api/v1/darkweb/breaches
// Returns the public breach catalog (HIBP), cached server-side for 24h.
func (h *DarkWebHandler) GetBreaches(w http.ResponseWriter, r *http.Request) {
	breaches, err := h.monitor.GetAllBreaches(r.Context())
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to fetch breach catalog")
		h.respondError(w, http.StatusBadGateway, "failed to fetch breach catalog from upstream provider")
		return
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"breaches": breaches,
		"count":    len(breaches),
	})
}

// GetBreachByName handles GET /api/v1/darkweb/breaches/{name}
func (h *DarkWebHandler) GetBreachByName(w http.ResponseWriter, r *http.Request) {
	name := chi.URLParam(r, "name")
	if name == "" {
		h.respondError(w, http.StatusBadRequest, "breach name is required")
		return
	}

	breach, err := h.monitor.GetBreachByName(r.Context(), name)
	if err != nil {
		if errors.Is(err, services.ErrBreachNotFound) {
			h.respondError(w, http.StatusNotFound, "breach not found")
			return
		}
		h.logger.Error().Err(err).Msg("failed to fetch breach details")
		h.respondError(w, http.StatusBadGateway, "failed to fetch breach details from upstream provider")
		return
	}

	h.respondJSON(w, http.StatusOK, breach)
}

// RefreshMonitoring handles POST /api/v1/darkweb/refresh
func (h *DarkWebHandler) RefreshMonitoring(w http.ResponseWriter, r *http.Request) {
	if err := h.monitor.RefreshMonitoredAssets(r.Context()); err != nil {
		if errors.Is(err, services.ErrRefreshInProgress) {
			h.respondError(w, http.StatusConflict, "a refresh is already running")
			return
		}
		if h.respondPaidLookupError(w, err) {
			return
		}
		h.logger.Error().Err(err).Msg("failed to refresh monitored assets")
		h.respondError(w, http.StatusInternalServerError, "failed to refresh")
		return
	}

	h.respondJSON(w, http.StatusOK, map[string]string{"status": "refreshed"})
}

func (h *DarkWebHandler) respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func (h *DarkWebHandler) respondError(w http.ResponseWriter, status int, message string) {
	h.respondJSON(w, status, map[string]string{"error": message})
}
