package api

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"
)

func (s *Server) withAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path
		// health + websocket PTY self-authenticate
		if path == "/v1/health" || path == "/v1/pty" || strings.HasSuffix(path, "/pty") {
			next.ServeHTTP(w, r)
			return
		}
		tok := r.Header.Get("X-Local-Token")
		if s.LocalToken != "" && tok != s.LocalToken {
			writeErr(w, http.StatusUnauthorized, "invalid or missing X-Local-Token")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Allow local WebView / file / localhost
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, X-Local-Token")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":         true,
		"service":    "ssh-ai-agent-backend",
		"version":    Version,
		"startedAt":  s.StartedAt.Format(time.RFC3339),
		"listenHint": "127.0.0.1 only",
		"features":   []string{"exec", "probe", "agent", "audit", "pty", "sftp", "tofu", "stream", "tokstream", "models", "longmem", "fscopy", "fsmove", "sessions"},
	})
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		log.Printf("write json: %v", err)
	}
}

func writeErr(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]any{"error": msg})
}
