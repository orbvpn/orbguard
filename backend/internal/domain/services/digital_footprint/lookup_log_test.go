package digital_footprint

import (
	"bytes"
	"context"
	"errors"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/rs/zerolog"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/brokers"
	"orbguard-lab/pkg/logger"
)

// unreachableProvider fails every request, so http.Client wraps the failure
// in a url.Error that holds the request URL. It counts requests whose URL
// carries the marker, to show the marker really was in the URL.
type unreachableProvider struct {
	marker string
	seen   atomic.Int64
}

func (p *unreachableProvider) RoundTrip(r *http.Request) (*http.Response, error) {
	if strings.Contains(r.URL.String(), p.marker) {
		p.seen.Add(1)
	}
	return nil, errors.New("connection refused")
}

func TestFootprintLookupFailureLogsNoAddress(t *testing.T) {
	const email = "marker.person@example.com"
	logs := &bytes.Buffer{}
	scanner := NewDarkWebScanner(scanTestRedis(t), &logger.Logger{Logger: zerolog.New(logs)})
	provider := &unreachableProvider{marker: "marker.person"}
	scanner.httpClient = &http.Client{Transport: provider}

	if _, _, err := scanner.Scan(context.Background(), email, ""); err != nil {
		t.Fatal(err)
	}
	if provider.seen.Load() == 0 {
		t.Fatal("control: no request carried the address")
	}
	if strings.Contains(logs.String(), "marker.person") {
		t.Errorf("the address reached the log: %s", logs)
	}
	if got := strings.Count(logs.String(), `"reason":"unreachable"`); got != 2 {
		t.Errorf("want 2 lines with the failure reason, got %d: %s", got, logs)
	}
}

func TestFootprintBadAddressLogsNoAddress(t *testing.T) {
	// A control character makes URL parsing fail, and that error quotes the URL.
	const email = "marker.person\x7f@example.com"
	logs := &bytes.Buffer{}
	scanner := NewDarkWebScanner(scanTestRedis(t), &logger.Logger{Logger: zerolog.New(logs)})
	scanner.httpClient = &http.Client{Transport: &unreachableProvider{marker: "marker.person"}}

	if _, _, err := scanner.Scan(context.Background(), email, ""); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(logs.String(), "person") {
		t.Errorf("the address reached the log: %s", logs)
	}
}

func TestLookupFailureReasons(t *testing.T) {
	for want, err := range map[string]error{
		"canceled": context.Canceled,
		"timeout":  context.DeadlineExceeded,
		"failed":   errors.New("HIBP API returned status 401"),
	} {
		if got := lookupFailure(err); got != want {
			t.Errorf("lookupFailure(%v) = %q, want %q", err, got, want)
		}
	}
}

func TestBrokerLookupFailureLogsNoName(t *testing.T) {
	logs := &bytes.Buffer{}
	// The scanner logs from several goroutines.
	scanner := NewBrokerScanner(brokers.NewBrokerDatabase(), scanTestRedis(t), &logger.Logger{Logger: zerolog.New(zerolog.SyncWriter(logs))})
	provider := &unreachableProvider{marker: "Markerperson"}
	scanner.httpClient = &http.Client{Transport: provider}

	if _, _, err := scanner.Scan(context.Background(), BrokerScanRequest{FirstName: "Markerperson", LastName: "Example"}); err != nil {
		t.Fatal(err)
	}
	if provider.seen.Load() == 0 {
		t.Fatal("control: no request carried the name")
	}
	if strings.Contains(logs.String(), "Markerperson") {
		t.Errorf("the name reached the log")
	}
}

func TestSocialLookupFailureLogsNoUsername(t *testing.T) {
	logs := &bytes.Buffer{}
	scanner := NewSocialMediaScanner(scanTestRedis(t), &logger.Logger{Logger: zerolog.New(logs)})
	provider := &unreachableProvider{marker: "markerperson"}
	scanner.httpClient = &http.Client{Transport: provider}

	_, err := scanner.Scan(context.Background(), SocialScanRequest{
		Profiles: []models.SocialProfileInfo{{Platform: "facebook", Username: "markerperson"}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if provider.seen.Load() == 0 {
		t.Fatal("control: no request carried the username")
	}
	if strings.Contains(logs.String(), "markerperson") {
		t.Errorf("the username reached the log")
	}
}
