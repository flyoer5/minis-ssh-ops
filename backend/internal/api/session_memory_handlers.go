package api

import "net/http"

func (s *Server) handleListSessionMemory(w http.ResponseWriter, r *http.Request) {
	list, err := s.Store.ListSessionMemories()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"entries": list})
}

func (s *Server) handleDeleteSessionMemory(w http.ResponseWriter, r *http.Request) {
	if r.URL.Query().Get("all") == "1" || r.URL.Query().Get("all") == "true" {
		n, err := s.Store.DeleteAllSessionMemory()
		if err != nil {
			writeErr(w, http.StatusInternalServerError, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "deleted": n})
		return
	}
	sid := r.URL.Query().Get("sessionId")
	if sid == "" {
		writeErr(w, http.StatusBadRequest, "sessionId required (or all=1)")
		return
	}
	if err := s.Store.DeleteSessionMemory(sid); err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "sessionId": sid})
}
