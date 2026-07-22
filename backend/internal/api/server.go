package api

import (
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/sshx"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/store"
)

type Server struct {
	Store      *store.Store
	LocalToken string
	HostKeys  *sshx.HostKeyStore
	StartedAt  time.Time
	mux        *http.ServeMux
}

func New(st *store.Store, localToken string, hostKeys *sshx.HostKeyStore) *Server {
	s := &Server{Store: st, LocalToken: localToken, HostKeys: hostKeys, StartedAt: time.Now().UTC()}
	s.mux = http.NewServeMux()
	s.routes()
	return s
}

func (s *Server) Handler() http.Handler {
	return s.withCORS(s.withAuth(s.mux))
}

func (s *Server) routes() {
	s.mux.HandleFunc("GET /v1/health", s.handleHealth)
	s.mux.HandleFunc("GET /v1/settings/llm", s.handleGetLLM)
	s.mux.HandleFunc("PUT /v1/settings/llm", s.handlePutLLM)
	s.mux.HandleFunc("GET /v1/hosts", s.handleListHosts)
	s.mux.HandleFunc("POST /v1/hosts", s.handleCreateHost)
	s.mux.HandleFunc("GET /v1/hosts/{id}", s.handleGetHost)
	s.mux.HandleFunc("PUT /v1/hosts/{id}", s.handleUpdateHost)
	s.mux.HandleFunc("DELETE /v1/hosts/{id}", s.handleDeleteHost)
	// exec with risk gate (confirmed field supported)
	s.mux.HandleFunc("POST /v1/hosts/{id}/exec", s.handleExecV2)
	s.mux.HandleFunc("POST /v1/hosts/{id}/probe", s.handleProbe)
	s.mux.HandleFunc("POST /v1/agent/plan", s.handleAgentPlan)
	s.mux.HandleFunc("POST /v1/agent/chat", s.handleAgentChat)
	s.mux.HandleFunc("POST /v1/agent/exec-step", s.handleAgentExecStep)
	s.mux.HandleFunc("GET /v1/audit", s.handleAudit)
	s.mux.HandleFunc("GET /v1/known-hosts", s.handleListKnownHosts)
	s.mux.HandleFunc("DELETE /v1/known-hosts", s.handleDeleteKnownHost)
	s.mux.HandleFunc("POST /v1/hosts/{id}/fs/list", s.handleFSList)
	s.mux.HandleFunc("POST /v1/hosts/{id}/fs/read", s.handleFSRead)
	s.mux.HandleFunc("POST /v1/hosts/{id}/fs/write", s.handleFSWrite)
	// Interactive PTY (auth handled inside; needed for WS upgrade path)
	s.mux.HandleFunc("/v1/hosts/{id}/pty", s.handlePtyWSHost)
	s.mux.HandleFunc("/v1/pty", s.handlePtyWS)
}

func (s *Server) handlePtyWSHost(w http.ResponseWriter, r *http.Request) {
	// normalize host id into query for shared handler
	id := r.PathValue("id")
	q := r.URL.Query()
	if q.Get("hostId") == "" && id != "" {
		q.Set("hostId", id)
		r.URL.RawQuery = q.Encode()
	}
	s.handlePtyWS(w, r)
}

func (s *Server) withAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path
		// health + websocket PTY self-authenticate
		if path == "/v1/health" || path == "/v1/pty" || strings.HasSuffix(path, "/pty") {
			next.ServeHTTP(w, r)
			return
		}
		tok := r.Header.Get("X-Local-Token")
		if tok == "" {
			tok = r.URL.Query().Get("token")
		}
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
		"ok":        true,
		"service":   "ssh-ai-agent-backend",
		"version":   "1.1.1",
		"startedAt": s.StartedAt.Format(time.RFC3339),
		"listenHint": "127.0.0.1 only",
		"features":  []string{"exec","probe","agent","audit","pty","sftp","tofu"},
	})
}

func (s *Server) handleGetLLM(w http.ResponseWriter, r *http.Request) {
	st, err := s.Store.GetLLM()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, st)
}

func (s *Server) handlePutLLM(w http.ResponseWriter, r *http.Request) {
	var in store.LLMSettings
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	out, err := s.Store.PutLLM(in)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) handleListHosts(w http.ResponseWriter, r *http.Request) {
	list, err := s.Store.ListHosts()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"hosts": list})
}

func (s *Server) handleGetHost(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	h, err := s.Store.GetHost(id)
	if errors.Is(err, sql.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "host not found")
		return
	}
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, h)
}

func (s *Server) handleCreateHost(w http.ResponseWriter, r *http.Request) {
	var in store.Host
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	if strings.TrimSpace(in.Host) == "" || strings.TrimSpace(in.Username) == "" {
		writeErr(w, http.StatusBadRequest, "host and username required")
		return
	}
	if in.Password == "" && in.PrivateKeyPEM == "" {
		writeErr(w, http.StatusBadRequest, "password or privateKeyPem required")
		return
	}
	out, err := s.Store.CreateHost(in)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, out)
}

func (s *Server) handleUpdateHost(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var in store.Host
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	out, err := s.Store.UpdateHost(id, in)
	if errors.Is(err, sql.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "host not found")
		return
	}
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) handleDeleteHost(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	err := s.Store.DeleteHost(id)
	if errors.Is(err, sql.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "host not found")
		return
	}
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

type execBody struct {
	Command string `json:"command"`
}

func (s *Server) handleExec(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body execBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || strings.TrimSpace(body.Command) == "" {
		writeErr(w, http.StatusBadRequest, "command required")
		return
	}
	h, err := s.Store.GetHost(id)
	if errors.Is(err, sql.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "host not found")
		return
	}
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	sec, err := s.Store.GetHostSecrets(id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	res, err := sshx.Exec(sshx.ConnectParams{
		Host:          h.Host,
		Port:          h.Port,
		Username:      h.Username,
		Password:      sec.Password,
		PrivateKeyPEM: sec.PrivateKeyPEM,
		Passphrase:    sec.Passphrase,
		HostKeys:      s.HostKeys,
	}, body.Command)
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, res)
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
