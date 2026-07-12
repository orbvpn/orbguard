package blocklists

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/sources"
	"orbguard-lab/pkg/logger"
)

const (
	// Spamhaus DROP list (JSON) - IP ranges hijacked or leased by spammers.
	// Note: the legacy text lists are deprecated — EDROP was merged into
	// DROP in 2024 and asndrop.txt was replaced by a JSON version.
	spamhausDROPURL = "https://www.spamhaus.org/drop/drop_v4.json"
	// Spamhaus ASN DROP (JSON) - Autonomous Systems controlled by spammers
	spamhausASNDROPURL = "https://www.spamhaus.org/drop/asndrop.json"

	spamhausSlug = "spamhaus"
)

// SpamhausConnector implements the source connector for Spamhaus DROP lists
type SpamhausConnector struct {
	client   *http.Client
	logger   *logger.Logger
	enabled  bool
	interval time.Duration
	sourceID uuid.UUID
}

// NewSpamhausConnector creates a new Spamhaus connector
func NewSpamhausConnector(log *logger.Logger) *SpamhausConnector {
	return &SpamhausConnector{
		client: &http.Client{
			Timeout: 60 * time.Second,
		},
		logger:   log.WithComponent("spamhaus"),
		enabled:  true,
		interval: 24 * time.Hour, // Lists update once per day
	}
}

// Slug returns the unique identifier for this source
func (c *SpamhausConnector) Slug() string {
	return spamhausSlug
}

// Name returns the human-readable name of this source
func (c *SpamhausConnector) Name() string {
	return "Spamhaus DROP"
}

// Category returns the category of this source
func (c *SpamhausConnector) Category() models.SourceCategory {
	return models.SourceCategoryIPRep
}

// IsEnabled returns whether this source is enabled
func (c *SpamhausConnector) IsEnabled() bool {
	return c.enabled
}

// SetEnabled sets the enabled state
func (c *SpamhausConnector) SetEnabled(enabled bool) {
	c.enabled = enabled
}

// UpdateInterval returns how often this source should be updated
func (c *SpamhausConnector) UpdateInterval() time.Duration {
	return c.interval
}

// SetSourceID sets the database source ID
func (c *SpamhausConnector) SetSourceID(id uuid.UUID) {
	c.sourceID = id
}

// Configure configures the connector with the given config
func (c *SpamhausConnector) Configure(cfg sources.ConnectorConfig) error {
	c.enabled = cfg.Enabled
	if cfg.UpdateInterval > 0 {
		c.interval = cfg.UpdateInterval
	}
	return nil
}

// Fetch retrieves IP blocklists from Spamhaus
func (c *SpamhausConnector) Fetch(ctx context.Context) (*models.SourceFetchResult, error) {
	start := time.Now()
	result := &models.SourceFetchResult{
		SourceID:   c.sourceID,
		SourceSlug: spamhausSlug,
		FetchedAt:  start,
	}

	c.logger.Info().Msg("fetching from Spamhaus DROP lists")

	var allIndicators []models.RawIndicator

	// Fetch DROP list (includes the former EDROP entries, merged by
	// Spamhaus into DROP in 2024)
	dropIndicators, err := c.fetchList(ctx, spamhausDROPURL, "DROP")
	if err != nil {
		c.logger.Warn().Err(err).Msg("failed to fetch DROP list")
	} else {
		allIndicators = append(allIndicators, dropIndicators...)
	}

	// Fetch ASN DROP list
	asnIndicators, err := c.fetchASNList(ctx, spamhausASNDROPURL)
	if err != nil {
		c.logger.Warn().Err(err).Msg("failed to fetch ASN DROP list")
	} else {
		allIndicators = append(allIndicators, asnIndicators...)
	}

	if len(allIndicators) == 0 {
		result.Error = fmt.Errorf("failed to fetch any Spamhaus lists")
		result.Success = false
		result.Duration = time.Since(start)
		return result, result.Error
	}

	result.RawIndicators = allIndicators
	result.TotalFetched = len(allIndicators)
	result.Success = true
	result.Duration = time.Since(start)

	c.logger.Info().
		Int("total", len(allIndicators)).
		Dur("duration", result.Duration).
		Msg("Spamhaus fetch completed")

	return result, nil
}

// fetchList fetches a single DROP/EDROP list
func (c *SpamhausConnector) fetchList(ctx context.Context, url, listType string) ([]models.RawIndicator, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch %s: %w", listType, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("%s returned status %d: %s", listType, resp.StatusCode, string(body))
	}

	return c.parseDROPList(resp.Body, listType)
}

// spamhausDROPRecord is one newline-delimited JSON record from drop_v4.json.
// Example: {"cidr":"1.10.16.0/20","sblid":"SBL256894","rir":"apnic"}
type spamhausDROPRecord struct {
	CIDR  string `json:"cidr"`
	SBLID string `json:"sblid"`
	RIR   string `json:"rir"`
}

// parseDROPList parses the newline-delimited JSON DROP list (drop_v4.json).
// Lines that are not data records (e.g. the trailing metadata record) are
// skipped.
func (c *SpamhausConnector) parseDROPList(reader io.Reader, listType string) ([]models.RawIndicator, error) {
	var indicators []models.RawIndicator
	now := time.Now()
	conf := 0.90 // Spamhaus has very high reliability

	scanner := bufio.NewScanner(reader)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		// Skip empty lines and legacy-style comments
		if line == "" || strings.HasPrefix(line, ";") {
			continue
		}

		var rec spamhausDROPRecord
		if err := json.Unmarshal([]byte(line), &rec); err != nil {
			c.logger.Debug().Str("line", line).Msg("skipping non-JSON DROP line")
			continue
		}
		if rec.CIDR == "" {
			// Metadata record or unrelated entry
			continue
		}

		cidr := rec.CIDR

		// Validate CIDR
		_, ipNet, err := net.ParseCIDR(cidr)
		if err != nil {
			c.logger.Debug().Str("cidr", cidr).Msg("invalid CIDR, skipping")
			continue
		}

		sblID := rec.SBLID

		// Determine severity based on CIDR size
		severity := models.SeverityHigh
		ones, _ := ipNet.Mask.Size()
		if ones >= 24 {
			severity = models.SeverityMedium // Smaller ranges
		}

		description := fmt.Sprintf("Spamhaus %s blocklist - Known malicious IP range", listType)
		if sblID != "" {
			description += fmt.Sprintf(" (%s)", sblID)
		}

		indicator := models.RawIndicator{
			Value:       cidr,
			Type:        models.IndicatorTypeCIDR,
			Severity:    severity,
			Description: description,
			Tags:        []string{"spamhaus", strings.ToLower(listType), "blocklist", "hijacked"},
			FirstSeen:   &now,
			LastSeen:    &now,
			Confidence:  &conf,
			SourceID:    c.Slug(),
			SourceName:  c.Name(),
			RawData: map[string]any{
				"source":    "spamhaus",
				"list_type": listType,
				"cidr":      cidr,
				"sbl_id":    sblID,
				"rir":       rec.RIR,
			},
		}

		indicators = append(indicators, indicator)

		// Also add the network address as an IP indicator
		networkIP := ipNet.IP.String()
		ipIndicator := models.RawIndicator{
			Value:       networkIP,
			Type:        models.IndicatorTypeIPv4,
			Severity:    severity,
			Description: fmt.Sprintf("Network address from Spamhaus %s range %s", listType, cidr),
			Tags:        []string{"spamhaus", strings.ToLower(listType), "blocklist", "network-address"},
			FirstSeen:   &now,
			LastSeen:    &now,
			Confidence:  &conf,
			SourceID:    c.Slug(),
			SourceName:  c.Name(),
			RawData: map[string]any{
				"source":      "spamhaus",
				"list_type":   listType,
				"parent_cidr": cidr,
				"sbl_id":      sblID,
			},
		}
		indicators = append(indicators, ipIndicator)
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading %s list: %w", listType, err)
	}

	return indicators, nil
}

// fetchASNList fetches the ASN DROP list
func (c *SpamhausConnector) fetchASNList(ctx context.Context, url string) ([]models.RawIndicator, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch ASN DROP: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("ASN DROP returned status %d: %s", resp.StatusCode, string(body))
	}

	return c.parseASNList(resp.Body)
}

// spamhausASNRecord is one newline-delimited JSON record from asndrop.json.
// Example: {"asn":245,"rir":"arin","domain":"example.com","cc":"US","asname":"PRC-AS"}
type spamhausASNRecord struct {
	ASN    int64  `json:"asn"`
	RIR    string `json:"rir"`
	Domain string `json:"domain"`
	CC     string `json:"cc"`
	ASName string `json:"asname"`
}

// parseASNList parses the newline-delimited JSON ASN DROP list
// (asndrop.json). Lines that are not data records (e.g. the trailing
// metadata record) are skipped.
func (c *SpamhausConnector) parseASNList(reader io.Reader) ([]models.RawIndicator, error) {
	var indicators []models.RawIndicator
	now := time.Now()
	conf := 0.90

	scanner := bufio.NewScanner(reader)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		// Skip empty lines and legacy-style comments
		if line == "" || strings.HasPrefix(line, ";") {
			continue
		}

		var rec spamhausASNRecord
		if err := json.Unmarshal([]byte(line), &rec); err != nil {
			c.logger.Debug().Str("line", line).Msg("skipping non-JSON ASN DROP line")
			continue
		}
		if rec.ASN <= 0 {
			// Metadata record or unrelated entry
			continue
		}

		asn := fmt.Sprintf("AS%d", rec.ASN)
		country := rec.CC
		asnName := rec.ASName

		description := fmt.Sprintf("Spamhaus ASN DROP - Autonomous System controlled by spammers: %s", asn)
		if asnName != "" {
			description += fmt.Sprintf(" (%s)", asnName)
		}

		tags := []string{"spamhaus", "asndrop", "blocklist", "hijacked-asn"}
		if country != "" {
			tags = append(tags, "country:"+strings.ToLower(country))
		}

		indicator := models.RawIndicator{
			Value:       strings.ToUpper(asn),
			Type:        models.IndicatorTypeASN,
			Severity:    models.SeverityHigh,
			Description: description,
			Tags:        tags,
			FirstSeen:   &now,
			LastSeen:    &now,
			Confidence:  &conf,
			SourceID:    c.Slug(),
			SourceName:  c.Name(),
			RawData: map[string]any{
				"source":   "spamhaus",
				"asn":      asn,
				"rir":      rec.RIR,
				"domain":   rec.Domain,
				"country":  country,
				"asn_name": asnName,
			},
		}

		indicators = append(indicators, indicator)
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading ASN DROP list: %w", err)
	}

	return indicators, nil
}
