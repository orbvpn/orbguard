package handlers

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"runtime"
	"strings"
	"testing"
	"time"

	"orbguard-lab/internal/api/middleware"
)

// fillReader yields n bytes of 'a'.
type fillReader struct{ n int64 }

func (f *fillReader) Read(p []byte) (int, error) {
	if f.n <= 0 {
		return 0, io.EOF
	}
	if int64(len(p)) > f.n {
		p = p[:f.n]
	}
	for i := range p {
		p[i] = 'a'
	}
	f.n -= int64(len(p))
	return len(p), nil
}

// paddedBody is a JSON object whose "pad" string holds n bytes.
func paddedBody(fields string, n int64) io.Reader {
	return io.MultiReader(strings.NewReader(`{`+fields+`"pad":"`), &fillReader{n: n}, strings.NewReader(`"}`))
}

func forensicJSONRoutes(h *ForensicsHandler) map[string]struct {
	serve  func(http.ResponseWriter, *http.Request)
	fields string
} {
	return map[string]struct {
		serve  func(http.ResponseWriter, *http.Request)
		fields string
	}{
		"analyze shutdown log": {h.AnalyzeShutdownLog, `"device_id":"d",`},
		"analyze backup":       {h.AnalyzeBackup, `"device_id":"d",`},
		"analyze data usage":   {h.AnalyzeDataUsage, `"device_id":"d",`},
		"analyze sysdiagnose":  {h.AnalyzeSysdiagnose, `"device_id":"d",`},
		"analyze logcat":       {h.AnalyzeLogcat, `"device_id":"d",`},
		"full analysis":        {h.FullAnalysis, `"device_id":"d","platform":"ios",`},
		"quick check":          {h.QuickCheck, `"platform":"ios",`},
	}
}

func serviceRequest(body io.Reader, length int64) *http.Request {
	req := httptest.NewRequest(http.MethodPost, "/f", body)
	req.ContentLength = length
	return req.WithContext(context.WithValue(req.Context(), middleware.ContextKeyIsService, true))
}

func TestForensicJSONBodyOverTheCapIsRefused(t *testing.T) {
	h := budgetHandler(time.Minute)
	for name, route := range forensicJSONRoutes(h) {
		t.Run(name+"/streamed", func(t *testing.T) {
			runtime.GC()
			var before, after runtime.MemStats
			runtime.ReadMemStats(&before)
			rec := httptest.NewRecorder()
			route.serve(rec, serviceRequest(paddedBody(route.fields, 64<<20), -1))
			runtime.ReadMemStats(&after)
			if rec.Code != http.StatusRequestEntityTooLarge || !strings.Contains(rec.Body.String(), `"error":"request body exceeds the`) {
				t.Fatalf("want 413, got %d: %.200s", rec.Code, rec.Body.String())
			}
			if grew := after.TotalAlloc - before.TotalAlloc; grew > 4*maxForensicJSONBytes {
				t.Fatalf("a 64 MiB body allocated %d MiB", grew>>20)
			}
		})
		t.Run(name+"/declared length", func(t *testing.T) {
			rec := httptest.NewRecorder()
			route.serve(rec, serviceRequest(paddedBody(route.fields, 64<<20), 64<<20))
			if rec.Code != http.StatusRequestEntityTooLarge {
				t.Fatalf("want 413, got %d: %.200s", rec.Code, rec.Body.String())
			}
		})
		t.Run(name+"/under the cap", func(t *testing.T) {
			var body bytes.Buffer
			io.Copy(&body, paddedBody(route.fields, maxForensicJSONBytes-1024))
			rec := httptest.NewRecorder()
			route.serve(rec, serviceRequest(&body, int64(body.Len())))
			if rec.Code == http.StatusRequestEntityTooLarge || strings.Contains(rec.Body.String(), "invalid request body") {
				t.Fatalf("a body under the cap must be read, got %d: %.200s", rec.Code, rec.Body.String())
			}
		})
	}
}
