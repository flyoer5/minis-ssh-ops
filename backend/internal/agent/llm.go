package agent

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"
)

type Client struct {
	BaseURL       string
	APIKey        string
	Model         string
	ThinkingLevel string // none|low|medium|high|xhigh|auto
	HTTP          *http.Client
	// Req is cancelled when the SSE client disconnects (user stop).
	// LLM HTTP requests and tool rounds should respect it.
	Ctx context.Context
}

type Msg struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

func NewClient(baseURL, apiKey, model string) *Client {
	tr := &http.Transport{
		Proxy: http.ProxyFromEnvironment,
		DialContext: (&net.Dialer{
			Timeout:   15 * time.Second,
			KeepAlive: 30 * time.Second,
		}).DialContext,
		ForceAttemptHTTP2:     false, // some gateways flake on h2
		MaxIdleConns:          4,
		IdleConnTimeout:       60 * time.Second,
		TLSHandshakeTimeout:   15 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
		ResponseHeaderTimeout: 90 * time.Second,
	}
	return &Client{
		BaseURL: strings.TrimRight(baseURL, "/"),
		APIKey:  apiKey,
		Model:   model,
		Ctx:     context.Background(),
		HTTP: &http.Client{
			Timeout:   120 * time.Second,
			Transport: tr,
		},
	}
}

func (c *Client) Chat(messages []Msg) (string, error) {
	if c.BaseURL == "" || c.Model == "" {
		return "", fmt.Errorf("llm not configured")
	}
	var last error
	for attempt := 1; attempt <= 3; attempt++ {
		text, err := c.chatOnce(messages)
		if err == nil {
			return text, nil
		}
		last = err
		if !isRetryable(err) || attempt == 3 {
			break
		}
		time.Sleep(time.Duration(attempt) * 800 * time.Millisecond)
	}
	return "", friendlyLLMError(last)
}

func (c *Client) chatOnce(messages []Msg) (string, error) {
	payload := map[string]any{
		"model":       c.Model,
		"messages":    messages,
		"temperature": 0.2,
	}
	applyThinkingParams(payload, c.ThinkingLevel)
	body, _ := json.Marshal(payload)
	req, err := http.NewRequest(http.MethodPost, c.BaseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Connection", "close")
	if c.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.APIKey)
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("llm http %d: %s", resp.StatusCode, truncate(string(raw), 300))
	}
	var out struct {
		Choices []struct {
			Message Msg `json:"message"`
		} `json:"choices"`
		Error *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return "", fmt.Errorf("llm decode: %w", err)
	}
	if out.Error != nil {
		return "", fmt.Errorf("llm: %s", out.Error.Message)
	}
	if len(out.Choices) == 0 {
		return "", fmt.Errorf("llm empty choices")
	}
	content := out.Choices[0].Message.Content
	if strings.Contains(strings.ToLower(content), "<think") || strings.Contains(strings.ToLower(content), "<reasoning") {
		c2, _ := splitThinkTags(content)
		if c2 != "" {
			content = c2
		}
	}
	return content, nil
}

func isRetryable(err error) bool {
	if err == nil {
		return false
	}
	s := strings.ToLower(err.Error())
	for _, k := range []string{
		"connection abort", "connection reset", "broken pipe",
		"timeout", "temporary", "eof", "i/o timeout",
		"tls handshake", "server closed", "http2",
	} {
		if strings.Contains(s, k) {
			return true
		}
	}
	// retry 502/503/429 body markers
	if strings.Contains(s, "llm http 502") || strings.Contains(s, "llm http 503") || strings.Contains(s, "llm http 429") {
		return true
	}
	return false
}

func friendlyLLMError(err error) error {
	if err == nil {
		return fmt.Errorf("llm unknown error")
	}
	s := err.Error()
	low := strings.ToLower(s)
	switch {
	case strings.Contains(low, "connection abort"), strings.Contains(low, "connection reset"), strings.Contains(low, "broken pipe"):
		return fmt.Errorf("模型网关连接中断，请重试")
	case strings.Contains(low, "timeout"), strings.Contains(low, "deadline"):
		return fmt.Errorf("模型请求超时，请重试")
	case strings.Contains(low, "llm http 401"), strings.Contains(low, "llm http 403"):
		return fmt.Errorf("模型鉴权失败，请检查 API Key / Base URL")
	case strings.Contains(low, "llm http 404"):
		return fmt.Errorf("模型接口不存在，请检查 Base URL（需含 /v1）")
	case strings.Contains(low, "llm not configured"):
		return fmt.Errorf("未配置模型，请到设置页填写")
	default:
		// strip noisy Go transport prefix
		if i := strings.Index(s, "Post \""); i >= 0 {
			if j := strings.Index(s, "\": "); j > i {
				return fmt.Errorf("模型请求失败: %s", s[j+3:])
			}
		}
		return fmt.Errorf("模型请求失败: %s", truncate(s, 180))
	}
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}

// ListModels calls OpenAI-compatible GET {base}/models and returns model ids.
func ListModels(baseURL, apiKey string) ([]string, error) {
	baseURL = strings.TrimRight(baseURL, "/")
	if baseURL == "" {
		return nil, fmt.Errorf("empty base url")
	}
	req, err := http.NewRequest(http.MethodGet, baseURL+"/models", nil)
	if err != nil {
		return nil, err
	}
	if apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+apiKey)
	}
	cli := &http.Client{
		Timeout: 20 * time.Second,
		Transport: &http.Transport{
			Proxy:                 http.ProxyFromEnvironment,
			ForceAttemptHTTP2:     false,
			MaxIdleConns:          8,
			IdleConnTimeout:       30 * time.Second,
			TLSHandshakeTimeout:   8 * time.Second,
			ResponseHeaderTimeout: 15 * time.Second,
			ExpectContinueTimeout: 1 * time.Second,
		},
	}
	resp, err := cli.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("models http %d: %s", resp.StatusCode, truncate(string(raw), 200))
	}
	var out struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, err
	}
	ids := make([]string, 0, len(out.Data))
	for _, d := range out.Data {
		if strings.TrimSpace(d.ID) != "" {
			ids = append(ids, d.ID)
		}
	}
	return ids, nil
}

// applyThinkingParams injects common gateway thinking fields (Minis-compatible).
func applyThinkingParams(payload map[string]any, level string) {
	lv := strings.ToLower(strings.TrimSpace(level))
	if lv == "" {
		lv = "auto"
	}
	switch lv {
	case "none", "off", "disabled", "0", "false":
		payload["enable_thinking"] = false
		payload["reasoning_effort"] = "none"
		return
	case "auto", "enabled", "true", "on":
		payload["enable_thinking"] = true
		return
	case "low", "minimal", "min":
		payload["enable_thinking"] = true
		payload["reasoning_effort"] = "low"
		payload["thinking_budget"] = 1024
	case "medium", "med", "default":
		payload["enable_thinking"] = true
		payload["reasoning_effort"] = "medium"
		payload["thinking_budget"] = 4096
	case "high":
		payload["enable_thinking"] = true
		payload["reasoning_effort"] = "high"
		payload["thinking_budget"] = 8192
	case "xhigh", "extra", "max":
		payload["enable_thinking"] = true
		payload["reasoning_effort"] = "high"
		payload["thinking_budget"] = 16384
		payload["thinkingLevel"] = "XHIGH"
	default:
		payload["enable_thinking"] = true
		payload["reasoning_effort"] = lv
	}
	if lv != "none" && lv != "off" {
		payload["includeThoughts"] = true
	}
}
