package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/pkg/logger"
)

// IntelXClient provides access to the Intelligence X search API
// (https://github.com/IntelligenceX/SDK). It searches dark-web leak buckets
// for a selector (e.g. an email address) and is aggregated as an optional
// breach provider alongside HIBP and LeakCheck.
type IntelXClient struct {
	apiKey     string
	baseURL    string
	httpClient *http.Client
	logger     *logger.Logger
}

// IntelXClientConfig holds configuration for the Intelligence X client.
type IntelXClientConfig struct {
	APIKey  string
	BaseURL string
	Timeout time.Duration
}

// NewIntelXClient creates a new Intelligence X API client.
func NewIntelXClient(config IntelXClientConfig, log *logger.Logger) *IntelXClient {
	timeout := config.Timeout
	if timeout == 0 {
		timeout = 25 * time.Second
	}

	baseURL := strings.TrimRight(config.BaseURL, "/")
	if baseURL == "" {
		baseURL = "https://2.intelx.io"
	}

	return &IntelXClient{
		apiKey:  config.APIKey,
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: timeout,
		},
		logger: log.WithComponent("intelx-client"),
	}
}

// Configured reports whether the client has an API key and can be used.
func (c *IntelXClient) Configured() bool {
	return c.apiKey != ""
}

// intelxSearchRequest is the body for POST /intelligent/search.
type intelxSearchRequest struct {
	Term       string   `json:"term"`
	MaxResults int      `json:"maxresults"`
	Media      int      `json:"media"`
	Sort       int      `json:"sort"`
	Terminate  []string `json:"terminate"`
}

// intelxSearchResponse is the response of POST /intelligent/search.
type intelxSearchResponse struct {
	ID     string `json:"id"`
	Status int    `json:"status"` // 0 = success, 1 = invalid term, 2 = error max concurrent searches
}

// intelxRecord is one search result record.
type intelxRecord struct {
	SystemID string `json:"systemid"`
	Name     string `json:"name"`
	Bucket   string `json:"bucket"`
	BucketH  string `json:"bucketh"`
	Date     string `json:"date"`
	Media    int    `json:"media"`
}

// intelxResultResponse is the response of GET /intelligent/search/result.
type intelxResultResponse struct {
	Records []intelxRecord `json:"records"`
	Status  int            `json:"status"` // 0 = success more coming, 1 = success finished, 2 = search id not found, 3 = no results yet
}

// SearchLeaks searches Intelligence X leak buckets for the selector (email,
// domain, etc.) and converts matching leak documents to the shared Breach
// model. Returns an empty slice when nothing is found.
func (c *IntelXClient) SearchLeaks(ctx context.Context, term string) ([]models.Breach, error) {
	if !c.Configured() {
		return nil, fmt.Errorf("intelx api key not configured")
	}

	searchID, err := c.startSearch(ctx, term)
	if err != nil {
		return nil, err
	}
	// Best-effort terminate so the search slot is freed server-side.
	defer c.terminateSearch(searchID)

	records, err := c.collectResults(ctx, searchID)
	if err != nil {
		return nil, err
	}

	breaches := c.recordsToBreaches(records)

	c.logger.Info().
		Str("term", maskEmail(term)).
		Int("records", len(records)).
		Int("leak_documents", len(breaches)).
		Msg("intelx leak search completed")

	return breaches, nil
}

func (c *IntelXClient) startSearch(ctx context.Context, term string) (string, error) {
	body, err := json.Marshal(intelxSearchRequest{
		Term:       term,
		MaxResults: 100,
		Media:      0,
		Sort:       2, // most recent first
		Terminate:  []string{},
	})
	if err != nil {
		return "", fmt.Errorf("intelx: failed to encode request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", c.baseURL+"/intelligent/search", bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("intelx: failed to create request: %w", err)
	}
	c.setHeaders(req)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("intelx: search request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusUnauthorized {
		return "", fmt.Errorf("intelx: invalid API key")
	}
	if resp.StatusCode == http.StatusPaymentRequired {
		return "", fmt.Errorf("intelx: no credits remaining for search")
	}
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("intelx: search API returned status %d", resp.StatusCode)
	}

	var searchResp intelxSearchResponse
	if err := json.NewDecoder(resp.Body).Decode(&searchResp); err != nil {
		return "", fmt.Errorf("intelx: failed to decode search response: %w", err)
	}
	if searchResp.Status != 0 || searchResp.ID == "" {
		return "", fmt.Errorf("intelx: search rejected (status %d)", searchResp.Status)
	}

	return searchResp.ID, nil
}

// collectResults polls the result endpoint until the search finishes or the
// polling budget is exhausted.
func (c *IntelXClient) collectResults(ctx context.Context, searchID string) ([]intelxRecord, error) {
	var records []intelxRecord

	const maxPolls = 10
	for attempt := 0; attempt < maxPolls; attempt++ {
		reqURL := fmt.Sprintf("%s/intelligent/search/result?id=%s&limit=100", c.baseURL, url.QueryEscape(searchID))
		req, err := http.NewRequestWithContext(ctx, "GET", reqURL, nil)
		if err != nil {
			return nil, fmt.Errorf("intelx: failed to create result request: %w", err)
		}
		c.setHeaders(req)

		resp, err := c.httpClient.Do(req)
		if err != nil {
			return nil, fmt.Errorf("intelx: result request failed: %w", err)
		}

		var resultResp intelxResultResponse
		decodeErr := json.NewDecoder(resp.Body).Decode(&resultResp)
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("intelx: result API returned status %d", resp.StatusCode)
		}
		if decodeErr != nil {
			return nil, fmt.Errorf("intelx: failed to decode result response: %w", decodeErr)
		}

		records = append(records, resultResp.Records...)

		switch resultResp.Status {
		case 1: // success, finished
			return records, nil
		case 2: // search id not found / expired
			return records, nil
		case 0, 3: // more results coming / nothing yet — keep polling
		default:
			return nil, fmt.Errorf("intelx: unexpected result status %d", resultResp.Status)
		}

		select {
		case <-ctx.Done():
			return records, ctx.Err()
		case <-time.After(700 * time.Millisecond):
		}
	}

	// Polling budget exhausted; return what we have so far.
	return records, nil
}

// terminateSearch frees the search slot server-side (best effort).
func (c *IntelXClient) terminateSearch(searchID string) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	reqURL := fmt.Sprintf("%s/intelligent/search/terminate?id=%s", c.baseURL, url.QueryEscape(searchID))
	req, err := http.NewRequestWithContext(ctx, "GET", reqURL, nil)
	if err != nil {
		return
	}
	c.setHeaders(req)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		c.logger.Debug().Err(err).Msg("intelx: failed to terminate search (ignored)")
		return
	}
	resp.Body.Close()
}

// recordsToBreaches converts leak-bucket records to Breach entries, deduped
// by document name. Only records from leak buckets are considered — other
// buckets (whois, dumpster, etc.) do not indicate breach exposure.
func (c *IntelXClient) recordsToBreaches(records []intelxRecord) []models.Breach {
	seen := make(map[string]bool)
	breaches := []models.Breach{}

	for _, rec := range records {
		if !strings.HasPrefix(strings.ToLower(rec.Bucket), "leaks") {
			continue
		}

		name := strings.TrimSpace(rec.Name)
		if name == "" {
			name = rec.SystemID
		}
		if name == "" || seen[strings.ToLower(name)] {
			continue
		}
		seen[strings.ToLower(name)] = true

		bucketLabel := rec.BucketH
		if bucketLabel == "" {
			bucketLabel = rec.Bucket
		}

		// IntelX reports presence in a leaked document; it does not expose
		// which data classes leaked, so only the selector type is claimed.
		dataClasses := []string{"Email addresses"}

		breaches = append(breaches, models.Breach{
			Name:        name,
			Title:       name,
			BreachDate:  parseIntelXDate(rec.Date),
			Description: fmt.Sprintf("Found in dark-web leak document indexed by Intelligence X (bucket: %s).", bucketLabel),
			DataClasses: dataClasses,
			IsVerified:  false,
			Severity:    models.CalculateBreachSeverity(dataClasses),
		})
	}

	return breaches
}

// parseIntelXDate parses Intelligence X record dates ("2006-01-02 15:04:05"
// or RFC3339). Returns the zero time when absent or unparseable.
func parseIntelXDate(s string) time.Time {
	if s == "" {
		return time.Time{}
	}
	for _, layout := range []string{"2006-01-02 15:04:05", time.RFC3339, "2006-01-02"} {
		if t, err := time.Parse(layout, s); err == nil {
			return t
		}
	}
	return time.Time{}
}

func (c *IntelXClient) setHeaders(req *http.Request) {
	req.Header.Set("User-Agent", "OrbGuard-Security-App")
	req.Header.Set("x-key", c.apiKey)
}
