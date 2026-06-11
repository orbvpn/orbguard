package ai

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"orbguard-lab/pkg/logger"
)

// capturedRequest records everything the LLM client sent so tests can assert
// on URL, headers and body shape per provider.
type capturedRequest struct {
	Method string
	Path   string
	Query  string
	Header http.Header
	Body   map[string]interface{}
}

// newOpenAIShapedServer returns an httptest server that captures the request
// and replies with an OpenAI-shaped chat-completions response.
func newOpenAIShapedServer(t *testing.T, captured *capturedRequest) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		captured.Method = r.Method
		captured.Path = r.URL.Path
		captured.Query = r.URL.RawQuery
		captured.Header = r.Header.Clone()
		if err := json.NewDecoder(r.Body).Decode(&captured.Body); err != nil {
			t.Errorf("failed to decode request body: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{
			"choices": [{"message": {"content": "openai-shaped reply"}, "finish_reason": "stop"}],
			"usage": {"prompt_tokens": 11, "completion_tokens": 7}
		}`))
	}))
}

// newClaudeShapedServer returns an httptest server that captures the request
// and replies with an Anthropic Messages API shaped response.
func newClaudeShapedServer(t *testing.T, captured *capturedRequest) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		captured.Method = r.Method
		captured.Path = r.URL.Path
		captured.Query = r.URL.RawQuery
		captured.Header = r.Header.Clone()
		if err := json.NewDecoder(r.Body).Decode(&captured.Body); err != nil {
			t.Errorf("failed to decode request body: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{
			"content": [{"type": "text", "text": "claude reply"}],
			"stop_reason": "end_turn",
			"usage": {"input_tokens": 13, "output_tokens": 5}
		}`))
	}))
}

func testMessages() []Message {
	return []Message{NewTextMessage("user", "is this a scam?")}
}

// assertOpenAIBodyShape verifies the shared OpenAI-compatible request body:
// model, max_tokens, temperature, and a system message followed by the user
// message with structured content parts.
func assertOpenAIBodyShape(t *testing.T, body map[string]interface{}, wantModel string, tokenParam string) {
	t.Helper()
	if got := body["model"]; got != wantModel {
		t.Errorf("body model = %v, want %s", got, wantModel)
	}
	if _, ok := body[tokenParam].(float64); !ok {
		t.Errorf("body %s missing or not a number: %v", tokenParam, body[tokenParam])
	}
	other := "max_tokens"
	if tokenParam == "max_tokens" {
		other = "max_completion_tokens"
	}
	if _, present := body[other]; present {
		t.Errorf("body must not contain %s when %s is used", other, tokenParam)
	}
	if _, ok := body["temperature"].(float64); !ok {
		t.Errorf("body temperature missing or not a number: %v", body["temperature"])
	}
	msgs, ok := body["messages"].([]interface{})
	if !ok || len(msgs) != 2 {
		t.Fatalf("body messages = %v, want system + user message", body["messages"])
	}
	sys := msgs[0].(map[string]interface{})
	if sys["role"] != "system" || sys["content"] != "system prompt" {
		t.Errorf("first message = %v, want system role with system prompt", sys)
	}
	user := msgs[1].(map[string]interface{})
	if user["role"] != "user" {
		t.Errorf("second message role = %v, want user", user["role"])
	}
	parts, ok := user["content"].([]interface{})
	if !ok || len(parts) != 1 {
		t.Fatalf("user content = %v, want one content part", user["content"])
	}
	part := parts[0].(map[string]interface{})
	if part["type"] != "text" || part["text"] != "is this a scam?" {
		t.Errorf("user content part = %v, want text part with prompt", part)
	}
}

func assertOpenAIResponseParsed(t *testing.T, resp *CompletionResponse, err error) {
	t.Helper()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.Content != "openai-shaped reply" {
		t.Errorf("response content = %q, want %q", resp.Content, "openai-shaped reply")
	}
	if resp.StopReason != "stop" {
		t.Errorf("stop reason = %q, want stop", resp.StopReason)
	}
	if resp.Usage.InputTokens != 11 || resp.Usage.OutputTokens != 7 {
		t.Errorf("usage = %+v, want input 11 / output 7", resp.Usage)
	}
}

func TestCallOpenAIRequestConstruction(t *testing.T) {
	var captured capturedRequest
	server := newOpenAIShapedServer(t, &captured)
	defer server.Close()

	client := NewLLMClient(LLMConfig{
		Provider:     "openai",
		OpenAIAPIKey: "sk-openai-test",
		BaseURL:      server.URL + "/v1",
	}, logger.NewDevelopment())

	resp, err := client.callOpenAI(context.Background(), "system prompt", testMessages())
	assertOpenAIResponseParsed(t, resp, err)

	if captured.Method != http.MethodPost {
		t.Errorf("method = %s, want POST", captured.Method)
	}
	if captured.Path != "/v1/chat/completions" {
		t.Errorf("path = %s, want /v1/chat/completions", captured.Path)
	}
	if got := captured.Header.Get("Authorization"); got != "Bearer sk-openai-test" {
		t.Errorf("Authorization header = %q, want Bearer sk-openai-test", got)
	}
	if got := captured.Header.Get("Content-Type"); got != "application/json" {
		t.Errorf("Content-Type = %q, want application/json", got)
	}
	// gpt-4-turbo is the default model for the openai provider.
	assertOpenAIBodyShape(t, captured.Body, "gpt-4-turbo", "max_completion_tokens")
}

func TestCallDeepSeekRequestConstruction(t *testing.T) {
	var captured capturedRequest
	server := newOpenAIShapedServer(t, &captured)
	defer server.Close()

	client := NewLLMClient(LLMConfig{
		Provider:       "deepseek",
		DeepSeekAPIKey: "sk-deepseek-test",
		BaseURL:        server.URL,
	}, logger.NewDevelopment())

	resp, err := client.callDeepSeek(context.Background(), "system prompt", testMessages())
	assertOpenAIResponseParsed(t, resp, err)

	if captured.Method != http.MethodPost {
		t.Errorf("method = %s, want POST", captured.Method)
	}
	// DeepSeek default base URL has no /v1 segment: {base_url}/chat/completions.
	if captured.Path != "/chat/completions" {
		t.Errorf("path = %s, want /chat/completions", captured.Path)
	}
	if got := captured.Header.Get("Authorization"); got != "Bearer sk-deepseek-test" {
		t.Errorf("Authorization header = %q, want Bearer sk-deepseek-test", got)
	}
	// deepseek-chat is the default model for the deepseek provider.
	assertOpenAIBodyShape(t, captured.Body, "deepseek-chat", "max_tokens")
}

func TestCallAzureOpenAIRequestConstruction(t *testing.T) {
	var captured capturedRequest
	server := newOpenAIShapedServer(t, &captured)
	defer server.Close()

	client := NewLLMClient(LLMConfig{
		Provider:              "azure-openai",
		AzureOpenAIEndpoint:   server.URL,
		AzureOpenAIKey:        "azure-test-key",
		AzureOpenAIDeployment: "gpt-4o-prod",
	}, logger.NewDevelopment())

	resp, err := client.callAzureOpenAI(context.Background(), "system prompt", testMessages())
	assertOpenAIResponseParsed(t, resp, err)

	if captured.Method != http.MethodPost {
		t.Errorf("method = %s, want POST", captured.Method)
	}
	if captured.Path != "/openai/deployments/gpt-4o-prod/chat/completions" {
		t.Errorf("path = %s, want /openai/deployments/gpt-4o-prod/chat/completions", captured.Path)
	}
	if captured.Query != "api-version=2024-02-15-preview" {
		t.Errorf("query = %s, want api-version=2024-02-15-preview", captured.Query)
	}
	// Azure authenticates with the api-key header, not Bearer.
	if got := captured.Header.Get("api-key"); got != "azure-test-key" {
		t.Errorf("api-key header = %q, want azure-test-key", got)
	}
	if got := captured.Header.Get("Authorization"); got != "" {
		t.Errorf("Authorization header = %q, want empty for azure-openai", got)
	}
	// With no explicit model, the deployment name is reported as the model.
	assertOpenAIBodyShape(t, captured.Body, "gpt-4o-prod", "max_completion_tokens")
}

func TestCallAzureOpenAICustomAPIVersionAndModel(t *testing.T) {
	var captured capturedRequest
	server := newOpenAIShapedServer(t, &captured)
	defer server.Close()

	client := NewLLMClient(LLMConfig{
		Provider:              "azure-openai",
		AzureOpenAIEndpoint:   server.URL + "/", // trailing slash must be trimmed
		AzureOpenAIKey:        "azure-test-key",
		AzureOpenAIDeployment: "gpt-4o-prod",
		AzureOpenAIAPIVersion: "2024-06-01",
		Model:                 "gpt-4o",
	}, logger.NewDevelopment())

	_, err := client.callAzureOpenAI(context.Background(), "system prompt", testMessages())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if captured.Path != "/openai/deployments/gpt-4o-prod/chat/completions" {
		t.Errorf("path = %s, want /openai/deployments/gpt-4o-prod/chat/completions", captured.Path)
	}
	if captured.Query != "api-version=2024-06-01" {
		t.Errorf("query = %s, want api-version=2024-06-01", captured.Query)
	}
	if got := captured.Body["model"]; got != "gpt-4o" {
		t.Errorf("body model = %v, want gpt-4o", got)
	}
}

func TestReasoningEffortSentForAzureOpenAI(t *testing.T) {
	var captured capturedRequest
	server := newOpenAIShapedServer(t, &captured)
	defer server.Close()

	client := NewLLMClient(LLMConfig{
		Provider:              "azure-openai",
		AzureOpenAIEndpoint:   server.URL,
		AzureOpenAIKey:        "azure-test-key",
		AzureOpenAIDeployment: "orbguard-scam",
		ReasoningEffort:       "low",
	}, logger.NewDevelopment())

	resp, err := client.callAzureOpenAI(context.Background(), "system prompt", testMessages())
	assertOpenAIResponseParsed(t, resp, err)

	if got := captured.Body["reasoning_effort"]; got != "low" {
		t.Errorf("body reasoning_effort = %v, want low", got)
	}
}

func TestReasoningEffortSentForOpenAI(t *testing.T) {
	var captured capturedRequest
	server := newOpenAIShapedServer(t, &captured)
	defer server.Close()

	client := NewLLMClient(LLMConfig{
		Provider:        "openai",
		OpenAIAPIKey:    "sk-openai-test",
		BaseURL:         server.URL + "/v1",
		ReasoningEffort: "medium",
	}, logger.NewDevelopment())

	resp, err := client.callOpenAI(context.Background(), "system prompt", testMessages())
	assertOpenAIResponseParsed(t, resp, err)

	if got := captured.Body["reasoning_effort"]; got != "medium" {
		t.Errorf("body reasoning_effort = %v, want medium", got)
	}
}

func TestReasoningEffortNotSentForDeepSeek(t *testing.T) {
	var captured capturedRequest
	server := newOpenAIShapedServer(t, &captured)
	defer server.Close()

	client := NewLLMClient(LLMConfig{
		Provider:        "deepseek",
		DeepSeekAPIKey:  "sk-deepseek-test",
		BaseURL:         server.URL,
		ReasoningEffort: "low",
	}, logger.NewDevelopment())

	resp, err := client.callDeepSeek(context.Background(), "system prompt", testMessages())
	assertOpenAIResponseParsed(t, resp, err)

	if _, present := captured.Body["reasoning_effort"]; present {
		t.Errorf("body must not contain reasoning_effort for deepseek, got %v", captured.Body["reasoning_effort"])
	}
}

func TestReasoningEffortOmittedWhenUnset(t *testing.T) {
	var captured capturedRequest
	server := newOpenAIShapedServer(t, &captured)
	defer server.Close()

	client := NewLLMClient(LLMConfig{
		Provider:              "azure-openai",
		AzureOpenAIEndpoint:   server.URL,
		AzureOpenAIKey:        "azure-test-key",
		AzureOpenAIDeployment: "orbguard-scam",
	}, logger.NewDevelopment())

	resp, err := client.callAzureOpenAI(context.Background(), "system prompt", testMessages())
	assertOpenAIResponseParsed(t, resp, err)

	if _, present := captured.Body["reasoning_effort"]; present {
		t.Errorf("body must not contain reasoning_effort when not configured, got %v", captured.Body["reasoning_effort"])
	}
}

func TestReasoningEffortStripRetry(t *testing.T) {
	var bodies []map[string]interface{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]interface{}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Errorf("failed to decode request body: %v", err)
		}
		bodies = append(bodies, body)
		w.Header().Set("Content-Type", "application/json")
		if len(bodies) == 1 {
			// First call: deployment rejects reasoning_effort.
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(`{"error": {"code": "unsupported_parameter", "message": "Unsupported parameter: 'reasoning_effort' is not supported with this model.", "param": "reasoning_effort", "type": "invalid_request_error"}}`))
			return
		}
		_, _ = w.Write([]byte(`{
			"choices": [{"message": {"content": "openai-shaped reply"}, "finish_reason": "stop"}],
			"usage": {"prompt_tokens": 11, "completion_tokens": 7}
		}`))
	}))
	defer server.Close()

	client := NewLLMClient(LLMConfig{
		Provider:              "azure-openai",
		AzureOpenAIEndpoint:   server.URL,
		AzureOpenAIKey:        "azure-test-key",
		AzureOpenAIDeployment: "orbguard-scam",
		ReasoningEffort:       "low",
	}, logger.NewDevelopment())

	resp, err := client.callAzureOpenAI(context.Background(), "system prompt", testMessages())
	assertOpenAIResponseParsed(t, resp, err)

	if len(bodies) != 2 {
		t.Fatalf("got %d requests, want 2 (initial + strip-retry)", len(bodies))
	}
	if got := bodies[0]["reasoning_effort"]; got != "low" {
		t.Errorf("first request reasoning_effort = %v, want low", got)
	}
	if _, present := bodies[1]["reasoning_effort"]; present {
		t.Errorf("retry request must not contain reasoning_effort, got %v", bodies[1]["reasoning_effort"])
	}
	// The retry keeps the rest of the body intact.
	if _, ok := bodies[1]["max_completion_tokens"].(float64); !ok {
		t.Errorf("retry request max_completion_tokens missing: %v", bodies[1]["max_completion_tokens"])
	}
	if _, ok := bodies[1]["temperature"].(float64); !ok {
		t.Errorf("retry request temperature missing: %v", bodies[1]["temperature"])
	}
}

func TestCallAzureOpenAIMissingConfig(t *testing.T) {
	client := NewLLMClient(LLMConfig{
		Provider:       "azure-openai",
		AzureOpenAIKey: "azure-test-key",
	}, logger.NewDevelopment())

	if _, err := client.callAzureOpenAI(context.Background(), "system prompt", testMessages()); err == nil {
		t.Fatal("expected error when azure endpoint/deployment are missing, got nil")
	}
}

func TestCallClaudeRequestConstruction(t *testing.T) {
	var captured capturedRequest
	server := newClaudeShapedServer(t, &captured)
	defer server.Close()

	client := NewLLMClient(LLMConfig{
		Provider:     "claude",
		ClaudeAPIKey: "sk-ant-test",
		BaseURL:      server.URL,
	}, logger.NewDevelopment())

	resp, err := client.callClaude(context.Background(), "system prompt", testMessages())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.Content != "claude reply" {
		t.Errorf("response content = %q, want %q", resp.Content, "claude reply")
	}
	if resp.StopReason != "end_turn" {
		t.Errorf("stop reason = %q, want end_turn", resp.StopReason)
	}
	if resp.Usage.InputTokens != 13 || resp.Usage.OutputTokens != 5 {
		t.Errorf("usage = %+v, want input 13 / output 5", resp.Usage)
	}

	if captured.Method != http.MethodPost {
		t.Errorf("method = %s, want POST", captured.Method)
	}
	if captured.Path != "/v1/messages" {
		t.Errorf("path = %s, want /v1/messages", captured.Path)
	}
	if got := captured.Header.Get("x-api-key"); got != "sk-ant-test" {
		t.Errorf("x-api-key header = %q, want sk-ant-test", got)
	}
	if got := captured.Header.Get("anthropic-version"); got != "2023-06-01" {
		t.Errorf("anthropic-version header = %q, want 2023-06-01", got)
	}
	if got := captured.Header.Get("Authorization"); got != "" {
		t.Errorf("Authorization header = %q, want empty for claude", got)
	}

	// Claude body shape: system is a top-level field, messages have no
	// system entry.
	if got := captured.Body["model"]; got != "claude-3-sonnet-20240229" {
		t.Errorf("body model = %v, want claude-3-sonnet-20240229", got)
	}
	if got := captured.Body["system"]; got != "system prompt" {
		t.Errorf("body system = %v, want system prompt", got)
	}
	msgs, ok := captured.Body["messages"].([]interface{})
	if !ok || len(msgs) != 1 {
		t.Fatalf("body messages = %v, want exactly one user message", captured.Body["messages"])
	}
	user := msgs[0].(map[string]interface{})
	if user["role"] != "user" {
		t.Errorf("message role = %v, want user", user["role"])
	}
	parts, ok := user["content"].([]interface{})
	if !ok || len(parts) != 1 {
		t.Fatalf("message content = %v, want one content part", user["content"])
	}
	part := parts[0].(map[string]interface{})
	if part["type"] != "text" || part["text"] != "is this a scam?" {
		t.Errorf("content part = %v, want text part with prompt", part)
	}
}

func TestChatDispatchesByProvider(t *testing.T) {
	var captured capturedRequest
	server := newOpenAIShapedServer(t, &captured)
	defer server.Close()

	client := NewLLMClient(LLMConfig{
		Provider:       "deepseek",
		DeepSeekAPIKey: "sk-deepseek-test",
		BaseURL:        server.URL,
	}, logger.NewDevelopment())

	content, err := client.Chat(context.Background(), testMessages(), "system prompt")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if content != "openai-shaped reply" {
		t.Errorf("chat content = %q, want %q", content, "openai-shaped reply")
	}
	if captured.Path != "/chat/completions" {
		t.Errorf("path = %s, want /chat/completions", captured.Path)
	}
}

func TestChatUnsupportedProvider(t *testing.T) {
	client := NewLLMClient(LLMConfig{Provider: "gemini"}, logger.NewDevelopment())
	if _, err := client.Chat(context.Background(), testMessages(), "system prompt"); err == nil {
		t.Fatal("expected error for unsupported provider, got nil")
	}
}

func TestProviderErrorIncludesProviderName(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, `{"error": "rate limited"}`, http.StatusTooManyRequests)
	}))
	defer server.Close()

	client := NewLLMClient(LLMConfig{
		Provider:       "deepseek",
		DeepSeekAPIKey: "sk-deepseek-test",
		BaseURL:        server.URL,
	}, logger.NewDevelopment())

	_, err := client.callDeepSeek(context.Background(), "system prompt", testMessages())
	if err == nil {
		t.Fatal("expected error for non-200 response, got nil")
	}
	if want := "DeepSeek API error 429"; !strings.Contains(err.Error(), want) {
		t.Errorf("error = %q, want it to contain %q", err.Error(), want)
	}
}

func TestDefaultModelForProvider(t *testing.T) {
	cases := map[string]string{
		"claude":       "claude-3-sonnet-20240229",
		"openai":       "gpt-4-turbo",
		"deepseek":     "deepseek-chat",
		"azure-openai": "",
		"unknown":      "gpt-4-turbo",
	}
	for provider, want := range cases {
		if got := DefaultModelForProvider(provider); got != want {
			t.Errorf("DefaultModelForProvider(%q) = %q, want %q", provider, got, want)
		}
	}
}
