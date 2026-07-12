package handlers

import (
	"encoding/json"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// SourcesHandler handles source endpoints
type SourcesHandler struct {
	repos      *repository.Repositories
	aggregator *services.Aggregator
	logger     *logger.Logger
}

// NewSourcesHandler creates a new SourcesHandler
func NewSourcesHandler(repos *repository.Repositories, agg *services.Aggregator, log *logger.Logger) *SourcesHandler {
	return &SourcesHandler{
		repos:      repos,
		aggregator: agg,
		logger:     log.WithComponent("sources"),
	}
}

// List handles GET /api/v1/sources
func (h *SourcesHandler) List(w http.ResponseWriter, r *http.Request) {
	var sources []*models.Source
	var err error

	if h.repos != nil {
		sources, err = h.repos.Sources.List(r.Context())
		if err != nil {
			h.logger.Error().Err(err).Msg("failed to list sources")
			defaults := models.DefaultSources()
			for i := range defaults {
				sources = append(sources, &defaults[i])
			}
		}
	} else {
		defaults := models.DefaultSources()
		for i := range defaults {
			sources = append(sources, &defaults[i])
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"data":  sources,
		"total": len(sources),
	})
}

// Get handles GET /api/v1/sources/{slug}
func (h *SourcesHandler) Get(w http.ResponseWriter, r *http.Request) {
	slug := chi.URLParam(r, "slug")

	if h.repos != nil {
		source, err := h.repos.Sources.GetBySlug(r.Context(), slug)
		if err == nil && source != nil {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(source)
			return
		}
	}

	// Fall back to defaults
	for _, s := range models.DefaultSources() {
		if s.Slug == slug {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(s)
			return
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusNotFound)
	json.NewEncoder(w).Encode(map[string]string{"error": "source not found"})
}

// sourceSlugPattern restricts slugs to lowercase letters, digits,
// underscores and hyphens (2-64 chars, must start with a letter or digit).
var sourceSlugPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]{1,63}$`)

// knownSourceCategories mirrors the SourceCategory constants in models.
var knownSourceCategories = map[models.SourceCategory]bool{
	models.SourceCategoryAbuseCH:    true,
	models.SourceCategoryPhishing:   true,
	models.SourceCategoryIPRep:      true,
	models.SourceCategoryMobile:     true,
	models.SourceCategoryGeneral:    true,
	models.SourceCategoryGovernment: true,
	models.SourceCategoryISAC:       true,
	models.SourceCategoryCommunity:  true,
	models.SourceCategoryPremium:    true,
}

// knownSourceTypes mirrors the SourceType constants in models.
var knownSourceTypes = map[models.SourceType]bool{
	models.SourceTypeAPI:       true,
	models.SourceTypeFeed:      true,
	models.SourceTypeGithub:    true,
	models.SourceTypeTAXII:     true,
	models.SourceTypeManual:    true,
	models.SourceTypeCommunity: true,
}

// settableSourceStatuses are the statuses a client may set explicitly
// ("error" is system-managed and therefore excluded).
var settableSourceStatuses = map[models.SourceStatus]bool{
	models.SourceStatusActive:   true,
	models.SourceStatusPaused:   true,
	models.SourceStatusDisabled: true,
}

// validateFeedHTTPURL ensures a value is an absolute http(s) URL.
func validateFeedHTTPURL(raw string) error {
	u, err := url.Parse(raw)
	if err != nil {
		return err
	}
	if (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return &url.Error{Op: "parse", URL: raw, Err: http.ErrNotSupported}
	}
	return nil
}

// createSourceRequest is the request body for POST /api/v1/sources.
type createSourceRequest struct {
	Name           string   `json:"name"`
	Slug           string   `json:"slug"`
	Description    string   `json:"description,omitempty"`
	Category       string   `json:"category,omitempty"`
	Type           string   `json:"type"`
	URL            string   `json:"url,omitempty"` // shorthand: mapped to api_url/feed_url/github_urls by type
	APIURL         string   `json:"api_url,omitempty"`
	FeedURL        string   `json:"feed_url,omitempty"`
	GithubURLs     []string `json:"github_urls,omitempty"`
	RequiresAPIKey bool     `json:"requires_api_key,omitempty"`
	Reliability    *float64 `json:"reliability,omitempty"`
	Weight         *float64 `json:"weight,omitempty"`
	// Interval accepted either as seconds or a Go duration string ("15m").
	UpdateIntervalSeconds *int64 `json:"update_interval_seconds,omitempty"`
	Interval              string `json:"interval,omitempty"`
	Enabled               *bool  `json:"enabled,omitempty"`
}

// Create handles POST /api/v1/sources — registers a new intelligence source.
func (h *SourcesHandler) Create(w http.ResponseWriter, r *http.Request) {
	if h.repos == nil {
		h.logger.Error().Msg("source creation unavailable: repository not configured")
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "source storage unavailable"})
		return
	}

	var req createSourceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	req.Name = strings.TrimSpace(req.Name)
	req.Slug = strings.ToLower(strings.TrimSpace(req.Slug))

	if req.Name == "" {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "name is required"})
		return
	}
	if !sourceSlugPattern.MatchString(req.Slug) {
		respondJSON(w, http.StatusBadRequest, map[string]string{
			"error": "slug is required and must match ^[a-z0-9][a-z0-9_-]{1,63}$",
		})
		return
	}

	srcType := models.SourceType(strings.ToLower(strings.TrimSpace(req.Type)))
	if !knownSourceTypes[srcType] {
		respondJSON(w, http.StatusBadRequest, map[string]string{
			"error": "type must be one of: api, feed, github, taxii, manual, community",
		})
		return
	}

	category := models.SourceCategory(strings.ToLower(strings.TrimSpace(req.Category)))
	if category == "" {
		category = models.SourceCategoryGeneral
	}
	if !knownSourceCategories[category] {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "unknown category"})
		return
	}

	// Resolve URLs: the "url" shorthand maps onto the type-specific field.
	apiURL := strings.TrimSpace(req.APIURL)
	feedURL := strings.TrimSpace(req.FeedURL)
	githubURLs := req.GithubURLs
	if shorthand := strings.TrimSpace(req.URL); shorthand != "" {
		switch srcType {
		case models.SourceTypeAPI, models.SourceTypeTAXII:
			if apiURL == "" {
				apiURL = shorthand
			}
		case models.SourceTypeGithub:
			if len(githubURLs) == 0 {
				githubURLs = []string{shorthand}
			}
		default:
			if feedURL == "" {
				feedURL = shorthand
			}
		}
	}

	// URL requirements per type.
	switch srcType {
	case models.SourceTypeAPI, models.SourceTypeTAXII:
		if apiURL == "" {
			respondJSON(w, http.StatusBadRequest, map[string]string{"error": "url (api_url) is required for api/taxii sources"})
			return
		}
	case models.SourceTypeFeed:
		if feedURL == "" {
			respondJSON(w, http.StatusBadRequest, map[string]string{"error": "url (feed_url) is required for feed sources"})
			return
		}
	case models.SourceTypeGithub:
		if len(githubURLs) == 0 {
			respondJSON(w, http.StatusBadRequest, map[string]string{"error": "url (github_urls) is required for github sources"})
			return
		}
	}
	for _, candidate := range githubURLs {
		if err := validateFeedHTTPURL(candidate); err != nil {
			respondJSON(w, http.StatusBadRequest, map[string]string{"error": "github_urls entries must be absolute http(s) URLs"})
			return
		}
	}
	for field, candidate := range map[string]string{"api_url": apiURL, "feed_url": feedURL} {
		if candidate == "" {
			continue
		}
		if err := validateFeedHTTPURL(candidate); err != nil {
			respondJSON(w, http.StatusBadRequest, map[string]string{"error": field + " must be an absolute http(s) URL"})
			return
		}
	}

	reliability := 0.5
	if req.Reliability != nil {
		reliability = *req.Reliability
	}
	weight := 1.0
	if req.Weight != nil {
		weight = *req.Weight
	}
	if reliability < 0 || reliability > 1 {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "reliability must be between 0.0 and 1.0"})
		return
	}
	if weight < 0 || weight > 10 {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "weight must be between 0.0 and 10.0"})
		return
	}

	interval, errMsg := resolveSourceInterval(req.UpdateIntervalSeconds, req.Interval, time.Hour)
	if errMsg != "" {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": errMsg})
		return
	}

	status := models.SourceStatusActive
	if req.Enabled != nil && !*req.Enabled {
		status = models.SourceStatusPaused
	}

	// Reject duplicate slugs explicitly (the unique index would also catch
	// this, but a 409 is a clearer contract than a 500).
	existing, err := h.repos.Sources.GetBySlug(r.Context(), req.Slug)
	if err != nil {
		h.logger.Error().Err(err).Str("slug", req.Slug).Msg("failed to check existing source")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to create source"})
		return
	}
	if existing != nil {
		respondJSON(w, http.StatusConflict, map[string]string{"error": "a source with this slug already exists"})
		return
	}

	source := &models.Source{
		Name:           req.Name,
		Slug:           req.Slug,
		Description:    strings.TrimSpace(req.Description),
		Category:       category,
		Type:           srcType,
		Status:         status,
		APIURL:         apiURL,
		FeedURL:        feedURL,
		GithubURLs:     githubURLs,
		RequiresAPIKey: req.RequiresAPIKey,
		Reliability:    reliability,
		Weight:         weight,
		UpdateInterval: interval,
	}

	created, err := h.repos.Sources.Create(r.Context(), source)
	if err != nil {
		h.logger.Error().Err(err).Str("slug", req.Slug).Msg("failed to create source")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to create source"})
		return
	}

	h.logger.Info().Str("slug", created.Slug).Str("id", created.ID.String()).Msg("intelligence source created")
	respondJSON(w, http.StatusCreated, created)
}

// updateSourceRequest is the request body for PATCH /api/v1/sources/{slug}.
// All fields are optional; only present fields are applied.
type updateSourceRequest struct {
	Name        *string  `json:"name,omitempty"`
	Description *string  `json:"description,omitempty"`
	Enabled     *bool    `json:"enabled,omitempty"`
	Status      *string  `json:"status,omitempty"`
	URL         *string  `json:"url,omitempty"` // shorthand: mapped by source type
	APIURL      *string  `json:"api_url,omitempty"`
	FeedURL     *string  `json:"feed_url,omitempty"`
	GithubURLs  []string `json:"github_urls,omitempty"`
	Reliability *float64 `json:"reliability,omitempty"`
	Weight      *float64 `json:"weight,omitempty"`
	// Interval accepted either as seconds or a Go duration string ("15m").
	UpdateIntervalSeconds *int64  `json:"update_interval_seconds,omitempty"`
	Interval              *string `json:"interval,omitempty"`
}

// Update handles PATCH /api/v1/sources/{slug} — partial update of a source.
func (h *SourcesHandler) Update(w http.ResponseWriter, r *http.Request) {
	if h.repos == nil {
		h.logger.Error().Msg("source update unavailable: repository not configured")
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "source storage unavailable"})
		return
	}

	slug := chi.URLParam(r, "slug")

	var req updateSourceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	source, err := h.repos.Sources.GetBySlug(r.Context(), slug)
	if err != nil {
		h.logger.Error().Err(err).Str("slug", slug).Msg("failed to load source for update")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to update source"})
		return
	}

	// The list endpoint serves the built-in defaults until they are
	// persisted; allow patching those by materializing the default row
	// first, so the Sources screen's enable-switch works on a fresh DB.
	isNew := false
	if source == nil {
		for _, def := range models.DefaultSources() {
			if def.Slug == slug {
				defCopy := def
				source = &defCopy
				isNew = true
				break
			}
		}
	}
	if source == nil {
		respondJSON(w, http.StatusNotFound, map[string]string{"error": "source not found"})
		return
	}

	if req.Name != nil {
		name := strings.TrimSpace(*req.Name)
		if name == "" {
			respondJSON(w, http.StatusBadRequest, map[string]string{"error": "name cannot be empty"})
			return
		}
		source.Name = name
	}
	if req.Description != nil {
		source.Description = strings.TrimSpace(*req.Description)
	}

	// Status: explicit status wins over the enabled shorthand.
	if req.Status != nil {
		status := models.SourceStatus(strings.ToLower(strings.TrimSpace(*req.Status)))
		if !settableSourceStatuses[status] {
			respondJSON(w, http.StatusBadRequest, map[string]string{"error": "status must be one of: active, paused, disabled"})
			return
		}
		source.Status = status
	} else if req.Enabled != nil {
		if *req.Enabled {
			source.Status = models.SourceStatusActive
		} else {
			source.Status = models.SourceStatusPaused
		}
	}

	// URL updates.
	if req.URL != nil {
		shorthand := strings.TrimSpace(*req.URL)
		switch source.Type {
		case models.SourceTypeAPI, models.SourceTypeTAXII:
			req.APIURL = &shorthand
		case models.SourceTypeGithub:
			if shorthand != "" {
				req.GithubURLs = []string{shorthand}
			}
		default:
			req.FeedURL = &shorthand
		}
	}
	if req.APIURL != nil {
		apiURL := strings.TrimSpace(*req.APIURL)
		if apiURL != "" {
			if err := validateFeedHTTPURL(apiURL); err != nil {
				respondJSON(w, http.StatusBadRequest, map[string]string{"error": "api_url must be an absolute http(s) URL"})
				return
			}
		}
		source.APIURL = apiURL
	}
	if req.FeedURL != nil {
		feedURL := strings.TrimSpace(*req.FeedURL)
		if feedURL != "" {
			if err := validateFeedHTTPURL(feedURL); err != nil {
				respondJSON(w, http.StatusBadRequest, map[string]string{"error": "feed_url must be an absolute http(s) URL"})
				return
			}
		}
		source.FeedURL = feedURL
	}
	if len(req.GithubURLs) > 0 {
		for _, candidate := range req.GithubURLs {
			if err := validateFeedHTTPURL(candidate); err != nil {
				respondJSON(w, http.StatusBadRequest, map[string]string{"error": "github_urls entries must be absolute http(s) URLs"})
				return
			}
		}
		source.GithubURLs = req.GithubURLs
	}

	if req.Reliability != nil {
		if *req.Reliability < 0 || *req.Reliability > 1 {
			respondJSON(w, http.StatusBadRequest, map[string]string{"error": "reliability must be between 0.0 and 1.0"})
			return
		}
		source.Reliability = *req.Reliability
	}
	if req.Weight != nil {
		if *req.Weight < 0 || *req.Weight > 10 {
			respondJSON(w, http.StatusBadRequest, map[string]string{"error": "weight must be between 0.0 and 10.0"})
			return
		}
		source.Weight = *req.Weight
	}

	intervalStr := ""
	if req.Interval != nil {
		intervalStr = *req.Interval
	}
	if req.UpdateIntervalSeconds != nil || intervalStr != "" {
		interval, errMsg := resolveSourceInterval(req.UpdateIntervalSeconds, intervalStr, source.UpdateInterval)
		if errMsg != "" {
			respondJSON(w, http.StatusBadRequest, map[string]string{"error": errMsg})
			return
		}
		source.UpdateInterval = interval
	}

	var updated *models.Source
	if isNew {
		updated, err = h.repos.Sources.Create(r.Context(), source)
	} else {
		updated, err = h.repos.Sources.Update(r.Context(), source)
	}
	if err != nil {
		h.logger.Error().Err(err).Str("slug", slug).Msg("failed to update source")
		respondJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to update source"})
		return
	}
	if updated == nil {
		respondJSON(w, http.StatusNotFound, map[string]string{"error": "source not found"})
		return
	}

	h.logger.Info().Str("slug", slug).Str("status", string(updated.Status)).Msg("intelligence source updated")
	respondJSON(w, http.StatusOK, updated)
}

// resolveSourceInterval converts the seconds/duration-string pair into a
// time.Duration, enforcing a 60s floor. Returns a non-empty error message
// on invalid input; falls back to def when neither field is provided.
func resolveSourceInterval(seconds *int64, durationStr string, def time.Duration) (time.Duration, string) {
	const minInterval = 60 * time.Second

	if seconds != nil {
		d := time.Duration(*seconds) * time.Second
		if d < minInterval {
			return 0, "update_interval_seconds must be at least 60"
		}
		return d, ""
	}
	if s := strings.TrimSpace(durationStr); s != "" {
		d, err := time.ParseDuration(s)
		if err != nil {
			return 0, "interval must be a valid duration string (e.g. \"15m\", \"4h\")"
		}
		if d < minInterval {
			return 0, "interval must be at least 60s"
		}
		return d, ""
	}
	return def, ""
}
