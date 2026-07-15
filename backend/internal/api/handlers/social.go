package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"

	"orbguard-lab/pkg/logger"
)

// Social media username presence enumeration (OSINT).
//
// Given a username, this concurrently HTTP-requests the public profile URL on
// a curated set of platforms and reports, per platform, whether a public
// profile exists. This is exactly what tools like Sherlock/Maigret do and is
// genuinely useful ("your handle @x exists on GitHub, Reddit, TikTok…").
//
// Honesty is the hard rule: a platform that blocks us, rate-limits us,
// redirects an unauthenticated request to a login page, or is simply
// unreachable is reported as "unknown" — NEVER guessed as "not_found". Only an
// unambiguous 404-style signal (or a platform API's own not-found verdict)
// counts as absence.
const (
	// socialPerCheckTimeout bounds a single platform HTTP check.
	socialPerCheckTimeout = 5 * time.Second
	// socialScanTimeout bounds the whole multi-platform scan.
	socialScanTimeout = 12 * time.Second
	// socialWorkerCount bounds concurrent outbound checks.
	socialWorkerCount = 6
	// socialMaxBodyBytes bounds how much response body is read for the
	// body/JSON classification modes.
	socialMaxBodyBytes = 96 * 1024
	// socialUserAgent is a real browser-like UA (many platforms 403 the Go
	// default UA) with an honest attribution suffix.
	socialUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
		"AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 " +
		"OrbGuard-UsernameScan/1.0"
)

// Presence verdicts. These are the only values the status field ever takes.
const (
	statusFound    = "found"
	statusNotFound = "not_found"
	statusUnknown  = "unknown"
)

// socialCheckMode selects how a platform's HTTP response is interpreted.
type socialCheckMode int

const (
	// checkByStatus: the profile URL returns 200 for an existing profile and
	// 404 for a missing one. Redirects are NOT followed, so a login/consent
	// redirect surfaces as a 3xx status -> unknown, never a false "found" on
	// the resulting login page.
	checkByStatus socialCheckMode = iota
	// checkByBody: the endpoint returns 200 regardless of existence, and an
	// existing profile is distinguished by a marker string in the body.
	checkByBody
	// checkKeybase: the Keybase user-lookup JSON API, whose status.code tells
	// existence precisely (0 = found, 205 = not found).
	checkKeybase
)

// socialPlatform describes one platform's presence check.
type socialPlatform struct {
	Name string
	// CheckTemplate is the URL actually requested; it contains exactly one %s
	// filled with the (validated) username.
	CheckTemplate string
	// DisplayTemplate is the human-facing profile URL returned to the client
	// (one %s). Empty means "same as CheckTemplate" — used where the checked
	// URL is an API endpoint (Reddit about.json, Keybase lookup API).
	DisplayTemplate string
	Mode            socialCheckMode
	// BodyMarker (checkByBody only) is a substring present iff the profile
	// exists.
	BodyMarker string
}

// defaultSocialPlatforms is the curated platform set. Each entry was chosen
// for a reliable, documented public existence signal (a real 404 on a missing
// handle, or a definitive API verdict). Platforms that heavily bot-block
// (Instagram, TikTok) are still included because when they do answer their
// 200/404 is meaningful, and when they block us we honestly return "unknown".
func defaultSocialPlatforms() []socialPlatform {
	return []socialPlatform{
		{Name: "GitHub", CheckTemplate: "https://github.com/%s", Mode: checkByStatus},
		{Name: "GitLab", CheckTemplate: "https://gitlab.com/%s", Mode: checkByStatus},
		{Name: "Reddit", CheckTemplate: "https://www.reddit.com/user/%s/about.json", DisplayTemplate: "https://www.reddit.com/user/%s", Mode: checkByStatus},
		{Name: "Instagram", CheckTemplate: "https://www.instagram.com/%s/", Mode: checkByStatus},
		{Name: "TikTok", CheckTemplate: "https://www.tiktok.com/@%s", Mode: checkByStatus},
		{Name: "Telegram", CheckTemplate: "https://t.me/%s", Mode: checkByBody, BodyMarker: "tgme_page_title"},
		{Name: "Mastodon", CheckTemplate: "https://mastodon.social/@%s", Mode: checkByStatus},
		{Name: "Keybase", CheckTemplate: "https://keybase.io/_/api/1.0/user/lookup.json?username=%s", DisplayTemplate: "https://keybase.io/%s", Mode: checkKeybase},
		{Name: "Dev.to", CheckTemplate: "https://dev.to/%s", Mode: checkByStatus},
		{Name: "Medium", CheckTemplate: "https://medium.com/@%s", Mode: checkByStatus},
		{Name: "npm", CheckTemplate: "https://www.npmjs.com/~%s", Mode: checkByStatus},
		{Name: "Gravatar", CheckTemplate: "https://en.gravatar.com/%s", Mode: checkByStatus},
	}
}

// socialUsernamePattern bounds usernames to a URL-safe charset. Beyond input
// hygiene this is a security control: the username is interpolated into
// outbound URLs, so restricting it to [A-Za-z0-9._-] prevents path/query
// injection and SSRF via the username field.
var socialUsernamePattern = regexp.MustCompile(`^[A-Za-z0-9._-]{1,64}$`)

// SocialHandler enumerates public username presence across platforms.
type SocialHandler struct {
	client    *http.Client
	platforms []socialPlatform
	logger    *logger.Logger
}

// NewSocialHandler creates a new social handler. It is self-contained: the
// only dependency is the logger — presence checks are stateless outbound HTTP
// requests with no database or external-service credentials.
func NewSocialHandler(log *logger.Logger) *SocialHandler {
	return &SocialHandler{
		client: &http.Client{
			Timeout: socialPerCheckTimeout,
			CheckRedirect: func(*http.Request, []*http.Request) error {
				// Do NOT follow redirects: a platform that 3xx-redirects an
				// unauthenticated profile request to a login/consent page must
				// classify as "unknown", not as a false "found" on the 200
				// login page it would land on.
				return http.ErrUseLastResponse
			},
			Transport: &http.Transport{
				Proxy:               http.ProxyFromEnvironment,
				MaxIdleConns:        32,
				MaxIdleConnsPerHost: 2,
				IdleConnTimeout:     30 * time.Second,
				TLSHandshakeTimeout: 5 * time.Second,
			},
		},
		platforms: defaultSocialPlatforms(),
		logger:    log.WithComponent("social-handler"),
	}
}

// socialResult is one platform's verdict in the response.
type socialResult struct {
	Platform string `json:"platform"`
	URL      string `json:"url"`
	Status   string `json:"status"` // found | not_found | unknown
}

// ScanUsername handles POST /api/v1/social/username-scan - concurrently checks
// whether the given username exists as a public profile on each curated
// platform. Body: { "username": "..." }. Response:
// { username, results:[{platform,url,status}], found_count, not_found_count,
//   unknown_count, platform_count, scanned_at }.
func (h *SocialHandler) ScanUsername(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Username string `json:"username"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.logger.Debug().Err(err).Msg("invalid request body")
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Normalize: trim surrounding space and a leading '@' users often type.
	username := strings.TrimPrefix(strings.TrimSpace(req.Username), "@")
	if username == "" {
		http.Error(w, "username is required", http.StatusBadRequest)
		return
	}
	if !socialUsernamePattern.MatchString(username) {
		http.Error(w, "username must be 1-64 characters of letters, digits, '.', '_' or '-'", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), socialScanTimeout)
	defer cancel()

	results := h.scan(ctx, username)

	found, notFound, unknown := 0, 0, 0
	for _, res := range results {
		switch res.Status {
		case statusFound:
			found++
		case statusNotFound:
			notFound++
		default:
			unknown++
		}
	}

	h.logger.Info().
		Int("platforms", len(results)).
		Int("found", found).
		Int("not_found", notFound).
		Int("unknown", unknown).
		Msg("username presence scan completed")

	respondJSON(w, http.StatusOK, map[string]any{
		"username":        username,
		"results":         results,
		"found_count":     found,
		"not_found_count": notFound,
		"unknown_count":   unknown,
		"platform_count":  len(results),
		"scanned_at":      time.Now().UTC().Format(time.RFC3339),
	})
}

// scan runs every platform check through a bounded worker pool and returns the
// results in stable platform order. A check that cannot start before the scan
// deadline is recorded as "unknown".
func (h *SocialHandler) scan(ctx context.Context, username string) []socialResult {
	results := make([]socialResult, len(h.platforms))
	sem := make(chan struct{}, socialWorkerCount)
	var wg sync.WaitGroup

	for i, p := range h.platforms {
		wg.Add(1)
		go func(i int, p socialPlatform) {
			defer wg.Done()

			// Acquire a worker slot, but never block past the scan deadline.
			select {
			case sem <- struct{}{}:
			case <-ctx.Done():
				results[i] = socialResult{
					Platform: p.Name,
					URL:      h.profileURL(p, username),
					Status:   statusUnknown,
				}
				return
			}
			defer func() { <-sem }()

			results[i] = h.checkPlatform(ctx, p, username)
		}(i, p)
	}

	wg.Wait()
	return results
}

// profileURL returns the human-facing profile URL for the response.
func (h *SocialHandler) profileURL(p socialPlatform, username string) string {
	tmpl := p.DisplayTemplate
	if tmpl == "" {
		tmpl = p.CheckTemplate
	}
	return fmt.Sprintf(tmpl, username)
}

// checkPlatform performs one platform's HTTP presence check. Any transport
// error, timeout or ambiguous response yields "unknown" (never "not_found").
func (h *SocialHandler) checkPlatform(ctx context.Context, p socialPlatform, username string) socialResult {
	res := socialResult{
		Platform: p.Name,
		URL:      h.profileURL(p, username),
		Status:   statusUnknown,
	}

	reqCtx, cancel := context.WithTimeout(ctx, socialPerCheckTimeout)
	defer cancel()

	target := fmt.Sprintf(p.CheckTemplate, username)
	httpReq, err := http.NewRequestWithContext(reqCtx, http.MethodGet, target, nil)
	if err != nil {
		h.logger.Debug().Err(err).Str("platform", p.Name).Msg("failed to build presence request")
		return res
	}
	httpReq.Header.Set("User-Agent", socialUserAgent)
	httpReq.Header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,application/json;q=0.9,*/*;q=0.8")
	httpReq.Header.Set("Accept-Language", "en-US,en;q=0.9")

	resp, err := h.client.Do(httpReq)
	if err != nil {
		// Timeout, DNS failure, connection reset, TLS error: the platform is
		// unreachable from here. That is "unknown", not "absent".
		h.logger.Debug().Err(err).Str("platform", p.Name).Msg("presence check request failed")
		return res
	}
	defer resp.Body.Close()

	var body []byte
	if p.Mode == checkByStatus {
		// Status is all we need; drain a little for connection reuse.
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 2048))
	} else {
		body, _ = io.ReadAll(io.LimitReader(resp.Body, socialMaxBodyBytes))
	}

	res.Status = classifyPresence(p, resp.StatusCode, body)
	return res
}

// classifyPresence maps one platform's HTTP outcome to a presence verdict.
// It is deliberately conservative: only an unambiguous "missing" signal (a
// 404-style status, a Keybase NOT_FOUND, or a 200 body lacking the profile
// marker on an always-200 endpoint) yields not_found. Blocked, rate-limited,
// redirected or errored responses are always unknown — never guessed absent.
//
// It is a pure function of (platform rule, status code, body) so it can be
// unit-tested without any network.
func classifyPresence(p socialPlatform, statusCode int, body []byte) string {
	switch p.Mode {
	case checkKeybase:
		return classifyKeybase(statusCode, body)

	case checkByBody:
		if statusCode != http.StatusOK {
			if statusCode == http.StatusNotFound || statusCode == http.StatusGone {
				return statusNotFound
			}
			return statusUnknown
		}
		if p.BodyMarker != "" && bytes.Contains(body, []byte(p.BodyMarker)) {
			return statusFound
		}
		// 200 without the profile marker: these endpoints serve a generic
		// placeholder page for unknown handles, so absence of the marker is a
		// real not-found signal (established Sherlock/Maigret heuristic).
		return statusNotFound

	default: // checkByStatus
		switch statusCode {
		case http.StatusOK:
			return statusFound
		case http.StatusNotFound, http.StatusGone:
			return statusNotFound
		default:
			// 3xx (login/consent redirect — not followed), 401/403/429
			// (bot-blocked / rate-limited), 5xx (platform error): can't tell.
			return statusUnknown
		}
	}
}

// classifyKeybase interprets the Keybase user-lookup JSON API response.
// status.code 0 = OK (exists), 205 = NOT_FOUND. Anything else, a non-200
// transport status, or an unparseable body is "unknown".
func classifyKeybase(statusCode int, body []byte) string {
	if statusCode != http.StatusOK || len(body) == 0 {
		return statusUnknown
	}
	var payload struct {
		Status struct {
			Code int `json:"code"`
		} `json:"status"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return statusUnknown
	}
	switch payload.Status.Code {
	case 0: // OK
		return statusFound
	case 205: // NOT_FOUND
		return statusNotFound
	default:
		return statusUnknown
	}
}
