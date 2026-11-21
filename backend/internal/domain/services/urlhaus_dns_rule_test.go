package services

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/sources"
	"orbguard-lab/internal/sources/free/abusech"
	"orbguard-lab/pkg/logger"
)

// exportOnlyTransport answers the URLhaus export host from memory and hands
// every other request to the original transport, so nothing reaches abuse.ch.
type exportOnlyTransport struct {
	body string
	next http.RoundTripper
}

func (tr exportOnlyTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	if req.URL.Hostname() != "urlhaus-api.abuse.ch" {
		return tr.next.RoundTrip(req)
	}
	return &http.Response{
		StatusCode: http.StatusOK,
		Header:     http.Header{},
		Body:       io.NopCloser(strings.NewReader(tr.body)),
		Request:    req,
	}, nil
}

// dnsRuleHostsFor runs rows through the real connector and normalizer and
// returns the host the DNS rule loader derives from each stored URL.
func dnsRuleHostsFor(t *testing.T, rawURLs []string) map[string]string {
	t.Helper()
	const when = "2026-11-20 10:00:00"
	var body strings.Builder
	body.WriteString("# id,dateadded,url,url_status,last_online,threat,tags,urlhaus_link,reporter\n")
	for i, raw := range rawURLs {
		fmt.Fprintf(&body, "\"%d\",\"%s\",\"%s\",\"online\",\"%s\",\"malware_download\",\"elf\",\"https://urlhaus.abuse.ch/url/%d/\",\"r\"\n",
			i+1, when, raw, when, i+1)
	}

	original := http.DefaultTransport
	http.DefaultTransport = exportOnlyTransport{body: body.String(), next: original}
	t.Cleanup(func() { http.DefaultTransport = original })

	log := logger.New(logger.Config{Level: "error", Format: "json"})
	conn := abusech.NewURLhausConnector(log)
	if err := conn.Configure(sources.ConnectorConfig{Enabled: true, UpdateInterval: time.Hour, APIKey: "test-marker"}); err != nil {
		t.Fatal(err)
	}
	result, err := conn.Fetch(context.Background())
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	normalized, _ := NewNormalizer(log).NormalizeBatch(result.RawIndicators)

	hosts := make(map[string]string)
	for _, indicator := range normalized {
		if indicator.Type == models.IndicatorTypeURL {
			hosts[indicator.Value] = extractDomainFromURL(indicator.Value)
		}
	}
	return hosts
}

func TestHostileURLhausRowsCannotBecomeASharedHostDNSRule(t *testing.T) {
	hostile := []string{
		"http://https://github.com/x",
		"http://https://raw.githubusercontent.com/u/r/x.sh",
		"https://https://github.com/x",
		"https://http://github.com/x",
		"http://http://github.com/x",
		"http://https:/github.com/x",
		"http://https:443//github.com/x",
		"HTTP://https://github.com/x",
		"http://evil.example://github.com/x",
		"http:////github.com/x",
		"http://github.com:80@evil.example/x",
		"http://evil.example:80@github.com/x",
		"http://github.com../x",
		"http://GITHUB.com/x",
		"ftp://github.com/x",
	}
	rows := append([]string{"http://bad.example/a.sh"}, hostile...)

	// Every combination of the pieces parsers tend to disagree on.
	for _, scheme := range []string{"http://", "https://", "HTTP://", "http:/", "http:", "ftp://"} {
		for _, authority := range []string{
			"https:", "http:", "github.com", "github.com:", "github.com.", "github.com..",
			"evil.example:", "evil.example:80", "u@github.com", "github.com@evil.example",
			"github.com:80@evil.example", "[::1]", "evil.example%2f",
		} {
			for _, path := range []string{"/x", "//github.com/x", "://github.com/x", "?a=//github.com/", "#//github.com/"} {
				rows = append(rows, scheme+authority+path)
			}
		}
	}

	hosts := dnsRuleHostsFor(t, rows)
	if hosts["http://bad.example/a.sh"] != "bad.example" {
		t.Fatalf("the ordinary row was lost: %v", hosts)
	}
	for stored, host := range hosts {
		if host == "github.com" || strings.HasSuffix(host, ".github.com") ||
			host == "githubusercontent.com" || strings.HasSuffix(host, ".githubusercontent.com") {
			t.Errorf("stored URL %q becomes a DNS block on %q", stored, host)
		}
		judged, ok := models.IndicatorURLHost(stored)
		if !ok || judged != host {
			t.Errorf("stored URL %q: rule host %q, parser host %q (ok=%v)", stored, host, judged, ok)
		}
	}
}

func TestExtractDomainFromURLKeepsOrdinaryValues(t *testing.T) {
	for raw, want := range map[string]string{
		"https://Example.com:8443/a":   "example.com",
		"http://sub.example.com/a?b=c": "sub.example.com",
		"example.com/path":             "example.com",
		"example.com/a://b":            "example.com",
		"http://203.0.113.9/x":         "203.0.113.9",
		"http://https://github.com/x":  "",
		"ftp://example.com/x":          "",
	} {
		if got := extractDomainFromURL(raw); got != want {
			t.Errorf("extractDomainFromURL(%q) = %q, want %q", raw, got, want)
		}
	}
}

func TestURLhausDNSRuleHostMatchesTheHostTheConnectorJudged(t *testing.T) {
	got := dnsRuleHostsFor(t, []string{
		"http://bad.example/a.sh",
		"http://bad2.example:8080//bin/x.sh",
		"http://203.0.113.9:8080/bin",
		"http://https://github.com/x",
		"http://evil.example://github.com/x",
		"HTTP://bad3.example/x",
	})
	want := map[string]string{
		"http://bad.example/a.sh":            "bad.example",
		"http://bad2.example:8080//bin/x.sh": "bad2.example",
		"http://203.0.113.9:8080/bin":        "203.0.113.9",
	}
	if len(got) != len(want) {
		t.Fatalf("stored %v, want %v", got, want)
	}
	for stored, host := range want {
		if got[stored] != host {
			t.Errorf("%q derives %q, want %q", stored, got[stored], host)
		}
	}
}
