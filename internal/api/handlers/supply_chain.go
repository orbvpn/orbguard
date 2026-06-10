package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// maxCheckPackages bounds one /supply-chain/check request.
const maxCheckPackages = 200

// checkRequestTimeout bounds the total time spent resolving one check
// request against OSV (individual HTTP calls have their own client timeout).
const checkRequestTimeout = 60 * time.Second

// SupplyChainHandler handles supply-chain security endpoints backed by
// OSV.dev vulnerability data and the curated tracker dataset.
type SupplyChainHandler struct {
	service *services.SupplyChainService
	logger  *logger.Logger
}

// NewSupplyChainHandler creates a new supply-chain handler. osvBaseURL may
// be empty to use the public OSV.dev API endpoint.
func NewSupplyChainHandler(repos *repository.Repositories, log *logger.Logger, osvBaseURL string) *SupplyChainHandler {
	return &SupplyChainHandler{
		service: services.NewSupplyChainService(repos, log, osvBaseURL),
		logger:  log.WithComponent("supply-chain-handler"),
	}
}

// vulnerabilityResponse is one cached advisory in the GET /vulnerabilities
// payload. Canonical fields mirror the supply_chain_vulns columns; the
// library_name/description/affected_versions/published_date aliases match
// what the current Flutter client parses (supply_chain_monitor_service).
type vulnerabilityResponse struct {
	ID           string     `json:"id"`
	Ecosystem    string     `json:"ecosystem"`
	PackageName  string     `json:"package_name"`
	VersionRange string     `json:"version_range"`
	CVEID        string     `json:"cve_id"`
	Severity     string     `json:"severity"`
	CVSSScore    float64    `json:"cvss_score"`
	Summary      string     `json:"summary"`
	Source       string     `json:"source"`
	PublishedAt  *time.Time `json:"published_at,omitempty"`
	FetchedAt    time.Time  `json:"fetched_at"`

	// Compatibility aliases for the current client parser.
	LibraryName      string     `json:"library_name"`
	Description      string     `json:"description"`
	AffectedVersions string     `json:"affected_versions"`
	PublishedDate    *time.Time `json:"published_date,omitempty"`
}

// GetVulnerabilities handles GET /api/v1/supply-chain/vulnerabilities -
// returns the cached OSV-sourced vulnerability database. Optional query
// parameters: ecosystem, package, limit (default 500, max 2000).
func (h *SupplyChainHandler) GetVulnerabilities(w http.ResponseWriter, r *http.Request) {
	if !h.service.HasStorage() {
		h.logger.Error().Msg("supply-chain vulnerabilities unavailable: database not configured")
		http.Error(w, "Vulnerability storage unavailable", http.StatusServiceUnavailable)
		return
	}

	limit := 500
	if raw := r.URL.Query().Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed <= 0 {
			http.Error(w, "limit must be a positive integer", http.StatusBadRequest)
			return
		}
		limit = parsed
	}
	if limit > 2000 {
		limit = 2000
	}

	recs, err := h.service.ListVulnerabilities(
		r.Context(),
		r.URL.Query().Get("ecosystem"),
		r.URL.Query().Get("package"),
		limit,
	)
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to list supply-chain vulnerabilities")
		http.Error(w, "Failed to load vulnerabilities", http.StatusInternalServerError)
		return
	}

	vulns := make([]vulnerabilityResponse, 0, len(recs))
	for _, rec := range recs {
		vulns = append(vulns, vulnerabilityResponse{
			ID:           rec.ID.String(),
			Ecosystem:    rec.Ecosystem,
			PackageName:  rec.PackageName,
			VersionRange: rec.VersionRange,
			CVEID:        rec.CVEID,
			Severity:     rec.Severity,
			CVSSScore:    rec.CVSSScore,
			Summary:      rec.Summary,
			Source:       rec.Source,
			PublishedAt:  rec.PublishedAt,
			FetchedAt:    rec.FetchedAt,

			LibraryName:      rec.PackageName,
			Description:      rec.Summary,
			AffectedVersions: rec.VersionRange,
			PublishedDate:    rec.PublishedAt,
		})
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"vulnerabilities": vulns,
		"count":           len(vulns),
		"source":          "osv.dev",
	})
}

// checkRequest is the POST /supply-chain/check body. The canonical key is
// "packages"; "libraries" is accepted for the current Flutter client, which
// still sends {libraries:[{name, version}]}.
type checkRequest struct {
	Packages  []services.PackageQuery `json:"packages"`
	Libraries []services.PackageQuery `json:"libraries"`
}

// CheckPackages handles POST /api/v1/supply-chain/check - checks the given
// packages against OSV.dev with server-side version-range matching.
func (h *SupplyChainHandler) CheckPackages(w http.ResponseWriter, r *http.Request) {
	var req checkRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.logger.Debug().Err(err).Msg("invalid request body")
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	packages := req.Packages
	if len(packages) == 0 {
		packages = req.Libraries
	}
	if len(packages) == 0 {
		http.Error(w, "At least one package is required (packages: [{name, version, ecosystem?}])", http.StatusBadRequest)
		return
	}
	if len(packages) > maxCheckPackages {
		http.Error(w, "Maximum 200 packages per request", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), checkRequestTimeout)
	defer cancel()

	results := h.service.CheckPackages(ctx, packages)

	vulnerable := 0
	failed := 0
	for _, res := range results {
		if res.Vulnerable {
			vulnerable++
		}
		if res.Error != "" {
			failed++
		}
	}

	h.logger.Info().
		Int("packages", len(results)).
		Int("vulnerable", vulnerable).
		Int("failed", failed).
		Msg("supply-chain check completed")

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"results": results,
		"checked": len(results),
	})
}

// GetTrackers handles GET /api/v1/supply-chain/trackers - returns the
// curated tracker SDK signature dataset (Exodus Privacy documented
// signatures seeded by migration 015).
func (h *SupplyChainHandler) GetTrackers(w http.ResponseWriter, r *http.Request) {
	if !h.service.HasStorage() {
		h.logger.Error().Msg("tracker dataset unavailable: database not configured")
		http.Error(w, "Tracker dataset storage unavailable", http.StatusServiceUnavailable)
		return
	}

	trackers, err := h.service.ListTrackers(r.Context())
	if err != nil {
		h.logger.Error().Err(err).Msg("failed to list known trackers")
		http.Error(w, "Failed to load tracker dataset", http.StatusInternalServerError)
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"trackers": trackers,
		"count":    len(trackers),
	})
}
