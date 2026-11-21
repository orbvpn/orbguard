package abusech

import (
	"bufio"
	"container/heap"
	"context"
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"sync"
	"time"

	"orbguard-lab/internal/sources"
	"orbguard-lab/pkg/logger"
)

// abuse.ch serves its file exports at
//
//	https://<platform>-api.abuse.ch/v2/files/exports/<Auth-Key>/recent.csv
//
// The key is part of the path, so the request address is a secret. Everything
// in this file is written so that address never leaves fetch: redirects are
// not followed, transport errors are replaced by fixed text, and response
// bodies are never copied into an error or a log line.
const (
	exportRequestTimeout = 3 * time.Minute
	exportMaxScannedRows = 1_000_000
	exportMaxBadPercent  = 5
	exportRefusedHold    = 24 * time.Hour
	exportStoreRetry     = 5 * time.Minute
	exportStoreTimeout   = 3 * time.Second
	exportCommentMax     = 64 * 1024
	exportDateLayout     = "2006-01-02 15:04:05"
	exportGateKeyPrefix  = "abusech:export-gate:"
)

var (
	errExportEmpty      = errors.New("export held no data rows")
	errExportLayout     = errors.New("export header missing or columns changed")
	errExportZipped     = errors.New("export arrived as a zip archive")
	errExportMalformed  = errors.New("too many unreadable rows in export")
	errExportNoEligible = errors.New("no usable rows in export")
	errExportTooLarge   = errors.New("export exceeds the size limit")
	errExportKeyRefused = errors.New("export body reports a refused key")
)

// exportTransportError is a network failure with the request address removed.
// Its text is fixed; only a context sentinel is kept as the cause.
type exportTransportError struct {
	msg   string
	cause error
}

func (e *exportTransportError) Error() string { return e.msg }
func (e *exportTransportError) Unwrap() error { return e.cause }

// exportBodyError marks a failure reading the response body, as opposed to a
// body that was read and judged invalid.
type exportBodyError struct{ err error }

func (e *exportBodyError) Error() string { return "export body read failed" }

// rowVerdict is what a feed decides about one well-formed row.
type rowVerdict int

const (
	rowUse  rowVerdict = iota
	rowSkip            // valid, but this feed does not ingest it
	rowBad             // does not hold what the column layout promises
)

// exportRow is one data row of an export.
type exportRow struct {
	when   time.Time
	record []string
	index  map[string]int
}

func (r exportRow) get(column string) string {
	return strings.TrimSpace(r.record[r.index[column]])
}

// exportSpec describes one feed's export.
type exportSpec struct {
	provider    string
	slug        string
	base        string
	columns     []string
	dateColumn  string
	maxBytes    int64
	maxRows     int
	minInterval time.Duration
	check       func(exportRow) rowVerdict
}

// exportParse is the outcome of reading one export.
type exportParse struct {
	rows    []exportRow // newest first, at most spec.maxRows
	read    int
	skipped int
	bad     int
	capped  bool
}

// FetchGateStore is the shared store that paces export downloads across
// replicas. *cache.RedisCache implements it.
type FetchGateStore interface {
	SetNX(ctx context.Context, key, value string, ttl time.Duration) (bool, error)
	Set(ctx context.Context, key, value string, ttl time.Duration) error
	TTL(ctx context.Context, key string) (time.Duration, error)
}

type fetchGateUser interface {
	setFetchGateStore(FetchGateStore)
}

// ShareFetchGate makes the export connectors among conns pace themselves
// through store, so all replicas together stay inside the provider's limits.
func ShareFetchGate(conns []sources.Connector, store FetchGateStore) {
	for _, conn := range conns {
		if user, ok := conn.(fetchGateUser); ok {
			user.setFetchGateStore(store)
		}
	}
}

// exportGate allows one download per pacing window: per process on its own,
// across replicas when a shared store is set. With a store that does not
// answer it allows nothing, so a store outage cannot turn into a burst.
type exportGate struct {
	mu        sync.Mutex
	notBefore time.Time
	store     FetchGateStore
	key       string
	logger    *logger.Logger
}

// reserve claims the window. It returns zero when the caller may download,
// otherwise how long to wait.
func (g *exportGate) reserve(ctx context.Context, pace time.Duration) time.Duration {
	g.mu.Lock()
	defer g.mu.Unlock()

	now := time.Now()
	if wait := g.notBefore.Sub(now); wait > 0 {
		return wait
	}
	if g.store != nil {
		claimed, err := g.store.SetNX(ctx, g.key, "1", pace)
		if err != nil {
			g.logger.Warn().Msg("shared export gate unavailable, skipping this fetch")
			g.notBefore = now.Add(exportStoreRetry)
			return exportStoreRetry
		}
		if !claimed {
			wait, err := g.store.TTL(ctx, g.key)
			if err != nil || wait <= 0 {
				wait = exportStoreRetry
			}
			g.notBefore = now.Add(wait)
			return wait
		}
	}
	g.notBefore = now.Add(pace)
	return 0
}

// hold extends the closed window to at least d, here and in the shared store.
func (g *exportGate) hold(ctx context.Context, d time.Duration) {
	g.mu.Lock()
	defer g.mu.Unlock()

	now := time.Now()
	if g.notBefore.Sub(now) >= d {
		return
	}
	g.notBefore = now.Add(d)
	if g.store != nil {
		storeCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), exportStoreTimeout)
		defer cancel()
		if err := g.store.Set(storeCtx, g.key, "1", d); err != nil {
			g.logger.Warn().Msg("could not extend the shared export gate")
		}
	}
}

// exportFeed downloads and validates one abuse.ch export.
type exportFeed struct {
	spec   exportSpec
	apiKey string
	client *http.Client
	gate   *exportGate
}

func newExportFeed(spec exportSpec, log *logger.Logger) *exportFeed {
	return &exportFeed{
		spec: spec,
		client: &http.Client{
			Timeout: exportRequestTimeout,
			// A redirect would carry the key-bearing address to another
			// location and repeat it in the error text. Never follow one.
			CheckRedirect: func(*http.Request, []*http.Request) error {
				return http.ErrUseLastResponse
			},
		},
		gate: &exportGate{key: exportGateKeyPrefix + spec.slug, logger: log},
	}
}

func (f *exportFeed) setFetchGateStore(store FetchGateStore) {
	f.gate.mu.Lock()
	defer f.gate.mu.Unlock()
	f.gate.store = store
}

// exportURL builds the key-bearing address. Callers must not log or wrap it.
func (f *exportFeed) exportURL() (string, error) {
	base, err := url.Parse(f.spec.base)
	if err != nil {
		return "", errors.New("export base address is invalid")
	}
	const prefix, suffix = "/v2/files/exports/", "/recent.csv"
	base.Path = prefix + f.apiKey + suffix
	base.RawPath = prefix + url.PathEscape(f.apiKey) + suffix
	return base.String(), nil
}

// fetch downloads and validates the export, at most once per pacing window.
func (f *exportFeed) fetch(ctx context.Context, configured time.Duration) (*exportParse, error) {
	provider := f.spec.provider
	if f.apiKey == "" {
		return nil, &sources.PlanLimitError{
			Provider: provider,
			Message:  "no abuse.ch Auth-Key configured, export not requested",
		}
	}

	pace := max(configured, f.spec.minInterval)
	if wait := f.gate.reserve(ctx, pace); wait > 0 {
		return nil, &sources.FetchDeferredError{Provider: provider, Wait: wait}
	}

	address, err := f.exportURL()
	if err != nil {
		return nil, fmt.Errorf("%s: %w", provider, err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, address, nil)
	if err != nil {
		return nil, fmt.Errorf("%s export request could not be built", provider)
	}

	resp, err := f.client.Do(req)
	if err != nil {
		return nil, redactTransportError(provider, err)
	}
	defer resp.Body.Close()

	if err := f.checkStatus(ctx, resp, pace); err != nil {
		return nil, err
	}

	limited := &io.LimitedReader{R: resp.Body, N: f.spec.maxBytes + 1}
	parsed, parseErr := parseExport(limited, f.spec)
	if limited.N <= 0 {
		return nil, fmt.Errorf("%s: %w", provider, errExportTooLarge)
	}
	if parseErr != nil {
		var bodyErr *exportBodyError
		if errors.As(parseErr, &bodyErr) {
			return nil, redactTransportError(provider, bodyErr.err)
		}
		if errors.Is(parseErr, errExportKeyRefused) {
			f.gate.hold(ctx, exportRefusedHold)
			return nil, &sources.PlanLimitError{
				Provider: provider,
				Message:  "provider refused the abuse.ch Auth-Key (reported in the response body)",
			}
		}
		return nil, fmt.Errorf("%s: %w", provider, parseErr)
	}
	return parsed, nil
}

// checkStatus maps a non-200 response to an error carrying only the status
// code, and closes the gate for as long as retrying would be pointless.
func (f *exportFeed) checkStatus(ctx context.Context, resp *http.Response, pace time.Duration) error {
	provider := f.spec.provider
	code := resp.StatusCode
	switch {
	case code == http.StatusOK:
		return nil
	case code == http.StatusUnauthorized || code == http.StatusForbidden:
		f.gate.hold(ctx, exportRefusedHold)
		return &sources.PlanLimitError{
			Provider: provider,
			Message: fmt.Sprintf("provider refused the abuse.ch Auth-Key (HTTP %d), next attempt in %s",
				code, exportRefusedHold),
		}
	case code == http.StatusTooManyRequests:
		// The body is deliberately not passed on: it could echo the address.
		wait := max(sources.ParseRetryAfter(resp, nil, pace), pace)
		f.gate.hold(ctx, wait)
		return &sources.RateLimitError{Provider: provider, Wait: wait}
	case code == http.StatusNotFound || code == http.StatusGone || (code >= 300 && code < 400):
		f.gate.hold(ctx, exportRefusedHold)
		return fmt.Errorf("%s export address not served (HTTP %d), next attempt in %s",
			provider, code, exportRefusedHold)
	default:
		return fmt.Errorf("%s export returned HTTP %d", provider, code)
	}
}

// redactTransportError replaces a client error, whose text repeats the
// request address, with fixed text for its category.
func redactTransportError(provider string, err error) error {
	var netErr net.Error
	switch {
	case errors.Is(err, context.Canceled):
		return &exportTransportError{msg: provider + " export request canceled", cause: context.Canceled}
	case errors.Is(err, context.DeadlineExceeded), errors.As(err, &netErr) && netErr.Timeout():
		return &exportTransportError{msg: provider + " export request timed out", cause: context.DeadlineExceeded}
	default:
		return &exportTransportError{msg: provider + " export connection failed"}
	}
}

// parseExport streams the CSV, keeping only the newest spec.maxRows usable
// rows in memory.
func parseExport(r io.Reader, spec exportSpec) (*exportParse, error) {
	br := bufio.NewReaderSize(r, exportCommentMax)
	if err := sniffExport(br); err != nil {
		return nil, err
	}

	header, err := readCommentHeader(br, spec.columns)
	if err != nil {
		return nil, err
	}

	cr := csv.NewReader(br)
	cr.Comment = '#'
	cr.FieldsPerRecord = -1
	cr.LazyQuotes = true
	cr.TrimLeadingSpace = true

	var index map[string]int
	if header != nil {
		index = columnIndex(header)
	}

	out := &exportParse{}
	newest := &rowHeap{}
	for {
		rec, err := cr.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			var parseErr *csv.ParseError
			if !errors.As(err, &parseErr) {
				return nil, &exportBodyError{err: err}
			}
			if index == nil {
				return nil, errExportLayout
			}
			out.read++
			out.bad++
			continue
		}

		if index == nil {
			cols := normalizeColumns(rec)
			if !hasColumns(cols, spec.columns) {
				return nil, errExportLayout
			}
			header, index = cols, columnIndex(cols)
			continue
		}
		if len(rec) > 0 && normalizeColumn(rec[0]) == header[0] {
			continue // the header repeated as a plain row
		}

		out.read++
		if out.read > exportMaxScannedRows {
			return nil, errExportTooLarge
		}
		if len(rec) != len(header) {
			out.bad++
			continue
		}

		row := exportRow{record: rec, index: index}
		when, err := time.Parse(exportDateLayout, row.get(spec.dateColumn))
		if err != nil {
			out.bad++
			continue
		}
		row.when = when

		switch spec.check(row) {
		case rowBad:
			out.bad++
		case rowSkip:
			out.skipped++
		default:
			if newest.Len() < spec.maxRows {
				heap.Push(newest, row)
			} else {
				out.capped = true
				if row.when.After((*newest)[0].when) {
					(*newest)[0] = row
					heap.Fix(newest, 0)
				}
			}
		}
	}

	if out.read == 0 {
		return nil, errExportEmpty
	}
	if out.bad*100 > out.read*exportMaxBadPercent {
		return nil, errExportMalformed
	}
	if newest.Len() == 0 {
		return nil, errExportNoEligible
	}

	out.rows = []exportRow(*newest)
	sort.SliceStable(out.rows, func(i, j int) bool { return out.rows[i].when.After(out.rows[j].when) })
	return out, nil
}

// sniffExport rejects bodies that are plainly not a CSV before parsing.
func sniffExport(br *bufio.Reader) error {
	head, err := br.Peek(4)
	if err != nil && err != io.EOF {
		return &exportBodyError{err: err}
	}
	if len(head) == 0 {
		return errExportEmpty
	}
	if len(head) >= 3 && head[0] == 0xEF && head[1] == 0xBB && head[2] == 0xBF {
		if _, err := br.Discard(3); err != nil {
			return &exportBodyError{err: err}
		}
		if head, err = br.Peek(4); err != nil && err != io.EOF {
			return &exportBodyError{err: err}
		}
		if len(head) == 0 {
			return errExportEmpty
		}
	}
	switch {
	case len(head) == 4 && string(head) == "PK\x03\x04":
		return errExportZipped
	case head[0] == '<':
		return errExportLayout
	case head[0] == '{':
		var probe struct {
			QueryStatus string `json:"query_status"`
		}
		if json.NewDecoder(io.LimitReader(br, 4096)).Decode(&probe) == nil {
			status := strings.ToLower(probe.QueryStatus)
			if strings.Contains(status, "auth") || strings.Contains(status, "key") {
				return errExportKeyRefused
			}
		}
		return errExportLayout
	}
	return nil
}

// readCommentHeader consumes the leading comment and blank lines and returns
// the column names if one of the comments is the header.
func readCommentHeader(br *bufio.Reader, required []string) ([]string, error) {
	var header []string
	for {
		next, err := br.Peek(1)
		if err == io.EOF {
			return header, nil
		}
		if err != nil {
			return nil, &exportBodyError{err: err}
		}
		switch next[0] {
		case '\n', '\r':
			if _, err := br.Discard(1); err != nil {
				return nil, &exportBodyError{err: err}
			}
		case '#':
			line, err := br.ReadSlice('\n')
			if err == bufio.ErrBufferFull {
				return nil, errExportLayout
			}
			if err != nil && err != io.EOF {
				return nil, &exportBodyError{err: err}
			}
			if cols := parseHeaderLine(string(line), required); cols != nil {
				header = cols
			}
		default:
			return header, nil
		}
	}
}

func parseHeaderLine(line string, required []string) []string {
	cr := csv.NewReader(strings.NewReader(strings.TrimLeft(strings.TrimSpace(line), "# \t")))
	cr.LazyQuotes = true
	cr.TrimLeadingSpace = true
	rec, err := cr.Read()
	if err != nil {
		return nil
	}
	cols := normalizeColumns(rec)
	if !hasColumns(cols, required) {
		return nil
	}
	return cols
}

func normalizeColumn(name string) string {
	return strings.ToLower(strings.Trim(strings.TrimSpace(name), `"`))
}

func normalizeColumns(rec []string) []string {
	cols := make([]string, len(rec))
	for i, name := range rec {
		cols[i] = normalizeColumn(name)
	}
	return cols
}

func hasColumns(cols, required []string) bool {
	present := make(map[string]bool, len(cols))
	for _, c := range cols {
		present[c] = true
	}
	for _, c := range required {
		if !present[c] {
			return false
		}
	}
	return true
}

func columnIndex(cols []string) map[string]int {
	index := make(map[string]int, len(cols))
	for i, c := range cols {
		index[c] = i
	}
	return index
}

// withTag returns a copy of tags plus tag, so sibling indicators built from
// one row never share a backing array.
func withTag(tags []string, tag string) []string {
	out := make([]string, 0, len(tags)+1)
	out = append(out, tags...)
	return append(out, tag)
}

// rowHeap is a min-heap on row time: its root is the oldest row kept.
type rowHeap []exportRow

func (h rowHeap) Len() int           { return len(h) }
func (h rowHeap) Less(i, j int) bool { return h[i].when.Before(h[j].when) }
func (h rowHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *rowHeap) Push(x any)        { *h = append(*h, x.(exportRow)) }
func (h *rowHeap) Pop() any {
	old := *h
	last := len(old) - 1
	row := old[last]
	*h = old[:last]
	return row
}
