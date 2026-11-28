package api

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestOnlyTheArchiveUploadsOutliveTheRequestTimeout(t *testing.T) {
	var hasDeadline bool
	handler := requestTimeout(time.Minute)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, hasDeadline = r.Context().Deadline()
	}))
	for path, wantDeadline := range map[string]bool{
		"/api/v1/forensics/ios/sysdiagnose/upload":   false,
		"/api/v1/forensics/android/bugreport/upload": false,
		"/api/v1/forensics/ios/backup/upload":        false,
		"/api/v1/forensics/android/logcat/upload":    true,
		"/api/v1/forensics/quick-check":              true,
		"/api/v1/scam/analyze":                       true,
	} {
		handler.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodPost, path, nil))
		if hasDeadline != wantDeadline {
			t.Errorf("%s: deadline %v, want %v", path, hasDeadline, wantDeadline)
		}
	}
	handler.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/api/v1/forensics/ios/sysdiagnose/upload", nil))
	if !hasDeadline {
		t.Error("only a POST upload is exempt")
	}
}
