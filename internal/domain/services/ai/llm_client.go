package ai

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/pkg/logger"
)

// LLMClient provides access to large language model APIs
type LLMClient struct {
	httpClient   *http.Client
	logger       *logger.Logger
	config       LLMConfig

	// Content-filter circuit breaker: some deployments (Azure default
	// Responsible-AI policy) reject scam/phishing content under analysis as
	// if it were an attack prompt. After repeated rejections the LLM path is
	// paused so requests stay fast on the rule-based engines instead of
	// burning latency on calls that will be blocked.
	breakerMu            sync.Mutex
	contentFilterStrikes int
	llmDisabledUntil     time.Time
}

// contentFilterStrikeLimit and contentFilterCooldown govern the breaker. The
// cooldown is short so the LLM path self-heals quickly after a transient
// slowdown or a deploy; a persistent block (e.g. a content-filter policy) just
// re-trips it on the next batch of requests.
const (
	contentFilterStrikeLimit = 3
	contentFilterCooldown    = 3 * time.Minute
)

// ErrLLMTemporarilyDisabled is returned while the content-filter breaker is open.
var ErrLLMTemporarilyDisabled = fmt.Errorf("llm temporarily disabled: deployment content filter repeatedly blocked analysis prompts")

func (c *LLMClient) breakerOpen() bool {
	c.breakerMu.Lock()
	defer c.breakerMu.Unlock()
	return time.Now().Before(c.llmDisabledUntil)
}

func (c *LLMClient) recordContentFilter() {
	c.recordStrike("content filter blocked repeated analysis prompts; pausing LLM calls (request a Responsible-AI filter exemption or switch llm_provider)")
}

// recordTimeout counts provider timeouts toward the same breaker: a
// deployment that cannot answer within the per-call budget degrades every
// request identically to one that rejects them.
func (c *LLMClient) recordTimeout() {
	c.recordStrike("provider repeatedly exceeded the per-call timeout; pausing LLM calls (deployment too slow for interactive analysis)")
}

func (c *LLMClient) recordStrike(reason string) {
	c.breakerMu.Lock()
	defer c.breakerMu.Unlock()
	c.contentFilterStrikes++
	if c.contentFilterStrikes >= contentFilterStrikeLimit {
		c.llmDisabledUntil = time.Now().Add(contentFilterCooldown)
		c.contentFilterStrikes = 0
		if c.logger != nil {
			c.logger.Warn().
				Str("provider", c.config.Provider).
				Dur("cooldown", contentFilterCooldown).
				Msg(reason)
		}
	}
}

func (c *LLMClient) recordLLMSuccess() {
	c.breakerMu.Lock()
	defer c.breakerMu.Unlock()
	c.contentFilterStrikes = 0
}

// LLMConfig holds LLM client configuration
type LLMConfig struct {
	Provider       string  // claude, openai, deepseek, azure-openai
	ClaudeAPIKey   string
	OpenAIAPIKey   string
	DeepSeekAPIKey string
	// Azure OpenAI settings (used only when Provider == "azure-openai").
	AzureOpenAIEndpoint   string // e.g. https://my-resource.openai.azure.com
	AzureOpenAIKey        string
	AzureOpenAIDeployment string
	AzureOpenAIAPIVersion string // defaults to 2024-02-15-preview
	// BaseURL overrides the provider's default API base URL
	// (claude, openai and deepseek paths; Azure uses AzureOpenAIEndpoint).
	BaseURL        string
	Model          string  // claude-3-sonnet-20240229, gpt-4-turbo, deepseek-chat, etc.
	// ReasoningEffort, when non-empty, is sent as the "reasoning_effort"
	// chat-completions parameter for reasoning-capable OpenAI/Azure OpenAI
	// deployments (GPT-5.x, o-series). Empty omits the parameter. It is never
	// sent to DeepSeek or Claude.
	ReasoningEffort string
	Temperature    float64
	MaxTokens      int
	VisionEnabled  bool
	SystemPrompt   string
	Timeout        time.Duration
}

// DefaultModelForProvider returns the default model used when no explicit
// model is configured for the given provider. For azure-openai the model is
// implied by the deployment, so there is no provider-level default.
func DefaultModelForProvider(provider string) string {
	switch provider {
	case "claude":
		return "claude-3-sonnet-20240229"
	case "deepseek":
		return "deepseek-chat"
	case "azure-openai":
		return ""
	default:
		return "gpt-4-turbo"
	}
}

// NewLLMClient creates a new LLM client
func NewLLMClient(cfg LLMConfig, log *logger.Logger) *LLMClient {
	if cfg.Timeout == 0 {
		// Scam analysis runs intent + entity (parallel) plus an optional deep
		// pass per request behind an ingress that resets slow responses. The
		// budget must cover a cross-region hop plus generation; paired with the
		// capped MaxTokens below this keeps interactive requests responsive.
		cfg.Timeout = 18 * time.Second
	}
	if cfg.Temperature == 0 {
		cfg.Temperature = 0.3 // Low temperature for factual analysis
	}
	if cfg.MaxTokens == 0 {
		// Scam analyses return compact structured JSON; a large ceiling only
		// lets a verbose model run long enough to blow the timeout. 1024 tokens
		// comfortably holds every analysis schema while keeping latency low.
		cfg.MaxTokens = 1024
	}
	if cfg.AzureOpenAIAPIVersion == "" {
		cfg.AzureOpenAIAPIVersion = "2024-02-15-preview"
	}
	if cfg.Model == "" {
		cfg.Model = DefaultModelForProvider(cfg.Provider)
		if cfg.Provider == "azure-openai" {
			// Azure selects the model via the deployment; record it so
			// analysis results report which model was used.
			cfg.Model = cfg.AzureOpenAIDeployment
		}
	}

	return &LLMClient{
		httpClient: &http.Client{
			Timeout: cfg.Timeout,
		},
		logger: log.WithComponent("llm-client"),
		config: cfg,
	}
}

// Message represents a chat message
type Message struct {
	Role    string        `json:"role"`
	Content []ContentPart `json:"content"`
}

// ContentPart represents a part of message content (text or image)
type ContentPart struct {
	Type      string       `json:"type"`
	Text      string       `json:"text,omitempty"`
	ImageURL  *ImageURL    `json:"image_url,omitempty"`  // OpenAI format
	Source    *ImageSource `json:"source,omitempty"`     // Claude format
}

// ImageURL for OpenAI format
type ImageURL struct {
	URL    string `json:"url"`
	Detail string `json:"detail,omitempty"` // low, high, auto
}

// ImageSource for Claude format
type ImageSource struct {
	Type      string `json:"type"` // base64
	MediaType string `json:"media_type"`
	Data      string `json:"data"`
}

// CompletionRequest represents a completion request
type CompletionRequest struct {
	Messages    []Message `json:"messages"`
	System      string    `json:"system,omitempty"`
	MaxTokens   int       `json:"max_tokens"`
	Temperature float64   `json:"temperature"`
	Model       string    `json:"model"`
}

// CompletionResponse represents a completion response
type CompletionResponse struct {
	Content    string `json:"content"`
	StopReason string `json:"stop_reason"`
	Usage      struct {
		InputTokens  int `json:"input_tokens"`
		OutputTokens int `json:"output_tokens"`
	} `json:"usage"`
}

// AnalyzeForScam sends content to LLM for scam analysis
func (c *LLMClient) AnalyzeForScam(ctx context.Context, req *models.ScamAnalysisRequest) (*LLMScamAnalysis, error) {
	startTime := time.Now()

	// Build the prompt
	systemPrompt := c.getScamDetectionSystemPrompt()
	userPrompt := c.buildScamAnalysisPrompt(req)

	// Prepare messages
	messages := []Message{
		{
			Role: "user",
			Content: []ContentPart{
				{Type: "text", Text: userPrompt},
			},
		},
	}

	// Add image if present
	if len(req.ImageData) > 0 && c.config.VisionEnabled {
		mediaType := "image/png"
		if isJPEG(req.ImageData) {
			mediaType = "image/jpeg"
		}

		imageContent := ContentPart{
			Type: "image",
		}

		if c.config.Provider == "claude" {
			imageContent.Source = &ImageSource{
				Type:      "base64",
				MediaType: mediaType,
				Data:      base64.StdEncoding.EncodeToString(req.ImageData),
			}
		} else {
			// OpenAI format
			imageContent.Type = "image_url"
			imageContent.ImageURL = &ImageURL{
				URL:    fmt.Sprintf("data:%s;base64,%s", mediaType, base64.StdEncoding.EncodeToString(req.ImageData)),
				Detail: "high",
			}
		}

		messages[0].Content = append(messages[0].Content, imageContent)
	}

	if c.breakerOpen() {
		return nil, ErrLLMTemporarilyDisabled
	}

	// Make the API call
	var response *CompletionResponse
	var err error

	switch c.config.Provider {
	case "claude":
		response, err = c.callClaude(ctx, systemPrompt, messages)
	case "openai":
		response, err = c.callOpenAI(ctx, systemPrompt, messages)
	case "deepseek":
		response, err = c.callDeepSeek(ctx, systemPrompt, messages)
	case "azure-openai":
		response, err = c.callAzureOpenAI(ctx, systemPrompt, messages)
	default:
		return nil, fmt.Errorf("unsupported LLM provider: %s", c.config.Provider)
	}

	if err != nil {
		return nil, err
	}

	// Parse the response
	analysis, err := c.parseLLMResponse(response.Content)
	if err != nil {
		c.logger.Warn().Err(err).Msg("failed to parse LLM response, returning raw")
		analysis = &LLMScamAnalysis{
			RawResponse: response.Content,
		}
	}

	analysis.ProcessingTime = time.Since(startTime).String()
	analysis.ModelUsed = c.config.Model
	analysis.TokensUsed = response.Usage.InputTokens + response.Usage.OutputTokens

	return analysis, nil
}

// LLMScamAnalysis represents the parsed LLM analysis
type LLMScamAnalysis struct {
	IsScam          bool                    `json:"is_scam"`
	Confidence      float64                 `json:"confidence"`
	ScamType        models.ScamType         `json:"scam_type"`
	Severity        models.ScamSeverity     `json:"severity"`
	Explanation     string                  `json:"explanation"`
	RedFlags        []string                `json:"red_flags"`
	Indicators      []models.ScamIndicator  `json:"indicators"`
	SafetyTips      []string                `json:"safety_tips"`
	Intent          string                  `json:"intent"`
	ManipulationTactics []string            `json:"manipulation_tactics"`
	RawResponse     string                  `json:"raw_response,omitempty"`
	ProcessingTime  string                  `json:"processing_time"`
	ModelUsed       string                  `json:"model_used"`
	TokensUsed      int                     `json:"tokens_used"`
}

// getScamDetectionSystemPrompt returns the system prompt for scam detection
func (c *LLMClient) getScamDetectionSystemPrompt() string {
	return `You are an expert scam detection AI assistant. Your role is to analyze messages, images, URLs, and other content to identify potential scams, fraud, and phishing attempts.

## Your Expertise Includes:
- Phishing and social engineering detection
- Financial scam patterns (advance fee fraud, investment scams, crypto scams)
- Romance/dating scams
- Tech support scams
- Impersonation scams (CEO fraud, government impersonation)
- Job offer scams
- Prize/lottery scams
- Multi-language scam detection (Arabic, Persian, Hindi, Chinese, etc.)

## Analysis Guidelines:
1. Look for urgency tactics ("Act now!", "Limited time!")
2. Check for emotional manipulation (fear, greed, romance)
3. Identify requests for money, gift cards, or cryptocurrency
4. Spot grammatical errors and awkward phrasing
5. Recognize impersonation of trusted brands/authorities
6. Detect suspicious URLs and domains
7. Identify requests for personal/financial information

## Response Format:
Respond in valid JSON format with this structure:
{
  "is_scam": boolean,
  "confidence": 0.0-1.0,
  "scam_type": "phishing|advance_fee|romance|tech_support|investment|impersonation|job_offer|shipping|tax_refund|prize_winning|banking|crypto|sextortion|other|none",
  "severity": "critical|high|medium|low|none",
  "explanation": "Brief explanation of why this is or isn't a scam",
  "red_flags": ["list of red flags found"],
  "safety_tips": ["actionable safety advice"],
  "intent": "The apparent intent of the message",
  "manipulation_tactics": ["psychological tactics used"]
}

Be thorough but concise. When in doubt, err on the side of caution.`
}

// buildScamAnalysisPrompt builds the user prompt for scam analysis
func (c *LLMClient) buildScamAnalysisPrompt(req *models.ScamAnalysisRequest) string {
	var sb strings.Builder

	sb.WriteString("Analyze the following content for potential scam or fraud:\n\n")

	// Content type
	sb.WriteString(fmt.Sprintf("**Content Type:** %s\n", req.ContentType))

	// Source
	if req.Source != "" {
		sb.WriteString(fmt.Sprintf("**Source:** %s\n", req.Source))
	}

	// Sender info
	if req.SenderInfo != nil {
		sb.WriteString("\n**Sender Information:**\n")
		if req.SenderInfo.PhoneNumber != "" {
			sb.WriteString(fmt.Sprintf("- Phone: %s\n", req.SenderInfo.PhoneNumber))
		}
		if req.SenderInfo.Email != "" {
			sb.WriteString(fmt.Sprintf("- Email: %s\n", req.SenderInfo.Email))
		}
		if req.SenderInfo.DisplayName != "" {
			sb.WriteString(fmt.Sprintf("- Name: %s\n", req.SenderInfo.DisplayName))
		}
		if req.SenderInfo.Country != "" {
			sb.WriteString(fmt.Sprintf("- Country: %s\n", req.SenderInfo.Country))
		}
		sb.WriteString(fmt.Sprintf("- Is Contact: %v\n", req.SenderInfo.IsContact))
	}

	// Main content
	sb.WriteString("\n**Content to Analyze:**\n```\n")
	sb.WriteString(req.Content)
	sb.WriteString("\n```\n")

	// URL if present
	if req.URL != "" {
		sb.WriteString(fmt.Sprintf("\n**URL:** %s\n", req.URL))
	}

	// Context
	if req.Context != "" {
		sb.WriteString(fmt.Sprintf("\n**Additional Context:** %s\n", req.Context))
	}

	// Language hint
	if req.Language != "" {
		sb.WriteString(fmt.Sprintf("\n**Language:** %s\n", req.Language))
	}

	sb.WriteString("\nProvide your analysis in JSON format.")

	return sb.String()
}

// callClaude makes a request to Claude API
func (c *LLMClient) callClaude(ctx context.Context, system string, messages []Message) (*CompletionResponse, error) {
	base := c.config.BaseURL
	if base == "" {
		base = "https://api.anthropic.com"
	}
	url := strings.TrimRight(base, "/") + "/v1/messages"

	// Convert messages to Claude format
	claudeMessages := make([]map[string]interface{}, len(messages))
	for i, msg := range messages {
		content := make([]map[string]interface{}, len(msg.Content))
		for j, part := range msg.Content {
			switch part.Type {
			case "text":
				content[j] = map[string]interface{}{
					"type": "text",
					"text": part.Text,
				}
			case "image":
				if part.Source != nil {
					content[j] = map[string]interface{}{
						"type": "image",
						"source": map[string]string{
							"type":       part.Source.Type,
							"media_type": part.Source.MediaType,
							"data":       part.Source.Data,
						},
					}
				}
			}
		}
		claudeMessages[i] = map[string]interface{}{
			"role":    msg.Role,
			"content": content,
		}
	}

	reqBody := map[string]interface{}{
		"model":       c.config.Model,
		"max_tokens":  c.config.MaxTokens,
		"temperature": c.config.Temperature,
		"system":      system,
		"messages":    claudeMessages,
	}

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(jsonBody))
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", c.config.ClaudeAPIKey)
	req.Header.Set("anthropic-version", "2023-06-01")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Claude API error %d: %s", resp.StatusCode, string(body))
	}

	// Parse Claude response
	var claudeResp struct {
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
		StopReason string `json:"stop_reason"`
		Usage      struct {
			InputTokens  int `json:"input_tokens"`
			OutputTokens int `json:"output_tokens"`
		} `json:"usage"`
	}

	if err := json.Unmarshal(body, &claudeResp); err != nil {
		return nil, err
	}

	var content string
	for _, c := range claudeResp.Content {
		if c.Type == "text" {
			content += c.Text
		}
	}

	return &CompletionResponse{
		Content:    content,
		StopReason: claudeResp.StopReason,
		Usage: struct {
			InputTokens  int `json:"input_tokens"`
			OutputTokens int `json:"output_tokens"`
		}{
			InputTokens:  claudeResp.Usage.InputTokens,
			OutputTokens: claudeResp.Usage.OutputTokens,
		},
	}, nil
}

// callOpenAI makes a request to the OpenAI API.
func (c *LLMClient) callOpenAI(ctx context.Context, system string, messages []Message) (*CompletionResponse, error) {
	base := c.config.BaseURL
	if base == "" {
		base = "https://api.openai.com/v1"
	}
	url := strings.TrimRight(base, "/") + "/chat/completions"
	headers := map[string]string{"Authorization": "Bearer " + c.config.OpenAIAPIKey}
	return c.callOpenAICompatible(ctx, system, messages, url, headers, "OpenAI")
}

// callDeepSeek makes a request to the DeepSeek API, which is OpenAI-compatible.
func (c *LLMClient) callDeepSeek(ctx context.Context, system string, messages []Message) (*CompletionResponse, error) {
	base := c.config.BaseURL
	if base == "" {
		base = "https://api.deepseek.com"
	}
	url := strings.TrimRight(base, "/") + "/chat/completions"
	headers := map[string]string{"Authorization": "Bearer " + c.config.DeepSeekAPIKey}
	return c.callOpenAICompatible(ctx, system, messages, url, headers, "DeepSeek")
}

// callAzureOpenAI makes a request to an Azure OpenAI deployment. Azure uses
// the OpenAI-shaped request/response body but authenticates with an "api-key"
// header (not Bearer) and addresses the model via the deployment in the URL.
func (c *LLMClient) callAzureOpenAI(ctx context.Context, system string, messages []Message) (*CompletionResponse, error) {
	if c.config.AzureOpenAIEndpoint == "" || c.config.AzureOpenAIDeployment == "" {
		return nil, fmt.Errorf("azure-openai provider requires endpoint and deployment to be configured")
	}
	endpoint := strings.TrimRight(c.config.AzureOpenAIEndpoint, "/")
	requestURL := fmt.Sprintf(
		"%s/openai/deployments/%s/chat/completions?api-version=%s",
		endpoint,
		url.PathEscape(c.config.AzureOpenAIDeployment),
		url.QueryEscape(c.config.AzureOpenAIAPIVersion),
	)
	headers := map[string]string{"api-key": c.config.AzureOpenAIKey}
	return c.callOpenAICompatible(ctx, system, messages, requestURL, headers, "Azure OpenAI")
}

// callOpenAICompatible makes a chat-completions request to any
// OpenAI-compatible endpoint (OpenAI, DeepSeek, Azure OpenAI) with
// provider-specific URL and auth headers.
func (c *LLMClient) callOpenAICompatible(ctx context.Context, system string, messages []Message, requestURL string, headers map[string]string, providerName string) (*CompletionResponse, error) {
	// Convert messages to OpenAI format
	openAIMessages := []map[string]interface{}{
		{
			"role":    "system",
			"content": system,
		},
	}

	for _, msg := range messages {
		content := make([]map[string]interface{}, len(msg.Content))
		for j, part := range msg.Content {
			switch part.Type {
			case "text":
				content[j] = map[string]interface{}{
					"type": "text",
					"text": part.Text,
				}
			case "image_url":
				if part.ImageURL != nil {
					content[j] = map[string]interface{}{
						"type": "image_url",
						"image_url": map[string]string{
							"url":    part.ImageURL.URL,
							"detail": part.ImageURL.Detail,
						},
					}
				}
			}
		}
		openAIMessages = append(openAIMessages, map[string]interface{}{
			"role":    msg.Role,
			"content": content,
		})
	}

	reqBody := map[string]interface{}{
		"model":       c.config.Model,
		"temperature": c.config.Temperature,
		"messages":    openAIMessages,
	}
	// OpenAI and Azure OpenAI replaced max_tokens with max_completion_tokens
	// (newer model families reject the legacy parameter outright). DeepSeek's
	// OpenAI-compatible API still uses max_tokens.
	if strings.EqualFold(providerName, "deepseek") {
		reqBody["max_tokens"] = c.config.MaxTokens
	} else {
		reqBody["max_completion_tokens"] = c.config.MaxTokens
	}
	// reasoning_effort is only understood by OpenAI and Azure OpenAI
	// reasoning-capable deployments; DeepSeek rejects unknown parameters.
	if c.config.ReasoningEffort != "" &&
		(strings.EqualFold(providerName, "openai") || strings.EqualFold(providerName, "azure openai")) {
		reqBody["reasoning_effort"] = c.config.ReasoningEffort
	}

	doRequest := func(payload map[string]interface{}) (int, []byte, error) {
		jsonBody, err := json.Marshal(payload)
		if err != nil {
			return 0, nil, err
		}
		req, err := http.NewRequestWithContext(ctx, "POST", requestURL, bytes.NewBuffer(jsonBody))
		if err != nil {
			return 0, nil, err
		}
		req.Header.Set("Content-Type", "application/json")
		for k, v := range headers {
			req.Header.Set(k, v)
		}
		resp, err := c.httpClient.Do(req)
		if err != nil {
			return 0, nil, err
		}
		defer resp.Body.Close()
		body, err := io.ReadAll(resp.Body)
		if err != nil {
			return resp.StatusCode, nil, err
		}
		return resp.StatusCode, body, nil
	}

	status, body, err := doRequest(reqBody)
	if err != nil {
		if isTimeoutErr(err) {
			c.recordTimeout()
		}
		return nil, err
	}
	// Some deployments reject parameters the family normally accepts: reasoning
	// models (GPT-5.x) require the default temperature, non-reasoning models
	// reject reasoning_effort, legacy models reject max_completion_tokens.
	// Adapt to whichever parameter the 400 names and retry, up to a few times
	// so multiple offending parameters are stripped in sequence.
	for attempt := 0; attempt < 3 && status == http.StatusBadRequest && isAdjustableParamError(string(body)); attempt++ {
		retryBody := make(map[string]interface{}, len(reqBody))
		for k, v := range reqBody {
			retryBody[k] = v
		}
		bodyStr := string(body)
		if strings.Contains(bodyStr, "temperature") {
			// Reasoning models accept only the default (1); send that
			// explicitly rather than dropping it so deployments that require
			// the field present still succeed.
			retryBody["temperature"] = 1
		}
		if strings.Contains(bodyStr, "reasoning_effort") {
			delete(retryBody, "reasoning_effort")
		}
		if strings.Contains(bodyStr, "max_completion_tokens") {
			delete(retryBody, "max_completion_tokens")
			retryBody["max_tokens"] = c.config.MaxTokens
		} else if strings.Contains(bodyStr, "max_tokens") {
			delete(retryBody, "max_tokens")
			retryBody["max_completion_tokens"] = c.config.MaxTokens
		}
		// Carry the adapted body forward so the next iteration keeps the fix.
		reqBody = retryBody
		status, body, err = doRequest(retryBody)
		if err != nil {
			if isTimeoutErr(err) {
				c.recordTimeout()
			}
			return nil, err
		}
	}

	if status != http.StatusOK {
		if strings.Contains(string(body), "content_filter") || strings.Contains(string(body), "ResponsibleAIPolicyViolation") {
			// Azure's default Responsible-AI filter flags scam/phishing
			// content being ANALYZED as if it were an attack prompt. This is
			// a deployment-policy limitation, not a transient error.
			c.recordContentFilter()
			return nil, fmt.Errorf("%s content filter blocked the analysis prompt (deployment policy; request a Responsible-AI filter exemption for security-analysis use cases or switch llm_provider): %d: %s", providerName, status, string(body))
		}
		return nil, fmt.Errorf("%s API error %d: %s", providerName, status, string(body))
	}
	c.recordLLMSuccess()

	// Parse OpenAI response
	var openAIResp struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
			FinishReason string `json:"finish_reason"`
		} `json:"choices"`
		Usage struct {
			PromptTokens     int `json:"prompt_tokens"`
			CompletionTokens int `json:"completion_tokens"`
		} `json:"usage"`
	}

	if err := json.Unmarshal(body, &openAIResp); err != nil {
		return nil, err
	}

	if len(openAIResp.Choices) == 0 {
		return nil, fmt.Errorf("no response from %s", providerName)
	}

	return &CompletionResponse{
		Content:    openAIResp.Choices[0].Message.Content,
		StopReason: openAIResp.Choices[0].FinishReason,
		Usage: struct {
			InputTokens  int `json:"input_tokens"`
			OutputTokens int `json:"output_tokens"`
		}{
			InputTokens:  openAIResp.Usage.PromptTokens,
			OutputTokens: openAIResp.Usage.CompletionTokens,
		},
	}, nil
}

// parseLLMResponse parses the JSON response from the LLM
func (c *LLMClient) parseLLMResponse(content string) (*LLMScamAnalysis, error) {
	// Try to extract JSON from the response
	content = strings.TrimSpace(content)

	// Handle markdown code blocks
	if strings.HasPrefix(content, "```json") {
		content = strings.TrimPrefix(content, "```json")
		content = strings.TrimSuffix(content, "```")
		content = strings.TrimSpace(content)
	} else if strings.HasPrefix(content, "```") {
		content = strings.TrimPrefix(content, "```")
		content = strings.TrimSuffix(content, "```")
		content = strings.TrimSpace(content)
	}

	// Find JSON in response
	startIdx := strings.Index(content, "{")
	endIdx := strings.LastIndex(content, "}")
	if startIdx != -1 && endIdx != -1 && endIdx > startIdx {
		content = content[startIdx : endIdx+1]
	}

	var analysis LLMScamAnalysis
	if err := json.Unmarshal([]byte(content), &analysis); err != nil {
		return nil, fmt.Errorf("failed to parse JSON: %w", err)
	}

	return &analysis, nil
}

// NewTextMessage creates a simple text message
func NewTextMessage(role, text string) Message {
	return Message{
		Role: role,
		Content: []ContentPart{
			{Type: "text", Text: text},
		},
	}
}

// Chat sends a chat message and returns the response
func (c *LLMClient) Chat(ctx context.Context, messages []Message, system string) (string, error) {
	if c.breakerOpen() {
		return "", ErrLLMTemporarilyDisabled
	}
	if system == "" {
		system = c.config.SystemPrompt
	}

	var response *CompletionResponse
	var err error

	switch c.config.Provider {
	case "claude":
		response, err = c.callClaude(ctx, system, messages)
	case "openai":
		response, err = c.callOpenAI(ctx, system, messages)
	case "deepseek":
		response, err = c.callDeepSeek(ctx, system, messages)
	case "azure-openai":
		response, err = c.callAzureOpenAI(ctx, system, messages)
	default:
		return "", fmt.Errorf("unsupported provider: %s", c.config.Provider)
	}

	if err != nil {
		return "", err
	}

	return response.Content, nil
}

// Helper functions

func isJPEG(data []byte) bool {
	return len(data) >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF
}

// isTimeoutErr reports whether an HTTP client error was a timeout/deadline.
func isTimeoutErr(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return true
	}
	var ne net.Error
	if errors.As(err, &ne) && ne.Timeout() {
		return true
	}
	return strings.Contains(err.Error(), "Client.Timeout exceeded")
}

// isAdjustableParamError reports whether a 400 body names a request parameter
// we know how to adapt (temperature, reasoning_effort, max_tokens family).
func isAdjustableParamError(body string) bool {
	if !strings.Contains(body, "unsupported_parameter") &&
		!strings.Contains(body, "unsupported_value") &&
		!strings.Contains(body, "invalid_request_error") {
		return false
	}
	return strings.Contains(body, "temperature") ||
		strings.Contains(body, "reasoning_effort") ||
		strings.Contains(body, "max_completion_tokens") ||
		strings.Contains(body, "max_tokens")
}
