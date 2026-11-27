package site

import (
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
)

func get(t *testing.T, r http.Handler, path string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec
}

func newRouter() chi.Router {
	r := chi.NewRouter()
	Register(r)
	return r
}

var storeVars = []string{"ORBGUARD_STORE_IOS", "ORBGUARD_STORE_ANDROID", "ORBGUARD_STORE_MAC", "ORBGUARD_STORE_WINDOWS"}

// noStores pins every store variable empty so the host environment cannot leak in.
func noStores(t *testing.T) {
	for _, v := range storeVars {
		t.Setenv(v, "")
	}
}

func TestPagesServe(t *testing.T) {
	r := newRouter()
	for path, want := range map[string]string{
		"/terms":   "ORB GLOBAL LTD",
		"/privacy": "ORB GLOBAL LTD",
		"/pricing": "$3.99",
	} {
		rec := get(t, r, path)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s: status %d", path, rec.Code)
		}
		if !strings.Contains(rec.Body.String(), want) {
			t.Fatalf("%s: missing %q", path, want)
		}
		if strings.Contains(rec.Body.String(), "orbvpn.com/terms") {
			t.Fatalf("%s: stale orbvpn.com link", path)
		}
	}
}

func TestHomeServes(t *testing.T) {
	noStores(t)
	rec := get(t, newRouter(), "/")
	if rec.Code != http.StatusOK {
		t.Fatalf("/: status %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "text/html; charset=utf-8" {
		t.Fatalf("/: content type %q", ct)
	}
	body := rec.Body.String()
	for _, want := range []string{
		"Is your circle closed?",
		"OrbGuard checks your phone for spyware, stalkerware and trackers, then tells you plainly what it found.",
		`href="/pricing"`, `href="/terms"`, `href="/privacy"`,
		`href="#get"`, `id="get"`,
		"ORB GLOBAL LTD",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("/: missing %q", want)
		}
	}
	for _, dash := range []string{"—", "–", "&mdash;", "&ndash;"} {
		if strings.Contains(body, dash) {
			t.Errorf("/: contains dash %q", dash)
		}
	}
	// Nothing on the page may come from another host: no absolute or
	// protocol-relative URLs anywhere (store links are configured, and absent here).
	if m := regexp.MustCompile(`(?i)(https?:)?//[a-z0-9.-]+\.[a-z]{2,}`).FindString(body); m != "" {
		t.Errorf("/: references an external host: %q", m)
	}
	// Every asset the page names must be served by this package.
	refs := regexp.MustCompile(`/site/([A-Za-z0-9._-]+)\?v=[0-9a-f]{8}`).FindAllStringSubmatch(body, -1)
	if len(refs) == 0 {
		t.Fatal("/: no versioned /site/ assets referenced")
	}
	for _, m := range refs {
		if rec := get(t, newRouter(), m[0]); rec.Code != http.StatusOK {
			t.Errorf("%s: status %d", m[0], rec.Code)
		}
	}
}

func TestHomeWithoutStores(t *testing.T) {
	noStores(t)
	body := get(t, newRouter(), "/").Body.String()
	if !strings.Contains(body, "Store links appear here as each listing goes live.") {
		t.Error("missing the not-yet-listed sentence")
	}
	for _, name := range []string{"iPhone", "Android", "Mac", "Windows"} {
		if !strings.Contains(body, "<b>"+name+"</b>") {
			t.Errorf("get section does not name %s", name)
		}
	}
	for _, s := range []string{`class="row" href=`, "Available on", "Not listed yet"} {
		if strings.Contains(body, s) {
			t.Errorf("unexpected %q with no stores configured", s)
		}
	}
}

func TestHomeWithSomeStores(t *testing.T) {
	noStores(t)
	t.Setenv("ORBGUARD_STORE_IOS", "https://apps.example.test/orbguard-ios")
	t.Setenv("ORBGUARD_STORE_ANDROID", " https://play.example.test/orbguard?id=1&hl=en ")
	t.Setenv("ORBGUARD_STORE_MAC", "javascript:alert(1)")           // not https: ignored
	t.Setenv("ORBGUARD_STORE_WINDOWS", "http://plain.example.test") // not https: ignored
	body := get(t, newRouter(), "/").Body.String()

	for _, want := range []string{
		`href="https://apps.example.test/orbguard-ios"`,
		`href="https://play.example.test/orbguard?id=1&amp;hl=en"`,
		"Available on iPhone and Android.",
		"Store links appear here as each listing goes live.",
		"Not listed yet",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("missing %q", want)
		}
	}
	for _, bad := range []string{"javascript:", "plain.example.test"} {
		if strings.Contains(body, bad) {
			t.Errorf("rendered rejected store URL %q", bad)
		}
	}
	if n := strings.Count(body, `class="row" href=`); n != 2 {
		t.Errorf("want 2 store links, got %d", n)
	}
}

func TestHomeWithAllStores(t *testing.T) {
	for _, v := range storeVars {
		t.Setenv(v, "https://store.example.test/"+strings.ToLower(v))
	}
	body := get(t, newRouter(), "/").Body.String()
	if !strings.Contains(body, "Available on iPhone, Android, Mac and Windows.") {
		t.Error("platform line does not name all four platforms")
	}
	for _, s := range []string{"Store links appear here", "Not listed yet"} {
		if strings.Contains(body, s) {
			t.Errorf("unexpected %q with every store configured", s)
		}
	}
}

func TestAssetsServe(t *testing.T) {
	r := newRouter()
	for file, ctype := range map[string]string{
		"archivo.woff2":          "font/woff2",
		"plex-sans.woff2":        "font/woff2",
		"plex-mono-medium.woff2": "font/woff2",
		"home-dark.webp":         "image/webp",
		"home-light.webp":        "image/webp",
		"mark.svg":               "image/svg+xml",
	} {
		rec := get(t, r, "/site/"+file)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s: status %d", file, rec.Code)
		}
		if got := rec.Header().Get("Content-Type"); got != ctype {
			t.Errorf("%s: content type %q, want %q", file, got, ctype)
		}
		if cc := rec.Header().Get("Cache-Control"); !strings.Contains(cc, "max-age=31536000") {
			t.Errorf("%s: cache control %q", file, cc)
		}
		if rec.Body.Len() == 0 {
			t.Errorf("%s: empty body", file)
		}
	}
	body := get(t, r, "/site/archivo.woff2").Body.Bytes()
	if string(body[:4]) != "wOF2" {
		t.Errorf("archivo.woff2 is not WOFF2: %q", body[:4])
	}
	if b := get(t, r, "/site/home-dark.webp").Body.Bytes(); string(b[8:12]) != "WEBP" {
		t.Errorf("home-dark.webp is not WebP")
	}
	for _, bad := range []string{"/site/missing.woff2", "/site/home.html", "/site/..%2fpages%2fterms.html", "/site/.webp"} {
		if rec := get(t, r, bad); rec.Code != http.StatusNotFound {
			t.Errorf("%s: status %d, want 404", bad, rec.Code)
		}
	}
}
