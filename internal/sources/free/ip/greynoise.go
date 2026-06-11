package ip

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/sources"
	"orbguard-lab/pkg/logger"
)

const (
	// GreyNoise API v3 GNQL endpoint. The v2 endpoint
	// (/v2/experimental/gnql) was deprecated and now returns HTTP 410.
	greyNoiseGNQLURL = "https://api.greynoise.io/v3/gnql"
	// GreyNoise Community lookup endpoint (free tier, single IP).
	greyNoiseCommunityURL = "https://api.greynoise.io/v3/community"
	greyNoiseSlug         = "greynoise"
	greyNoiseName         = "GreyNoise"
)

// GreyNoiseConnector fetches malicious IPs from GreyNoise
type GreyNoiseConnector struct {
	*sources.BaseConnector
	client *http.Client
	logger *logger.Logger
	apiKey string
}

// NewGreyNoiseConnector creates a new GreyNoise connector
func NewGreyNoiseConnector(log *logger.Logger) *GreyNoiseConnector {
	return &GreyNoiseConnector{
		BaseConnector: sources.NewBaseConnector(
			greyNoiseSlug,
			greyNoiseName,
			models.SourceCategoryIPRep,
			models.SourceTypeAPI,
		),
		client: &http.Client{
			// v3 GNQL responses stream slowly from the provider
			// (~90s measured for a 10k-result quick query)
			Timeout: 180 * time.Second,
		},
		logger: log.WithComponent("greynoise"),
	}
}

// Configure configures the connector with the given config
func (c *GreyNoiseConnector) Configure(cfg sources.ConnectorConfig) error {
	if err := c.BaseConnector.Configure(cfg); err != nil {
		return err
	}
	c.apiKey = cfg.APIKey
	return nil
}

// greyNoiseV3Response represents the v3 GNQL API response.
// Shape: {"data": [...], "request_metadata": {...}}
type greyNoiseV3Response struct {
	Data            []greyNoiseV3Entry `json:"data"`
	RequestMetadata struct {
		Scroll   string `json:"scroll"`
		Message  string `json:"message"`
		Query    string `json:"query"`
		Complete bool   `json:"complete"`
		Count    int    `json:"count"`
	} `json:"request_metadata"`
}

type greyNoiseV3Entry struct {
	IP                          string `json:"ip"`
	BusinessServiceIntelligence struct {
		Found      bool   `json:"found"`
		Category   string `json:"category"`
		Name       string `json:"name"`
		TrustLevel string `json:"trust_level"`
	} `json:"business_service_intelligence"`
	InternetScannerIntelligence struct {
		Found          bool             `json:"found"`
		FirstSeen      string           `json:"first_seen"`
		LastSeen       string           `json:"last_seen"`
		Classification string           `json:"classification"`
		Actor          string           `json:"actor"`
		Spoofable      bool             `json:"spoofable"`
		CVEs           []string         `json:"cves"`
		VPN            bool             `json:"vpn"`
		VPNService     string           `json:"vpn_service"`
		Tor            bool             `json:"tor"`
		Tags           []greyNoiseV3Tag `json:"tags"`
		Metadata       struct {
			ASN               string `json:"asn"`
			SourceCountry     string `json:"source_country"`
			SourceCountryCode string `json:"source_country_code"`
			SourceCity        string `json:"source_city"`
			Organization      string `json:"organization"`
			Category          string `json:"category"`
			OS                string `json:"os"`
			RDNS              string `json:"rdns"`
		} `json:"metadata"`
	} `json:"internet_scanner_intelligence"`
}

type greyNoiseV3Tag struct {
	Slug           string   `json:"slug"`
	Name           string   `json:"name"`
	Category       string   `json:"category"`
	Intention      string   `json:"intention"`
	CVEs           []string `json:"cves"`
	RecommendBlock bool     `json:"recommend_block"`
}

// CommunityLookupResult represents a single IP lookup from the Community API
type CommunityLookupResult struct {
	IP             string `json:"ip"`
	Noise          bool   `json:"noise"`
	RIOT           bool   `json:"riot"`
	Classification string `json:"classification"` // benign, malicious, unknown
	Name           string `json:"name"`
	Link           string `json:"link"`
	LastSeen       string `json:"last_seen"`
	Message        string `json:"message"`
}

// LookupIP checks a single IP using the GreyNoise Community API (free tier)
func (c *GreyNoiseConnector) LookupIP(ctx context.Context, ipAddr string) (*CommunityLookupResult, error) {
	if c.apiKey == "" {
		return nil, fmt.Errorf("GreyNoise API key not configured")
	}

	url := fmt.Sprintf("%s/%s", greyNoiseCommunityURL, ipAddr)
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("key", c.apiKey)
	req.Header.Set("Accept", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	// The Community API returns 404 with a valid JSON body when the IP has
	// not been observed scanning the internet — that is a legitimate
	// "not noise" answer, not an error.
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNotFound {
		if resp.StatusCode == http.StatusTooManyRequests {
			return nil, sources.NewRateLimitError(greyNoiseName, resp, body, time.Hour)
		}
		return nil, fmt.Errorf("GreyNoise returned status %d: %s", resp.StatusCode, string(body))
	}

	var result CommunityLookupResult
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	return &result, nil
}

// Fetch retrieves malicious IPs from GreyNoise using the v3 GNQL endpoint.
// If the configured API key's plan does not include GNQL queries, the
// provider returns 401/403 and this connector reports an honest
// PlanLimitError so the source is marked accordingly (single IP lookups via
// LookupIP remain available on the Community API).
func (c *GreyNoiseConnector) Fetch(ctx context.Context) (*models.SourceFetchResult, error) {
	start := time.Now()

	result := &models.SourceFetchResult{
		SourceID:      uuid.Nil,
		SourceSlug:    c.Slug(),
		FetchedAt:     start,
		RawIndicators: make([]models.RawIndicator, 0),
	}

	if c.apiKey == "" {
		err := fmt.Errorf("GreyNoise API key not configured")
		result.Error = err
		c.logger.Warn().Msg("GreyNoise API key not configured, skipping")
		return result, err
	}

	// Honor an active rate-limit backoff window without hammering the API
	// or spamming logs (logged once per window).
	if remaining, first := c.BackoffRemaining(); remaining > 0 {
		if first {
			c.logger.Warn().Dur("remaining", remaining).Msg("GreyNoise in rate-limit backoff, skipping fetch")
		}
		err := &sources.RateLimitError{Provider: greyNoiseName, Wait: remaining, Repeat: !first}
		result.Error = err
		result.Duration = time.Since(start)
		return result, err
	}

	// Query for malicious IPs seen in the last 7 days
	query := "classification:malicious last_seen:7d"

	req, err := http.NewRequestWithContext(ctx, "GET", greyNoiseGNQLURL, nil)
	if err != nil {
		result.Error = err
		return result, err
	}

	// Set headers
	req.Header.Set("key", c.apiKey)
	req.Header.Set("Accept", "application/json")

	// Query params. quick=true returns minimal records (ip +
	// classification) — full records are ~13KB each in v3 (structured tag
	// objects), which makes a 10k-result page >100MB and untransferable;
	// quick mode keeps it at ~1.6MB (measured live).
	q := req.URL.Query()
	q.Set("query", query)
	q.Set("size", "10000")
	q.Set("quick", "true")
	req.URL.RawQuery = q.Encode()

	c.logger.Info().Str("query", query).Msg("fetching GreyNoise malicious IPs (v3 GNQL)")

	resp, err := c.client.Do(req)
	if err != nil {
		result.Error = err
		return result, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		result.Error = err
		return result, err
	}

	if resp.StatusCode != http.StatusOK {
		switch resp.StatusCode {
		case http.StatusUnauthorized, http.StatusForbidden:
			// Honest plan-limitation reporting: the key works for Community
			// lookups but the plan does not include GNQL bulk queries.
			plErr := &sources.PlanLimitError{
				Provider: greyNoiseName,
				Message: fmt.Sprintf(
					"GNQL bulk queries not available on the current API plan (HTTP %d). Single IP lookups via the Community API remain available.",
					resp.StatusCode,
				),
			}
			c.logger.Warn().Int("status", resp.StatusCode).Msg(plErr.Message)
			result.Error = plErr
			result.Duration = time.Since(start)
			return result, plErr
		case http.StatusTooManyRequests:
			rlErr := sources.NewRateLimitError(greyNoiseName, resp, body, time.Hour)
			c.SetBackoff(rlErr.Wait)
			result.Error = rlErr
			result.Duration = time.Since(start)
			return result, rlErr
		case http.StatusGone:
			err = fmt.Errorf("GreyNoise endpoint deprecated (HTTP 410): %s — connector needs migration to the current API version", string(body))
		default:
			err = fmt.Errorf("GreyNoise returned status %d: %s", resp.StatusCode, string(body))
		}
		result.Error = err
		return result, err
	}

	var apiResp greyNoiseV3Response
	if err := json.Unmarshal(body, &apiResp); err != nil {
		result.Error = fmt.Errorf("failed to parse response: %w", err)
		return result, result.Error
	}

	c.logger.Info().
		Int("total_matches", apiResp.RequestMetadata.Count).
		Int("returned", len(apiResp.Data)).
		Msg("parsing GreyNoise entries")

	for _, entry := range apiResp.Data {
		if entry.IP == "" {
			continue
		}
		scanner := entry.InternetScannerIntelligence
		if !scanner.Found {
			continue
		}

		// Parse dates
		var firstSeen, lastSeen *time.Time
		if t, err := time.Parse("2006-01-02", scanner.FirstSeen); err == nil {
			firstSeen = &t
		}
		if t, err := time.Parse("2006-01-02", scanner.LastSeen); err == nil {
			lastSeen = &t
		}

		// Collect tag names and CVEs (v3 tags are structured objects;
		// CVEs may appear both at the entry level and per tag)
		tagNames := make([]string, 0, len(scanner.Tags))
		cveSet := make(map[string]struct{})
		for _, cve := range scanner.CVEs {
			cveSet[cve] = struct{}{}
		}
		for _, t := range scanner.Tags {
			if t.Name != "" {
				tagNames = append(tagNames, t.Name)
			}
			for _, cve := range t.CVEs {
				cveSet[cve] = struct{}{}
			}
		}
		cves := make([]string, 0, len(cveSet))
		for cve := range cveSet {
			cves = append(cves, cve)
		}

		// Build tags
		tags := []string{"greynoise", "scanner"}
		tags = append(tags, tagNames...)
		if scanner.Tor {
			tags = append(tags, "tor")
		}
		if scanner.Metadata.SourceCountryCode != "" {
			tags = append(tags, strings.ToLower(scanner.Metadata.SourceCountryCode))
		}
		if scanner.Actor != "" && scanner.Actor != "unknown" {
			tags = append(tags, strings.ToLower(strings.ReplaceAll(scanner.Actor, " ", "-")))
		}

		// Determine severity based on classification and CVEs
		severity := models.SeverityMedium
		if scanner.Classification == "malicious" {
			severity = models.SeverityHigh
			if len(cves) > 0 {
				severity = models.SeverityCritical
			}
		}

		// High confidence for GreyNoise data
		confidence := 0.85

		// Build description
		desc := fmt.Sprintf("GreyNoise: %s", scanner.Classification)
		if scanner.Actor != "" && scanner.Actor != "unknown" {
			desc += fmt.Sprintf(" (Actor: %s)", scanner.Actor)
		}
		if len(cves) > 0 {
			desc += fmt.Sprintf(" [CVEs: %s]", strings.Join(cves, ", "))
		}

		result.RawIndicators = append(result.RawIndicators, models.RawIndicator{
			Value:       entry.IP,
			Type:        models.IndicatorTypeIP,
			Severity:    severity,
			Confidence:  &confidence,
			Description: desc,
			Tags:        tags,
			FirstSeen:   firstSeen,
			LastSeen:    lastSeen,
			SourceID:    c.Slug(),
			SourceName:  c.Name(),
			RawData: map[string]any{
				"ip":             entry.IP,
				"classification": scanner.Classification,
				"actor":          scanner.Actor,
				"tags":           tagNames,
				"cve":            cves,
				"spoofable":      scanner.Spoofable,
				"vpn":            scanner.VPN,
				"vpn_service":    scanner.VPNService,
				"tor":            scanner.Tor,
				"asn":            scanner.Metadata.ASN,
				"country":        scanner.Metadata.SourceCountry,
				"organization":   scanner.Metadata.Organization,
				"os":             scanner.Metadata.OS,
				"rdns":           scanner.Metadata.RDNS,
			},
		})
	}

	result.Success = true
	result.TotalFetched = len(result.RawIndicators)
	result.Duration = time.Since(start)

	c.logger.Info().
		Int("total_matches", apiResp.RequestMetadata.Count).
		Int("indicators", len(result.RawIndicators)).
		Dur("duration", result.Duration).
		Msg("GreyNoise fetch completed")

	return result, nil
}
