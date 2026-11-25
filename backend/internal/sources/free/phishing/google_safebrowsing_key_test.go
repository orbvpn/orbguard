package phishing

import (
	"context"
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"

	"orbguard-lab/internal/sources"
	"orbguard-lab/pkg/logger"
)

// keyCapture answers every request itself (no socket is opened) and records
// where the key travelled. With fail set it returns a transport error, which
// http.Client wraps in a *url.Error that quotes the request URL.
type keyCapture struct {
	urls, headers []string
	fail          bool
}

func (k *keyCapture) RoundTrip(r *http.Request) (*http.Response, error) {
	k.urls = append(k.urls, r.URL.String())
	k.headers = append(k.headers, r.Header.Get("X-Goog-Api-Key"))
	if k.fail {
		return nil, errors.New("dial tcp: i/o timeout")
	}
	return &http.Response{StatusCode: http.StatusOK, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(`{}`)), Request: r}, nil
}

const testSafeBrowsingKey = "AIzaSECRETKEYxxxxxxxxxxxxxxxxxxxxxxxxx"

func TestSafeBrowsingKeyTravelsInTheHeaderOnly(t *testing.T) {
	for _, fail := range []bool{false, true} {
		capture := &keyCapture{fail: fail}
		c := NewSafeBrowsingConnector(logger.NewDefault())
		if err := c.Configure(sources.ConnectorConfig{Enabled: true, APIKey: testSafeBrowsingKey}); err != nil {
			t.Fatal(err)
		}
		c.client = &http.Client{Transport: capture}

		_, errList := c.fetchThreatListUpdates(context.Background())
		_, errLookup := c.LookupURLs(context.Background(), []string{"http://example.test/"})
		if len(capture.urls) != 2 {
			t.Fatalf("fail=%v: %d requests, want 2", fail, len(capture.urls))
		}
		for i, u := range capture.urls {
			if strings.Contains(u, testSafeBrowsingKey) || strings.Contains(u, "key=") {
				t.Errorf("fail=%v: the key is in the URL %q", fail, u)
			}
			if capture.headers[i] != testSafeBrowsingKey {
				t.Errorf("fail=%v: X-Goog-Api-Key is %q", fail, capture.headers[i])
			}
		}
		for _, err := range []error{errList, errLookup} {
			if fail && err == nil {
				t.Fatalf("a transport failure was not reported")
			}
			if err != nil && strings.Contains(err.Error(), testSafeBrowsingKey) {
				t.Errorf("the key is in the error: %v", err)
			}
		}
	}
}
