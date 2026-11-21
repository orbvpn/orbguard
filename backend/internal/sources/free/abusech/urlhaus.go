package abusech

import (
	"context"
	"errors"
	"fmt"
	"net"
	"strings"
	"time"

	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/sources"
	"orbguard-lab/pkg/logger"
)

const (
	urlhausExportBase = "https://urlhaus-api.abuse.ch"

	// recent.csv covers 30 days. The cap keeps the newest rows, which is what
	// a first ingest after a gap and every later hourly fetch both need.
	urlhausMaxBytes int64 = 64 << 20
	urlhausMaxRows        = 5000

	// The provider regenerates the file every 5 minutes and asks for no more
	// than one fetch in that time. One an hour stays far inside it.
	urlhausMinInterval = time.Hour
)

var urlhausColumns = []string{
	"id", "dateadded", "url", "url_status", "last_online",
	"threat", "tags", "urlhaus_link", "reporter",
}

// urlhausSharedHosts are platforms where one malicious file says nothing about
// the rest of the host. OrbGuard's DNS rule loader turns every URL indicator
// into a rule for its whole host, so a row on one of these would block the
// platform for every user. Subdomains match too.
var urlhausSharedHosts = map[string]bool{
	"github.com": true, "githubusercontent.com": true, "github.io": true,
	"gitlab.com": true, "gitlab.io": true, "bitbucket.org": true, "sourceforge.net": true,
	"google.com": true, "googleapis.com": true, "googleusercontent.com": true,
	"gstatic.com": true, "goo.gl": true, "youtube.com": true, "web.app": true,
	"firebaseapp.com": true, "firebasestorage.app": true, "appspot.com": true,
	"microsoft.com": true, "live.com": true, "office.com": true, "office365.com": true,
	"outlook.com": true, "sharepoint.com": true, "1drv.ms": true, "windows.net": true,
	"azureedge.net": true, "azurewebsites.net": true, "azurefd.net": true,
	"amazon.com": true, "amazonaws.com": true, "cloudfront.net": true,
	"cloudflare.com": true, "r2.dev": true, "pages.dev": true, "workers.dev": true,
	"trycloudflare.com": true, "apple.com": true, "icloud.com": true,
	"discord.com": true, "discordapp.com": true, "discordapp.net": true,
	"telegram.org": true, "t.me": true, "whatsapp.net": true, "whatsapp.com": true,
	"facebook.com": true, "fbcdn.net": true, "instagram.com": true,
	"twitter.com": true, "x.com": true, "twimg.com": true, "linkedin.com": true,
	"dropbox.com": true, "dropboxusercontent.com": true, "box.com": true,
	"mediafire.com": true, "mega.nz": true, "mega.co.nz": true, "wetransfer.com": true,
	"transfer.sh": true, "catbox.moe": true, "litter.catbox.moe": true,
	"pastebin.com": true, "paste.ee": true, "hastebin.com": true, "archive.org": true,
	"wikipedia.org": true, "wikimedia.org": true, "ngrok.io": true, "ngrok.app": true,
	"ngrok-free.app": true, "vercel.app": true, "netlify.app": true, "herokuapp.com": true,
	"onrender.com": true, "fly.dev": true, "railway.app": true, "wordpress.com": true,
	"blogspot.com": true, "blogger.com": true, "weebly.com": true, "wixsite.com": true,
	"yandex.ru": true, "yandex.net": true, "vk.com": true, "userapi.com": true,
	"baidu.com": true, "qq.com": true, "aliyuncs.com": true, "myqcloud.com": true,
}

// URLhausConnector fetches data from the Abuse.ch URLhaus file export
type URLhausConnector struct {
	*sources.BaseConnector
	feed   *exportFeed
	logger *logger.Logger
}

// NewURLhausConnector creates a new URLhaus connector
func NewURLhausConnector(log *logger.Logger) *URLhausConnector {
	componentLog := log.WithComponent("urlhaus")
	return &URLhausConnector{
		BaseConnector: sources.NewBaseConnector(
			"urlhaus",
			"URLhaus",
			models.SourceCategoryAbuseCH,
			models.SourceTypeAPI,
		),
		feed: newExportFeed(exportSpec{
			provider:    "URLhaus",
			slug:        "urlhaus",
			base:        urlhausExportBase,
			columns:     urlhausColumns,
			dateColumn:  "dateadded",
			maxBytes:    urlhausMaxBytes,
			maxRows:     urlhausMaxRows,
			minInterval: urlhausMinInterval,
			check:       checkURLhausRow,
		}, componentLog),
		logger: componentLog,
	}
}

// Configure keeps the key inside the export client, out of the general
// connector config that other code can read.
func (c *URLhausConnector) Configure(cfg sources.ConnectorConfig) error {
	c.feed.apiKey = cfg.APIKey
	cfg.APIKey = ""
	return c.BaseConnector.Configure(cfg)
}

func (c *URLhausConnector) setFetchGateStore(store FetchGateStore) {
	c.feed.setFetchGateStore(store)
}

// Fetch retrieves recent malware URLs from the URLhaus export
func (c *URLhausConnector) Fetch(ctx context.Context) (*models.SourceFetchResult, error) {
	start := time.Now()

	result := &models.SourceFetchResult{
		SourceID:      uuid.Nil, // Will be set by caller
		SourceSlug:    c.Slug(),
		FetchedAt:     start,
		RawIndicators: make([]models.RawIndicator, 0),
	}

	parsed, err := c.feed.fetch(ctx, c.UpdateInterval())
	if err != nil {
		result.Error = err
		result.Duration = time.Since(start)
		return result, err
	}

	for _, row := range parsed.rows {
		result.RawIndicators = append(result.RawIndicators, c.rowIndicators(row)...)
	}
	if len(result.RawIndicators) == 0 {
		err := errors.New("URLhaus: export produced no indicators")
		result.Error = err
		result.Duration = time.Since(start)
		return result, err
	}

	result.Success = true
	result.TotalFetched = len(result.RawIndicators)
	result.Duration = time.Since(start)

	c.logger.Info().
		Int("rows_read", parsed.read).
		Int("rows_used", len(parsed.rows)).
		Int("rows_skipped", parsed.skipped).
		Int("rows_bad", parsed.bad).
		Bool("rows_capped", parsed.capped).
		Int("indicators", len(result.RawIndicators)).
		Dur("duration", result.Duration).
		Msg("URLhaus export fetch completed")

	return result, nil
}

// checkURLhausRow keeps online http(s) URLs whose host can safely carry a
// block. Anything else is left out rather than risk blocking a healthy site.
// A URL that fails the host parser is third-party input to ignore, so it is
// skipped: a handful of crafted rows must not be able to fail the whole feed.
func checkURLhausRow(row exportRow) rowVerdict {
	raw := row.get("url")
	if raw == "" {
		return rowBad
	}
	host, ok := models.IndicatorURLHost(raw)
	if !ok {
		return rowSkip
	}
	if !strings.EqualFold(row.get("url_status"), "online") {
		return rowSkip
	}

	if ip := net.ParseIP(host); ip != nil {
		if !isPublicIP(ip) {
			return rowSkip
		}
		return rowUse
	}
	if isSharedHost(host) {
		return rowSkip
	}
	return rowUse
}

func isPublicIP(ip net.IP) bool {
	return ip.IsGlobalUnicast() && !ip.IsPrivate()
}

func isSharedHost(host string) bool {
	for {
		if urlhausSharedHosts[host] {
			return true
		}
		dot := strings.IndexByte(host, '.')
		if dot < 0 {
			return false
		}
		host = host[dot+1:]
	}
}

// rowIndicators builds the URL indicator, plus an IP indicator when the URL
// is hosted on a bare address. A domain indicator is deliberately not made:
// the row proves one URL is bad, not the whole domain.
func (c *URLhausConnector) rowIndicators(row exportRow) []models.RawIndicator {
	urlValue := row.get("url")
	threat := row.get("threat")
	urlStatus := row.get("url_status")

	severity := models.SeverityMedium
	switch strings.ToLower(threat) {
	case "malware_download":
		severity = models.SeverityHigh
	case "phishing":
		severity = models.SeverityMedium
	}

	firstSeen := row.when

	tags := []string{"urlhaus", threat}
	for _, tag := range strings.Split(row.get("tags"), ",") {
		tag = strings.TrimSpace(tag)
		if tag != "" && !strings.EqualFold(tag, "none") {
			tags = append(tags, tag)
		}
	}

	urlConfidence := 0.85
	indicators := []models.RawIndicator{{
		Value:       urlValue,
		Type:        models.IndicatorTypeURL,
		Severity:    severity,
		Confidence:  &urlConfidence,
		Description: fmt.Sprintf("URLhaus: %s - %s", threat, urlStatus),
		Tags:        withTag(tags, "url"),
		FirstSeen:   &firstSeen,
		SourceID:    c.Slug(),
		SourceName:  c.Name(),
		RawData: map[string]any{
			"urlhaus_id":   row.get("id"),
			"url_status":   urlStatus,
			"reporter":     row.get("reporter"),
			"urlhaus_link": row.get("urlhaus_link"),
		},
	}}

	host, ok := models.IndicatorURLHost(urlValue)
	if !ok {
		return indicators
	}
	if net.ParseIP(host) != nil {
		ipConfidence := 0.80
		indicators = append(indicators, models.RawIndicator{
			Value:       host,
			Type:        models.IndicatorTypeIP,
			Severity:    severity,
			Confidence:  &ipConfidence,
			Description: fmt.Sprintf("IP from URLhaus: %s", threat),
			Tags:        withTag(tags, "extracted"),
			FirstSeen:   &firstSeen,
			SourceID:    c.Slug(),
			SourceName:  c.Name(),
		})
	}
	return indicators
}
