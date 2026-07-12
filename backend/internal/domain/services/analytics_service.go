package services

import (
	"bytes"
	"context"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"html"
	"math"
	"strconv"
	"time"

	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

const (
	analyticsCacheTTL = 5 * time.Minute
	reportRetention   = 7 * 24 * time.Hour
	reportGenTimeout  = 2 * time.Minute
)

// AnalyticsService provides analytics and reporting capabilities backed by
// real database aggregations
type AnalyticsService struct {
	repos       *repository.Repositories
	analytics   *repository.AnalyticsRepository
	reportsRepo *repository.AnalyticsReportRepository
	cache       *cache.RedisCache
	logger      *logger.Logger
	mitre       *MITREService
}

// NewAnalyticsService creates a new analytics service
func NewAnalyticsService(repos *repository.Repositories, cache *cache.RedisCache, log *logger.Logger) *AnalyticsService {
	return &AnalyticsService{
		repos:       repos,
		analytics:   repository.NewAnalyticsRepositoryFromRepos(repos),
		reportsRepo: repository.NewAnalyticsReportRepositoryFromRepos(repos),
		cache:       cache,
		logger:      log.WithComponent("analytics-service"),
	}
}

// SetMITREService injects the MITRE ATT&CK service used to resolve technique
// names/tactics. Optional: without it technique IDs are still returned.
func (s *AnalyticsService) SetMITREService(m *MITREService) {
	s.mitre = m
}

// GetThreatAnalytics returns threat analytics for the specified time range,
// aggregated from the indicators/campaigns tables
func (s *AnalyticsService) GetThreatAnalytics(ctx context.Context, timeRange models.AnalyticsTimeRange) (*models.ThreatAnalytics, error) {
	if s.analytics == nil {
		return nil, fmt.Errorf("analytics repository not available: database not configured")
	}

	// Serve from cache when the same window was computed recently
	cacheKey := s.threatAnalyticsCacheKey(timeRange)
	if s.cache != nil && cacheKey != "" {
		var cached models.ThreatAnalytics
		if err := s.cache.GetJSON(ctx, cacheKey, &cached); err == nil && cached.GeneratedAt.After(time.Now().Add(-analyticsCacheTTL)) {
			return &cached, nil
		}
	}

	analytics := &models.ThreatAnalytics{
		TimeRange:   timeRange,
		GeneratedAt: time.Now(),
	}

	summary, err := s.buildSummary(ctx, timeRange)
	if err != nil {
		return nil, fmt.Errorf("failed to build analytics summary: %w", err)
	}
	analytics.Summary = summary

	// Trend data (new indicators per bucket)
	trend, err := s.buildTrendData(ctx, timeRange)
	if err != nil {
		s.logger.Warn().Err(err).Msg("failed to build trend data")
	} else {
		analytics.TrendData = trend
	}

	// Distributions (with severity change vs previous period)
	previousRange := previousPeriod(timeRange)
	analytics.BySeverity = s.buildSeverityDistribution(ctx, timeRange, previousRange)
	analytics.ByType = s.buildDistribution(ctx, timeRange, s.analytics.TypeDistribution, "type")
	analytics.ByPlatform = s.buildDistribution(ctx, timeRange, s.analytics.PlatformDistribution, "platform")
	analytics.BySource = s.buildDistribution(ctx, timeRange, s.analytics.SourceDistribution, "source")

	// Top indicators / domains / IPs
	analytics.TopIndicators = s.buildTopIndicators(ctx, timeRange, 10)
	analytics.TopDomains = s.buildTopDomains(ctx, timeRange, 10)
	analytics.TopIPs = s.buildTopIPs(ctx, timeRange, 10)

	// Campaign insights
	if insights, err := s.buildCampaignInsights(ctx, timeRange); err != nil {
		s.logger.Warn().Err(err).Msg("failed to build campaign insights")
	} else {
		analytics.ActiveCampaigns = insights
	}

	// MITRE techniques
	if mitre, err := s.buildMitreData(ctx, timeRange, 10); err != nil {
		s.logger.Warn().Err(err).Msg("failed to build MITRE data")
	} else {
		analytics.MitreTopTechniques = mitre
	}

	if s.cache != nil && cacheKey != "" {
		_ = s.cache.SetJSON(ctx, cacheKey, analytics, analyticsCacheTTL)
	}

	s.logger.Info().
		Time("start", timeRange.Start).
		Time("end", timeRange.End).
		Msg("generated threat analytics")

	return analytics, nil
}

func (s *AnalyticsService) threatAnalyticsCacheKey(timeRange models.AnalyticsTimeRange) string {
	duration := timeRange.End.Sub(timeRange.Start)
	if duration <= 0 {
		return ""
	}
	// Bucket the window end to 5 minutes so repeated dashboard polls hit cache
	return fmt.Sprintf("analytics:threats:%dm:%d",
		int64(duration.Minutes()), timeRange.End.Truncate(5*time.Minute).Unix())
}

// previousPeriod returns the immediately preceding window of equal length
func previousPeriod(timeRange models.AnalyticsTimeRange) models.AnalyticsTimeRange {
	duration := timeRange.End.Sub(timeRange.Start)
	return models.AnalyticsTimeRange{
		Start: timeRange.Start.Add(-duration),
		End:   timeRange.Start,
	}
}

// pctChange computes the percentage change from prev to cur, rounded to 1 decimal
func pctChange(cur, prev int64) float64 {
	if prev == 0 {
		if cur == 0 {
			return 0
		}
		return 100
	}
	return math.Round(float64(cur-prev)/float64(prev)*1000) / 10
}

// buildSummary computes summary metrics from real repository data
func (s *AnalyticsService) buildSummary(ctx context.Context, timeRange models.AnalyticsTimeRange) (*models.AnalyticsSummary, error) {
	summary := &models.AnalyticsSummary{}

	stats, err := s.repos.Indicators.GetStats(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get indicator stats: %w", err)
	}
	summary.TotalIndicators = stats.TotalCount
	summary.PegasusIndicators = stats.PegasusCount
	summary.MobileThreats = stats.MobileCount
	summary.CriticalThreats = stats.CriticalCount
	summary.HighThreats = stats.BySeverity["high"]
	summary.MediumThreats = stats.BySeverity["medium"]
	summary.LowThreats = stats.BySeverity["low"]
	summary.BlockedDomains = stats.ByType["domain"]
	summary.BlockedIPs = stats.ByType["ip"]

	// New indicators within the requested window
	newTotal, newCritical, err := s.analytics.NewIndicatorCounts(ctx, timeRange.Start, timeRange.End)
	if err != nil {
		return nil, err
	}
	summary.NewIndicators = newTotal

	if active, expired, err := s.analytics.ActiveExpiredCounts(ctx); err != nil {
		s.logger.Warn().Err(err).Msg("failed to count active/expired indicators")
	} else {
		summary.ActiveIndicators = active
		summary.ExpiredIndicators = expired
	}

	if s.repos.Campaigns != nil {
		if _, total, err := s.repos.Campaigns.List(ctx, false, 1, 0); err == nil {
			summary.TotalCampaigns = total
		}
		if _, active, err := s.repos.Campaigns.List(ctx, true, 1, 0); err == nil {
			summary.ActiveCampaigns = active
		}
	}

	// Detection / false-positive rates derived from community report review
	// outcomes. Omitted entirely when no reviewed data exists for the window.
	if review, err := s.analytics.CommunityReportMetrics(ctx, timeRange.Start, timeRange.End); err != nil {
		s.logger.Warn().Err(err).Msg("failed to get community report metrics")
	} else if reviewed := review.Approved + review.Rejected; reviewed > 0 {
		detectionRate := math.Round(float64(review.Approved)/float64(reviewed)*1000) / 10
		fpRate := math.Round(float64(review.Rejected)/float64(reviewed)*1000) / 10
		summary.DetectionRate = &detectionRate
		summary.FalsePositiveRate = &fpRate
	}

	// Change from the immediately preceding period (computed, not invented)
	prev := previousPeriod(timeRange)
	prevTotal, prevCritical, err := s.analytics.NewIndicatorCounts(ctx, prev.Start, prev.End)
	if err != nil {
		s.logger.Warn().Err(err).Msg("failed to compute previous period counts")
		return summary, nil
	}

	curCampaigns, errCur := s.analytics.ActiveCampaignCount(ctx, timeRange.Start, timeRange.End)
	prevCampaigns, errPrev := s.analytics.ActiveCampaignCount(ctx, prev.Start, prev.End)

	change := &models.ChangeMetrics{
		IndicatorsChange: pctChange(newTotal, prevTotal),
		CriticalChange:   pctChange(newCritical, prevCritical),
	}
	if errCur == nil && errPrev == nil {
		change.CampaignsChange = pctChange(curCampaigns, prevCampaigns)
	}
	switch {
	case change.IndicatorsChange > 0:
		change.Direction = "up"
	case change.IndicatorsChange < 0:
		change.Direction = "down"
	default:
		change.Direction = "stable"
	}
	summary.ChangeFromPrevious = change

	return summary, nil
}

// trendPointCount derives the number of trend buckets from the window length
func trendPointCount(timeRange models.AnalyticsTimeRange) int {
	duration := timeRange.End.Sub(timeRange.Start)
	points := 24
	if duration > 7*24*time.Hour {
		points = int(duration.Hours() / 24) // daily for longer periods
	} else if duration <= 24*time.Hour {
		points = int(duration.Hours()) // hourly for short periods
	}
	if points < 1 {
		points = 1
	}
	if points > 100 {
		points = 100
	}
	return points
}

// buildTrendData aggregates new indicators per time bucket
func (s *AnalyticsService) buildTrendData(ctx context.Context, timeRange models.AnalyticsTimeRange) ([]models.TrendDataPoint, error) {
	points := trendPointCount(timeRange)
	duration := timeRange.End.Sub(timeRange.Start)
	interval := duration / time.Duration(points)
	bucketSeconds := int64(interval.Seconds())
	if bucketSeconds < 1 {
		bucketSeconds = 1
	}

	buckets, err := s.analytics.TrendBuckets(ctx, timeRange.Start, timeRange.End, bucketSeconds)
	if err != nil {
		return nil, err
	}

	byBucket := make(map[int]repository.TrendBucketRow, len(buckets))
	for _, b := range buckets {
		byBucket[b.Bucket] = b
	}

	trendData := make([]models.TrendDataPoint, points)
	for i := 0; i < points; i++ {
		point := models.TrendDataPoint{
			Timestamp: timeRange.Start.Add(interval * time.Duration(i)),
		}
		if b, ok := byBucket[i]; ok {
			point.Count = b.Count
			point.Critical = b.Critical
			point.High = b.High
			point.Medium = b.Medium
			point.Low = b.Low
		}
		trendData[i] = point
	}
	return trendData, nil
}

// rowsToCategoryCounts converts repository rows into API category counts with
// percentages computed against the in-range total
func rowsToCategoryCounts(rows []repository.CategoryCountRow) []models.CategoryCount {
	var total int64
	for _, r := range rows {
		total += r.Count
	}
	result := make([]models.CategoryCount, len(rows))
	for i, r := range rows {
		cc := models.CategoryCount{Category: r.Category, Count: r.Count}
		if total > 0 {
			cc.Percentage = math.Round(float64(r.Count)/float64(total)*1000) / 10
		}
		result[i] = cc
	}
	return result
}

type distributionQuery func(ctx context.Context, start, end time.Time) ([]repository.CategoryCountRow, error)

func (s *AnalyticsService) buildDistribution(ctx context.Context, timeRange models.AnalyticsTimeRange, query distributionQuery, name string) []models.CategoryCount {
	rows, err := query(ctx, timeRange.Start, timeRange.End)
	if err != nil {
		s.logger.Warn().Err(err).Str("distribution", name).Msg("failed to build distribution")
		return nil
	}
	return rowsToCategoryCounts(rows)
}

// buildSeverityDistribution includes the change vs the previous period
func (s *AnalyticsService) buildSeverityDistribution(ctx context.Context, timeRange, previousRange models.AnalyticsTimeRange) []models.CategoryCount {
	rows, err := s.analytics.SeverityDistribution(ctx, timeRange.Start, timeRange.End)
	if err != nil {
		s.logger.Warn().Err(err).Msg("failed to build severity distribution")
		return nil
	}
	result := rowsToCategoryCounts(rows)

	prevRows, err := s.analytics.SeverityDistribution(ctx, previousRange.Start, previousRange.End)
	if err != nil {
		s.logger.Warn().Err(err).Msg("failed to build previous severity distribution")
		return result
	}
	prevCounts := make(map[string]int64, len(prevRows))
	for _, r := range prevRows {
		prevCounts[r.Category] = r.Count
	}
	for i := range result {
		result[i].Change = pctChange(result[i].Count, prevCounts[result[i].Category])
	}
	return result
}

func (s *AnalyticsService) buildTopIndicators(ctx context.Context, timeRange models.AnalyticsTimeRange, limit int) []models.AnalyticsIndicatorSummary {
	rows, err := s.analytics.TopIndicators(ctx, timeRange.Start, timeRange.End, limit)
	if err != nil {
		s.logger.Warn().Err(err).Msg("failed to build top indicators")
		return nil
	}
	result := make([]models.AnalyticsIndicatorSummary, len(rows))
	for i, r := range rows {
		result[i] = models.AnalyticsIndicatorSummary{
			Value:      r.Value,
			Type:       r.Type,
			Severity:   r.Severity,
			Confidence: r.Confidence,
			HitCount:   r.ReportCount,
			FirstSeen:  r.FirstSeen,
			LastSeen:   r.LastSeen,
			Campaign:   r.Campaign,
			Tags:       r.Tags,
		}
	}
	return result
}

func (s *AnalyticsService) buildTopDomains(ctx context.Context, timeRange models.AnalyticsTimeRange, limit int) []models.DomainSummary {
	rows, err := s.analytics.TopIndicatorsByType(ctx, timeRange.Start, timeRange.End, []string{"domain"}, limit)
	if err != nil {
		s.logger.Warn().Err(err).Msg("failed to build top domains")
		return nil
	}
	result := make([]models.DomainSummary, len(rows))
	for i, r := range rows {
		category := r.Severity
		if len(r.Tags) > 0 {
			category = r.Tags[0]
		}
		result[i] = models.DomainSummary{
			Domain:      r.Value,
			Category:    category,
			HitCount:    r.ReportCount,
			BlockCount:  0, // block events are not tracked server-side
			LastSeen:    r.LastSeen,
			ThreatTypes: r.Tags,
		}
	}
	return result
}

func (s *AnalyticsService) buildTopIPs(ctx context.Context, timeRange models.AnalyticsTimeRange, limit int) []models.IPSummary {
	rows, err := s.analytics.TopIndicatorsByType(ctx, timeRange.Start, timeRange.End, []string{"ip", "ipv6"}, limit)
	if err != nil {
		s.logger.Warn().Err(err).Msg("failed to build top IPs")
		return nil
	}
	result := make([]models.IPSummary, len(rows))
	for i, r := range rows {
		result[i] = models.IPSummary{
			IP:          r.Value,
			Country:     r.Country,
			ASN:         r.ASN,
			HitCount:    r.ReportCount,
			BlockCount:  0, // block events are not tracked server-side
			LastSeen:    r.LastSeen,
			ThreatTypes: r.Tags,
		}
	}
	return result
}

func (s *AnalyticsService) buildCampaignInsights(ctx context.Context, timeRange models.AnalyticsTimeRange) ([]models.CampaignInsight, error) {
	rows, err := s.analytics.ActiveCampaignInsights(ctx, timeRange.Start, timeRange.End)
	if err != nil {
		return nil, err
	}
	insights := make([]models.CampaignInsight, len(rows))
	for i, r := range rows {
		insights[i] = models.CampaignInsight{
			ID:              r.ID.String(),
			Name:            r.Name,
			Status:          r.Status,
			IndicatorCount:  r.IndicatorCount,
			NewIndicators:   r.NewIndicators,
			Severity:        r.TopSeverity,
			TargetSectors:   r.TargetSectors,
			TargetCountries: r.TargetRegions,
			FirstSeen:       r.FirstSeen,
			LastActivity:    r.LastSeen,
			MitreTactics:    r.MitreTactics,
		}
	}
	return insights, nil
}

func (s *AnalyticsService) buildMitreData(ctx context.Context, timeRange models.AnalyticsTimeRange, limit int) ([]models.MitreTechniqueSummary, error) {
	rows, err := s.analytics.MitreTechniqueCounts(ctx, timeRange.Start, timeRange.End, limit)
	if err != nil {
		return nil, err
	}
	result := make([]models.MitreTechniqueSummary, len(rows))
	for i, r := range rows {
		entry := models.MitreTechniqueSummary{
			ID:        r.TechniqueID,
			Count:     r.Count,
			Campaigns: r.Campaigns,
		}
		if s.mitre != nil {
			if tech := s.mitre.GetTechnique(r.TechniqueID); tech != nil {
				entry.Name = tech.Name
				if len(tech.Tactics) > 0 {
					entry.Tactic = tech.Tactics[0]
				}
			}
		}
		result[i] = entry
	}
	return result, nil
}

// GetAlertMetrics returns alert metrics aggregated from community threat
// reports (the platform's alert records)
func (s *AnalyticsService) GetAlertMetrics(ctx context.Context, timeRange models.AnalyticsTimeRange) (*models.AlertMetrics, error) {
	if s.analytics == nil {
		return nil, fmt.Errorf("analytics repository not available: database not configured")
	}

	review, err := s.analytics.CommunityReportMetrics(ctx, timeRange.Start, timeRange.End)
	if err != nil {
		return nil, err
	}

	metrics := &models.AlertMetrics{
		TimeRange:          timeRange,
		TotalAlerts:        review.Total,
		OpenAlerts:         review.Pending,
		AcknowledgedAlerts: review.Reviewing,
		ResolvedAlerts:     review.Approved + review.Rejected + review.Duplicate,
		// MTTA is not tracked (no acknowledgement timestamp exists); omitted.
		MTTR: review.AvgResolveMinutes,
	}

	if bySeverity, err := s.analytics.CommunityReportsBySeverity(ctx, timeRange.Start, timeRange.End); err != nil {
		s.logger.Warn().Err(err).Msg("failed to aggregate alerts by severity")
	} else {
		metrics.AlertsBySeverity = rowsToCategoryCounts(bySeverity)
	}
	if byType, err := s.analytics.CommunityReportsByType(ctx, timeRange.Start, timeRange.End); err != nil {
		s.logger.Warn().Err(err).Msg("failed to aggregate alerts by category")
	} else {
		metrics.AlertsByCategory = rowsToCategoryCounts(byType)
	}
	if trend, err := s.buildReportTrend(ctx, timeRange); err != nil {
		s.logger.Warn().Err(err).Msg("failed to build alert trend")
	} else {
		metrics.AlertsTrend = trend
	}

	return metrics, nil
}

// GetDetectionMetrics returns detection metrics aggregated from community
// threat reports and their review outcomes
func (s *AnalyticsService) GetDetectionMetrics(ctx context.Context, timeRange models.AnalyticsTimeRange) (*models.DetectionMetrics, error) {
	if s.analytics == nil {
		return nil, fmt.Errorf("analytics repository not available: database not configured")
	}

	review, err := s.analytics.CommunityReportMetrics(ctx, timeRange.Start, timeRange.End)
	if err != nil {
		return nil, err
	}

	metrics := &models.DetectionMetrics{
		TimeRange: timeRange,
		// Client-side checks are not tracked server-side, so TotalChecks,
		// DetectionRate and AverageResponseTime are omitted rather than faked.
		TotalDetections: review.Total,
		FalsePositives:  review.Rejected,
	}
	if reviewed := review.Approved + review.Rejected; reviewed > 0 {
		fpRate := math.Round(float64(review.Rejected)/float64(reviewed)*1000) / 10
		metrics.FalsePositiveRate = &fpRate
	}

	if byType, err := s.analytics.CommunityReportsByType(ctx, timeRange.Start, timeRange.End); err != nil {
		s.logger.Warn().Err(err).Msg("failed to aggregate detections by type")
	} else {
		metrics.DetectionsByType = rowsToCategoryCounts(byType)
	}
	if trend, err := s.buildReportTrend(ctx, timeRange); err != nil {
		s.logger.Warn().Err(err).Msg("failed to build detections trend")
	} else {
		metrics.DetectionsTrend = trend
	}

	return metrics, nil
}

func (s *AnalyticsService) buildReportTrend(ctx context.Context, timeRange models.AnalyticsTimeRange) ([]models.TrendDataPoint, error) {
	points := trendPointCount(timeRange)
	duration := timeRange.End.Sub(timeRange.Start)
	interval := duration / time.Duration(points)
	bucketSeconds := int64(interval.Seconds())
	if bucketSeconds < 1 {
		bucketSeconds = 1
	}

	buckets, err := s.analytics.CommunityReportTrend(ctx, timeRange.Start, timeRange.End, bucketSeconds)
	if err != nil {
		return nil, err
	}
	byBucket := make(map[int]repository.TrendBucketRow, len(buckets))
	for _, b := range buckets {
		byBucket[b.Bucket] = b
	}

	trend := make([]models.TrendDataPoint, points)
	for i := 0; i < points; i++ {
		point := models.TrendDataPoint{
			Timestamp: timeRange.Start.Add(interval * time.Duration(i)),
		}
		if b, ok := byBucket[i]; ok {
			point.Count = b.Count
			point.Critical = b.Critical
			point.High = b.High
			point.Medium = b.Medium
			point.Low = b.Low
		}
		trend[i] = point
	}
	return trend, nil
}

// GetSourceHealth returns the real fetch health of all configured feed
// sources, derived from the sources table and recent update history
func (s *AnalyticsService) GetSourceHealth(ctx context.Context) (*models.SourceHealthReport, error) {
	if s.analytics == nil {
		return nil, fmt.Errorf("analytics repository not available: database not configured")
	}

	rows, err := s.analytics.SourceHealth(ctx)
	if err != nil {
		return nil, err
	}

	report := &models.SourceHealthReport{
		GeneratedAt:  time.Now(),
		TotalSources: len(rows),
		Sources:      make([]models.SourceHealthEntry, 0, len(rows)),
	}

	for _, r := range rows {
		entry := models.SourceHealthEntry{
			Slug:           r.Slug,
			Name:           r.Name,
			IndicatorCount: r.IndicatorCount,
			NewToday:       r.NewToday,
			AverageLatency: int64(math.Round(r.AvgLatencyMs)),
			LastError:      r.LastError,
		}
		if r.LastSuccess != nil {
			entry.LastSuccess = *r.LastSuccess
		}
		if r.LastFailure != nil {
			entry.LastFailure = *r.LastFailure
		}
		if r.NextFetch != nil {
			entry.NextScheduled = *r.NextFetch
		}
		if r.Attempts > 0 {
			entry.SuccessRate = math.Round(float64(r.Successes)/float64(r.Attempts)*1000) / 10
		}

		entry.Status = classifySourceHealth(r)
		switch entry.Status {
		case "healthy":
			report.HealthySources++
		case "degraded":
			report.DegradedSources++
		case "failed":
			report.FailedSources++
		}

		report.Sources = append(report.Sources, entry)
	}

	return report, nil
}

// classifySourceHealth derives a health status from real fetch results
func classifySourceHealth(r repository.SourceHealthRow) string {
	switch r.SourceStatus {
	case "disabled", "paused":
		return "disabled"
	case "error":
		return "failed"
	}
	if r.Attempts > 0 {
		rate := float64(r.Successes) / float64(r.Attempts)
		switch {
		case r.Successes == 0:
			return "failed"
		case rate >= 0.9:
			return "healthy"
		default:
			return "degraded"
		}
	}
	// No fetch attempts in the last 7 days
	if r.LastFetched != nil && time.Since(*r.LastFetched) < 24*time.Hour {
		return "healthy"
	}
	return "degraded"
}

// GetGeoDistribution returns the geographic distribution of indicators based
// on country enrichment metadata. Indicators without country data are excluded,
// so the result is empty until enrichment provides geo information.
func (s *AnalyticsService) GetGeoDistribution(ctx context.Context, timeRange models.AnalyticsTimeRange) (*models.GeoDistribution, error) {
	if s.analytics == nil {
		return nil, fmt.Errorf("analytics repository not available: database not configured")
	}

	rows, err := s.analytics.GeoCountryDistribution(ctx, timeRange.Start, timeRange.End, 25)
	if err != nil {
		return nil, err
	}

	var total int64
	for _, r := range rows {
		total += r.Count
	}

	dist := &models.GeoDistribution{Countries: make([]models.GeoCountryData, 0, len(rows))}
	for _, r := range rows {
		entry := models.GeoCountryData{
			CountryCode: r.CountryCode,
			CountryName: countryName(r.CountryCode),
			Count:       r.Count,
			Severity:    r.TopSeverity,
		}
		if total > 0 {
			entry.Percentage = math.Round(float64(r.Count)/float64(total)*1000) / 10
		}
		dist.Countries = append(dist.Countries, entry)
	}
	return dist, nil
}

// isoCountryNames maps common ISO 3166-1 alpha-2 codes to display names
// (static reference data, not metrics)
var isoCountryNames = map[string]string{
	"AE": "United Arab Emirates", "AR": "Argentina", "AT": "Austria", "AU": "Australia",
	"BD": "Bangladesh", "BE": "Belgium", "BG": "Bulgaria", "BR": "Brazil", "BY": "Belarus",
	"CA": "Canada", "CH": "Switzerland", "CL": "Chile", "CN": "China", "CO": "Colombia",
	"CZ": "Czechia", "DE": "Germany", "DK": "Denmark", "EG": "Egypt", "ES": "Spain",
	"FI": "Finland", "FR": "France", "GB": "United Kingdom", "GR": "Greece", "HK": "Hong Kong",
	"HU": "Hungary", "ID": "Indonesia", "IE": "Ireland", "IL": "Israel", "IN": "India",
	"IQ": "Iraq", "IR": "Iran", "IT": "Italy", "JP": "Japan", "KR": "South Korea",
	"KZ": "Kazakhstan", "LT": "Lithuania", "LU": "Luxembourg", "LV": "Latvia", "MA": "Morocco",
	"MD": "Moldova", "MX": "Mexico", "MY": "Malaysia", "NG": "Nigeria", "NL": "Netherlands",
	"NO": "Norway", "NZ": "New Zealand", "PA": "Panama", "PH": "Philippines", "PK": "Pakistan",
	"PL": "Poland", "PT": "Portugal", "RO": "Romania", "RS": "Serbia", "RU": "Russia",
	"SA": "Saudi Arabia", "SC": "Seychelles", "SE": "Sweden", "SG": "Singapore", "SK": "Slovakia",
	"TH": "Thailand", "TR": "Turkey", "TW": "Taiwan", "UA": "Ukraine", "US": "United States",
	"VE": "Venezuela", "VN": "Vietnam", "ZA": "South Africa",
}

func countryName(code string) string {
	if name, ok := isoCountryNames[code]; ok {
		return name
	}
	return code
}

// ============================================================================
// Reports
// ============================================================================

var supportedReportFormats = map[models.ReportFormat]bool{
	models.ReportFormatJSON: true,
	models.ReportFormatCSV:  true,
	models.ReportFormatHTML: true,
}

var supportedReportTypes = map[models.ReportType]bool{
	models.ReportTypeExecutiveSummary: true,
	models.ReportTypeThreatLandscape:  true,
	models.ReportTypeTrendAnalysis:    true,
	models.ReportTypeIndicatorReport:  true,
	models.ReportTypeCampaignAnalysis: true,
	models.ReportTypeSourceHealth:     true,
	models.ReportTypeCustom:           true,
}

// CreateReport creates a new report record and generates its content
// asynchronously, persisting all state transitions to Postgres
func (s *AnalyticsService) CreateReport(ctx context.Context, reportType models.ReportType, format models.ReportFormat, timeRange models.AnalyticsTimeRange, params map[string]interface{}, createdBy string) (*models.AnalyticsReport, error) {
	if s.reportsRepo == nil {
		return nil, fmt.Errorf("report repository not available: database not configured")
	}
	if format == "" {
		format = models.ReportFormatJSON
	}
	if !supportedReportTypes[reportType] {
		return nil, fmt.Errorf("unsupported report type %q: supported types are executive_summary, threat_landscape, trend_analysis, indicator_report, campaign_analysis, source_health, custom", reportType)
	}
	if !supportedReportFormats[format] {
		return nil, fmt.Errorf("unsupported report format %q: supported formats are json, csv, html", format)
	}

	report := &models.AnalyticsReport{
		ID:         uuid.New().String(),
		Name:       string(reportType) + "_" + time.Now().Format("20060102_150405"),
		Type:       reportType,
		Format:     format,
		Status:     models.AnalyticsReportStatusPending,
		TimeRange:  timeRange,
		Parameters: params,
		CreatedBy:  createdBy,
		CreatedAt:  time.Now(),
	}

	if err := s.reportsRepo.Create(ctx, report); err != nil {
		return nil, err
	}

	go s.generateReport(report)

	s.logger.Info().
		Str("report_id", report.ID).
		Str("type", string(reportType)).
		Str("format", string(format)).
		Str("created_by", createdBy).
		Msg("report generation started")

	return report, nil
}

// generateReport aggregates the report payload, renders it in the requested
// format and persists the result
func (s *AnalyticsService) generateReport(report *models.AnalyticsReport) {
	ctx, cancel := context.WithTimeout(context.Background(), reportGenTimeout)
	defer cancel()

	id, err := uuid.Parse(report.ID)
	if err != nil {
		s.logger.Error().Err(err).Str("report_id", report.ID).Msg("invalid report id")
		return
	}

	if err := s.reportsRepo.SetStatus(ctx, id, models.AnalyticsReportStatusGenerating); err != nil {
		s.logger.Error().Err(err).Str("report_id", report.ID).Msg("failed to set report status")
	}

	fail := func(genErr error) {
		s.logger.Error().Err(genErr).Str("report_id", report.ID).Msg("report generation failed")
		if dbErr := s.reportsRepo.Fail(ctx, id, genErr.Error()); dbErr != nil {
			s.logger.Error().Err(dbErr).Str("report_id", report.ID).Msg("failed to persist report failure")
		}
	}

	payload, err := s.buildReportPayload(ctx, report)
	if err != nil {
		fail(err)
		return
	}

	content, err := json.Marshal(payload)
	if err != nil {
		fail(fmt.Errorf("failed to marshal report payload: %w", err))
		return
	}

	fileData, err := s.renderReport(report, payload)
	if err != nil {
		fail(err)
		return
	}

	if err := s.reportsRepo.Complete(ctx, id, content, fileData, time.Now().Add(reportRetention)); err != nil {
		s.logger.Error().Err(err).Str("report_id", report.ID).Msg("failed to persist completed report")
		return
	}

	s.logger.Info().
		Str("report_id", report.ID).
		Int("file_size", len(fileData)).
		Msg("report generation completed")
}

// reportPayload is the structured content of a generated report
type reportPayload struct {
	ReportID    string                     `json:"report_id"`
	Name        string                     `json:"name"`
	Type        models.ReportType          `json:"type"`
	TimeRange   models.AnalyticsTimeRange  `json:"time_range"`
	GeneratedAt time.Time                  `json:"generated_at"`
	Threats     *models.ThreatAnalytics    `json:"threats,omitempty"`
	Campaigns   []models.CampaignInsight   `json:"campaigns,omitempty"`
	Sources     *models.SourceHealthReport `json:"sources,omitempty"`
}

func (s *AnalyticsService) buildReportPayload(ctx context.Context, report *models.AnalyticsReport) (*reportPayload, error) {
	payload := &reportPayload{
		ReportID:    report.ID,
		Name:        report.Name,
		Type:        report.Type,
		TimeRange:   report.TimeRange,
		GeneratedAt: time.Now(),
	}

	switch report.Type {
	case models.ReportTypeSourceHealth:
		sources, err := s.GetSourceHealth(ctx)
		if err != nil {
			return nil, err
		}
		payload.Sources = sources
	case models.ReportTypeCampaignAnalysis:
		campaigns, err := s.buildCampaignInsights(ctx, report.TimeRange)
		if err != nil {
			return nil, err
		}
		payload.Campaigns = campaigns
	default:
		// executive_summary, threat_landscape, trend_analysis,
		// indicator_report, custom: full threat analytics for the range
		threats, err := s.GetThreatAnalytics(ctx, report.TimeRange)
		if err != nil {
			return nil, err
		}
		payload.Threats = threats
	}

	return payload, nil
}

// renderReport renders the payload bytes in the requested format
func (s *AnalyticsService) renderReport(report *models.AnalyticsReport, payload *reportPayload) ([]byte, error) {
	switch report.Format {
	case models.ReportFormatJSON:
		return json.MarshalIndent(payload, "", "  ")
	case models.ReportFormatCSV:
		return renderReportCSV(payload)
	case models.ReportFormatHTML:
		return renderReportHTML(payload)
	default:
		return nil, fmt.Errorf("unsupported report format %q", report.Format)
	}
}

// renderReportCSV renders the report payload as CSV sections
func renderReportCSV(payload *reportPayload) ([]byte, error) {
	var buf bytes.Buffer
	w := csv.NewWriter(&buf)

	write := func(record ...string) {
		_ = w.Write(record)
	}

	write("report_id", payload.ReportID)
	write("name", payload.Name)
	write("type", string(payload.Type))
	write("time_range_start", payload.TimeRange.Start.Format(time.RFC3339))
	write("time_range_end", payload.TimeRange.End.Format(time.RFC3339))
	write("generated_at", payload.GeneratedAt.Format(time.RFC3339))
	write()

	writeDistribution := func(title string, rows []models.CategoryCount) {
		if len(rows) == 0 {
			return
		}
		write(title)
		write("category", "count", "percentage")
		for _, r := range rows {
			write(r.Category, strconv.FormatInt(r.Count, 10), strconv.FormatFloat(r.Percentage, 'f', 1, 64))
		}
		write()
	}

	if t := payload.Threats; t != nil {
		if sum := t.Summary; sum != nil {
			write("summary")
			write("metric", "value")
			write("total_indicators", strconv.FormatInt(sum.TotalIndicators, 10))
			write("new_indicators", strconv.FormatInt(sum.NewIndicators, 10))
			write("active_indicators", strconv.FormatInt(sum.ActiveIndicators, 10))
			write("expired_indicators", strconv.FormatInt(sum.ExpiredIndicators, 10))
			write("critical_threats", strconv.FormatInt(sum.CriticalThreats, 10))
			write("high_threats", strconv.FormatInt(sum.HighThreats, 10))
			write("medium_threats", strconv.FormatInt(sum.MediumThreats, 10))
			write("low_threats", strconv.FormatInt(sum.LowThreats, 10))
			write("pegasus_indicators", strconv.FormatInt(sum.PegasusIndicators, 10))
			write("mobile_threats", strconv.FormatInt(sum.MobileThreats, 10))
			write("total_campaigns", strconv.FormatInt(sum.TotalCampaigns, 10))
			write("active_campaigns", strconv.FormatInt(sum.ActiveCampaigns, 10))
			if sum.DetectionRate != nil {
				write("detection_rate", strconv.FormatFloat(*sum.DetectionRate, 'f', 1, 64))
			}
			if sum.FalsePositiveRate != nil {
				write("false_positive_rate", strconv.FormatFloat(*sum.FalsePositiveRate, 'f', 1, 64))
			}
			write()
		}

		writeDistribution("by_severity", t.BySeverity)
		writeDistribution("by_type", t.ByType)
		writeDistribution("by_platform", t.ByPlatform)
		writeDistribution("by_source", t.BySource)

		if len(t.TopIndicators) > 0 {
			write("top_indicators")
			write("value", "type", "severity", "confidence", "hit_count", "first_seen", "last_seen", "campaign")
			for _, ind := range t.TopIndicators {
				write(ind.Value, ind.Type, ind.Severity,
					strconv.FormatFloat(ind.Confidence, 'f', 2, 64),
					strconv.FormatInt(ind.HitCount, 10),
					ind.FirstSeen.Format(time.RFC3339),
					ind.LastSeen.Format(time.RFC3339),
					ind.Campaign)
			}
			write()
		}

		if len(t.TrendData) > 0 {
			write("trend")
			write("timestamp", "count", "critical", "high", "medium", "low")
			for _, p := range t.TrendData {
				write(p.Timestamp.Format(time.RFC3339),
					strconv.FormatInt(p.Count, 10),
					strconv.FormatInt(p.Critical, 10),
					strconv.FormatInt(p.High, 10),
					strconv.FormatInt(p.Medium, 10),
					strconv.FormatInt(p.Low, 10))
			}
			write()
		}
	}

	if len(payload.Campaigns) > 0 {
		write("campaigns")
		write("id", "name", "status", "severity", "indicator_count", "new_indicators", "first_seen", "last_activity")
		for _, c := range payload.Campaigns {
			write(c.ID, c.Name, c.Status, c.Severity,
				strconv.FormatInt(c.IndicatorCount, 10),
				strconv.FormatInt(c.NewIndicators, 10),
				c.FirstSeen.Format(time.RFC3339),
				c.LastActivity.Format(time.RFC3339))
		}
		write()
	}

	if src := payload.Sources; src != nil {
		write("sources")
		write("slug", "name", "status", "indicator_count", "new_today", "success_rate", "avg_latency_ms", "last_error")
		for _, e := range src.Sources {
			write(e.Slug, e.Name, e.Status,
				strconv.FormatInt(e.IndicatorCount, 10),
				strconv.FormatInt(e.NewToday, 10),
				strconv.FormatFloat(e.SuccessRate, 'f', 1, 64),
				strconv.FormatInt(e.AverageLatency, 10),
				e.LastError)
		}
		write()
	}

	w.Flush()
	if err := w.Error(); err != nil {
		return nil, fmt.Errorf("failed to render CSV report: %w", err)
	}
	return buf.Bytes(), nil
}

// renderReportHTML renders the report payload as a self-contained HTML page
func renderReportHTML(payload *reportPayload) ([]byte, error) {
	pretty, err := json.MarshalIndent(payload, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("failed to render HTML report: %w", err)
	}

	var buf bytes.Buffer
	buf.WriteString("<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n")
	buf.WriteString("<title>" + html.EscapeString(payload.Name) + "</title>\n")
	buf.WriteString("<style>body{font-family:system-ui,sans-serif;margin:2rem;background:#0f1117;color:#e6e6e6}h1{font-size:1.4rem}p{color:#9aa0a6}pre{background:#181b23;padding:1rem;border-radius:8px;overflow:auto;font-size:.85rem}</style>\n")
	buf.WriteString("</head>\n<body>\n")
	buf.WriteString("<h1>" + html.EscapeString(payload.Name) + "</h1>\n")
	buf.WriteString("<p>Type: " + html.EscapeString(string(payload.Type)) +
		" &middot; Range: " + html.EscapeString(payload.TimeRange.Start.Format(time.RFC3339)) +
		" &rarr; " + html.EscapeString(payload.TimeRange.End.Format(time.RFC3339)) +
		" &middot; Generated: " + html.EscapeString(payload.GeneratedAt.Format(time.RFC3339)) + "</p>\n")
	buf.WriteString("<pre>" + html.EscapeString(string(pretty)) + "</pre>\n")
	buf.WriteString("</body>\n</html>\n")
	return buf.Bytes(), nil
}

// GetReport retrieves a report by ID from persistent storage
func (s *AnalyticsService) GetReport(ctx context.Context, id string) (*models.AnalyticsReport, error) {
	if s.reportsRepo == nil {
		return nil, fmt.Errorf("report repository not available: database not configured")
	}
	reportID, err := uuid.Parse(id)
	if err != nil {
		return nil, nil // invalid IDs cannot match any report
	}
	return s.reportsRepo.GetByID(ctx, reportID)
}

// GetReportFile retrieves a completed report's rendered file
func (s *AnalyticsService) GetReportFile(ctx context.Context, id string) ([]byte, *models.AnalyticsReport, error) {
	if s.reportsRepo == nil {
		return nil, nil, fmt.Errorf("report repository not available: database not configured")
	}
	reportID, err := uuid.Parse(id)
	if err != nil {
		return nil, nil, nil // invalid IDs cannot match any report
	}
	return s.reportsRepo.GetFile(ctx, reportID)
}

// ListReports returns persisted reports, newest first. When createdBy is
// non-empty only that user's reports are returned.
func (s *AnalyticsService) ListReports(ctx context.Context, createdBy string, limit int) ([]*models.AnalyticsReport, error) {
	if s.reportsRepo == nil {
		return nil, fmt.Errorf("report repository not available: database not configured")
	}
	reports, err := s.reportsRepo.List(ctx, createdBy, limit)
	if err != nil {
		return nil, err
	}
	if reports == nil {
		reports = []*models.AnalyticsReport{}
	}
	return reports, nil
}

// GetDefaultDashboard returns the default dashboard configuration
func (s *AnalyticsService) GetDefaultDashboard() *models.Dashboard {
	return &models.Dashboard{
		ID:          "default",
		Name:        "Threat Intelligence Overview",
		Description: "Main threat intelligence dashboard",
		RefreshRate: 300, // 5 minutes
		IsDefault:   true,
		Widgets: []models.DashboardWidget{
			{
				ID:            "total-indicators",
				Type:          models.WidgetTypeMetric,
				Title:         "Total Indicators",
				Position:      models.WidgetPosition{X: 0, Y: 0},
				Size:          models.WidgetSize{Width: 3, Height: 1},
				DataSource:    "indicators",
				Visualization: "metric",
			},
			{
				ID:            "critical-threats",
				Type:          models.WidgetTypeMetric,
				Title:         "Critical Threats",
				Position:      models.WidgetPosition{X: 3, Y: 0},
				Size:          models.WidgetSize{Width: 3, Height: 1},
				DataSource:    "indicators",
				Visualization: "metric",
			},
			{
				ID:            "active-campaigns",
				Type:          models.WidgetTypeMetric,
				Title:         "Active Campaigns",
				Position:      models.WidgetPosition{X: 6, Y: 0},
				Size:          models.WidgetSize{Width: 3, Height: 1},
				DataSource:    "campaigns",
				Visualization: "metric",
			},
			{
				ID:            "detection-rate",
				Type:          models.WidgetTypeMetric,
				Title:         "Detection Rate",
				Position:      models.WidgetPosition{X: 9, Y: 0},
				Size:          models.WidgetSize{Width: 3, Height: 1},
				DataSource:    "detections",
				Visualization: "metric",
			},
			{
				ID:            "threat-trend",
				Type:          models.WidgetTypeTrend,
				Title:         "Threat Trend (7 Days)",
				Position:      models.WidgetPosition{X: 0, Y: 1},
				Size:          models.WidgetSize{Width: 8, Height: 3},
				DataSource:    "indicators",
				Visualization: "line_chart",
			},
			{
				ID:            "severity-distribution",
				Type:          models.WidgetTypeChart,
				Title:         "By Severity",
				Position:      models.WidgetPosition{X: 8, Y: 1},
				Size:          models.WidgetSize{Width: 4, Height: 3},
				DataSource:    "indicators",
				Visualization: "pie_chart",
			},
			{
				ID:            "threat-feed",
				Type:          models.WidgetTypeThreatFeed,
				Title:         "Recent Threats",
				Position:      models.WidgetPosition{X: 0, Y: 4},
				Size:          models.WidgetSize{Width: 6, Height: 4},
				DataSource:    "indicators",
				Visualization: "table",
				RefreshRate:   60,
			},
			{
				ID:            "geo-map",
				Type:          models.WidgetTypeMap,
				Title:         "Threat Origins",
				Position:      models.WidgetPosition{X: 6, Y: 4},
				Size:          models.WidgetSize{Width: 6, Height: 4},
				DataSource:    "geo",
				Visualization: "world_map",
			},
		},
		Layout: &models.DashboardLayout{
			Columns: 12,
			Theme:   "dark",
		},
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
}
