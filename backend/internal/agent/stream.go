package agent

import (
	"bufio"
	"context"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"
)

// chatToolsStream calls chat/completions with stream=true and emits:
//   - assistant_delta / reasoning_delta as tokens arrive
//   - returns the assembled assistant message (content + tool_calls + reasoning)
// Falls back to non-stream postChat if the gateway rejects stream or returns non-SSE.
func (c *Client) chatToolsStream(messages []LoopMsg, onDelta func(kind, text string)) (LoopMsg, error) {
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
		"stream":      true,
	}
	applyThinkingParams(payload, c.ThinkingLevel)
	body, _ := json.Marshal(payload)

	var last error
	for attempt := 1; attempt <= 3; attempt++ {
		msg, err := c.postChatStream(body, onDelta)
		if err == nil {
			return msg, nil
		}
		last = err
		// Non-stream fallback when gateway clearly rejects streaming
		es := err.Error()
		if strings.Contains(es, "stream") && (strings.Contains(es, "unsupported") ||
			strings.Contains(es, "not supported") ||
			strings.Contains(es, "http 4")) {
			return c.postChat(mustJSONWithoutStream(body))
		}
		if !isRetryable(err) || attempt == 3 {
			break
		}
		time.Sleep(time.Duration(attempt) * 800 * time.Millisecond)
	}
	// last resort: non-stream
	if last != nil {
		if msg, err := c.postChat(mustJSONWithoutStream(body)); err == nil {
			return msg, nil
		}
	}
	return LoopMsg{}, friendlyLLMError(last)
}

func mustJSONWithoutStream(body []byte) []byte {
	var m map[string]any
	if err := json.Unmarshal(body, &m); err != nil {
		return body
	}
	delete(m, "stream")
	b, _ := json.Marshal(m)
	return b
}

func (c *Client) postChatStream(body []byte, onDelta func(kind, text string)) (LoopMsg, error) {
	ctx := c.Ctx
	if ctx == nil {
		ctx = context.Background()
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.BaseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return LoopMsg{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "text/event-stream")
	req.Header.Set("Connection", "close")
	if c.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.APIKey)
	}
	// Streaming needs no overall body timeout — use generous response header timeout only.
	httpClient := c.HTTP
	if httpClient == nil || httpClient.Timeout > 0 {
		httpClient = &http.Client{
			Timeout: 0,
			Transport: &http.Transport{
				Proxy:                 http.ProxyFromEnvironment,
				DialContext:           (&net.Dialer{Timeout: 15 * time.Second}).DialContext,
				ForceAttemptHTTP2:     false,
				TLSHandshakeTimeout:   15 * time.Second,
				ResponseHeaderTimeout: 120 * time.Second,
			},
		}
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return LoopMsg{}, err
	}
	defer resp.Body.Close()
	ct := resp.Header.Get("Content-Type")
	if resp.StatusCode >= 300 {
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
		return LoopMsg{}, fmt.Errorf("llm http %d: %s", resp.StatusCode, truncate(string(raw), 300))
	}
	// Some gateways ignore stream and return JSON object
	if !strings.Contains(ct, "text/event-stream") && !strings.Contains(ct, "stream") {
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
		// try parse as non-stream
		return parseChatCompletionJSON(raw)
	}

	var content strings.Builder
	var reason strings.Builder
	// tool call assembly by index
	type tcAcc struct {
		id, name, args string
	}
	tools := map[int]*tcAcc{}

	sc := bufio.NewScanner(resp.Body)
	// allow long SSE lines
	buf := make([]byte, 0, 64*1024)
	sc.Buffer(buf, 2<<20)
	for sc.Scan() {
		if err := ctx.Err(); err != nil {
			_ = resp.Body.Close()
			return LoopMsg{}, err
		}
		line := sc.Text()
		if line == "" {
			continue
		}
		if !strings.HasPrefix(line, "data:") {
			continue
		}
		data := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
		if data == "" || data == "[DONE]" {
			if data == "[DONE]" {
				break
			}
			continue
		}
		var chunk struct {
			Choices []struct {
				Delta struct {
					Content          any        `json:"content"`
					ReasoningContent string     `json:"reasoning_content"`
					Reasoning        any        `json:"reasoning"`
					ToolCalls        []struct {
						Index    int    `json:"index"`
						ID       string `json:"id"`
						Type     string `json:"type"`
						Function struct {
							Name      string `json:"name"`
							Arguments string `json:"arguments"`
						} `json:"function"`
					} `json:"tool_calls"`
				} `json:"delta"`
				// some providers put message on non-stream-like final
				Message *struct {
					Content          any        `json:"content"`
					ReasoningContent string     `json:"reasoning_content"`
					ToolCalls        []ToolCall `json:"tool_calls"`
				} `json:"message"`
			} `json:"choices"`
			Error *struct {
				Message string `json:"message"`
			} `json:"error"`
		}
		if err := json.Unmarshal([]byte(data), &chunk); err != nil {
			continue
		}
		if chunk.Error != nil {
			return LoopMsg{}, fmt.Errorf("llm: %s", chunk.Error.Message)
		}
		if len(chunk.Choices) == 0 {
			continue
		}
		d := chunk.Choices[0].Delta
		// content delta
		var piece string
		switch v := d.Content.(type) {
		case string:
			piece = v
		case []any:
			// rare content parts array
			for _, p := range v {
				if m, ok := p.(map[string]any); ok {
					if s, ok := m["text"].(string); ok {
						piece += s
					}
				}
			}
		}
		if piece != "" {
			content.WriteString(piece)
			if onDelta != nil {
				onDelta("assistant_delta", piece)
			}
		}
		// reasoning delta — do NOT TrimSpace: stream tokens often are " word" with a
		// leading space; trimming each piece produces "Theusersaid你好" glue.
		rpiece := d.ReasoningContent
		if rpiece == "" {
			switch v := d.Reasoning.(type) {
			case string:
				rpiece = v
			case map[string]any:
				if s, ok := v["content"].(string); ok {
					rpiece = s
				} else if s, ok := v["text"].(string); ok {
					rpiece = s
				}
			}
		}
		if rpiece != "" {
			reason.WriteString(rpiece)
			if onDelta != nil {
				onDelta("reasoning_delta", rpiece)
			}
		}
		// tool call deltas
		for _, tc := range d.ToolCalls {
			acc := tools[tc.Index]
			if acc == nil {
				acc = &tcAcc{}
				tools[tc.Index] = acc
			}
			if tc.ID != "" {
				acc.id = tc.ID
			}
			if tc.Function.Name != "" {
				acc.name += tc.Function.Name
			}
			if tc.Function.Arguments != "" {
				acc.args += tc.Function.Arguments
			}
		}
	}
	if err := sc.Err(); err != nil && err != io.EOF {
		// partial may still be usable
		if content.Len() == 0 && len(tools) == 0 {
			return LoopMsg{}, err
		}
	}

	// assemble tool calls in index order
	var tcs []ToolCall
	if len(tools) > 0 {
		maxIdx := 0
		for i := range tools {
			if i > maxIdx {
				maxIdx = i
			}
		}
		for i := 0; i <= maxIdx; i++ {
			acc := tools[i]
			if acc == nil {
				continue
			}
			tc := ToolCall{ID: acc.id, Type: "function"}
			tc.Function.Name = acc.name
			tc.Function.Arguments = acc.args
			if tc.ID == "" {
				tc.ID = fmt.Sprintf("call_%d", i)
			}
			tcs = append(tcs, tc)
		}
	}

	text := content.String()
	rs := strings.TrimSpace(reason.String())
	// strip think tags if any leaked into content mid-stream
	text, fromTag := splitThinkTags(text)
	if rs == "" {
		rs = fromTag
	} else if fromTag != "" {
		rs = rs + "\n" + fromTag
	}
	return LoopMsg{Role: "assistant", Content: text, Reasoning: rs, ToolCalls: tcs}, nil
}

func parseChatCompletionJSON(raw []byte) (LoopMsg, error) {
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
	default:
		b, _ := json.Marshal(v)
		content = string(b)
	}
	reason := strings.TrimSpace(m.ReasoningContent)
	content, fromTag := splitThinkTags(content)
	if reason == "" {
		reason = fromTag
	}
	return LoopMsg{Role: "assistant", Content: content, Reasoning: reason, ToolCalls: m.ToolCalls}, nil
}
