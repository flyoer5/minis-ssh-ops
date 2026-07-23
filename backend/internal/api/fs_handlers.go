package api

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strconv"
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
	resolved, entries, err := sshx.ListDir(p, body.Path)
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"path": resolved, "entries": entries})
}

func (s *Server) handleFSRead(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		Path     string `json:"path"`
		MaxBytes int64  `json:"maxBytes"`
		// Force: ignore soft text limits (still capped by maxBytes hard limit)
		Force bool `json:"force"`
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
	// Soft editor default 1 MiB; hard default 2 MiB (sshx.ReadFile)
	const softText = int64(1 << 20)
	if body.MaxBytes <= 0 {
		if body.Force {
			body.MaxBytes = 2 << 20
		} else {
			body.MaxBytes = softText
		}
	}
	data, err := sshx.ReadFile(p, body.Path, body.MaxBytes)
	if err != nil {
		// surface size errors as structured response for UI
		msg := err.Error()
		if strings.Contains(msg, "file too large") {
			writeJSON(w, http.StatusOK, map[string]any{
				"path":     body.Path,
				"tooLarge": true,
				"error":    msg,
				"maxBytes": body.MaxBytes,
				"text":     "",
			})
			return
		}
		writeErr(w, http.StatusBadGateway, msg)
		return
	}
	// binary sniff: NUL in first 8KiB
	sample := data
	if len(sample) > 8192 {
		sample = sample[:8192]
	}
	binary := false
	for _, b := range sample {
		if b == 0 {
			binary = true
			break
		}
	}
	if binary && !body.Force {
		writeJSON(w, http.StatusOK, map[string]any{
			"path":   body.Path,
			"size":   len(data),
			"binary": true,
			"text":   "",
			"error":  "looks like binary; open with force or download",
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"path":   body.Path,
		"size":   len(data),
		"binary": binary,
		"text":   string(data),
	})
}

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

func (s *Server) handleFSDownload(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		Path     string `json:"path"`
		MaxBytes int64  `json:"maxBytes"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || strings.TrimSpace(body.Path) == "" {
		writeErr(w, http.StatusBadRequest, "path required")
		return
	}
	if body.MaxBytes <= 0 {
		body.MaxBytes = 8 << 20 // 8MiB
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
	// base64 for binary-safe transport over JSON API
	writeJSON(w, http.StatusOK, map[string]any{
		"path": body.Path,
		"size": len(data),
		"b64":  base64.StdEncoding.EncodeToString(data),
		"name": pathBase(body.Path),
	})
}

func pathBase(p string) string {
	i := strings.LastIndex(p, "/")
	if i < 0 {
		return p
	}
	return p[i+1:]
}

func (s *Server) handleListKnownHosts(w http.ResponseWriter, r *http.Request) {
	if s.HostKeys == nil {
		writeJSON(w, http.StatusOK, map[string]any{"entries": []any{}})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"entries": s.HostKeys.List()})
}

func (s *Server) handleDeleteKnownHost(w http.ResponseWriter, r *http.Request) {
	// Prefer query params (DELETE body is unreliable on some clients).
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
