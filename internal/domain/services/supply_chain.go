package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// defaultOSVBaseURL is the public OSV.dev API endpoint.
const defaultOSVBaseURL = "https://api.osv.dev"

// osvCacheTTL is how long a successful per-package OSV lookup stays fresh
// before /supply-chain/check re-queries OSV for that package.
const osvCacheTTL = 24 * time.Hour

// ============================================================
// OSV API client
// ============================================================

// OSVClient is a client for the OSV.dev vulnerability API.
type OSVClient struct {
	baseURL    string
	httpClient *http.Client
	logger     *logger.Logger
}

// NewOSVClient creates an OSV.dev API client. An empty baseURL selects the
// public https://api.osv.dev endpoint.
func NewOSVClient(baseURL string, log *logger.Logger) *OSVClient {
	if baseURL == "" {
		baseURL = defaultOSVBaseURL
	}
	return &OSVClient{
		baseURL: strings.TrimRight(baseURL, "/"),
		httpClient: &http.Client{
			Timeout: 15 * time.Second,
		},
		logger: log.WithComponent("osv-client"),
	}
}

// OSVSeverity is one severity entry on an OSV record (CVSS vector string).
type OSVSeverity struct {
	Type  string `json:"type"`
	Score string `json:"score"`
}

// OSVEvent is one version event inside an OSV affected range.
type OSVEvent struct {
	Introduced   string `json:"introduced,omitempty"`
	Fixed        string `json:"fixed,omitempty"`
	LastAffected string `json:"last_affected,omitempty"`
	Limit        string `json:"limit,omitempty"`
}

// OSVRange is one affected version range.
type OSVRange struct {
	Type   string     `json:"type"`
	Events []OSVEvent `json:"events"`
}

// OSVPackage identifies a package inside an OSV record.
type OSVPackage struct {
	Ecosystem string `json:"ecosystem"`
	Name      string `json:"name"`
	Purl      string `json:"purl,omitempty"`
}

// OSVAffected is one affected-package entry on an OSV record.
type OSVAffected struct {
	Package          OSVPackage      `json:"package"`
	Ranges           []OSVRange      `json:"ranges,omitempty"`
	Versions         []string        `json:"versions,omitempty"`
	DatabaseSpecific json.RawMessage `json:"database_specific,omitempty"`
}

// OSVVulnerability is a (subset of an) OSV.dev vulnerability record.
type OSVVulnerability struct {
	ID               string          `json:"id"`
	Summary          string          `json:"summary"`
	Details          string          `json:"details"`
	Aliases          []string        `json:"aliases"`
	Published        time.Time       `json:"published"`
	Modified         time.Time       `json:"modified"`
	Severity         []OSVSeverity   `json:"severity"`
	Affected         []OSVAffected   `json:"affected"`
	DatabaseSpecific json.RawMessage `json:"database_specific,omitempty"`
}

type osvQueryRequest struct {
	Package   OSVPackage `json:"package"`
	PageToken string     `json:"page_token,omitempty"`
}

type osvQueryResponse struct {
	Vulns         []OSVVulnerability `json:"vulns"`
	NextPageToken string             `json:"next_page_token"`
}

type osvBatchVulnRef struct {
	ID       string `json:"id"`
	Modified string `json:"modified"`
}

type osvBatchResult struct {
	Vulns         []osvBatchVulnRef `json:"vulns"`
	NextPageToken string            `json:"next_page_token"`
}

type osvBatchResponse struct {
	Results []osvBatchResult `json:"results"`
}

// post sends a JSON POST to the OSV API and decodes the response into out.
func (c *OSVClient) post(ctx context.Context, path string, body, out interface{}) error {
	payload, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("osv: marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+path, bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("osv: build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("osv: %s: %w", path, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		snippet, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return fmt.Errorf("osv: %s returned status %d: %s", path, resp.StatusCode, strings.TrimSpace(string(snippet)))
	}

	if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
		return fmt.Errorf("osv: decode %s response: %w", path, err)
	}
	return nil
}

// QueryPackage returns all OSV vulnerability records affecting the package,
// following pagination.
func (c *OSVClient) QueryPackage(ctx context.Context, ecosystem, name string) ([]OSVVulnerability, error) {
	var all []OSVVulnerability
	pageToken := ""

	for {
		req := osvQueryRequest{
			Package:   OSVPackage{Ecosystem: ecosystem, Name: name},
			PageToken: pageToken,
		}
		var resp osvQueryResponse
		if err := c.post(ctx, "/v1/query", req, &resp); err != nil {
			return nil, err
		}
		all = append(all, resp.Vulns...)
		if resp.NextPageToken == "" {
			return all, nil
		}
		pageToken = resp.NextPageToken
	}
}

// QueryBatch resolves the vulnerability IDs affecting each queried package.
// The result slice is index-aligned with pkgs. A package whose result page
// is truncated (next_page_token set) is reported via the second return value
// so callers can fall back to QueryPackage for it.
func (c *OSVClient) QueryBatch(ctx context.Context, pkgs []OSVPackage) ([][]string, []bool, error) {
	queries := make([]osvQueryRequest, len(pkgs))
	for i, p := range pkgs {
		queries[i] = osvQueryRequest{Package: p}
	}

	var resp osvBatchResponse
	if err := c.post(ctx, "/v1/querybatch", struct {
		Queries []osvQueryRequest `json:"queries"`
	}{Queries: queries}, &resp); err != nil {
		return nil, nil, err
	}

	if len(resp.Results) != len(pkgs) {
		return nil, nil, fmt.Errorf("osv: querybatch returned %d results for %d queries", len(resp.Results), len(pkgs))
	}

	ids := make([][]string, len(pkgs))
	truncated := make([]bool, len(pkgs))
	for i, res := range resp.Results {
		for _, v := range res.Vulns {
			ids[i] = append(ids[i], v.ID)
		}
		truncated[i] = res.NextPageToken != ""
	}
	return ids, truncated, nil
}

// GetVulnByID fetches one full OSV record by advisory ID.
func (c *OSVClient) GetVulnByID(ctx context.Context, id string) (*OSVVulnerability, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		c.baseURL+"/v1/vulns/"+url.PathEscape(id), nil)
	if err != nil {
		return nil, fmt.Errorf("osv: build request: %w", err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("osv: get vuln %s: %w", id, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		snippet, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return nil, fmt.Errorf("osv: get vuln %s returned status %d: %s", id, resp.StatusCode, strings.TrimSpace(string(snippet)))
	}

	var vuln OSVVulnerability
	if err := json.NewDecoder(resp.Body).Decode(&vuln); err != nil {
		return nil, fmt.Errorf("osv: decode vuln %s: %w", id, err)
	}
	return &vuln, nil
}

// ============================================================
// Supply-chain service
// ============================================================

// SupplyChainService backs the /supply-chain endpoints: OSV-sourced
// vulnerability data with database caching, server-side version-range
// matching, and the curated tracker dataset.
type SupplyChainService struct {
	repo   *repository.SupplyChainRepository
	osv    *OSVClient
	logger *logger.Logger
}

// NewSupplyChainService creates the supply-chain service. osvBaseURL may be
// empty to use the public OSV.dev endpoint. The service still performs live
// OSV checks when the repository is unavailable; only caching is skipped.
func NewSupplyChainService(repos *repository.Repositories, log *logger.Logger, osvBaseURL string) *SupplyChainService {
	return &SupplyChainService{
		repo:   repository.NewSupplyChainRepositoryFromRepos(repos),
		osv:    NewOSVClient(osvBaseURL, log),
		logger: log.WithComponent("supply-chain-service"),
	}
}

// HasStorage reports whether the database-backed cache is available.
func (s *SupplyChainService) HasStorage() bool {
	return s.repo != nil
}

// PackageQuery is one package to check.
type PackageQuery struct {
	Name      string `json:"name"`
	Version   string `json:"version"`
	Ecosystem string `json:"ecosystem,omitempty"`
}

// VulnSummary is one matched vulnerability in a check result.
type VulnSummary struct {
	CVEID     string  `json:"cve_id"`
	Severity  string  `json:"severity"`
	Summary   string  `json:"summary"`
	CVSSScore float64 `json:"cvss_score,omitempty"`
}

// PackageCheckResult is the outcome for one checked package.
type PackageCheckResult struct {
	Package    string        `json:"package"`
	Version    string        `json:"version"`
	Ecosystem  string        `json:"ecosystem"`
	Vulnerable bool          `json:"vulnerable"`
	Vulns      []VulnSummary `json:"vulns"`
	Error      string        `json:"error,omitempty"`
}

// storedAffected is the JSON shape persisted in supply_chain_vulns.version_range.
type storedAffected struct {
	Ranges   []OSVRange `json:"ranges,omitempty"`
	Versions []string   `json:"versions,omitempty"`
}

// DefaultEcosystem resolves the OSV ecosystem for a package when the caller
// did not specify one. Android app dependencies are Java/Kotlin artifacts,
// so reverse-DNS and group:artifact names default to Maven; npm-style
// scoped/slashed names map to npm.
func DefaultEcosystem(name string) string {
	if strings.HasPrefix(name, "@") || strings.Contains(name, "/") {
		return "npm"
	}
	return "Maven"
}

// ListVulnerabilities returns cached advisories from the database.
func (s *SupplyChainService) ListVulnerabilities(ctx context.Context, ecosystem, packageName string, limit int) ([]repository.SupplyChainVulnRecord, error) {
	if s.repo == nil {
		return nil, fmt.Errorf("supply-chain vulnerability storage unavailable: database not configured")
	}
	return s.repo.ListVulns(ctx, ecosystem, packageName, limit)
}

// ListTrackers returns the curated tracker-signature dataset.
func (s *SupplyChainService) ListTrackers(ctx context.Context) ([]repository.KnownTracker, error) {
	if s.repo == nil {
		return nil, fmt.Errorf("tracker dataset unavailable: database not configured")
	}
	return s.repo.ListTrackers(ctx)
}

// CheckPackages checks each package against OSV data with server-side
// version-range matching. Fresh database-cached results are used when
// available; everything else is queried live against OSV with per-package
// failure isolation (one package's lookup failure never fails the others).
func (s *SupplyChainService) CheckPackages(ctx context.Context, pkgs []PackageQuery) []PackageCheckResult {
	results := make([]PackageCheckResult, len(pkgs))
	var liveIdx []int

	for i, p := range pkgs {
		eco := strings.TrimSpace(p.Ecosystem)
		if eco == "" {
			eco = DefaultEcosystem(p.Name)
		}
		results[i] = PackageCheckResult{
			Package:   strings.TrimSpace(p.Name),
			Version:   strings.TrimSpace(p.Version),
			Ecosystem: eco,
			Vulns:     []VulnSummary{},
		}

		if results[i].Package == "" {
			results[i].Error = "package name is required"
			continue
		}
		if results[i].Version == "" {
			results[i].Error = "package version is required for vulnerability range matching"
			continue
		}

		if s.checkFromCache(ctx, &results[i]) {
			continue
		}
		liveIdx = append(liveIdx, i)
	}

	if len(liveIdx) > 0 {
		s.checkLive(ctx, results, liveIdx)
	}
	return results
}

// checkFromCache fills the result from the database cache when the package
// lookup is still fresh. Returns false when a live OSV query is needed.
func (s *SupplyChainService) checkFromCache(ctx context.Context, res *PackageCheckResult) bool {
	if s.repo == nil {
		return false
	}

	checkedAt, err := s.repo.GetPackageLastChecked(ctx, res.Ecosystem, res.Package)
	if err != nil {
		s.logger.Error().Err(err).Str("package", res.Package).Msg("failed to read package check freshness")
		return false
	}
	if checkedAt == nil || time.Since(*checkedAt) > osvCacheTTL {
		return false
	}

	recs, err := s.repo.GetVulnsForPackage(ctx, res.Ecosystem, res.Package)
	if err != nil {
		s.logger.Error().Err(err).Str("package", res.Package).Msg("failed to read cached vulnerabilities")
		return false
	}

	for _, rec := range recs {
		var affected storedAffected
		if err := json.Unmarshal([]byte(rec.VersionRange), &affected); err != nil {
			s.logger.Warn().Err(err).Str("cve_id", rec.CVEID).Str("package", res.Package).
				Msg("cached version_range is not valid JSON; skipping record")
			continue
		}
		if versionMatchesAffected(res.Version, affected.Ranges, affected.Versions) {
			res.Vulns = append(res.Vulns, VulnSummary{
				CVEID:     rec.CVEID,
				Severity:  rec.Severity,
				Summary:   rec.Summary,
				CVSSScore: rec.CVSSScore,
			})
		}
	}
	res.Vulnerable = len(res.Vulns) > 0
	return true
}

// checkLive queries OSV for the packages at liveIdx via querybatch + per-ID
// detail fetches, matches versions, persists findings and marks freshness.
func (s *SupplyChainService) checkLive(ctx context.Context, results []PackageCheckResult, liveIdx []int) {
	osvPkgs := make([]OSVPackage, len(liveIdx))
	for n, i := range liveIdx {
		osvPkgs[n] = OSVPackage{Ecosystem: results[i].Ecosystem, Name: results[i].Package}
	}

	idsPerPkg, truncated, err := s.osv.QueryBatch(ctx, osvPkgs)
	if err != nil {
		// Batch endpoint failed entirely: fall back to isolated per-package
		// full queries so one outage path does not take everything down.
		s.logger.Warn().Err(err).Int("packages", len(liveIdx)).
			Msg("OSV querybatch failed; falling back to per-package queries")
		for _, i := range liveIdx {
			s.checkSinglePackageLive(ctx, &results[i])
		}
		return
	}

	// Packages with truncated batch pages (>~1000 vulns) need full queries.
	var batchResolved []int // indices into results
	for n, i := range liveIdx {
		if truncated[n] {
			s.checkSinglePackageLive(ctx, &results[i])
		} else {
			batchResolved = append(batchResolved, i)
		}
	}

	// Fetch unique vulnerability details concurrently (bounded).
	idsByResult := make(map[int][]string, len(batchResolved))
	unique := map[string]bool{}
	for n, i := range liveIdx {
		if truncated[n] {
			continue
		}
		idsByResult[i] = idsPerPkg[n]
		for _, id := range idsPerPkg[n] {
			unique[id] = true
		}
	}
	details, fetchErrs := s.fetchVulnDetails(ctx, unique)

	now := time.Now().UTC()
	var records []repository.SupplyChainVulnRecord
	var freshPkgs []repository.PackageRef

	for _, i := range batchResolved {
		res := &results[i]
		complete := true

		for _, id := range idsByResult[i] {
			vuln, ok := details[id]
			if !ok {
				complete = false
				continue
			}
			recs := s.applyVuln(res, vuln)
			records = append(records, recs...)
		}

		res.Vulnerable = len(res.Vulns) > 0

		if complete {
			freshPkgs = append(freshPkgs, repository.PackageRef{
				Ecosystem: res.Ecosystem, PackageName: res.Package,
			})
		} else if len(res.Vulns) == 0 {
			// Nothing usable was determined for this package.
			res.Error = "failed to retrieve vulnerability details from OSV"
		}
	}

	for id, ferr := range fetchErrs {
		s.logger.Error().Err(ferr).Str("vuln_id", id).Msg("failed to fetch OSV vulnerability detail")
	}

	s.persist(ctx, records, freshPkgs, now)
}

// checkSinglePackageLive resolves one package via the full /v1/query path.
func (s *SupplyChainService) checkSinglePackageLive(ctx context.Context, res *PackageCheckResult) {
	vulns, err := s.osv.QueryPackage(ctx, res.Ecosystem, res.Package)
	if err != nil {
		s.logger.Error().Err(err).Str("package", res.Package).Str("ecosystem", res.Ecosystem).
			Msg("OSV package query failed")
		res.Error = fmt.Sprintf("OSV lookup failed: %v", err)
		return
	}

	now := time.Now().UTC()
	var records []repository.SupplyChainVulnRecord
	for i := range vulns {
		records = append(records, s.applyVuln(res, &vulns[i])...)
	}
	res.Vulnerable = len(res.Vulns) > 0

	s.persist(ctx, records, []repository.PackageRef{{
		Ecosystem: res.Ecosystem, PackageName: res.Package,
	}}, now)
}

// fetchVulnDetails retrieves full OSV records for the given advisory IDs
// with bounded concurrency. Failures are isolated per advisory.
func (s *SupplyChainService) fetchVulnDetails(ctx context.Context, ids map[string]bool) (map[string]*OSVVulnerability, map[string]error) {
	details := make(map[string]*OSVVulnerability, len(ids))
	errs := map[string]error{}

	var mu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, 4)

	for id := range ids {
		wg.Add(1)
		go func(id string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			vuln, err := s.osv.GetVulnByID(ctx, id)
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				errs[id] = err
				return
			}
			details[id] = vuln
		}(id)
	}
	wg.Wait()
	return details, errs
}

// applyVuln matches one OSV record against the result's package/version,
// appending a VulnSummary when the version is affected, and returns the
// persistence records for the (vuln, package) pair.
func (s *SupplyChainService) applyVuln(res *PackageCheckResult, vuln *OSVVulnerability) []repository.SupplyChainVulnRecord {
	affected := collectAffected(vuln, res.Ecosystem, res.Package)
	if len(affected.Ranges) == 0 && len(affected.Versions) == 0 {
		return nil
	}

	severity, score := s.severityOf(vuln)
	summary := vuln.Summary
	if summary == "" {
		summary = firstLine(vuln.Details)
	}

	if versionMatchesAffected(res.Version, affected.Ranges, affected.Versions) {
		res.Vulns = append(res.Vulns, VulnSummary{
			CVEID:     bestVulnID(vuln),
			Severity:  severity,
			Summary:   summary,
			CVSSScore: score,
		})
	}

	rangeJSON, err := json.Marshal(affected)
	if err != nil {
		s.logger.Error().Err(err).Str("vuln_id", vuln.ID).Msg("failed to marshal affected ranges")
		rangeJSON = []byte("{}")
	}

	var publishedAt *time.Time
	if !vuln.Published.IsZero() {
		p := vuln.Published
		publishedAt = &p
	}

	return []repository.SupplyChainVulnRecord{{
		Ecosystem:    res.Ecosystem,
		PackageName:  res.Package,
		VersionRange: string(rangeJSON),
		CVEID:        bestVulnID(vuln),
		Severity:     severity,
		CVSSScore:    score,
		Summary:      summary,
		Source:       "osv.dev",
		PublishedAt:  publishedAt,
	}}
}

// persist caches findings and freshness markers; failures are logged but do
// not fail the check (the live results are still valid for the caller).
func (s *SupplyChainService) persist(ctx context.Context, records []repository.SupplyChainVulnRecord, fresh []repository.PackageRef, checkedAt time.Time) {
	if s.repo == nil {
		if len(records) > 0 || len(fresh) > 0 {
			s.logger.Warn().Msg("supply-chain persistence skipped: database not configured")
		}
		return
	}
	if err := s.repo.UpsertVulns(ctx, records); err != nil {
		s.logger.Error().Err(err).Int("count", len(records)).Msg("failed to persist supply-chain vulnerabilities")
		return
	}
	if err := s.repo.MarkPackagesChecked(ctx, fresh, checkedAt); err != nil {
		s.logger.Error().Err(err).Int("count", len(fresh)).Msg("failed to mark packages checked")
	}
}

// collectAffected merges all affected entries on the record that target the
// given package into one storedAffected.
func collectAffected(vuln *OSVVulnerability, ecosystem, name string) storedAffected {
	var out storedAffected
	for _, aff := range vuln.Affected {
		if !strings.EqualFold(aff.Package.Name, name) {
			continue
		}
		// Ecosystem values may carry a suffix (e.g. "Debian:11"); compare
		// the base ecosystem.
		affEco := aff.Package.Ecosystem
		if idx := strings.Index(affEco, ":"); idx >= 0 {
			affEco = affEco[:idx]
		}
		if !strings.EqualFold(affEco, ecosystem) {
			continue
		}
		out.Ranges = append(out.Ranges, aff.Ranges...)
		out.Versions = append(out.Versions, aff.Versions...)
	}
	return out
}

// bestVulnID prefers a CVE alias, falling back to the OSV advisory ID.
func bestVulnID(vuln *OSVVulnerability) string {
	for _, alias := range vuln.Aliases {
		if strings.HasPrefix(alias, "CVE-") {
			return alias
		}
	}
	return vuln.ID
}

// severityOf derives a severity label and CVSS base score for the record:
// computed from the CVSS v3/v2 vector when present, otherwise taken from
// the database_specific severity label.
func (s *SupplyChainService) severityOf(vuln *OSVVulnerability) (string, float64) {
	for _, sev := range vuln.Severity {
		switch sev.Type {
		case "CVSS_V3":
			if score, ok := cvss3BaseScore(sev.Score); ok {
				return severityFromScore(score), score
			}
		case "CVSS_V2":
			if score, ok := cvss2BaseScore(sev.Score); ok {
				return severityFromScore(score), score
			}
		}
	}

	// CVSS v4 vectors (and malformed vectors) fall through to the advisory
	// database's own severity label.
	var dbSpecific struct {
		Severity string `json:"severity"`
	}
	if len(vuln.DatabaseSpecific) > 0 {
		if err := json.Unmarshal(vuln.DatabaseSpecific, &dbSpecific); err == nil && dbSpecific.Severity != "" {
			return normalizeSeverityLabel(dbSpecific.Severity), 0
		}
	}
	return "unknown", 0
}

func normalizeSeverityLabel(label string) string {
	switch strings.ToUpper(strings.TrimSpace(label)) {
	case "CRITICAL":
		return "critical"
	case "HIGH":
		return "high"
	case "MODERATE", "MEDIUM":
		return "medium"
	case "LOW":
		return "low"
	default:
		return strings.ToLower(strings.TrimSpace(label))
	}
}

func severityFromScore(score float64) string {
	switch {
	case score >= 9.0:
		return "critical"
	case score >= 7.0:
		return "high"
	case score >= 4.0:
		return "medium"
	case score > 0:
		return "low"
	default:
		return "unknown"
	}
}

// firstLine returns the first non-empty line of s, trimmed.
func firstLine(s string) string {
	for _, line := range strings.Split(s, "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			return line
		}
	}
	return ""
}

// ============================================================
// Version-range matching (OSV events-based ranges)
// ============================================================

// versionMatchesAffected reports whether version falls inside any OSV
// affected range or explicit version list. GIT (commit-hash) ranges cannot
// be compared against release versions and are skipped.
func versionMatchesAffected(version string, ranges []OSVRange, versions []string) bool {
	for _, v := range versions {
		if compareOSVVersions(version, v) == 0 {
			return true
		}
	}
	for _, r := range ranges {
		switch strings.ToUpper(r.Type) {
		case "SEMVER", "ECOSYSTEM":
			if versionInEvents(version, r.Events) {
				return true
			}
		}
	}
	return false
}

// versionInEvents walks an OSV event sequence (introduced/fixed/
// last_affected/limit pairs) and reports whether the version falls inside
// any affected interval.
func versionInEvents(version string, events []OSVEvent) bool {
	var introduced string
	haveIntroduced := false

	afterIntroduced := func() bool {
		if introduced == "0" || introduced == "" {
			return true
		}
		return compareOSVVersions(version, introduced) >= 0
	}

	for _, e := range events {
		switch {
		case e.Introduced != "":
			introduced = e.Introduced
			haveIntroduced = true
		case e.Fixed != "":
			if haveIntroduced && afterIntroduced() && compareOSVVersions(version, e.Fixed) < 0 {
				return true
			}
			haveIntroduced = false
		case e.LastAffected != "":
			if haveIntroduced && afterIntroduced() && compareOSVVersions(version, e.LastAffected) <= 0 {
				return true
			}
			haveIntroduced = false
		case e.Limit != "":
			if haveIntroduced && afterIntroduced() && compareOSVVersions(version, e.Limit) < 0 {
				return true
			}
			haveIntroduced = false
		}
	}

	// An interval opened by "introduced" with no closing event affects all
	// later versions.
	return haveIntroduced && afterIntroduced()
}

// compareOSVVersions compares two version strings, returning -1, 0 or 1. It
// implements semver-style ordering generalised to the common syntaxes OSV
// emits for Maven/npm/PyPI artifacts: dot-separated numeric/alphanumeric
// release segments, a pre-release part after the first '-' (which sorts
// before the plain release), and ignored '+' build metadata.
func compareOSVVersions(a, b string) int {
	aMain, aPre := splitVersion(a)
	bMain, bPre := splitVersion(b)

	if c := compareDottedSegments(aMain, bMain, true); c != 0 {
		return c
	}

	// Same release: no pre-release > pre-release ("1.0.0" > "1.0.0-rc1").
	switch {
	case aPre == "" && bPre == "":
		return 0
	case aPre == "":
		return 1
	case bPre == "":
		return -1
	}
	return compareDottedSegments(aPre, bPre, false)
}

// splitVersion normalises a version string into (release, prerelease),
// stripping a leading 'v' and any '+' build metadata.
func splitVersion(v string) (string, string) {
	v = strings.TrimSpace(v)
	if len(v) > 1 && (v[0] == 'v' || v[0] == 'V') {
		v = v[1:]
	}
	if idx := strings.IndexByte(v, '+'); idx >= 0 {
		v = v[:idx]
	}
	if idx := strings.IndexByte(v, '-'); idx >= 0 {
		return v[:idx], v[idx+1:]
	}
	return v, ""
}

// compareDottedSegments compares dot-separated identifier lists. Numeric
// identifiers compare numerically and sort before alphanumeric identifiers
// (per semver pre-release rules). When padMissing is true, missing release
// segments compare as "0" (so "1.2" == "1.2.0"); for pre-release parts the
// shorter list sorts first ("1.0-rc" < "1.0-rc.1").
func compareDottedSegments(a, b string, padMissing bool) int {
	as := strings.Split(a, ".")
	bs := strings.Split(b, ".")

	n := len(as)
	if len(bs) > n {
		n = len(bs)
	}

	for i := 0; i < n; i++ {
		var sa, sb string
		aMissing := i >= len(as)
		bMissing := i >= len(bs)

		if aMissing || bMissing {
			if !padMissing {
				if aMissing && bMissing {
					return 0
				}
				if aMissing {
					return -1
				}
				return 1
			}
			sa, sb = "0", "0"
			if !aMissing {
				sa = as[i]
			}
			if !bMissing {
				sb = bs[i]
			}
		} else {
			sa, sb = as[i], bs[i]
		}

		if c := compareIdentifier(sa, sb); c != 0 {
			return c
		}
	}
	return 0
}

// compareIdentifier compares two single identifiers: numerics numerically,
// numerics before alphanumerics, alphanumerics lexically (case-insensitive).
func compareIdentifier(a, b string) int {
	av, aErr := strconv.ParseUint(a, 10, 64)
	bv, bErr := strconv.ParseUint(b, 10, 64)
	aIsNum := aErr == nil
	bIsNum := bErr == nil

	switch {
	case aIsNum && bIsNum:
		switch {
		case av < bv:
			return -1
		case av > bv:
			return 1
		default:
			return 0
		}
	case aIsNum:
		return -1
	case bIsNum:
		return 1
	default:
		return strings.Compare(strings.ToLower(a), strings.ToLower(b))
	}
}

// ============================================================
// CVSS base-score computation (v3.x and v2 vectors)
// ============================================================

// cvss3BaseScore computes the CVSS v3.x base score from a vector string
// (e.g. "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"), per the FIRST
// CVSS v3.1 specification.
func cvss3BaseScore(vector string) (float64, bool) {
	metrics := parseVector(vector)
	if !strings.HasPrefix(vector, "CVSS:3") {
		return 0, false
	}

	scopeChanged := metrics["S"] == "C"

	av, ok := map[string]float64{"N": 0.85, "A": 0.62, "L": 0.55, "P": 0.2}[metrics["AV"]]
	if !ok {
		return 0, false
	}
	ac, ok := map[string]float64{"L": 0.77, "H": 0.44}[metrics["AC"]]
	if !ok {
		return 0, false
	}
	var pr float64
	switch metrics["PR"] {
	case "N":
		pr = 0.85
	case "L":
		pr = 0.62
		if scopeChanged {
			pr = 0.68
		}
	case "H":
		pr = 0.27
		if scopeChanged {
			pr = 0.5
		}
	default:
		return 0, false
	}
	ui, ok := map[string]float64{"N": 0.85, "R": 0.62}[metrics["UI"]]
	if !ok {
		return 0, false
	}

	cia := map[string]float64{"H": 0.56, "L": 0.22, "N": 0}
	c, okC := cia[metrics["C"]]
	i, okI := cia[metrics["I"]]
	a, okA := cia[metrics["A"]]
	if !okC || !okI || !okA {
		return 0, false
	}

	iss := 1 - (1-c)*(1-i)*(1-a)
	var impact float64
	if scopeChanged {
		impact = 7.52*(iss-0.029) - 3.25*math.Pow(iss-0.02, 15)
	} else {
		impact = 6.42 * iss
	}
	exploitability := 8.22 * av * ac * pr * ui

	if impact <= 0 {
		return 0, true
	}
	var score float64
	if scopeChanged {
		score = math.Min(1.08*(impact+exploitability), 10)
	} else {
		score = math.Min(impact+exploitability, 10)
	}
	return cvssRoundup(score), true
}

// cvss2BaseScore computes the CVSS v2 base score from a vector string
// (e.g. "AV:N/AC:L/Au:N/C:P/I:P/A:P"), per the CVSS v2 specification.
func cvss2BaseScore(vector string) (float64, bool) {
	metrics := parseVector(vector)

	av, ok := map[string]float64{"L": 0.395, "A": 0.646, "N": 1.0}[metrics["AV"]]
	if !ok {
		return 0, false
	}
	ac, ok := map[string]float64{"H": 0.35, "M": 0.61, "L": 0.71}[metrics["AC"]]
	if !ok {
		return 0, false
	}
	au, ok := map[string]float64{"M": 0.45, "S": 0.56, "N": 0.704}[metrics["Au"]]
	if !ok {
		return 0, false
	}
	cia := map[string]float64{"N": 0, "P": 0.275, "C": 0.660}
	c, okC := cia[metrics["C"]]
	i, okI := cia[metrics["I"]]
	a, okA := cia[metrics["A"]]
	if !okC || !okI || !okA {
		return 0, false
	}

	impact := 10.41 * (1 - (1-c)*(1-i)*(1-a))
	exploitability := 20 * av * ac * au
	fImpact := 1.176
	if impact == 0 {
		fImpact = 0
	}
	score := (0.6*impact + 0.4*exploitability - 1.5) * fImpact
	return math.Round(score*10) / 10, true
}

// parseVector splits a CVSS vector string into a metric→value map.
func parseVector(vector string) map[string]string {
	metrics := map[string]string{}
	for _, part := range strings.Split(vector, "/") {
		kv := strings.SplitN(part, ":", 2)
		if len(kv) == 2 {
			metrics[kv[0]] = kv[1]
		}
	}
	return metrics
}

// cvssRoundup implements the CVSS v3.1 Roundup function: round up to one
// decimal place, with the specification's floating-point-stability fix.
func cvssRoundup(x float64) float64 {
	i := int(math.Round(x * 100000))
	if i%10000 == 0 {
		return float64(i) / 100000
	}
	return (math.Floor(float64(i)/10000) + 1) / 10
}
