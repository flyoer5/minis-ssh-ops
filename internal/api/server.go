package api

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	"minis-ssh-ops/internal/agent"
	"minis-ssh-ops/internal/sshx"
	"minis-ssh-ops/internal/storage"
)

type Server struct {
	Store  *storage.Store
	Pool   *sshx.Pool
	Agent  *agent.Agent
	Token  string
	Static http.FileSystem

	mu    sync.Mutex
	plans map[string]*agent.Plan // planID -> plan
}

func New(store *storage.Store, pool *sshx.Pool, token string, static http.FileSystem) *Server {
	if token == "" {
		token = randomToken(16)
	}
	return &Server{
		Store:  store,
		Pool:   pool,
		Agent:  agent.New(store, pool),
		Token:  token,
		Static: static,
		plans:  make(map[string]*agent.Plan),
	}
}

func randomToken(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/health", s.withAuth(s.handleHealth))
	mux.HandleFunc("/api/token", s.handleTokenInfo) // bootstrap: only shows if same machine; still needs nothing for first paint — actually protect
	mux.HandleFunc("/api/hosts", s.withAuth(s.handleHosts))
	mux.HandleFunc("/api/hosts/", s.withAuth(s.handleHostSub))
	mux.HandleFunc("/api/llm", s.withAuth(s.handleLLM))
	mux.HandleFunc("/api/exec", s.withAuth(s.handleExec))
	mux.HandleFunc("/api/probe", s.withAuth(s.handleProbe))
	mux.HandleFunc("/api/agent/plan", s.withAuth(s.handleAgentPlan))
	mux.HandleFunc("/api/agent/exec-step", s.withAuth(s.handleAgentExecStep))
	mux.HandleFunc("/api/audit", s.withAuth(s.handleAudit))
	mux.HandleFunc("/api/chat/", s.withAuth(s.handleChat))
	mux.HandleFunc("/api/fs/list", s.withAuth(s.handleFSList))
	mux.HandleFunc("/api/fs/read", s.withAuth(s.handleFSRead))
	mux.HandleFunc("/api/fs/write", s.withAuth(s.handleFSWrite))
	mux.HandleFunc("/api/fs/mkdir", s.withAuth(s.handleFSMkdir))
	mux.HandleFunc("/api/fs/remove", s.withAuth(s.handleFSRemove))
	mux.HandleFunc("/api/fs/stat", s.withAuth(s.handleFSStat))
	// WebSocket PTY — auth via ?token= (withAuth not used: upgrade path)
	mux.HandleFunc("/api/pty", s.handlePtyWS)

	if s.Static != nil {
		mux.Handle("/", http.FileServer(s.Static))
	} else {
		mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "text/plain; charset=utf-8")
			fmt.Fprintf(w, "minis-ssh-ops opsd ok\n")
		})
	}
	return s.cors(mux)
}

func (s *Server) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Ops-Token")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(204)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) withAuth(fn http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		tok := r.Header.Get("X-Ops-Token")
		if tok == "" {
			auth := r.Header.Get("Authorization")
			if strings.HasPrefix(auth, "Bearer ") {
				tok = strings.TrimPrefix(auth, "Bearer ")
			}
		}
		if tok == "" {
			tok = r.URL.Query().Get("token")
		}
		if tok != s.Token {
			writeErr(w, 401, "unauthorized")
			return
		}
		fn(w, r)
	}
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]any{"error": msg})
}

func decodeJSON(r *http.Request, v any) error {
	defer r.Body.Close()
	return json.NewDecoder(r.Body).Decode(v)
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, 200, map[string]any{"ok": true, "time": time.Now().UTC()})
}

func (s *Server) handleTokenInfo(w http.ResponseWriter, r *http.Request) {
	// Only expose token when request comes from loopback (local UI bootstrap).
	host, _, _ := net.SplitHostPort(r.RemoteAddr)
	ip := net.ParseIP(host)
	if ip == nil || !ip.IsLoopback() {
		// try X-Forwarded not trusted; deny
		writeErr(w, 403, "token bootstrap only on loopback")
		return
	}
	writeJSON(w, 200, map[string]any{"token": s.Token})
}

// --- hosts ---

func (s *Server) handleHosts(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		list, err := s.Store.ListHosts()
		if err != nil {
			writeErr(w, 500, err.Error())
			return
		}
		if list == nil {
			list = []storage.Host{}
		}
		writeJSON(w, 200, map[string]any{"hosts": list})
	case http.MethodPost:
		var req struct {
			ID         string `json:"id"`
			Name       string `json:"name"`
			Host       string `json:"host"`
			Port       int    `json:"port"`
			User       string `json:"user"`
			AuthType   string `json:"auth_type"`
			Password   string `json:"password"`
			PrivateKey string `json:"private_key"`
			Passphrase string `json:"passphrase"`
			Tags       string `json:"tags"`
		}
		if err := decodeJSON(r, &req); err != nil {
			writeErr(w, 400, "bad json")
			return
		}
		if req.Name == "" || req.Host == "" || req.User == "" {
			writeErr(w, 400, "name, host, user required")
			return
		}
		if req.Port == 0 {
			req.Port = 22
		}
		if req.AuthType == "" {
			if req.PrivateKey != "" {
				req.AuthType = "key"
			} else {
				req.AuthType = "password"
			}
		}
		if req.ID == "" {
			req.ID = uuid.NewString()
		}
		h := &storage.Host{
			ID: req.ID, Name: req.Name, Host: req.Host, Port: req.Port,
			User: req.User, AuthType: req.AuthType, Tags: req.Tags,
		}
		var sec *storage.HostSecret
		if req.Password != "" || req.PrivateKey != "" {
			sec = &storage.HostSecret{
				Password: req.Password, PrivateKey: req.PrivateKey, Passphrase: req.Passphrase,
			}
		}
		if err := s.Store.UpsertHost(h, sec); err != nil {
			writeErr(w, 500, err.Error())
			return
		}
		h.HasSecret = sec != nil
		writeJSON(w, 200, map[string]any{"host": h})
	default:
		writeErr(w, 405, "method not allowed")
	}
}

func (s *Server) handleHostSub(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/api/hosts/")
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) == 0 || parts[0] == "" {
		writeErr(w, 404, "not found")
		return
	}
	id := parts[0]
	action := ""
	if len(parts) > 1 {
		action = parts[1]
	}

	switch {
	case action == "" && r.Method == http.MethodGet:
		h, _, err := s.Store.GetHost(id)
		if err != nil {
			writeErr(w, 404, "host not found")
			return
		}
		writeJSON(w, 200, map[string]any{"host": h})
	case action == "" && r.Method == http.MethodDelete:
		s.Pool.Remove(id)
		if err := s.Store.DeleteHost(id); err != nil {
			writeErr(w, 500, err.Error())
			return
		}
		writeJSON(w, 200, map[string]any{"ok": true})
	case action == "connect" && r.Method == http.MethodPost:
		h, sec, err := s.Store.GetHost(id)
		if err != nil {
			writeErr(w, 404, "host not found")
			return
		}
		if sec == nil {
			writeErr(w, 400, "no credentials stored")
			return
		}
		cli, err := sshx.Dial(h.Host, h.Port, sshx.Auth{
			User: h.User, Password: sec.Password, PrivateKey: sec.PrivateKey, Passphrase: sec.Passphrase,
		}, 15*time.Second)
		if err != nil {
			writeErr(w, 502, err.Error())
			return
		}
		info, err := cli.TestConnection()
		if err != nil {
			_ = cli.Close()
			writeErr(w, 502, err.Error())
			return
		}
		s.Pool.Put(id, cli)
		writeJSON(w, 200, map[string]any{"ok": true, "banner": info})
	case action == "disconnect" && r.Method == http.MethodPost:
		s.Pool.Remove(id)
		writeJSON(w, 200, map[string]any{"ok": true})
	default:
		writeErr(w, 404, "not found")
	}
}

func (s *Server) handleLLM(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		m, err := s.Store.GetLLMMasked()
		if err != nil {
			writeErr(w, 500, err.Error())
			return
		}
		writeJSON(w, 200, m)
	case http.MethodPut, http.MethodPost:
		var req storage.LLMConfig
		if err := decodeJSON(r, &req); err != nil {
			writeErr(w, 400, "bad json")
			return
		}
		// merge: if api_key empty, keep old
		old, _ := s.Store.GetLLM()
		if req.APIKey == "" && old != nil {
			req.APIKey = old.APIKey
		}
		if req.BaseURL == "" && old != nil {
			req.BaseURL = old.BaseURL
		}
		if req.Model == "" && old != nil {
			req.Model = old.Model
		}
		if err := s.Store.SetLLM(req); err != nil {
			writeErr(w, 500, err.Error())
			return
		}
		m, _ := s.Store.GetLLMMasked()
		writeJSON(w, 200, m)
	default:
		writeErr(w, 405, "method not allowed")
	}
}

func (s *Server) handleExec(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, 405, "method not allowed")
		return
	}
	var req struct {
		HostID    string `json:"host_id"`
		Command   string `json:"command"`
		Confirmed bool   `json:"confirmed"`
		SessionID string `json:"session_id"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeErr(w, 400, "bad json")
		return
	}
	if req.HostID == "" || req.Command == "" {
		writeErr(w, 400, "host_id and command required")
		return
	}
	if req.SessionID == "" {
		req.SessionID = "manual"
	}
	risk := agent.Classify(req.Command)
	if risk == agent.RiskBlocked {
		_ = s.Store.AddAudit(&storage.AuditEntry{
			HostID: req.HostID, SessionID: req.SessionID, Command: req.Command,
			Risk: string(risk), Confirmed: false, ExitCode: -1, Stderr: "blocked",
		})
		writeErr(w, 403, "command blocked by safety policy")
		return
	}
	if agent.NeedsConfirm(risk) && !req.Confirmed {
		writeJSON(w, 409, map[string]any{
			"error":   "confirmation required",
			"risk":    risk,
			"command": req.Command,
		})
		return
	}
	step := agent.PlanStep{Command: req.Command, Title: "manual"}
	out, err := s.Agent.ExecStep(req.HostID, req.SessionID, step, req.Confirmed || agent.AllowedToAutoRun(risk))
	if err != nil && out == nil {
		writeErr(w, 502, err.Error())
		return
	}
	writeJSON(w, 200, map[string]any{"step": out, "error": errString(err)})
}

func (s *Server) handleProbe(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, 405, "method not allowed")
		return
	}
	var req struct {
		HostID string `json:"host_id"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeErr(w, 400, "bad json")
		return
	}
	data, err := s.Agent.QuickProbe(req.HostID)
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	writeJSON(w, 200, data)
}

func (s *Server) handleAgentPlan(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, 405, "method not allowed")
		return
	}
	var req struct {
		HostID    string `json:"host_id"`
		Goal      string `json:"goal"`
		SessionID string `json:"session_id"`
		Context   string `json:"context"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeErr(w, 400, "bad json")
		return
	}
	if req.HostID == "" || req.Goal == "" {
		writeErr(w, 400, "host_id and goal required")
		return
	}
	if req.SessionID == "" {
		req.SessionID = uuid.NewString()
	}
	plan, err := s.Agent.Plan(req.SessionID, req.HostID, req.Goal, req.Context)
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	planID := uuid.NewString()
	s.mu.Lock()
	s.plans[planID] = plan
	s.mu.Unlock()
	writeJSON(w, 200, map[string]any{
		"plan_id":    planID,
		"session_id": req.SessionID,
		"plan":       plan,
	})
}

func (s *Server) handleAgentExecStep(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, 405, "method not allowed")
		return
	}
	var req struct {
		HostID    string `json:"host_id"`
		SessionID string `json:"session_id"`
		PlanID    string `json:"plan_id"`
		StepID    int    `json:"step_id"`
		Command   string `json:"command"`
		Confirmed bool   `json:"confirmed"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeErr(w, 400, "bad json")
		return
	}
	step := agent.PlanStep{ID: req.StepID, Command: req.Command}
	if req.PlanID != "" {
		s.mu.Lock()
		p := s.plans[req.PlanID]
		s.mu.Unlock()
		if p != nil {
			for _, st := range p.Steps {
				if st.ID == req.StepID || (req.StepID == 0 && st.Command == req.Command) {
					step = st
					break
				}
			}
		}
	}
	if step.Command == "" {
		writeErr(w, 400, "command required")
		return
	}
	if req.SessionID == "" {
		req.SessionID = "agent"
	}
	out, err := s.Agent.ExecStep(req.HostID, req.SessionID, step, req.Confirmed)
	if err != nil && out == nil {
		writeErr(w, 502, err.Error())
		return
	}
	// update plan memory
	if req.PlanID != "" {
		s.mu.Lock()
		if p := s.plans[req.PlanID]; p != nil {
			for i := range p.Steps {
				if p.Steps[i].ID == out.ID || p.Steps[i].Command == out.Command {
					p.Steps[i] = *out
				}
			}
		}
		s.mu.Unlock()
	}
	code := 200
	if err != nil && strings.Contains(err.Error(), "confirmation required") {
		code = 409
	}
	if err != nil && strings.Contains(err.Error(), "blocked") {
		code = 403
	}
	writeJSON(w, code, map[string]any{"step": out, "error": errString(err)})
}

func (s *Server) handleAudit(w http.ResponseWriter, r *http.Request) {
	list, err := s.Store.ListAudit(100)
	if err != nil {
		writeErr(w, 500, err.Error())
		return
	}
	if list == nil {
		list = []storage.AuditEntry{}
	}
	writeJSON(w, 200, map[string]any{"entries": list})
}

func (s *Server) handleChat(w http.ResponseWriter, r *http.Request) {
	sid := strings.TrimPrefix(r.URL.Path, "/api/chat/")
	if sid == "" {
		writeErr(w, 400, "session id required")
		return
	}
	list, err := s.Store.ListChat(sid, 200)
	if err != nil {
		writeErr(w, 500, err.Error())
		return
	}
	if list == nil {
		list = []storage.ChatMessage{}
	}
	writeJSON(w, 200, map[string]any{"messages": list})
}

func errString(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

// ensureConn returns a pooled SSH client, dialing if needed.
func (s *Server) ensureConn(hostID string) (*sshx.Client, error) {
	if cli := s.Pool.Get(hostID); cli != nil {
		return cli, nil
	}
	h, sec, err := s.Store.GetHost(hostID)
	if err != nil {
		return nil, fmt.Errorf("host: %w", err)
	}
	if sec == nil {
		return nil, fmt.Errorf("no credentials stored")
	}
	cli, err := sshx.Dial(h.Host, h.Port, sshx.Auth{
		User: h.User, Password: sec.Password, PrivateKey: sec.PrivateKey, Passphrase: sec.Passphrase,
	}, 15*time.Second)
	if err != nil {
		return nil, err
	}
	s.Pool.Put(hostID, cli)
	return cli, nil
}

func (s *Server) handleFSList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost && r.Method != http.MethodGet {
		writeErr(w, 405, "method not allowed")
		return
	}
	var hostID, path string
	if r.Method == http.MethodGet {
		hostID = r.URL.Query().Get("host_id")
		path = r.URL.Query().Get("path")
	} else {
		var req struct {
			HostID string `json:"host_id"`
			Path   string `json:"path"`
		}
		if err := decodeJSON(r, &req); err != nil {
			writeErr(w, 400, "bad json")
			return
		}
		hostID, path = req.HostID, req.Path
	}
	if hostID == "" {
		writeErr(w, 400, "host_id required")
		return
	}
	cli, err := s.ensureConn(hostID)
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	entries, err := cli.ListDir(path)
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	if entries == nil {
		entries = []sshx.FileEntry{}
	}
	writeJSON(w, 200, map[string]any{"path": path, "entries": entries})
}

func (s *Server) handleFSRead(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, 405, "method not allowed")
		return
	}
	var req struct {
		HostID   string `json:"host_id"`
		Path     string `json:"path"`
		MaxBytes int64  `json:"max_bytes"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeErr(w, 400, "bad json")
		return
	}
	if req.HostID == "" || req.Path == "" {
		writeErr(w, 400, "host_id and path required")
		return
	}
	cli, err := s.ensureConn(req.HostID)
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	data, err := cli.ReadFile(req.Path, req.MaxBytes)
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	// return as text when possible; UI can treat as string
	writeJSON(w, 200, map[string]any{
		"path": req.Path,
		"size": len(data),
		"text": string(data),
	})
}

func (s *Server) handleFSWrite(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, 405, "method not allowed")
		return
	}
	var req struct {
		HostID    string `json:"host_id"`
		Path      string `json:"path"`
		Content   string `json:"content"`
		Confirmed bool   `json:"confirmed"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeErr(w, 400, "bad json")
		return
	}
	if req.HostID == "" || req.Path == "" {
		writeErr(w, 400, "host_id and path required")
		return
	}
	if !req.Confirmed {
		writeJSON(w, 409, map[string]any{"error": "confirmation required", "risk": "write", "path": req.Path})
		return
	}
	cli, err := s.ensureConn(req.HostID)
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	if err := cli.WriteFile(req.Path, []byte(req.Content)); err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	_ = s.Store.AddAudit(&storage.AuditEntry{
		HostID: req.HostID, SessionID: "sftp", Command: "sftp:write " + req.Path,
		Risk: "write", Confirmed: true, ExitCode: 0, Stdout: fmt.Sprintf("%d bytes", len(req.Content)),
	})
	writeJSON(w, 200, map[string]any{"ok": true, "path": req.Path, "size": len(req.Content)})
}

func (s *Server) handleFSMkdir(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, 405, "method not allowed")
		return
	}
	var req struct {
		HostID    string `json:"host_id"`
		Path      string `json:"path"`
		Confirmed bool   `json:"confirmed"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeErr(w, 400, "bad json")
		return
	}
	if req.HostID == "" || req.Path == "" {
		writeErr(w, 400, "host_id and path required")
		return
	}
	if !req.Confirmed {
		writeJSON(w, 409, map[string]any{"error": "confirmation required", "risk": "write"})
		return
	}
	cli, err := s.ensureConn(req.HostID)
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	if err := cli.Mkdir(req.Path); err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	_ = s.Store.AddAudit(&storage.AuditEntry{
		HostID: req.HostID, SessionID: "sftp", Command: "sftp:mkdir " + req.Path,
		Risk: "write", Confirmed: true, ExitCode: 0,
	})
	writeJSON(w, 200, map[string]any{"ok": true, "path": req.Path})
}

func (s *Server) handleFSRemove(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, 405, "method not allowed")
		return
	}
	var req struct {
		HostID    string `json:"host_id"`
		Path      string `json:"path"`
		Recursive bool   `json:"recursive"`
		Confirmed bool   `json:"confirmed"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeErr(w, 400, "bad json")
		return
	}
	if req.HostID == "" || req.Path == "" {
		writeErr(w, 400, "host_id and path required")
		return
	}
	// hard deny dangerous paths
	p := strings.TrimSpace(req.Path)
	if p == "/" || p == "" || p == "." || p == ".." {
		writeErr(w, 403, "refusing to remove path")
		return
	}
	if !req.Confirmed {
		writeJSON(w, 409, map[string]any{"error": "confirmation required", "risk": "destructive", "path": req.Path})
		return
	}
	cli, err := s.ensureConn(req.HostID)
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	if err := cli.Remove(req.Path, req.Recursive); err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	_ = s.Store.AddAudit(&storage.AuditEntry{
		HostID: req.HostID, SessionID: "sftp", Command: "sftp:remove " + req.Path,
		Risk: "destructive", Confirmed: true, ExitCode: 0,
	})
	writeJSON(w, 200, map[string]any{"ok": true, "path": req.Path})
}

func (s *Server) handleFSStat(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, 405, "method not allowed")
		return
	}
	var req struct {
		HostID string `json:"host_id"`
		Path   string `json:"path"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeErr(w, 400, "bad json")
		return
	}
	cli, err := s.ensureConn(req.HostID)
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	ent, err := cli.Stat(req.Path)
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	writeJSON(w, 200, map[string]any{"entry": ent})
}

// Listen starts HTTP on addr (e.g. 127.0.0.1:18765).
func (s *Server) Listen(addr string) error {
	log.Printf("opsd listening on http://%s  token=%s", addr, s.Token)
	return http.ListenAndServe(addr, s.Handler())
}
