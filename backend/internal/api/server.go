package api

import (
	"net/http"
	"time"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/sshx"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/store"
)

// Version is the backend build version, injected at build time via
// -ldflags "-X .../api.Version=x.y.z" from app/pubspec.yaml (single source).
var Version = "dev"

type Server struct {
	Store      *store.Store
	LocalToken string
	HostKeys   *sshx.HostKeyStore
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
	s.mux.HandleFunc("GET /v1/settings/llm/models", s.handleListLLMModels)
	s.mux.HandleFunc("GET /v1/hosts", s.handleListHosts)
	s.mux.HandleFunc("POST /v1/hosts", s.handleCreateHost)
	s.mux.HandleFunc("PUT /v1/hosts/reorder", s.handleReorderHosts)
	s.mux.HandleFunc("GET /v1/hosts/{id}", s.handleGetHost)
	s.mux.HandleFunc("PUT /v1/hosts/{id}", s.handleUpdateHost)
	s.mux.HandleFunc("DELETE /v1/hosts/{id}", s.handleDeleteHost)
	// exec with risk gate (confirmed field supported)
	s.mux.HandleFunc("POST /v1/hosts/{id}/exec", s.handleExecV2)
	s.mux.HandleFunc("POST /v1/hosts/{id}/probe", s.handleProbe)
	s.mux.HandleFunc("POST /v1/agent/plan", s.handleAgentPlan)
	s.mux.HandleFunc("POST /v1/agent/chat", s.handleAgentChat)
	s.mux.HandleFunc("POST /v1/agent/chat/stream", s.handleAgentChatStream)
	s.mux.HandleFunc("POST /v1/agent/exec-step", s.handleAgentExecStep)
	// Minis-style durable sessions
	s.mux.HandleFunc("GET /v1/agent/sessions", s.handleListAgentSessions)
	s.mux.HandleFunc("POST /v1/agent/sessions", s.handleCreateAgentSession)
	s.mux.HandleFunc("GET /v1/agent/sessions/{id}", s.handleGetAgentSession)
	s.mux.HandleFunc("GET /v1/agent/sessions/{id}/messages", s.handleGetAgentSessionMessages)
	s.mux.HandleFunc("GET /v1/agent/sessions/{id}/memory", s.handleGetAgentSessionMemory)
	s.mux.HandleFunc("DELETE /v1/agent/sessions/{id}/memory", s.handleDeleteAgentSessionMemory)
	s.mux.HandleFunc("PATCH /v1/agent/sessions/{id}", s.handlePatchAgentSession)
	s.mux.HandleFunc("DELETE /v1/agent/sessions/{id}", s.handleDeleteAgentSession)
	s.mux.HandleFunc("GET /v1/audit", s.handleAudit)
	s.mux.HandleFunc("GET /v1/known-hosts", s.handleListKnownHosts)
	s.mux.HandleFunc("DELETE /v1/known-hosts", s.handleDeleteKnownHost)
	s.mux.HandleFunc("GET /v1/session-memory", s.handleListSessionMemory)
	s.mux.HandleFunc("DELETE /v1/session-memory", s.handleDeleteSessionMemory)
	s.mux.HandleFunc("POST /v1/hosts/{id}/fs/list", s.handleFSList)
	s.mux.HandleFunc("POST /v1/hosts/{id}/fs/read", s.handleFSRead)
	s.mux.HandleFunc("POST /v1/hosts/{id}/fs/write", s.handleFSWrite)
	s.mux.HandleFunc("POST /v1/hosts/{id}/fs/mkdir", s.handleFSMkdir)
	s.mux.HandleFunc("POST /v1/hosts/{id}/fs/remove", s.handleFSRemove)
	s.mux.HandleFunc("POST /v1/hosts/{id}/fs/rename", s.handleFSRename)
	s.mux.HandleFunc("POST /v1/hosts/{id}/fs/download", s.handleFSDownload)
	s.mux.HandleFunc("POST /v1/hosts/{id}/fs/copy", s.handleFSCopy)
	s.mux.HandleFunc("POST /v1/hosts/{id}/fs/move", s.handleFSMove)
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
