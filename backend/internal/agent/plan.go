package agent

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/risk"
)

const SystemPrompt = `你是手机端本地运维 Agent，通过 SSH 协助用户运维 Linux。
规则：
1. 只输出 JSON，不要 Markdown 代码围栏。
2. 优先只读诊断；变更拆小步。
3. 禁止：rm -rf /、mkfs、dd 写盘、curl|sh、关机重启（除非用户明确且标 destructive）。
4. schema:
{"summary":"...","steps":[{"id":1,"title":"...","command":"单行shell","reason":"..."}],"notes":"..."}
5. steps 最多 8 步。`

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
