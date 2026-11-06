package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
)

// readJSONBody decodes the request body as JSON after capping it at limit
// bytes, so a caller can never make the server buffer more than limit of
// their input. A declared Content-Length over the cap is refused before a
// byte is read (MaxBytesReader alone would read and hold the whole cap
// first); chunked and under-declared bodies are still cut off by
// http.MaxBytesReader. On failure it has already answered the request — 413
// when the cap was hit, 400 for anything else — and returns false.
func readJSONBody(w http.ResponseWriter, r *http.Request, limit int64, dst any) bool {
	if r.ContentLength > limit {
		respondJSON(w, http.StatusRequestEntityTooLarge, map[string]string{
			"error": fmt.Sprintf("request body exceeds the %d byte limit", limit),
		})
		return false
	}
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	err := json.NewDecoder(r.Body).Decode(dst)
	if err == nil {
		return true
	}
	var tooLarge *http.MaxBytesError
	if errors.As(err, &tooLarge) {
		respondJSON(w, http.StatusRequestEntityTooLarge, map[string]string{
			"error": fmt.Sprintf("request body exceeds the %d byte limit", tooLarge.Limit),
		})
		return false
	}
	respondJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
	return false
}
