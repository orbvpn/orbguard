package services

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// AppAnalyzer provides app security analysis services
type AppAnalyzer struct {
	repos  *repository.Repositories
	appSec *repository.AppSecurityRepository
	cache  *cache.RedisCache
	logger *logger.Logger

	// Known dangerous permissions
	dangerousPermissions map[string]bool
	// Permission to category mapping
	permissionCategories map[string]models.PermissionCategory
}

// NewAppAnalyzer creates a new app analyzer
func NewAppAnalyzer(repos *repository.Repositories, redisCache *cache.RedisCache, log *logger.Logger) *AppAnalyzer {
	analyzer := &AppAnalyzer{
		repos:                repos,
		cache:                redisCache,
		logger:               log.WithComponent("app-analyzer"),
		dangerousPermissions: make(map[string]bool),
		permissionCategories: make(map[string]models.PermissionCategory),
	}

	analyzer.initPermissionMaps()
	return analyzer
}

// SetAppSecurityRepository wires the Postgres-backed app security repository.
// Without it, analysis still runs but history persistence, reputation lookups
// from history, app reports, and stats are unavailable.
func (a *AppAnalyzer) SetAppSecurityRepository(repo *repository.AppSecurityRepository) {
	a.appSec = repo
}

// initPermissionMaps initializes permission classification maps
func (a *AppAnalyzer) initPermissionMaps() {
	// Dangerous permissions
	dangerous := []string{
		"android.permission.READ_CONTACTS",
		"android.permission.WRITE_CONTACTS",
		"android.permission.READ_CALL_LOG",
		"android.permission.WRITE_CALL_LOG",
		"android.permission.PROCESS_OUTGOING_CALLS",
		"android.permission.READ_SMS",
		"android.permission.SEND_SMS",
		"android.permission.RECEIVE_SMS",
		"android.permission.READ_PHONE_STATE",
		"android.permission.CALL_PHONE",
		"android.permission.ACCESS_FINE_LOCATION",
		"android.permission.ACCESS_COARSE_LOCATION",
		"android.permission.ACCESS_BACKGROUND_LOCATION",
		"android.permission.CAMERA",
		"android.permission.RECORD_AUDIO",
		"android.permission.READ_EXTERNAL_STORAGE",
		"android.permission.WRITE_EXTERNAL_STORAGE",
		"android.permission.READ_CALENDAR",
		"android.permission.WRITE_CALENDAR",
		"android.permission.BODY_SENSORS",
		"android.permission.ACTIVITY_RECOGNITION",
		"android.permission.READ_MEDIA_IMAGES",
		"android.permission.READ_MEDIA_VIDEO",
		"android.permission.READ_MEDIA_AUDIO",
	}

	for _, p := range dangerous {
		a.dangerousPermissions[p] = true
	}

	// Permission categories
	a.permissionCategories["android.permission.ACCESS_FINE_LOCATION"] = models.PermissionCategoryLocation
	a.permissionCategories["android.permission.ACCESS_COARSE_LOCATION"] = models.PermissionCategoryLocation
	a.permissionCategories["android.permission.ACCESS_BACKGROUND_LOCATION"] = models.PermissionCategoryLocation
	a.permissionCategories["android.permission.CAMERA"] = models.PermissionCategoryCamera
	a.permissionCategories["android.permission.RECORD_AUDIO"] = models.PermissionCategoryMicrophone
	a.permissionCategories["android.permission.READ_CONTACTS"] = models.PermissionCategoryContacts
	a.permissionCategories["android.permission.WRITE_CONTACTS"] = models.PermissionCategoryContacts
	a.permissionCategories["android.permission.READ_CALENDAR"] = models.PermissionCategoryCalendar
	a.permissionCategories["android.permission.WRITE_CALENDAR"] = models.PermissionCategoryCalendar
	a.permissionCategories["android.permission.READ_EXTERNAL_STORAGE"] = models.PermissionCategoryStorage
	a.permissionCategories["android.permission.WRITE_EXTERNAL_STORAGE"] = models.PermissionCategoryStorage
	a.permissionCategories["android.permission.READ_SMS"] = models.PermissionCategorySMS
	a.permissionCategories["android.permission.SEND_SMS"] = models.PermissionCategorySMS
	a.permissionCategories["android.permission.RECEIVE_SMS"] = models.PermissionCategorySMS
	a.permissionCategories["android.permission.READ_PHONE_STATE"] = models.PermissionCategoryPhone
	a.permissionCategories["android.permission.CALL_PHONE"] = models.PermissionCategoryPhone
	a.permissionCategories["android.permission.READ_CALL_LOG"] = models.PermissionCategoryPhone
	a.permissionCategories["android.permission.BODY_SENSORS"] = models.PermissionCategorySensors
	a.permissionCategories["android.permission.INTERNET"] = models.PermissionCategoryNetwork
	a.permissionCategories["android.permission.ACCESS_NETWORK_STATE"] = models.PermissionCategoryNetwork
	a.permissionCategories["android.permission.BLUETOOTH"] = models.PermissionCategoryBluetooth
	a.permissionCategories["android.permission.BLUETOOTH_ADMIN"] = models.PermissionCategoryBluetooth
	a.permissionCategories["android.permission.BIND_ACCESSIBILITY_SERVICE"] = models.PermissionCategoryAccessibility
	a.permissionCategories["android.permission.BIND_DEVICE_ADMIN"] = models.PermissionCategoryAdmin
}

// AnalyzeApp performs a complete security analysis of an app
func (a *AppAnalyzer) AnalyzeApp(ctx context.Context, req *models.AppAnalysisRequest) (*models.AppAnalysisResult, error) {
	result := &models.AppAnalysisResult{
		ID:              uuid.New(),
		PackageName:     req.PackageName,
		AppName:         req.AppName,
		AnalyzedAt:      time.Now(),
		AnalysisVersion: "1.0.0",
	}

	// 1. Analyze permissions
	result.PermissionRisk = a.analyzePermissions(req.Permissions)

	// 2. Analyze privacy risks
	result.PrivacyRisk = a.analyzePrivacy(req)

	// 3. Analyze security risks
	result.SecurityRisk = a.analyzeSecurityRisks(req)

	// 4. Check threat intelligence
	result.ThreatIntelMatch = a.checkThreatIntelligence(ctx, req)

	// 5. Calculate overall risk score
	result.RiskScore, result.RiskLevel = a.calculateOverallRisk(result)

	// 6. Generate recommendations
	result.Recommendations = a.generateRecommendations(result, req)

	// 7. Set overall verdict
	result.OverallVerdict = a.generateVerdict(result)

	// 8. Persist the analysis so reputation and stats reflect real history.
	a.persistAnalysis(ctx, req, result)

	a.logger.Info().
		Str("package", req.PackageName).
		Str("risk_level", string(result.RiskLevel)).
		Float64("risk_score", result.RiskScore).
		Msg("app analysis completed")

	return result, nil
}

// persistAnalysis stores an analysis row in Postgres. Persistence failures are
// logged but do not fail the analysis itself.
func (a *AppAnalyzer) persistAnalysis(ctx context.Context, req *models.AppAnalysisRequest, result *models.AppAnalysisResult) {
	if a.appSec == nil {
		a.logger.Warn().
			Str("package", req.PackageName).
			Msg("app security repository not configured - analysis not persisted")
		return
	}

	flags := map[string]interface{}{
		"sideloaded":                    result.SecurityRisk.IsSideloaded,
		"targets_old_sdk":               result.SecurityRisk.TargetsOldSDK,
		"tracker_count":                 len(result.PrivacyRisk.TrackerSDKs),
		"dangerous_permissions_granted": result.PermissionRisk.GrantedDangerous,
		"dangerous_combo_count":         len(result.PermissionRisk.DangerousCombos),
		"known_malware":                 result.ThreatIntelMatch != nil && result.ThreatIntelMatch.IsKnownMalware,
		"potentially_harmful":           result.ThreatIntelMatch != nil && result.ThreatIntelMatch.IsPotentiallyHarmful,
	}

	rec := &repository.AppAnalysisRecord{
		ID:            result.ID,
		DeviceID:      req.DeviceID,
		UserID:        req.UserID,
		PackageName:   req.PackageName,
		AppName:       req.AppName,
		Version:       req.VersionName,
		InstallSource: string(req.InstallSource),
		RiskScore:     result.RiskScore,
		RiskLevel:     string(result.RiskLevel),
		Flags:         flags,
		AnalyzedAt:    result.AnalyzedAt,
	}

	if err := a.appSec.InsertAnalysis(ctx, rec); err != nil {
		a.logger.Error().Err(err).
			Str("package", req.PackageName).
			Msg("failed to persist app analysis")
	}
}

// AnalyzeBatch analyzes multiple apps
func (a *AppAnalyzer) AnalyzeBatch(ctx context.Context, req *models.AppBatchAnalysisRequest) (*models.AppBatchAnalysisResult, error) {
	result := &models.AppBatchAnalysisResult{
		Results:    make([]models.AppAnalysisResult, 0, len(req.Apps)),
		TotalCount: len(req.Apps),
		AnalyzedAt: time.Now(),
	}

	for _, app := range req.Apps {
		appResult, err := a.AnalyzeApp(ctx, &app)
		if err != nil {
			a.logger.Warn().Err(err).Str("package", app.PackageName).Msg("failed to analyze app")
			continue
		}

		result.Results = append(result.Results, *appResult)

		switch appResult.RiskLevel {
		case models.AppRiskLevelSafe, models.AppRiskLevelLow:
			result.SafeCount++
		case models.AppRiskLevelMedium, models.AppRiskLevelHigh:
			result.RiskyCount++
		case models.AppRiskLevelCritical:
			result.CriticalCount++
		}
	}

	return result, nil
}

// analyzePermissions analyzes app permissions for risks
func (a *AppAnalyzer) analyzePermissions(permissions []models.AppPermission) models.PermissionRiskAnalysis {
	analysis := models.PermissionRiskAnalysis{
		PermissionGroups: make(map[string]int),
		Concerns:         []string{},
	}

	grantedPerms := make(map[string]bool)

	for _, perm := range permissions {
		// Count dangerous permissions
		if a.dangerousPermissions[perm.Name] || perm.IsDangerous {
			analysis.DangerousCount++
			if perm.IsGranted {
				analysis.GrantedDangerous++
				grantedPerms[perm.Name] = true
			}
		}

		// Categorize permissions
		if cat, ok := a.permissionCategories[perm.Name]; ok {
			analysis.PermissionGroups[string(cat)]++
		}
	}

	// Check for dangerous combinations
	for _, combo := range models.DangerousPermissionCombos {
		allGranted := true
		for _, p := range combo.Permissions {
			if !grantedPerms[p] {
				allGranted = false
				break
			}
		}
		if allGranted {
			analysis.DangerousCombos = append(analysis.DangerousCombos, combo)
			analysis.Concerns = append(analysis.Concerns, combo.Description)
		}
	}

	// Add specific concerns
	if grantedPerms["android.permission.READ_SMS"] {
		analysis.Concerns = append(analysis.Concerns, "Can read your SMS messages")
	}
	if grantedPerms["android.permission.ACCESS_BACKGROUND_LOCATION"] {
		analysis.Concerns = append(analysis.Concerns, "Can track your location in background")
	}
	if grantedPerms["android.permission.BIND_ACCESSIBILITY_SERVICE"] {
		analysis.Concerns = append(analysis.Concerns, "Has accessibility service access - can monitor screen content")
	}
	if grantedPerms["android.permission.BIND_DEVICE_ADMIN"] {
		analysis.Concerns = append(analysis.Concerns, "Has device admin rights - can perform administrative actions")
	}

	// Calculate permission risk score
	analysis.Score = a.calculatePermissionScore(analysis)

	return analysis
}

// analyzePrivacy analyzes privacy risks
func (a *AppAnalyzer) analyzePrivacy(req *models.AppAnalysisRequest) models.PrivacyRiskAnalysis {
	analysis := models.PrivacyRiskAnalysis{
		DataAccessTypes: []string{},
		TrackerSDKs:     []models.TrackerSDK{},
		DataCollection:  models.DataCollectionInfo{},
		Concerns:        []string{},
	}

	// Build permission set
	permSet := make(map[string]bool)
	for _, p := range req.Permissions {
		if p.IsGranted {
			permSet[p.Name] = true
		}
	}

	// Determine data collection capabilities
	if permSet["android.permission.ACCESS_FINE_LOCATION"] || permSet["android.permission.ACCESS_COARSE_LOCATION"] {
		analysis.DataCollection.CollectsLocation = true
		analysis.DataAccessTypes = append(analysis.DataAccessTypes, "Location")
	}
	if permSet["android.permission.READ_CONTACTS"] {
		analysis.DataCollection.CollectsContacts = true
		analysis.DataAccessTypes = append(analysis.DataAccessTypes, "Contacts")
	}
	if permSet["android.permission.READ_CALL_LOG"] {
		analysis.DataCollection.CollectsCallLogs = true
		analysis.DataAccessTypes = append(analysis.DataAccessTypes, "Call Logs")
	}
	if permSet["android.permission.READ_SMS"] {
		analysis.DataCollection.CollectsSMS = true
		analysis.DataAccessTypes = append(analysis.DataAccessTypes, "SMS")
	}
	if permSet["android.permission.CAMERA"] {
		analysis.DataCollection.CollectsCamera = true
		analysis.DataAccessTypes = append(analysis.DataAccessTypes, "Camera")
	}
	if permSet["android.permission.RECORD_AUDIO"] {
		analysis.DataCollection.CollectsMicrophone = true
		analysis.DataAccessTypes = append(analysis.DataAccessTypes, "Microphone")
	}
	if permSet["android.permission.READ_EXTERNAL_STORAGE"] || permSet["android.permission.WRITE_EXTERNAL_STORAGE"] {
		analysis.DataCollection.CollectsStorage = true
		analysis.DataAccessTypes = append(analysis.DataAccessTypes, "Storage")
	}
	if permSet["android.permission.INTERNET"] {
		analysis.DataCollection.HasInternetAccess = true
	}
	if permSet["android.permission.RECEIVE_BOOT_COMPLETED"] || permSet["android.permission.FOREGROUND_SERVICE"] {
		analysis.DataCollection.CanRunInBackground = true
	}

	// Check for known trackers based on the libraries detected inside the app
	// (e.g. from DEX class scanning on the client). An empty detected_libraries
	// list legitimately yields no tracker findings.
	analysis.TrackerSDKs = a.detectTrackers(req.DetectedLibraries)

	// Generate privacy concerns
	if analysis.DataCollection.CollectsLocation && analysis.DataCollection.HasInternetAccess {
		analysis.Concerns = append(analysis.Concerns, "Can collect and transmit your location data")
	}
	if analysis.DataCollection.CollectsContacts && analysis.DataCollection.HasInternetAccess {
		analysis.Concerns = append(analysis.Concerns, "Can access and potentially upload your contacts")
	}
	if len(analysis.TrackerSDKs) > 0 {
		analysis.Concerns = append(analysis.Concerns, "Contains tracking SDKs that may collect your data")
	}
	if analysis.DataCollection.CanRunInBackground && len(analysis.DataAccessTypes) > 2 {
		analysis.Concerns = append(analysis.Concerns, "Can collect data even when not in use")
	}

	// Calculate privacy score
	analysis.Score = a.calculatePrivacyScore(analysis)

	return analysis
}

// detectTrackers matches detected library package names against the known
// tracker SDK list. Matching is prefix-based: a library like
// "com.appsflyer.internal.AFc1qSDK" matches the "com.appsflyer" tracker.
// Results are deduplicated by tracker name.
func (a *AppAnalyzer) detectTrackers(detectedLibraries []string) []models.TrackerSDK {
	trackers := []models.TrackerSDK{}
	if len(detectedLibraries) == 0 {
		return trackers
	}

	seen := make(map[string]bool)
	for _, lib := range detectedLibraries {
		lib = strings.ToLower(strings.TrimSpace(lib))
		if lib == "" {
			continue
		}
		for pkgPrefix, tracker := range models.KnownTrackers {
			if seen[tracker.Name] {
				continue
			}
			prefix := strings.ToLower(pkgPrefix)
			// Library equals the tracker prefix, or is a sub-package of it.
			if lib == prefix || strings.HasPrefix(lib, prefix+".") {
				seen[tracker.Name] = true
				trackers = append(trackers, tracker)
			}
		}
	}

	return trackers
}

// analyzeSecurityRisks analyzes security-related risks
func (a *AppAnalyzer) analyzeSecurityRisks(req *models.AppAnalysisRequest) models.SecurityRiskAnalysis {
	analysis := models.SecurityRiskAnalysis{
		Concerns: []string{},
	}

	// Check install source
	analysis.IsSideloaded = req.InstallSource == models.AppInstallSourceSideloaded ||
		req.InstallSource == models.AppInstallSourceADB ||
		req.InstallSource == models.AppInstallSourceUnknown

	if analysis.IsSideloaded {
		analysis.Concerns = append(analysis.Concerns, "App was not installed from official app store")
	}

	// Check target SDK (old SDKs have known vulnerabilities)
	if req.TargetSDK > 0 && req.TargetSDK < 28 { // Android 9 (Pie)
		analysis.TargetsOldSDK = true
		analysis.Concerns = append(analysis.Concerns, "App targets an outdated Android version with known security issues")
	}

	// Check for signature
	if req.SignatureHash != "" {
		analysis.SignatureValid = true
		// In production, we'd verify against known trusted signatures
	}

	// Additional security checks would include:
	// - APK decompilation for obfuscation detection
	// - Manifest analysis for debug/backup flags
	// - Network security config analysis
	// For now, we'll set sensible defaults

	analysis.HasDebugEnabled = false
	analysis.HasBackupAllowed = true // Most apps allow backup by default

	// Calculate security score
	analysis.Score = a.calculateSecurityScore(analysis)

	return analysis
}

// checkThreatIntelligence checks the app against threat intelligence
func (a *AppAnalyzer) checkThreatIntelligence(ctx context.Context, req *models.AppAnalysisRequest) *models.ThreatIntelMatch {
	if a.repos == nil {
		return nil
	}

	// Check package name against indicators
	indicator, err := a.repos.Indicators.GetByValue(ctx, req.PackageName, models.IndicatorTypePackage)
	if err == nil && indicator != nil {
		return &models.ThreatIntelMatch{
			IsKnownMalware:       indicator.Severity == models.SeverityCritical,
			IsPotentiallyHarmful: severityRank(indicator.Severity) >= severityRank(models.SeverityMedium),
			IndicatorIDs:         []string{indicator.ID.String()},
			DetectionSource:      "threat_intel_db",
			FirstSeen:            indicator.FirstSeen,
		}
	}

	// Check APK hash if available
	if req.APKHash != "" {
		indicator, err = a.repos.Indicators.GetByValue(ctx, req.APKHash, models.IndicatorTypeHash)
		if err == nil && indicator != nil {
			match := &models.ThreatIntelMatch{
				IsKnownMalware:       indicator.Severity == models.SeverityCritical,
				IsPotentiallyHarmful: severityRank(indicator.Severity) >= severityRank(models.SeverityMedium),
				IndicatorIDs:         []string{indicator.ID.String()},
				DetectionSource:      "threat_intel_db",
				FirstSeen:            indicator.FirstSeen,
			}

			// Check for campaign association
			if indicator.CampaignID != nil {
				match.CampaignID = indicator.CampaignID.String()
				campaign, err := a.repos.Campaigns.GetByID(ctx, *indicator.CampaignID)
				if err == nil && campaign != nil {
					match.MalwareFamily = campaign.Name // Use campaign name as malware family
				}
			}

			return match
		}
	}

	return nil
}

// severityRank orders Severity values for comparison (string comparison on the
// Severity type is lexicographic and therefore wrong for ordering).
func severityRank(s models.Severity) int {
	switch s {
	case models.SeverityCritical:
		return 4
	case models.SeverityHigh:
		return 3
	case models.SeverityMedium:
		return 2
	case models.SeverityLow:
		return 1
	case models.SeverityInfo:
		return 0
	default:
		return 0
	}
}

// calculateOverallRisk calculates the overall risk score and level
func (a *AppAnalyzer) calculateOverallRisk(result *models.AppAnalysisResult) (float64, models.AppRiskLevel) {
	// Weighted average of different risk components
	permWeight := 0.30
	privWeight := 0.25
	secWeight := 0.25
	threatWeight := 0.20

	score := result.PermissionRisk.Score*permWeight +
		result.PrivacyRisk.Score*privWeight +
		result.SecurityRisk.Score*secWeight

	// Threat intel match is binary but weighted heavily
	if result.ThreatIntelMatch != nil {
		if result.ThreatIntelMatch.IsKnownMalware {
			score += 100 * threatWeight
		} else if result.ThreatIntelMatch.IsPotentiallyHarmful {
			score += 70 * threatWeight
		}
	}

	// Determine risk level
	var level models.AppRiskLevel
	switch {
	case result.ThreatIntelMatch != nil && result.ThreatIntelMatch.IsKnownMalware:
		level = models.AppRiskLevelCritical
	case score >= 80:
		level = models.AppRiskLevelCritical
	case score >= 60:
		level = models.AppRiskLevelHigh
	case score >= 40:
		level = models.AppRiskLevelMedium
	case score >= 20:
		level = models.AppRiskLevelLow
	default:
		level = models.AppRiskLevelSafe
	}

	return score, level
}

// Score calculation helpers

func (a *AppAnalyzer) calculatePermissionScore(analysis models.PermissionRiskAnalysis) float64 {
	score := 0.0

	// Base score from dangerous permissions
	score += float64(analysis.GrantedDangerous) * 5

	// Extra for dangerous combos
	for _, combo := range analysis.DangerousCombos {
		switch combo.RiskLevel {
		case "critical":
			score += 30
		case "high":
			score += 20
		case "medium":
			score += 10
		}
	}

	// Cap at 100
	if score > 100 {
		score = 100
	}

	return score
}

func (a *AppAnalyzer) calculatePrivacyScore(analysis models.PrivacyRiskAnalysis) float64 {
	score := 0.0

	// Data collection types
	score += float64(len(analysis.DataAccessTypes)) * 8

	// Trackers
	score += float64(len(analysis.TrackerSDKs)) * 10

	// Background capability with data access
	if analysis.DataCollection.CanRunInBackground {
		score += 10
	}

	// Cap at 100
	if score > 100 {
		score = 100
	}

	return score
}

func (a *AppAnalyzer) calculateSecurityScore(analysis models.SecurityRiskAnalysis) float64 {
	score := 0.0

	if analysis.IsSideloaded {
		score += 30
	}
	if analysis.TargetsOldSDK {
		score += 20
	}
	if analysis.HasDebugEnabled {
		score += 25
	}
	if analysis.UsesHTTP {
		score += 15
	}
	if analysis.HasWeakCrypto {
		score += 20
	}
	if !analysis.SignatureValid {
		score += 25
	}

	// Cap at 100
	if score > 100 {
		score = 100
	}

	return score
}

// generateRecommendations creates actionable recommendations
func (a *AppAnalyzer) generateRecommendations(result *models.AppAnalysisResult, req *models.AppAnalysisRequest) []models.AppRecommendation {
	recommendations := []models.AppRecommendation{}

	// Critical: Known malware
	if result.ThreatIntelMatch != nil && result.ThreatIntelMatch.IsKnownMalware {
		recommendations = append(recommendations, models.AppRecommendation{
			ID:          "uninstall_malware",
			Priority:    "critical",
			Category:    "security",
			Title:       "Uninstall Malicious App",
			Description: "This app has been identified as malware. Uninstall it immediately.",
			Action:      "uninstall",
		})
	}

	// High: Sideloaded with risky permissions
	if result.SecurityRisk.IsSideloaded && result.RiskLevel >= models.AppRiskLevelMedium {
		recommendations = append(recommendations, models.AppRecommendation{
			ID:          "review_sideloaded",
			Priority:    "high",
			Category:    "security",
			Title:       "Review Sideloaded App",
			Description: "This app was not installed from an official store and has concerning permissions.",
			Action:      "review",
		})
	}

	// Medium: Excessive permissions
	if result.PermissionRisk.GrantedDangerous > 5 {
		recommendations = append(recommendations, models.AppRecommendation{
			ID:          "review_permissions",
			Priority:    "medium",
			Category:    "permission",
			Title:       "Review App Permissions",
			Description: "This app has access to many sensitive permissions. Consider revoking unnecessary ones.",
			Action:      "revoke_permission",
		})
	}

	// Privacy: Too many trackers
	if len(result.PrivacyRisk.TrackerSDKs) > 3 {
		recommendations = append(recommendations, models.AppRecommendation{
			ID:          "privacy_concern",
			Priority:    "medium",
			Category:    "privacy",
			Title:       "High Tracker Count",
			Description: "This app contains multiple tracking SDKs that may be collecting your data.",
			Action:      "review",
		})
	}

	// Old SDK target
	if result.SecurityRisk.TargetsOldSDK {
		recommendations = append(recommendations, models.AppRecommendation{
			ID:          "update_app",
			Priority:    "low",
			Category:    "update",
			Title:       "App Needs Update",
			Description: "This app targets an old Android version. Look for updates or alternatives.",
			Action:      "update",
		})
	}

	return recommendations
}

// generateVerdict creates a human-readable verdict
func (a *AppAnalyzer) generateVerdict(result *models.AppAnalysisResult) string {
	switch result.RiskLevel {
	case models.AppRiskLevelCritical:
		if result.ThreatIntelMatch != nil && result.ThreatIntelMatch.IsKnownMalware {
			return "DANGEROUS: This app is known malware. Uninstall immediately."
		}
		return "CRITICAL RISK: This app has severe security concerns and should be removed."
	case models.AppRiskLevelHigh:
		return "HIGH RISK: This app has significant security or privacy concerns. Review carefully."
	case models.AppRiskLevelMedium:
		return "MODERATE RISK: This app has some concerning behaviors. Monitor its activity."
	case models.AppRiskLevelLow:
		return "LOW RISK: This app has minor concerns but is generally acceptable."
	default:
		return "SAFE: No significant security or privacy concerns detected."
	}
}

// GetSideloadedApps returns a report on sideloaded apps
func (a *AppAnalyzer) GetSideloadedApps(ctx context.Context, apps []models.AppInfo) (*models.SideloadedAppReport, error) {
	report := &models.SideloadedAppReport{
		TotalApps:       len(apps),
		SideloadedApps:  []models.SideloadedAppInfo{},
		GeneratedAt:     time.Now(),
	}

	for _, app := range apps {
		if app.InstallSource == models.AppInstallSourceSideloaded ||
			app.InstallSource == models.AppInstallSourceADB ||
			app.InstallSource == models.AppInstallSourceUnknown {

			report.SideloadedCount++

			info := models.SideloadedAppInfo{
				PackageName:   app.PackageName,
				AppName:       app.AppName,
				InstallSource: app.InstallSource,
				InstalledAt:   app.InstalledAt,
				Concerns:      []string{"Not installed from official app store"},
			}

			// Quick risk assessment
			if app.InstallSource == models.AppInstallSourceUnknown {
				info.RiskLevel = models.AppRiskLevelHigh
				info.RiskScore = 70
				info.Concerns = append(info.Concerns, "Install source unknown")
			} else {
				info.RiskLevel = models.AppRiskLevelMedium
				info.RiskScore = 40
			}

			if !app.IsSystemApp {
				report.RiskyCount++
			}

			report.SideloadedApps = append(report.SideloadedApps, info)
		}
	}

	if len(report.SideloadedApps) > 0 {
		report.DeviceID = apps[0].DeviceID
	}

	return report, nil
}

// GeneratePrivacyReport generates a privacy audit report
func (a *AppAnalyzer) GeneratePrivacyReport(ctx context.Context, results []models.AppAnalysisResult, deviceID string) (*models.PrivacyReport, error) {
	report := &models.PrivacyReport{
		DeviceID:           deviceID,
		TotalApps:          len(results),
		TrackersByCategory: make(map[string]int),
		AppPrivacyScores:   []models.AppPrivacyScore{},
		GeneratedAt:        time.Now(),
	}

	trackerCounts := make(map[string]int)

	for _, result := range results {
		// Count trackers
		if len(result.PrivacyRisk.TrackerSDKs) > 0 {
			report.AppsWithTrackers++
		}

		for _, tracker := range result.PrivacyRisk.TrackerSDKs {
			report.TotalTrackers++
			trackerCounts[tracker.Name]++
			report.TrackersByCategory[tracker.Category]++
		}

		// Calculate privacy score (inverted - higher is better)
		privacyScore := 100 - result.PrivacyRisk.Score
		if privacyScore < 0 {
			privacyScore = 0
		}

		report.AppPrivacyScores = append(report.AppPrivacyScores, models.AppPrivacyScore{
			PackageName:  result.PackageName,
			AppName:      result.AppName,
			PrivacyScore: privacyScore,
			TrackerCount: len(result.PrivacyRisk.TrackerSDKs),
			DataTypes:    result.PrivacyRisk.DataAccessTypes,
		})
	}

	// Top trackers
	for name, count := range trackerCounts {
		if tracker, ok := models.KnownTrackers[name]; ok {
			report.TopTrackers = append(report.TopTrackers, models.TrackerStats{
				Name:     name,
				Company:  tracker.Company,
				AppCount: count,
				Category: tracker.Category,
			})
		}
	}

	// Generate recommendations
	if report.AppsWithTrackers > report.TotalApps/2 {
		report.Recommendations = append(report.Recommendations, models.AppRecommendation{
			ID:          "many_trackers",
			Priority:    "medium",
			Category:    "privacy",
			Title:       "High Tracker Prevalence",
			Description: "More than half of your apps contain tracking SDKs.",
			Action:      "review",
		})
	}

	return report, nil
}

// ErrAppSecurityUnavailable is returned when app security persistence is not
// configured (no database) and a persistence-backed operation is requested.
var ErrAppSecurityUnavailable = errors.New("app security persistence not configured")

// GetStats returns app security statistics aggregated from stored analyses.
func (a *AppAnalyzer) GetStats(ctx context.Context) (*models.AppSecurityStats, error) {
	if a.appSec == nil {
		a.logger.Warn().Msg("app security stats requested but repository not configured")
		return nil, ErrAppSecurityUnavailable
	}

	stats, err := a.appSec.GetStats(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to load app security stats: %w", err)
	}

	return stats, nil
}

// reputationCacheTTL controls how long computed reputations are cached.
const reputationCacheTTL = 10 * time.Minute

// GetAppReputation computes the reputation of a package from threat
// intelligence indicators, stored analysis history, and user reports.
// Returns (nil, nil) when nothing at all is known about the package.
func (a *AppAnalyzer) GetAppReputation(ctx context.Context, packageName string) (*models.AppReputation, error) {
	cacheKey := "appsec:reputation:" + packageName
	if a.cache != nil {
		var cached models.AppReputation
		if err := a.cache.GetJSON(ctx, cacheKey, &cached); err == nil && cached.PackageName == packageName {
			return &cached, nil
		}
	}

	var (
		indicator *models.Indicator
		summary   *repository.PackageAnalysisSummary
		reports   int64
	)

	// 1. Threat intelligence lookup (package-type IOCs).
	if a.repos != nil && a.repos.Indicators != nil {
		ind, err := a.repos.Indicators.GetByValue(ctx, packageName, models.IndicatorTypePackage)
		if err != nil {
			a.logger.Error().Err(err).Str("package", packageName).Msg("threat intel lookup failed for reputation")
			return nil, fmt.Errorf("threat intelligence lookup failed: %w", err)
		}
		indicator = ind
	}

	// 2. Stored analysis history.
	if a.appSec != nil {
		s, err := a.appSec.GetPackageSummary(ctx, packageName)
		if err != nil {
			a.logger.Error().Err(err).Str("package", packageName).Msg("analysis history lookup failed for reputation")
			return nil, fmt.Errorf("analysis history lookup failed: %w", err)
		}
		summary = s

		count, err := a.appSec.CountReportsForPackage(ctx, packageName)
		if err != nil {
			a.logger.Error().Err(err).Str("package", packageName).Msg("report count lookup failed for reputation")
			return nil, fmt.Errorf("report count lookup failed: %w", err)
		}
		reports = count
	}

	// Nothing known about this package — no fabricated verdict.
	if indicator == nil && summary == nil && reports == 0 {
		return nil, nil
	}

	rep := &models.AppReputation{
		PackageName: packageName,
		ReportCount: int(reports),
		IsVerified:  false,
	}

	// Risk from analysis history (latest analysis is the freshest signal).
	if summary != nil {
		rep.AppName = summary.LatestAppName
		rep.RiskScore = summary.LatestRiskScore
		rep.FirstSeen = summary.FirstAnalyzedAt
		rep.LastUpdated = summary.LastAnalyzedAt
	}

	// Risk from threat intelligence overrides history when stronger.
	if indicator != nil {
		intelScore := severityToScore(indicator.Severity)
		if intelScore > rep.RiskScore {
			rep.RiskScore = intelScore
		}
		if indicator.Severity == models.SeverityCritical || indicator.Severity == models.SeverityHigh {
			rep.IsBlacklisted = true
		}
		if rep.FirstSeen.IsZero() || (!indicator.FirstSeen.IsZero() && indicator.FirstSeen.Before(rep.FirstSeen)) {
			rep.FirstSeen = indicator.FirstSeen
		}
		if indicator.LastSeen.After(rep.LastUpdated) {
			rep.LastUpdated = indicator.LastSeen
		}
	}

	// Many independent user reports raise the floor of the risk score.
	if reports >= 3 && rep.RiskScore < 40 {
		rep.RiskScore = 40
	}

	rep.RiskLevel = riskLevelFromScore(rep.RiskScore)
	if indicator != nil && indicator.Severity == models.SeverityCritical {
		rep.RiskLevel = models.AppRiskLevelCritical
	}

	if rep.LastUpdated.IsZero() {
		rep.LastUpdated = time.Now()
	}
	if rep.FirstSeen.IsZero() {
		rep.FirstSeen = rep.LastUpdated
	}

	if a.cache != nil {
		if err := a.cache.SetJSON(ctx, cacheKey, rep, reputationCacheTTL); err != nil {
			a.logger.Warn().Err(err).Str("package", packageName).Msg("failed to cache app reputation")
		}
	}

	return rep, nil
}

// SaveAppReport persists a user-submitted report about a suspicious app.
func (a *AppAnalyzer) SaveAppReport(ctx context.Context, rec *repository.AppReportRecord) (*repository.AppReportRecord, error) {
	if a.appSec == nil {
		a.logger.Warn().Str("package", rec.PackageName).Msg("app report received but repository not configured")
		return nil, ErrAppSecurityUnavailable
	}

	saved, err := a.appSec.InsertReport(ctx, rec)
	if err != nil {
		return nil, fmt.Errorf("failed to save app report: %w", err)
	}

	// A new report invalidates the cached reputation for the package.
	if a.cache != nil {
		if err := a.cache.Delete(ctx, "appsec:reputation:"+rec.PackageName); err != nil {
			a.logger.Warn().Err(err).Str("package", rec.PackageName).Msg("failed to invalidate reputation cache")
		}
	}

	a.logger.Info().
		Str("package", rec.PackageName).
		Str("type", rec.ReportType).
		Str("report_id", saved.ID.String()).
		Msg("app report persisted")

	return saved, nil
}

// severityToScore maps a threat-intel severity to a 0-100 risk score.
func severityToScore(s models.Severity) float64 {
	switch s {
	case models.SeverityCritical:
		return 95
	case models.SeverityHigh:
		return 80
	case models.SeverityMedium:
		return 55
	case models.SeverityLow:
		return 30
	default:
		return 10
	}
}

// riskLevelFromScore maps a 0-100 risk score to a risk level using the same
// thresholds as calculateOverallRisk.
func riskLevelFromScore(score float64) models.AppRiskLevel {
	switch {
	case score >= 80:
		return models.AppRiskLevelCritical
	case score >= 60:
		return models.AppRiskLevelHigh
	case score >= 40:
		return models.AppRiskLevelMedium
	case score >= 20:
		return models.AppRiskLevelLow
	default:
		return models.AppRiskLevelSafe
	}
}
