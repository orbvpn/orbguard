package handlers

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"orbguard-lab/internal/api/middleware"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// IntelligenceHandler handles intelligence endpoints
type IntelligenceHandler struct {
	repos   *repository.Repositories
	reports *repository.ThreatReportRepository
	cache   *cache.RedisCache
	logger  *logger.Logger
}

// NewIntelligenceHandler creates a new IntelligenceHandler
func NewIntelligenceHandler(repos *repository.Repositories, c *cache.RedisCache, log *logger.Logger) *IntelligenceHandler {
	h := &IntelligenceHandler{
		repos:  repos,
		cache:  c,
		logger: log.WithComponent("intelligence"),
	}
	// The threat report repository shares the same pool as the indicator
	// repository; constructing it here avoids new wiring in main.go.
	if repos != nil && repos.Indicators != nil {
		if pool := repos.Indicators.Pool(); pool != nil {
			h.reports = repository.NewThreatReportRepository(pool)
		}
	}
	return h
}

// knownPlatforms is the set of platform values accepted by the API; it
// mirrors the platform_type enum in Postgres.
var knownPlatforms = map[models.Platform]bool{
	models.PlatformAndroid: true,
	models.PlatformIOS:     true,
	models.PlatformWindows: true,
	models.PlatformMacOS:   true,
	models.PlatformLinux:   true,
	models.PlatformAll:     true,
}

// knownReportSeverities is the set of severity values accepted on reports.
var knownReportSeverities = map[models.Severity]bool{
	models.SeverityCritical: true,
	models.SeverityHigh:     true,
	models.SeverityMedium:   true,
	models.SeverityLow:      true,
	models.SeverityInfo:     true,
}

// knownIndicatorTypes is the set of indicator types accepted on reports.
var knownIndicatorTypes = map[models.IndicatorType]bool{
	models.IndicatorTypeDomain:      true,
	models.IndicatorTypeIP:          true,
	models.IndicatorTypeIPv4:        true,
	models.IndicatorTypeIPv6:        true,
	models.IndicatorTypeCIDR:        true,
	models.IndicatorTypeASN:         true,
	models.IndicatorTypeHash:        true,
	models.IndicatorTypeURL:         true,
	models.IndicatorTypeProcess:     true,
	models.IndicatorTypeCertificate: true,
	models.IndicatorTypePackage:     true,
	models.IndicatorTypeEmail:       true,
	models.IndicatorTypeFilePath:    true,
	models.IndicatorTypeRegistry:    true,
	models.IndicatorTypeYARA:        true,
	models.IndicatorTypeCVE:         true,
}

// ListResponse represents a paginated list response
type ListResponse struct {
	Data       any    `json:"data"`
	Total      int    `json:"total"`
	Limit      int    `json:"limit"`
	Offset     int    `json:"offset"`
	HasMore    bool   `json:"has_more"`
	NextCursor string `json:"next_cursor,omitempty"`
}

// List handles GET /api/v1/intelligence
func (h *IntelligenceHandler) List(w http.ResponseWriter, r *http.Request) {
	// Parse query parameters
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 1000 {
		limit = 100
	}
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	// Build filter from query params
	filter := repository.IndicatorFilter{
		Limit:  limit,
		Offset: offset,
	}

	// Parse optional filters
	if types := r.URL.Query()["type"]; len(types) > 0 {
		for _, t := range types {
			filter.Types = append(filter.Types, models.ParseIndicatorType(t))
		}
	}
	if severities := r.URL.Query()["severity"]; len(severities) > 0 {
		for _, s := range severities {
			filter.Severities = append(filter.Severities, models.ParseSeverity(s))
		}
	}
	if search := r.URL.Query().Get("search"); search != "" {
		filter.Value = search
	}

	var data []*models.Indicator
	var total int64
	var err error

	if h.repos != nil {
		data, total, err = h.repos.Indicators.List(r.Context(), filter)
		if err != nil {
			h.logger.Error().Err(err).Msg("failed to list indicators")
			h.respondError(w, http.StatusInternalServerError, "failed to fetch indicators")
			return
		}
	}

	response := ListResponse{
		Data:    data,
		Total:   int(total),
		Limit:   limit,
		Offset:  offset,
		HasMore: offset+len(data) < int(total),
	}

	h.respondJSON(w, http.StatusOK, response)
}

// ListPegasus handles GET /api/v1/intelligence/pegasus
func (h *IntelligenceHandler) ListPegasus(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 1000 {
		limit = 100
	}
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	var data []*models.Indicator
	var total int64
	var err error

	if h.repos != nil {
		data, total, err = h.repos.Indicators.ListPegasus(r.Context(), limit, offset)
		if err != nil {
			h.logger.Error().Err(err).Msg("failed to list pegasus indicators")
			h.respondError(w, http.StatusInternalServerError, "failed to fetch pegasus indicators")
			return
		}
	}

	response := ListResponse{
		Data:    data,
		Total:   int(total),
		Limit:   limit,
		Offset:  offset,
		HasMore: offset+len(data) < int(total),
	}

	h.respondJSON(w, http.StatusOK, response)
}

// ListMobile handles GET /api/v1/intelligence/mobile
func (h *IntelligenceHandler) ListMobile(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 1000 {
		limit = 100
	}
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	if h.repos == nil {
		h.respondError(w, http.StatusServiceUnavailable, "intelligence database unavailable")
		return
	}

	var data []*models.Indicator
	var total int64
	var err error

	if platformParam := r.URL.Query().Get("platform"); platformParam != "" {
		platform := models.ParsePlatform(platformParam)
		if !knownPlatforms[platform] {
			h.respondError(w, http.StatusBadRequest, "invalid platform; expected one of android, ios, windows, macos, linux, all")
			return
		}
		// Indicators tagged 'all' apply to every platform.
		platforms := []models.Platform{platform}
		if platform != models.PlatformAll {
			platforms = append(platforms, models.PlatformAll)
		}
		data, total, err = h.repos.Indicators.List(r.Context(), repository.IndicatorFilter{
			Platforms: platforms,
			Limit:     limit,
			Offset:    offset,
		})
	} else {
		data, total, err = h.repos.Indicators.ListMobile(r.Context(), limit, offset)
	}
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to list mobile indicators")
		h.respondError(w, http.StatusInternalServerError, "failed to fetch mobile indicators")
		return
	}

	response := ListResponse{
		Data:    data,
		Total:   int(total),
		Limit:   limit,
		Offset:  offset,
		HasMore: offset+len(data) < int(total),
	}

	h.respondJSON(w, http.StatusOK, response)
}

// mobileSyncMaxLimit caps how many indicators a single sync page returns.
const mobileSyncMaxLimit = 5000

// parseSinceParam parses the 'since' query parameter, accepting Unix seconds
// or RFC3339. Returns nil when the parameter is absent, and an ok=false when
// it is present but unparseable.
func parseSinceParam(raw string) (*time.Time, bool) {
	if raw == "" {
		return nil, true
	}
	if secs, err := strconv.ParseInt(raw, 10, 64); err == nil {
		t := time.Unix(secs, 0).UTC()
		return &t, true
	}
	if t, err := time.Parse(time.RFC3339, raw); err == nil {
		t = t.UTC()
		return &t, true
	}
	return nil, false
}

// toMobileIndicator converts a full indicator to the compact mobile format.
func toMobileIndicator(ind *models.Indicator) models.MobileIndicator {
	return models.MobileIndicator{
		ID:         ind.ID.String(),
		Value:      ind.Value,
		Type:       ind.Type,
		Severity:   ind.Severity,
		Confidence: ind.Confidence,
		Tags:       ind.Tags,
		Platforms:  ind.Platforms,
		IsPegasus:  ind.IsPegasus(),
		UpdatedAt:  ind.UpdatedAt.Unix(),
	}
}

// toMobileIndicators converts full indicators to the compact mobile format.
func toMobileIndicators(indicators []*models.Indicator) []models.MobileIndicator {
	out := make([]models.MobileIndicator, 0, len(indicators))
	for _, ind := range indicators {
		out = append(out, toMobileIndicator(ind))
	}
	return out
}

// MobileSync handles GET /api/v1/intelligence/mobile/sync
// Optimized sync endpoint for mobile apps.
//
// Modes:
//   - full sync: full=true, or no 'version'/'since' supplied — returns the
//     active indicator set for the platform, paginated via limit/offset.
//   - delta sync: 'since' (Unix seconds or RFC3339) — returns indicators
//     created/updated after that time.
//   - up to date: 'version' equals the current sync version and no 'since' —
//     returns an empty delta.
func (h *IntelligenceHandler) MobileSync(w http.ResponseWriter, r *http.Request) {
	if h.repos == nil {
		h.respondError(w, http.StatusServiceUnavailable, "intelligence database unavailable")
		return
	}

	q := r.URL.Query()
	lastVersion, _ := strconv.ParseInt(q.Get("version"), 10, 64)
	fullSync := q.Get("full") == "true"

	since, ok := parseSinceParam(q.Get("since"))
	if !ok {
		h.respondError(w, http.StatusBadRequest, "invalid 'since' parameter; expected Unix seconds or RFC3339")
		return
	}

	// Platform scope: a specific platform plus 'all'-tagged indicators, or
	// the mobile platforms when unspecified (this is the mobile endpoint).
	var platforms []models.Platform
	if platformParam := q.Get("platform"); platformParam != "" {
		platform := models.ParsePlatform(platformParam)
		if !knownPlatforms[platform] {
			h.respondError(w, http.StatusBadRequest, "invalid platform; expected one of android, ios, windows, macos, linux, all")
			return
		}
		platforms = []models.Platform{platform}
		if platform != models.PlatformAll {
			platforms = append(platforms, models.PlatformAll)
		}
	} else {
		platforms = []models.Platform{models.PlatformAndroid, models.PlatformIOS, models.PlatformAll}
	}

	limit, _ := strconv.Atoi(q.Get("limit"))
	if limit <= 0 || limit > mobileSyncMaxLimit {
		limit = 1000
	}
	offset, _ := strconv.Atoi(q.Get("offset"))
	if offset < 0 {
		offset = 0
	}
	// 'cursor' is the next_cursor value from a previous page.
	if cursor := q.Get("cursor"); cursor != "" {
		if c, err := strconv.Atoi(cursor); err == nil && c > 0 {
			offset = c
		}
	}

	// Current sync version (incremented by the aggregator on data changes).
	var currentVersion int64
	if h.cache != nil {
		v, err := h.cache.GetSyncVersion(r.Context())
		if err != nil {
			h.logger.Warn().Err(err).Msg("failed to read sync version from cache")
		} else {
			currentVersion = v
		}
	}

	// Real last-updated timestamp from the indicator store.
	lastUpdated, hasData, err := h.repos.Indicators.LatestUpdatedAt(r.Context())
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to get latest indicator update time")
		h.respondError(w, http.StatusInternalServerError, "failed to fetch sync state")
		return
	}

	response := models.MobileSyncResponse{
		Version:     currentVersion,
		LastUpdated: lastUpdated,
		HasMore:     false,
	}
	if !hasData {
		// Empty indicator store: nothing to sync; LastUpdated stays zero.
		h.respondJSON(w, http.StatusOK, response)
		return
	}

	switch {
	case !fullSync && since != nil:
		// Delta sync by timestamp.
		indicators, total, err := h.repos.Indicators.ListForSync(r.Context(), platforms, since, limit, offset)
		if err != nil {
			h.logger.Error().Err(err).Msg("failed to list delta sync indicators")
			h.respondError(w, http.StatusInternalServerError, "failed to fetch indicators")
			return
		}

		newIndicators := make([]models.MobileIndicator, 0)
		updatedIndicators := make([]models.MobileIndicator, 0)
		for _, ind := range indicators {
			mi := toMobileIndicator(ind)
			if ind.CreatedAt.After(*since) {
				newIndicators = append(newIndicators, mi)
			} else {
				updatedIndicators = append(updatedIndicators, mi)
			}
		}
		response.NewIndicators = newIndicators
		response.UpdatedIndicators = updatedIndicators
		// Deletions are not tracked (no tombstones), so removals cannot be
		// reported honestly; clients drop indicators via expires_at instead.
		response.RemovedIDs = []string{}
		response.HasMore = offset+len(indicators) < int(total)
		if response.HasMore {
			response.NextCursor = strconv.Itoa(offset + len(indicators))
		}

	case !fullSync && lastVersion > 0 && currentVersion > 0 && lastVersion >= currentVersion:
		// Client is up to date; nothing to send.

	default:
		// Full sync (explicit, first sync, or a version delta that cannot be
		// resolved to a timestamp).
		indicators, total, err := h.repos.Indicators.ListForSync(r.Context(), platforms, nil, limit, offset)
		if err != nil {
			h.logger.Error().Err(err).Msg("failed to list full sync indicators")
			h.respondError(w, http.StatusInternalServerError, "failed to fetch indicators")
			return
		}
		response.Indicators = toMobileIndicators(indicators)
		response.HasMore = offset+len(indicators) < int(total)
		if response.HasMore {
			response.NextCursor = strconv.Itoa(offset + len(indicators))
		}
	}

	h.respondJSON(w, http.StatusOK, response)
}

// ListCommunity handles GET /api/v1/intelligence/community
// Community intelligence consists of user-submitted threat reports that have
// been reviewed and approved. When no approved reports exist yet, it falls
// back to aggregated indicators tagged 'community'.
func (h *IntelligenceHandler) ListCommunity(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 1000 {
		limit = 100
	}
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	if h.reports == nil && h.repos == nil {
		h.respondError(w, http.StatusServiceUnavailable, "intelligence database unavailable")
		return
	}

	if h.reports != nil {
		reports, total, err := h.reports.ListByStatus(r.Context(), string(models.ReportStatusApproved), limit, offset)
		if err != nil {
			h.logger.Error().Err(err).Msg("failed to list approved community reports")
			h.respondError(w, http.StatusInternalServerError, "failed to fetch community intelligence")
			return
		}
		if total > 0 {
			h.respondJSON(w, http.StatusOK, ListResponse{
				Data:    reports,
				Total:   int(total),
				Limit:   limit,
				Offset:  offset,
				HasMore: offset+len(reports) < int(total),
			})
			return
		}
	}

	// Fallback: aggregated indicators tagged as community-sourced.
	if h.repos != nil {
		data, total, err := h.repos.Indicators.List(r.Context(), repository.IndicatorFilter{
			Tags:   []string{"community"},
			Limit:  limit,
			Offset: offset,
		})
		if err != nil {
			h.logger.Error().Err(err).Msg("failed to list community-tagged indicators")
			h.respondError(w, http.StatusInternalServerError, "failed to fetch community intelligence")
			return
		}
		if data == nil {
			data = []*models.Indicator{}
		}
		h.respondJSON(w, http.StatusOK, ListResponse{
			Data:    data,
			Total:   int(total),
			Limit:   limit,
			Offset:  offset,
			HasMore: offset+len(data) < int(total),
		})
		return
	}

	// Reports store reachable but legitimately empty, and no indicator repo.
	h.respondJSON(w, http.StatusOK, ListResponse{
		Data:    []*repository.ThreatReport{},
		Total:   0,
		Limit:   limit,
		Offset:  offset,
		HasMore: false,
	})
}

// Check handles GET /api/v1/intelligence/check?value=...&type=...
func (h *IntelligenceHandler) Check(w http.ResponseWriter, r *http.Request) {
	value := r.URL.Query().Get("value")
	iocType := r.URL.Query().Get("type")

	if value == "" || iocType == "" {
		h.respondError(w, http.StatusBadRequest, "missing value or type parameter")
		return
	}

	result := models.CheckResult{
		Value:       value,
		Type:        models.IndicatorType(iocType),
		IsMalicious: false,
	}

	if h.repos != nil {
		// Compute hash for lookup
		hash := sha256.Sum256([]byte(value))
		hashStr := hex.EncodeToString(hash[:])

		indicator, err := h.repos.Indicators.GetByHash(r.Context(), hashStr)
		if err == nil && indicator != nil {
			result.IsMalicious = true
			result.Indicator = indicator
		}
	}

	h.respondJSON(w, http.StatusOK, result)
}

// CheckBatch handles POST /api/v1/intelligence/check/batch
func (h *IntelligenceHandler) CheckBatch(w http.ResponseWriter, r *http.Request) {
	var req models.CheckRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if len(req.Indicators) == 0 {
		h.respondError(w, http.StatusBadRequest, "no indicators provided")
		return
	}

	if len(req.Indicators) > 100 {
		h.respondError(w, http.StatusBadRequest, "maximum 100 indicators per request")
		return
	}

	// Compute hashes for all values
	hashes := make([]string, len(req.Indicators))
	hashToIndex := make(map[string]int)
	for i, ind := range req.Indicators {
		hash := sha256.Sum256([]byte(ind.Value))
		hashStr := hex.EncodeToString(hash[:])
		hashes[i] = hashStr
		hashToIndex[hashStr] = i
	}

	// Initialize results
	results := make([]models.CheckResult, len(req.Indicators))
	for i, ind := range req.Indicators {
		results[i] = models.CheckResult{
			Value:       ind.Value,
			Type:        ind.Type,
			IsMalicious: false,
		}
	}

	// Batch check in database
	if h.repos != nil {
		matches, err := h.repos.Indicators.CheckBatch(r.Context(), hashes)
		if err != nil {
			h.logger.Error().Err(err).Msg("failed to batch check indicators")
		} else {
			for _, indicator := range matches {
				if idx, ok := hashToIndex[indicator.ValueHash]; ok {
					results[idx].IsMalicious = true
					results[idx].Indicator = indicator
				}
			}
		}
	}

	h.respondJSON(w, http.StatusOK, models.CheckResponse{Results: results})
}

// Report handles POST /api/v1/intelligence/report
func (h *IntelligenceHandler) Report(w http.ResponseWriter, r *http.Request) {
	var req models.CreateReportRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	// Validate request
	if req.IndicatorValue == "" {
		h.respondError(w, http.StatusBadRequest, "indicator_value is required")
		return
	}
	if req.IndicatorType == "" {
		h.respondError(w, http.StatusBadRequest, "indicator_type is required")
		return
	}
	if req.Description == "" {
		h.respondError(w, http.StatusBadRequest, "description is required")
		return
	}
	if len(req.Description) < 10 {
		h.respondError(w, http.StatusBadRequest, "description must be at least 10 characters")
		return
	}
	if len(req.Description) > 1000 {
		h.respondError(w, http.StatusBadRequest, "description must be at most 1000 characters")
		return
	}
	if !knownIndicatorTypes[req.IndicatorType] {
		h.respondError(w, http.StatusBadRequest, "unsupported indicator_type")
		return
	}

	severity := req.Severity
	if severity == "" {
		severity = models.SeverityMedium
	}
	if !knownReportSeverities[severity] {
		h.respondError(w, http.StatusBadRequest, "invalid severity; expected one of critical, high, medium, low, info")
		return
	}

	if req.DeviceInfo.Type != "" && !knownPlatforms[models.ParsePlatform(req.DeviceInfo.Type)] {
		h.respondError(w, http.StatusBadRequest, "invalid device_info.type; expected one of android, ios, windows, macos, linux, all")
		return
	}

	// Reporter identity from the auth context (set by APIKeyAuth).
	userID := middleware.GetUserID(r.Context())
	deviceID := middleware.GetDeviceID(r.Context())
	if userID == "" && deviceID == "" && !middleware.IsServiceRequest(r.Context()) {
		h.respondError(w, http.StatusUnauthorized, "reporter identity unavailable")
		return
	}

	if h.reports == nil {
		h.respondError(w, http.StatusServiceUnavailable, "report storage unavailable")
		return
	}

	// Reject duplicate pending reports from the same reporter for the same
	// indicator value.
	dup, err := h.reports.HasPendingDuplicate(r.Context(), userID, deviceID, req.IndicatorValue)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to check duplicate threat report")
		h.respondError(w, http.StatusInternalServerError, "failed to store report")
		return
	}
	if dup {
		h.respondError(w, http.StatusConflict, "a pending report for this indicator already exists")
		return
	}

	// Basic abuse limit: at most 50 reports per reporter per 24 hours.
	if userID != "" || deviceID != "" {
		count, err := h.reports.CountRecentByReporter(r.Context(), userID, deviceID, time.Now().Add(-24*time.Hour))
		if err != nil {
			h.logger.Error().Err(err).Msg("failed to count recent threat reports")
			h.respondError(w, http.StatusInternalServerError, "failed to store report")
			return
		}
		if count >= 50 {
			h.respondError(w, http.StatusTooManyRequests, "report limit reached; try again later")
			return
		}
	}

	var evidence []byte
	if len(req.EvidenceData) > 0 {
		evidence, err = json.Marshal(req.EvidenceData)
		if err != nil {
			h.respondError(w, http.StatusBadRequest, "invalid evidence_data")
			return
		}
	}

	report, err := h.reports.Create(r.Context(), repository.CreateThreatReportParams{
		UserID:         userID,
		DeviceID:       deviceID,
		IndicatorValue: req.IndicatorValue,
		IndicatorType:  string(req.IndicatorType),
		Severity:       string(severity),
		Description:    req.Description,
		Tags:           req.Tags,
		Platform:       req.DeviceInfo.Type,
		DeviceModel:    req.DeviceInfo.Model,
		OSVersion:      req.DeviceInfo.OSVersion,
		AppVersion:     req.DeviceInfo.AppVersion,
		EvidenceData:   evidence,
	})
	if err != nil {
		h.logger.Error().Err(err).
			Str("value", req.IndicatorValue).
			Str("type", string(req.IndicatorType)).
			Msg("failed to store threat report")
		h.respondError(w, http.StatusInternalServerError, "failed to store report")
		return
	}

	h.logger.Info().
		Str("report_id", report.ID.String()).
		Str("value", req.IndicatorValue).
		Str("type", string(req.IndicatorType)).
		Msg("stored threat report")

	// Best effort: if the reported indicator already exists, bump its report
	// count so corroborated indicators rank higher.
	if h.repos != nil {
		hash := sha256.Sum256([]byte(req.IndicatorValue))
		if existing, lookupErr := h.repos.Indicators.GetByHash(r.Context(), hex.EncodeToString(hash[:])); lookupErr == nil && existing != nil {
			if incErr := h.repos.Indicators.IncrementReportCount(r.Context(), existing.ID); incErr != nil {
				h.logger.Warn().Err(incErr).Str("indicator_id", existing.ID.String()).Msg("failed to increment indicator report count")
			}
		}
	}

	h.respondJSON(w, http.StatusCreated, map[string]any{
		"success":   true,
		"message":   "Report received and queued for review",
		"report_id": report.ID.String(),
		"status":    report.Status,
	})
}

// respondJSON sends a JSON response
func (h *IntelligenceHandler) respondJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

// respondError sends an error response
func (h *IntelligenceHandler) respondError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"error": message})
}
