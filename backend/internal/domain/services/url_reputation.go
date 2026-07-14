package services

import (
	"context"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// ErrURLListsUnavailable is returned when URL list persistence is not
// configured (database unavailable at startup).
var ErrURLListsUnavailable = errors.New("url list persistence is not available")

// ErrUserIdentityRequired is returned when a per-user list operation is
// attempted without an authenticated user identity.
var ErrUserIdentityRequired = errors.New("user identity is required for list operations")

// domainNameRe validates a plausible DNS hostname (at least two labels).
var domainNameRe = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]{0,62})?(\.[a-z0-9]([a-z0-9-]{0,62})?)+$`)

// URLReputationService provides URL safety checking and reputation scoring
type URLReputationService struct {
	repos            *repository.Repositories
	urlLists         *repository.URLListRepository
	cache            *cache.RedisCache
	safeBrowsing     SafeBrowsingClient
	phishingPatterns *PhishingPatterns
	httpClient       *http.Client
	logger           *logger.Logger

	// Built-in read-only whitelist of well-known safe domains.
	// Initialized once at construction and never mutated afterwards.
	whitelistedDomains map[string]bool
}

// SafeBrowsingClient interface for Google Safe Browsing API
type SafeBrowsingClient interface {
	CheckURLs(ctx context.Context, urls []string) ([]models.SafeBrowsingResult, error)
}

// NewURLReputationService creates a new URL reputation service
func NewURLReputationService(
	repos *repository.Repositories,
	cache *cache.RedisCache,
	safeBrowsing SafeBrowsingClient,
	log *logger.Logger,
) *URLReputationService {
	svc := &URLReputationService{
		repos:              repos,
		cache:              cache,
		safeBrowsing:       safeBrowsing,
		phishingPatterns:   NewPhishingPatterns(),
		httpClient:         &http.Client{Timeout: 8 * time.Second},
		logger:             log.WithComponent("url-reputation"),
		whitelistedDomains: make(map[string]bool),
	}

	// Initialize known safe domains
	svc.initWhitelist()

	return svc
}

// SetURLListRepository wires the Postgres-backed URL list repository.
// Called from main.go after the database pool is available.
func (s *URLReputationService) SetURLListRepository(repo *repository.URLListRepository) {
	s.urlLists = repo
}

// initWhitelist initializes the whitelist with known safe domains
func (s *URLReputationService) initWhitelist() {
	safeDomains := []string{
		"google.com", "www.google.com", "accounts.google.com",
		"apple.com", "www.apple.com", "icloud.com",
		"microsoft.com", "www.microsoft.com", "live.com", "outlook.com",
		"amazon.com", "www.amazon.com", "aws.amazon.com",
		"facebook.com", "www.facebook.com", "fb.com",
		"twitter.com", "www.twitter.com", "x.com",
		"linkedin.com", "www.linkedin.com",
		"github.com", "www.github.com",
		"paypal.com", "www.paypal.com",
		"netflix.com", "www.netflix.com",
		"youtube.com", "www.youtube.com",
		"instagram.com", "www.instagram.com",
		"wikipedia.org", "en.wikipedia.org",
	}

	for _, domain := range safeDomains {
		s.whitelistedDomains[domain] = true
	}
}

// CheckURL checks a single URL for threats
func (s *URLReputationService) CheckURL(ctx context.Context, req *models.URLCheckRequest) (*models.URLCheckResponse, error) {
	response := &models.URLCheckResponse{
		URL:           req.URL,
		IsSafe:        true,
		ShouldBlock:   false,
		Category:      models.URLCategorySafe,
		ThreatLevel:   models.SeverityInfo,
		Confidence:    1.0,
		AllowOverride: true,
		CheckedAt:     time.Now(),
	}

	// Parse URL
	parsed, err := s.parseURL(req.URL)
	if err != nil {
		s.logger.Debug().Err(err).Str("url", req.URL).Msg("failed to parse URL")
		response.IsSafe = false
		response.Category = models.URLCategorySuspicious
		response.Warnings = append(response.Warnings, "Invalid URL format")
		return response, nil
	}

	response.Domain = parsed.Host

	// Check cache first
	cacheKey := s.getCacheKey(req.URL)
	var cachedResult models.URLCheckResponse
	if err := s.cache.GetJSON(ctx, cacheKey, &cachedResult); err == nil {
		cachedResult.CacheHit = true
		return &cachedResult, nil
	}

	// Check whitelist
	if s.isWhitelisted(parsed.Host) {
		response.IsSafe = true
		response.Category = models.URLCategorySafe
		s.cacheResult(ctx, cacheKey, response)
		return response, nil
	}

	// Run all checks
	s.runChecks(ctx, parsed, response)

	// Cache the result
	s.cacheResult(ctx, cacheKey, response)

	// Log the check
	s.logger.Info().
		Str("url", req.URL).
		Bool("safe", response.IsSafe).
		Str("category", string(response.Category)).
		Float64("confidence", response.Confidence).
		Msg("URL checked")

	return response, nil
}

// CheckURLForUser checks a URL applying the user's personal
// whitelist/blacklist before falling back to the global checks.
// userID may be empty (e.g. service-to-service requests), in which case
// this behaves exactly like CheckURL.
func (s *URLReputationService) CheckURLForUser(ctx context.Context, userID string, req *models.URLCheckRequest) (*models.URLCheckResponse, error) {
	if userID != "" && s.urlLists != nil {
		if parsed, err := s.parseURL(req.URL); err == nil {
			host := strings.ToLower(parsed.Host)

			blocked, err := s.matchUserList(ctx, userID, models.URLListTypeBlacklist, host, parsed.String())
			if err != nil {
				s.logger.Warn().Err(err).Str("user_id", userID).Msg("failed to check user blacklist")
			} else if blocked {
				return &models.URLCheckResponse{
					URL:           req.URL,
					Domain:        parsed.Host,
					IsSafe:        false,
					ShouldBlock:   true,
					Category:      models.URLCategorySuspicious,
					ThreatLevel:   models.SeverityHigh,
					Confidence:    1.0,
					Description:   "Blocked by your personal blocklist",
					BlockReason:   "Domain is on your personal blocklist",
					AllowOverride: true,
					CheckedAt:     time.Now(),
				}, nil
			}

			allowed, err := s.matchUserList(ctx, userID, models.URLListTypeWhitelist, host, parsed.String())
			if err != nil {
				s.logger.Warn().Err(err).Str("user_id", userID).Msg("failed to check user whitelist")
			} else if allowed {
				return &models.URLCheckResponse{
					URL:           req.URL,
					Domain:        parsed.Host,
					IsSafe:        true,
					ShouldBlock:   false,
					Category:      models.URLCategorySafe,
					ThreatLevel:   models.SeverityInfo,
					Confidence:    1.0,
					Description:   "Allowed by your personal whitelist",
					AllowOverride: true,
					CheckedAt:     time.Now(),
				}, nil
			}
		}
	}

	return s.CheckURL(ctx, req)
}

// CheckURLBatch checks multiple URLs
func (s *URLReputationService) CheckURLBatch(ctx context.Context, req *models.URLBatchCheckRequest) (*models.URLBatchCheckResponse, error) {
	response := &models.URLBatchCheckResponse{
		Results:    make([]models.URLCheckResponse, 0, len(req.URLs)),
		TotalCount: len(req.URLs),
		CheckedAt:  time.Now(),
	}

	for _, urlStr := range req.URLs {
		checkReq := &models.URLCheckRequest{
			URL:      urlStr,
			DeviceID: req.DeviceID,
			Source:   req.Source,
		}
		result, err := s.CheckURL(ctx, checkReq)
		if err != nil {
			s.logger.Warn().Err(err).Str("url", urlStr).Msg("failed to check URL")
			continue
		}
		response.Results = append(response.Results, *result)
		if result.IsSafe {
			response.SafeCount++
		}
		if result.ShouldBlock {
			response.BlockCount++
		}
	}

	return response, nil
}

// runChecks runs all URL safety checks
func (s *URLReputationService) runChecks(ctx context.Context, parsed *url.URL, response *models.URLCheckResponse) {
	// 1. Check threat intelligence database
	s.checkThreatIntelligence(ctx, parsed, response)
	if response.ShouldBlock {
		return
	}

	// 2. Check phishing patterns
	s.checkPhishingPatterns(parsed, response)
	if response.ShouldBlock {
		return
	}

	// 3. Check URL characteristics
	s.checkURLCharacteristics(parsed, response)

	// 4. Check Google Safe Browsing (if available)
	if s.safeBrowsing != nil {
		s.checkSafeBrowsing(ctx, parsed.String(), response)
	}

	// Calculate final verdict
	s.calculateVerdict(response)
}

// checkThreatIntelligence checks against our threat intelligence database
func (s *URLReputationService) checkThreatIntelligence(ctx context.Context, parsed *url.URL, response *models.URLCheckResponse) {
	if s.repos == nil {
		return
	}

	// Check domain
	indicator, err := s.repos.Indicators.GetByValue(ctx, parsed.Host, models.IndicatorTypeDomain)
	if err == nil && indicator != nil {
		response.IsSafe = false
		response.ShouldBlock = true
		response.Category = s.indicatorCategoryToURLCategory(indicator.Tags)
		response.ThreatLevel = indicator.Severity
		response.Confidence = indicator.Confidence
		response.Description = indicator.Description
		response.BlockReason = fmt.Sprintf("Domain is associated with %s", response.Category)

		if indicator.CampaignID != nil {
			// Get campaign name
			campaign, err := s.repos.Campaigns.GetByID(ctx, *indicator.CampaignID)
			if err == nil {
				response.CampaignName = campaign.Name
			}
		}
		return
	}

	// Check full URL
	indicator, err = s.repos.Indicators.GetByValue(ctx, parsed.String(), models.IndicatorTypeURL)
	if err == nil && indicator != nil {
		response.IsSafe = false
		response.ShouldBlock = true
		response.Category = models.URLCategoryMalware
		response.ThreatLevel = indicator.Severity
		response.Confidence = indicator.Confidence
		response.Description = indicator.Description
		response.BlockReason = "URL is known to be malicious"
		return
	}
}

// checkPhishingPatterns checks against known phishing patterns
func (s *URLReputationService) checkPhishingPatterns(parsed *url.URL, response *models.URLCheckResponse) {
	// Check domain patterns
	if s.phishingPatterns.IsPhishingDomain(parsed.Host) {
		response.IsSafe = false
		response.ShouldBlock = true
		response.Category = models.URLCategoryPhishing
		response.ThreatLevel = models.SeverityHigh
		response.Confidence = 0.85
		response.BlockReason = "Domain matches known phishing patterns"
		response.Warnings = append(response.Warnings, "This domain appears to be impersonating a legitimate website")
		return
	}

	// Check for typosquatting
	if s.isTyposquatting(parsed.Host) {
		response.IsSafe = false
		response.ShouldBlock = true
		response.Category = models.URLCategoryPhishing
		response.ThreatLevel = models.SeverityHigh
		response.Confidence = 0.8
		response.BlockReason = "Domain appears to be typosquatting a legitimate brand"
		return
	}
}

// checkURLCharacteristics checks suspicious URL characteristics
func (s *URLReputationService) checkURLCharacteristics(parsed *url.URL, response *models.URLCheckResponse) {
	riskScore := 0.0
	warnings := []string{}

	// Check for IP address instead of domain
	if net.ParseIP(parsed.Host) != nil {
		riskScore += 0.3
		warnings = append(warnings, "URL uses IP address instead of domain name")
	}

	// Check for suspicious TLD
	if hasSuspiciousTLD(parsed.Host) {
		riskScore += 0.25
		warnings = append(warnings, "Domain uses a high-risk TLD")
	}

	// Check for excessive subdomains
	parts := strings.Split(parsed.Host, ".")
	if len(parts) > 4 {
		riskScore += 0.2
		warnings = append(warnings, "URL has an unusually complex domain structure")
	}

	// Check for long domain
	if len(parsed.Host) > 50 {
		riskScore += 0.15
		warnings = append(warnings, "Domain name is unusually long")
	}

	// Check for suspicious keywords in URL
	suspiciousKeywords := []string{"login", "signin", "verify", "secure", "account", "update", "confirm", "banking", "password", "credential"}
	pathLower := strings.ToLower(parsed.Path + parsed.RawQuery)
	for _, keyword := range suspiciousKeywords {
		if strings.Contains(pathLower, keyword) {
			riskScore += 0.1
			break
		}
	}

	// Check for encoded characters
	if strings.Contains(parsed.Host, "%") || strings.Contains(parsed.Host, "@") {
		riskScore += 0.3
		warnings = append(warnings, "URL contains suspicious encoded characters")
	}

	// Check for homograph attack (mixed scripts)
	if containsMixedScripts(parsed.Host) {
		riskScore += 0.4
		warnings = append(warnings, "Domain may be using lookalike characters (homograph attack)")
	}

	// Check for URL shortener
	if s.isURLShortener(parsed.Host) {
		riskScore += 0.15
		warnings = append(warnings, "URL uses a shortening service - actual destination unknown")
	}

	// Update response
	response.Warnings = append(response.Warnings, warnings...)

	if riskScore > 0 {
		if response.Confidence == 1.0 {
			response.Confidence = 1.0 - riskScore
		}
	}

	if riskScore >= 0.6 {
		response.IsSafe = false
		response.Category = models.URLCategorySuspicious
		response.ThreatLevel = models.SeverityMedium
		if riskScore >= 0.8 {
			response.ShouldBlock = true
			response.BlockReason = "URL has multiple suspicious characteristics"
		}
	}
}

// checkSafeBrowsing checks Google Safe Browsing API
func (s *URLReputationService) checkSafeBrowsing(ctx context.Context, urlStr string, response *models.URLCheckResponse) {
	if s.safeBrowsing == nil {
		return
	}

	results, err := s.safeBrowsing.CheckURLs(ctx, []string{urlStr})
	if err != nil {
		s.logger.Warn().Err(err).Msg("Safe Browsing API check failed")
		return
	}

	if len(results) > 0 && results[0].IsThreat {
		result := results[0]
		response.IsSafe = false
		response.ShouldBlock = true
		response.Confidence = 0.95 // High confidence from Google

		// Map threat types
		for _, threatType := range result.ThreatTypes {
			switch threatType {
			case "MALWARE":
				response.Category = models.URLCategoryMalware
				response.ThreatLevel = models.SeverityCritical
			case "SOCIAL_ENGINEERING":
				response.Category = models.URLCategoryPhishing
				response.ThreatLevel = models.SeverityHigh
			case "UNWANTED_SOFTWARE":
				response.Category = models.URLCategorySuspicious
				response.ThreatLevel = models.SeverityMedium
			case "POTENTIALLY_HARMFUL_APPLICATION":
				response.Category = models.URLCategoryMalware
				response.ThreatLevel = models.SeverityHigh
			}
		}

		response.BlockReason = fmt.Sprintf("Google Safe Browsing: %s", strings.Join(result.ThreatTypes, ", "))
		response.AllowOverride = false // Don't allow overriding Google's verdict
	}
}

// calculateVerdict calculates the final safety verdict
func (s *URLReputationService) calculateVerdict(response *models.URLCheckResponse) {
	// If already marked as unsafe/blocked, keep it
	if !response.IsSafe || response.ShouldBlock {
		return
	}

	// If we have warnings but didn't block, mark as potentially unsafe
	if len(response.Warnings) > 2 {
		response.Category = models.URLCategorySuspicious
		response.ThreatLevel = models.SeverityLow
	}

	// Set description if not set
	if response.Description == "" {
		if response.IsSafe {
			response.Description = "No threats detected"
		} else if response.ShouldBlock {
			response.Description = response.BlockReason
		} else {
			response.Description = "Proceed with caution"
		}
	}
}

// Helper functions

func (s *URLReputationService) parseURL(rawURL string) (*url.URL, error) {
	// Add protocol if missing
	if !strings.HasPrefix(rawURL, "http://") && !strings.HasPrefix(rawURL, "https://") {
		rawURL = "https://" + rawURL
	}
	return url.Parse(rawURL)
}

func (s *URLReputationService) getCacheKey(urlStr string) string {
	hash := sha256.Sum256([]byte(urlStr))
	return "url:reputation:" + hex.EncodeToString(hash[:8])
}

func (s *URLReputationService) cacheResult(ctx context.Context, key string, response *models.URLCheckResponse) {
	// Cache for 5 minutes for safe URLs, 1 hour for blocked URLs
	ttl := 5 * time.Minute
	if response.ShouldBlock {
		ttl = 1 * time.Hour
	}
	_ = s.cache.SetJSON(ctx, key, response, ttl)
}

func (s *URLReputationService) isWhitelisted(domain string) bool {
	domain = strings.ToLower(domain)
	if s.whitelistedDomains[domain] {
		return true
	}
	// Check parent domains
	parts := strings.Split(domain, ".")
	for i := 1; i < len(parts); i++ {
		parent := strings.Join(parts[i:], ".")
		if s.whitelistedDomains[parent] {
			return true
		}
	}
	return false
}

func (s *URLReputationService) isURLShortener(domain string) bool {
	shorteners := map[string]bool{
		"bit.ly": true, "tinyurl.com": true, "t.co": true, "goo.gl": true,
		"ow.ly": true, "is.gd": true, "buff.ly": true, "adf.ly": true,
		"j.mp": true, "rb.gy": true, "cutt.ly": true, "short.io": true,
		"rebrand.ly": true, "bl.ink": true, "soo.gd": true, "s.id": true,
		"clk.sh": true, "shorturl.at": true, "tiny.cc": true,
	}
	return shorteners[strings.ToLower(domain)]
}

// hasSuspiciousTLD reports whether the host ends in a high-risk TLD.
func hasSuspiciousTLD(host string) bool {
	suspiciousTLDs := []string{".xyz", ".top", ".club", ".work", ".click", ".link", ".gq", ".ml", ".cf", ".tk", ".ga", ".buzz", ".icu"}
	host = strings.ToLower(host)
	for _, tld := range suspiciousTLDs {
		if strings.HasSuffix(host, tld) {
			return true
		}
	}
	return false
}

func (s *URLReputationService) isTyposquatting(domain string) bool {
	// Check common brand typosquatting patterns
	brands := map[string]*regexp.Regexp{
		"paypal":     regexp.MustCompile(`(?i)(paypa1|pay-pal|paypai|payp4l|paypall|paipal)`),
		"amazon":     regexp.MustCompile(`(?i)(amaz0n|amazn|arnazon|amzon)`),
		"apple":      regexp.MustCompile(`(?i)(app1e|appie|appl3)`),
		"google":     regexp.MustCompile(`(?i)(g00gle|googel|gooogle|gogle)`),
		"microsoft":  regexp.MustCompile(`(?i)(micr0soft|mircosoft|microsft|microsooft)`),
		"facebook":   regexp.MustCompile(`(?i)(faceb00k|facebok|facbook|facebock)`),
		"netflix":    regexp.MustCompile(`(?i)(netf1ix|netfilx|netfix)`),
		"chase":      regexp.MustCompile(`(?i)(chas3|chace|chasse)`),
		"wellsfargo": regexp.MustCompile(`(?i)(wel1sfargo|wellsfarg0|welsfargo)`),
	}

	for _, pattern := range brands {
		if pattern.MatchString(domain) {
			return true
		}
	}

	return false
}

func (s *URLReputationService) indicatorCategoryToURLCategory(tags []string) models.URLCategory {
	for _, tag := range tags {
		switch strings.ToLower(tag) {
		case "phishing":
			return models.URLCategoryPhishing
		case "malware":
			return models.URLCategoryMalware
		case "scam":
			return models.URLCategoryScam
		case "spam":
			return models.URLCategorySpam
		case "c2", "c&c", "command_and_control":
			return models.URLCategoryC2
		case "botnet":
			return models.URLCategoryBotnet
		case "ransomware":
			return models.URLCategoryRansomware
		case "exploit":
			return models.URLCategoryExploit
		}
	}
	return models.URLCategorySuspicious
}

// --- Per-user whitelist/blacklist management (Postgres-backed) ---

// listEntryPattern extracts the pattern string from a list entry,
// preferring Domain, then URL, then Pattern.
func listEntryPattern(entry *models.URLListEntry) string {
	switch {
	case entry.Domain != "":
		return strings.ToLower(strings.TrimSpace(entry.Domain))
	case entry.URL != "":
		return strings.TrimSpace(entry.URL)
	case entry.Pattern != "":
		return strings.TrimSpace(entry.Pattern)
	default:
		return ""
	}
}

func (s *URLReputationService) userListCacheKey(userID string, listType models.URLListType) string {
	return fmt.Sprintf("url:userlist:%s:%s", userID, listType)
}

// AddToList adds an entry to the authenticated user's whitelist or blacklist.
func (s *URLReputationService) AddToList(ctx context.Context, userID string, entry *models.URLListEntry) error {
	if s.urlLists == nil {
		return ErrURLListsUnavailable
	}
	if userID == "" {
		return ErrUserIdentityRequired
	}
	if entry.ListType != models.URLListTypeWhitelist && entry.ListType != models.URLListTypeBlacklist {
		return fmt.Errorf("invalid list type: %s", entry.ListType)
	}

	pattern := listEntryPattern(entry)
	if pattern == "" {
		return fmt.Errorf("url, domain, or pattern is required")
	}

	stored, err := s.urlLists.Add(ctx, userID, entry.ListType, pattern, entry.Reason, entry.CreatedBy)
	if err != nil {
		return fmt.Errorf("failed to persist list entry: %w", err)
	}

	// Reflect persisted values back to the caller's entry
	entry.ID = stored.ID
	entry.CreatedAt = stored.CreatedAt
	entry.IsActive = true

	// Invalidate caches: the user's list cache and any cached check
	// result for this pattern.
	_ = s.cache.Delete(ctx, s.userListCacheKey(userID, entry.ListType))
	_ = s.cache.Delete(ctx, s.getCacheKey(pattern))

	s.logger.Info().
		Str("user_id", userID).
		Str("list_type", string(entry.ListType)).
		Str("pattern", pattern).
		Msg("added URL list entry")

	return nil
}

// AddToWhitelist adds an entry to the user's whitelist
func (s *URLReputationService) AddToWhitelist(ctx context.Context, userID string, entry *models.URLListEntry) error {
	entry.ListType = models.URLListTypeWhitelist
	return s.AddToList(ctx, userID, entry)
}

// AddToBlacklist adds an entry to the user's blacklist
func (s *URLReputationService) AddToBlacklist(ctx context.Context, userID string, entry *models.URLListEntry) error {
	entry.ListType = models.URLListTypeBlacklist
	return s.AddToList(ctx, userID, entry)
}

// GetList returns the authenticated user's entries for the given list type.
func (s *URLReputationService) GetList(ctx context.Context, userID string, listType models.URLListType) ([]models.URLListEntry, error) {
	if s.urlLists == nil {
		return nil, ErrURLListsUnavailable
	}
	if userID == "" {
		return nil, ErrUserIdentityRequired
	}

	return s.urlLists.List(ctx, userID, listType)
}

// RemoveFromList removes one of the user's list entries by ID.
// Returns repository.ErrURLListEntryNotFound when the entry does not
// exist or belongs to another user.
func (s *URLReputationService) RemoveFromList(ctx context.Context, userID string, id uuid.UUID) error {
	if s.urlLists == nil {
		return ErrURLListsUnavailable
	}
	if userID == "" {
		return ErrUserIdentityRequired
	}

	// Fetch entry first so we can invalidate the correct caches.
	entry, err := s.urlLists.GetByID(ctx, userID, id)
	if err != nil {
		return err
	}

	if err := s.urlLists.Remove(ctx, userID, id); err != nil {
		return err
	}

	_ = s.cache.Delete(ctx, s.userListCacheKey(userID, entry.ListType))
	if pattern := listEntryPattern(entry); pattern != "" {
		_ = s.cache.Delete(ctx, s.getCacheKey(pattern))
	}

	s.logger.Info().
		Str("user_id", userID).
		Str("id", id.String()).
		Str("list_type", string(entry.ListType)).
		Msg("removed URL list entry")

	return nil
}

// matchUserList reports whether host/fullURL matches any of the user's
// active patterns of the given list type. Patterns are cached briefly
// in Redis to avoid a database round-trip on every URL check.
func (s *URLReputationService) matchUserList(ctx context.Context, userID string, listType models.URLListType, host, fullURL string) (bool, error) {
	patterns, err := s.userPatterns(ctx, userID, listType)
	if err != nil {
		return false, err
	}

	for _, p := range patterns {
		if matchesPattern(p, host, fullURL) {
			return true, nil
		}
	}
	return false, nil
}

// userPatterns returns the user's active patterns, with a short Redis cache.
func (s *URLReputationService) userPatterns(ctx context.Context, userID string, listType models.URLListType) ([]string, error) {
	cacheKey := s.userListCacheKey(userID, listType)

	var patterns []string
	if err := s.cache.GetJSON(ctx, cacheKey, &patterns); err == nil {
		return patterns, nil
	}

	patterns, err := s.urlLists.ActivePatterns(ctx, userID, listType)
	if err != nil {
		return nil, err
	}

	_ = s.cache.SetJSON(ctx, cacheKey, patterns, 60*time.Second)
	return patterns, nil
}

// matchesPattern matches a stored list pattern against a host and full URL.
// Supported forms:
//   - exact domain ("example.com") — matches host and its subdomains
//   - wildcard domain ("*.example.com") — matches subdomains and apex
//   - URL prefix ("https://example.com/path") — prefix match on full URL
func matchesPattern(pattern, host, fullURL string) bool {
	pattern = strings.TrimSpace(pattern)
	if pattern == "" {
		return false
	}

	lowered := strings.ToLower(pattern)

	switch {
	case strings.Contains(pattern, "://") || strings.Contains(pattern, "/"):
		return strings.HasPrefix(strings.ToLower(fullURL), lowered)
	case strings.HasPrefix(lowered, "*."):
		base := lowered[2:]
		return host == base || strings.HasSuffix(host, "."+base)
	default:
		return host == lowered || strings.HasSuffix(host, "."+lowered)
	}
}

// --- URL reports ---

// ReportURL persists a user-submitted URL report (false positive,
// missed threat, or feedback).
func (s *URLReputationService) ReportURL(ctx context.Context, userID, deviceID, reportURL, reportType, comment string) (*repository.URLReport, error) {
	if s.urlLists == nil {
		return nil, ErrURLListsUnavailable
	}

	report := &repository.URLReport{
		UserID:     userID,
		DeviceID:   deviceID,
		URL:        reportURL,
		ReportType: reportType,
		Comment:    comment,
	}

	if err := s.urlLists.CreateReport(ctx, report); err != nil {
		return nil, fmt.Errorf("failed to persist URL report: %w", err)
	}

	s.logger.Info().
		Str("url", reportURL).
		Str("report_type", reportType).
		Str("user_id", userID).
		Str("device_id", deviceID).
		Str("report_id", report.ID.String()).
		Msg("URL report persisted")

	return report, nil
}

// BatchCheckURLs checks multiple URLs (alias for CheckURLBatch)
func (s *URLReputationService) BatchCheckURLs(ctx context.Context, req *models.URLBatchCheckRequest) (*models.URLBatchCheckResponse, error) {
	return s.CheckURLBatch(ctx, req)
}

// --- Domain reputation with live enrichment (DNS / TLS / RDAP) ---

const domainReputationCacheTTL = 12 * time.Hour

// domainEnrichment holds raw results gathered from network sources.
type domainEnrichment struct {
	ips     []net.IP
	mxCount int
	nsCount int

	certPresent   bool
	certValid     bool
	certIssuer    string
	certNotBefore time.Time
	certNotAfter  time.Time

	registeredAt *time.Time
	registrar    string

	sources []string
}

// GetDomainReputation returns the reputation data for a domain.
// It combines the threat-intelligence database with live enrichment:
// DNS resolution, TLS certificate inspection, and RDAP registration
// data, plus heuristic scoring. Results are cached in Redis.
// Returns (nil, nil) when the domain does not exist (NXDOMAIN) or is
// not a valid domain name.
func (s *URLReputationService) GetDomainReputation(ctx context.Context, domain string) (*models.URLReputation, error) {
	domain = strings.ToLower(strings.TrimSpace(strings.TrimSuffix(domain, ".")))
	if !domainNameRe.MatchString(domain) || net.ParseIP(domain) != nil {
		s.logger.Debug().Str("domain", domain).Msg("invalid domain name for reputation lookup")
		return nil, nil
	}

	// 1. Threat intelligence database takes precedence
	if s.repos != nil {
		indicator, err := s.repos.Indicators.GetByValue(ctx, domain, models.IndicatorTypeDomain)
		if err == nil && indicator != nil {
			return &models.URLReputation{
				ID:          indicator.ID,
				URL:         domain,
				Domain:      domain,
				Category:    s.indicatorCategoryToURLCategory(indicator.Tags),
				ThreatLevel: indicator.Severity,
				Confidence:  indicator.Confidence,
				IsMalicious: true,
				IsBlocked:   true,
				Sources:     []string{"threat-intel-db"},
				FirstSeen:   indicator.FirstSeen,
				LastSeen:    indicator.LastSeen,
				LastChecked: time.Now(),
				Tags:        indicator.Tags,
				Description: indicator.Description,
				CampaignID:  indicator.CampaignID,
				RiskScore:   1.0,
			}, nil
		}
	}

	// 2. Built-in whitelist of well-known safe domains
	if s.isWhitelisted(domain) {
		return &models.URLReputation{
			ID:          uuid.New(),
			URL:         domain,
			Domain:      domain,
			Category:    models.URLCategorySafe,
			ThreatLevel: models.SeverityInfo,
			Confidence:  1.0,
			IsMalicious: false,
			IsBlocked:   false,
			Sources:     []string{"builtin-whitelist"},
			LastChecked: time.Now(),
		}, nil
	}

	// 3. Cached enrichment result
	cacheKey := "url:domainrep:" + domain
	var cached models.URLReputation
	if err := s.cache.GetJSON(ctx, cacheKey, &cached); err == nil && cached.Domain != "" {
		return &cached, nil
	}

	// 4. Live enrichment: DNS existence check first
	enrich := &domainEnrichment{}
	exists, err := s.enrichDNS(ctx, domain, enrich)
	if err != nil {
		s.logger.Warn().Err(err).Str("domain", domain).Msg("DNS enrichment failed")
	}
	if !exists {
		// NXDOMAIN: the domain genuinely does not exist
		s.logger.Debug().Str("domain", domain).Msg("domain does not resolve (NXDOMAIN)")
		return nil, nil
	}

	// TLS and RDAP can run concurrently; each fails gracefully.
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		s.enrichTLS(ctx, domain, enrich)
	}()
	go func() {
		defer wg.Done()
		s.enrichRDAP(ctx, domain, enrich)
	}()
	wg.Wait()

	rep := s.buildReputation(domain, enrich)

	_ = s.cache.SetJSON(ctx, cacheKey, rep, domainReputationCacheTTL)

	s.logger.Info().
		Str("domain", domain).
		Float64("risk_score", rep.RiskScore).
		Str("category", string(rep.Category)).
		Strs("sources", rep.Sources).
		Msg("domain reputation computed")

	return rep, nil
}

// enrichDNS resolves A/AAAA, MX, and NS records. Returns exists=false
// only on a definitive NXDOMAIN answer.
func (s *URLReputationService) enrichDNS(ctx context.Context, domain string, enrich *domainEnrichment) (bool, error) {
	resolver := net.DefaultResolver

	dnsCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	ips, err := resolver.LookupIP(dnsCtx, "ip", domain)
	if err != nil {
		var dnsErr *net.DNSError
		if errors.As(err, &dnsErr) && dnsErr.IsNotFound {
			// Definitive: no A/AAAA records. The domain may still exist
			// (e.g. MX-only), so check NS before declaring NXDOMAIN.
			nsCtx, nsCancel := context.WithTimeout(ctx, 3*time.Second)
			defer nsCancel()
			ns, nsErr := resolver.LookupNS(nsCtx, domain)
			if nsErr != nil || len(ns) == 0 {
				return false, nil
			}
			enrich.nsCount = len(ns)
			enrich.sources = append(enrich.sources, "dns")
			return true, nil
		}
		// Transient failure (timeout, SERVFAIL): treat as existing but
		// unresolved so we do not 404 a real domain on resolver trouble.
		return true, err
	}

	enrich.ips = ips
	enrich.sources = append(enrich.sources, "dns")

	// MX and NS lookups are best-effort signals
	mxCtx, mxCancel := context.WithTimeout(ctx, 3*time.Second)
	defer mxCancel()
	if mx, err := resolver.LookupMX(mxCtx, domain); err == nil {
		enrich.mxCount = len(mx)
	}

	nsCtx, nsCancel := context.WithTimeout(ctx, 3*time.Second)
	defer nsCancel()
	if ns, err := resolver.LookupNS(nsCtx, domain); err == nil {
		enrich.nsCount = len(ns)
	}

	return true, nil
}

// enrichTLS fetches and inspects the TLS certificate on port 443.
// A verification failure downgrades to an unverified fetch so we can
// still report issuer and validity window with certValid=false.
func (s *URLReputationService) enrichTLS(ctx context.Context, domain string, enrich *domainEnrichment) {
	dialer := &net.Dialer{Timeout: 5 * time.Second}

	conn, err := tls.DialWithDialer(dialer, "tcp", net.JoinHostPort(domain, "443"), &tls.Config{
		ServerName: domain,
	})
	if err == nil {
		defer conn.Close()
		s.recordCert(conn.ConnectionState().PeerCertificates, enrich, true)
		enrich.sources = append(enrich.sources, "tls")
		return
	}

	// Distinguish certificate problems from connectivity problems
	var certErr *tls.CertificateVerificationError
	var hostErr x509.HostnameError
	var unknownAuthErr x509.UnknownAuthorityError
	var invalidErr x509.CertificateInvalidError
	if errors.As(err, &certErr) || errors.As(err, &hostErr) || errors.As(err, &unknownAuthErr) || errors.As(err, &invalidErr) {
		// Certificate is invalid — fetch it without verification to
		// report issuer/validity, marked invalid.
		insecureConn, insecureErr := tls.DialWithDialer(dialer, "tcp", net.JoinHostPort(domain, "443"), &tls.Config{
			ServerName:         domain,
			InsecureSkipVerify: true, // #nosec G402 -- intentional: inspecting an already-failed certificate
		})
		if insecureErr == nil {
			defer insecureConn.Close()
			s.recordCert(insecureConn.ConnectionState().PeerCertificates, enrich, false)
			enrich.sources = append(enrich.sources, "tls")
			return
		}
		err = insecureErr
	}

	s.logger.Debug().Err(err).Str("domain", domain).Msg("TLS enrichment unavailable")
}

func (s *URLReputationService) recordCert(certs []*x509.Certificate, enrich *domainEnrichment, verified bool) {
	if len(certs) == 0 {
		return
	}
	leaf := certs[0]

	now := time.Now()
	enrich.certPresent = true
	enrich.certValid = verified && now.After(leaf.NotBefore) && now.Before(leaf.NotAfter)
	enrich.certNotBefore = leaf.NotBefore
	enrich.certNotAfter = leaf.NotAfter

	enrich.certIssuer = leaf.Issuer.CommonName
	if enrich.certIssuer == "" && len(leaf.Issuer.Organization) > 0 {
		enrich.certIssuer = leaf.Issuer.Organization[0]
	}
}

// rdapResponse is the subset of the RDAP domain object we consume.
type rdapResponse struct {
	Events []struct {
		EventAction string `json:"eventAction"`
		EventDate   string `json:"eventDate"`
	} `json:"events"`
	Entities []struct {
		Roles      []string        `json:"roles"`
		VcardArray json.RawMessage `json:"vcardArray"`
	} `json:"entities"`
}

// enrichRDAP queries the public RDAP bootstrap service (rdap.org) for
// registration date and registrar. rdap.org redirects to the
// authoritative registry RDAP server; no API key is required.
func (s *URLReputationService) enrichRDAP(ctx context.Context, domain string, enrich *domainEnrichment) {
	// RDAP only answers for registrable domains, not subdomains.
	// Try the most likely registrable suffixes (handles example.com
	// directly and foo.example.co.uk via the second attempt).
	for _, candidate := range registrableCandidates(domain) {
		if s.queryRDAP(ctx, candidate, enrich) {
			enrich.sources = append(enrich.sources, "rdap")
			return
		}
	}
	s.logger.Debug().Str("domain", domain).Msg("RDAP enrichment unavailable")
}

// registrableCandidates returns probable registrable domains for an
// FQDN, most specific plausible registration first.
func registrableCandidates(domain string) []string {
	labels := strings.Split(domain, ".")
	if len(labels) <= 2 {
		return []string{domain}
	}

	candidates := []string{
		strings.Join(labels[len(labels)-2:], "."), // example.com
		strings.Join(labels[len(labels)-3:], "."), // example.co.uk
	}
	if len(labels) > 3 {
		candidates = append(candidates, domain)
	}
	return candidates
}

func (s *URLReputationService) queryRDAP(ctx context.Context, domain string, enrich *domainEnrichment) bool {
	reqCtx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(reqCtx, http.MethodGet, "https://rdap.org/domain/"+url.PathEscape(domain), nil)
	if err != nil {
		return false
	}
	req.Header.Set("Accept", "application/rdap+json")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		s.logger.Debug().Err(err).Str("domain", domain).Msg("RDAP request failed")
		return false
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return false
	}

	var rdap rdapResponse
	if err := json.NewDecoder(resp.Body).Decode(&rdap); err != nil {
		s.logger.Debug().Err(err).Str("domain", domain).Msg("failed to decode RDAP response")
		return false
	}

	found := false
	for _, event := range rdap.Events {
		if event.EventAction == "registration" {
			if t, err := time.Parse(time.RFC3339, event.EventDate); err == nil {
				enrich.registeredAt = &t
				found = true
			}
		}
	}

	for _, entity := range rdap.Entities {
		for _, role := range entity.Roles {
			if role == "registrar" {
				if name := parseVcardFN(entity.VcardArray); name != "" {
					enrich.registrar = name
					found = true
				}
				break
			}
		}
	}

	return found
}

// parseVcardFN extracts the "fn" (formatted name) from a jCard array
// (RFC 7095): ["vcard", [["fn", {}, "text", "Name"], ...]].
func parseVcardFN(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}

	var vcard []json.RawMessage
	if err := json.Unmarshal(raw, &vcard); err != nil || len(vcard) < 2 {
		return ""
	}

	var props [][]any
	if err := json.Unmarshal(vcard[1], &props); err != nil {
		return ""
	}

	for _, prop := range props {
		if len(prop) >= 4 {
			if name, ok := prop[0].(string); ok && name == "fn" {
				if value, ok := prop[3].(string); ok {
					return value
				}
			}
		}
	}
	return ""
}

// buildReputation combines enrichment data with heuristic scoring into
// a final reputation record. Fields that could not be determined are
// left empty — never fabricated.
func (s *URLReputationService) buildReputation(domain string, enrich *domainEnrichment) *models.URLReputation {
	now := time.Now()

	rep := &models.URLReputation{
		ID:          uuid.New(),
		URL:         domain,
		Domain:      domain,
		LastChecked: now,
		IsShortened: s.isURLShortener(domain),
	}

	risk := 0.0
	tags := []string{}

	// DNS signals
	if len(enrich.ips) > 0 {
		rep.IPAddress = enrich.ips[0].String()
		tags = append(tags, "dns:resolved")
	} else {
		risk += 0.1
		tags = append(tags, "dns:no-address")
	}
	if enrich.mxCount > 0 {
		tags = append(tags, "dns:mx")
	}
	if enrich.nsCount > 0 {
		tags = append(tags, "dns:ns")
	}

	// TLS signals
	if enrich.certPresent {
		valid := enrich.certValid
		rep.CertValid = &valid
		rep.CertIssuer = enrich.certIssuer
		if valid {
			tags = append(tags, "tls:valid")
		} else {
			risk += 0.2
			tags = append(tags, "tls:invalid")
		}
		// Very new certificates are a weak phishing signal
		if certAge := now.Sub(enrich.certNotBefore); certAge >= 0 && certAge < 14*24*time.Hour {
			risk += 0.1
			tags = append(tags, "tls:new-cert")
		}
	} else {
		risk += 0.1
		tags = append(tags, "tls:none")
	}

	// Registration-age signals (RDAP)
	if enrich.registeredAt != nil {
		rep.FirstSeen = *enrich.registeredAt
		rep.Registrar = enrich.registrar
		age := now.Sub(*enrich.registeredAt)
		switch {
		case age < 30*24*time.Hour:
			rep.IsNewDomain = true
			risk += 0.35
			tags = append(tags, "domain:registered-last-30d")
		case age < 90*24*time.Hour:
			rep.IsNewDomain = true
			risk += 0.2
			tags = append(tags, "domain:registered-last-90d")
		case age < 365*24*time.Hour:
			risk += 0.05
			tags = append(tags, "domain:registered-last-year")
		}
	} else if enrich.registrar != "" {
		rep.Registrar = enrich.registrar
	}

	// Heuristic signals
	if hasSuspiciousTLD(domain) {
		rep.HasSuspiciousTLD = true
		risk += 0.2
		tags = append(tags, "heuristic:suspicious-tld")
	}
	if rep.IsShortened {
		risk += 0.15
		tags = append(tags, "heuristic:url-shortener")
	}
	if s.isTyposquatting(domain) {
		risk += 0.5
		tags = append(tags, "heuristic:typosquatting")
	}
	if containsMixedScripts(domain) {
		risk += 0.3
		tags = append(tags, "heuristic:mixed-scripts")
	}

	if risk > 1.0 {
		risk = 1.0
	}
	rep.RiskScore = risk
	rep.Tags = tags
	rep.Sources = append(enrich.sources, "heuristics")

	switch {
	case risk >= 0.7:
		rep.Category = models.URLCategorySuspicious
		rep.ThreatLevel = models.SeverityHigh
	case risk >= 0.45:
		rep.Category = models.URLCategorySuspicious
		rep.ThreatLevel = models.SeverityMedium
	case risk >= 0.25:
		rep.Category = models.URLCategorySuspicious
		rep.ThreatLevel = models.SeverityLow
	default:
		rep.Category = models.URLCategorySafe
		rep.ThreatLevel = models.SeverityInfo
	}
	rep.IsMalicious = false
	rep.IsBlocked = false

	// Confidence grows with the number of successful enrichment sources
	rep.Confidence = 0.5 + 0.1*float64(len(enrich.sources))
	if rep.Confidence > 0.9 {
		rep.Confidence = 0.9
	}

	// Human-readable summary built only from observed facts
	descParts := []string{}
	if len(enrich.ips) > 0 {
		descParts = append(descParts, fmt.Sprintf("resolves to %d address(es)", len(enrich.ips)))
	}
	if enrich.certPresent {
		if enrich.certValid {
			descParts = append(descParts, fmt.Sprintf("valid TLS certificate (issuer: %s, expires %s)", enrich.certIssuer, enrich.certNotAfter.Format("2006-01-02")))
		} else {
			descParts = append(descParts, "TLS certificate failed verification")
		}
	}
	if enrich.registeredAt != nil {
		descParts = append(descParts, "registered "+enrich.registeredAt.Format("2006-01-02"))
	}
	if len(descParts) > 0 {
		rep.Description = "Domain " + strings.Join(descParts, "; ")
	} else {
		rep.Description = "No enrichment data could be collected for this domain"
	}

	return rep
}

// GetStats returns URL protection statistics
func (s *URLReputationService) GetStats(ctx context.Context) (*models.URLStats, error) {
	stats := &models.URLStats{
		ByCategory:        make(map[string]int64),
		ByThreatLevel:     make(map[string]int64),
		TopBlockedDomains: []models.DomainCount{},
	}

	// Get stats from indicators repository
	if s.repos != nil {
		// Count domain indicators
		filter := repository.IndicatorFilter{
			Types: []models.IndicatorType{models.IndicatorTypeDomain, models.IndicatorTypeURL},
		}
		_, total, err := s.repos.Indicators.List(ctx, filter)
		if err == nil {
			stats.TotalChecks = int64(total)
		}

		// Count by severity
		for _, sev := range []models.Severity{models.SeverityCritical, models.SeverityHigh, models.SeverityMedium, models.SeverityLow} {
			filter.Severities = []models.Severity{sev}
			_, count, _ := s.repos.Indicators.List(ctx, filter)
			stats.ByThreatLevel[string(sev)] = int64(count)
		}
	}

	// Count active blacklist entries across all users
	if s.urlLists != nil {
		count, err := s.urlLists.CountByType(ctx, models.URLListTypeBlacklist)
		if err != nil {
			s.logger.Warn().Err(err).Msg("failed to count blacklist entries")
		} else {
			stats.BlockedCount = count
		}
	}

	return stats, nil
}

// GetDNSBlockRules returns DNS blocking rules for VPN integration.
// Rules combine the user's personal blacklist (when authenticated)
// with high-severity domain indicators from threat intelligence.
func (s *URLReputationService) GetDNSBlockRules(ctx context.Context, userID string) ([]models.DNSBlockRule, error) {
	rules := []models.DNSBlockRule{}

	// User's personal blacklist entries
	if userID != "" && s.urlLists != nil {
		entries, err := s.urlLists.List(ctx, userID, models.URLListTypeBlacklist)
		if err != nil {
			return nil, fmt.Errorf("failed to load user blacklist: %w", err)
		}
		for _, entry := range entries {
			pattern := listEntryPattern(&entry)
			if pattern == "" || strings.Contains(pattern, "/") {
				// URL-prefix patterns cannot be enforced at DNS level
				continue
			}
			ruleType := "exact"
			domain := pattern
			if strings.HasPrefix(pattern, "*.") {
				ruleType = "wildcard"
				domain = pattern[2:]
			}
			rules = append(rules, models.DNSBlockRule{
				ID:        entry.ID,
				Domain:    domain,
				RuleType:  ruleType,
				Category:  string(models.URLCategorySuspicious),
				Severity:  models.SeverityHigh,
				Enabled:   true,
				CreatedAt: entry.CreatedAt,
			})
		}
	}

	// High-severity domain indicators from threat intelligence
	if s.repos != nil {
		filter := repository.IndicatorFilter{
			Types:      []models.IndicatorType{models.IndicatorTypeDomain},
			Severities: []models.Severity{models.SeverityHigh, models.SeverityCritical},
			Limit:      10000,
		}

		indicators, _, err := s.repos.Indicators.List(ctx, filter)
		if err == nil {
			for _, ind := range indicators {
				rules = append(rules, models.DNSBlockRule{
					ID:        ind.ID,
					Domain:    ind.Value,
					RuleType:  "exact",
					Category:  string(s.indicatorCategoryToURLCategory(ind.Tags)),
					Severity:  ind.Severity,
					Enabled:   true,
					CreatedAt: ind.FirstSeen,
					UpdatedAt: ind.LastSeen,
				})
			}
		}
	}

	return rules, nil
}
