package api

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/risk"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/sshx"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/store"
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
	return s.runSSHContext(context.Background(), hostID, command)
}

func (s *Server) runSSHContext(ctx context.Context, hostID, command string) (sshx.ExecResult, error) {
	h, err := s.Store.GetHost(hostID)
	if err != nil {
		return sshx.ExecResult{}, err
	}
	sec, err := s.Store.GetHostSecrets(hostID)
	if err != nil {
		return sshx.ExecResult{}, err
	}
	// Agent tools often chain ps/docker/journalctl; 12s dial default is too tight
	// on loaded hosts and surfaces as "context deadline exceeded".
	return sshx.ExecContext(ctx, sshx.ConnectParams{
		Host:          h.Host,
		Port:          h.Port,
		Username:      h.Username,
		Password:      sec.Password,
		PrivateKeyPEM: sec.PrivateKeyPEM,
		Passphrase:    sec.Passphrase,
		HostKeys:      s.HostKeys,
		Timeout:       90 * time.Second,
	}, command)
}
