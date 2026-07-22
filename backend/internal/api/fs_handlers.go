package api

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/sshx"
)

func (s *Server) connectParams(hostID string) (sshx.ConnectParams, error) {
	h, err := s.Store.GetHost(hostID)
	if err != nil {
		return sshx.ConnectParams{}, err
	}
	sec, err := s.Store.GetHostSecrets(hostID)
	if err != nil {
		return sshx.ConnectParams{}, err
	}
	return sshx.ConnectParams{
		Host:          h.Host,
		Port:          h.Port,
		Username:      h.Username,
		Password:      sec.Password,
		PrivateKeyPEM: sec.PrivateKeyPEM,
		Passphrase:    sec.Passphrase,
		HostKeys:      s.HostKeys,
	}, nil
}

func (s *Server) handleFSList(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		Path string `json:"path"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	p, err := s.connectParams(id)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	entries, err := sshx.ListDir(p, body.Path)
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"path": body.Path, "entries": entries})
}

func (s *Server) handleFSRead(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		Path     string `json:"path"`
		MaxBytes int64  `json:"maxBytes"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || strings.TrimSpace(body.Path) == "" {
		writeErr(w, http.StatusBadRequest, "path required")
		return
	}
	p, err := s.connectParams(id)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	data, err := sshx.ReadFile(p, body.Path, body.MaxBytes)
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"path": body.Path, "size": len(data), "text": string(data)})
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

func (s *Server) handleListKnownHosts(w http.ResponseWriter, r *http.Request) {
	if s.HostKeys == nil {
		writeJSON(w, http.StatusOK, map[string]any{"entries": []any{}})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"entries": s.HostKeys.List()})
}

func (s *Server) handleDeleteKnownHost(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Host string `json:"host"`
		Port int    `json:"port"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Host == "" {
		writeErr(w, http.StatusBadRequest, "host required")
		return
	}
	if s.HostKeys == nil {
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
		return
	}
	if err := s.HostKeys.Delete(body.Host, body.Port); err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}
