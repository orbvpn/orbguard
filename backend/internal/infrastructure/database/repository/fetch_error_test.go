package repository

import (
	"strings"
	"testing"
)

func TestCleanFetchErrorRemovesCredentials(t *testing.T) {
	cases := []struct{ in, keep string }{
		// Go's *url.Error for a transport failure, as the Safe Browsing
		// connector produced it while the key was in the query string.
		{`failed to fetch threat lists: Post "https://safebrowsing.googleapis.com/v4/threatListUpdates:fetch?key=SECRET1": dial tcp 142.250.0.1:443: i/o timeout`,
			`failed to fetch threat lists: Post "https://safebrowsing.googleapis.com/v4/threatListUpdates:fetch?[redacted]": dial tcp 142.250.0.1:443: i/o timeout`},
		{`Get "https://api.shodan.io/shodan/host/search?key=SECRET1&query=port:22": EOF`,
			`Get "https://api.shodan.io/shodan/host/search?[redacted]": EOF`},
		{`upstream said api_key=SECRET1, retry later`, `upstream said api_key=[redacted], retry later`},
		{`Auth-Key: SECRET1 refused`, `Auth-Key: [redacted] refused`},
		{`token="SECRET1"`, `token=[redacted]`},
		{`Authorization: Bearer SECRET1abcdef`, `Authorization: Bearer [redacted]`},
		{`key AIza` + strings.Repeat("S", 35) + ` was rejected`, `key [redacted] was rejected`},
		// Ordinary errors are left as they were.
		{`failed to read response: stream error: stream ID 1; INTERNAL_ERROR; received from peer`,
			`failed to read response: stream error: stream ID 1; INTERNAL_ERROR; received from peer`},
		{`ThreatFox returned status 503: Service Unavailable`, `ThreatFox returned status 503: Service Unavailable`},
		{`Get "https://urlhaus.abuse.ch/downloads/csv_recent/": EOF`, `Get "https://urlhaus.abuse.ch/downloads/csv_recent/": EOF`},
	}
	for _, c := range cases {
		got := cleanFetchError(c.in)
		if strings.Contains(got, "SECRET1") || strings.Contains(got, strings.Repeat("S", 35)) {
			t.Errorf("secret kept: %q", got)
		}
		if got != c.keep {
			t.Errorf("cleanFetchError(%q)\n got %q\nwant %q", c.in, got, c.keep)
		}
	}
}
