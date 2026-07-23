package agent

import (
	"fmt"
	"strings"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/store"
)

// BuildMemoryMessages constructs model history with long-term memory:
//  1. optional durable summary/facts from session_memory
//  2. recent full user/assistant turns (chronological)
// Older turns are NOT discarded raw — they are folded into summary/facts over time.
func BuildMemoryMessages(st *store.Store, sessionID, currentUser string, recentLimit int) ([]LoopMsg, store.SessionMemory) {
	if recentLimit <= 0 {
		recentLimit = 16
	}
	mem, _ := st.GetSessionMemory(sessionID)
	recent, _ := st.ListChatRecent(sessionID, recentLimit+4)

	var turns []LoopMsg
	for _, row := range recent {
		role, _ := row["role"].(string)
		content, _ := row["content"].(string)
		if role != "user" && role != "assistant" {
			continue
		}
		content = strings.TrimSpace(content)
		if content == "" {
			continue
		}
		// keep recent turns readable but bounded
		if len(content) > 4000 {
			content = content[:4000] + "…"
		}
		turns = append(turns, LoopMsg{Role: role, Content: content})
	}
	if n := len(turns); n > 0 && turns[n-1].Role == "user" && turns[n-1].Content == currentUser {
		turns = turns[:n-1]
	}
	if len(turns) > recentLimit {
		turns = turns[len(turns)-recentLimit:]
	}

	out := make([]LoopMsg, 0, len(turns)+1)
	if block := formatMemoryBlock(mem); block != "" {
		out = append(out, LoopMsg{Role: "system", Content: block})
	}
	out = append(out, turns...)
	return out, mem
}

func formatMemoryBlock(m store.SessionMemory) string {
	sum := strings.TrimSpace(m.Summary)
	facts := strings.TrimSpace(m.Facts)
	if sum == "" && facts == "" {
		return ""
	}
	var b strings.Builder
	b.WriteString("Long-term memory for this session (do not discard; update mentally as chat continues):\n")
	if sum != "" {
		b.WriteString("Summary:\n")
		b.WriteString(sum)
		b.WriteByte('\n')
	}
	if facts != "" {
		b.WriteString("Facts:\n")
		b.WriteString(facts)
		b.WriteByte('\n')
	}
	b.WriteString("Use memory when relevant. If new durable facts appear, include them in your final answer.")
	return b.String()
}

// MaybeRefreshMemory folds older turns into durable summary/facts via a small LLM call.
func MaybeRefreshMemory(cli *Client, st *store.Store, sessionID string, everyN, minNew int) error {
	if cli == nil || st == nil || sessionID == "" {
		return nil
	}
	if everyN <= 0 {
		everyN = 20
	}
	if minNew <= 0 {
		minNew = 8
	}
	total, err := st.CountChat(sessionID)
	if err != nil || total < minNew+4 {
		return err
	}
	mem, err := st.GetSessionMemory(sessionID)
	if err != nil {
		return err
	}
	pending, err := st.ListChatAfter(sessionID, mem.CoveredUntilID, 120)
	if err != nil {
		return err
	}
	// only user/assistant for summarization
	var lines []string
	var maxID int64
	for _, row := range pending {
		role, _ := row["role"].(string)
		content, _ := row["content"].(string)
		id, _ := row["id"].(int64)
		if id == 0 {
			if v, ok := row["id"].(int); ok {
				id = int64(v)
			}
		}
		if id > maxID {
			maxID = id
		}
		if role != "user" && role != "assistant" {
			continue
		}
		content = strings.TrimSpace(content)
		if content == "" {
			continue
		}
		if len(content) > 500 {
			content = content[:500] + "…"
		}
		lines = append(lines, role+": "+content)
	}
	if len(lines) < minNew {
		return nil
	}
	// throttle: refresh roughly every everyN messages of growth
	if mem.CoveredUntilID > 0 && total-int(mem.CoveredUntilID) < everyN && len(lines) < everyN {
		// still allow if never summarized and already long
		if mem.Summary != "" {
			return nil
		}
	}

	var prompt strings.Builder
	prompt.WriteString("You maintain long-term memory for an ops chat about a Linux server.\n")
	prompt.WriteString("Merge OLD MEMORY with NEW TURNS. Keep durable facts (host traits, issues found, decisions, paths, versions).\n")
	prompt.WriteString("Drop chit-chat and raw command spam. Output exactly:\n")
	prompt.WriteString("SUMMARY:\n<one short paragraph>\nFACTS:\n- bullet facts\n")
	prompt.WriteString("\nOLD MEMORY SUMMARY:\n")
	if strings.TrimSpace(mem.Summary) == "" {
		prompt.WriteString("(none)\n")
	} else {
		prompt.WriteString(mem.Summary)
		prompt.WriteByte('\n')
	}
	prompt.WriteString("\nOLD FACTS:\n")
	if strings.TrimSpace(mem.Facts) == "" {
		prompt.WriteString("(none)\n")
	} else {
		prompt.WriteString(mem.Facts)
		prompt.WriteByte('\n')
	}
	prompt.WriteString("\nNEW TURNS:\n")
	prompt.WriteString(strings.Join(lines, "\n"))

	out, err := cli.Chat([]Msg{{Role: "user", Content: prompt.String()}})
	if err != nil {
		return err
	}
	sum, facts := parseMemoryOutput(out)
	if sum == "" && facts == "" {
		return fmt.Errorf("empty memory refresh")
	}
	if sum == "" {
		sum = mem.Summary
	}
	if facts == "" {
		facts = mem.Facts
	}
	// keep memory bounded
	if len(sum) > 2500 {
		sum = sum[:2500] + "…"
	}
	if len(facts) > 2500 {
		facts = facts[:2500] + "…"
	}
	if maxID == 0 {
		maxID = mem.CoveredUntilID
	}
	return st.UpsertSessionMemory(store.SessionMemory{
		SessionID:      sessionID,
		Summary:        sum,
		Facts:          facts,
		CoveredUntilID: maxID,
	})
}

func parseMemoryOutput(s string) (summary, facts string) {
	s = strings.TrimSpace(s)
	up := strings.ToUpper(s)
	si := strings.Index(up, "SUMMARY:")
	fi := strings.Index(up, "FACTS:")
	if si >= 0 && fi > si {
		summary = strings.TrimSpace(s[si+len("SUMMARY:") : fi])
		facts = strings.TrimSpace(s[fi+len("FACTS:"):])
		return summary, facts
	}
	if si >= 0 {
		summary = strings.TrimSpace(s[si+len("SUMMARY:"):])
		return summary, ""
	}
	// fallback: whole text as summary
	if len(s) > 0 {
		return s, ""
	}
	return "", ""
}
