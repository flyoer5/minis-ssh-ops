package agent

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"minis-ssh-ops/internal/sshx"
	"minis-ssh-ops/internal/storage"
)

const systemPrompt = `你是安卓端本地运维 Agent，通过 SSH 在用户的 Linux 主机上协助运维。
规则：
1. 只输出 JSON，不要 Markdown 代码块，不要解释性前后文。
2. 优先只读诊断；变更类命令必须拆成小步。
3. 禁止建议：rm -rf /、mkfs、dd 写磁盘、curl|sh、关机重启（除非用户明确要求且标 destructive）。
4. JSON schema:
{
  "summary": "一句话目标理解",
  "steps": [
    {
      "id": 1,
      "title": "步骤说明",
      "command": "单行 shell 命令",
      "risk": "read|write|destructive",
      "reason": "为什么执行"
    }
  ],
  "notes": "给用户的注意事项"
}
5. steps 最多 8 步；command 必须是可直接在 bash 执行的单行命令。
6. 若信息不足，steps 可为空，notes 里写需要用户补充什么。`

type PlanStep struct {
	ID      int    `json:"id"`
	Title   string `json:"title"`
	Command string `json:"command"`
	Risk    string `json:"risk"`
	Reason  string `json:"reason"`
	// runtime
	Status   string          `json:"status,omitempty"` // pending|confirmed|running|done|skipped|blocked
	Result   *sshx.ExecResult `json:"result,omitempty"`
	RiskReal Risk            `json:"risk_real,omitempty"`
}

type Plan struct {
	Summary string     `json:"summary"`
	Steps   []PlanStep `json:"steps"`
	Notes   string     `json:"notes"`
	Raw     string     `json:"raw,omitempty"`
}

type Agent struct {
	Store *storage.Store
	Pool  *sshx.Pool
}

func New(store *storage.Store, pool *sshx.Pool) *Agent {
	return &Agent{Store: store, Pool: pool}
}

func (a *Agent) llm() (*LLMClient, error) {
	cfg, err := a.Store.GetLLM()
	if err != nil {
		return nil, err
	}
	if cfg.APIKey == "" && !strings.Contains(cfg.BaseURL, "localhost") && !strings.Contains(cfg.BaseURL, "127.0.0.1") {
		// still allow keyless local endpoints
	}
	return NewLLM(cfg.BaseURL, cfg.APIKey, cfg.Model), nil
}

// Plan asks the model for a step plan (does not execute).
func (a *Agent) Plan(sessionID, hostID, goal string, extraContext string) (*Plan, error) {
	host, _, err := a.Store.GetHost(hostID)
	if err != nil {
		return nil, fmt.Errorf("host: %w", err)
	}
	llm, err := a.llm()
	if err != nil {
		return nil, err
	}

	user := fmt.Sprintf(`主机: %s (%s@%s:%d)
运维目标: %s
补充上下文:
%s
请给出诊断/处理计划 JSON。`, host.Name, host.User, host.Host, host.Port, goal, extraContext)

	_ = a.Store.AddChat(sessionID, "user", goal)
	msgs := []ChatMsg{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: user},
	}
	// recent chat for context
	history, _ := a.Store.ListChat(sessionID, 20)
	for _, m := range history {
		if m.Role == "user" || m.Role == "assistant" {
			// already added last user; skip duplicate end
		}
	}
	_ = history

	raw, err := llm.Chat(msgs)
	if err != nil {
		return nil, err
	}
	_ = a.Store.AddChat(sessionID, "assistant", raw)

	plan, err := parsePlan(raw)
	if err != nil {
		return &Plan{Summary: "模型输出无法解析为计划", Notes: raw, Raw: raw}, nil
	}
	// reclassify risk server-side (never trust model risk alone)
	for i := range plan.Steps {
		r := Classify(plan.Steps[i].Command)
		plan.Steps[i].RiskReal = r
		plan.Steps[i].Risk = string(r)
		plan.Steps[i].Status = "pending"
		if r == RiskBlocked {
			plan.Steps[i].Status = "blocked"
		}
	}
	plan.Raw = raw
	return plan, nil
}

func parsePlan(raw string) (*Plan, error) {
	s := strings.TrimSpace(raw)
	// strip ```json fences if present
	if strings.HasPrefix(s, "```") {
		s = strings.TrimPrefix(s, "```json")
		s = strings.TrimPrefix(s, "```JSON")
		s = strings.TrimPrefix(s, "```")
		if i := strings.LastIndex(s, "```"); i >= 0 {
			s = s[:i]
		}
		s = strings.TrimSpace(s)
	}
	// find first { last }
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
	return &p, nil
}

// ExecStep runs one step after risk checks.
func (a *Agent) ExecStep(hostID, sessionID string, step PlanStep, confirmed bool) (*PlanStep, error) {
	r := Classify(step.Command)
	step.RiskReal = r
	step.Risk = string(r)

	if r == RiskBlocked {
		step.Status = "blocked"
		_ = a.Store.AddAudit(&storage.AuditEntry{
			HostID: hostID, SessionID: sessionID, Command: step.Command,
			Risk: string(r), Confirmed: false, ExitCode: -1,
			Stderr: "blocked by policy",
		})
		return &step, fmt.Errorf("command blocked by safety policy")
	}
	if NeedsConfirm(r) && !confirmed {
		step.Status = "pending"
		return &step, fmt.Errorf("confirmation required for risk=%s", r)
	}

	cli := a.Pool.Get(hostID)
	if cli == nil {
		// dial on demand
		h, sec, err := a.Store.GetHost(hostID)
		if err != nil {
			return nil, err
		}
		if sec == nil {
			return nil, fmt.Errorf("host has no credentials")
		}
		cli, err = sshx.Dial(h.Host, h.Port, sshx.Auth{
			User: h.User, Password: sec.Password, PrivateKey: sec.PrivateKey, Passphrase: sec.Passphrase,
		}, 15*time.Second)
		if err != nil {
			return nil, err
		}
		a.Pool.Put(hostID, cli)
	}

	step.Status = "running"
	res, err := cli.Exec(step.Command, 90*time.Second)
	if res == nil {
		res = &sshx.ExecResult{ExitCode: -1, Stderr: err.Error()}
	}
	step.Result = res
	if err != nil && res.ExitCode == -1 {
		step.Status = "done"
	} else {
		step.Status = "done"
	}

	stdout := res.Stdout
	stderr := res.Stderr
	if len(stdout) > 8000 {
		stdout = stdout[:8000] + "\n...[truncated]"
	}
	if len(stderr) > 4000 {
		stderr = stderr[:4000] + "\n...[truncated]"
	}
	_ = a.Store.AddAudit(&storage.AuditEntry{
		HostID: hostID, SessionID: sessionID, Command: step.Command,
		Risk: string(r), Confirmed: confirmed || AllowedToAutoRun(r),
		ExitCode: res.ExitCode, Stdout: stdout, Stderr: stderr,
	})
	return &step, err
}

// QuickProbe runs a fixed safe read-only health snapshot.
func (a *Agent) QuickProbe(hostID string) (map[string]any, error) {
	cli := a.Pool.Get(hostID)
	if cli == nil {
		h, sec, err := a.Store.GetHost(hostID)
		if err != nil {
			return nil, err
		}
		if sec == nil {
			return nil, fmt.Errorf("no credentials")
		}
		cli, err = sshx.Dial(h.Host, h.Port, sshx.Auth{
			User: h.User, Password: sec.Password, PrivateKey: sec.PrivateKey, Passphrase: sec.Passphrase,
		}, 15*time.Second)
		if err != nil {
			return nil, err
		}
		a.Pool.Put(hostID, cli)
	}
	cmds := map[string]string{
		"uname":  "uname -a",
		"uptime": "uptime",
		"disk":   "df -h",
		"memory": "free -h 2>/dev/null || cat /proc/meminfo | head -5",
		"load":   "cat /proc/loadavg",
	}
	out := map[string]any{}
	for k, cmd := range cmds {
		r, err := cli.Exec(cmd, 15*time.Second)
		if err != nil && r == nil {
			out[k] = err.Error()
			continue
		}
		out[k] = map[string]any{"exit": r.ExitCode, "stdout": strings.TrimSpace(r.Stdout), "stderr": strings.TrimSpace(r.Stderr)}
	}
	return out, nil
}
