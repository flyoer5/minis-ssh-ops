package storage

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	"minis-ssh-ops/internal/crypto"

	_ "modernc.org/sqlite"
)

type Store struct {
	db  *sql.DB
	key *crypto.MasterKey
}

type Host struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Host      string    `json:"host"`
	Port      int       `json:"port"`
	User      string    `json:"user"`
	AuthType  string    `json:"auth_type"` // password | key
	HasSecret bool      `json:"has_secret"`
	Tags      string    `json:"tags"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type HostSecret struct {
	Password   string `json:"password,omitempty"`
	PrivateKey string `json:"private_key,omitempty"`
	Passphrase string `json:"passphrase,omitempty"`
}

type LLMConfig struct {
	BaseURL string `json:"base_url"`
	APIKey  string `json:"api_key"`
	Model   string `json:"model"`
}

type AuditEntry struct {
	ID        int64     `json:"id"`
	HostID    string    `json:"host_id"`
	SessionID string    `json:"session_id"`
	Command   string    `json:"command"`
	Risk      string    `json:"risk"`
	Confirmed bool      `json:"confirmed"`
	ExitCode  int       `json:"exit_code"`
	Stdout    string    `json:"stdout"`
	Stderr    string    `json:"stderr"`
	CreatedAt time.Time `json:"created_at"`
}

type ChatMessage struct {
	ID        int64     `json:"id"`
	SessionID string    `json:"session_id"`
	Role      string    `json:"role"`
	Content   string    `json:"content"`
	CreatedAt time.Time `json:"created_at"`
}

func Open(path string, key *crypto.MasterKey) (*Store, error) {
	// modernc.org/sqlite registers as "sqlite"
	dsn := "file:" + path + "?_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1) // SQLite + WAL is safest single-writer in-process
	s := &Store{db: db, key: key}
	if err := s.migrate(); err != nil {
		_ = db.Close()
		return nil, err
	}
	return s, nil
}

func (s *Store) Close() error { return s.db.Close() }

func (s *Store) migrate() error {
	schema := `
CREATE TABLE IF NOT EXISTS hosts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  host TEXT NOT NULL,
  port INTEGER NOT NULL DEFAULT 22,
  user TEXT NOT NULL,
  auth_type TEXT NOT NULL,
  secret_enc TEXT,
  tags TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value_enc TEXT NOT NULL
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
CREATE TABLE IF NOT EXISTS agent_tasks (
  id TEXT PRIMARY KEY,
  host_id TEXT,
  goal TEXT NOT NULL,
  status TEXT NOT NULL,
  steps_json TEXT DEFAULT '[]',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
`
	_, err := s.db.Exec(schema)
	return err
}

func now() string { return time.Now().UTC().Format(time.RFC3339Nano) }

func parseTime(s string) time.Time {
	t, _ := time.Parse(time.RFC3339Nano, s)
	return t
}

// --- Hosts ---

func (s *Store) UpsertHost(h *Host, secret *HostSecret) error {
	var secretEnc string
	if secret != nil {
		b, err := json.Marshal(secret)
		if err != nil {
			return err
		}
		enc, err := s.key.Encrypt(b)
		if err != nil {
			return err
		}
		secretEnc = enc
	}
	ts := now()
	if h.CreatedAt.IsZero() {
		h.CreatedAt = time.Now().UTC()
	}
	h.UpdatedAt = time.Now().UTC()
	_, err := s.db.Exec(`
INSERT INTO hosts (id,name,host,port,user,auth_type,secret_enc,tags,created_at,updated_at)
VALUES (?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(id) DO UPDATE SET
  name=excluded.name, host=excluded.host, port=excluded.port, user=excluded.user,
  auth_type=excluded.auth_type,
  secret_enc=CASE WHEN excluded.secret_enc='' THEN hosts.secret_enc ELSE excluded.secret_enc END,
  tags=excluded.tags, updated_at=excluded.updated_at
`, h.ID, h.Name, h.Host, h.Port, h.User, h.AuthType, secretEnc, h.Tags,
		h.CreatedAt.UTC().Format(time.RFC3339Nano), ts)
	return err
}

func (s *Store) ListHosts() ([]Host, error) {
	rows, err := s.db.Query(`SELECT id,name,host,port,user,auth_type,secret_enc,tags,created_at,updated_at FROM hosts ORDER BY name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Host
	for rows.Next() {
		var h Host
		var secretEnc, ca, ua string
		if err := rows.Scan(&h.ID, &h.Name, &h.Host, &h.Port, &h.User, &h.AuthType, &secretEnc, &h.Tags, &ca, &ua); err != nil {
			return nil, err
		}
		h.HasSecret = secretEnc != ""
		h.CreatedAt = parseTime(ca)
		h.UpdatedAt = parseTime(ua)
		out = append(out, h)
	}
	return out, rows.Err()
}

func (s *Store) GetHost(id string) (*Host, *HostSecret, error) {
	var h Host
	var secretEnc, ca, ua string
	err := s.db.QueryRow(`SELECT id,name,host,port,user,auth_type,secret_enc,tags,created_at,updated_at FROM hosts WHERE id=?`, id).
		Scan(&h.ID, &h.Name, &h.Host, &h.Port, &h.User, &h.AuthType, &secretEnc, &h.Tags, &ca, &ua)
	if err != nil {
		return nil, nil, err
	}
	h.HasSecret = secretEnc != ""
	h.CreatedAt = parseTime(ca)
	h.UpdatedAt = parseTime(ua)
	var sec *HostSecret
	if secretEnc != "" {
		plain, err := s.key.Decrypt(secretEnc)
		if err != nil {
			return nil, nil, fmt.Errorf("decrypt secret: %w", err)
		}
		sec = &HostSecret{}
		if err := json.Unmarshal(plain, sec); err != nil {
			return nil, nil, err
		}
	}
	return &h, sec, nil
}

func (s *Store) DeleteHost(id string) error {
	_, err := s.db.Exec(`DELETE FROM hosts WHERE id=?`, id)
	return err
}

// --- LLM settings ---

func (s *Store) SetLLM(cfg LLMConfig) error {
	b, err := json.Marshal(cfg)
	if err != nil {
		return err
	}
	enc, err := s.key.Encrypt(b)
	if err != nil {
		return err
	}
	_, err = s.db.Exec(`INSERT INTO settings(key,value_enc) VALUES('llm',?)
		ON CONFLICT(key) DO UPDATE SET value_enc=excluded.value_enc`, enc)
	return err
}

func (s *Store) GetLLM() (*LLMConfig, error) {
	var enc string
	err := s.db.QueryRow(`SELECT value_enc FROM settings WHERE key='llm'`).Scan(&enc)
	if err == sql.ErrNoRows {
		return &LLMConfig{
			BaseURL: "https://api.openai.com/v1",
			Model:   "gpt-4o-mini",
		}, nil
	}
	if err != nil {
		return nil, err
	}
	plain, err := s.key.Decrypt(enc)
	if err != nil {
		return nil, err
	}
	var cfg LLMConfig
	if err := json.Unmarshal(plain, &cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

// Masked LLM for API response (never leak full key).
func (s *Store) GetLLMMasked() (map[string]any, error) {
	cfg, err := s.GetLLM()
	if err != nil {
		return nil, err
	}
	key := cfg.APIKey
	masked := ""
	if len(key) > 8 {
		masked = key[:4] + "****" + key[len(key)-4:]
	} else if key != "" {
		masked = "****"
	}
	return map[string]any{
		"base_url":    cfg.BaseURL,
		"model":       cfg.Model,
		"api_key_set": cfg.APIKey != "",
		"api_key_mask": masked,
	}, nil
}

// --- Audit ---

func (s *Store) AddAudit(e *AuditEntry) error {
	res, err := s.db.Exec(`INSERT INTO audit_log(host_id,session_id,command,risk,confirmed,exit_code,stdout,stderr,created_at)
		VALUES(?,?,?,?,?,?,?,?,?)`,
		e.HostID, e.SessionID, e.Command, e.Risk, boolToInt(e.Confirmed), e.ExitCode, e.Stdout, e.Stderr, now())
	if err != nil {
		return err
	}
	id, _ := res.LastInsertId()
	e.ID = id
	return nil
}

func (s *Store) ListAudit(limit int) ([]AuditEntry, error) {
	if limit <= 0 {
		limit = 50
	}
	rows, err := s.db.Query(`SELECT id,host_id,session_id,command,risk,confirmed,exit_code,stdout,stderr,created_at
		FROM audit_log ORDER BY id DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []AuditEntry
	for rows.Next() {
		var e AuditEntry
		var conf int
		var ca string
		if err := rows.Scan(&e.ID, &e.HostID, &e.SessionID, &e.Command, &e.Risk, &conf, &e.ExitCode, &e.Stdout, &e.Stderr, &ca); err != nil {
			return nil, err
		}
		e.Confirmed = conf != 0
		e.CreatedAt = parseTime(ca)
		out = append(out, e)
	}
	return out, rows.Err()
}

// --- Chat ---

func (s *Store) AddChat(sessionID, role, content string) error {
	_, err := s.db.Exec(`INSERT INTO chat_messages(session_id,role,content,created_at) VALUES(?,?,?,?)`,
		sessionID, role, content, now())
	return err
}

func (s *Store) ListChat(sessionID string, limit int) ([]ChatMessage, error) {
	if limit <= 0 {
		limit = 100
	}
	rows, err := s.db.Query(`SELECT id,session_id,role,content,created_at FROM chat_messages
		WHERE session_id=? ORDER BY id ASC LIMIT ?`, sessionID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ChatMessage
	for rows.Next() {
		var m ChatMessage
		var ca string
		if err := rows.Scan(&m.ID, &m.SessionID, &m.Role, &m.Content, &ca); err != nil {
			return nil, err
		}
		m.CreatedAt = parseTime(ca)
		out = append(out, m)
	}
	return out, rows.Err()
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
