package api

import (
	"database/sql"
	"fmt"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/agent"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/risk"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/sshx"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/store"
	"github.com/google/uuid"
)

type execBodyV2 struct {
	Command   string `json:"command"`
	Confirmed bool   `json:"confirmed"`
	SessionID string `json:"sessionId"`
}

func (s *Server) handleExecV2(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body execBodyV2
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || strings.TrimSpace(body.Command) == "" {
		writeErr(w, http.StatusBadRequest, "command required")
		return
	}
	if body.SessionID == "" {
		body.SessionID = "manual"
	}
	lvl := risk.Classify(body.Command)
	if lvl == risk.Blocked {
		_ = s.Store.AddAudit(&store.AuditEntry{
			HostID: id, SessionID: body.SessionID, Command: body.Command,
			Risk: string(lvl), Confirmed: false, ExitCode: -1, Stderr: "blocked by policy",
		})
		writeErr(w, http.StatusForbidden, "command blocked by safety policy")
		return
	}
	if risk.NeedsConfirm(lvl) && !body.Confirmed {
		writeJSON(w, http.StatusConflict, map[string]any{
			"error":   "confirmation required",
			"risk":    lvl,
			"command": body.Command,
		})
		return
	}
	res, err := s.runSSH(id, body.Command)
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	stdout, stderr := res.Stdout, res.Stderr
	if len(stdout) > 8000 {
		stdout = stdout[:8000] + "\n...[truncated]"
	}
	if len(stderr) > 4000 {
		stderr = stderr[:4000] + "\n...[truncated]"
	}
	_ = s.Store.AddAudit(&store.AuditEntry{
		HostID: id, SessionID: body.SessionID, Command: body.Command,
		Risk: string(lvl), Confirmed: body.Confirmed || lvl == risk.Read,
		ExitCode: res.ExitCode, Stdout: stdout, Stderr: stderr,
	})
	writeJSON(w, http.StatusOK, map[string]any{
		"exitCode":   res.ExitCode,
		"stdout":     res.Stdout,
		"stderr":     res.Stderr,
		"durationMs": res.DurationMs,
		"risk":       lvl,
	})
}

func (s *Server) runSSH(hostID, command string) (sshx.ExecResult, error) {
	h, err := s.Store.GetHost(hostID)
	if err != nil {
		return sshx.ExecResult{}, err
	}
	sec, err := s.Store.GetHostSecrets(hostID)
	if err != nil {
		return sshx.ExecResult{}, err
	}
	return sshx.Exec(sshx.ConnectParams{
		Host:          h.Host,
		Port:          h.Port,
		Username:      h.Username,
		Password:      sec.Password,
		PrivateKeyPEM: sec.PrivateKeyPEM,
		Passphrase:    sec.Passphrase,
		HostKeys:      s.HostKeys,
	}, command)
}

type planBody struct {
	HostID    string `json:"hostId"`
	Goal      string `json:"goal"`
	SessionID string `json:"sessionId"`
}

type chatBody struct {
	HostID         string `json:"hostId"`
	Message        string `json:"message"`
	SessionID      string `json:"sessionId"`
	ConfirmWrites  bool   `json:"confirmWrites"`
}


// handleAgentChat: OpenClaw-style multi-turn tool loop (model decides tools).
func (s *Server) handleAgentChat(w http.ResponseWriter, r *http.Request) {
	var body chatBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	if strings.TrimSpace(body.HostID) == "" || strings.TrimSpace(body.Message) == "" {
		writeErr(w, http.StatusBadRequest, "hostId and message required")
		return
	}
	if body.SessionID == "" {
		body.SessionID = uuid.NewString()
	}
	if _, err := s.Store.GetHost(body.HostID); errors.Is(err, sql.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "host not found")
		return
	} else if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	llmCfg, err := s.Store.GetLLMFull()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	if llmCfg.BaseURL == "" || llmCfg.Model == "" {
		writeErr(w, http.StatusBadRequest, "configure LLM in settings first")
		return
	}
	cli := agent.NewClient(llmCfg.BaseURL, llmCfg.APIKey, llmCfg.Model)
	cli.ThinkingLevel = llmCfg.ThinkingLevel
	_ = s.Store.AddChat(body.SessionID, "user", body.Message)

	// Durable memory + recent window (does not hard-forget older turns).
	history, _ := agent.BuildMemoryMessages(s.Store, body.SessionID, body.Message, 16)

	probeScript := `printf '%s\n' '___U___'; uname -a 2>/dev/null; printf '%s\n' '___T___'; uptime 2>/dev/null; printf '%s\n' '___L___'; cat /proc/loadavg 2>/dev/null; printf '%s\n' '___C___'; grep -m1 '^cpu ' /proc/stat 2>/dev/null; sleep 1; grep -m1 '^cpu ' /proc/stat 2>/dev/null; printf '%s\n' '___D___'; df -h 2>/dev/null; printf '%s\n' '___M___'; (free -h 2>/dev/null || head -5 /proc/meminfo 2>/dev/null)`

	run := func(name string, args map[string]any) (string, error) {
		switch name {
		case "probe_host":
			res, err := s.runSSH(body.HostID, probeScript)
			if err != nil {
				return "", err
			}
			_ = s.Store.AddAudit(&store.AuditEntry{
				HostID: body.HostID, SessionID: body.SessionID, Command: "probe_host",
				Risk: "read", Confirmed: true, ExitCode: res.ExitCode, Stdout: truncate(res.Stdout, 8000),
			})
			return res.Stdout, nil
		case "run_command":
			cmd, _ := args["command"].(string)
			cmd = strings.TrimSpace(cmd)
			if cmd == "" {
				return "", fmt.Errorf("empty command")
			}
			lvl := risk.Classify(cmd)
			// Keep only hard blacklist (app safety), not rssh confirm walls.
			if lvl == risk.Blocked {
				_ = s.Store.AddAudit(&store.AuditEntry{
					HostID: body.HostID, SessionID: body.SessionID, Command: cmd,
					Risk: string(lvl), Confirmed: false, ExitCode: -1, Stderr: "blocked",
				})
				return "", fmt.Errorf("blocked by policy: %s", cmd)
			}
			if body.ConfirmWrites && (lvl == risk.Write || lvl == risk.Destructive) {
				_ = s.Store.AddAudit(&store.AuditEntry{
					HostID: body.HostID, SessionID: body.SessionID, Command: cmd,
					Risk: string(lvl), Confirmed: false, ExitCode: -1, Stderr: "needs_confirm",
				})
				return "", fmt.Errorf("NEEDS_CONFIRM:%s:%s", lvl, cmd)
			}
			res, err := s.runSSH(body.HostID, cmd)
			if err != nil {
				return "", err
			}
			_ = s.Store.AddAudit(&store.AuditEntry{
				HostID: body.HostID, SessionID: body.SessionID, Command: cmd,
				Risk: string(lvl), Confirmed: true, ExitCode: res.ExitCode,
				Stdout: truncate(res.Stdout, 8000), Stderr: truncate(res.Stderr, 4000),
			})
			out := res.Stdout
			if res.Stderr != "" {
				out = out + "\n" + res.Stderr
			}
			return strings.TrimSpace(out), nil
		default:
			return "", fmt.Errorf("unknown tool %s", name)
		}
	}

	events, _, err := cli.RunLoop(body.Message, history, run, 5)
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	// persist final assistant text
	for i := len(events) - 1; i >= 0; i-- {
		if events[i].Type == "final" || events[i].Type == "assistant" {
			if events[i].Content != "" {
				_ = s.Store.AddChat(body.SessionID, "assistant", events[i].Content)
				break
			}
		}
	}
	// Update rolling long-term memory (summary/facts) when enough new turns exist.
	_ = agent.MaybeRefreshMemory(cli, s.Store, body.SessionID, 20, 8)
	mem, _ := s.Store.GetSessionMemory(body.SessionID)
	writeJSON(w, http.StatusOK, map[string]any{
		"sessionId": body.SessionID,
		"events":    events,
		"memory": map[string]any{
			"summary": mem.Summary,
			"facts":   mem.Facts,
		},
	})
}

// handleAgentChatStream: same loop as chat, but NDJSON/SSE event stream for progressive UI.
func (s *Server) handleAgentChatStream(w http.ResponseWriter, r *http.Request) {
	var body chatBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	if strings.TrimSpace(body.HostID) == "" || strings.TrimSpace(body.Message) == "" {
		writeErr(w, http.StatusBadRequest, "hostId and message required")
		return
	}
	if body.SessionID == "" {
		body.SessionID = uuid.NewString()
	}
	if _, err := s.Store.GetHost(body.HostID); errors.Is(err, sql.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "host not found")
		return
	} else if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	llmCfg, err := s.Store.GetLLMFull()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	if llmCfg.BaseURL == "" || llmCfg.Model == "" {
		writeErr(w, http.StatusBadRequest, "configure LLM in settings first")
		return
	}

	flusher, ok := w.(http.Flusher)
	if !ok {
		writeErr(w, http.StatusInternalServerError, "stream unsupported")
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)

	writeEv := func(v any) {
		b, _ := json.Marshal(v)
		fmt.Fprintf(w, "data: %s\n\n", b)
		flusher.Flush()
	}
	writeEv(map[string]any{"type": "session", "sessionId": body.SessionID})

	cli := agent.NewClient(llmCfg.BaseURL, llmCfg.APIKey, llmCfg.Model)
	cli.ThinkingLevel = llmCfg.ThinkingLevel
	_ = s.Store.AddChat(body.SessionID, "user", body.Message)
	history, _ := agent.BuildMemoryMessages(s.Store, body.SessionID, body.Message, 16)

	probeScript := `printf '%s\n' '___U___'; uname -a 2>/dev/null; printf '%s\n' '___T___'; uptime 2>/dev/null; printf '%s\n' '___L___'; cat /proc/loadavg 2>/dev/null; printf '%s\n' '___C___'; grep -m1 '^cpu ' /proc/stat 2>/dev/null; sleep 1; grep -m1 '^cpu ' /proc/stat 2>/dev/null; printf '%s\n' '___D___'; df -h 2>/dev/null; printf '%s\n' '___M___'; (free -h 2>/dev/null || head -5 /proc/meminfo 2>/dev/null)`
	run := func(name string, args map[string]any) (string, error) {
		switch name {
		case "probe_host":
			res, err := s.runSSH(body.HostID, probeScript)
			if err != nil {
				return "", err
			}
			_ = s.Store.AddAudit(&store.AuditEntry{
				HostID: body.HostID, SessionID: body.SessionID, Command: "probe_host",
				Risk: "read", Confirmed: true, ExitCode: res.ExitCode, Stdout: truncate(res.Stdout, 8000),
			})
			return res.Stdout, nil
		case "run_command":
			cmd, _ := args["command"].(string)
			cmd = strings.TrimSpace(cmd)
			if cmd == "" {
				return "", fmt.Errorf("empty command")
			}
			lvl := risk.Classify(cmd)
			if lvl == risk.Blocked {
				_ = s.Store.AddAudit(&store.AuditEntry{
					HostID: body.HostID, SessionID: body.SessionID, Command: cmd,
					Risk: string(lvl), Confirmed: false, ExitCode: -1, Stderr: "blocked",
				})
				return "", fmt.Errorf("blocked by policy: %s", cmd)
			}
			if body.ConfirmWrites && (lvl == risk.Write || lvl == risk.Destructive) {
				_ = s.Store.AddAudit(&store.AuditEntry{
					HostID: body.HostID, SessionID: body.SessionID, Command: cmd,
					Risk: string(lvl), Confirmed: false, ExitCode: -1, Stderr: "needs_confirm",
				})
				return "", fmt.Errorf("NEEDS_CONFIRM:%s:%s", lvl, cmd)
			}
			res, err := s.runSSH(body.HostID, cmd)
			if err != nil {
				return "", err
			}
			_ = s.Store.AddAudit(&store.AuditEntry{
				HostID: body.HostID, SessionID: body.SessionID, Command: cmd,
				Risk: string(lvl), Confirmed: true, ExitCode: res.ExitCode,
				Stdout: truncate(res.Stdout, 8000), Stderr: truncate(res.Stderr, 4000),
			})
			out := res.Stdout
			if res.Stderr != "" {
				out = out + "\n" + res.Stderr
			}
			return strings.TrimSpace(out), nil
		default:
			return "", fmt.Errorf("unknown tool %s", name)
		}
	}

	events, _, err := cli.RunLoopStream(body.Message, history, run, 5, func(ev agent.LoopEvent) {
		writeEv(ev)
	})
	if err != nil {
		writeEv(map[string]any{"type": "error", "content": err.Error()})
	}
	for i := len(events) - 1; i >= 0; i-- {
		if events[i].Type == "final" || events[i].Type == "assistant" {
			if events[i].Content != "" {
				_ = s.Store.AddChat(body.SessionID, "assistant", events[i].Content)
				break
			}
		}
	}
	_ = agent.MaybeRefreshMemory(cli, s.Store, body.SessionID, 20, 8)
	mem, _ := s.Store.GetSessionMemory(body.SessionID)
	writeEv(map[string]any{"type": "memory", "content": mem.Summary, "facts": mem.Facts})
	writeEv(map[string]any{"type": "done", "sessionId": body.SessionID})
}

func (s *Server) handleAgentPlan(w http.ResponseWriter, r *http.Request) {
	var body planBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	if strings.TrimSpace(body.HostID) == "" || strings.TrimSpace(body.Goal) == "" {
		writeErr(w, http.StatusBadRequest, "hostId and goal required")
		return
	}
	if body.SessionID == "" {
		body.SessionID = uuid.NewString()
	}
	h, err := s.Store.GetHost(body.HostID)
	if errors.Is(err, sql.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "host not found")
		return
	}
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	llmCfg, err := s.Store.GetLLMFull()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	if llmCfg.BaseURL == "" || llmCfg.Model == "" {
		writeErr(w, http.StatusBadRequest, "configure LLM in settings first")
		return
	}
	cli := agent.NewClient(llmCfg.BaseURL, llmCfg.APIKey, llmCfg.Model)
	cli.ThinkingLevel = llmCfg.ThinkingLevel
	_ = s.Store.AddChat(body.SessionID, "user", body.Goal)
	raw, err := cli.Chat([]agent.Msg{
		{Role: "system", Content: agent.SystemPrompt},
		{Role: "user", Content: body.Goal + "\n[" + h.Username + "@" + h.Host + "]"},
	})
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	_ = s.Store.AddChat(body.SessionID, "assistant", raw)
	plan, err := agent.ParsePlan(raw)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{
			"sessionId": body.SessionID,
			"plan": map[string]any{
				"summary": "模型输出无法解析为计划",
				"steps":   []any{},
				"notes":   raw,
				"raw":     raw,
			},
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"sessionId": body.SessionID,
		"plan":      plan,
	})
}

type stepBody struct {
	HostID    string `json:"hostId"`
	SessionID string `json:"sessionId"`
	Command   string `json:"command"`
	Confirmed bool   `json:"confirmed"`
	StepID    int    `json:"stepId"`
}

func (s *Server) handleAgentExecStep(w http.ResponseWriter, r *http.Request) {
	var body stepBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	if body.HostID == "" || strings.TrimSpace(body.Command) == "" {
		writeErr(w, http.StatusBadRequest, "hostId and command required")
		return
	}
	// reuse exec gate
	r2 := *r
	// call shared logic by constructing response via helper
	lvl := risk.Classify(body.Command)
	if lvl == risk.Blocked {
		writeErr(w, http.StatusForbidden, "command blocked by safety policy")
		return
	}
	if risk.NeedsConfirm(lvl) && !body.Confirmed {
		writeJSON(w, http.StatusConflict, map[string]any{
			"error": "confirmation required", "risk": lvl, "command": body.Command, "stepId": body.StepID,
		})
		return
	}
	res, err := s.runSSH(body.HostID, body.Command)
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	sid := body.SessionID
	if sid == "" {
		sid = "agent"
	}
	_ = s.Store.AddAudit(&store.AuditEntry{
		HostID: body.HostID, SessionID: sid, Command: body.Command,
		Risk: string(lvl), Confirmed: body.Confirmed || lvl == risk.Read,
		ExitCode: res.ExitCode, Stdout: truncate(res.Stdout, 8000), Stderr: truncate(res.Stderr, 4000),
	})
	writeJSON(w, http.StatusOK, map[string]any{
		"stepId":     body.StepID,
		"risk":       lvl,
		"exitCode":   res.ExitCode,
		"stdout":     res.Stdout,
		"stderr":     res.Stderr,
		"durationMs": res.DurationMs,
	})
	_ = r2
}

func (s *Server) handleAudit(w http.ResponseWriter, r *http.Request) {
	list, err := s.Store.ListAudit(100)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"entries": list})
}

func (s *Server) handleProbe(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	// One SSH session / one compound command — much faster than 5 sequential dials.
	const script = `printf '%s\n' '___U___'; uname -a 2>/dev/null; printf '%s\n' '___T___'; uptime 2>/dev/null; printf '%s\n' '___L___'; cat /proc/loadavg 2>/dev/null; printf '%s\n' '___C___'; grep -m1 '^cpu ' /proc/stat 2>/dev/null; sleep 1; grep -m1 '^cpu ' /proc/stat 2>/dev/null; printf '%s\n' '___D___'; df -h 2>/dev/null; printf '%s\n' '___M___'; (free -h 2>/dev/null || head -5 /proc/meminfo 2>/dev/null)`
	res, err := s.runSSH(id, script)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{
			"uname":  map[string]any{"error": err.Error()},
			"uptime": map[string]any{"error": err.Error()},
			"load":   map[string]any{"error": err.Error()},
			"cpu":    map[string]any{"error": err.Error()},
			"disk":   map[string]any{"error": err.Error()},
			"memory": map[string]any{"error": err.Error()},
		})
		return
	}
	parts := splitProbe(res.Stdout)
	parts["C"] = cpuUsageFromProcStat(parts["C"])
	mk := func(s string) map[string]any {
		return map[string]any{"exitCode": res.ExitCode, "stdout": strings.TrimSpace(s), "stderr": ""}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"uname":  mk(parts["U"]),
		"uptime": mk(parts["T"]),
		"load":   mk(parts["L"]),
		"cpu":    mk(parts["C"]),
		"disk":   mk(parts["D"]),
		"memory": mk(parts["M"]),
		"durationMs": res.DurationMs,
	})
}


// cpuUsageFromProcStat parses two "cpu ..." lines (~1s apart) → utilization 0–100.
func cpuUsageFromProcStat(raw string) string {
	var samples [][]uint64
	for _, line := range strings.Split(raw, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 5 || fields[0] != "cpu" {
			continue
		}
		nums := make([]uint64, 0, len(fields)-1)
		ok := true
		for _, f := range fields[1:] {
			var v uint64
			if _, err := fmt.Sscanf(f, "%d", &v); err != nil {
				ok = false
				break
			}
			nums = append(nums, v)
		}
		if !ok || len(nums) < 4 {
			continue
		}
		samples = append(samples, nums)
		if len(samples) >= 2 {
			break
		}
	}
	if len(samples) < 2 {
		return strings.TrimSpace(raw)
	}
	a, b := samples[0], samples[1]
	for len(a) < 8 {
		a = append(a, 0)
	}
	for len(b) < 8 {
		b = append(b, 0)
	}
	sum8 := func(s []uint64) uint64 {
		var t uint64
		for i := 0; i < 8; i++ {
			t += s[i]
		}
		return t
	}
	idleOf := func(s []uint64) uint64 { return s[3] + s[4] }
	if sum8(b) < sum8(a) || idleOf(b) < idleOf(a) {
		return "0"
	}
	dt := sum8(b) - sum8(a)
	di := idleOf(b) - idleOf(a)
	if dt == 0 {
		return "0"
	}
	busy := dt - di
	pct := (busy * 100) / dt
	if pct > 100 {
		pct = 100
	}
	return fmt.Sprintf("%d", pct)
}


func splitProbe(stdout string) map[string]string {
	out := map[string]string{"U": "", "T": "", "L": "", "C": "", "D": "", "M": ""}
	cur := ""
	for _, line := range strings.Split(stdout, "\n") {
		if strings.HasPrefix(line, "___") && strings.HasSuffix(line, "___") && len(line) >= 7 {
			// ___X___
			tag := strings.Trim(line, "_")
			if len(tag) == 1 {
				cur = tag
				continue
			}
		}
		if cur == "" {
			continue
		}
		if out[cur] == "" {
			out[cur] = line
		} else {
			out[cur] += "\n" + line
		}
	}
	return out
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "\n...[truncated]"
}

