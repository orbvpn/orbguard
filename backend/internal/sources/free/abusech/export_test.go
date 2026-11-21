package abusech

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/rs/zerolog"

	"orbguard-lab/internal/config"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/sources"
	"orbguard-lab/pkg/logger"
)

// All fixtures follow the layout of the abuse.ch CSV exports: a block of "#"
// comments whose last line names the columns, then quoted rows. No test here
// opens a socket to anything but 127.0.0.1.

const markerKey = "MARKERKEY7f3a9c"

const urlhausHeader = "################################\n" +
	"# abuse.ch URLhaus Database Dump (CSV - recent URLs)\n" +
	"#\n" +
	"# id,dateadded,url,url_status,last_online,threat,tags,urlhaus_link,reporter\n"

const bazaarHeader = "################################\n" +
	"# MalwareBazaar recent malware samples (CSV)\n" +
	"#\n" +
	`# "first_seen_utc","sha256_hash","md5_hash","sha1_hash","reporter","file_name","file_type_guess","mime_type","signature","clamav","vtpercent","imphash","ssdeep","tlsh"` + "\n"

func urlhausRow(id int, when, rawURL, status string) string {
	return fmt.Sprintf(`"%d","%s","%s","%s","%s","malware_download","elf,mirai","https://urlhaus.abuse.ch/url/%d/","reporter1"`+"\n",
		id, when, rawURL, status, when, id)
}

func bazaarRow(when, sha256, md5, sha1, signature, fileType string) string {
	return fmt.Sprintf(`"%s", "%s", "%s", "%s", "rep", "sample.bin", "%s", "application/octet-stream", "%s", "n/a", "n/a", "n/a", "n/a", "n/a"`+"\n",
		when, sha256, md5, sha1, fileType, signature)
}

var (
	goodURLhausBody = urlhausHeader + urlhausRow(1, "2026-11-20 10:00:00", "http://bad.example/a.sh", "online")
	goodBazaarBody  = bazaarHeader + bazaarRow("2026-11-20 10:00:00", strings.Repeat("a", 64), strings.Repeat("b", 32), strings.Repeat("c", 40), "Mirai", "elf")
)

type lockedBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *lockedBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *lockedBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

func testLogger(w io.Writer) *logger.Logger {
	return &logger.Logger{Logger: zerolog.New(w).Level(zerolog.DebugLevel)}
}

// feedCase runs a test against both connectors.
type feedCase struct {
	name string
	good string
	make func(log *logger.Logger, base, key string) (sources.Connector, *exportFeed)
}

func feedCases() []feedCase {
	return []feedCase{
		{"urlhaus", goodURLhausBody, func(log *logger.Logger, base, key string) (sources.Connector, *exportFeed) {
			c := NewURLhausConnector(log)
			c.feed.spec.base = base
			_ = c.Configure(sources.ConnectorConfig{Enabled: true, UpdateInterval: 15 * time.Minute, APIKey: key})
			return c, c.feed
		}},
		{"malwarebazaar", goodBazaarBody, func(log *logger.Logger, base, key string) (sources.Connector, *exportFeed) {
			c := NewMalwareBazaarConnector(log)
			c.feed.spec.base = base
			_ = c.Configure(sources.ConnectorConfig{Enabled: true, UpdateInterval: 4 * time.Hour, APIKey: key})
			return c, c.feed
		}},
	}
}

func assertNoKey(t *testing.T, where, text string) {
	t.Helper()
	if strings.Contains(text, markerKey) {
		t.Fatalf("the key leaked into %s: %s", where, text)
	}
}

func assertResultClean(t *testing.T, result *models.SourceFetchResult, err error, logs string) {
	t.Helper()
	if err != nil {
		assertNoKey(t, "error text", err.Error())
		assertNoKey(t, "error %+v", fmt.Sprintf("%+v", err))
		assertNoKey(t, "error %#v", fmt.Sprintf("%#v", err))
		for inner := errors.Unwrap(err); inner != nil; inner = errors.Unwrap(inner) {
			assertNoKey(t, "wrapped error", inner.Error())
		}
	}
	if result != nil {
		assertNoKey(t, "result error", result.ErrorString())
		if raw, jsonErr := json.Marshal(struct {
			Slug  string
			Error string
			Rows  []models.RawIndicator
		}{result.SourceSlug, result.ErrorString(), result.RawIndicators}); jsonErr == nil {
			assertNoKey(t, "serialized result", string(raw))
		}
	}
	assertNoKey(t, "logs", logs)
}

func TestExportKeyNeverLeaks(t *testing.T) {
	echo := func(code int) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("X-Echo", r.URL.Path)
			w.WriteHeader(code)
			_, _ = io.WriteString(w, "refused for "+r.URL.String())
		}
	}

	type scenario struct {
		name    string
		handler http.HandlerFunc
		closed  bool
		timeout time.Duration
	}
	scenarios := []scenario{
		{name: "connection refused", closed: true},
		{name: "timeout", timeout: 80 * time.Millisecond, handler: func(w http.ResponseWriter, r *http.Request) {
			<-r.Context().Done()
		}},
		{name: "401", handler: echo(http.StatusUnauthorized)},
		{name: "403", handler: echo(http.StatusForbidden)},
		{name: "410", handler: echo(http.StatusGone)},
		{name: "429", handler: echo(http.StatusTooManyRequests)},
		{name: "500", handler: echo(http.StatusInternalServerError)},
		{name: "malformed body", handler: func(w http.ResponseWriter, r *http.Request) {
			_, _ = io.WriteString(w, "this is not a csv "+r.URL.String()+"\nline two\n")
		}},
		{name: "json error body", handler: func(w http.ResponseWriter, r *http.Request) {
			_, _ = fmt.Fprintf(w, `{"query_status":"unknown_auth_key","echo":%q}`, r.URL.String())
		}},
		{name: "connection dropped mid body", handler: func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Length", "100000")
			_, _ = io.WriteString(w, urlhausHeader)
			w.(http.Flusher).Flush()
			conn, _, err := w.(http.Hijacker).Hijack()
			if err == nil {
				_ = conn.Close()
			}
		}},
	}

	for _, fc := range feedCases() {
		for _, sc := range scenarios {
			t.Run(fc.name+"/"+sc.name, func(t *testing.T) {
				var logs lockedBuffer
				handler := sc.handler
				if handler == nil {
					handler = func(http.ResponseWriter, *http.Request) {}
				}
				srv := httptest.NewServer(handler)
				base := srv.URL
				if sc.closed {
					srv.Close()
				} else {
					defer srv.Close()
				}

				conn, feed := fc.make(testLogger(&logs), base, markerKey)
				if sc.timeout > 0 {
					feed.client.Timeout = sc.timeout
				}
				result, err := conn.Fetch(context.Background())
				if err == nil {
					t.Fatal("want a failed fetch")
				}
				if result.Success {
					t.Fatal("a failed fetch reported Success")
				}
				assertResultClean(t, result, err, logs.String())
			})
		}
	}
}

func TestExportRedirectIsNotFollowedAndKeepsTheKeySecret(t *testing.T) {
	for _, fc := range feedCases() {
		t.Run(fc.name, func(t *testing.T) {
			var targetHits atomic.Int32
			target := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
				targetHits.Add(1)
			}))
			defer target.Close()
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				http.Redirect(w, r, target.URL+r.URL.Path, http.StatusFound)
			}))
			defer srv.Close()

			var logs lockedBuffer
			conn, _ := fc.make(testLogger(&logs), srv.URL, markerKey)
			result, err := conn.Fetch(context.Background())
			if err == nil || result.Success {
				t.Fatalf("a redirect must fail the fetch (err=%v)", err)
			}
			if n := targetHits.Load(); n != 0 {
				t.Fatalf("the key-bearing request was sent to the redirect target %d times", n)
			}
			assertResultClean(t, result, err, logs.String())
		})
	}
}

func TestExportRequestUsesTheOfficialAddress(t *testing.T) {
	for _, fc := range feedCases() {
		t.Run(fc.name, func(t *testing.T) {
			var gotPath, gotQuery string
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				gotPath, gotQuery = r.URL.EscapedPath(), r.URL.RawQuery
				_, _ = io.WriteString(w, fc.good)
			}))
			defer srv.Close()

			conn, _ := fc.make(testLogger(io.Discard), srv.URL, "key/with space")
			result, err := conn.Fetch(context.Background())
			if err != nil || !result.Success {
				t.Fatalf("fetch failed: %v", err)
			}
			want := "/v2/files/exports/key%2Fwith%20space/recent.csv"
			if gotPath != want || gotQuery != "" {
				t.Fatalf("requested %q?%q, want %q", gotPath, gotQuery, want)
			}
		})
	}

	if NewURLhausConnector(testLogger(io.Discard)).feed.spec.base != "https://urlhaus-api.abuse.ch" {
		t.Fatal("URLhaus export host changed")
	}
	if NewMalwareBazaarConnector(testLogger(io.Discard)).feed.spec.base != "https://mb-api.abuse.ch" {
		t.Fatal("MalwareBazaar export host changed")
	}
}

type failingTransport struct{ calls atomic.Int32 }

func (f *failingTransport) RoundTrip(*http.Request) (*http.Response, error) {
	f.calls.Add(1)
	return nil, errors.New("no request may be sent")
}

func TestExportWithoutKeyFailsClearlyAndCallsNothing(t *testing.T) {
	for _, fc := range feedCases() {
		t.Run(fc.name, func(t *testing.T) {
			conn, feed := fc.make(testLogger(io.Discard), "http://127.0.0.1:1", "")
			transport := &failingTransport{}
			feed.client.Transport = transport

			result, err := conn.Fetch(context.Background())
			if _, ok := sources.AsPlanLimit(err); !ok {
				t.Fatalf("want a plan-limit failure, got %v", err)
			}
			if !strings.Contains(err.Error(), "no abuse.ch Auth-Key") {
				t.Fatalf("the failure does not say why: %v", err)
			}
			if result.Success {
				t.Fatal("no key reported Success")
			}
			if n := transport.calls.Load(); n != 0 {
				t.Fatalf("%d requests sent without a key", n)
			}
		})
	}
}

func TestExportBadFilesAreFailedFetches(t *testing.T) {
	bodies := map[string]func(fc feedCase) string{
		"empty":         func(feedCase) string { return "" },
		"comments only": func(fc feedCase) string { return fc.good[:strings.LastIndex(strings.TrimRight(fc.good, "\n"), "\n")+1] },
		"html":          func(feedCase) string { return "<html><body>maintenance</body></html>" },
		"zip":           func(feedCase) string { return "PK\x03\x04rest-of-archive" },
		"json":          func(feedCase) string { return `{"query_status":"no_results"}` },
		"columns renamed": func(feedCase) string {
			return "# alpha,beta,gamma\n\"1\",\"2\",\"3\"\n"
		},
		"no header": func(fc feedCase) string {
			lines := strings.Split(strings.TrimRight(fc.good, "\n"), "\n")
			return lines[len(lines)-1] + "\n"
		},
		"short rows": func(fc feedCase) string {
			header := fc.good[:strings.LastIndex(strings.TrimRight(fc.good, "\n"), "\n")+1]
			return header + strings.Repeat("\"1\",\"2\"\n", 20)
		},
		"unparsable dates": func(fc feedCase) string {
			return strings.ReplaceAll(fc.good, "2026-11-20 10:00:00", "yesterday")
		},
	}

	for _, fc := range feedCases() {
		for name, body := range bodies {
			t.Run(fc.name+"/"+name, func(t *testing.T) {
				payload := body(fc)
				srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
					_, _ = io.WriteString(w, payload)
				}))
				defer srv.Close()

				conn, _ := fc.make(testLogger(io.Discard), srv.URL, markerKey)
				result, err := conn.Fetch(context.Background())
				if err == nil {
					t.Fatalf("want a failed fetch, got %d indicators", len(result.RawIndicators))
				}
				if result.Success || len(result.RawIndicators) != 0 {
					t.Fatalf("Success=%v with %d indicators", result.Success, len(result.RawIndicators))
				}
			})
		}
	}
}

func TestExportChangedLayoutIsReportedAsSuch(t *testing.T) {
	const when = "2026-11-20 10:00:00"
	sha := strings.Repeat("a", 64)
	cases := map[string]struct {
		make func(*logger.Logger, string) sources.Connector
		body string
	}{
		"urlhaus lost a column": {
			make: func(log *logger.Logger, base string) sources.Connector {
				c, _ := feedCases()[0].make(log, base, markerKey)
				return c
			},
			body: "# id,dateadded,url,last_online,threat,tags,urlhaus_link,reporter\n" +
				`"1","` + when + `","http://bad.example/a","` + when + `","malware_download","elf","https://urlhaus.abuse.ch/url/1/","r"` + "\n",
		},
		"malwarebazaar lost a column": {
			make: func(log *logger.Logger, base string) sources.Connector {
				c, _ := feedCases()[1].make(log, base, markerKey)
				return c
			},
			body: `# "first_seen_utc","sha256_hash","md5_hash","reporter","file_name","file_type_guess","mime_type","signature"` + "\n" +
				`"` + when + `","` + sha + `","` + strings.Repeat("b", 32) + `","r","f","elf","application/x","Mirai"` + "\n",
		},
		"urlhaus without any header": {
			make: func(log *logger.Logger, base string) sources.Connector {
				c, _ := feedCases()[0].make(log, base, markerKey)
				return c
			},
			body: urlhausRow(1, when, "http://bad.example/a", "online"),
		},
	}

	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = io.WriteString(w, tc.body)
			}))
			defer srv.Close()

			result, err := tc.make(testLogger(io.Discard), srv.URL).Fetch(context.Background())
			if !errors.Is(err, errExportLayout) || result.Success {
				t.Fatalf("want the layout failure, got err=%v success=%v", err, result.Success)
			}
		})
	}
}

func TestExportToleratesAFewBadRowsButNotMany(t *testing.T) {
	build := func(good, bad int) string {
		var b strings.Builder
		b.WriteString(urlhausHeader)
		for i := 0; i < good; i++ {
			b.WriteString(urlhausRow(i, "2026-11-20 10:00:00", fmt.Sprintf("http://bad%d.example/x", i), "online"))
		}
		for i := 0; i < bad; i++ {
			b.WriteString("\"1\",\"2\"\n")
		}
		return b.String()
	}

	for name, tc := range map[string]struct {
		good, bad int
		wantErr   bool
	}{
		"one in a hundred": {good: 99, bad: 1},
		"one in eight":     {good: 7, bad: 1, wantErr: true},
	} {
		t.Run(name, func(t *testing.T) {
			body := build(tc.good, tc.bad)
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = io.WriteString(w, body)
			}))
			defer srv.Close()

			c := NewURLhausConnector(testLogger(io.Discard))
			c.feed.spec.base = srv.URL
			_ = c.Configure(sources.ConnectorConfig{Enabled: true, APIKey: markerKey})
			result, err := c.Fetch(context.Background())
			if tc.wantErr {
				if !errors.Is(err, errExportMalformed) || result.Success {
					t.Fatalf("want the malformed failure, got err=%v success=%v", err, result.Success)
				}
				return
			}
			if err != nil || len(result.RawIndicators) != tc.good {
				t.Fatalf("err=%v indicators=%d", err, len(result.RawIndicators))
			}
		})
	}
}

func TestExportCutOffMidFileIsAFailedFetch(t *testing.T) {
	for _, fc := range feedCases() {
		t.Run(fc.name, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Length", "100000")
				_, _ = io.WriteString(w, fc.good)
				w.(http.Flusher).Flush()
				if conn, _, err := w.(http.Hijacker).Hijack(); err == nil {
					_ = conn.Close()
				}
			}))
			defer srv.Close()

			conn, _ := fc.make(testLogger(io.Discard), srv.URL, markerKey)
			result, err := conn.Fetch(context.Background())
			if err == nil || result.Success || len(result.RawIndicators) != 0 {
				t.Fatalf("a cut-off file was accepted: err=%v success=%v rows=%d", err, result.Success, len(result.RawIndicators))
			}
		})
	}
}

func TestExportKeyRefusalInsideA200BodyClosesTheGate(t *testing.T) {
	for _, fc := range feedCases() {
		t.Run(fc.name, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = io.WriteString(w, `{"query_status":"unknown_auth_key"}`)
			}))
			defer srv.Close()

			store := newMemoryGate()
			conn, _ := fc.make(testLogger(io.Discard), srv.URL, markerKey)
			ShareFetchGate([]sources.Connector{conn}, store)
			_, err := conn.Fetch(context.Background())
			if _, ok := sources.AsPlanLimit(err); !ok {
				t.Fatalf("want a plan-limit failure, got %v", err)
			}
			if left := store.remaining(exportGateKeyPrefix + fc.name); left < 23*time.Hour {
				t.Fatalf("shared gate closed for only %s", left)
			}
		})
	}
}

func TestExportOverSizeLimitFails(t *testing.T) {
	for _, fc := range feedCases() {
		t.Run(fc.name, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = io.WriteString(w, fc.good)
				_, _ = io.WriteString(w, strings.Repeat("# padding padding padding\n", 400))
			}))
			defer srv.Close()

			conn, feed := fc.make(testLogger(io.Discard), srv.URL, markerKey)
			feed.spec.maxBytes = int64(len(fc.good) + 100)
			result, err := conn.Fetch(context.Background())
			if !errors.Is(err, errExportTooLarge) || result.Success {
				t.Fatalf("want the size failure, got err=%v success=%v", err, result.Success)
			}
		})
	}
}

func TestExportRowCapKeepsTheNewestInAnyFileOrder(t *testing.T) {
	const total, limit = 60, 10
	build := func(ascending bool) string {
		var b strings.Builder
		b.WriteString(urlhausHeader)
		for i := 0; i < total; i++ {
			n := i
			if !ascending {
				n = total - 1 - i
			}
			when := time.Date(2026, 11, 1, 0, n, 0, 0, time.UTC).Format(exportDateLayout)
			b.WriteString(urlhausRow(n, when, fmt.Sprintf("http://bad%d.example/x", n), "online"))
		}
		return b.String()
	}

	for name, ascending := range map[string]bool{"oldest first": true, "newest first": false} {
		t.Run(name, func(t *testing.T) {
			body := build(ascending)
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = io.WriteString(w, body)
			}))
			defer srv.Close()

			c := NewURLhausConnector(testLogger(io.Discard))
			c.feed.spec.base = srv.URL
			c.feed.spec.maxRows = limit
			_ = c.Configure(sources.ConnectorConfig{Enabled: true, APIKey: markerKey})

			result, err := c.Fetch(context.Background())
			if err != nil {
				t.Fatal(err)
			}
			if len(result.RawIndicators) != limit {
				t.Fatalf("got %d indicators, want %d", len(result.RawIndicators), limit)
			}
			for i, ind := range result.RawIndicators {
				want := fmt.Sprintf("http://bad%d.example/x", total-1-i)
				if ind.Value != want {
					t.Fatalf("row %d is %s, want %s", i, ind.Value, want)
				}
			}
		})
	}
}

func TestExportPacesItselfInsideOneProcess(t *testing.T) {
	for _, fc := range feedCases() {
		t.Run(fc.name, func(t *testing.T) {
			var hits atomic.Int32
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				hits.Add(1)
				_, _ = io.WriteString(w, fc.good)
			}))
			defer srv.Close()

			conn, _ := fc.make(testLogger(io.Discard), srv.URL, markerKey)
			if _, err := conn.Fetch(context.Background()); err != nil {
				t.Fatal(err)
			}
			_, err := conn.Fetch(context.Background())
			var deferred *sources.FetchDeferredError
			if !errors.As(err, &deferred) {
				t.Fatalf("want a deferral, got %v", err)
			}
			if n := hits.Load(); n != 1 {
				t.Fatalf("%d downloads inside one window", n)
			}
		})
	}
}

// memoryGate is a stand-in for Redis shared by several connectors.
type memoryGate struct {
	mu     sync.Mutex
	until  map[string]time.Time
	failed bool
}

func newMemoryGate() *memoryGate { return &memoryGate{until: map[string]time.Time{}} }

func (g *memoryGate) SetNX(_ context.Context, key, _ string, ttl time.Duration) (bool, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.failed {
		return false, errors.New("store down")
	}
	if time.Now().Before(g.until[key]) {
		return false, nil
	}
	g.until[key] = time.Now().Add(ttl)
	return true, nil
}

func (g *memoryGate) Set(_ context.Context, key, _ string, ttl time.Duration) error {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.until[key] = time.Now().Add(ttl)
	return nil
}

func (g *memoryGate) TTL(_ context.Context, key string) (time.Duration, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	return time.Until(g.until[key]), nil
}

func (g *memoryGate) remaining(key string) time.Duration {
	g.mu.Lock()
	defer g.mu.Unlock()
	return time.Until(g.until[key])
}

func TestExportPacingHoldsAcrossReplicas(t *testing.T) {
	for _, fc := range feedCases() {
		t.Run(fc.name, func(t *testing.T) {
			var hits atomic.Int32
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				hits.Add(1)
				_, _ = io.WriteString(w, fc.good)
			}))
			defer srv.Close()

			store := newMemoryGate()
			var wg sync.WaitGroup
			for i := 0; i < 3; i++ {
				conn, _ := fc.make(testLogger(io.Discard), srv.URL, markerKey)
				ShareFetchGate([]sources.Connector{conn}, store)
				wg.Add(1)
				go func() {
					defer wg.Done()
					_, _ = conn.Fetch(context.Background())
				}()
			}
			wg.Wait()
			if n := hits.Load(); n != 1 {
				t.Fatalf("three replicas made %d downloads in one window", n)
			}
		})
	}
}

func TestExportStoreOutageSendsNothing(t *testing.T) {
	for _, fc := range feedCases() {
		t.Run(fc.name, func(t *testing.T) {
			var hits atomic.Int32
			srv := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
				hits.Add(1)
			}))
			defer srv.Close()

			store := newMemoryGate()
			store.failed = true
			conn, _ := fc.make(testLogger(io.Discard), srv.URL, markerKey)
			ShareFetchGate([]sources.Connector{conn}, store)

			_, err := conn.Fetch(context.Background())
			var deferred *sources.FetchDeferredError
			if !errors.As(err, &deferred) {
				t.Fatalf("want a deferral, got %v", err)
			}
			if n := hits.Load(); n != 0 {
				t.Fatalf("%d requests sent while the store was down", n)
			}
		})
	}
}

func TestExportRefusalClosesTheGateForADay(t *testing.T) {
	for _, code := range []int{http.StatusUnauthorized, http.StatusForbidden, http.StatusGone, http.StatusNotFound} {
		for _, fc := range feedCases() {
			t.Run(fmt.Sprintf("%s/%d", fc.name, code), func(t *testing.T) {
				var hits atomic.Int32
				srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
					hits.Add(1)
					w.WriteHeader(code)
				}))
				defer srv.Close()

				store := newMemoryGate()
				first, _ := fc.make(testLogger(io.Discard), srv.URL, markerKey)
				ShareFetchGate([]sources.Connector{first}, store)
				_, err := first.Fetch(context.Background())
				if err == nil {
					t.Fatal("want a failure")
				}
				if code == http.StatusUnauthorized || code == http.StatusForbidden {
					if _, ok := sources.AsPlanLimit(err); !ok {
						t.Fatalf("a refused key must be a plan-limit failure, got %v", err)
					}
				}

				if left := store.remaining(exportGateKeyPrefix + fc.name); left < 23*time.Hour {
					t.Fatalf("shared gate closed for only %s", left)
				}

				replica, _ := fc.make(testLogger(io.Discard), srv.URL, markerKey)
				ShareFetchGate([]sources.Connector{replica}, store)
				_, _ = replica.Fetch(context.Background())
				if n := hits.Load(); n != 1 {
					t.Fatalf("%d requests after a refusal", n)
				}
			})
		}
	}
}

func TestExportRateLimitHonoursRetryAfter(t *testing.T) {
	for _, fc := range feedCases() {
		t.Run(fc.name, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Retry-After", "36000")
				w.WriteHeader(http.StatusTooManyRequests)
			}))
			defer srv.Close()

			store := newMemoryGate()
			conn, _ := fc.make(testLogger(io.Discard), srv.URL, markerKey)
			ShareFetchGate([]sources.Connector{conn}, store)

			_, err := conn.Fetch(context.Background())
			rle, ok := sources.AsRateLimit(err)
			if !ok {
				t.Fatalf("want a rate-limit error, got %v", err)
			}
			if rle.Wait != 10*time.Hour {
				t.Fatalf("waits %s, want 10h", rle.Wait)
			}
			if left := store.remaining(exportGateKeyPrefix + fc.name); left < 9*time.Hour {
				t.Fatalf("shared gate closed for only %s", left)
			}
		})
	}
}

func TestExportFailedFetchIsNotRetriedInsideTheWindow(t *testing.T) {
	for _, fc := range feedCases() {
		t.Run(fc.name, func(t *testing.T) {
			var hits atomic.Int32
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				hits.Add(1)
				w.WriteHeader(http.StatusBadGateway)
			}))
			defer srv.Close()

			conn, _ := fc.make(testLogger(io.Discard), srv.URL, markerKey)
			_, _ = conn.Fetch(context.Background())
			_, _ = conn.Fetch(context.Background())
			if n := hits.Load(); n != 1 {
				t.Fatalf("%d requests inside one window after a 502", n)
			}
		})
	}
}

func TestURLhausLeavesOutRowsThatWouldBlockHealthySites(t *testing.T) {
	const when = "2026-11-20 10:00:00"
	body := urlhausHeader +
		urlhausRow(1, when, "http://bad.example/a.sh", "online") +
		urlhausRow(2, when, "http://203.0.113.9:8080/bin", "online") +
		urlhausRow(3, when, "https://raw.githubusercontent.com/u/r/x.sh", "online") +
		urlhausRow(4, when, "https://GitHub.com./u/r/x.sh", "online") +
		urlhausRow(5, when, "https://cdn.discordapp.com/a/b.exe", "online") +
		urlhausRow(6, when, "http://good.example:80@bad2.example/x", "online") +
		urlhausRow(7, when, "http://192.168.1.1:8080/x", "online") +
		urlhausRow(8, when, "http://offline.example/x", "offline") +
		urlhausRow(9, when, "ftp://bad3.example/x", "online")

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, body)
	}))
	defer srv.Close()

	c := NewURLhausConnector(testLogger(io.Discard))
	c.feed.spec.base = srv.URL
	_ = c.Configure(sources.ConnectorConfig{Enabled: true, APIKey: markerKey})
	result, err := c.Fetch(context.Background())
	if err != nil {
		t.Fatal(err)
	}

	got := map[string]models.IndicatorType{}
	for _, ind := range result.RawIndicators {
		got[ind.Value] = ind.Type
		if ind.Type == models.IndicatorTypeDomain {
			t.Fatalf("a whole-domain indicator was made for %s", ind.Value)
		}
	}
	want := map[string]models.IndicatorType{
		"http://bad.example/a.sh":     models.IndicatorTypeURL,
		"http://203.0.113.9:8080/bin": models.IndicatorTypeURL,
		"203.0.113.9":                 models.IndicatorTypeIP,
	}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for value, typ := range want {
		if got[value] != typ {
			t.Fatalf("missing %s as %s in %v", value, typ, got)
		}
	}
}

func TestURLhausFileWithNothingUsableIsAFailure(t *testing.T) {
	body := urlhausHeader + urlhausRow(1, "2026-11-20 10:00:00", "http://x.example/a", "offline")
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, body)
	}))
	defer srv.Close()

	c := NewURLhausConnector(testLogger(io.Discard))
	c.feed.spec.base = srv.URL
	_ = c.Configure(sources.ConnectorConfig{Enabled: true, APIKey: markerKey})
	result, err := c.Fetch(context.Background())
	if !errors.Is(err, errExportNoEligible) || result.Success {
		t.Fatalf("want the no-usable-rows failure, got err=%v success=%v", err, result.Success)
	}
}

func TestMalwareBazaarSiblingIndicatorsKeepTheirOwnTags(t *testing.T) {
	// One optional tag leaves the slice with spare capacity: with a shared
	// backing array all three indicators ended up tagged sha1.
	body := bazaarHeader + bazaarRow("2026-11-20 10:00:00",
		strings.Repeat("a", 64), strings.Repeat("b", 32), strings.Repeat("c", 40), "Mirai", "")
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, body)
	}))
	defer srv.Close()

	c := NewMalwareBazaarConnector(testLogger(io.Discard))
	c.feed.spec.base = srv.URL
	_ = c.Configure(sources.ConnectorConfig{Enabled: true, APIKey: markerKey})
	result, err := c.Fetch(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(result.RawIndicators) != 3 {
		t.Fatalf("got %d indicators, want 3", len(result.RawIndicators))
	}
	for i, want := range []string{"sha256", "md5", "sha1"} {
		tags := result.RawIndicators[i].Tags
		if tags[len(tags)-1] != want {
			t.Fatalf("indicator %d is tagged %v, want last tag %s", i, tags, want)
		}
	}
}

func TestMalwareBazaarDropsAMalformedSecondaryHashOnly(t *testing.T) {
	body := bazaarHeader + bazaarRow("2026-11-20 10:00:00", strings.Repeat("A", 64), "n/a", "", "Mirai", "elf")
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, body)
	}))
	defer srv.Close()

	c := NewMalwareBazaarConnector(testLogger(io.Discard))
	c.feed.spec.base = srv.URL
	_ = c.Configure(sources.ConnectorConfig{Enabled: true, APIKey: markerKey})
	result, err := c.Fetch(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(result.RawIndicators) != 1 || result.RawIndicators[0].Value != strings.Repeat("a", 64) {
		t.Fatalf("got %+v", result.RawIndicators)
	}
}

func TestConfigureKeepsTheKeyOutOfTheSharedConfig(t *testing.T) {
	for _, fc := range feedCases() {
		t.Run(fc.name, func(t *testing.T) {
			conn, feed := fc.make(testLogger(io.Discard), "http://127.0.0.1:1", markerKey)
			if feed.apiKey != markerKey {
				t.Fatal("the export client did not receive the key")
			}
			holder, ok := conn.(interface {
				Config() sources.ConnectorConfig
			})
			if !ok {
				t.Fatal("connector has no Config method")
			}
			if holder.Config().APIKey != "" {
				t.Fatal("the key is readable through Config()")
			}
		})
	}
}

func TestRegistryGivesBothExportsTheThreatFoxKey(t *testing.T) {
	log := testLogger(io.Discard)
	registry := sources.NewRegistry(log)
	urlhaus := NewURLhausConnector(log)
	bazaar := NewMalwareBazaarConnector(log)
	if err := registry.Register(urlhaus); err != nil {
		t.Fatal(err)
	}
	if err := registry.Register(bazaar); err != nil {
		t.Fatal(err)
	}

	registry.ConfigureFromSourcesConfig(config.SourcesConfig{
		URLhaus:       config.SourceConfig{Enabled: true, APIKey: "stale-unused-value"},
		MalwareBazaar: config.SourceConfig{Enabled: true},
		ThreatFox:     config.SourceConfig{Enabled: true, APIKey: markerKey},
	})

	if urlhaus.feed.apiKey != markerKey || bazaar.feed.apiKey != markerKey {
		t.Fatal("the exports did not receive the ThreatFox key")
	}
}

// TestLargeExportStaysBounded streams a file near the size cap through the
// connector and the normalizer and reports what it held in memory.
func TestLargeExportStaysBounded(t *testing.T) {
	const rows = 330_000
	start := time.Date(2026, 10, 22, 0, 0, 0, 0, time.UTC)

	var served atomic.Int64
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, urlhausHeader)
		var b strings.Builder
		for i := 0; i < rows; i++ {
			when := start.Add(time.Duration(i) * 8 * time.Second).Format(exportDateLayout)
			host := fmt.Sprintf("198.51.%d.%d", 100+i%2, 1+i%250)
			b.WriteString(urlhausRow(i, when, fmt.Sprintf("http://%s:8080/payload/sample-%d.bin", host, i), "online"))
			if b.Len() > 32*1024 {
				served.Add(int64(b.Len()))
				_, _ = io.WriteString(w, b.String())
				b.Reset()
			}
		}
		served.Add(int64(b.Len()))
		_, _ = io.WriteString(w, b.String())
	}))
	defer srv.Close()

	log := testLogger(io.Discard)
	c := NewURLhausConnector(log)
	c.feed.spec.base = srv.URL
	_ = c.Configure(sources.ConnectorConfig{Enabled: true, APIKey: markerKey})

	runtime.GC()
	var before runtime.MemStats
	runtime.ReadMemStats(&before)

	var peak atomic.Uint64
	done := make(chan struct{})
	var sampler sync.WaitGroup
	sampler.Add(1)
	go func() {
		defer sampler.Done()
		ticker := time.NewTicker(5 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-done:
				return
			case <-ticker.C:
				var m runtime.MemStats
				runtime.ReadMemStats(&m)
				if m.HeapAlloc > peak.Load() {
					peak.Store(m.HeapAlloc)
				}
			}
		}
	}()

	result, err := c.Fetch(context.Background())
	if err != nil {
		close(done)
		sampler.Wait()
		t.Fatal(err)
	}
	normalized, _ := services.NewNormalizer(log).NormalizeBatch(result.RawIndicators)
	close(done)
	sampler.Wait()

	runtime.GC()
	var after runtime.MemStats
	runtime.ReadMemStats(&after)
	liveMiB := (float64(after.HeapAlloc) - float64(before.HeapAlloc)) / (1 << 20)
	peakMiB := (float64(peak.Load()) - float64(before.HeapAlloc)) / (1 << 20)
	t.Logf("file=%.1f MiB rows=%d indicators=%d normalized=%d live=%.1f MiB peak heap=%.1f MiB",
		float64(served.Load())/(1<<20), rows, len(result.RawIndicators), len(normalized), liveMiB, peakMiB)

	if len(result.RawIndicators) != 2*urlhausMaxRows {
		t.Fatalf("got %d indicators, want %d", len(result.RawIndicators), 2*urlhausMaxRows)
	}
	if liveMiB > 64 {
		t.Fatalf("holds %.1f MiB after the fetch", liveMiB)
	}
	if peakMiB > 256 {
		t.Fatalf("peak heap grew by %.1f MiB", peakMiB)
	}
	runtime.KeepAlive(result)
	runtime.KeepAlive(normalized)
}
