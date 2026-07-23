package agent

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"regexp"
	"strings"
	"time"
)

// Matches <think>…</think>, <thinking>…</thinking>, <reasoning>…</reasoning>.
var thinkTagRe = regexp.MustCompile(`(?is)<think>(.*?)</think>|<thinking>(.*?)</thinking>|<reasoning>(.*?)</reasoning>`)

// OpenClaw-style tools (Minis-like short descriptions).
var defaultTools = []map[string]any{
	{
		"type": "function",
		"function": map[string]any{
			"name":        "run_command",
			"description": "Run a shell command on the selected host via SSH.",
			"parameters": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"command": map[string]any{"type": "string", "description": "shell command"},
				},
				"required": []string{"command"},
			},
		},
	},
	{
		"type": "function",
		"function": map[string]any{
			"name":        "probe_host",
			"description": "Optional broad health snapshot (uname/uptime/load/disk/memory). Use only when user asks overall status or you need a full snapshot—not for every message.",
			"parameters": map[string]any{
				"type":       "object",
				"properties": map[string]any{},
			},
		},
	},
}

// Minis stance + OpenClaw tool loop. Tools only when facts are missing.
const loopSystem = `You are a personal Linux ops assistant on the user's phone (SSH).

Don't perform — help. Be direct. Don't invent command output.
Tools: probe_host, run_command.
Do NOT run tools by default. Answer from chat/memory first.
Only call tools when the user needs live host facts, diagnosis, or you truly lack data.
Prefer a single targeted run_command over probe_host. Use probe_host only for broad health checks when asked.
After any tools, answer concisely in the user's language.`

type LoopMsg struct {
	Role       string     `json:"role"`
	Content    string     `json:"content,omitempty"`
	// Reasoning is model thinking (Minis reasoning_content). Not resent as history content.
	Reasoning  string     `json:"reasoning,omitempty"`
	Name       string     `json:"name,omitempty"`
	ToolCallID string     `json:"tool_call_id,omitempty"`
	ToolCalls  []ToolCall `json:"tool_calls,omitempty"`
}

type ToolCall struct {
	ID       string `json:"id"`
	Type     string `json:"type"`
	Function struct {
		Name      string `json:"name"`
		Arguments string `json:"arguments"`
	} `json:"function"`
}

type LoopEvent struct {
	Type      string `json:"type"` // assistant | tool | tool_result | final | error | reasoning
	Content   string `json:"content,omitempty"`
	Reasoning string `json:"reasoning,omitempty"`
	Name      string `json:"name,omitempty"`
	Command   string `json:"command,omitempty"`
}

// ToolRunner executes a tool and returns plain text output.
type ToolRunner func(name string, args map[string]any) (string, error)

// EventSink receives events as they happen (for SSE).
type EventSink func(ev LoopEvent)

func (c *Client) RunLoop(userText string, history []LoopMsg, run ToolRunner, maxRounds int) ([]LoopEvent, []LoopMsg, error) {
	return c.RunLoopStream(userText, history, run, maxRounds, nil)
}

func (c *Client) RunLoopStream(userText string, history []LoopMsg, run ToolRunner, maxRounds int, sink EventSink) ([]LoopEvent, []LoopMsg, error) {
	if maxRounds <= 0 {
		maxRounds = 6
	}
	emit := func(ev LoopEvent) {
		if sink != nil {
			sink(ev)
		}
	}
	msgs := make([]LoopMsg, 0, len(history)+4)
	msgs = append(msgs, LoopMsg{Role: "system", Content: loopSystem})
	msgs = append(msgs, history...)
	msgs = append(msgs, LoopMsg{Role: "user", Content: userText})

	var events []LoopEvent
	push := func(ev LoopEvent) {
		events = append(events, ev)
		emit(ev)
	}

	for round := 0; round < maxRounds; round++ {
		asst, err := c.chatTools(msgs)
		if err != nil {
			push(LoopEvent{Type: "error", Content: err.Error()})
			return events, msgs, err
		}
		if len(asst.ToolCalls) == 0 {
			text := strings.TrimSpace(asst.Content)
			reason := strings.TrimSpace(asst.Reasoning)
			if reason != "" && text == "" {
				push(LoopEvent{Type: "reasoning", Content: reason, Reasoning: reason})
			}
			if text != "" || reason != "" {
				push(LoopEvent{Type: "final", Content: text, Reasoning: reason})
			}
			msgs = append(msgs, LoopMsg{Role: "assistant", Content: asst.Content, ToolCalls: asst.ToolCalls})
			return events, msgs, nil
		}
		msgs = append(msgs, LoopMsg{Role: "assistant", Content: asst.Content, ToolCalls: asst.ToolCalls})
		if strings.TrimSpace(asst.Reasoning) != "" {
			push(LoopEvent{Type: "reasoning", Content: strings.TrimSpace(asst.Reasoning), Reasoning: strings.TrimSpace(asst.Reasoning)})
		}
		if strings.TrimSpace(asst.Content) != "" {
			push(LoopEvent{Type: "assistant", Content: strings.TrimSpace(asst.Content), Reasoning: strings.TrimSpace(asst.Reasoning)})
		}
		for _, tc := range asst.ToolCalls {
			args := map[string]any{}
			_ = json.Unmarshal([]byte(tc.Function.Arguments), &args)
			cmd, _ := args["command"].(string)
			push(LoopEvent{
				Type: "tool", Name: tc.Function.Name, Command: cmd, Content: "running",
			})
			out, err := run(tc.Function.Name, args)
			if err != nil {
				out = "error: " + err.Error()
			}
			if len(out) > 16000 {
				out = out[:16000] + "\n...[truncated]"
			}
			push(LoopEvent{
				Type: "tool_result", Name: tc.Function.Name, Command: cmd, Content: out,
			})
			msgs = append(msgs, LoopMsg{
				Role: "tool", ToolCallID: tc.ID, Name: tc.Function.Name, Content: out,
			})
		}
	}
	push(LoopEvent{Type: "final", Content: "（达到工具轮次上限）"})
	return events, msgs, nil
}

func (c *Client) chatTools(messages []LoopMsg) (LoopMsg, error) {
	if c.BaseURL == "" || c.Model == "" {
		return LoopMsg{}, fmt.Errorf("llm not configured")
	}
	apiMsgs := make([]map[string]any, 0, len(messages))
	for _, m := range messages {
		item := map[string]any{"role": m.Role}
		if m.Content != "" {
			item["content"] = m.Content
		}
		if m.Name != "" {
			item["name"] = m.Name
		}
		if m.ToolCallID != "" {
			item["tool_call_id"] = m.ToolCallID
		}
		if len(m.ToolCalls) > 0 {
			item["tool_calls"] = m.ToolCalls
		}
		if m.Role == "assistant" && m.Content == "" && len(m.ToolCalls) > 0 {
			item["content"] = nil
		}
		apiMsgs = append(apiMsgs, item)
	}
	payload := map[string]any{
		"model":       c.Model,
		"messages":    apiMsgs,
		"tools":       defaultTools,
		"tool_choice": "auto",
		"temperature": 0.2,
	}
	applyThinkingParams(payload, c.ThinkingLevel)
	body, _ := json.Marshal(payload)

	var last error
	for attempt := 1; attempt <= 3; attempt++ {
		text, err := c.postChat(body)
		if err == nil {
			return text, nil
		}
		last = err
		if !isRetryable(err) || attempt == 3 {
			break
		}
		time.Sleep(time.Duration(attempt) * 800 * time.Millisecond)
	}
	return LoopMsg{}, friendlyLLMError(last)
}

func (c *Client) postChat(body []byte) (LoopMsg, error) {
	req, err := http.NewRequest(http.MethodPost, c.BaseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return LoopMsg{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Connection", "close")
	if c.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.APIKey)
	}
	if c.HTTP == nil {
		c.HTTP = &http.Client{Timeout: 120 * time.Second, Transport: &http.Transport{
			Proxy:               http.ProxyFromEnvironment,
			DialContext:         (&net.Dialer{Timeout: 15 * time.Second}).DialContext,
			ForceAttemptHTTP2:   false,
			TLSHandshakeTimeout: 15 * time.Second,
		}}
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return LoopMsg{}, err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if resp.StatusCode >= 300 {
		return LoopMsg{}, fmt.Errorf("llm http %d: %s", resp.StatusCode, truncate(string(raw), 300))
	}
	var out struct {
		Choices []struct {
			Message struct {
				Role             string     `json:"role"`
				Content          any        `json:"content"`
				ReasoningContent string     `json:"reasoning_content"`
				Reasoning        any        `json:"reasoning"`
				ToolCalls        []ToolCall `json:"tool_calls"`
			} `json:"message"`
		} `json:"choices"`
		Error *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return LoopMsg{}, fmt.Errorf("llm decode: %w", err)
	}
	if out.Error != nil {
		return LoopMsg{}, fmt.Errorf("llm: %s", out.Error.Message)
	}
	if len(out.Choices) == 0 {
		return LoopMsg{}, fmt.Errorf("llm empty choices")
	}
	m := out.Choices[0].Message
	content := ""
	switch v := m.Content.(type) {
	case string:
		content = v
	case nil:
		content = ""
	default:
		b, _ := json.Marshal(v)
		content = string(b)
	}
	reason := strings.TrimSpace(m.ReasoningContent)
	if reason == "" {
		switch v := m.Reasoning.(type) {
		case string:
			reason = strings.TrimSpace(v)
		case map[string]any:
			if s, ok := v["content"].(string); ok {
				reason = strings.TrimSpace(s)
			} else if s, ok := v["text"].(string); ok {
				reason = strings.TrimSpace(s)
			} else if s, ok := v["summary"].(string); ok {
				reason = strings.TrimSpace(s)
			}
		}
	}
	content, fromTag := splitThinkTags(content)
	if reason == "" {
		reason = fromTag
	} else if fromTag != "" {
		reason = reason + "\n" + fromTag
	}
	return LoopMsg{Role: "assistant", Content: content, Reasoning: reason, ToolCalls: m.ToolCalls}, nil
}

func splitThinkTags(content string) (clean string, reason string) {
	if content == "" {
		return "", ""
	}
	var reasons []string
	clean = thinkTagRe.ReplaceAllStringFunc(content, func(m string) string {
		sub := thinkTagRe.FindStringSubmatch(m)
		for i := 1; i < len(sub); i++ {
			inner := strings.TrimSpace(sub[i])
			if inner != "" {
				reasons = append(reasons, inner)
				break
			}
		}
		return ""
	})
	clean = strings.TrimSpace(clean)
	reason = strings.TrimSpace(strings.Join(reasons, "\n\n"))
	return clean, reason
}
