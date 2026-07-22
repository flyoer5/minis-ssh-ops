package agent

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/risk"
)

// Keep prompt tiny. UI is Minis-like: assistant text + tool cards user must run.
const SystemPrompt = `JSON only: {"reply":"","commands":[{"title":"","command":"","side_effect":"read|write|destructive"}]}`

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
	Reply    string `json:"reply"`
	Summary  string `json:"summary"`
	Steps    []Step `json:"steps"`
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
		r := risk.Classify(p.Steps[i].Command)
		switch strings.ToLower(p.Steps[i].SideEffect) {
		case "destructive":
			if r != risk.Blocked {
				r = risk.Destructive
			}
		case "write":
			if r == risk.Read {
				r = risk.Write
			}
		}
		p.Steps[i].Risk = r
		p.Steps[i].Status = "pending"
		if r == risk.Blocked {
			p.Steps[i].Status = "blocked"
		}
		if p.Steps[i].Title == "" {
			p.Steps[i].Title = "shell"
		}
	}
	p.Raw = raw
	return &p, nil
}
