package api

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/sshx"
)

func (s *Server) handleFSMove(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		Src       string `json:"src"`
		Dest      string `json:"dest"`
		Confirmed bool   `json:"confirmed"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || strings.TrimSpace(body.Src) == "" || strings.TrimSpace(body.Dest) == "" {
		writeErr(w, http.StatusBadRequest, "src and dest required")
		return
	}
	if !body.Confirmed {
		writeJSON(w, http.StatusConflict, map[string]any{"error": "confirmation required", "risk": "write", "src": body.Src, "dest": body.Dest})
		return
	}
	p, err := s.connectParams(id)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	files, dirs, method, err := sshx.Move(p, body.Src, body.Dest)
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":     true,
		"src":    body.Src,
		"dest":   body.Dest,
		"files":  files,
		"dirs":   dirs,
		"method": method,
	})
}

func (s *Server) handleFSWrite(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		Path      string `json:"path"`
		Content   string `json:"content"`
		Confirmed bool   `json:"confirmed"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || strings.TrimSpace(body.Path) == "" {
		writeErr(w, http.StatusBadRequest, "path required")
		return
	}
	if !body.Confirmed {
		writeJSON(w, http.StatusConflict, map[string]any{"error": "confirmation required", "risk": "write", "path": body.Path})
		return
	}
	p, err := s.connectParams(id)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := sshx.WriteFile(p, body.Path, []byte(body.Content)); err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "path": body.Path, "size": len(body.Content)})
}

func (s *Server) handleFSMkdir(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		Path      string `json:"path"`
		Confirmed bool   `json:"confirmed"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || strings.TrimSpace(body.Path) == "" {
		writeErr(w, http.StatusBadRequest, "path required")
		return
	}
	if !body.Confirmed {
		writeJSON(w, http.StatusConflict, map[string]any{"error": "confirmation required", "risk": "write"})
		return
	}
	p, err := s.connectParams(id)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := sshx.Mkdir(p, body.Path); err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "path": body.Path})
}

func (s *Server) handleFSRemove(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		Path      string `json:"path"`
		Recursive bool   `json:"recursive"`
		Confirmed bool   `json:"confirmed"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || strings.TrimSpace(body.Path) == "" {
		writeErr(w, http.StatusBadRequest, "path required")
		return
	}
	if body.Path == "/" {
		writeErr(w, http.StatusForbidden, "refusing to remove /")
		return
	}
	if !body.Confirmed {
		writeJSON(w, http.StatusConflict, map[string]any{"error": "confirmation required", "risk": "destructive", "path": body.Path})
		return
	}
	p, err := s.connectParams(id)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := sshx.Remove(p, body.Path, body.Recursive); err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "path": body.Path})
}

func (s *Server) handleFSRename(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		OldPath   string `json:"oldPath"`
		NewPath   string `json:"newPath"`
		Confirmed bool   `json:"confirmed"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.OldPath == "" || body.NewPath == "" {
		writeErr(w, http.StatusBadRequest, "oldPath and newPath required")
		return
	}
	if !body.Confirmed {
		writeJSON(w, http.StatusConflict, map[string]any{"error": "confirmation required", "risk": "write"})
		return
	}
	p, err := s.connectParams(id)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := sshx.Rename(p, body.OldPath, body.NewPath); err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "oldPath": body.OldPath, "newPath": body.NewPath})
}

func (s *Server) handleFSCopy(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		Src       string `json:"src"`
		Dest      string `json:"dest"`
		Confirmed bool   `json:"confirmed"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || strings.TrimSpace(body.Src) == "" || strings.TrimSpace(body.Dest) == "" {
		writeErr(w, http.StatusBadRequest, "src and dest required")
		return
	}
	if !body.Confirmed {
		writeJSON(w, http.StatusConflict, map[string]any{"error": "confirmation required", "risk": "write", "src": body.Src, "dest": body.Dest})
		return
	}
	p, err := s.connectParams(id)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	files, dirs, err := sshx.Copy(p, body.Src, body.Dest)
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":    true,
		"src":   body.Src,
		"dest":  body.Dest,
		"files": files,
		"dirs":  dirs,
	})
}
