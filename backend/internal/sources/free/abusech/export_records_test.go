package abusech

import (
	"bytes"
	"context"
	"encoding/csv"
	"errors"
	"fmt"
	"math/rand"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"orbguard-lab/internal/sources"
)

func recordsKept(rows []exportRow, column, value string) bool {
	for _, row := range rows {
		if row.get(column) == value {
			return true
		}
	}
	return false
}

func TestExportRecordOverSeveralLinesGivesNoRow(t *testing.T) {
	const second = "http://second.example/a.sh"
	tail := "42," + limitsWhen + "," + second + ",online," + limitsWhen + ",malware_download,z"
	carrier := func(tags string) string {
		return `"41","` + limitsWhen + `","http://first.example/a.sh","online","` + limitsWhen +
			`","malware_download","` + tags + `","https://urlhaus.example/41/","r"` + "\n"
	}
	for name, tc := range map[string]struct {
		tags  string
		lines int
	}{
		"two lines":           {"elf\n" + tail, 2},
		"carriage return":     {"elf\r\n" + tail, 2},
		"three lines":         {"elf\nnote\n" + tail, 3},
		"comment inside":      {"elf\n# note\n" + tail, 3},
		"blank line inside":   {"elf\n\n" + tail, 3},
		"doubled quotes":      {`elf ""x""` + "\n" + tail, 2},
		"over the line limit": {strings.Repeat("x", exportMaxLineBytes+1) + "\n" + tail, 2},
		"over the buffer":     {strings.Repeat("x", exportCommentMax+1) + "\n" + tail, 2},
	} {
		t.Run(name, func(t *testing.T) {
			body := urlhausHeader + limitsRows(40) + carrier(tc.tags) +
				strings.ReplaceAll(limitsRows(40), "bad", "later")
			c := limitsConnector(t, "http://127.0.0.1:1")
			parsed, err := parseExport(strings.NewReader(body), c.feed.spec)
			if err != nil {
				t.Fatal(err)
			}
			if recordsKept(parsed.rows, "url", second) || recordsKept(parsed.rows, "url", "http://first.example/a.sh") {
				t.Fatal("a row was taken from a record over several lines")
			}
			if parsed.bad != tc.lines || parsed.read != 80+tc.lines || len(parsed.rows) != 80 {
				t.Fatalf("read=%d bad=%d kept=%d, want %d, %d and 80", parsed.read, parsed.bad, len(parsed.rows), 80+tc.lines, tc.lines)
			}
		})
	}
}

func TestExportBazaarRecordOverSeveralLinesGivesNoRow(t *testing.T) {
	second := strings.Repeat("1", 64)
	tail := limitsWhen + "," + second + "," + strings.Repeat("2", 32) + "," + strings.Repeat("3", 40) +
		",rep,x,elf,application/octet-stream,Mirai,n/a,n/a,n/a,n/a,n/a"
	var body strings.Builder
	body.WriteString(bazaarHeader)
	for i := 0; i < 40; i++ {
		body.WriteString(bazaarRow(limitsWhen, fmt.Sprintf("%064x", i+1000), strings.Repeat("b", 32), strings.Repeat("c", 40), "Mirai", "elf"))
	}
	body.WriteString(`"` + limitsWhen + `", "` + strings.Repeat("9", 64) + `", "` + strings.Repeat("b", 32) + `", "` +
		strings.Repeat("c", 40) + `", "rep", "first` + "\n" + tail + `", "elf", "application/octet-stream", "Mirai", "n/a", "n/a", "n/a", "n/a", "n/a"` + "\n")

	c := NewMalwareBazaarConnector(testLogger(&bytes.Buffer{}))
	parsed, err := parseExport(strings.NewReader(body.String()), c.feed.spec)
	if err != nil {
		t.Fatal(err)
	}
	if recordsKept(parsed.rows, "sha256_hash", second) || recordsKept(parsed.rows, "sha256_hash", strings.Repeat("9", 64)) {
		t.Fatal("a row was taken from a record over several lines")
	}
	if parsed.bad != 2 || len(parsed.rows) != 40 {
		t.Fatalf("bad=%d kept=%d, want 2 and 40", parsed.bad, len(parsed.rows))
	}
}

// Every line a record covers counts, so a quote that never closes cannot lose
// the rest of a file at the cost of one bad row.
func TestExportOpenQuoteCountsEveryLineItCovers(t *testing.T) {
	plain := func(i int, tags string) string {
		return fmt.Sprintf("%d,%s,http://plain%d.example/a.sh,online,%s,malware_download,%s,https://urlhaus.example/%d/,r\n",
			i, limitsWhen, i, limitsWhen, tags, i)
	}
	var body strings.Builder
	body.WriteString(urlhausHeader)
	for i := 0; i < 95; i++ {
		body.WriteString(plain(i, "elf"))
	}
	body.WriteString(plain(95, `"elf`))
	for i := 96; i < 1000; i++ {
		body.WriteString(plain(i, "elf"))
	}
	c := limitsConnector(t, "http://127.0.0.1:1")
	if _, err := parseExport(strings.NewReader(body.String()), c.feed.spec); !errors.Is(err, errExportMalformed) {
		t.Fatalf("err=%v, want %v", err, errExportMalformed)
	}
}

// A correct CSV writer's output must read back as exactly the records that
// have no line break in them.
func TestExportReadsWhatACSVWriterWrote(t *testing.T) {
	rng := rand.New(rand.NewSource(20261122))
	pieces := []string{"a", "b c", ",", `"`, `""`, " ", "\t", "\r", "#", `",`, `,"`, "x,y", "http://z.example/"}
	text := func() string {
		var b strings.Builder
		for n := rng.Intn(6); n > 0; n-- {
			b.WriteString(pieces[rng.Intn(len(pieces))])
		}
		return b.String()
	}

	for round := 0; round < 40; round++ {
		var out bytes.Buffer
		out.WriteString(urlhausHeader)
		w := csv.NewWriter(&out)
		want := map[string]bool{}
		broken := map[string]bool{}
		for i := 0; i < 400; i++ {
			rawURL := fmt.Sprintf("http://row%d-%d.example/a.sh", round, i)
			tags, reporter := text(), text()
			if rng.Intn(100) == 0 {
				tags += "\n" + fmt.Sprintf("%d,%s,http://inner%d.example/a.sh,online,%s,malware_download,z", i, limitsWhen, i, limitsWhen)
				broken[rawURL] = true
			} else {
				want[rawURL] = true
			}
			if err := w.Write([]string{fmt.Sprint(i + 1), limitsWhen, rawURL, "online", limitsWhen, "malware_download", tags, "https://urlhaus.example/1/", reporter}); err != nil {
				t.Fatal(err)
			}
		}
		w.Flush()

		c := limitsConnector(t, "http://127.0.0.1:1")
		parsed, err := parseExport(bytes.NewReader(out.Bytes()), c.feed.spec)
		if err != nil {
			t.Fatalf("round %d: %v", round, err)
		}
		got := map[string]bool{}
		for _, row := range parsed.rows {
			got[row.get("url")] = true
		}
		for rawURL := range want {
			if !got[rawURL] {
				t.Fatalf("round %d: lost %s", round, rawURL)
			}
		}
		for rawURL := range got {
			if !want[rawURL] {
				t.Fatalf("round %d: invented %s", round, rawURL)
			}
		}
	}
}

func TestRefusalIsHonouredWithoutTheGateKey(t *testing.T) {
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer srv.Close()

	store := newMemoryGate()
	replica := func() error {
		c := limitsConnector(t, srv.URL)
		ShareFetchGate([]sources.Connector{c}, store)
		_, err := c.Fetch(context.Background())
		return err
	}
	if err := replica(); err == nil {
		t.Fatal("the refused fetch reported success")
	}
	for i := 0; i < 3; i++ {
		store.mu.Lock()
		delete(store.until, exportGateKeyPrefix+"urlhaus")
		store.mu.Unlock()

		var blocked *sources.FetchBlockedError
		if err := replica(); !errors.As(err, &blocked) {
			t.Fatalf("replica %d: err=%v, want a blocked fetch", i, err)
		}
	}
	if got := hits.Load(); got != 1 {
		t.Fatalf("%d requests sent, want 1", got)
	}
}

func TestExportCommentLineCannotOpenAQuote(t *testing.T) {
	body := urlhausHeader + limitsRows(20) + "# a note with one \" in it\n" +
		strings.ReplaceAll(limitsRows(20), "bad", "later")
	c := limitsConnector(t, "http://127.0.0.1:1")
	parsed, err := parseExport(strings.NewReader(body), c.feed.spec)
	if err != nil {
		t.Fatal(err)
	}
	if parsed.bad != 0 || len(parsed.rows) != 40 {
		t.Fatalf("bad=%d kept=%d, want 0 and 40", parsed.bad, len(parsed.rows))
	}
}

// refusedDuringClaim records another replica's refusal while this one claims.
type refusedDuringClaim struct{ *memoryGate }

func (s refusedDuringClaim) SetNX(ctx context.Context, key, _ string, ttl time.Duration) (bool, error) {
	_ = s.memoryGate.Set(ctx, key+exportRefusedSuffix, "1", exportRefusedHold)
	_ = s.memoryGate.Set(ctx, key, "1", exportRefusedHold)
	return false, nil
}

func TestRefusalRecordedDuringTheClaimIsReported(t *testing.T) {
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { hits.Add(1) }))
	defer srv.Close()

	c := limitsConnector(t, srv.URL)
	ShareFetchGate([]sources.Connector{c}, refusedDuringClaim{newMemoryGate()})
	var blocked *sources.FetchBlockedError
	if _, err := c.Fetch(context.Background()); !errors.As(err, &blocked) {
		t.Fatalf("err=%v, want a blocked fetch", err)
	}
	if hits.Load() != 0 {
		t.Fatalf("%d requests sent", hits.Load())
	}
}
