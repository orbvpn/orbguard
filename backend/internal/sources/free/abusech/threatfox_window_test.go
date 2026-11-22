package abusech

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// threatFoxStub is an HTTP/2 TLS server on 127.0.0.1 that records the days of
// every get_iocs request. In reset mode it sends the response headers and part
// of the body, then aborts the handler, which makes Go's HTTP/2 server reset
// the stream with INTERNAL_ERROR: the failure production logged.
type threatFoxStub struct {
	mu    sync.Mutex
	days  []int
	reset bool
	body  string
}

func (s *threatFoxStub) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Query string `json:"query"`
		Days  int    `json:"days"`
	}
	raw, _ := io.ReadAll(r.Body)
	_ = json.Unmarshal(raw, &req)
	s.mu.Lock()
	s.days = append(s.days, req.Days)
	reset, body := s.reset, s.body
	s.mu.Unlock()

	w.Header().Set("Content-Type", "application/json")
	if reset {
		w.WriteHeader(http.StatusOK)
		_, _ = io.WriteString(w, `{"query_status":"ok","data":[{"id":"1",`)
		w.(http.Flusher).Flush()
		panic(http.ErrAbortHandler)
	}
	_, _ = io.WriteString(w, body)
}

func (s *threatFoxStub) set(reset bool, body string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.reset, s.body = reset, body
}

func (s *threatFoxStub) lastDays() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.days) == 0 {
		return 0
	}
	return s.days[len(s.days)-1]
}

const threatFoxOK = `{"query_status":"ok","data":[{"id":"1","ioc":"bad.example","ioc_type":"domain","threat_type":"botnet_cc","confidence_level":80,"first_seen":"2026-11-22 04:00:00 UTC"}]}`

func TestThreatFoxWindowFollowsTheLastSuccess(t *testing.T) {
	stub := &threatFoxStub{body: threatFoxOK}
	srv := httptest.NewUnstartedServer(stub)
	srv.EnableHTTP2 = true
	srv.StartTLS()
	t.Cleanup(srv.Close)

	clock := time.Date(2026, 11, 22, 6, 0, 0, 0, time.UTC)
	c := NewThreatFoxConnector(testLogger(io.Discard))
	c.client = srv.Client()
	c.apiURL = srv.URL + "/api/v1/"
	c.now = func() time.Time { return clock }
	ctx := context.Background()

	fetch := func(step string, wantDays int, wantErr string) error {
		t.Helper()
		result, err := c.Fetch(ctx)
		if got := stub.lastDays(); got != wantDays {
			t.Fatalf("%s: asked for %d days, want %d", step, got, wantDays)
		}
		switch {
		case wantErr == "" && err != nil:
			t.Fatalf("%s: %v", step, err)
		case wantErr == "" && len(result.RawIndicators) != 1:
			t.Fatalf("%s: %d indicators", step, len(result.RawIndicators))
		case wantErr != "" && (err == nil || !strings.Contains(err.Error(), wantErr)):
			t.Fatalf("%s: error %v, want one containing %q", step, err, wantErr)
		}
		return err
	}

	fetch("first fetch after start", 7, "")

	clock = clock.Add(15 * time.Minute)
	fetch("15 minutes after a success", 1, "")
	lastOK := clock

	// A stream reset 19 hours later: still the short window, and it must
	// not count as a success.
	stub.set(true, "")
	clock = lastOK.Add(19 * time.Hour)
	if err := fetch("stream reset", 1, "failed to read response: stream error"); !strings.Contains(err.Error(), "INTERNAL_ERROR; received from peer") {
		t.Fatalf("not the production failure: %v", err)
	}
	if c.lastSuccess != lastOK {
		t.Fatalf("the reset moved the last success to %v (want %v)", c.lastSuccess, lastOK)
	}

	// A refused query in a 200 answer is no success either.
	stub.set(false, `{"query_status":"illegal_search_term"}`)
	clock = lastOK.Add(19*time.Hour + 30*time.Minute)
	fetch("refused query", 1, "ThreatFox query failed")
	if c.lastSuccess != lastOK {
		t.Fatalf("the refusal moved the last success to %v", c.lastSuccess)
	}

	// 20 hours after the last success the window is the full seven days
	// again. Had either failure counted, this would still ask for one.
	stub.set(false, threatFoxOK)
	clock = lastOK.Add(20 * time.Hour)
	fetch("20 hours after the last success", 7, "")

	clock = clock.Add(15 * time.Minute)
	fetch("after the catch-up fetch", 1, "")

	stub.mu.Lock()
	defer stub.mu.Unlock()
	if len(stub.days) != 6 {
		t.Fatalf("requests: %v", stub.days)
	}
}

// A fresh process whose 7-day request keeps failing must not ask for 7 days
// again and again: after one failed full-window request it asks for one day
// until a fetch succeeds, and only a success restarts the 20-hour rule.
func TestThreatFoxDoesNotRepeatAFailedFullWindow(t *testing.T) {
	stub := &threatFoxStub{reset: true}
	srv := httptest.NewUnstartedServer(stub)
	srv.EnableHTTP2 = true
	srv.StartTLS()
	t.Cleanup(srv.Close)

	clock := time.Date(2026, 11, 22, 6, 0, 0, 0, time.UTC)
	c := NewThreatFoxConnector(testLogger(io.Discard))
	c.client = srv.Client()
	c.apiURL = srv.URL + "/api/v1/"
	c.now = func() time.Time { return clock }

	ask := func(step string, after time.Duration, wantDays int, wantOK bool) {
		t.Helper()
		clock = clock.Add(after)
		_, err := c.Fetch(context.Background())
		if got := stub.lastDays(); got != wantDays {
			t.Fatalf("%s: asked for %d days, want %d", step, got, wantDays)
		}
		if (err == nil) != wantOK {
			t.Fatalf("%s: err=%v, want ok=%v", step, err, wantOK)
		}
	}

	ask("first fetch of the process, reset", 0, 7, false)
	ask("15 minutes later, reset", 15*time.Minute, 1, false)
	ask("30 minutes later, reset", 15*time.Minute, 1, false)
	ask("a day later, still no success", 24*time.Hour, 1, false)
	stub.set(false, threatFoxOK)
	ask("the provider answers again", 15*time.Minute, 1, true)
	ask("15 minutes after the success", 15*time.Minute, 1, true)

	// The ordinary rule again: 20 hours without a success gives one
	// full-window attempt, and its failure falls back to one day.
	stub.set(true, "")
	ask("20 hours after the last success, reset", 20*time.Hour, 7, false)
	ask("15 minutes later", 15*time.Minute, 1, false)
}
