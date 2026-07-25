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

// PATCH /v1/agent/sessions/{id}  {title}
func (s *Server) handlePatchAgentSession(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		Title string `json:"title"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	if err := s.Store.RenameAgentSession(id, body.Title); err == sql.ErrNoRows {
		writeErr(w, http.StatusNotFound, "session not found")
		return
	} else if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	sess, err := s.Store.GetAgentSession(id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, sess)
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
