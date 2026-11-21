package services

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/rs/zerolog"

	"orbguard-lab/internal/config"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/sources"
	"orbguard-lab/internal/sources/free/abusech"
	"orbguard-lab/pkg/logger"
)

const (
	feedRowKey = "FEEDROWKEYMARKERq7"
	feedRowCSV = "# id,dateadded,url,url_status,last_online,threat,tags,urlhaus_link,reporter\n" +
		`"1","2026-11-20 10:00:00","http://evil.example/a","online","2026-11-20 10:00:00","malware_download","elf","https://urlhaus.example/1/","r"` + "\n"
)

func feedRowLog() *logger.Logger {
	return &logger.Logger{Logger: zerolog.New(io.Discard)}
}

// feedRowRedis is a minimal in-memory RESP server on 127.0.0.1. A key that was
// never set reports TTL -2, as real Redis does.
func feedRowRedis(t *testing.T) *cache.RedisCache {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { listener.Close() })

	var mu sync.Mutex
	store := map[string]string{}
	reply := func(args []string) string {
		mu.Lock()
		defer mu.Unlock()
		switch strings.ToUpper(args[0]) {
		case "PING":
			return "+PONG\r\n"
		case "HELLO":
			return "-ERR unknown command\r\n"
		case "SET":
			nx := false
			for _, a := range args[3:] {
				nx = nx || strings.EqualFold(a, "NX")
			}
			if _, held := store[args[1]]; nx && held {
				return "$-1\r\n"
			}
			store[args[1]] = args[2]
			return "+OK\r\n"
		case "SETNX":
			if _, held := store[args[1]]; held {
				return ":0\r\n"
			}
			store[args[1]] = args[2]
			return ":1\r\n"
		case "DEL":
			n := 0
			for _, k := range args[1:] {
				if _, held := store[k]; held {
					delete(store, k)
					n++
				}
			}
			return fmt.Sprintf(":%d\r\n", n)
		case "EXISTS":
			n := 0
			for _, k := range args[1:] {
				if _, held := store[k]; held {
					n++
				}
			}
			return fmt.Sprintf(":%d\r\n", n)
		case "TTL":
			if _, held := store[args[1]]; held {
				return ":3600\r\n"
			}
			return ":-2\r\n"
		case "INCR":
			return ":1\r\n"
		default:
			return "+OK\r\n"
		}
	}
	serve := func(conn net.Conn) {
		defer conn.Close()
		r := bufio.NewReader(conn)
		for {
			head, err := r.ReadString('\n')
			if err != nil || len(head) < 2 || head[0] != '*' {
				return
			}
			n, _ := strconv.Atoi(strings.TrimSpace(head[1:]))
			args := make([]string, n)
			for i := range args {
				size, err := r.ReadString('\n')
				if err != nil {
					return
				}
				length, _ := strconv.Atoi(strings.TrimSpace(size[1:]))
				buf := make([]byte, length+2)
				if _, err := io.ReadFull(r, buf); err != nil {
					return
				}
				args[i] = string(buf[:length])
			}
			if _, err := conn.Write([]byte(reply(args))); err != nil {
				return
			}
		}
	}
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go serve(conn)
		}
	}()

	port := listener.Addr().(*net.TCPAddr).Port
	rc, err := cache.NewRedis(context.Background(), config.RedisConfig{Host: "127.0.0.1", Port: port}, feedRowLog())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { rc.Close() })
	return rc
}

// feedRowRepo keeps one source row and applies the writes the way the real
// repository does.
type feedRowRepo struct {
	IndicatorRepository
	mu           sync.Mutex
	row          *models.Source
	due          []*models.Source
	planLimited  int
	afterSuccess []uuid.UUID
	afterFetch   []uuid.UUID
	afterError   int
	lookups      int
	stored       int
}

func (r *feedRowRepo) GetDueSources(context.Context) ([]*models.Source, error) { return r.due, nil }

func (r *feedRowRepo) GetSourceBySlug(_ context.Context, slug string) (*models.Source, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.lookups++
	if r.row == nil || r.row.Slug != slug {
		return nil, nil
	}
	copied := *r.row
	return &copied, nil
}

func (r *feedRowRepo) UpsertIndicator(_ context.Context, i *models.Indicator) (*models.Indicator, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.stored++
	return i, nil
}

func (r *feedRowRepo) UpdateSourceAfterFetch(_ context.Context, id uuid.UUID) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.afterFetch = append(r.afterFetch, id)
	return nil
}

func (r *feedRowRepo) UpdateSourceAfterSuccess(_ context.Context, id uuid.UUID) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.afterSuccess = append(r.afterSuccess, id)
	if r.row != nil && r.row.ID == id {
		r.row.Status = models.SourceStatusActive
		r.row.LastError = nil
		r.row.ErrorCount = 0
	}
	return nil
}

func (r *feedRowRepo) UpdateSourceAfterError(context.Context, uuid.UUID, string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.afterError++
	return nil
}

func (r *feedRowRepo) UpdateSourcePlanLimited(_ context.Context, id uuid.UUID, msg string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.planLimited++
	if r.row != nil && r.row.ID == id {
		r.row.Status = models.SourceStatusError
		r.row.LastError = &msg
		r.row.ErrorCount++
	}
	return nil
}

func (r *feedRowRepo) UpdateSourceRateLimited(context.Context, uuid.UUID, time.Time, string) error {
	return nil
}

func (r *feedRowRepo) RecordFetchHistory(context.Context, *models.SourceFetchResult) error {
	return nil
}

// feedRowTransport answers the export host from memory and refuses any other.
type feedRowTransport struct {
	code int
	body string
	hits atomic.Int32
}

func (tr *feedRowTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	if !strings.HasSuffix(req.URL.Hostname(), ".abuse.ch") {
		return nil, fmt.Errorf("unexpected host in test")
	}
	tr.hits.Add(1)
	return &http.Response{
		StatusCode: tr.code,
		Header:     http.Header{},
		Request:    req,
		Body:       io.NopCloser(strings.NewReader(tr.body)),
	}, nil
}

func feedRowAggregator(t *testing.T, repo IndicatorRepository, tr http.RoundTripper, rc *cache.RedisCache) *Aggregator {
	t.Helper()
	original := http.DefaultTransport
	http.DefaultTransport = tr
	t.Cleanup(func() { http.DefaultTransport = original })

	log := feedRowLog()
	agg := NewAggregator(config.AggregationConfig{WorkerPoolSize: 1}, repo, NewNormalizer(log),
		NewDeduplicator(rc, log), NewScorer(config.ScoringConfig{}, log), rc, log)
	conn := abusech.NewURLhausConnector(log)
	if err := conn.Configure(sources.ConnectorConfig{Enabled: true, UpdateInterval: time.Hour, APIKey: feedRowKey}); err != nil {
		t.Fatal(err)
	}
	abusech.ShareFetchGate([]sources.Connector{conn}, rc)
	agg.RegisterConnector(conn)
	return agg
}

func feedRow(status models.SourceStatus) *models.Source {
	old := "URLhaus: HTTP 410"
	return &models.Source{ID: uuid.New(), Slug: "urlhaus", Name: "URLhaus", Status: status, LastError: &old, ErrorCount: 9}
}

func TestRefusedKeyAtBootShowsOnTheRow(t *testing.T) {
	tr := &feedRowTransport{code: http.StatusUnauthorized}
	repo := &feedRowRepo{row: feedRow(models.SourceStatusActive)}
	agg := feedRowAggregator(t, repo, tr, feedRowRedis(t))

	if err := agg.RunOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	if repo.planLimited != 1 || repo.row.Status != models.SourceStatusError {
		t.Fatalf("planLimited=%d status=%s", repo.planLimited, repo.row.Status)
	}
	text := *repo.row.LastError
	if !strings.Contains(text, "refused") || strings.Contains(text, feedRowKey) {
		t.Fatalf("row text: %q", text)
	}
}

func TestRefusedKeyEndsAsAFailedJobEveryTime(t *testing.T) {
	tr := &feedRowTransport{code: http.StatusForbidden}
	repo := &feedRowRepo{row: feedRow(models.SourceStatusActive)}
	rc := feedRowRedis(t)
	agg := feedRowAggregator(t, repo, tr, rc)
	s := NewScheduler(agg, rc, feedRowLog())

	for i := 0; i < 3; i++ {
		job := s.ScheduleNow("urlhaus")
		s.executeJob(context.Background(), job)
		if job.Status != JobStatusFailed || job.Result.Success || job.Result.Error == "" {
			t.Fatalf("job %d: status=%s success=%v error=%q", i, job.Status, job.Result.Success, job.Result.Error)
		}
		if strings.Contains(job.Result.Error, feedRowKey) {
			t.Fatalf("job %d carries the key", i)
		}
	}
	if n := tr.hits.Load(); n != 1 {
		t.Fatalf("%d requests during the hold", n)
	}
	if repo.planLimited != 1 {
		t.Fatalf("the hold rewrote the row %d times", repo.planLimited)
	}
}

func TestRefusalOnADueTickIsRecorded(t *testing.T) {
	tr := &feedRowTransport{code: http.StatusUnauthorized}
	row := feedRow(models.SourceStatusActive)
	repo := &feedRowRepo{row: row, due: []*models.Source{row}}
	agg := feedRowAggregator(t, repo, tr, feedRowRedis(t))

	if err := agg.runDueSources(context.Background()); err != nil {
		t.Fatal(err)
	}
	if repo.planLimited != 1 || repo.afterError != 0 {
		t.Fatalf("planLimited=%d afterError=%d", repo.planLimited, repo.afterError)
	}
}

func TestRefusalLeavesAPausedRowPaused(t *testing.T) {
	for _, status := range []models.SourceStatus{models.SourceStatusPaused, models.SourceStatusDisabled} {
		tr := &feedRowTransport{code: http.StatusUnauthorized}
		repo := &feedRowRepo{row: feedRow(status)}
		agg := feedRowAggregator(t, repo, tr, feedRowRedis(t))

		if err := agg.RunSource(context.Background(), "urlhaus"); err == nil {
			t.Fatal("the job must still fail")
		}
		if repo.planLimited != 0 || repo.row.Status != status {
			t.Fatalf("%s: planLimited=%d status=%s", status, repo.planLimited, repo.row.Status)
		}
	}
}

func TestWorkingFeedClearsItsErrorRow(t *testing.T) {
	for _, status := range []models.SourceStatus{models.SourceStatusError, models.SourceStatusActive} {
		tr := &feedRowTransport{code: http.StatusOK, body: feedRowCSV}
		row := feedRow(status)
		id := row.ID
		repo := &feedRowRepo{row: row}
		rc := feedRowRedis(t)
		agg := feedRowAggregator(t, repo, tr, rc)
		s := NewScheduler(agg, rc, feedRowLog())

		job := s.ScheduleNow("urlhaus")
		s.executeJob(context.Background(), job)
		if !job.Result.Success || repo.stored == 0 {
			t.Fatalf("%s: job=%+v stored=%d", status, job.Result, repo.stored)
		}
		if len(repo.afterSuccess) != 1 || repo.afterSuccess[0] != id {
			t.Fatalf("%s: wrote %v, want the row %s", status, repo.afterSuccess, id)
		}
		if repo.row.Status != models.SourceStatusActive || repo.row.LastError != nil {
			t.Fatalf("%s: row left at %s", status, repo.row.Status)
		}
	}
}

func TestWorkingFeedLeavesAPausedRowPaused(t *testing.T) {
	for _, status := range []models.SourceStatus{models.SourceStatusPaused, models.SourceStatusDisabled} {
		tr := &feedRowTransport{code: http.StatusOK, body: feedRowCSV}
		repo := &feedRowRepo{row: feedRow(status)}
		agg := feedRowAggregator(t, repo, tr, feedRowRedis(t))

		if err := agg.RunSource(context.Background(), "urlhaus"); err != nil {
			t.Fatal(err)
		}
		if len(repo.afterSuccess) != 0 || repo.row.Status != status {
			t.Fatalf("%s: afterSuccess=%d status=%s", status, len(repo.afterSuccess), repo.row.Status)
		}
	}
}

// plainFeed is any connector that does not opt in to source-row tracking.
type plainFeed struct{ err error }

func (plainFeed) Slug() string                  { return "plain" }
func (plainFeed) IsEnabled() bool               { return true }
func (plainFeed) UpdateInterval() time.Duration { return time.Hour }
func (f plainFeed) Fetch(context.Context) (*models.SourceFetchResult, error) {
	if f.err != nil {
		return &models.SourceFetchResult{SourceSlug: "plain", Error: f.err}, f.err
	}
	return &models.SourceFetchResult{
		SourceSlug:    "plain",
		RawIndicators: []models.RawIndicator{{Value: "http://plain.example/a", Type: models.IndicatorTypeURL, SourceID: "plain", SourceName: "Plain"}},
	}, nil
}

func TestOtherConnectorsKeepTheirSourceRowBehaviour(t *testing.T) {
	rc := feedRowRedis(t)
	log := feedRowLog()
	newAgg := func(repo IndicatorRepository, f plainFeed) *Aggregator {
		agg := NewAggregator(config.AggregationConfig{}, repo, NewNormalizer(log),
			NewDeduplicator(rc, log), NewScorer(config.ScoringConfig{}, log), rc, log)
		agg.RegisterConnector(f)
		return agg
	}

	repo := &feedRowRepo{}
	if err := newAgg(repo, plainFeed{}).RunSource(context.Background(), "plain"); err != nil {
		t.Fatal(err)
	}
	if repo.lookups != 0 || len(repo.afterSuccess) != 0 || len(repo.afterFetch) != 1 || repo.afterFetch[0] != uuid.Nil {
		t.Fatalf("lookups=%d afterSuccess=%d afterFetch=%v", repo.lookups, len(repo.afterSuccess), repo.afterFetch)
	}

	// A plan limit from any other connector is still no job failure.
	repo = &feedRowRepo{}
	limited := plainFeed{err: &sources.PlanLimitError{Provider: "Plain", Message: "higher tier"}}
	if err := newAgg(repo, limited).RunSource(context.Background(), "plain"); err != nil {
		t.Fatalf("plan limit became a failure: %v", err)
	}
	if repo.planLimited != 0 || repo.lookups != 0 {
		t.Fatalf("planLimited=%d lookups=%d", repo.planLimited, repo.lookups)
	}
}

func oldExtractDomainFromURL(urlStr string) string {
	urlStr = strings.TrimPrefix(urlStr, "http://")
	urlStr = strings.TrimPrefix(urlStr, "https://")
	parts := strings.Split(urlStr, "/")
	if len(parts) > 0 {
		hostParts := strings.Split(parts[0], ":")
		return strings.ToLower(hostParts[0])
	}
	return ""
}

func TestExtractDomainFromURLKeepsEveryOldHost(t *testing.T) {
	for stored, want := range map[string]string{
		"http://evil.example/?q=a b":     "evil.example",
		`http://evil.example/?q=a\b`:     "evil.example",
		"http://https://evil.example/a":  "evil.example",
		"HTTP://Evil.Example/a":          "http",
		"http://evil.example:/a":         "evil.example",
		"http://evil.example?x=1":        "evil.example?x=1",
		"http://evil.example?x=@y.test/": "evil.example?x=@y.test",
		"http://evil.example.:8080/a":    "evil.example.",
		"http://[2001:db8::1]/a":         "[2001",
		"evil.example/path":              "evil.example",
		"ftp://evil.example/a":           "ftp",
	} {
		if got := extractDomainFromURL(stored); got != want {
			t.Errorf("extractDomainFromURL(%q) = %q, want %q", stored, got, want)
		}
		if got := oldExtractDomainFromURL(stored); got != want {
			t.Errorf("table entry %q is not what the old parser returned: %q", stored, got)
		}
	}
}

func TestExtractDomainFromURLMixedCaseSchemeThroughTheNormalizer(t *testing.T) {
	n := NewNormalizer(feedRowLog())
	for _, raw := range []string{"Https://evil.example/a", "HTTPS://evil.example/a", "hTTps://evil.example/a"} {
		stored := n.normalizeURL(raw)
		if got := extractDomainFromURL(stored); got != "evil.example" {
			t.Errorf("%q stored as %q derives %q", raw, stored, got)
		}
	}
}

func TestExtractDomainFromURLRefusesUserInfo(t *testing.T) {
	for _, stored := range []string{
		"http://github.com:80@evil.example/x",
		"http://evil.example:80@github.com/x",
		"https://u:p@github.com/x",
		`http://evil.example\@github.com/x`,
		"http://https://github.com:80@evil.example/x",
	} {
		if got := extractDomainFromURL(stored); got != "" {
			t.Errorf("extractDomainFromURL(%q) = %q, want no host", stored, got)
		}
	}
}

// Differential over every combination of the pieces parsers disagree on: the
// result is the old host, except for an authority carrying user info.
func TestExtractDomainFromURLDifferential(t *testing.T) {
	schemes := []string{"", "http://", "https://", "HTTP://", "Https://", "http://https://", "https://http://", "http://http://", "ftp://", "http:/", "//"}
	hosts := []string{"evil.example", "EVIL.example", "evil.example.", "203.0.113.9", "[2001:db8::1]", "a b.example", `a\b.example`, "", "evil.example:", "evil.example:8080", "https:", "xn--e1a.example"}
	userInfo := []string{"", "u@", "u:p@", "github.com:80@", `x\@`}
	tails := []string{"", "/", "/a b", `/a\b`, "?q=a b", `?q=a\b`, "#f", "?x=@y.test/z", "#@y.test/z", "//github.com/x", "/@y.test", "://github.com/x"}

	total, withUserInfo := 0, 0
	for _, scheme := range schemes {
		for _, host := range hosts {
			for _, info := range userInfo {
				for _, tail := range tails {
					stored := scheme + info + host + tail
					total++
					got, old := extractDomainFromURL(stored), oldExtractDomainFromURL(stored)
					if storedHasUserInfo(stored) {
						withUserInfo++
						if got != "" {
							t.Fatalf("%q has user info and derived %q", stored, got)
						}
						continue
					}
					if got != old {
						t.Fatalf("%q: new %q, old %q", stored, got, old)
					}
				}
			}
		}
	}
	t.Logf("%d stored values compared, %d with user info refused, all others equal the old host", total, withUserInfo)
}

// storedHasUserInfo finds an @ in the authority independently of the code
// under test: after the prefixes the old parser removes, before / ? or #.
func storedHasUserInfo(stored string) bool {
	rest := strings.TrimPrefix(strings.TrimPrefix(stored, "http://"), "https://")
	for i := 0; i < len(rest); i++ {
		switch rest[i] {
		case '/', '?', '#':
			return false
		case '@':
			return true
		}
	}
	return false
}
