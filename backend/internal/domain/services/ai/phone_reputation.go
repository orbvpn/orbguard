package ai

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"

	"orbguard-lab/pkg/logger"
)

// PhoneReputationService provides phone number reputation lookup
type PhoneReputationService struct {
	httpClient    *http.Client
	logger        *logger.Logger
	config        PhoneReputationConfig
	cache         map[string]*PhoneReputation
	cacheMu       sync.RWMutex
	cacheExpiry   time.Duration
	knownScamNumbers map[string]ScamNumberInfo

	// communityReports holds user reports apart from cache, so a report can
	// never overwrite what a lookup found. Keyed by normalized number.
	communityReports map[string]map[string]time.Time
	reportsMu        sync.Mutex
}

const (
	// phoneReportThreshold is how many distinct client networks must report a
	// number before other users see it as reported. Device keys are free, so
	// the network, not the key, is what counts as one reporter.
	phoneReportThreshold = 5
	// phoneReportWindow is how long one network's report keeps counting.
	phoneReportWindow = 30 * 24 * time.Hour
	// maxReportedNumbers bounds the memory reports can use.
	maxReportedNumbers = 20000
)

// PhoneReputationConfig contains configuration for phone reputation service
type PhoneReputationConfig struct {
	// API keys for various services
	NumverifyAPIKey   string
	TwilioAccountSID  string
	TwilioAuthToken   string

	// Local database path
	LocalDBPath       string

	// Feature flags
	EnableNumverify   bool
	EnableTwilio      bool
	EnableLocalDB     bool

	// Cache settings
	CacheTTL          time.Duration
}

// PhoneReputation contains the reputation data for a phone number
type PhoneReputation struct {
	Number          string           `json:"number"`
	NormalizedNum   string           `json:"normalized_number"`

	// Validation
	IsValid         bool             `json:"is_valid"`
	CountryCode     string           `json:"country_code"`
	CountryName     string           `json:"country_name"`
	Carrier         string           `json:"carrier,omitempty"`
	LineType        string           `json:"line_type,omitempty"` // mobile, landline, voip, toll-free, premium

	// Reputation
	ReputationScore float64          `json:"reputation_score"` // 0-100, higher is safer
	RiskLevel       PhoneRiskLevel   `json:"risk_level"`
	IsScam          bool             `json:"is_scam"`
	IsSpam          bool             `json:"is_spam"`
	IsPremiumRate   bool             `json:"is_premium_rate"`
	IsVoIP          bool             `json:"is_voip"`

	// Reports
	SpamReports     int              `json:"spam_reports"`
	ScamReports     int              `json:"scam_reports"`
	UserReports     []PhoneReport    `json:"user_reports,omitempty"`

	// Scam details if known
	ScamInfo        *ScamNumberInfo  `json:"scam_info,omitempty"`

	// Categories
	Categories      []string         `json:"categories,omitempty"`

	// Metadata
	CheckedAt       time.Time        `json:"checked_at"`
	DataSources     []string         `json:"data_sources,omitempty"`
	Confidence      float64          `json:"confidence"`
}

// PhoneRiskLevel represents the risk level of a phone number
type PhoneRiskLevel string

const (
	PhoneRiskUnknown   PhoneRiskLevel = "unknown"
	PhoneRiskSafe      PhoneRiskLevel = "safe"
	PhoneRiskLow       PhoneRiskLevel = "low"
	PhoneRiskMedium    PhoneRiskLevel = "medium"
	PhoneRiskHigh      PhoneRiskLevel = "high"
	PhoneRiskDangerous PhoneRiskLevel = "dangerous"
)

// PhoneReport represents a user report about a phone number
type PhoneReport struct {
	ReportType   string    `json:"report_type"` // scam, spam, fraud, harassment
	Description  string    `json:"description,omitempty"`
	ScamType     string    `json:"scam_type,omitempty"`
	ReportedAt   time.Time `json:"reported_at"`
	Verified     bool      `json:"verified"`
}

// ScamNumberInfo contains information about a known scam number
type ScamNumberInfo struct {
	ScamType      string    `json:"scam_type"`
	Description   string    `json:"description"`
	FirstReported time.Time `json:"first_reported"`
	LastActive    time.Time `json:"last_active"`
	TotalReports  int       `json:"total_reports"`
	Verified      bool      `json:"verified"`
	Source        string    `json:"source"`
}

// NewPhoneReputationService creates a new phone reputation service
func NewPhoneReputationService(log *logger.Logger, config PhoneReputationConfig) *PhoneReputationService {
	service := &PhoneReputationService{
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
		logger:           log.WithComponent("phone-reputation"),
		config:           config,
		cache:            make(map[string]*PhoneReputation),
		cacheExpiry:      config.CacheTTL,
		knownScamNumbers: make(map[string]ScamNumberInfo),
		communityReports: make(map[string]map[string]time.Time),
	}

	if config.CacheTTL == 0 {
		service.cacheExpiry = 24 * time.Hour
	}

	// Load known scam numbers
	service.loadKnownScamNumbers()

	return service
}

// loadKnownScamNumbers loads the database of known scam phone numbers
func (s *PhoneReputationService) loadKnownScamNumbers() {
	// Known scam number patterns and specific numbers
	// This would ideally be loaded from a database
	knownScams := []struct {
		pattern     string
		scamType    string
		description string
	}{
		// IRS/Tax scams (US)
		{"+1800", "irs_scam", "IRS impersonation scam"},
		{"+1866", "irs_scam", "IRS impersonation scam"},
		{"+1877", "irs_scam", "IRS impersonation scam"},
		{"+1888", "irs_scam", "IRS impersonation scam"},

		// Tech support scams
		{"+18005551234", "tech_support", "Fake Microsoft support"},
		{"+18005554321", "tech_support", "Fake Apple support"},

		// Premium rate numbers (UK)
		{"+4409", "premium_rate", "UK premium rate number"},
		{"+4490", "premium_rate", "UK premium rate number"},

		// Premium rate numbers (US)
		{"+1900", "premium_rate", "US premium rate number"},
		{"+1976", "premium_rate", "US premium rate number"},

		// UAE specific
		{"+97150", "suspicious", "UAE mobile - common scam source"},
	}

	for _, scam := range knownScams {
		s.knownScamNumbers[scam.pattern] = ScamNumberInfo{
			ScamType:    scam.scamType,
			Description: scam.description,
			Verified:    true,
			Source:      "local_database",
		}
	}
}

// Lookup looks up the reputation of a phone number
func (s *PhoneReputationService) Lookup(ctx context.Context, phoneNumber string) (*PhoneReputation, error) {
	// Normalize the phone number
	normalized := s.normalizeNumber(phoneNumber)

	// Check cache first
	if cached := s.getFromCache(normalized); cached != nil {
		return s.withCommunityReports(normalized, cached), nil
	}

	reputation := &PhoneReputation{
		Number:        phoneNumber,
		NormalizedNum: normalized,
		CheckedAt:     time.Now(),
		Confidence:    0.5, // Default confidence
	}

	// Check local scam database
	s.checkLocalDatabase(normalized, reputation)

	// Validate number format and extract info
	s.validateNumber(normalized, reputation)

	// Check for premium rate numbers
	s.checkPremiumRate(normalized, reputation)

	// Check for VoIP indicators
	s.checkVoIP(normalized, reputation)

	// Query external services if configured
	if s.config.EnableNumverify && s.config.NumverifyAPIKey != "" {
		s.queryNumverify(ctx, normalized, reputation)
	}

	// Calculate final reputation score and risk level
	s.calculateReputation(reputation)

	// Cache the result
	s.addToCache(normalized, reputation)

	return s.withCommunityReports(normalized, reputation), nil
}

// normalizeNumber normalizes a phone number
func (s *PhoneReputationService) normalizeNumber(number string) string {
	// Remove all non-digit characters except leading +
	var result strings.Builder
	for i, c := range number {
		if c == '+' && i == 0 {
			result.WriteRune(c)
		} else if c >= '0' && c <= '9' {
			result.WriteRune(c)
		}
	}

	normalized := result.String()

	// Add + if missing and number is long enough
	if !strings.HasPrefix(normalized, "+") && len(normalized) >= 10 {
		// Assume US/Canada if 10 digits
		if len(normalized) == 10 {
			normalized = "+1" + normalized
		} else if len(normalized) == 11 && normalized[0] == '1' {
			normalized = "+" + normalized
		} else {
			normalized = "+" + normalized
		}
	}

	return normalized
}

// checkLocalDatabase checks the local scam number database
func (s *PhoneReputationService) checkLocalDatabase(number string, reputation *PhoneReputation) {
	// Check exact match
	if info, exists := s.knownScamNumbers[number]; exists {
		reputation.IsScam = true
		reputation.ScamInfo = &info
		reputation.RiskLevel = PhoneRiskDangerous
		reputation.DataSources = append(reputation.DataSources, "local_database")
		reputation.Confidence = 0.95
		return
	}

	// Check prefix match
	for prefix, info := range s.knownScamNumbers {
		if strings.HasPrefix(number, prefix) {
			reputation.IsScam = true
			reputation.ScamInfo = &info
			reputation.RiskLevel = PhoneRiskHigh
			reputation.DataSources = append(reputation.DataSources, "local_database")
			reputation.Confidence = 0.8
			return
		}
	}
}

// validateNumber validates the phone number format
func (s *PhoneReputationService) validateNumber(number string, reputation *PhoneReputation) {
	// Basic validation
	if len(number) < 10 || len(number) > 15 {
		reputation.IsValid = false
		return
	}

	reputation.IsValid = true

	// Extract country code
	countryPatterns := map[string]struct {
		code string
		name string
	}{
		"+1":   {"US", "United States/Canada"},
		"+44":  {"GB", "United Kingdom"},
		"+91":  {"IN", "India"},
		"+86":  {"CN", "China"},
		"+971": {"AE", "United Arab Emirates"},
		"+966": {"SA", "Saudi Arabia"},
		"+49":  {"DE", "Germany"},
		"+33":  {"FR", "France"},
		"+81":  {"JP", "Japan"},
		"+82":  {"KR", "South Korea"},
		"+61":  {"AU", "Australia"},
		"+55":  {"BR", "Brazil"},
		"+52":  {"MX", "Mexico"},
		"+7":   {"RU", "Russia"},
		"+234": {"NG", "Nigeria"},
		"+233": {"GH", "Ghana"},
	}

	for prefix, info := range countryPatterns {
		if strings.HasPrefix(number, prefix) {
			reputation.CountryCode = info.code
			reputation.CountryName = info.name
			break
		}
	}

	// Check for high-risk countries (common scam sources)
	highRiskCountries := map[string]bool{
		"NG": true, // Nigeria
		"GH": true, // Ghana
		"IN": true, // India (call center scams)
	}

	if highRiskCountries[reputation.CountryCode] {
		reputation.Categories = append(reputation.Categories, "high_risk_country")
	}
}

// checkPremiumRate checks if the number is a premium rate number
func (s *PhoneReputationService) checkPremiumRate(number string, reputation *PhoneReputation) {
	premiumPatterns := []string{
		`^\+1900`,       // US premium
		`^\+1976`,       // US premium
		`^\+4409`,       // UK premium
		`^\+4490`,       // UK premium
		`^\+61190`,      // Australia premium
		`^\+353190`,     // Ireland premium
	}

	for _, pattern := range premiumPatterns {
		if matched, _ := regexp.MatchString(pattern, number); matched {
			reputation.IsPremiumRate = true
			reputation.Categories = append(reputation.Categories, "premium_rate")
			reputation.RiskLevel = PhoneRiskHigh
			reputation.Confidence = 0.9
			return
		}
	}
}

// checkVoIP checks for VoIP indicators
func (s *PhoneReputationService) checkVoIP(number string, reputation *PhoneReputation) {
	// VoIP number ranges (simplified - real implementation would be more comprehensive)
	voipPatterns := []struct {
		pattern string
		carrier string
	}{
		{`^\+1855`, "Toll-free (often VoIP)"},
		{`^\+1844`, "Toll-free (often VoIP)"},
		{`^\+1833`, "Toll-free (often VoIP)"},
	}

	for _, vp := range voipPatterns {
		if matched, _ := regexp.MatchString(vp.pattern, number); matched {
			reputation.IsVoIP = true
			reputation.LineType = "voip"
			reputation.Carrier = vp.carrier
			return
		}
	}
}

// queryNumverify queries the Numverify API
func (s *PhoneReputationService) queryNumverify(ctx context.Context, number string, reputation *PhoneReputation) {
	// Remove + for Numverify API
	cleanNumber := strings.TrimPrefix(number, "+")

	url := fmt.Sprintf("http://apilayer.net/api/validate?access_key=%s&number=%s&format=1",
		s.config.NumverifyAPIKey, cleanNumber)

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		s.logger.Warn().Err(err).Msg("Failed to create Numverify request")
		return
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		s.logger.Warn().Err(err).Msg("Numverify API request failed")
		return
	}
	defer resp.Body.Close()

	var result struct {
		Valid         bool   `json:"valid"`
		CountryCode   string `json:"country_code"`
		CountryName   string `json:"country_name"`
		Carrier       string `json:"carrier"`
		LineType      string `json:"line_type"`
		InternationalFormat string `json:"international_format"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		s.logger.Warn().Err(err).Msg("Failed to decode Numverify response")
		return
	}

	reputation.IsValid = result.Valid
	if result.CountryCode != "" {
		reputation.CountryCode = result.CountryCode
		reputation.CountryName = result.CountryName
	}
	if result.Carrier != "" {
		reputation.Carrier = result.Carrier
	}
	if result.LineType != "" {
		reputation.LineType = result.LineType
		if result.LineType == "voip" {
			reputation.IsVoIP = true
		}
	}

	reputation.DataSources = append(reputation.DataSources, "numverify")
	reputation.Confidence = maxFloat(reputation.Confidence, 0.7)
}

// calculateReputation calculates the final reputation score and risk level
func (s *PhoneReputationService) calculateReputation(reputation *PhoneReputation) {
	// Start with base score
	score := 50.0

	// Adjustments based on findings
	if reputation.IsScam {
		score = 0
	} else if reputation.IsSpam {
		score = 20
	} else if reputation.IsPremiumRate {
		score = 25
	} else if reputation.IsVoIP {
		score -= 15 // VoIP is slightly suspicious
	}

	// Country risk adjustment
	for _, category := range reputation.Categories {
		if category == "high_risk_country" {
			score -= 20
		}
	}

	// Validation adjustment
	if !reputation.IsValid {
		score = 10
	}

	// Reports adjustment
	score -= float64(reputation.SpamReports * 5)
	score -= float64(reputation.ScamReports * 10)

	// Ensure score is within bounds
	if score < 0 {
		score = 0
	} else if score > 100 {
		score = 100
	}

	reputation.ReputationScore = score

	// Determine risk level if not already set
	if reputation.RiskLevel == "" || reputation.RiskLevel == PhoneRiskUnknown {
		if score >= 80 {
			reputation.RiskLevel = PhoneRiskSafe
		} else if score >= 60 {
			reputation.RiskLevel = PhoneRiskLow
		} else if score >= 40 {
			reputation.RiskLevel = PhoneRiskMedium
		} else if score >= 20 {
			reputation.RiskLevel = PhoneRiskHigh
		} else {
			reputation.RiskLevel = PhoneRiskDangerous
		}
	}
}

// getFromCache retrieves a phone reputation from cache
func (s *PhoneReputationService) getFromCache(number string) *PhoneReputation {
	s.cacheMu.RLock()
	defer s.cacheMu.RUnlock()

	if cached, exists := s.cache[number]; exists {
		if time.Since(cached.CheckedAt) < s.cacheExpiry {
			return cached
		}
	}
	return nil
}

// addToCache adds a phone reputation to cache
func (s *PhoneReputationService) addToCache(number string, reputation *PhoneReputation) {
	s.cacheMu.Lock()
	defer s.cacheMu.Unlock()

	s.cache[number] = reputation
}

// ClearCache clears the reputation cache
func (s *PhoneReputationService) ClearCache() {
	s.cacheMu.Lock()
	defer s.cacheMu.Unlock()

	s.cache = make(map[string]*PhoneReputation)
}

// ReportNumber records one report of a number as scam, fraud or spam. reporter
// identifies the client's network, as derived by the server; a report without
// one is not counted. A report changes nothing other users see until
// phoneReportThreshold distinct networks have reported the number, and even
// then the number is shown as reported (IsSpam), never as a verified scam.
func (s *PhoneReputationService) ReportNumber(number, reportType, reporter string) {
	switch reportType {
	case "scam", "fraud", "spam":
	default:
		return
	}
	normalized := s.normalizeNumber(number)
	if reporter == "" || len(normalized) < 10 || len(normalized) > 16 {
		return
	}

	s.reportsMu.Lock()
	defer s.reportsMu.Unlock()

	now := time.Now()
	reporters, tracked := s.communityReports[normalized]
	if !tracked {
		if len(s.communityReports) >= maxReportedNumbers {
			s.evictReportedNumber(now)
		}
		reporters = make(map[string]time.Time, 1)
		s.communityReports[normalized] = reporters
	}
	pruneReporters(reporters, now)
	if _, known := reporters[reporter]; known || len(reporters) < phoneReportThreshold {
		reporters[reporter] = now
	}
}

// evictReportedNumber makes room for a new number, preferring one below the
// threshold, so a flood of invented numbers cannot push out a number many
// networks have reported. Callers hold reportsMu.
func (s *PhoneReputationService) evictReportedNumber(now time.Time) {
	for number, reporters := range s.communityReports {
		pruneReporters(reporters, now)
		if len(reporters) < phoneReportThreshold {
			delete(s.communityReports, number)
			return
		}
	}
	for number := range s.communityReports {
		delete(s.communityReports, number)
		return
	}
}

func pruneReporters(reporters map[string]time.Time, now time.Time) {
	for reporter, at := range reporters {
		if now.Sub(at) > phoneReportWindow {
			delete(reporters, reporter)
		}
	}
}

// withCommunityReports returns reputation with the community flag applied when
// enough distinct networks reported the number. It returns a copy: the cached
// entry is shared and stays unchanged.
func (s *PhoneReputationService) withCommunityReports(normalized string, reputation *PhoneReputation) *PhoneReputation {
	s.reportsMu.Lock()
	reporters := s.communityReports[normalized]
	pruneReporters(reporters, time.Now())
	count := len(reporters)
	s.reportsMu.Unlock()

	if count < phoneReportThreshold || reputation.IsScam {
		return reputation
	}
	flagged := *reputation
	flagged.IsSpam = true
	flagged.DataSources = append(append([]string(nil), reputation.DataSources...), "community_reports")
	if flagged.RiskLevel != PhoneRiskHigh && flagged.RiskLevel != PhoneRiskDangerous {
		flagged.RiskLevel = ""
	}
	s.calculateReputation(&flagged)
	return &flagged
}

// AddKnownScamNumber adds a number to the known scam database
func (s *PhoneReputationService) AddKnownScamNumber(number string, info ScamNumberInfo) {
	normalized := s.normalizeNumber(number)
	s.knownScamNumbers[normalized] = info
}

// LookupBatch looks up multiple phone numbers
func (s *PhoneReputationService) LookupBatch(ctx context.Context, numbers []string) map[string]*PhoneReputation {
	results := make(map[string]*PhoneReputation)

	for _, number := range numbers {
		select {
		case <-ctx.Done():
			return results
		default:
		}

		reputation, err := s.Lookup(ctx, number)
		if err != nil {
			s.logger.Warn().Err(err).Str("number", number).Msg("Failed to lookup number")
			continue
		}
		results[number] = reputation
	}

	return results
}

// GetStats returns statistics about the phone reputation database
func (s *PhoneReputationService) GetStats() PhoneReputationStats {
	s.cacheMu.RLock()
	defer s.cacheMu.RUnlock()

	stats := PhoneReputationStats{
		TotalCached:      len(s.cache),
		TotalKnownScams:  len(s.knownScamNumbers),
	}

	for _, rep := range s.cache {
		if rep.IsScam {
			stats.ScamNumbers++
		}
		if rep.IsSpam {
			stats.SpamNumbers++
		}
	}

	return stats
}

// PhoneReputationStats contains statistics about the reputation database
type PhoneReputationStats struct {
	TotalCached     int `json:"total_cached"`
	TotalKnownScams int `json:"total_known_scams"`
	ScamNumbers     int `json:"scam_numbers"`
	SpamNumbers     int `json:"spam_numbers"`
}

// Helper function
func maxFloat(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}

func minFloat(a, b float64) float64 {
	if a < b {
		return a
	}
	return b
}
