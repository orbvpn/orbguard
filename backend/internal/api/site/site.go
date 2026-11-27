// Package site serves OrbGuard's public pages: the landing page at /, and the
// legal and pricing pages.
//
// The legal and pricing pages exist because payment providers and consumer law
// require the Terms of Service (naming the legal entity ORB GLOBAL LTD), the
// Privacy Policy, and the subscription plans with prices to be viewable outside
// the app — the in-app paywall reads prices live from the platform stores,
// which are not reachable in every region or review environment.
//
// The page text mirrors app/lib/legal/legal_documents.dart — keep the two in
// sync when either changes. Prices on pricing.html are the store base prices
// (USD) and must be updated when the store prices change.
//
// The landing page (pages/home.html) is an html/template. Its store links come
// from optional environment variables read once in Register (see stores), so a
// listing goes live by setting its URL, never by editing the page. Its fonts
// and images are embedded under assets/ and served from /site/{file}; nothing
// on the page is fetched from another host.
package site

import (
	"bytes"
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"html/template"
	"net/http"
	"net/url"
	"os"
	"path"
	"strings"

	"github.com/go-chi/chi/v5"
)

//go:embed pages/*.html
var pages embed.FS

//go:embed assets/*
var assets embed.FS

func serve(name string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		body, err := pages.ReadFile("pages/" + name)
		if err != nil {
			http.Error(w, "page not found", http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "public, max-age=3600")
		_, _ = w.Write(body)
	}
}

// Register mounts the public pages on the router.
func Register(r chi.Router) {
	r.Get("/", serveHome(stores()))
	r.Get("/site/{file}", serveAsset)
	r.Get("/terms", serve("terms.html"))
	r.Get("/privacy", serve("privacy.html"))
	r.Get("/pricing", serve("pricing.html"))
}

// ---- store links ----

// platform is one place OrbGuard can be installed from. URL is empty until
// the listing is live and its env var is set.
type platform struct {
	Name  string // as the page names the device
	Store string // the store the link opens
	URL   string
}

// storeEnv lists the platforms in page order with the env var holding each
// store URL. Only https URLs are accepted; anything else is ignored.
var storeEnv = []struct{ name, store, env string }{
	{"iPhone", "App Store", "ORBGUARD_STORE_IOS"},
	{"Android", "Google Play", "ORBGUARD_STORE_ANDROID"},
	{"Mac", "Mac App Store", "ORBGUARD_STORE_MAC"},
	{"Windows", "Microsoft Store", "ORBGUARD_STORE_WINDOWS"},
}

func stores() []platform {
	out := make([]platform, 0, len(storeEnv))
	for _, s := range storeEnv {
		out = append(out, platform{Name: s.name, Store: s.store, URL: httpsURL(os.Getenv(s.env))})
	}
	return out
}

func httpsURL(raw string) string {
	raw = strings.TrimSpace(raw)
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.Host == "" {
		return ""
	}
	return u.String()
}

// ---- landing page ----

type homeData struct {
	Platforms []platform
	Listed    string // "iPhone, Android and Mac": the configured platforms, or ""
	AllListed bool
}

func newHomeData(ps []platform) homeData {
	var names []string
	for _, p := range ps {
		if p.URL != "" {
			names = append(names, p.Name)
		}
	}
	return homeData{Platforms: ps, Listed: joinAnd(names), AllListed: len(names) == len(ps)}
}

func joinAnd(xs []string) string {
	switch len(xs) {
	case 0:
		return ""
	case 1:
		return xs[0]
	}
	return strings.Join(xs[:len(xs)-1], ", ") + " and " + xs[len(xs)-1]
}

// assetVersion maps each embedded asset to a short content hash, appended to
// its URL so the year-long cache below never serves a replaced file.
var assetVersion = func() map[string]string {
	v := map[string]string{}
	entries, _ := assets.ReadDir("assets")
	for _, e := range entries {
		b, err := assets.ReadFile("assets/" + e.Name())
		if err != nil {
			continue
		}
		sum := sha256.Sum256(b)
		v[e.Name()] = hex.EncodeToString(sum[:4])
	}
	return v
}()

var homeTmpl = template.Must(template.New("home.html").Funcs(template.FuncMap{
	"asset": func(name string) string {
		return "/site/" + name + "?v=" + assetVersion[name]
	},
}).ParseFS(pages, "pages/home.html"))

// serveHome renders the landing page once, with the store links it was given.
func serveHome(ps []platform) http.HandlerFunc {
	var buf bytes.Buffer
	err := homeTmpl.Execute(&buf, newHomeData(ps))
	body := buf.Bytes()
	return func(w http.ResponseWriter, r *http.Request) {
		if err != nil {
			http.Error(w, "page unavailable", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "public, max-age=3600")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		_, _ = w.Write(body)
	}
}

// ---- assets ----

var assetTypes = map[string]string{
	".woff2": "font/woff2",
	".webp":  "image/webp",
	".svg":   "image/svg+xml",
}

func serveAsset(w http.ResponseWriter, r *http.Request) {
	name := chi.URLParam(r, "file")
	ctype, ok := assetTypes[path.Ext(name)]
	if !ok || strings.ContainsAny(name, `/\`) || strings.HasPrefix(name, ".") {
		http.NotFound(w, r)
		return
	}
	body, err := assets.ReadFile("assets/" + name)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", ctype)
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	_, _ = w.Write(body)
}
