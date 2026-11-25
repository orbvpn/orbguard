package services

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"testing"

	"orbguard-lab/pkg/logger"
)

type sbKeyCapture struct{ url, header string }

func (k *sbKeyCapture) RoundTrip(r *http.Request) (*http.Response, error) {
	k.url, k.header = r.URL.String(), r.Header.Get("X-Goog-Api-Key")
	return nil, errors.New("dial tcp: i/o timeout") // no socket is opened
}

func TestURLReputationSafeBrowsingKeyTravelsInTheHeaderOnly(t *testing.T) {
	const key = "AIzaSECRETKEYxxxxxxxxxxxxxxxxxxxxxxxxx"
	capture := &sbKeyCapture{}
	c := NewGoogleSafeBrowsingClient(SafeBrowsingConfig{APIKey: key}, logger.NewDefault())
	c.httpClient = &http.Client{Transport: capture}

	_, err := c.CheckURLs(context.Background(), []string{"http://example.test/"})
	if err == nil {
		t.Fatal("a transport failure was not reported")
	}
	if strings.Contains(capture.url, key) || strings.Contains(capture.url, "key=") {
		t.Errorf("the key is in the URL %q", capture.url)
	}
	if capture.header != key {
		t.Errorf("X-Goog-Api-Key is %q", capture.header)
	}
	if strings.Contains(err.Error(), key) {
		t.Errorf("the key is in the error: %v", err)
	}
}
