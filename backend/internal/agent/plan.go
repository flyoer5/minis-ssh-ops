package agent

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/risk"
)

const SystemPrompt = `SSH ops helper. Reply JSON only (no markdown):
{"summary":"brief","steps":[{"id":1,"title":"t","command":"one-line shell","reason":"why"}],"notes":""}
Prefer read-only; max 6 steps. Never suggest rm -rf /, mkfs, dd of=/dev, curl|sh.`

type Step struct {
	ID      int        `json:"id"`
	Title   string     `json:"title"`
	Command string     `json:"command"`
	Reason  string     `json:"reason"`
	Risk    risk.Level `json:"risk"`
	Status  string     `json:"status,omitempty"`
}

type Plan struct {
	Summary string `json:"summary"`
	Steps   []Step `json:"steps"`
	Notes   string `json:"notes"`
	Raw     string `json:"raw,omitempty"`
}

func ParsePlan(raw string) (*Plan, error) {
	s := strings.TrimSpace(raw)
	if strings.HasPrefix(s, "```") {
		s = strings.TrimPrefix(s, "```json")
		s = strings.TrimPrefix(s, "```JSON")
		s = strings.TrimPrefix(s, "```")
		if i := strings.LastIndex(s, "```"); i >= 0 {
			s = s[:i]
		}
		s = strings.TrimSpace(s)
	}
	start := strings.Index(s, "{")
	end := strings.LastIndex(s, "}")
	if start < 0 || end <= start {
		return nil, fmt.Errorf("no json object")
	}
	s = s[start : end+1]
	var p Plan
	if err := json.Unmarshal([]byte(s), &p); err != nil {
		return nil, err
	}
	for i := range p.Steps {
		r := risk.Classify(p.Steps[i].Command)
		p.Steps[i].Risk = r
		p.Steps[i].Status = "pending"
		if r == risk.Blocked {
			p.Steps[i].Status = "blocked"
		}
	}
	p.Raw = raw
	return &p, nil
}
