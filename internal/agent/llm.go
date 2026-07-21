package agent

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type LLMClient struct {
	BaseURL string
	APIKey  string
	Model   string
	HTTP    *http.Client
}

type ChatMsg struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type chatReq struct {
	Model       string    `json:"model"`
	Messages    []ChatMsg `json:"messages"`
	Temperature float64   `json:"temperature"`
}

type chatResp struct {
	Choices []struct {
		Message ChatMsg `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error"`
}

func NewLLM(baseURL, apiKey, model string) *LLMClient {
	baseURL = strings.TrimRight(baseURL, "/")
	return &LLMClient{
		BaseURL: baseURL,
		APIKey:  apiKey,
		Model:   model,
		HTTP:    &http.Client{Timeout: 120 * time.Second},
	}
}

func (c *LLMClient) Chat(messages []ChatMsg) (string, error) {
	if c.BaseURL == "" || c.Model == "" {
		return "", fmt.Errorf("llm not configured: set base_url and model")
	}
	body, _ := json.Marshal(chatReq{
		Model:       c.Model,
		Messages:    messages,
		Temperature: 0.2,
	})
	url := c.BaseURL + "/chat/completions"
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	if c.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.APIKey)
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("llm http %d: %s", resp.StatusCode, truncate(string(raw), 500))
	}
	var cr chatResp
	if err := json.Unmarshal(raw, &cr); err != nil {
		return "", fmt.Errorf("llm decode: %w", err)
	}
	if cr.Error != nil {
		return "", fmt.Errorf("llm error: %s", cr.Error.Message)
	}
	if len(cr.Choices) == 0 {
		return "", fmt.Errorf("llm empty choices")
	}
	return cr.Choices[0].Message.Content, nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}
