package abusech

import (
	"bufio"
	"bytes"
	"container/heap"
	"context"
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

	// exportRefusedSuffix names the shared key that records a refusal, so a
	// replica can tell a dead key from an ordinary pacing window.
	exportRefusedSuffix = ":refused"

	// Limits applied to a row before anything is split or stored. A compressed
	// response can expand to the full byte cap inside a single field.
	exportMaxLineBytes  = 8 << 10
	exportMaxFieldBytes = 4 << 10
	exportMaxColumns    = 64
	exportSniffBytes    = 4 << 10
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
	mu           sync.Mutex
	notBefore    time.Time
	refusedUntil time.Time
	store        FetchGateStore
	key          string
	logger       *logger.Logger
}

// reserve claims the window. It returns zero when the caller may download,
// otherwise how long to wait and whether the wait is a recorded refusal rather
// than ordinary pacing.
func (g *exportGate) reserve(ctx context.Context, pace time.Duration) (time.Duration, bool) {
	g.mu.Lock()
	defer g.mu.Unlock()

	now := time.Now()
	if left := g.refusedUntil.Sub(now); left > 0 {
		return left, true
	}
	if wait := g.notBefore.Sub(now); wait > 0 {
		return wait, false
	}
	if g.store != nil {
		claimed, err := g.store.SetNX(ctx, g.key, "1", pace)
		if err != nil {
			g.logger.Warn().Msg("shared export gate unavailable, skipping this fetch")
			g.notBefore = now.Add(exportStoreRetry)
			return exportStoreRetry, false
		}
		if !claimed {
			if left, err := g.store.TTL(ctx, g.key+exportRefusedSuffix); err == nil && left > 0 {
				g.refusedUntil = now.Add(left)
				g.notBefore = g.refusedUntil
				return left, true
			}
			wait, err := g.store.TTL(ctx, g.key)
			if err != nil || wait <= 0 {
				wait = exportStoreRetry
			}
			g.notBefore = now.Add(wait)
			return wait, false
		}
	}
	g.notBefore = now.Add(pace)
	return 0, false
}

// refuse closes the gate for the refusal hold and records why, here and in the
// shared store. The refusal key is written first: a replica that sees the long
// gate must also see the reason.
func (g *exportGate) refuse(ctx context.Context) {
	g.mu.Lock()
	defer g.mu.Unlock()

	until := time.Now().Add(exportRefusedHold)
	g.refusedUntil = until
	if g.notBefore.Before(until) {
		g.notBefore = until
	}
	if g.store == nil {
		return
	}
	storeCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), exportStoreTimeout)
	defer cancel()
	for _, key := range []string{g.key + exportRefusedSuffix, g.key} {
		if err := g.store.Set(storeCtx, key, "1", exportRefusedHold); err != nil {
			g.logger.Warn().Msg("could not record the refusal in the shared export gate")
		}
	}
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
		return nil, f.blocked("no abuse.ch Auth-Key configured, export not requested", false)
	}

	pace := max(configured, f.spec.minInterval)
	wait, refused := f.gate.reserve(ctx, pace)
	if refused {
		return nil, f.blocked(fmt.Sprintf(
			"provider refused the key or address at the last attempt, no request sent, next attempt in %s",
			wait.Round(time.Minute)), false)
	}
	if wait > 0 {
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
			f.gate.refuse(ctx)
			return nil, f.blocked("provider refused the abuse.ch Auth-Key (reported in the response body)", true)
		}
		return nil, fmt.Errorf("%s: %w", provider, parseErr)
	}
	return parsed, nil
}

func (f *exportFeed) blocked(message string, requested bool) error {
	return &sources.FetchBlockedError{
		PlanLimitError: sources.PlanLimitError{Provider: f.spec.provider, Message: message},
		Requested:      requested,
	}
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
		f.gate.refuse(ctx)
		return f.blocked(fmt.Sprintf("provider refused the abuse.ch Auth-Key (HTTP %d), next attempt in %s",
			code, exportRefusedHold), true)
	case code == http.StatusTooManyRequests:
		// The body is deliberately not passed on: it could echo the address.
		wait := max(sources.ParseRetryAfter(resp, nil, pace), pace)
		f.gate.hold(ctx, wait)
		return &sources.RateLimitError{Provider: provider, Wait: wait}
	case code == http.StatusNotFound || code == http.StatusGone || (code >= 300 && code < 400):
		f.gate.refuse(ctx)
		return f.blocked(fmt.Sprintf("export address not served (HTTP %d), next attempt in %s",
			code, exportRefusedHold), true)
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
// rows in memory. It reads one line at a time: a line over the limit is
// discarded without being stored, and a stray quote can damage only its own
// row, because no field may continue onto the next line.
func parseExport(r io.Reader, spec exportSpec) (*exportParse, error) {
	br := bufio.NewReaderSize(r, exportCommentMax)
	if err := sniffExport(br); err != nil {
		return nil, err
	}

	header, err := readCommentHeader(br, spec.columns)
	if err != nil {
		return nil, err
	}

	var index map[string]int
	maxFields := exportMaxColumns
	if header != nil {
		index = columnIndex(header)
		maxFields = len(header)
	}

	out := &exportParse{}
	newest := &rowHeap{}
	for {
		line, oversize, err := readExportLine(br)
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, &exportBodyError{err: err}
		}

		var rec []string
		usable := false
		if !oversize {
			line = bytes.TrimRight(line, "\r\n")
			if len(line) == 0 || line[0] == '#' {
				continue
			}
			rec, usable = splitExportLine(string(line), maxFields)
		}
		if !usable {
			if index == nil {
				return nil, errExportLayout
			}
			out.read++
			if out.read > exportMaxScannedRows {
				return nil, errExportTooLarge
			}
			out.bad++
			continue
		}

		if index == nil {
			cols := normalizeColumns(rec)
			if !hasColumns(cols, spec.columns) {
				return nil, errExportLayout
			}
			header, index = cols, columnIndex(cols)
			maxFields = len(cols)
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

// readExportLine returns the next line. The slice is only valid until the next
// read. A line longer than exportMaxLineBytes is reported as oversize, and the
// part beyond the read buffer is dropped without being stored.
func readExportLine(br *bufio.Reader) ([]byte, bool, error) {
	line, err := br.ReadSlice('\n')
	switch {
	case err == bufio.ErrBufferFull:
		for err == bufio.ErrBufferFull {
			_, err = br.ReadSlice('\n')
		}
		if err != nil && err != io.EOF {
			return nil, false, err
		}
		return nil, true, nil
	case err == io.EOF:
		if len(line) == 0 {
			return nil, false, io.EOF
		}
	case err != nil:
		return nil, false, err
	}
	return line, len(line) > exportMaxLineBytes, nil
}

// splitExportLine splits one CSV line into at most maxFields fields of at most
// exportMaxFieldBytes each. ok is false when the line breaks either limit or a
// quoted field never closes. Leading blanks of a field are dropped, a doubled
// quote is one quote, and a lone quote inside a quoted field is kept as text.
func splitExportLine(line string, maxFields int) (fields []string, ok bool) {
	fields = make([]string, 0, maxFields)
	for {
		line = strings.TrimLeft(line, " \t")

		var field string
		more := false
		if strings.HasPrefix(line, `"`) {
			var closed bool
			field, line, more, closed = readQuotedField(line[1:])
			if !closed {
				return nil, false
			}
		} else if comma := strings.IndexByte(line, ','); comma >= 0 {
			field, line, more = line[:comma], line[comma+1:], true
		} else {
			field, line = line, ""
		}

		if len(field) > exportMaxFieldBytes || len(fields) == maxFields {
			return nil, false
		}
		fields = append(fields, field)
		if !more {
			return fields, true
		}
	}
}

// readQuotedField reads a field whose opening quote is already consumed. The
// field ends at a quote followed by a comma or by the end of the line.
func readQuotedField(s string) (field, rest string, more, closed bool) {
	var unescaped strings.Builder
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] != '"' {
			continue
		}
		switch {
		case i+1 == len(s) || s[i+1] == ',':
			field = s[start:i]
			if unescaped.Len() > 0 {
				unescaped.WriteString(field)
				field = unescaped.String()
			}
			if i+1 == len(s) {
				return field, "", false, true
			}
			return field, s[i+2:], true, true
		case s[i+1] == '"':
			unescaped.WriteString(s[start : i+1])
			i++
			start = i + 1
		}
	}
	return "", "", false, false
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
	if len(head) == 4 && string(head) == "PK\x03\x04" {
		return errExportZipped
	}

	sample, err := br.Peek(exportSniffBytes)
	if err != nil && err != io.EOF {
		return &exportBodyError{err: err}
	}
	if looksLikeCSV(sample) {
		return nil
	}
	if mentionsRefusal(sample) {
		return errExportKeyRefused
	}
	switch first := bytes.TrimLeft(sample, " \t\r\n"); {
	case len(first) == 0:
		return errExportEmpty
	case first[0] == '<', first[0] == '{', first[0] == '[':
		return errExportLayout
	}
	return nil
}

// looksLikeCSV keeps a file whose columns merely changed from being read as a
// refusal message just because a column name contains a word like "auth_key".
func looksLikeCSV(sample []byte) bool {
	trimmed := bytes.TrimLeft(sample, " \t\r\n")
	if len(trimmed) == 0 {
		return false
	}
	switch trimmed[0] {
	case '#', '"':
		return true
	case '{', '[', '<':
		return false
	}
	line, _, _ := bytes.Cut(trimmed, []byte{'\n'})
	return bytes.Count(line, []byte{','}) >= 3
}

// exportRefusalPhrases are specific on purpose. A bare "auth" would also match
// the author tag of an ordinary HTML outage page.
var exportRefusalPhrases = [][]byte{
	[]byte("auth_key"), []byte("auth-key"), []byte("auth key"), []byte("authkey"),
	[]byte("api_key"), []byte("api-key"), []byte("api key"), []byte("apikey"),
	[]byte("invalid_key"), []byte("invalid key"), []byte("unauthori"),
	[]byte("authentication"), []byte("credentials"), []byte("forbidden"),
	[]byte("access denied"),
}

func mentionsRefusal(sample []byte) bool {
	lower := bytes.ToLower(sample)
	for _, phrase := range exportRefusalPhrases {
		if bytes.Contains(lower, phrase) {
			return true
		}
	}
	return false
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
	rec, ok := splitExportLine(strings.TrimLeft(strings.TrimSpace(line), "# \t"), exportMaxColumns)
	if !ok {
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
