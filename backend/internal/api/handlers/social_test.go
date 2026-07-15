package handlers

import (
	"net/http"
	"strings"
	"testing"
)

// statusPlatform is a checkByStatus platform (the common case).
var statusPlatform = socialPlatform{Name: "GitHub", CheckTemplate: "https://github.com/%s", Mode: checkByStatus}

// bodyPlatform is a checkByBody platform (always-200 endpoint with a marker).
var bodyPlatform = socialPlatform{Name: "Telegram", CheckTemplate: "https://t.me/%s", Mode: checkByBody, BodyMarker: "tgme_page_title"}

// keybasePlatform is the JSON-API platform.
var keybasePlatform = socialPlatform{Name: "Keybase", CheckTemplate: "https://keybase.io/_/api/1.0/user/lookup.json?username=%s", Mode: checkKeybase}

func TestClassifyPresence_StatusMode(t *testing.T) {
	cases := []struct {
		name   string
		status int
		want   string
	}{
		{"200 exists", http.StatusOK, statusFound},
		{"404 missing", http.StatusNotFound, statusNotFound},
		{"410 gone is missing", http.StatusGone, statusNotFound},
		{"301 redirect is unknown", http.StatusMovedPermanently, statusUnknown},
		{"302 login redirect is unknown", http.StatusFound, statusUnknown},
		{"401 unauthorized is unknown", http.StatusUnauthorized, statusUnknown},
		{"403 blocked is unknown", http.StatusForbidden, statusUnknown},
		{"429 rate-limited is unknown", http.StatusTooManyRequests, statusUnknown},
		{"500 error is unknown", http.StatusInternalServerError, statusUnknown},
		{"503 unavailable is unknown", http.StatusServiceUnavailable, statusUnknown},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := classifyPresence(statusPlatform, tc.status, nil); got != tc.want {
				t.Errorf("classifyPresence(status=%d) = %q, want %q", tc.status, got, tc.want)
			}
		})
	}
}

func TestClassifyPresence_BodyMode(t *testing.T) {
	cases := []struct {
		name   string
		status int
		body   string
		want   string
	}{
		{"200 with marker exists", http.StatusOK, `<div class="tgme_page_title">Someone</div>`, statusFound},
		{"200 without marker is missing", http.StatusOK, `<html>generic telegram landing</html>`, statusNotFound},
		{"404 is missing", http.StatusNotFound, "", statusNotFound},
		{"403 blocked is unknown", http.StatusForbidden, "", statusUnknown},
		{"500 error is unknown", http.StatusInternalServerError, "", statusUnknown},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := classifyPresence(bodyPlatform, tc.status, []byte(tc.body)); got != tc.want {
				t.Errorf("classifyPresence(body) = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestClassifyKeybase(t *testing.T) {
	cases := []struct {
		name   string
		status int
		body   string
		want   string
	}{
		{"code 0 exists", http.StatusOK, `{"status":{"code":0,"name":"OK"},"them":{"id":"x"}}`, statusFound},
		{"code 205 missing", http.StatusOK, `{"status":{"code":205,"name":"NOT_FOUND"}}`, statusNotFound},
		{"other code unknown", http.StatusOK, `{"status":{"code":100,"name":"INPUT_ERROR"}}`, statusUnknown},
		{"malformed body unknown", http.StatusOK, `not json`, statusUnknown},
		{"empty body unknown", http.StatusOK, ``, statusUnknown},
		{"non-200 unknown", http.StatusForbidden, `{"status":{"code":0}}`, statusUnknown},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := classifyPresence(keybasePlatform, tc.status, []byte(tc.body)); got != tc.want {
				t.Errorf("classifyKeybase = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestSocialUsernamePattern(t *testing.T) {
	valid := []string{"octocat", "user.name", "user_name", "user-name", "abc123", "a", "A1_.-"}
	for _, u := range valid {
		if !socialUsernamePattern.MatchString(u) {
			t.Errorf("expected %q to be a valid username", u)
		}
	}

	invalid := []string{
		"",                // empty
		"has space",       // space
		"user/../../etc",  // path traversal
		"user?x=1",        // query injection
		"user@host",       // '@'
		"user#frag",       // fragment
		"user%2f",         // encoded slash
		"http://evil.com", // SSRF attempt
		"名前",              // non-ASCII
		strings.Repeat("a", 65), // > 64 chars
	}
	for _, u := range invalid {
		if socialUsernamePattern.MatchString(u) {
			t.Errorf("expected %q to be rejected", u)
		}
	}
}

// TestDefaultSocialPlatforms guards the curated list and the invariant that
// every check template has exactly one %s verb and (where present) a display
// template does too.
func TestDefaultSocialPlatforms(t *testing.T) {
	platforms := defaultSocialPlatforms()
	if len(platforms) < 10 {
		t.Fatalf("expected a curated list of at least 10 platforms, got %d", len(platforms))
	}
	seen := map[string]bool{}
	for _, p := range platforms {
		if p.Name == "" {
			t.Error("platform with empty name")
		}
		if seen[p.Name] {
			t.Errorf("duplicate platform %q", p.Name)
		}
		seen[p.Name] = true

		if got := countVerb(p.CheckTemplate); got != 1 {
			t.Errorf("%s: CheckTemplate must have exactly one %%s, got %d in %q", p.Name, got, p.CheckTemplate)
		}
		if p.DisplayTemplate != "" && countVerb(p.DisplayTemplate) != 1 {
			t.Errorf("%s: DisplayTemplate must have exactly one %%s, got %q", p.Name, p.DisplayTemplate)
		}
		if p.Mode == checkByBody && p.BodyMarker == "" {
			t.Errorf("%s: checkByBody platform must define a BodyMarker", p.Name)
		}
	}
}

func countVerb(s string) int {
	n := 0
	for i := 0; i+1 < len(s); i++ {
		if s[i] == '%' && s[i+1] == 's' {
			n++
		}
	}
	return n
}
