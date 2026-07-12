package services

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"time"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/pkg/logger"
)

// LeakCheckClient provides access to the LeakCheck v2 breach-search API
// (https://wiki.leakcheck.io/en/api). It is an optional secondary breach
// provider aggregated alongside HIBP.
type LeakCheckClient struct {
	apiKey     string
	baseURL    string
	httpClient *http.Client
	logger     *logger.Logger
}

// LeakCheckClientConfig holds configuration for the LeakCheck client.
type LeakCheckClientConfig struct {
	APIKey  string
	Timeout time.Duration
}

// NewLeakCheckClient creates a new LeakCheck API client.
func NewLeakCheckClient(config LeakCheckClientConfig, log *logger.Logger) *LeakCheckClient {
	timeout := config.Timeout
	if timeout == 0 {
		timeout = 10 * time.Second
	}

	return &LeakCheckClient{
		apiKey:  config.APIKey,
		baseURL: "https://leakcheck.io/api/v2",
		httpClient: &http.Client{
			Timeout: timeout,
		},
		logger: log.WithComponent("leakcheck-client"),
	}
}

// Configured reports whether the client has an API key and can be used.
func (c *LeakCheckClient) Configured() bool {
	return c.apiKey != ""
}

// leakCheckResponse is the LeakCheck v2 query response envelope.
type leakCheckResponse struct {
	Success bool   `json:"success"`
	Error   string `json:"error,omitempty"`
	Found   int    `json:"found"`
	Quota   int    `json:"quota"`
	Result  []struct {
		Source struct {
			Name         string `json:"name"`
			BreachDate   string `json:"breach_date"` // "2019-03" or "2019"
			Unverified   int    `json:"unverified"`
			Passwordless int    `json:"passwordless"`
			Compromised  int    `json:"compromised"`
		} `json:"source"`
		Fields []string `json:"fields"`
	} `json:"result"`
}

// leakCheckFieldToDataClass maps LeakCheck result field names to HIBP-style
// data class names so results merge cleanly with HIBP breaches.
var leakCheckFieldToDataClass = map[string]string{
	"password":      "Passwords",
	"username":      "Usernames",
	"email":         "Email addresses",
	"phone":         "Phone numbers",
	"name":          "Names",
	"first_name":    "Names",
	"last_name":     "Names",
	"address":       "Physical addresses",
	"zip":           "Physical addresses",
	"city":          "Physical addresses",
	"country":       "Geographic locations",
	"ip":            "IP addresses",
	"dob":           "Dates of birth",
	"origin":        "Website activity",
	"document":      "Government issued IDs",
	"passport":      "Passport numbers",
	"ssn":           "Social security numbers",
	"profile_name":  "Names",
	"account_login": "Usernames",
}

// CheckEmail queries LeakCheck for breach entries containing the email and
// converts them to the shared Breach model. Returns an empty slice when the
// email is not found in any indexed leak.
func (c *LeakCheckClient) CheckEmail(ctx context.Context, email string) ([]models.Breach, error) {
	if !c.Configured() {
		return nil, fmt.Errorf("leakcheck api key not configured")
	}

	reqURL := fmt.Sprintf("%s/query/%s?type=email", c.baseURL, url.PathEscape(email))

	req, err := http.NewRequestWithContext(ctx, "GET", reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("User-Agent", "OrbGuard-Security-App")
	req.Header.Set("X-API-Key", c.apiKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	switch resp.StatusCode {
	case http.StatusOK, http.StatusNotFound:
		// 404 is "not found in any leak" — body still carries the envelope.
	case http.StatusUnauthorized, http.StatusForbidden:
		return nil, fmt.Errorf("leakcheck: invalid API key (status %d)", resp.StatusCode)
	case http.StatusTooManyRequests:
		return nil, fmt.Errorf("leakcheck: rate limited - try again later")
	default:
		return nil, fmt.Errorf("leakcheck: API returned status %d", resp.StatusCode)
	}

	var lcResp leakCheckResponse
	if err := json.NewDecoder(resp.Body).Decode(&lcResp); err != nil {
		return nil, fmt.Errorf("leakcheck: failed to decode response: %w", err)
	}

	if !lcResp.Success {
		if lcResp.Error == "Not found" {
			return []models.Breach{}, nil
		}
		return nil, fmt.Errorf("leakcheck: API error: %s", lcResp.Error)
	}

	breaches := make([]models.Breach, 0, len(lcResp.Result))
	for _, entry := range lcResp.Result {
		dataClassSet := make(map[string]bool)
		for _, field := range entry.Fields {
			if dc, ok := leakCheckFieldToDataClass[field]; ok {
				dataClassSet[dc] = true
			}
		}
		dataClasses := make([]string, 0, len(dataClassSet))
		for dc := range dataClassSet {
			dataClasses = append(dataClasses, dc)
		}
		if len(dataClasses) == 0 {
			dataClasses = []string{"Email addresses"}
		}

		name := entry.Source.Name
		if name == "" {
			name = "Unknown leak (LeakCheck)"
		}

		breaches = append(breaches, models.Breach{
			Name:        name,
			Title:       name,
			BreachDate:  parseLeakCheckDate(entry.Source.BreachDate),
			Description: fmt.Sprintf("Leak record indexed by LeakCheck (source: %s).", name),
			DataClasses: dataClasses,
			IsVerified:  entry.Source.Unverified == 0,
			Severity:    models.CalculateBreachSeverity(dataClasses),
		})
	}

	c.logger.Info().
		Str("email", maskEmail(email)).
		Int("found", lcResp.Found).
		Msg("leakcheck email query completed")

	return breaches, nil
}

// parseLeakCheckDate parses LeakCheck breach dates which come as "2006-01"
// or "2006". Returns the zero time when the date is absent or unparseable.
func parseLeakCheckDate(s string) time.Time {
	if s == "" {
		return time.Time{}
	}
	for _, layout := range []string{"2006-01-02", "2006-01", "2006"} {
		if t, err := time.Parse(layout, s); err == nil {
			return t
		}
	}
	return time.Time{}
}
