package abusech

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"runtime"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/sources"
)

const limitsWhen = "2026-11-20 10:00:00"

func limitsRows(n int) string {
	var b strings.Builder
	for i := 0; i < n; i++ {
		b.WriteString(urlhausRow(i+1, limitsWhen, fmt.Sprintf("http://bad%d.example/a.sh", i), "online"))
	}
	return b.String()
}

func limitsConnector(t *testing.T, base string) *URLhausConnector {
	t.Helper()
	c := NewURLhausConnector(testLogger(io.Discard))
	c.feed.spec.base = base
	if err := c.Configure(sources.ConnectorConfig{Enabled: true, APIKey: markerKey}); err != nil {
		t.Fatal(err)
	}
	return c
}

// A row whose tags field is megabytes of commas must cost no allocation in
// proportion to its comma count, plain or compressed on the wire.
func TestExportCommaBombCostsNoMemory(t *testing.T) {
	bomb := `"999","` + limitsWhen + `","http://bomb.example/a","online","` + limitsWhen +
		`","malware_download","` + strings.Repeat(",", 8<<20) + `","https://urlhaus.example/1/","r"` + "\n"
	body := urlhausHeader + limitsRows(60) + bomb

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, body)
	}))
	defer srv.Close()
	c := limitsConnector(t, srv.URL)

	runtime.GC()
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	result, err := c.Fetch(context.Background())
	runtime.ReadMemStats(&after)
	if err != nil {
		t.Fatalf("one oversized row must not fail the feed: %v", err)
	}

	allocated := float64(after.TotalAlloc-before.TotalAlloc) / (1 << 20)
	t.Logf("allocated %.1f MiB to read an %d MiB row", allocated, 8)
	if allocated > 16 {
		t.Fatalf("allocated %.1f MiB for one row", allocated)
	}
	for _, ind := range result.RawIndicators {
		if strings.Contains(ind.Value, "bomb.example") {
			t.Fatalf("the oversized row was ingested: %s", ind.Value)
		}
	}
	if len(result.RawIndicators) != 60 {
		t.Fatalf("got %d indicators, want 60", len(result.RawIndicators))
	}
}

func TestExportFieldOverTheLimitIsABadRow(t *testing.T) {
	long := "http://long.example/" + strings.Repeat("a", exportFieldLimitForTest)
	body := urlhausHeader + limitsRows(60) + urlhausRow(100, limitsWhen, long, "online")

	c := limitsConnector(t, "http://127.0.0.1:1")
	parsed, err := parseExport(strings.NewReader(body), c.feed.spec)
	if err != nil {
		t.Fatal(err)
	}
	if parsed.bad != 1 || len(parsed.rows) != 60 {
		t.Fatalf("bad=%d kept=%d, want 1 and 60", parsed.bad, len(parsed.rows))
	}
}

func TestExportLineOverTheLimitIsABadRow(t *testing.T) {
	// Every field is inside the field limit; only the line as a whole is not.
	wide := strings.Repeat("x", exportFieldLimitForTest-1)
	row := `"100","` + limitsWhen + `","http://wide.example/` + strings.Repeat("a", 3000) + `","online","` + limitsWhen +
		`","malware_download","` + wide + `","` + wide + `","r"` + "\n"
	body := urlhausHeader + limitsRows(60) + row

	c := limitsConnector(t, "http://127.0.0.1:1")
	parsed, err := parseExport(strings.NewReader(body), c.feed.spec)
	if err != nil {
		t.Fatal(err)
	}
	if parsed.bad != 1 || len(parsed.rows) != 60 {
		t.Fatalf("bad=%d kept=%d, want 1 and 60", parsed.bad, len(parsed.rows))
	}
}

// The hostile worst case for what is kept: every row as large as the limits
// allow, so the row cap holds the most memory it ever can.
func TestExportLargestLegalRowsStayBounded(t *testing.T) {
	const rows = 7000
	tags := strings.TrimSuffix(strings.Repeat("abcdefgh,", 330), ",")
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, urlhausHeader)
		for i := 0; i < rows; i++ {
			address := fmt.Sprintf("http://h%d.example/%s", i, strings.Repeat("p", 4000))
			_, _ = fmt.Fprintf(w, "\"%d\",\"%s\",\"%s\",\"online\",\"%s\",\"malware_download\",\"%s\",\"https://urlhaus.example/%d/\",\"r\"\n",
				i, limitsWhen, address, limitsWhen, tags, i)
		}
	}))
	defer srv.Close()
	c := limitsConnector(t, srv.URL)

	runtime.GC()
	var before runtime.MemStats
	runtime.ReadMemStats(&before)
	var peak atomic.Uint64
	stop := make(chan struct{})
	finished := make(chan struct{})
	go func() {
		defer close(finished)
		var m runtime.MemStats
		for {
			select {
			case <-stop:
				return
			case <-time.After(2 * time.Millisecond):
				runtime.ReadMemStats(&m)
				if m.HeapAlloc > peak.Load() {
					peak.Store(m.HeapAlloc)
				}
			}
		}
	}()
	result, err := c.Fetch(context.Background())
	close(stop)
	<-finished
	if err != nil {
		t.Fatal(err)
	}

	peakMiB := (float64(peak.Load()) - float64(before.HeapAlloc)) / (1 << 20)
	t.Logf("rows=%d kept=%d peak heap=%.1f MiB", rows, len(result.RawIndicators), peakMiB)
	if len(result.RawIndicators) != urlhausMaxRows {
		t.Fatalf("kept %d indicators, want %d", len(result.RawIndicators), urlhausMaxRows)
	}
	if peakMiB > 128 {
		t.Fatalf("peak heap %.1f MiB", peakMiB)
	}
}

// One row with an unbalanced quote must lose that row only. A parser that lets
// a quoted field run across lines would swallow the rows after it.
func TestExportStrayQuoteCannotSpliceRows(t *testing.T) {
	broken := `"500","` + limitsWhen + `","http://broken.example/a","online","` + limitsWhen +
		`","malware_download","elf,"https://urlhaus.example/1/","r` + "\n"
	body := urlhausHeader + limitsRows(30) + broken + strings.ReplaceAll(limitsRows(30), "bad", "later")

	c := limitsConnector(t, "http://127.0.0.1:1")
	parsed, err := parseExport(strings.NewReader(body), c.feed.spec)
	if err != nil {
		t.Fatal(err)
	}
	if parsed.read != 61 || parsed.bad != 1 || len(parsed.rows) != 60 {
		t.Fatalf("read=%d bad=%d kept=%d, want 61, 1 and 60", parsed.read, parsed.bad, len(parsed.rows))
	}
	for _, row := range parsed.rows {
		if strings.Contains(row.get("url"), "broken.example") {
			t.Fatalf("the broken row was kept: %q", row.get("url"))
		}
	}
}

func TestExportQuotedFieldsAreRead(t *testing.T) {
	body := urlhausHeader +
		`"1","` + limitsWhen + `","http://a.example/x,y","online","` + limitsWhen + `","malware_download","el""f","https://urlhaus.example/1/","r"` + "\r\n" +
		`2,` + limitsWhen + `,http://b.example/z,online,` + limitsWhen + `,malware_download,  elf,https://urlhaus.example/2/,r` + "\n"

	c := limitsConnector(t, "http://127.0.0.1:1")
	parsed, err := parseExport(strings.NewReader(body), c.feed.spec)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]string{}
	for _, row := range parsed.rows {
		got[row.get("url")] = row.get("tags")
	}
	if got["http://a.example/x,y"] != `el"f` || got["http://b.example/z"] != "elf" {
		t.Fatalf("fields read wrongly: %v", got)
	}
}

func TestURLhausTagsAreCapped(t *testing.T) {
	var tags []string
	for i := 0; i < 200; i++ {
		tags = append(tags, fmt.Sprintf("t%d", i))
	}
	row := `"1","` + limitsWhen + `","http://a.example/x","online","` + limitsWhen +
		`","malware_download","` + strings.Join(tags, ",") + `","https://urlhaus.example/1/","r"` + "\n"

	c := limitsConnector(t, "http://127.0.0.1:1")
	parsed, err := parseExport(strings.NewReader(urlhausHeader+row), c.feed.spec)
	if err != nil {
		t.Fatal(err)
	}
	indicators := c.rowIndicators(parsed.rows[0])
	if n := len(indicators[0].Tags); n > 40 {
		t.Fatalf("one row produced %d tags", n)
	}
}

// F2: one bad URL says nothing about the rest of its host.
func TestURLhausRowProducesOnlyAURLIndicator(t *testing.T) {
	body := urlhausHeader +
		urlhausRow(1, limitsWhen, "http://203.0.113.9:8080/bin", "online") +
		urlhausRow(2, limitsWhen, "http://bad.example/a.sh", "online")

	c := limitsConnector(t, "http://127.0.0.1:1")
	parsed, err := parseExport(strings.NewReader(body), c.feed.spec)
	if err != nil {
		t.Fatal(err)
	}
	for _, row := range parsed.rows {
		indicators := c.rowIndicators(row)
		if len(indicators) != 1 || indicators[0].Type != models.IndicatorTypeURL {
			t.Fatalf("row %q produced %d indicators, first type %s",
				row.get("url"), len(indicators), indicators[0].Type)
		}
	}
}

func TestExportRefusalBodiesInA200AreHeldForADay(t *testing.T) {
	for name, body := range map[string]string{
		"json-unknown-key":     `{"query_status":"unknown_auth_key"}`,
		"json-leading-newline": "\n{\"query_status\":\"unknown_auth_key\"}",
		"json-leading-space":   " {\"query_status\":\"unknown_auth_key\"}",
		"json-error-field":     `{"error":"invalid auth key"}`,
		"json-detail-field":    `{"detail":"Authentication credentials were not provided."}`,
		"json-forbidden":       `{"query_status":"forbidden"}`,
		"json-unauthorized":    `{"query_status":"unauthorized"}`,
		"text-unauthorized":    "Unauthorized\n",
		"text-invalid-key":     "Invalid Auth-Key\n",
		"html-denied":          "<html><body>Access denied</body></html>",
	} {
		t.Run(name, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = io.WriteString(w, body)
			}))
			defer srv.Close()
			c := limitsConnector(t, srv.URL)

			_, err := c.Fetch(context.Background())
			if _, ok := sources.AsPlanLimit(err); !ok {
				t.Fatalf("want a refusal, got %v", err)
			}
			if left := time.Until(c.feed.gate.notBefore); left < 23*time.Hour {
				t.Fatalf("held for only %s", left)
			}
		})
	}
}

// A file that merely changed must not be reported as a dead key.
func TestExportOtherBadBodiesAreNotCalledARefusal(t *testing.T) {
	for name, body := range map[string]string{
		"html-outage":    `<html><head><meta name="author" content="ops"></head><body>Service unavailable</body></html>`,
		"json-other":     `{"query_status":"no_results"}`,
		"csv-new-layout": "# id,when,auth_key,forbidden,status\n1,2,3,4,5\n",
		"plain-outage":   "Service temporarily unavailable\n",
	} {
		t.Run(name, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = io.WriteString(w, body)
			}))
			defer srv.Close()
			c := limitsConnector(t, srv.URL)

			_, err := c.Fetch(context.Background())
			if err == nil {
				t.Fatal("want a failure")
			}
			if _, ok := sources.AsPlanLimit(err); ok {
				t.Fatalf("reported as a refused key: %v", err)
			}
			if left := time.Until(c.feed.gate.notBefore); left > 2*time.Hour {
				t.Fatalf("held for %s", left)
			}
		})
	}
}

// F3: while a refusal is in force, every replica must report it. A silent
// deferral would make a dead key look like a healthy, paced feed.
func TestExportHeldRefusalIsReportedNotDeferred(t *testing.T) {
	for _, code := range []int{http.StatusUnauthorized, http.StatusForbidden, http.StatusGone} {
		t.Run(fmt.Sprint(code), func(t *testing.T) {
			var hits atomic.Int32
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				hits.Add(1)
				w.WriteHeader(code)
			}))
			defer srv.Close()

			store := newMemoryGate()
			first := limitsConnector(t, srv.URL)
			ShareFetchGate([]sources.Connector{first}, store)
			if _, err := first.Fetch(context.Background()); err == nil {
				t.Fatal("want a failure")
			}

			replica := limitsConnector(t, srv.URL)
			ShareFetchGate([]sources.Connector{replica}, store)
			for name, conn := range map[string]*URLhausConnector{"same process": first, "replica": replica} {
				_, err := conn.Fetch(context.Background())
				var deferred *sources.FetchDeferredError
				if err == nil || errors.As(err, &deferred) {
					t.Fatalf("%s: a held refusal read as %v", name, err)
				}
				if _, ok := sources.AsPlanLimit(err); !ok {
					t.Fatalf("%s: want a refusal, got %v", name, err)
				}
				assertNoKey(t, name, err.Error())
			}
			if n := hits.Load(); n != 1 {
				t.Fatalf("%d requests during the hold", n)
			}
		})
	}
}

func TestExportRefusalEndsWhenTheHoldEnds(t *testing.T) {
	var refuse atomic.Bool
	refuse.Store(true)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if refuse.Load() {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		_, _ = io.WriteString(w, urlhausHeader+limitsRows(3))
	}))
	defer srv.Close()

	store := newMemoryGate()
	first := limitsConnector(t, srv.URL)
	ShareFetchGate([]sources.Connector{first}, store)
	if _, err := first.Fetch(context.Background()); err == nil {
		t.Fatal("want a failure")
	}

	store.mu.Lock()
	for key := range store.until {
		store.until[key] = time.Now().Add(-time.Second)
	}
	store.mu.Unlock()
	refuse.Store(false)

	replica := limitsConnector(t, srv.URL)
	ShareFetchGate([]sources.Connector{replica}, store)
	if _, err := replica.Fetch(context.Background()); err != nil {
		t.Fatalf("the feed stayed closed after the hold: %v", err)
	}
}

// A rate limit is a pacing matter and stays a plain deferral for the others.
func TestExportRateLimitIsStillADeferralForReplicas(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	defer srv.Close()

	store := newMemoryGate()
	first := limitsConnector(t, srv.URL)
	ShareFetchGate([]sources.Connector{first}, store)
	_, _ = first.Fetch(context.Background())

	replica := limitsConnector(t, srv.URL)
	ShareFetchGate([]sources.Connector{replica}, store)
	_, err := replica.Fetch(context.Background())
	var deferred *sources.FetchDeferredError
	if !errors.As(err, &deferred) {
		t.Fatalf("want a deferral, got %v", err)
	}
}

const exportFieldLimitForTest = 4 << 10
