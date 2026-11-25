package middleware

import (
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5/middleware"

	"orbguard-lab/pkg/logger"
)

// phoneLookupPath is the part of the route that has a phone number after it.
const phoneLookupPath = "/scam/phone/"

// logPath is the request path for a log line, with the phone number of a
// reputation lookup replaced.
func logPath(r *http.Request) string {
	path := r.URL.Path
	i := strings.Index(path, phoneLookupPath)
	if i < 0 {
		return path
	}
	end := i + len(phoneLookupPath)
	if path[end:] == "report" {
		return path
	}
	return path[:end] + "{number}"
}

// Logger returns a middleware that logs requests
func Logger(log *logger.Logger) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		fn := func(w http.ResponseWriter, r *http.Request) {
			ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
			start := time.Now()

			defer func() {
				log.Info().
					Str("method", r.Method).
					Str("path", logPath(r)).
					Str("remote_addr", r.RemoteAddr).
					Int("status", ww.Status()).
					Int("bytes", ww.BytesWritten()).
					Dur("duration", time.Since(start)).
					Str("request_id", middleware.GetReqID(r.Context())).
					Msg("request completed")
			}()

			next.ServeHTTP(ww, r)
		}
		return http.HandlerFunc(fn)
	}
}
