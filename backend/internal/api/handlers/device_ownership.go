package handlers

import (
	"context"
	"net/http"

	"github.com/go-chi/chi/v5"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/domain/models"
)

// Device ownership — the OrbNet-account side of anti-theft.
//
// A device is "claimed" by the first logged-in OrbNet user, after which only
// that account may control it (enforced by middleware.DeviceOwnership). These
// handlers provide the bootstrap (claim) and the account's device list; both
// require an OrbNet JWT (ContextKeyOrbNetUserID).

// orbNetUserID extracts the authenticated OrbNet account id, or (0,false) when
// the caller is not an OrbNet-JWT user (e.g. a device key or S2S).
func orbNetUserID(ctx context.Context) (int64, bool) {
	id, ok := ctx.Value(middleware.ContextKeyOrbNetUserID).(int64)
	if !ok || id <= 0 {
		return 0, false
	}
	return id, true
}

// LookupOrbNetOwner is the owner-resolver the DeviceOwnership middleware calls.
func (h *DeviceSecurityHandler) LookupOrbNetOwner(ctx context.Context, deviceID string) (ownerID *int64, found bool, err error) {
	return h.service.GetOrbNetOwner(ctx, deviceID)
}

// ClaimDevice handles POST /api/v1/device/{device_id}/claim — the ownership
// bootstrap. The logged-in OrbNet user claims a device that is currently
// unclaimed (or already theirs). Returns 409 if another account owns it.
func (h *DeviceSecurityHandler) ClaimDevice(w http.ResponseWriter, r *http.Request) {
	userID, ok := orbNetUserID(r.Context())
	if !ok {
		h.respondError(w, http.StatusUnauthorized, "sign in with your OrbVPN account to claim a device")
		return
	}
	deviceID := chi.URLParam(r, "device_id")
	if deviceID == "" {
		h.respondError(w, http.StatusBadRequest, "device_id is required")
		return
	}

	claimed, conflict, found, err := h.service.ClaimDevice(r.Context(), deviceID, userID)
	if err != nil {
		h.logger.Error().Err(err).Str("device_id", deviceID).Msg("failed to claim device")
		h.respondError(w, http.StatusInternalServerError, "failed to claim device")
		return
	}
	if !found {
		h.respondError(w, http.StatusNotFound, "device not found — register it first")
		return
	}
	if conflict {
		// Already owned by a different account. Don't reveal by whom.
		h.respondError(w, http.StatusConflict, "this device is already linked to another account")
		return
	}
	if !claimed {
		h.respondError(w, http.StatusInternalServerError, "failed to claim device")
		return
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"status":    "claimed",
		"device_id": deviceID,
	})
}

// GetMyDevices handles GET /api/v1/device — the OrbNet account's owned devices.
func (h *DeviceSecurityHandler) GetMyDevices(w http.ResponseWriter, r *http.Request) {
	userID, ok := orbNetUserID(r.Context())
	if !ok {
		h.respondError(w, http.StatusUnauthorized, "sign in with your OrbVPN account to list your devices")
		return
	}

	devices, err := h.service.ListDevicesByOrbNetUser(r.Context(), userID)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to list owned devices")
		h.respondError(w, http.StatusInternalServerError, "failed to list devices")
		return
	}
	if devices == nil {
		devices = []*models.SecureDeviceInfo{} // return [] not null when empty
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"devices": devices,
		"count":   len(devices),
	})
}
