package api

import (
	"encoding/json"
	"net/http"
	"strconv"
)

func (s *Server) handleListKnownHosts(w http.ResponseWriter, r *http.Request) {
	if s.HostKeys == nil {
		writeJSON(w, http.StatusOK, map[string]any{"entries": []any{}})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"entries": s.HostKeys.List()})
}

func (s *Server) handleDeleteKnownHost(w http.ResponseWriter, r *http.Request) {
	// Prefer query params (DELETE body is unreliable on some clients).
	// all=1 clears every trusted key.
	if r.URL.Query().Get("all") == "1" || r.URL.Query().Get("all") == "true" {
		if s.HostKeys == nil {
			writeJSON(w, http.StatusOK, map[string]any{"ok": true, "deleted": 0})
			return
		}
		n, err := s.HostKeys.Clear()
		if err != nil {
			writeErr(w, http.StatusInternalServerError, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "deleted": n})
		return
	}
	host := r.URL.Query().Get("host")
	port := 22
	if p := r.URL.Query().Get("port"); p != "" {
		if n, err := strconv.Atoi(p); err == nil && n > 0 {
			port = n
		}
	}
	if host == "" {
		var body struct {
			Host string `json:"host"`
			Port int    `json:"port"`
		}
		_ = json.NewDecoder(r.Body).Decode(&body)
		host = body.Host
		if body.Port > 0 {
			port = body.Port
		}
	}
	if host == "" {
		writeErr(w, http.StatusBadRequest, "host required")
		return
	}
	if s.HostKeys == nil {
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
		return
	}
	if err := s.HostKeys.Delete(host, port); err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}
