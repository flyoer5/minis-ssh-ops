package agent

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/risk"
)

// Minimal: model proposes commands; app requires explicit Run (rssh-style).
const SystemPrompt = `You help operate a Linux host over SSH.
Reply JSON only, no markdown:
{"reply":"short natural language","commands":[{"title":"","command":"single-line shell","side_effect":"none|read|write|destructive"}]}
Prefer read-only diagnostics. Max 5 commands. Never suggest rm -rf /, mkfs, dd of=/dev, curl|sh.`

type Step struct {
	ID         int        `json:"id"`
	Title      string     `json:"title"`
	Command    string     `json:"command"`
	Reason     string     `json:"reason"`
	SideEffect string     `json:"side_effect,omitempty"`
	Risk       risk.Level `json:"risk"`
	Status     string     `json:"status,omitempty"`
}

type Plan struct {
	// reply: natural chat text (preferred)
	Reply   string `json:"reply"`
	Summary string `json:"summary"` // legacy alias
	Steps   []Step `json:"steps"`
	// commands: rssh-style alias for steps
	Commands []Step `json:"commands"`
	Notes    string `json:"notes"`
	Raw      string `json:"raw,omitempty"`
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
	// normalize commands -> steps
	if len(p.Steps) == 0 && len(p.Commands) > 0 {
		p.Steps = p.Commands
	}
	if p.Reply == "" {
		p.Reply = p.Summary
	}
	if p.Summary == "" {
		p.Summary = p.Reply
	}
	for i := range p.Steps {
		if p.Steps[i].ID == 0 {
			p.Steps[i].ID = i + 1
		}
		// map side_effect to risk if provided
		se := strings.ToLower(p.Steps[i].SideEffect)
		r := risk.Classify(p.Steps[i].Command)
		switch se {
		case "destructive":
			if riskRank(r) < riskRank(risk.Destructive) {
				r = risk.Destructive
			}
		case "write":
			if riskRank(r) < riskRank(risk.Write) {
				r = risk.Write
			}
		case "none", "read":
			// keep server classify as floor
		}
		p.Steps[i].Risk = r
		p.Steps[i].Status = "pending"
		if r == risk.Blocked {
			p.Steps[i].Status = "blocked"
		}
		if p.Steps[i].Title == "" {
			p.Steps[i].Title = p.Steps[i].Command
		}
	}
	p.Raw = raw
	return &p, nil
}

func riskRank(r risk.Level) int {
	switch r {
	case risk.Read:
		return 1
	case risk.Write:
		return 2
	case risk.Destructive:
		return 3
	case risk.Blocked:
		return 4
	default:
		return 0
	}
}
