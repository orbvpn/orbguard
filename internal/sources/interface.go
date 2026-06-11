package sources

import (
	"context"
	"sync"
	"time"

	"orbguard-lab/internal/domain/models"
)

// Connector defines the interface for threat intelligence source connectors
type Connector interface {
	// Slug returns the unique identifier for this source
	Slug() string

	// Name returns the human-readable name of this source
	Name() string

	// Category returns the category of this source
	Category() models.SourceCategory

	// Fetch retrieves indicators from the source
	Fetch(ctx context.Context) (*models.SourceFetchResult, error)

	// IsEnabled returns whether this source is enabled
	IsEnabled() bool

	// UpdateInterval returns how often this source should be updated
	UpdateInterval() time.Duration

	// Configure configures the connector with the given config
	Configure(cfg ConnectorConfig) error
}

// ConnectorConfig holds configuration for a connector
type ConnectorConfig struct {
	Enabled        bool          `json:"enabled"`
	UpdateInterval time.Duration `json:"update_interval"`
	APIURL         string        `json:"api_url,omitempty"`
	FeedURL        string        `json:"feed_url,omitempty"`
	GithubURLs     []string      `json:"github_urls,omitempty"`
	APIKey         string        `json:"api_key,omitempty"`
	Timeout        time.Duration `json:"timeout,omitempty"`
	RateLimit      int           `json:"rate_limit,omitempty"` // Requests per minute
}

// DefaultConfig returns default connector configuration
func DefaultConfig() ConnectorConfig {
	return ConnectorConfig{
		Enabled:        true,
		UpdateInterval: 15 * time.Minute,
		Timeout:        30 * time.Second,
		RateLimit:      60,
	}
}

// BaseConnector provides common functionality for connectors
type BaseConnector struct {
	slug           string
	name           string
	category       models.SourceCategory
	sourceType     models.SourceType
	config         ConnectorConfig

	// Rate-limit backoff state (in-memory; the DB-side next_fetch is the
	// durable counterpart, persisted by the aggregator).
	backoffMu     sync.Mutex
	backoffUntil  time.Time
	backoffLogged bool
}

// NewBaseConnector creates a new base connector
func NewBaseConnector(slug, name string, category models.SourceCategory, sourceType models.SourceType) *BaseConnector {
	return &BaseConnector{
		slug:       slug,
		name:       name,
		category:   category,
		sourceType: sourceType,
		config:     DefaultConfig(),
	}
}

// Slug returns the unique identifier for this source
func (c *BaseConnector) Slug() string {
	return c.slug
}

// Name returns the human-readable name of this source
func (c *BaseConnector) Name() string {
	return c.name
}

// Category returns the category of this source
func (c *BaseConnector) Category() models.SourceCategory {
	return c.category
}

// IsEnabled returns whether this source is enabled
func (c *BaseConnector) IsEnabled() bool {
	return c.config.Enabled
}

// UpdateInterval returns how often this source should be updated
func (c *BaseConnector) UpdateInterval() time.Duration {
	return c.config.UpdateInterval
}

// Configure configures the connector
func (c *BaseConnector) Configure(cfg ConnectorConfig) error {
	c.config = cfg
	return nil
}

// Config returns the current configuration
func (c *BaseConnector) Config() ConnectorConfig {
	return c.config
}

// SetBackoff records that the provider rate-limited us and fetches should be
// skipped for the given duration. The caller is expected to surface the
// triggering 429 once itself (a non-repeat RateLimitError), so all
// subsequent skips within this window are treated as quiet repeats.
func (c *BaseConnector) SetBackoff(d time.Duration) {
	c.backoffMu.Lock()
	defer c.backoffMu.Unlock()
	c.backoffUntil = time.Now().Add(d)
	c.backoffLogged = true
}

// BackoffRemaining returns how long the current rate-limit backoff window
// still has to run (zero when not in backoff), plus whether this is the
// first time the caller observes this window (used to log exactly once per
// backoff window instead of every cycle).
func (c *BaseConnector) BackoffRemaining() (remaining time.Duration, firstObservation bool) {
	c.backoffMu.Lock()
	defer c.backoffMu.Unlock()
	remaining = time.Until(c.backoffUntil)
	if remaining <= 0 {
		return 0, false
	}
	firstObservation = !c.backoffLogged
	c.backoffLogged = true
	return remaining, firstObservation
}
