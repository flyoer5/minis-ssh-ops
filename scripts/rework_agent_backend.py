#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def must_replace(path, old, new, label):
    p = ROOT / path
    t = p.read_text()
    if old not in t:
        print(f"FAIL {label}")
        sys.exit(1)
    p.write_text(t.replace(old, new))
    print(f"OK {label} x{t.count(old)}")


def main():
    # ----- llm.go: ThinkingLevel + applyThinkingParams + chatOnce body -----
    p = ROOT / "backend/internal/agent/llm.go"
    t = p.read_text()
    t = t.replace(
        """type Client struct {
	BaseURL string
	APIKey  string
	Model   string
	HTTP    *http.Client
}
""",
        """type Client struct {
	BaseURL       string
	APIKey        string
	Model         string
	ThinkingLevel string // none|low|medium|high|xhigh|auto
	HTTP          *http.Client
}
""",
    )
    t = t.replace(
        """func (c *Client) chatOnce(messages []Msg) (string, error) {
	body, _ := json.Marshal(map[string]any{
		"model":       c.Model,
		"messages":    messages,
		"temperature": 0.2,
	})
""",
        """func (c *Client) chatOnce(messages []Msg) (string, error) {
	payload := map[string]any{
		"model":       c.Model,
		"messages":    messages,
		"temperature": 0.2,
	}
	applyThinkingParams(payload, c.ThinkingLevel)
	body, _ := json.Marshal(payload)
""",
    )
    # strip think tags from simple chat content
    t = t.replace(
        """	return out.Choices[0].Message.Content, nil
}
""",
        """	content := out.Choices[0].Message.Content
	if strings.Contains(strings.ToLower(content), "<think") || strings.Contains(strings.ToLower(content), "<reasoning") {
		c2, _ := splitThinkTags(content)
		if c2 != "" {
			content = c2
		}
	}
	return content, nil
}
""",
    )
    if "func applyThinkingParams" not in t:
        t = t.rstrip() + """

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
"""
    p.write_text(t)
    print("OK llm.go")

    # ----- loop.go: reasoning fields + parse + emit -----
    p = ROOT / "backend/internal/agent/loop.go"
    t = p.read_text()
    if '"regexp"' not in t:
        t = t.replace(
            """import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"
)
""",
            """import (
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
var thinkTagRe = regexp.MustCompile(`(?is)<(think|thinking|reasoning)>(.*?)</\\1>`)
""",
        )

    t = t.replace(
        """type LoopMsg struct {
	Role       string     `json:"role"`
	Content    string     `json:"content,omitempty"`
	Name       string     `json:"name,omitempty"`
	ToolCallID string     `json:"tool_call_id,omitempty"`
	ToolCalls  []ToolCall `json:"tool_calls,omitempty"`
}
""",
        """type LoopMsg struct {
	Role       string     `json:"role"`
	Content    string     `json:"content,omitempty"`
	// Reasoning is model thinking (Minis reasoning_content). Not resent as history content.
	Reasoning  string     `json:"reasoning,omitempty"`
	Name       string     `json:"name,omitempty"`
	ToolCallID string     `json:"tool_call_id,omitempty"`
	ToolCalls  []ToolCall `json:"tool_calls,omitempty"`
}
""",
    )

    t = t.replace(
        """type LoopEvent struct {
	Type    string `json:"type"` // assistant | tool | tool_result | final | error
	Content string `json:"content,omitempty"`
	Name    string `json:"name,omitempty"`
	Command string `json:"command,omitempty"`
}
""",
        """type LoopEvent struct {
	Type      string `json:"type"` // assistant | tool | tool_result | final | error | reasoning
	Content   string `json:"content,omitempty"`
	Reasoning string `json:"reasoning,omitempty"`
	Name      string `json:"name,omitempty"`
	Command   string `json:"command,omitempty"`
}
""",
    )

    # request body with thinking
    old_body = """	body, _ := json.Marshal(map[string]any{
		"model":       c.Model,
		"messages":    apiMsgs,
		"tools":       defaultTools,
		"tool_choice": "auto",
		"temperature": 0.2,
	})
"""
    new_body = """	payload := map[string]any{
		"model":       c.Model,
		"messages":    apiMsgs,
		"tools":       defaultTools,
		"tool_choice": "auto",
		"temperature": 0.2,
	}
	applyThinkingParams(payload, c.ThinkingLevel)
	body, _ := json.Marshal(payload)
"""
    if old_body not in t:
        print("FAIL loop request body")
        sys.exit(1)
    t = t.replace(old_body, new_body)

    # emit final/assistant with reasoning — find original blocks
    old_final = """		if len(asst.ToolCalls) == 0 {
			text := strings.TrimSpace(asst.Content)
			if text != "" {
				push(LoopEvent{Type: "final", Content: text})
			}
			msgs = append(msgs, asst)
			return events, msgs, nil
		}
		msgs = append(msgs, asst)
		if strings.TrimSpace(asst.Content) != "" {
			push(LoopEvent{Type: "assistant", Content: strings.TrimSpace(asst.Content)})
		}
"""
    new_final = """		if len(asst.ToolCalls) == 0 {
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
"""
    if old_final not in t:
        print("FAIL final emit block")
        # try show
        i = t.find("len(asst.ToolCalls)")
        print(t[i : i + 500])
        sys.exit(1)
    t = t.replace(old_final, new_final)

    # decode message with reasoning_content
    old_dec = """	var out struct {
		Choices []struct {
			Message struct {
				Role      string     `json:"role"`
				Content   any        `json:"content"`
				ToolCalls []ToolCall `json:"tool_calls"`
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
	return LoopMsg{Role: "assistant", Content: content, ToolCalls: m.ToolCalls}, nil
}
"""
    new_dec = """	var out struct {
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
		reason = reason + "\\n" + fromTag
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
		if len(sub) >= 3 {
			inner := strings.TrimSpace(sub[2])
			if inner != "" {
				reasons = append(reasons, inner)
			}
		}
		return ""
	})
	clean = strings.TrimSpace(clean)
	reason = strings.TrimSpace(strings.Join(reasons, "\\n\\n"))
	return clean, reason
}
"""
    if old_dec not in t:
        print("FAIL decode block")
        sys.exit(1)
    t = t.replace(old_dec, new_dec)
    p.write_text(t)
    print("OK loop.go")

    # wire ThinkingLevel on client creation
    p = ROOT / "backend/internal/api/agent_handlers.go"
    t = p.read_text()
    old = "cli := agent.NewClient(llmCfg.BaseURL, llmCfg.APIKey, llmCfg.Model)"
    new = """cli := agent.NewClient(llmCfg.BaseURL, llmCfg.APIKey, llmCfg.Model)
	cli.ThinkingLevel = llmCfg.ThinkingLevel"""
    if old not in t:
        print("FAIL NewClient sites")
        sys.exit(1)
    n = t.count(old)
    p.write_text(t.replace(old, new))
    print(f"OK handlers ThinkingLevel x{n}")


if __name__ == "__main__":
    main()
