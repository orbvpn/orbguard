package repository

import "regexp"

// Fetch errors are stored in sources.last_error and update_history.error and
// served by the sources and analytics endpoints. A connector's error text can
// carry a credential: Go's *url.Error quotes the whole request URL, query
// string included, so a key sent as ?key= ends up in the message. Every
// writer of a fetch error passes it through cleanFetchError first.
var fetchErrorSecrets = []struct {
	re   *regexp.Regexp
	with string
}{
	// The query string of any URL.
	{regexp.MustCompile(`(?i)\b((?:https?|wss?)://[^\s?#"'<>]+)\?[^\s#"'<>]*`), `${1}?[redacted]`},
	// name=value or name: value for names that hold credentials.
	{regexp.MustCompile(`(?i)\b((?:api[_-]?key|auth[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|token|secret|password|passwd|signature|sig|key)\s*[=:]\s*)("[^"]*"|[^\s&,;"'<>]+)`), `${1}[redacted]`},
	// Authorization header values.
	{regexp.MustCompile(`(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]{8,}`), `${1} [redacted]`},
	// Google API keys anywhere.
	{regexp.MustCompile(`AIza[0-9A-Za-z_-]{35}`), `[redacted]`},
}

// cleanFetchError removes URL query strings and anything that looks like a
// key or token from a fetch error before it is stored.
func cleanFetchError(msg string) string {
	for _, s := range fetchErrorSecrets {
		msg = s.re.ReplaceAllString(msg, s.with)
	}
	return msg
}
