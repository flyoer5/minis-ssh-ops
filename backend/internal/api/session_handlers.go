package api

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"github.com/google/uuid"
)

// GET /v1/agent/sessions?hostId=&q=&limit=
func (s *Server) handleListAgentSessions(w http.ResponseWriter, r *http.Request) {
	hostID := strings.TrimSpace(r.URL.Query().Get("hostId"))
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	limit := 50
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			limit = n
		}
	}
	var (
		list any
		err  error
	)
	if q != "" {
		list, err = s.Store.SearchAgentSessions(q, hostID, limit)
	} else {
		list, err = s.Store.ListAgentSessions(hostID, limit)
	}
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"sessions": list})
}

// POST /v1/agent/sessions  {hostId?, title?}
func (s *Server) handleCreateAgentSession(w http.ResponseWriter, r *http.Request) {
	var body struct {
		HostID string `json:"hostId"`
		Title  string `json:"title"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil && err.Error() != "EOF" {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	id := uuid.NewString()
	title := strings.TrimSpace(body.Title)
	if title == "" {
		title = "新会话"
	}
	if err := s.Store.EnsureAgentSession(id, body.HostID, title); err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	_ = s.Store.RenameAgentSession(id, title)
	sess, err := s.Store.GetAgentSession(id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, sess)
}

// GET /v1/agent/sessions/{id}
func (s *Server) handleGetAgentSession(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	sess, err := s.Store.GetAgentSession(id)
	if err == sql.ErrNoRows {
		writeErr(w, http.StatusNotFound, "session not found")
		return
	}
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, sess)
}

// GET /v1/agent/sessions/{id}/messages?limit=
func (s *Server) handleGetAgentSessionMessages(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	limit := 200
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			limit = n
		}
	}
	if _, err := s.Store.GetAgentSession(id); err != nil && err != sql.ErrNoRows {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	msgs, err := s.Store.ListChatRecent(id, limit)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"sessionId": id,
		"messages":  msgs,
	})
}

// PATCH /v1/agent/sessions/{id}
// {title?} and/or overrides:
//   ovMaxRounds (null clears), ovTemperature, ovConfirm (null|0|1), ovPrompt
// Use clearOverrides:true to wipe all overrides.
func (s *Server) handlePatchAgentSession(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		Title          *string  `json:"title"`
		ClearOverrides bool     `json:"clearOverrides"`
		OvMaxRounds    *int     `json:"ovMaxRounds"`
		OvTemperature  *float64 `json:"ovTemperature"`
		OvConfirm      *int     `json:"ovConfirm"`
		OvPrompt       *string  `json:"ovPrompt"`
		// Present flags: client may send null to clear individual fields via explicit JSON null
		// handled by optional wrappers below for "set null" semantics.
		HasOvMaxRounds   bool `json:"-"`
		HasOvTemperature bool `json:"-"`
		HasOvConfirm     bool `json:"-"`
		HasOvPrompt      bool `json:"-"`
	}
	raw := map[string]json.RawMessage{}
	if err := json.NewDecoder(r.Body).Decode(&raw); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	if v, ok := raw["title"]; ok {
		var t string
		if json.Unmarshal(v, &t) == nil {
			tt := t
			body.Title = &tt
		}
	}
	if v, ok := raw["clearOverrides"]; ok {
		_ = json.Unmarshal(v, &body.ClearOverrides)
	}
	if v, ok := raw["ovMaxRounds"]; ok {
		body.HasOvMaxRounds = true
		if string(v) != "null" {
			var n int
			if json.Unmarshal(v, &n) == nil {
				body.OvMaxRounds = &n
			}
		}
	}
	if v, ok := raw["ovTemperature"]; ok {
		body.HasOvTemperature = true
		if string(v) != "null" {
			var f float64
			if json.Unmarshal(v, &f) == nil {
				body.OvTemperature = &f
			}
		}
	}
	if v, ok := raw["ovConfirm"]; ok {
		body.HasOvConfirm = true
		if string(v) != "null" {
			var n int
			if json.Unmarshal(v, &n) == nil {
				body.OvConfirm = &n
			}
		}
	}
	if v, ok := raw["ovPrompt"]; ok {
		body.HasOvPrompt = true
		if string(v) != "null" {
			var s2 string
			if json.Unmarshal(v, &s2) == nil {
				body.OvPrompt = &s2
			}
		}
	}

	if body.Title != nil {
		if err := s.Store.RenameAgentSession(id, *body.Title); err == sql.ErrNoRows {
			writeErr(w, http.StatusNotFound, "session not found")
			return
		} else if err != nil {
			writeErr(w, http.StatusBadRequest, err.Error())
			return
		}
	}

	if body.ClearOverrides || body.HasOvMaxRounds || body.HasOvTemperature || body.HasOvConfirm || body.HasOvPrompt {
		// Load current, merge: fields not present keep existing; present null → clear.
		cur, err := s.Store.GetAgentSession(id)
		if err == sql.ErrNoRows {
			writeErr(w, http.StatusNotFound, "session not found")
			return
		}
		if err != nil {
			writeErr(w, http.StatusInternalServerError, err.Error())
			return
		}
		rounds, temp, conf, prompt := cur.OvMaxRounds, cur.OvTemperature, cur.OvConfirm, cur.OvPrompt
		if body.ClearOverrides {
			rounds, temp, conf, prompt = nil, nil, nil, nil
		} else {
			if body.HasOvMaxRounds {
				rounds = body.OvMaxRounds
			}
			if body.HasOvTemperature {
				temp = body.OvTemperature
			}
			if body.HasOvConfirm {
				conf = body.OvConfirm
			}
			if body.HasOvPrompt {
				prompt = body.OvPrompt
			}
		}
		if err := s.Store.UpdateAgentSessionOverrides(id, rounds, temp, conf, prompt); err != nil {
			writeErr(w, http.StatusBadRequest, err.Error())
			return
		}
	}

	sess, err := s.Store.GetAgentSession(id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, sess)
}

// GET /v1/agent/sessions/{id}/memory
func (s *Server) handleGetAgentSessionMemory(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	mem, err := s.Store.GetSessionMemory(id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, mem)
}

// DELETE /v1/agent/sessions/{id}/memory
func (s *Server) handleDeleteAgentSessionMemory(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := s.Store.DeleteSessionMemory(id); err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "sessionId": id})
}

// DELETE /v1/agent/sessions/{id}
func (s *Server) handleDeleteAgentSession(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := s.Store.DeleteAgentSession(id); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "id": id})
}
