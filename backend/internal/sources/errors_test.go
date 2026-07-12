package sources

import (
	"errors"
	"fmt"
	"net/http"
	"testing"
	"time"

	"orbguard-lab/internal/domain/models"
)

func respWithHeader(key, value string) *http.Response {
	h := http.Header{}
	if key != "" {
		h.Set(key, value)
	}
	return &http.Response{StatusCode: http.StatusTooManyRequests, Header: h}
}

func TestParseRetryAfter_HeaderSeconds(t *testing.T) {
	resp := respWithHeader("Retry-After", "3600")
	got := ParseRetryAfter(resp, nil, time.Minute)
	if got != time.Hour {
		t.Fatalf("expected 1h, got %s", got)
	}
}

func TestParseRetryAfter_HeaderHTTPDate(t *testing.T) {
	future := time.Now().Add(2 * time.Hour).UTC().Format(http.TimeFormat)
	resp := respWithHeader("Retry-After", future)
	got := ParseRetryAfter(resp, nil, time.Minute)
	if got < 119*time.Minute || got > 121*time.Minute {
		t.Fatalf("expected ~2h, got %s", got)
	}
}

func TestParseRetryAfter_DRFBody(t *testing.T) {
	// Live production error observed from Koodous
	body := []byte(`{"detail":"Request was throttled. Expected available in 29895 seconds."}`)
	got := ParseRetryAfter(respWithHeader("", ""), body, time.Minute)
	if got != 29895*time.Second {
		t.Fatalf("expected 29895s, got %s", got)
	}
}

func TestParseRetryAfter_Fallback(t *testing.T) {
	got := ParseRetryAfter(respWithHeader("", ""), []byte("no hints here"), 6*time.Hour)
	if got != 6*time.Hour {
		t.Fatalf("expected fallback 6h, got %s", got)
	}
}

func TestParseRetryAfter_ClampMin(t *testing.T) {
	resp := respWithHeader("Retry-After", "1")
	got := ParseRetryAfter(resp, nil, time.Minute)
	if got != MinRateLimitBackoff {
		t.Fatalf("expected clamp to %s, got %s", MinRateLimitBackoff, got)
	}
}

func TestParseRetryAfter_ClampMax(t *testing.T) {
	resp := respWithHeader("Retry-After", "999999999")
	got := ParseRetryAfter(resp, nil, time.Minute)
	if got != MaxRateLimitBackoff {
		t.Fatalf("expected clamp to %s, got %s", MaxRateLimitBackoff, got)
	}
}

func TestRateLimitErrorDetection(t *testing.T) {
	base := NewRateLimitError("TestProvider", respWithHeader("Retry-After", "120"), nil, time.Minute)
	wrapped := fmt.Errorf("fetch failed: %w", base)

	rle, ok := AsRateLimit(wrapped)
	if !ok {
		t.Fatal("expected AsRateLimit to detect wrapped RateLimitError")
	}
	if rle.RetryAfter() != 2*time.Minute {
		t.Fatalf("expected 2m, got %s", rle.RetryAfter())
	}

	// Duck-typed detection (as used by the aggregator, which does not
	// import this package)
	var duck interface {
		error
		RetryAfter() time.Duration
		IsRepeat() bool
	}
	if !errors.As(wrapped, &duck) {
		t.Fatal("expected duck-typed detection to work")
	}
	if duck.IsRepeat() {
		t.Fatal("fresh rate limit error should not be a repeat")
	}
}

func TestPlanLimitErrorDetection(t *testing.T) {
	base := &PlanLimitError{Provider: "TestProvider", Message: "GNQL requires a paid plan"}
	wrapped := fmt.Errorf("fetch failed: %w", base)

	if _, ok := AsPlanLimit(wrapped); !ok {
		t.Fatal("expected AsPlanLimit to detect wrapped PlanLimitError")
	}

	var duck interface {
		error
		IsPlanLimit() bool
	}
	if !errors.As(wrapped, &duck) {
		t.Fatal("expected duck-typed detection to work")
	}
}

func TestBaseConnectorBackoffWindow(t *testing.T) {
	c := NewBaseConnector("test", "Test", models.SourceCategoryIPRep, models.SourceTypeAPI)

	// No backoff initially
	if remaining, _ := c.BackoffRemaining(); remaining != 0 {
		t.Fatalf("expected no backoff, got %s", remaining)
	}

	c.SetBackoff(time.Hour)

	// The 429 that triggered SetBackoff is the announcement, so every
	// observation inside the window is a quiet repeat
	remaining, first := c.BackoffRemaining()
	if remaining <= 0 {
		t.Fatalf("expected active backoff, got remaining=%s", remaining)
	}
	if first {
		t.Fatal("observations within a window announced by SetBackoff must be quiet repeats")
	}
	if _, first = c.BackoffRemaining(); first {
		t.Fatal("second observation within the same window must not be 'first'")
	}
}
