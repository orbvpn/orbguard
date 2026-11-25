package handlers

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"orbguard-lab/internal/domain/services"
	"orbguard-lab/pkg/logger"
)

// newYARATestHandler builds the handler over a real engine with the built-in
// rules and no Redis or database.
func newYARATestHandler() *YARAHandler {
	log := logger.NewDefault()
	return NewYARAHandler(services.NewYARAService("", nil, log), log)
}

func postJSON(h http.HandlerFunc, path, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

const validRule = `rule Limits_Test { strings: $a = "indicator" condition: any of them }`

func TestParseRuleBodyCap(t *testing.T) {
	h := newYARATestHandler()

	t.Run("over the cap is 413", func(t *testing.T) {
		body := `{"rule_content":"` + strings.Repeat("a", maxRuleBodyBytes+1) + `"}`
		rec := postJSON(h.ParseRule, "/api/v1/yara/parse", body)
		if rec.Code != http.StatusRequestEntityTooLarge {
			t.Fatalf("want 413, got %d: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "byte limit") {
			t.Fatalf("413 body should name the limit, got %s", rec.Body.String())
		}
	})

	t.Run("under the cap is processed", func(t *testing.T) {
		rec := postJSON(h.ParseRule, "/api/v1/yara/parse", `{"rule_content":`+quote(validRule)+`}`)
		if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"valid":true`) {
			t.Fatalf("want 200 valid, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("malformed JSON under the cap is 400", func(t *testing.T) {
		rec := postJSON(h.ParseRule, "/api/v1/yara/parse", `{"rule_content": "unterminated`)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("want 400, got %d", rec.Code)
		}
	})

	t.Run("empty rule_content is 400", func(t *testing.T) {
		rec := postJSON(h.ParseRule, "/api/v1/yara/parse", `{"rule_content":""}`)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("want 400, got %d", rec.Code)
		}
	})
}

func TestSubmitRuleBodyCap(t *testing.T) {
	h := newYARATestHandler() // no submission repository: valid bodies answer 503

	body := `{"name":"big","raw_rule":"` + strings.Repeat("a", maxRuleBodyBytes+1) + `"}`
	rec := postJSON(h.SubmitRule, "/api/v1/yara/submit", body)
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized submit: want 413, got %d: %s", rec.Code, rec.Body.String())
	}

	// The cap is checked before anything else: a small body reaches the
	// repository check, proving the 413 above came from the cap alone.
	rec = postJSON(h.SubmitRule, "/api/v1/yara/submit", `{"name":"small","raw_rule":`+quote(validRule)+`}`)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("small submit without a repository: want 503, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRuleValidationTimeoutIs400(t *testing.T) {
	h := newYARATestHandler()

	// A deadline already in the past makes the context expire before the
	// compiler's first check, so the timeout path is taken deterministically.
	saved := ruleValidateTimeout
	ruleValidateTimeout = -time.Second
	t.Cleanup(func() { ruleValidateTimeout = saved })

	rec := postJSON(h.ParseRule, "/api/v1/yara/parse", `{"rule_content":`+quote(validRule)+`}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("parse under an expired deadline: want 400, got %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "timed out") {
		t.Fatalf("400 body should say the validation timed out, got %s", rec.Body.String())
	}
	// SubmitRule validates through the same validateRuleSource, but only
	// after its storage check, which needs a database; the shared path is
	// covered here through ParseRule.
}

func TestScanBodyCap(t *testing.T) {
	h := newYARATestHandler()
	tooBig := `{"base64_data":"` + strings.Repeat("A", maxScanBodyBytes+1) + `"}`

	for name, fn := range map[string]http.HandlerFunc{
		"scan":       h.Scan,
		"scan/apk":   h.ScanAPK,
		"scan/ipa":   h.ScanIPA,
		"quick-scan": h.QuickScan,
	} {
		rec := postJSON(fn, "/api/v1/yara/"+name, tooBig)
		if rec.Code != http.StatusRequestEntityTooLarge {
			t.Fatalf("%s oversized: want 413, got %d: %s", name, rec.Code, rec.Body.String())
		}
	}

	// A normal quick scan still works.
	rec := postJSON(h.QuickScan, "/api/v1/yara/quick-scan", `{"content":"hello"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("normal quick-scan: want 200, got %d: %s", rec.Code, rec.Body.String())
	}
}

// quote JSON-encodes a rule string for embedding in a request body.
func quote(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for _, r := range s {
		switch r {
		case '"':
			b.WriteString(`\"`)
		case '\\':
			b.WriteString(`\\`)
		case '\n':
			b.WriteString(`\n`)
		default:
			b.WriteRune(r)
		}
	}
	b.WriteByte('"')
	return b.String()
}

// endlessJSONBody is a request body that opens a JSON string and keeps it
// going far past any cap, counting every byte the handler pulls from it. It
// does end, at 4x the largest cap, so a handler that lost its limit fails the
// test with a wrong status instead of reading forever.
type endlessJSONBody struct {
	prefix string
	read   int64
}

const endlessBodyEnd = 4 * maxScanBodyBytes

func (b *endlessJSONBody) Read(p []byte) (int, error) {
	n := 0
	for n < len(p) && b.read < endlessBodyEnd {
		if int(b.read) < len(b.prefix) {
			p[n] = b.prefix[b.read]
		} else {
			p[n] = 'A'
		}
		n++
		b.read++
	}
	if n == 0 {
		return 0, io.EOF
	}
	return n, nil
}

func (b *endlessJSONBody) Close() error { return nil }

func TestReadJSONBodyStopsAtTheCap(t *testing.T) {
	h := newYARATestHandler()

	t.Run("a declared Content-Length over the cap is refused unread", func(t *testing.T) {
		for name, tc := range map[string]struct {
			fn    http.HandlerFunc
			limit int64
		}{
			"scan":  {h.Scan, maxScanBodyBytes},
			"parse": {h.ParseRule, maxRuleBodyBytes},
		} {
			body := &endlessJSONBody{prefix: `{"base64_data":"`}
			req := httptest.NewRequest(http.MethodPost, "/api/v1/yara/"+name, nil)
			req.Body = body
			req.ContentLength = tc.limit + 1
			rec := httptest.NewRecorder()
			tc.fn(rec, req)
			if rec.Code != http.StatusRequestEntityTooLarge {
				t.Fatalf("%s: want 413, got %d: %s", name, rec.Code, rec.Body.String())
			}
			if body.read != 0 {
				t.Fatalf("%s: %d body bytes were read before refusing a declared oversize body", name, body.read)
			}
		}
	})

	t.Run("a body of unknown length is cut off at the cap", func(t *testing.T) {
		body := &endlessJSONBody{prefix: `{"rule_content":"`}
		req := httptest.NewRequest(http.MethodPost, "/api/v1/yara/parse", nil)
		req.Body = body
		req.ContentLength = -1 // chunked
		rec := httptest.NewRecorder()
		h.ParseRule(rec, req)
		if rec.Code != http.StatusRequestEntityTooLarge {
			t.Fatalf("want 413, got %d: %s", rec.Code, rec.Body.String())
		}
		if body.read > maxRuleBodyBytes+1 {
			t.Fatalf("read %d bytes of an endless body, want at most the cap (%d) plus one", body.read, maxRuleBodyBytes)
		}
	})
}

// TestParseRuleRefusesCompileBombsQuickly is the attack from the review run
// through the handler: 230 KB of regex text that would expand to 33M
// instructions (2 s and 7 GB of allocation when it was compiled). It is now
// answered as a validation failure, without being compiled, in a small
// fraction of the request deadline.
func TestParseRuleRefusesCompileBombsQuickly(t *testing.T) {
	h := newYARATestHandler()

	var rule strings.Builder
	rule.WriteString("rule Bomb { strings:\n")
	for i := 0; i < 10; i++ {
		rule.WriteString("$a" + strconv.Itoa(i) + " = /" + strings.Repeat("x{1000}", 3300) + "/\n")
	}
	rule.WriteString("condition: any of them }")
	body := `{"rule_content":` + quote(rule.String()) + `}`
	if len(body) > maxRuleBodyBytes {
		t.Fatalf("test body is %d bytes, it must fit the %d byte cap to reach the compiler", len(body), maxRuleBodyBytes)
	}

	start := time.Now()
	rec := postJSON(h.ParseRule, "/api/v1/yara/parse", body)
	elapsed := time.Since(start)

	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"valid":false`) || !strings.Contains(rec.Body.String(), "instructions") {
		t.Fatalf("want 200 valid=false naming the instruction limit, got %d: %.300s", rec.Code, rec.Body.String())
	}
	if elapsed > time.Second {
		t.Fatalf("refusing the submission took %s; the request deadline is %s", elapsed, ruleValidateTimeout)
	}
}
