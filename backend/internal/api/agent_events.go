package api

import (
	"strings"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/agent"
)

// persistAgentEvents writes tool/reasoning/assistant parts for session history replay.
func (s *Server) persistAgentEvents(sessionID string, events []agent.LoopEvent) {
	if sessionID == "" || len(events) == 0 {
		return
	}
	// Prefer the last non-empty final/assistant as the answer; also keep tools + reasoning.
	var lastAssistant string
	for _, ev := range events {
		switch ev.Type {
		case "reasoning":
			if strings.TrimSpace(ev.Content) == "" && strings.TrimSpace(ev.Reasoning) == "" {
				continue
			}
			txt := strings.TrimSpace(ev.Content)
			if txt == "" {
				txt = strings.TrimSpace(ev.Reasoning)
			}
			_ = s.Store.AddChatPart(sessionID, "assistant", txt, "reasoning", map[string]any{"part": "reasoning"})
		case "tool":
			meta := map[string]any{
				"part":        "toolUse",
				"name":        ev.Name,
				"command":     ev.Command,
				"description": "运行中",
			}
			_ = s.Store.AddChatPart(sessionID, "tool", "running", "toolUse", meta)
		case "tool_result":
			success := true
			out := ev.Content
			if strings.Contains(strings.ToLower(out), "deadline exceeded") {
				out = "远程命令超时（主机忙或命令过慢）。可拆短命令后重试。\n原始错误: " + out
				success = false
			}
			if strings.HasPrefix(out, "error:") || strings.HasPrefix(out, "NEEDS_CONFIRM:") || strings.HasPrefix(out, "error: NEEDS_CONFIRM:") {
				success = false
			}
			meta := map[string]any{
				"part":    "toolResult",
				"name":    ev.Name,
				"command": ev.Command,
				"success": success,
				"output":  out,
			}
			if strings.Contains(out, "NEEDS_CONFIRM") {
				meta["pendingConfirm"] = true
				meta["success"] = nil
			}
			_ = s.Store.AddChatPart(sessionID, "tool", out, "toolResult", meta)
		case "final", "assistant":
			if strings.TrimSpace(ev.Content) != "" {
				lastAssistant = ev.Content
			}
		case "error":
			if strings.TrimSpace(ev.Content) != "" {
				_ = s.Store.AddChatPart(sessionID, "assistant", ev.Content, "error", map[string]any{"part": "error"})
			}
		}
	}
	if strings.TrimSpace(lastAssistant) != "" {
		_ = s.Store.AddChatPart(sessionID, "assistant", lastAssistant, "text", map[string]any{"part": "text"})
	}
}
