// Package push delivers real-time, high-priority data messages to user
// devices via Firebase Cloud Messaging (FCM HTTP v1). It is used by the
// device-security (anti-theft) service so that a remote command
// (locate/lock/wipe/ring/selfie) reaches the device immediately instead of
// waiting for the next poll cycle.
//
// The service is fully config-gated: when no FCM service-account JSON or
// project id is configured it becomes a no-op that logs once and returns nil,
// so anti-theft continues to work via polling with zero external dependency.
package push

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"

	"orbguard-lab/pkg/logger"
)

// fcmScope is the OAuth2 scope required to send FCM messages via HTTP v1.
const fcmScope = "https://www.googleapis.com/auth/firebase.messaging"

// fcmSendTimeout bounds a single FCM send (token mint + HTTP POST).
const fcmSendTimeout = 10 * time.Second

// TokenStore is the minimal persistence surface the push service needs to
// resolve a device's current FCM token and to clear it when FCM reports the
// token is no longer valid (UNREGISTERED). It is satisfied by
// repository.DeviceSecurityRepository.
type TokenStore interface {
	GetToken(ctx context.Context, deviceID string) (string, error)
	ClearToken(ctx context.Context, deviceID string) error
}

// Sender delivers push notifications to a device. NotifyCommand tells a device
// that a remote command is pending so it polls immediately.
type Sender interface {
	NotifyCommand(ctx context.Context, deviceID string) error
	Enabled() bool
}

// Config holds the FCM configuration consumed by the push service.
type Config struct {
	// Enabled is the operator master switch. When false the service is a
	// no-op regardless of credentials.
	Enabled bool
	// ProjectID is the Firebase/GCP project id (used in the v1 send URL).
	ProjectID string
	// ServiceAccountJSON is either the raw service-account JSON content or a
	// path to a file containing it. Both forms are supported.
	ServiceAccountJSON string
}

// Service is the FCM HTTP v1 implementation of Sender. The zero value is not
// usable; construct it with NewService.
type Service struct {
	projectID   string
	sendURL     string
	tokenSource oauth2.TokenSource
	httpClient  *http.Client
	store       TokenStore
	logger      *logger.Logger

	// enabled is true only when master switch is on AND credentials parsed.
	enabled bool

	// disabledOnce guards the single "push disabled" log line so a no-op
	// service does not spam logs on every command.
	disabledOnce sync.Once
}

// NewService constructs an FCM push Sender from config. It never returns an
// error: when the service cannot be enabled (master switch off, missing
// project id / service-account JSON, or unparseable credentials) it returns a
// no-op Service that logs the reason once on first use and always returns nil
// from NotifyCommand. This keeps anti-theft working via polling.
//
// store may be nil; token persistence/clearing is then skipped (the service
// can still send if a token is supplied, but NotifyCommand resolves tokens via
// the store, so a nil store effectively disables sending).
func NewService(cfg Config, store TokenStore, log *logger.Logger) *Service {
	l := log.WithComponent("push-fcm")
	s := &Service{
		store:      store,
		logger:     l,
		httpClient: &http.Client{Timeout: fcmSendTimeout},
	}

	if !cfg.Enabled {
		l.Info().Msg("push disabled (push.enabled=false)")
		return s
	}
	if strings.TrimSpace(cfg.ProjectID) == "" || strings.TrimSpace(cfg.ServiceAccountJSON) == "" {
		l.Info().Msg("push disabled (no FCM credentials)")
		return s
	}

	jsonKey, err := loadServiceAccountJSON(cfg.ServiceAccountJSON)
	if err != nil {
		l.Error().Err(err).Msg("push disabled (failed to load FCM service-account JSON)")
		return s
	}

	jwtCfg, err := google.JWTConfigFromJSON(jsonKey, fcmScope)
	if err != nil {
		l.Error().Err(err).Msg("push disabled (invalid FCM service-account JSON)")
		return s
	}

	// jwt.Config.TokenSource performs the OAuth2 JWT -> access-token exchange
	// and caches the access token until it expires, refreshing automatically.
	s.tokenSource = oauth2.ReuseTokenSource(nil, jwtCfg.TokenSource(context.Background()))
	s.projectID = cfg.ProjectID
	s.sendURL = fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages", cfg.ProjectID)
	s.enabled = true

	l.Info().Str("project_id", cfg.ProjectID).Msg("FCM push service initialized")
	return s
}

// Enabled reports whether the service will actually send pushes.
func (s *Service) Enabled() bool { return s.enabled }

// logDisabledOnce logs the no-op notice exactly once.
func (s *Service) logDisabledOnce() {
	s.disabledOnce.Do(func() {
		s.logger.Info().Msg("push disabled (no FCM credentials)")
	})
}

// NotifyCommand sends a high-priority data push telling the device that a
// remote command is pending, so it polls for and executes it immediately.
//
// It is best-effort by contract: when the service is disabled, the device has
// no registered token, or FCM is transiently unavailable, it logs and returns
// nil (or a non-fatal error) — the caller must never let a push failure block
// command creation, since the command is still delivered by polling.
func (s *Service) NotifyCommand(ctx context.Context, deviceID string) error {
	if !s.enabled || s.store == nil {
		s.logDisabledOnce()
		return nil
	}

	token, err := s.store.GetToken(ctx, deviceID)
	if err != nil {
		s.logger.Warn().Err(err).Str("device_id", deviceID).Msg("failed to load FCM token for push")
		return nil
	}
	if strings.TrimSpace(token) == "" {
		// No token registered for this device: polling-only. Not an error.
		s.logger.Debug().Str("device_id", deviceID).Msg("no FCM token registered; relying on polling")
		return nil
	}

	return s.send(ctx, deviceID, token, map[string]string{
		"type":      "command_pending",
		"device_id": deviceID,
	})
}

// send posts a single data message to FCM HTTP v1. On a 404/UNREGISTERED (or
// INVALID_ARGUMENT for a malformed token) response it clears the stored token
// so the dead token is not reused.
func (s *Service) send(ctx context.Context, deviceID, token string, data map[string]string) error {
	sendCtx, cancel := context.WithTimeout(ctx, fcmSendTimeout)
	defer cancel()

	tok, err := s.tokenSource.Token()
	if err != nil {
		s.logger.Warn().Err(err).Msg("failed to mint FCM access token")
		return fmt.Errorf("mint FCM access token: %w", err)
	}

	payload := fcmV1Message{}
	payload.Message.Token = token
	payload.Message.Data = data
	// High priority so anti-theft commands wake the device promptly.
	payload.Message.Android.Priority = "high"
	payload.Message.APNS.Headers = map[string]string{"apns-priority": "10"}

	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal FCM message: %w", err)
	}

	req, err := http.NewRequestWithContext(sendCtx, http.MethodPost, s.sendURL, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("build FCM request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+tok.AccessToken)
	req.Header.Set("Content-Type", "application/json")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		s.logger.Warn().Err(err).Str("device_id", deviceID).Msg("FCM send failed (transport)")
		return fmt.Errorf("FCM send: %w", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 64*1024))

	if resp.StatusCode == http.StatusOK {
		s.logger.Debug().Str("device_id", deviceID).Msg("FCM command_pending push delivered")
		return nil
	}

	// Decode the FCM error envelope to detect an unregistered/invalid token.
	if s.isUnregistered(resp.StatusCode, respBody) {
		s.logger.Info().
			Str("device_id", deviceID).
			Int("status", resp.StatusCode).
			Msg("FCM token unregistered; clearing stored token")
		if clearErr := s.store.ClearToken(sendCtx, deviceID); clearErr != nil {
			s.logger.Warn().Err(clearErr).Str("device_id", deviceID).Msg("failed to clear unregistered FCM token")
		}
		return nil
	}

	s.logger.Warn().
		Str("device_id", deviceID).
		Int("status", resp.StatusCode).
		Str("response", string(respBody)).
		Msg("FCM send returned non-OK status")
	return fmt.Errorf("FCM send returned status %d", resp.StatusCode)
}

// isUnregistered reports whether an FCM error response indicates the token is
// no longer valid and should be cleared. FCM HTTP v1 returns 404 with
// error.status == "NOT_FOUND" and an UNREGISTERED detail for a stale token,
// and 400 INVALID_ARGUMENT for a structurally invalid token.
func (s *Service) isUnregistered(status int, body []byte) bool {
	if status != http.StatusNotFound && status != http.StatusBadRequest {
		return false
	}

	var env struct {
		Error struct {
			Status  string `json:"status"`
			Message string `json:"message"`
			Details []struct {
				ErrorCode string `json:"errorCode"`
			} `json:"details"`
		} `json:"error"`
	}
	if err := json.Unmarshal(body, &env); err != nil {
		// On a 404 we cannot parse, conservatively treat as unregistered.
		return status == http.StatusNotFound
	}

	for _, d := range env.Error.Details {
		if d.ErrorCode == "UNREGISTERED" {
			return true
		}
	}
	if status == http.StatusNotFound && env.Error.Status == "NOT_FOUND" {
		return true
	}
	if status == http.StatusBadRequest &&
		strings.Contains(strings.ToUpper(env.Error.Message), "REGISTRATION") {
		return true
	}
	return false
}

// fcmV1Message is the FCM HTTP v1 send envelope (subset used here).
type fcmV1Message struct {
	Message struct {
		Token   string            `json:"token"`
		Data    map[string]string `json:"data,omitempty"`
		Android struct {
			Priority string `json:"priority,omitempty"`
		} `json:"android,omitempty"`
		APNS struct {
			Headers map[string]string `json:"headers,omitempty"`
		} `json:"apns,omitempty"`
	} `json:"message"`
}

// loadServiceAccountJSON accepts either raw JSON content or a filesystem path
// to the service-account JSON and returns the JSON bytes. Content is detected
// by a leading '{' after trimming whitespace.
func loadServiceAccountJSON(value string) ([]byte, error) {
	trimmed := strings.TrimSpace(value)
	if strings.HasPrefix(trimmed, "{") {
		return []byte(trimmed), nil
	}
	data, err := os.ReadFile(trimmed)
	if err != nil {
		return nil, fmt.Errorf("read service-account file %q: %w", trimmed, err)
	}
	return data, nil
}
