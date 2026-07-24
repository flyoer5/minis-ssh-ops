package store

import (
	"database/sql"
	"fmt"
	"strings"
	"time"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/crypto"
	"github.com/google/uuid"
	_ "modernc.org/sqlite"
)

type Store struct {
	db  *sql.DB
	box *crypto.Box
}

type Host struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	Host          string `json:"host"`
	Port          int    `json:"port"`
	Username      string `json:"username"`
	HasPassword   bool   `json:"hasPassword"`
	HasPrivateKey bool   `json:"hasPrivateKey"`
	// Write-only fields (accepted on create/update, never returned plaintext)
	Password       string `json:"password,omitempty"`
	PrivateKeyPEM  string `json:"privateKeyPem,omitempty"`
	Passphrase     string `json:"passphrase,omitempty"`
	CreatedAt      string `json:"createdAt,omitempty"`
	UpdatedAt      string `json:"updatedAt,omitempty"`
}

type LLMSettings struct {
	BaseURL        string `json:"baseUrl"`
	APIKey         string `json:"apiKey,omitempty"` // write full; read may be masked
	APIKeySet      bool   `json:"apiKeySet"`
	APIKeyMasked   string `json:"apiKeyMasked,omitempty"`
	Model          string `json:"model"`
	TimeoutSeconds int    `json:"timeoutSeconds"`
	// ThinkingLevel: none|low|medium|high|xhigh|auto (Minis thinking_override style)
	ThinkingLevel string `json:"thinkingLevel,omitempty"`
}

type HostSecrets struct {
	Password      string
	PrivateKeyPEM string
	Passphrase    string
}

func Open(path string, box *crypto.Box) (*Store, error) {
	db, err := sql.Open("sqlite", path+"?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)")
	if err != nil {
		return nil, err
	}
	s := &Store{db: db, box: box}
	if err := s.migrate(); err != nil {
		_ = db.Close()
		return nil, err
	}
	return s, nil
}

func (s *Store) Close() error { return s.db.Close() }

func (s *Store) migrate() error {
	_, err := s.db.Exec(`
CREATE TABLE IF NOT EXISTS hosts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  host TEXT NOT NULL,
  port INTEGER NOT NULL,
  username TEXT NOT NULL,
  password_enc TEXT,
  private_key_enc TEXT,
  passphrase_enc TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  host_id TEXT,
  session_id TEXT,
  command TEXT NOT NULL,
  risk TEXT NOT NULL,
  confirmed INTEGER NOT NULL DEFAULT 0,
  exit_code INTEGER DEFAULT -1,
  stdout TEXT DEFAULT '',
  stderr TEXT DEFAULT '',
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS chat_messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS session_memory (
  session_id TEXT PRIMARY KEY,
  summary TEXT NOT NULL DEFAULT '',
  facts TEXT NOT NULL DEFAULT '',
  covered_until_id INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_chat_session_id ON chat_messages(session_id);
`)
	return err
}

// SessionMemory is durable long-term memory for one agent chat session.
type SessionMemory struct {
	SessionID      string `json:"sessionId"`
	Summary        string `json:"summary"`
	Facts          string `json:"facts"`
	CoveredUntilID int64  `json:"coveredUntilId"`
	UpdatedAt      string `json:"updatedAt"`
}

func (s *Store) GetSessionMemory(sessionID string) (SessionMemory, error) {
	var m SessionMemory
	err := s.db.QueryRow(
		`SELECT session_id, summary, facts, covered_until_id, updated_at FROM session_memory WHERE session_id=?`,
		sessionID,
	).Scan(&m.SessionID, &m.Summary, &m.Facts, &m.CoveredUntilID, &m.UpdatedAt)
	if err == sql.ErrNoRows {
		return SessionMemory{SessionID: sessionID}, nil
	}
	return m, err
}

func (s *Store) UpsertSessionMemory(m SessionMemory) error {
	now := time.Now().UTC().Format(time.RFC3339)
	if m.UpdatedAt == "" {
		m.UpdatedAt = now
	}
	_, err := s.db.Exec(
		`INSERT INTO session_memory(session_id,summary,facts,covered_until_id,updated_at)
		 VALUES(?,?,?,?,?)
		 ON CONFLICT(session_id) DO UPDATE SET
		   summary=excluded.summary,
		   facts=excluded.facts,
		   covered_until_id=excluded.covered_until_id,
		   updated_at=excluded.updated_at`,
		m.SessionID, m.Summary, m.Facts, m.CoveredUntilID, m.UpdatedAt,
	)
	return err
}

func (s *Store) DeleteSessionMemory(sessionID string) error {
	_, err := s.db.Exec(`DELETE FROM session_memory WHERE session_id=?`, sessionID)
	return err
}

// ListSessionMemories returns all durable agent memories, newest first.
func (s *Store) ListSessionMemories() ([]SessionMemory, error) {
	rows, err := s.db.Query(
		`SELECT session_id, summary, facts, covered_until_id, updated_at
		 FROM session_memory
		 ORDER BY updated_at DESC`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]SessionMemory, 0)
	for rows.Next() {
		var m SessionMemory
		if err := rows.Scan(&m.SessionID, &m.Summary, &m.Facts, &m.CoveredUntilID, &m.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// DeleteAllSessionMemory clears every long-term memory row.
func (s *Store) DeleteAllSessionMemory() (int64, error) {
	res, err := s.db.Exec(`DELETE FROM session_memory`)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

// CountChat returns total messages in a session.
func (s *Store) CountChat(sessionID string) (int, error) {
	var n int
	err := s.db.QueryRow(`SELECT COUNT(1) FROM chat_messages WHERE session_id=?`, sessionID).Scan(&n)
	return n, err
}

// ListChatRecent returns the newest messages in chronological order (oldest→newest among the recent set).
func (s *Store) ListChatRecent(sessionID string, limit int) ([]map[string]any, error) {
	if limit <= 0 {
		limit = 100
	}
	rows, err := s.db.Query(
		`SELECT id,session_id,role,content,created_at FROM (
		   SELECT id,session_id,role,content,created_at FROM chat_messages
		   WHERE session_id=? ORDER BY id DESC LIMIT ?
		 ) ORDER BY id ASC`,
		sessionID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []map[string]any
	for rows.Next() {
		var id int64
		var sid, role, content, ca string
		if err := rows.Scan(&id, &sid, &role, &content, &ca); err != nil {
			return nil, err
		}
		out = append(out, map[string]any{
			"id": id, "sessionId": sid, "role": role, "content": content, "createdAt": ca,
		})
	}
	if out == nil {
		out = []map[string]any{}
	}
	return out, rows.Err()
}

// ListChatAfter returns messages with id > afterID ascending.
func (s *Store) ListChatAfter(sessionID string, afterID int64, limit int) ([]map[string]any, error) {
	if limit <= 0 {
		limit = 200
	}
	rows, err := s.db.Query(
		`SELECT id,session_id,role,content,created_at FROM chat_messages
		 WHERE session_id=? AND id>? ORDER BY id ASC LIMIT ?`,
		sessionID, afterID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []map[string]any
	for rows.Next() {
		var id int64
		var sid, role, content, ca string
		if err := rows.Scan(&id, &sid, &role, &content, &ca); err != nil {
			return nil, err
		}
		out = append(out, map[string]any{
			"id": id, "sessionId": sid, "role": role, "content": content, "createdAt": ca,
		})
	}
	if out == nil {
		out = []map[string]any{}
	}
	return out, rows.Err()
}

type AuditEntry struct {
	ID        int64  `json:"id"`
	HostID    string `json:"hostId"`
	SessionID string `json:"sessionId"`
	Command   string `json:"command"`
	Risk      string `json:"risk"`
	Confirmed bool   `json:"confirmed"`
	ExitCode  int    `json:"exitCode"`
	Stdout    string `json:"stdout"`
	Stderr    string `json:"stderr"`
	CreatedAt string `json:"createdAt"`
}

func (s *Store) AddAudit(e *AuditEntry) error {
	now := time.Now().UTC().Format(time.RFC3339)
	conf := 0
	if e.Confirmed {
		conf = 1
	}
	res, err := s.db.Exec(
		`INSERT INTO audit_log(host_id,session_id,command,risk,confirmed,exit_code,stdout,stderr,created_at)
		 VALUES(?,?,?,?,?,?,?,?,?)`,
		e.HostID, e.SessionID, e.Command, e.Risk, conf, e.ExitCode, e.Stdout, e.Stderr, now,
	)
	if err != nil {
		return err
	}
	id, _ := res.LastInsertId()
	e.ID = id
	e.CreatedAt = now
	return nil
}

func (s *Store) ListAudit(limit int) ([]AuditEntry, error) {
	if limit <= 0 {
		limit = 100
	}
	rows, err := s.db.Query(
		`SELECT id,host_id,session_id,command,risk,confirmed,exit_code,stdout,stderr,created_at
		 FROM audit_log ORDER BY id DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []AuditEntry
	for rows.Next() {
		var e AuditEntry
		var conf int
		if err := rows.Scan(&e.ID, &e.HostID, &e.SessionID, &e.Command, &e.Risk, &conf, &e.ExitCode, &e.Stdout, &e.Stderr, &e.CreatedAt); err != nil {
			return nil, err
		}
		e.Confirmed = conf != 0
		out = append(out, e)
	}
	if out == nil {
		out = []AuditEntry{}
	}
	return out, rows.Err()
}

func (s *Store) AddChat(sessionID, role, content string) error {
	now := time.Now().UTC().Format(time.RFC3339)
	_, err := s.db.Exec(
		`INSERT INTO chat_messages(session_id,role,content,created_at) VALUES(?,?,?,?)`,
		sessionID, role, content, now,
	)
	return err
}

// ListChat returns recent messages (chronological). Prefer ListChatRecent for new code.
func (s *Store) ListChat(sessionID string, limit int) ([]map[string]any, error) {
	return s.ListChatRecent(sessionID, limit)
}

func (s *Store) ListHosts() ([]Host, error) {
	rows, err := s.db.Query(`SELECT id,name,host,port,username,password_enc,private_key_enc,created_at,updated_at FROM hosts ORDER BY name, host`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Host
	for rows.Next() {
		var h Host
		var pw, pk sql.NullString
		if err := rows.Scan(&h.ID, &h.Name, &h.Host, &h.Port, &h.Username, &pw, &pk, &h.CreatedAt, &h.UpdatedAt); err != nil {
			return nil, err
		}
		h.HasPassword = pw.Valid && pw.String != ""
		h.HasPrivateKey = pk.Valid && pk.String != ""
		out = append(out, h)
	}
	if out == nil {
		out = []Host{}
	}
	return out, rows.Err()
}

func (s *Store) GetHost(id string) (Host, error) {
	var h Host
	var pw, pk sql.NullString
	err := s.db.QueryRow(
		`SELECT id,name,host,port,username,password_enc,private_key_enc,created_at,updated_at FROM hosts WHERE id=?`, id,
	).Scan(&h.ID, &h.Name, &h.Host, &h.Port, &h.Username, &pw, &pk, &h.CreatedAt, &h.UpdatedAt)
	if err != nil {
		return h, err
	}
	h.HasPassword = pw.Valid && pw.String != ""
	h.HasPrivateKey = pk.Valid && pk.String != ""
	return h, nil
}

func (s *Store) GetHostSecrets(id string) (HostSecrets, error) {
	var pw, pk, pp sql.NullString
	err := s.db.QueryRow(
		`SELECT password_enc, private_key_enc, passphrase_enc FROM hosts WHERE id=?`, id,
	).Scan(&pw, &pk, &pp)
	if err != nil {
		return HostSecrets{}, err
	}
	var sec HostSecrets
	if pw.Valid {
		sec.Password, err = s.box.Open(pw.String)
		if err != nil {
			return sec, err
		}
	}
	if pk.Valid {
		sec.PrivateKeyPEM, err = s.box.Open(pk.String)
		if err != nil {
			return sec, err
		}
	}
	if pp.Valid {
		sec.Passphrase, err = s.box.Open(pp.String)
		if err != nil {
			return sec, err
		}
	}
	return sec, nil
}

func (s *Store) CreateHost(h Host) (Host, error) {
	if h.ID == "" {
		h.ID = uuid.NewString()
	}
	if h.Port == 0 {
		h.Port = 22
	}
	if h.Name == "" {
		h.Name = h.Host
	}
	now := time.Now().UTC().Format(time.RFC3339)
	h.CreatedAt, h.UpdatedAt = now, now
	pw, pk, pp, err := s.sealSecrets(h.Password, h.PrivateKeyPEM, h.Passphrase)
	if err != nil {
		return h, err
	}
	_, err = s.db.Exec(
		`INSERT INTO hosts(id,name,host,port,username,password_enc,private_key_enc,passphrase_enc,created_at,updated_at)
		 VALUES(?,?,?,?,?,?,?,?,?,?)`,
		h.ID, h.Name, h.Host, h.Port, h.Username, pw, pk, pp, h.CreatedAt, h.UpdatedAt,
	)
	if err != nil {
		return h, err
	}
	return s.publicHost(h), nil
}

func (s *Store) UpdateHost(id string, h Host) (Host, error) {
	cur, err := s.GetHost(id)
	if err != nil {
		return h, err
	}
	if h.Name != "" {
		cur.Name = h.Name
	}
	if h.Host != "" {
		cur.Host = h.Host
	}
	if h.Port != 0 {
		cur.Port = h.Port
	}
	if h.Username != "" {
		cur.Username = h.Username
	}
	cur.UpdatedAt = time.Now().UTC().Format(time.RFC3339)

	// Load existing secrets if not replaced
	sec, err := s.GetHostSecrets(id)
	if err != nil {
		return h, err
	}
	pwIn, pkIn, ppIn := sec.Password, sec.PrivateKeyPEM, sec.Passphrase
	if h.Password != "" {
		pwIn = h.Password
	}
	if h.PrivateKeyPEM != "" {
		pkIn = h.PrivateKeyPEM
	}
	if h.Passphrase != "" {
		ppIn = h.Passphrase
	}
	// allow clearing password with explicit empty via sentinel? skip for v0.1
	pw, pk, pp, err := s.sealSecrets(pwIn, pkIn, ppIn)
	if err != nil {
		return h, err
	}
	_, err = s.db.Exec(
		`UPDATE hosts SET name=?,host=?,port=?,username=?,password_enc=?,private_key_enc=?,passphrase_enc=?,updated_at=? WHERE id=?`,
		cur.Name, cur.Host, cur.Port, cur.Username, pw, pk, pp, cur.UpdatedAt, id,
	)
	if err != nil {
		return h, err
	}
	cur.HasPassword = pw != ""
	cur.HasPrivateKey = pk != ""
	return cur, nil
}

func (s *Store) DeleteHost(id string) error {
	res, err := s.db.Exec(`DELETE FROM hosts WHERE id=?`, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func (s *Store) sealSecrets(password, pem, pass string) (pw, pk, pp string, err error) {
	if password != "" {
		pw, err = s.box.Seal(password)
		if err != nil {
			return
		}
	}
	if pem != "" {
		pk, err = s.box.Seal(pem)
		if err != nil {
			return
		}
	}
	if pass != "" {
		pp, err = s.box.Seal(pass)
		if err != nil {
			return
		}
	}
	return
}

func (s *Store) publicHost(h Host) Host {
	h.Password = ""
	h.PrivateKeyPEM = ""
	h.Passphrase = ""
	h.HasPassword = false
	h.HasPrivateKey = false
	// re-fetch flags
	got, err := s.GetHost(h.ID)
	if err != nil {
		return h
	}
	return got
}

func (s *Store) GetLLM() (LLMSettings, error) {
	get := func(k string) string {
		var v string
		_ = s.db.QueryRow(`SELECT value FROM settings WHERE key=?`, k).Scan(&v)
		return v
	}
	keyEnc := get("llm.api_key_enc")
	var key string
	if keyEnc != "" {
		var err error
		key, err = s.box.Open(keyEnc)
		if err != nil {
			return LLMSettings{}, err
		}
	}
	timeout := 180
	if t := get("llm.timeout_seconds"); t != "" {
		fmt.Sscanf(t, "%d", &timeout)
	}
	st := LLMSettings{
		BaseURL:        get("llm.base_url"),
		Model:          get("llm.model"),
		TimeoutSeconds: timeout,
		APIKeySet:      key != "",
		ThinkingLevel:  get("llm.thinking_level"),
	}
	if st.Model == "" {
		st.Model = "grok-4.5"
	}
	if st.TimeoutSeconds == 0 {
		st.TimeoutSeconds = 180
	}
	if st.ThinkingLevel == "" {
		st.ThinkingLevel = "auto"
	}
	if key != "" {
		// User requested plaintext key in settings UI (local-only app).
		st.APIKey = key
		st.APIKeyMasked = maskKey(key)
	}
	return st, nil
}

// GetLLMFull returns settings including plaintext API key (for server-side LLM calls).
func (s *Store) GetLLMFull() (LLMSettings, error) {
	st, err := s.GetLLM()
	if err != nil {
		return st, err
	}
	var keyEnc string
	_ = s.db.QueryRow(`SELECT value FROM settings WHERE key=?`, "llm.api_key_enc").Scan(&keyEnc)
	if keyEnc != "" {
		st.APIKey, err = s.box.Open(keyEnc)
		if err != nil {
			return st, err
		}
	}
	return st, nil
}

func (s *Store) PutLLM(in LLMSettings) (LLMSettings, error) {
	put := func(k, v string) error {
		_, err := s.db.Exec(
			`INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value`,
			k, v,
		)
		return err
	}
	if in.BaseURL != "" || in.BaseURL == "" {
		// allow empty clear
		if err := put("llm.base_url", in.BaseURL); err != nil {
			return in, err
		}
	}
	if in.Model != "" {
		if err := put("llm.model", in.Model); err != nil {
			return in, err
		}
	}
	if in.TimeoutSeconds > 0 {
		if err := put("llm.timeout_seconds", fmt.Sprintf("%d", in.TimeoutSeconds)); err != nil {
			return in, err
		}
	}
	if in.ThinkingLevel != "" {
		if err := put("llm.thinking_level", strings.ToLower(strings.TrimSpace(in.ThinkingLevel))); err != nil {
			return in, err
		}
	}
	if in.APIKey != "" {
		enc, err := s.box.Seal(in.APIKey)
		if err != nil {
			return in, err
		}
		if err := put("llm.api_key_enc", enc); err != nil {
			return in, err
		}
	}
	return s.GetLLM()
}

func maskKey(k string) string {
	if len(k) <= 8 {
		return "****"
	}
	return k[:4] + "…" + k[len(k)-4:]
}
