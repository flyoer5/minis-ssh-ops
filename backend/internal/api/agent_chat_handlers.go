package api

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/agent"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/risk"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/store"
	"github.com/google/uuid"
)

type chatBody struct {
	HostID        string  `json:"hostId"`
	Message       string  `json:"message"`
	SessionID     string  `json:"sessionId"`
	ConfirmWrites bool    `json:"confirmWrites"`
	MaxRounds     int     `json:"maxRounds"`
	Temperature   float64 `json:"temperature"`
	CustomPrompt  string  `json:"customPrompt"`
}

func clampMaxRounds(n int) int {
	if n <= 0 || n > 99 {
		return 12
	}
	return n
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
	defer cli.Close()
	cli.ThinkingLevel = llmCfg.ThinkingLevel
	_ = s.Store.EnsureAgentSession(body.SessionID, body.HostID, body.Message)
	_ = s.Store.AddChat(body.SessionID, "user", body.Message)

	// Durable memory + recent window (does not hard-forget older turns).
	history, _ := agent.BuildMemoryMessages(s.Store, body.SessionID, body.Message, 16)

	probeScript := `printf '%s\n' '___O___'; ( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-${NAME:-}} ${VERSION_ID:-}" ) | sed 's/  */ /g;s/^ //;s/ $//'; printf '%s\n' '___U___'; uname -a 2>/dev/null; printf '%s\n' '___T___'; uptime 2>/dev/null; printf '%s\n' '___L___'; cat /proc/loadavg 2>/dev/null; printf '%s\n' '___C___'; grep -m1 '^cpu ' /proc/stat 2>/dev/null; sleep 0.12 2>/dev/null || sleep 1; grep -m1 '^cpu ' /proc/stat 2>/dev/null; printf '%s\n' '___D___'; df -h 2>/dev/null; printf '%s\n' '___M___'; (free -h 2>/dev/null || head -5 /proc/meminfo 2>/dev/null)`

	run := func(name string, args map[string]any) (string, error) {
		switch name {
		case "probe_host":
			res, err := s.runSSHContext(r.Context(), body.HostID, probeScript)
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
			res, err := s.runSSHContext(r.Context(), body.HostID, cmd)
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

	if body.Temperature > 0 {
		cli.Temperature = body.Temperature
	}
	events, _, err := cli.RunLoop(body.Message, history, run, clampMaxRounds(body.MaxRounds))
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	// Persist structured transcript parts for session replay.
	s.persistAgentEvents(body.SessionID, events)
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

	writeEv := func(v any) bool {
		if err := r.Context().Err(); err != nil {
			return false
		}
		b, _ := json.Marshal(v)
		if _, err := fmt.Fprintf(w, "data: %s\n\n", b); err != nil {
			return false
		}
		flusher.Flush()
		return true
	}
	writeEv(map[string]any{"type": "session", "sessionId": body.SessionID})

	cli := agent.NewClient(llmCfg.BaseURL, llmCfg.APIKey, llmCfg.Model)
	defer cli.Close()
	cli.ThinkingLevel = llmCfg.ThinkingLevel
	// Cancel LLM + SSH when the mobile client closes the SSE (user hit 停止).
	cli.Ctx = r.Context()
	_ = s.Store.EnsureAgentSession(body.SessionID, body.HostID, body.Message)
	_ = s.Store.AddChat(body.SessionID, "user", body.Message)
	history, _ := agent.BuildMemoryMessages(s.Store, body.SessionID, body.Message, 16)

	probeScript := `printf '%s\n' '___O___'; ( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-${NAME:-}} ${VERSION_ID:-}" ) | sed 's/  */ /g;s/^ //;s/ $//'; printf '%s\n' '___U___'; uname -a 2>/dev/null; printf '%s\n' '___T___'; uptime 2>/dev/null; printf '%s\n' '___L___'; cat /proc/loadavg 2>/dev/null; printf '%s\n' '___C___'; grep -m1 '^cpu ' /proc/stat 2>/dev/null; sleep 0.12 2>/dev/null || sleep 1; grep -m1 '^cpu ' /proc/stat 2>/dev/null; printf '%s\n' '___D___'; df -h 2>/dev/null; printf '%s\n' '___M___'; (free -h 2>/dev/null || head -5 /proc/meminfo 2>/dev/null)`
	run := func(name string, args map[string]any) (string, error) {
		switch name {
		case "probe_host":
			res, err := s.runSSHContext(r.Context(), body.HostID, probeScript)
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
			res, err := s.runSSHContext(r.Context(), body.HostID, cmd)
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

	if body.Temperature > 0 {
		cli.Temperature = body.Temperature
	}
	events, _, err := cli.RunLoopStream(body.Message, history, run, clampMaxRounds(body.MaxRounds), func(ev agent.LoopEvent) {
		if !writeEv(ev) {
			// Client closed SSE mid-event — request context should already be cancelled.
			log.Printf("agent stream: write failed session=%s (client stop?)", body.SessionID)
		}
	})
	if err != nil {
		// cancelled: client already gone — don't bother error event
		if r.Context().Err() != nil {
			log.Printf("agent stream: cancelled session=%s host=%s err=%v", body.SessionID, body.HostID, err)
			return
		}
		_ = writeEv(map[string]any{"type": "error", "content": err.Error()})
	}
	s.persistAgentEvents(body.SessionID, events)
	if r.Context().Err() != nil {
		return
	}
	_ = agent.MaybeRefreshMemory(cli, s.Store, body.SessionID, 20, 8)
	mem, _ := s.Store.GetSessionMemory(body.SessionID)
	_ = writeEv(map[string]any{"type": "memory", "content": mem.Summary, "facts": mem.Facts})
	_ = writeEv(map[string]any{"type": "done", "sessionId": body.SessionID})
}
