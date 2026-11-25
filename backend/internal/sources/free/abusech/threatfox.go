package abusech

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/sources"
	"orbguard-lab/pkg/logger"
)

const (
	threatFoxAPIURL     = "https://threatfox-api.abuse.ch/api/v1/"
	threatFoxSlug       = "threatfox"
	threatFoxMaxRecords = 1000

	// threatFoxFullWindowDays is the largest window get_iocs allows. It is
	// asked for on the first fetch after start and after a long outage.
	threatFoxFullWindowDays = 7
	// threatFoxShortWindowDays is asked for while the last success is
	// recent. ThreatFox is fetched several times an hour, so one day
	// overlaps the previous fetch many times over; the aggregator drops the
	// repeats (Deduplicator, then ON CONFLICT (value_hash) on indicators).
	threatFoxShortWindowDays = 1
	// threatFoxShortWindowMaxAge is the oldest last success that still
	// allows the short window: four hours inside its 24.
	threatFoxShortWindowMaxAge = 20 * time.Hour
)

// ThreatFoxConnector implements the source connector for ThreatFox
type ThreatFoxConnector struct {
	client   *http.Client
	logger   *logger.Logger
	enabled  bool
	interval time.Duration
	sourceID uuid.UUID
	apiKey   string
	apiURL   string
	now      func() time.Time

	// lastSuccess is when the last fetch that returned a parsed answer was
	// sent. It is kept in memory only: nothing persistent records a
	// ThreatFox success apart from update_history, which the connector
	// cannot read. After a restart the first fetch asks for the full window.
	mu          sync.Mutex
	lastSuccess time.Time
	// fullFailedAt is when the last full-window request was sent that
	// failed. Once one has failed since the last success, the connector
	// asks for the short window until something succeeds again: a 7-day
	// export that keeps failing is not asked for again and again.
	fullFailedAt time.Time
}

// NewThreatFoxConnector creates a new ThreatFox connector
func NewThreatFoxConnector(log *logger.Logger) *ThreatFoxConnector {
	return &ThreatFoxConnector{
		client: &http.Client{
			Timeout: 60 * time.Second,
		},
		logger:   log.WithComponent("threatfox"),
		enabled:  true,
		interval: 15 * time.Minute,
		apiURL:   threatFoxAPIURL,
		now:      time.Now,
	}
}

// Slug returns the unique identifier for this source
func (c *ThreatFoxConnector) Slug() string {
	return threatFoxSlug
}

// Name returns the human-readable name of this source
func (c *ThreatFoxConnector) Name() string {
	return "ThreatFox"
}

// Category returns the category of this source
func (c *ThreatFoxConnector) Category() models.SourceCategory {
	return models.SourceCategoryAbuseCH
}

// IsEnabled returns whether this source is enabled
func (c *ThreatFoxConnector) IsEnabled() bool {
	return c.enabled
}

// SetEnabled sets the enabled state
func (c *ThreatFoxConnector) SetEnabled(enabled bool) {
	c.enabled = enabled
}

// UpdateInterval returns how often this source should be updated
func (c *ThreatFoxConnector) UpdateInterval() time.Duration {
	return c.interval
}

// SetSourceID sets the database source ID
func (c *ThreatFoxConnector) SetSourceID(id uuid.UUID) {
	c.sourceID = id
}

// Configure configures the connector with the given config
func (c *ThreatFoxConnector) Configure(cfg sources.ConnectorConfig) error {
	c.enabled = cfg.Enabled
	if cfg.UpdateInterval > 0 {
		c.interval = cfg.UpdateInterval
	}
	if cfg.APIKey != "" {
		c.apiKey = cfg.APIKey
	}
	return nil
}

// Fetch retrieves indicators from ThreatFox
func (c *ThreatFoxConnector) Fetch(ctx context.Context) (*models.SourceFetchResult, error) {
	start := time.Now()
	result := &models.SourceFetchResult{
		SourceID:   c.sourceID,
		SourceSlug: threatFoxSlug,
		FetchedAt:  start,
	}

	sentAt := c.now()
	days := c.windowDays(sentAt)
	c.logger.Info().Int("days", days).Msg("fetching from ThreatFox API")

	indicators, err := c.fetchRecentIOCs(ctx, days)
	if err != nil {
		if days == threatFoxFullWindowDays {
			c.markFullWindowFailed(sentAt)
		}
		result.Error = err
		result.Success = false
		result.Duration = time.Since(start)
		return result, err
	}

	c.markSuccess(sentAt)

	result.RawIndicators = indicators
	result.TotalFetched = len(indicators)
	result.Success = true
	result.Duration = time.Since(start)

	c.logger.Info().
		Int("total", len(indicators)).
		Dur("duration", result.Duration).
		Msg("ThreatFox fetch completed")

	return result, nil
}

// windowDays chooses the get_iocs window. One day while the last success is
// under threatFoxShortWindowMaxAge old. Otherwise the full seven days (the
// first fetch of a process, or the first after an outage), but only once:
// when a full-window request has failed since the last success, one day until
// a fetch succeeds. Only a success moves the 20-hour clock.
func (c *ThreatFoxConnector) windowDays(now time.Time) int {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.lastSuccess.IsZero() && now.Sub(c.lastSuccess) < threatFoxShortWindowMaxAge {
		return threatFoxShortWindowDays
	}
	if c.fullFailedAt.After(c.lastSuccess) {
		return threatFoxShortWindowDays
	}
	return threatFoxFullWindowDays
}

// markFullWindowFailed records the send time of a full-window request that
// failed.
func (c *ThreatFoxConnector) markFullWindowFailed(sentAt time.Time) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if sentAt.After(c.fullFailedAt) {
		c.fullFailedAt = sentAt
	}
}

// markSuccess records the send time of a fetch that returned a parsed answer.
func (c *ThreatFoxConnector) markSuccess(sentAt time.Time) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if sentAt.After(c.lastSuccess) {
		c.lastSuccess = sentAt
	}
}

// fetchRecentIOCs fetches IOCs from the last N days
func (c *ThreatFoxConnector) fetchRecentIOCs(ctx context.Context, days int) ([]models.RawIndicator, error) {
	payload := map[string]interface{}{
		"query": "get_iocs",
		"days":  days,
	}

	jsonPayload, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", c.apiURL, bytes.NewBuffer(jsonPayload))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	if c.apiKey != "" {
		req.Header.Set("Auth-Key", c.apiKey)
	}

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch from ThreatFox: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("ThreatFox returned status %d: %s", resp.StatusCode, string(body))
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	var apiResp threatFoxResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	if apiResp.QueryStatus != "ok" {
		return nil, fmt.Errorf("ThreatFox query failed: %s", apiResp.QueryStatus)
	}

	return c.parseIOCs(apiResp.Data)
}

// parseIOCs converts ThreatFox IOCs to raw indicators
func (c *ThreatFoxConnector) parseIOCs(iocs []threatFoxIOC) ([]models.RawIndicator, error) {
	var indicators []models.RawIndicator

	for _, ioc := range iocs {
		indicator := models.RawIndicator{
			Value:       ioc.IOC,
			Type:        mapThreatFoxType(ioc.IOCType),
			Severity:    mapThreatFoxSeverity(ioc.ThreatType, ioc.ConfidenceLevel),
			Description: formatDescription(ioc),
			Tags:        buildTags(ioc),
			SourceID:    threatFoxSlug,
			SourceName:  "ThreatFox",
			RawData: map[string]any{
				"id":               ioc.ID,
				"threat_type":      ioc.ThreatType,
				"threat_type_desc": ioc.ThreatTypeDesc,
				"malware":          ioc.Malware,
				"malware_alias":    ioc.MalwareAlias,
				"malware_printable": ioc.MalwarePrintable,
				"confidence_level": ioc.ConfidenceLevel,
				"reference":        ioc.Reference,
				"reporter":         ioc.Reporter,
			},
		}

		// Parse timestamps
		if ioc.FirstSeen != "" {
			if t, err := time.Parse("2006-01-02 15:04:05 UTC", ioc.FirstSeen); err == nil {
				indicator.FirstSeen = &t
			}
		}
		if ioc.LastSeen != "" {
			if t, err := time.Parse("2006-01-02 15:04:05 UTC", ioc.LastSeen); err == nil {
				indicator.LastSeen = &t
			}
		}

		// Set confidence
		conf := float64(ioc.ConfidenceLevel) / 100.0
		indicator.Confidence = &conf

		indicators = append(indicators, indicator)
	}

	return indicators, nil
}

// mapThreatFoxType maps ThreatFox IOC types to our indicator types
func mapThreatFoxType(iocType string) models.IndicatorType {
	switch strings.ToLower(iocType) {
	case "domain":
		return models.IndicatorTypeDomain
	case "ip:port":
		return models.IndicatorTypeIP
	case "url":
		return models.IndicatorTypeURL
	case "md5_hash", "sha1_hash", "sha256_hash":
		return models.IndicatorTypeHash
	default:
		return models.IndicatorType(iocType)
	}
}

// mapThreatFoxSeverity maps threat type and confidence to severity
func mapThreatFoxSeverity(threatType string, confidence int) models.Severity {
	// Base on threat type
	switch strings.ToLower(threatType) {
	case "botnet_cc", "c2":
		if confidence >= 75 {
			return models.SeverityCritical
		}
		return models.SeverityHigh
	case "payload_delivery":
		if confidence >= 75 {
			return models.SeverityHigh
		}
		return models.SeverityMedium
	default:
		if confidence >= 90 {
			return models.SeverityHigh
		}
		if confidence >= 50 {
			return models.SeverityMedium
		}
		return models.SeverityLow
	}
}

// formatDescription creates a description from the IOC data
func formatDescription(ioc threatFoxIOC) string {
	parts := []string{}
	if ioc.ThreatTypeDesc != "" {
		parts = append(parts, ioc.ThreatTypeDesc)
	}
	if ioc.MalwarePrintable != "" {
		parts = append(parts, fmt.Sprintf("Malware: %s", ioc.MalwarePrintable))
	}
	if ioc.Reference != "" {
		parts = append(parts, fmt.Sprintf("Ref: %s", ioc.Reference))
	}
	return strings.Join(parts, " | ")
}

// buildTags creates tags from the IOC data
func buildTags(ioc threatFoxIOC) []string {
	tags := []string{"threatfox", "abuse.ch"}

	if ioc.ThreatType != "" {
		tags = append(tags, strings.ToLower(ioc.ThreatType))
	}
	if ioc.Malware != "" {
		tags = append(tags, strings.ToLower(ioc.Malware))
	}
	if ioc.MalwareAlias != "" {
		tags = append(tags, strings.ToLower(ioc.MalwareAlias))
	}

	// Add specific tags based on threat type
	switch strings.ToLower(ioc.ThreatType) {
	case "botnet_cc":
		tags = append(tags, "botnet", "c2")
	case "c2":
		tags = append(tags, "c2", "command-and-control")
	case "payload_delivery":
		tags = append(tags, "malware-delivery", "payload")
	}

	return tags
}

// ThreatFox API response structures
type threatFoxResponse struct {
	QueryStatus string         `json:"query_status"`
	Data        []threatFoxIOC `json:"data"`
}

type threatFoxIOC struct {
	ID               string `json:"id"`
	IOC              string `json:"ioc"`
	IOCType          string `json:"ioc_type"`
	ThreatType       string `json:"threat_type"`
	ThreatTypeDesc   string `json:"threat_type_desc"`
	Malware          string `json:"malware"`
	MalwareAlias     string `json:"malware_alias"`
	MalwarePrintable string `json:"malware_printable"`
	ConfidenceLevel  int    `json:"confidence_level"`
	FirstSeen        string `json:"first_seen"`
	LastSeen         string `json:"last_seen_utc"`
	Reference        string `json:"reference"`
	Reporter         string `json:"reporter"`
	Tags             []string `json:"tags"`
}
