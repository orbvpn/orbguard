// Package site serves OrbGuard's public legal and pricing pages.
//
// These exist because payment providers and consumer law require the Terms of
// Service (naming the legal entity ORB GLOBAL LTD), the Privacy Policy, and
// the subscription plans with prices to be viewable outside the app — the
// in-app paywall reads prices live from the platform stores, which are not
// reachable in every region or review environment.
//
// The page text mirrors app/lib/legal/legal_documents.dart — keep the two in
// sync when either changes. Prices on pricing.html are the store base prices
// (USD) and must be updated when the store prices change.
package site

import (
	"embed"
	"net/http"

	"github.com/go-chi/chi/v5"
)

//go:embed pages/*.html
var pages embed.FS

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
	r.Get("/terms", serve("terms.html"))
	r.Get("/privacy", serve("privacy.html"))
	r.Get("/pricing", serve("pricing.html"))
}
