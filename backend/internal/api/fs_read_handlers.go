package api

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strings"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/sshx"
)

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
		body.MaxBytes = 32 << 20 // 32MiB default download cap
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
