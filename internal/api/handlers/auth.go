package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"time"

	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/pkg/logger"
)

// AuthHandler handles authentication endpoints
type AuthHandler struct {
	cache  *cache.RedisCache
	logger *logger.Logger
	secret string
}

// NewAuthHandler creates a new AuthHandler
func NewAuthHandler(c *cache.RedisCache, secret string, log *logger.Logger) *AuthHandler {
	return &AuthHandler{
		cache:  c,
		logger: log.WithComponent("auth-handler"),
		secret: secret,
	}
}

func authGenerateToken(length int) string {
	b := make([]byte, length)
	rand.Read(b)
	return hex.EncodeToString(b)
}

// Login handles POST /api/v1/auth/login
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

	if req.Email == "" || req.Password == "" {
		http.Error(w, `{"error":"email and password are required"}`, http.StatusBadRequest)
		return
	}

	token := authGenerateToken(32)
	refreshToken := authGenerateToken(48)

	// Store token in cache
	_ = h.cache.SetJSON(r.Context(), "auth:token:"+token, map[string]interface{}{
		"email":     req.Email,
		"device_id": req.DeviceID,
		"created":   time.Now().UTC().Format(time.RFC3339),
	}, 24*time.Hour)

	// Store refresh token
	_ = h.cache.SetJSON(r.Context(), "auth:refresh:"+refreshToken, map[string]interface{}{
		"email":   req.Email,
		"token":   token,
		"created": time.Now().UTC().Format(time.RFC3339),
	}, 30*24*time.Hour)

	h.logger.Info().Str("email", req.Email).Msg("user logged in")

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"token":         token,
		"refresh_token": refreshToken,
		"expires_in":    86400,
		"token_type":    "Bearer",
		"user_id":       authGenerateToken(16),
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
	var refreshData map[string]interface{}
	if err := h.cache.GetJSON(r.Context(), refreshKey, &refreshData); err != nil {
		http.Error(w, `{"error":"invalid or expired refresh token"}`, http.StatusUnauthorized)
		return
	}

	// Issue new tokens
	newToken := authGenerateToken(32)
	newRefreshToken := authGenerateToken(48)
	email, _ := refreshData["email"].(string)

	_ = h.cache.SetJSON(r.Context(), "auth:token:"+newToken, map[string]interface{}{
		"email":   email,
		"created": time.Now().UTC().Format(time.RFC3339),
	}, 24*time.Hour)

	_ = h.cache.Delete(r.Context(), refreshKey)
	_ = h.cache.SetJSON(r.Context(), "auth:refresh:"+newRefreshToken, map[string]interface{}{
		"email":   email,
		"token":   newToken,
		"created": time.Now().UTC().Format(time.RFC3339),
	}, 30*24*time.Hour)

	h.logger.Info().Str("email", email).Msg("token refreshed")

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"token":         newToken,
		"refresh_token": newRefreshToken,
		"expires_in":    86400,
		"token_type":    "Bearer",
	})
}

// RegisterDevice handles POST /api/v1/auth/device
func (h *AuthHandler) RegisterDevice(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DeviceID   string `json:"device_id"`
		DeviceName string `json:"device_name"`
		Platform   string `json:"platform"`
		OSVersion  string `json:"os_version"`
		AppVersion string `json:"app_version"`
		PushToken  string `json:"push_token,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	if req.DeviceID == "" {
		http.Error(w, `{"error":"device_id is required"}`, http.StatusBadRequest)
		return
	}

	apiKey := authGenerateToken(32)
	expiresAt := time.Now().Add(365 * 24 * time.Hour)

	_ = h.cache.SetJSON(r.Context(), "auth:device:"+req.DeviceID, map[string]interface{}{
		"device_id":   req.DeviceID,
		"device_name": req.DeviceName,
		"platform":    req.Platform,
		"os_version":  req.OSVersion,
		"app_version": req.AppVersion,
		"push_token":  req.PushToken,
		"api_key":     apiKey,
		"registered":  time.Now().UTC().Format(time.RFC3339),
	}, 365*24*time.Hour)

	_ = h.cache.SetJSON(r.Context(), "auth:apikey:"+apiKey, map[string]interface{}{
		"device_id": req.DeviceID,
	}, 365*24*time.Hour)

	h.logger.Info().Str("device_id", req.DeviceID).Str("platform", req.Platform).Msg("device registered")

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"device_id":  req.DeviceID,
		"api_key":    apiKey,
		"expires_at": expiresAt.Format(time.RFC3339),
		"message":    "Device registered successfully",
	})
}
