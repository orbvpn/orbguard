package ai

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/pkg/logger"
)

const (
	numverifyTestKey    = "test-numverify-key-value"
	numverifyTestDigits = "4915112340077"
	numverifyTestNumber = "+" + numverifyTestDigits
	providerBodyMarker  = "marker-echoed-user-text"
)

type privacyLog struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (l *privacyLog) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.Write(p)
}

func (l *privacyLog) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.String()
}

func (l *privacyLog) logger() *logger.Logger {
	return &logger.Logger{Logger: zerolog.New(l).Level(zerolog.DebugLevel)}
}

// fakeProvider answers in memory: these tests never open a socket to a provider.
type fakeProvider struct {
	mu      sync.Mutex
	urls    []string
	respond func(*http.Request) (*http.Response, error)
}

func (f *fakeProvider) RoundTrip(r *http.Request) (*http.Response, error) {
	f.mu.Lock()
	f.urls = append(f.urls, r.URL.String())
	f.mu.Unlock()
	return f.respond(r)
}

func (f *fakeProvider) calls() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.urls...)
}

func providerReply(status int, body string, headers ...string) func(*http.Request) (*http.Response, error) {
	return func(r *http.Request) (*http.Response, error) {
		h := http.Header{}
		for i := 0; i+1 < len(headers); i += 2 {
			h.Set(headers[i], headers[i+1])
		}
		return &http.Response{
			Status:     strconv.Itoa(status) + " " + http.StatusText(status),
			StatusCode: status, Header: h, Request: r,
			Body: io.NopCloser(strings.NewReader(body)),
		}, nil
	}
}

func numverifyService(respond func(*http.Request) (*http.Response, error)) (*PhoneReputationService, *fakeProvider, *privacyLog) {
	logs := &privacyLog{}
	fake := &fakeProvider{respond: respond}
	s := NewPhoneReputationService(logs.logger(), PhoneReputationConfig{
		NumverifyAPIKey: numverifyTestKey, EnableNumverify: true, CacheTTL: time.Hour,
	})
	s.httpClient = &http.Client{Transport: fake, Timeout: 2 * time.Second}
	return s, fake, logs
}

func reportsUnavailable(t *testing.T, rep *PhoneReputation) bool {
	t.Helper()
	raw, err := json.Marshal(rep)
	if err != nil {
		t.Fatal(err)
	}
	var fields struct {
		Unavailable []string `json:"unavailable_sources"`
	}
	if err := json.Unmarshal(raw, &fields); err != nil {
		t.Fatal(err)
	}
	for _, source := range fields.Unavailable {
		if source == "numverify" {
			return true
		}
	}
	return false
}

func hasSource(rep *PhoneReputation, name string) bool {
	for _, source := range rep.DataSources {
		if source == name {
			return true
		}
	}
	return false
}

func TestNumverifyUsesHTTPSAndAppliesAnAnswer(t *testing.T) {
	s, fake, _ := numverifyService(providerReply(http.StatusOK,
		`{"valid":true,"country_code":"DE","country_name":"Germany","carrier":"Example Carrier","line_type":"mobile"}`))
	rep, err := s.Lookup(context.Background(), numverifyTestNumber)
	if err != nil {
		t.Fatal(err)
	}
	calls := fake.calls()
	if len(calls) != 1 || !strings.HasPrefix(calls[0], "https://apilayer.net/api/validate?") {
		t.Fatalf("provider calls = %d, want one HTTPS call", len(calls))
	}
	if !hasSource(rep, "numverify") || rep.Carrier != "Example Carrier" {
		t.Fatalf("a good answer was not applied: sources %v, carrier %q", rep.DataSources, rep.Carrier)
	}
	if reportsUnavailable(t, rep) {
		t.Fatal("a good answer was reported as unavailable")
	}
}

func TestNumverifyNeverFollowsARedirect(t *testing.T) {
	s, fake, logs := numverifyService(providerReply(http.StatusFound, "",
		"Location", "http://apilayer.net/api/validate?moved=1"))
	rep, err := s.Lookup(context.Background(), numverifyTestNumber)
	if err != nil {
		t.Fatal(err)
	}
	if got := len(fake.calls()); got != 1 {
		t.Fatalf("provider calls = %d: a redirect was followed", got)
	}
	if !reportsUnavailable(t, rep) || hasSource(rep, "numverify") {
		t.Fatalf("a redirect must report the source unavailable: %v", rep.DataSources)
	}
	assertNumverifyLogClean(t, logs)
}

func TestNumverifyRefusalReportsUnavailable(t *testing.T) {
	cases := map[string]func(*http.Request) (*http.Response, error){
		"plan without HTTPS": providerReply(http.StatusOK,
			`{"success":false,"error":{"code":105,"type":"https_access_restricted"}}`),
		"refused key":     providerReply(http.StatusUnauthorized, `{"message":"refused"}`),
		"server error":    providerReply(http.StatusBadGateway, `bad gateway`),
		"not JSON":        providerReply(http.StatusOK, `not json`),
		"answer is empty": providerReply(http.StatusOK, `{}`),
		"error status with an answer": providerReply(http.StatusInternalServerError,
			`{"valid":true,"country_code":"US","carrier":"Wrong"}`),
		"refusal with an answer": providerReply(http.StatusOK,
			`{"success":false,"valid":true,"country_code":"US","carrier":"Wrong"}`),
	}
	for name, respond := range cases {
		t.Run(name, func(t *testing.T) {
			s, _, logs := numverifyService(respond)
			rep, err := s.Lookup(context.Background(), numverifyTestNumber)
			if err != nil {
				t.Fatal(err)
			}
			if !reportsUnavailable(t, rep) {
				t.Error("lookup did not report the source unavailable")
			}
			if hasSource(rep, "numverify") {
				t.Error("a refused lookup is listed as a data source")
			}
			if !rep.IsValid || rep.CountryCode != "DE" {
				t.Errorf("a refusal changed the local result: valid=%v country=%q", rep.IsValid, rep.CountryCode)
			}
			if rep.Confidence > 0.5 {
				t.Errorf("a refusal raised confidence to %v", rep.Confidence)
			}
			assertNumverifyLogClean(t, logs)
		})
	}
}

// http.Client wraps a transport failure in a url.Error that prints the whole
// URL, query included.
func TestNumverifyTransportFailureLeaksNothing(t *testing.T) {
	s, _, logs := numverifyService(func(*http.Request) (*http.Response, error) {
		return nil, errors.New("connection refused")
	})
	rep, err := s.Lookup(context.Background(), numverifyTestNumber)
	if err != nil {
		t.Fatal(err)
	}
	if !reportsUnavailable(t, rep) {
		t.Error("lookup did not report the source unavailable")
	}
	assertNumverifyLogClean(t, logs)
	if !strings.Contains(logs.String(), "Numverify") {
		t.Error("the failure left no log line")
	}
}

func assertNumverifyLogClean(t *testing.T, logs *privacyLog) {
	t.Helper()
	text := logs.String()
	if strings.Contains(text, numverifyTestKey) {
		t.Error("the provider key reached the log")
	}
	if strings.Contains(text, numverifyTestDigits) {
		t.Error("the phone number reached the log")
	}
}

func TestScamAnalysisCarriesAnUnavailableSource(t *testing.T) {
	s, _, _ := numverifyService(providerReply(http.StatusBadGateway, `bad gateway`))
	d := newReportDetector()
	d.phoneReputation = s
	result, err := d.Analyze(context.Background(), &models.ScamAnalysisRequest{
		ID: "phone-source", Content: numverifyTestNumber,
		ContentType: models.ContentTypePhone, PhoneNumber: numverifyTestNumber,
	})
	if err != nil {
		t.Fatal(err)
	}
	raw, err := json.Marshal(result)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), `"unavailable_sources":["numverify"]`) {
		t.Fatalf("analysis does not say the source was unavailable: %s", raw)
	}
}

func llmServer(t *testing.T, status int, body string) *httptest.Server {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_, _ = io.WriteString(w, body)
	}))
	t.Cleanup(server.Close)
	return server
}

func TestProviderErrorsHoldNoResponseBody(t *testing.T) {
	messages := []Message{{Role: "user", Content: []ContentPart{{Type: "text", Text: "hello"}}}}
	cases := []struct {
		name, body, want string
		call             func(*LLMClient) error
	}{
		{"openai shape", `{"error":"` + providerBodyMarker + `"}`, "DeepSeek API error 400", func(c *LLMClient) error {
			_, err := c.callDeepSeek(context.Background(), "system", messages)
			return err
		}},
		{"content filter", `{"error":"content_filter ` + providerBodyMarker + `"}`, "content filter", func(c *LLMClient) error {
			_, err := c.callDeepSeek(context.Background(), "system", messages)
			return err
		}},
		{"claude", `{"error":"` + providerBodyMarker + `"}`, "Claude API error 400", func(c *LLMClient) error {
			_, err := c.callClaude(context.Background(), "system", messages)
			return err
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			server := llmServer(t, http.StatusBadRequest, tc.body)
			client := NewLLMClient(LLMConfig{
				Provider: "deepseek", DeepSeekAPIKey: "test-key", ClaudeAPIKey: "test-key", BaseURL: server.URL,
			}, (&privacyLog{}).logger())
			err := tc.call(client)
			if err == nil {
				t.Fatal("want an error")
			}
			if strings.Contains(err.Error(), providerBodyMarker) {
				t.Error("the provider's response body is in the error")
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Errorf("error = %q, want it to contain %q", err, tc.want)
			}
		})
	}
}

func TestTranscriptionErrorsHoldNoResponseBody(t *testing.T) {
	audio := []byte("audio")
	t.Run("azure", func(t *testing.T) {
		server := llmServer(t, http.StatusBadRequest, providerBodyMarker)
		s := NewSpeechAnalyzer((&privacyLog{}).logger(), nil, SpeechAnalyzerConfig{
			AzureOpenAIEndpoint: server.URL, AzureOpenAIKey: "test-key", AzureOpenAITranscribeDeployment: "transcribe",
		})
		_, _, _, err := s.transcribeWithAzureOpenAI(context.Background(), audio, "audio/wav")
		if err == nil || strings.Contains(err.Error(), providerBodyMarker) || !strings.Contains(err.Error(), "400") {
			t.Fatalf("error = %v", err)
		}
	})
	t.Run("openai", func(t *testing.T) {
		s := NewSpeechAnalyzer((&privacyLog{}).logger(), nil, SpeechAnalyzerConfig{OpenAIAPIKey: "test-key"})
		s.httpClient = &http.Client{Transport: &fakeProvider{
			respond: providerReply(http.StatusBadRequest, providerBodyMarker),
		}}
		_, _, _, err := s.transcribeWithOpenAI(context.Background(), audio, "audio/wav")
		if err == nil || strings.Contains(err.Error(), providerBodyMarker) || !strings.Contains(err.Error(), "400") {
			t.Fatalf("error = %v", err)
		}
	})
}
