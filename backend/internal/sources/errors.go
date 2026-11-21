package sources

import (
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"strconv"
	"time"
)

const (
	// MinRateLimitBackoff is the minimum backoff applied when a provider
	// rate-limits us but gives no usable Retry-After hint.
	MinRateLimitBackoff = 1 * time.Minute
	// MaxRateLimitBackoff caps provider-supplied retry hints so a bogus
	// header cannot park a source for weeks.
	MaxRateLimitBackoff = 48 * time.Hour
)

// RateLimitError indicates the provider returned HTTP 429 (or an equivalent
// throttle response). Schedulers should honor RetryAfter() instead of
// retrying on the normal update interval, and must not treat this as a
// source failure (no error_count escalation).
type RateLimitError struct {
	// Provider is the human-readable source name (e.g. "AbuseIPDB").
	Provider string
	// Wait is how long the provider asked us to back off.
	Wait time.Duration
	// Message is the provider's original throttle message (truncated).
	Message string
	// Repeat is true when this error was synthesized because the connector
	// is still inside a previously announced backoff window (i.e. nothing
	// new happened; callers should log quietly).
	Repeat bool
}

// Error implements the error interface.
func (e *RateLimitError) Error() string {
	if e.Message != "" {
		return fmt.Sprintf("%s rate limited, retry after %s: %s", e.Provider, e.Wait.Round(time.Second), e.Message)
	}
	return fmt.Sprintf("%s rate limited, retry after %s", e.Provider, e.Wait.Round(time.Second))
}

// RetryAfter returns how long to wait before the next attempt.
func (e *RateLimitError) RetryAfter() time.Duration { return e.Wait }

// IsRepeat reports whether this is a repeat notification within an
// already-announced backoff window.
func (e *RateLimitError) IsRepeat() bool { return e.Repeat }

// PlanLimitError indicates the configured API key's plan does not permit the
// requested capability (HTTP 401/403 on an endpoint that requires a higher
// tier). This is a persistent condition: the source should be marked in
// error state with an honest explanation rather than retried aggressively.
type PlanLimitError struct {
	Provider string
	Message  string
}

// Error implements the error interface.
func (e *PlanLimitError) Error() string {
	return fmt.Sprintf("%s plan limitation: %s", e.Provider, e.Message)
}

// IsPlanLimit marks this error type for duck-typed detection.
func (e *PlanLimitError) IsPlanLimit() bool { return true }

// FetchDeferredError means the connector chose not to call the provider
// because its own pacing window is still open. Nothing was requested and
// nothing failed, so callers must not record a failure, a success or a rate
// limit for the source.
type FetchDeferredError struct {
	Provider string
	Wait     time.Duration
}

// Error implements the error interface.
func (e *FetchDeferredError) Error() string {
	return fmt.Sprintf("%s fetch deferred, next attempt in %s", e.Provider, e.Wait.Round(time.Second))
}

// IsFetchDeferred marks this error type for duck-typed detection.
func (e *FetchDeferredError) IsFetchDeferred() bool { return true }

// FetchBlockedError means a feed cannot work until someone acts: the provider
// refused the key or no longer serves the address, or no key is configured.
// Unlike a deferral it is a failure and must reach the job and the source row,
// also while the connector holds off and sends no request. It unwraps to its
// PlanLimitError so existing plan-limit checks still recognise it.
type FetchBlockedError struct {
	PlanLimitError
	// Requested is true when this attempt reached the provider.
	Requested bool
}

// Error implements the error interface.
func (e *FetchBlockedError) Error() string {
	return fmt.Sprintf("%s fetch blocked: %s", e.Provider, e.Message)
}

// Unwrap exposes the underlying plan-limit error.
func (e *FetchBlockedError) Unwrap() error { return &e.PlanLimitError }

// IsFetchBlocked marks this error type for duck-typed detection.
func (e *FetchBlockedError) IsFetchBlocked() bool { return true }

// RequestSent reports whether this attempt reached the provider.
func (e *FetchBlockedError) RequestSent() bool { return e.Requested }

// AsRateLimit extracts a *RateLimitError from an error chain.
func AsRateLimit(err error) (*RateLimitError, bool) {
	var rle *RateLimitError
	if errors.As(err, &rle) {
		return rle, true
	}
	return nil, false
}

// AsPlanLimit extracts a *PlanLimitError from an error chain.
func AsPlanLimit(err error) (*PlanLimitError, bool) {
	var ple *PlanLimitError
	if errors.As(err, &ple) {
		return ple, true
	}
	return nil, false
}

// throttleSecondsRe matches Django-REST-framework style throttle messages,
// e.g. "Request was throttled. Expected available in 29895 seconds."
var throttleSecondsRe = regexp.MustCompile(`available in (\d+)(?:\.\d+)? seconds`)

// ParseRetryAfter determines how long to back off after a 429 response.
// It checks, in order:
//  1. The Retry-After header (delta-seconds or HTTP-date form, RFC 9110)
//  2. A DRF-style "available in N seconds" hint in the response body
//  3. The provided fallback
//
// The result is clamped to [MinRateLimitBackoff, MaxRateLimitBackoff].
func ParseRetryAfter(resp *http.Response, body []byte, fallback time.Duration) time.Duration {
	wait := fallback

	if resp != nil {
		if ra := resp.Header.Get("Retry-After"); ra != "" {
			if secs, err := strconv.ParseInt(ra, 10, 64); err == nil && secs > 0 {
				wait = time.Duration(secs) * time.Second
			} else if t, err := http.ParseTime(ra); err == nil {
				if d := time.Until(t); d > 0 {
					wait = d
				}
			}
		} else if m := throttleSecondsRe.FindSubmatch(body); len(m) == 2 {
			if secs, err := strconv.ParseInt(string(m[1]), 10, 64); err == nil && secs > 0 {
				wait = time.Duration(secs) * time.Second
			}
		}
	} else if m := throttleSecondsRe.FindSubmatch(body); len(m) == 2 {
		if secs, err := strconv.ParseInt(string(m[1]), 10, 64); err == nil && secs > 0 {
			wait = time.Duration(secs) * time.Second
		}
	}

	if wait < MinRateLimitBackoff {
		wait = MinRateLimitBackoff
	}
	if wait > MaxRateLimitBackoff {
		wait = MaxRateLimitBackoff
	}
	return wait
}

// truncate shortens provider messages embedded into errors/last_error.
func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}

// NewRateLimitError builds a RateLimitError from a 429 HTTP response.
func NewRateLimitError(provider string, resp *http.Response, body []byte, fallback time.Duration) *RateLimitError {
	return &RateLimitError{
		Provider: provider,
		Wait:     ParseRetryAfter(resp, body, fallback),
		Message:  truncate(string(body), 200),
	}
}
