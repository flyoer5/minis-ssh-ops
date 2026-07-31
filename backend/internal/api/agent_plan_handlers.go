package api

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/agent"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/risk"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/store"
	"github.com/google/uuid"
)

type planBody struct {
	HostID    string `json:"hostId"`
	Goal      string `json:"goal"`
	SessionID string `json:"sessionId"`
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
	defer cli.Close()
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
	res, err := s.runSSHContext(r.Context(), body.HostID, body.Command)
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
