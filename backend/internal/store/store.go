package store

import (
	"database/sql"
	"encoding/json"
	"strings"
	"time"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/crypto"
	_ "modernc.org/sqlite"
)

type Store struct {
	db  *sql.DB
	box *crypto.Box
}

func Open(path string, box *crypto.Box) (*Store, error) {
	db, err := sql.Open("sqlite", path+"?_pragma=busy_timeout(3000)&_pragma=journal_mode(WAL)&_pragma=synchronous(NORMAL)&_pragma=temp_store(MEMORY)")
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
CREATE TABLE IF NOT EXISTS agent_sessions (
  id TEXT PRIMARY KEY,
  host_id TEXT,
  title TEXT NOT NULL DEFAULT '',
  preview TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS session_memory (
  session_id TEXT PRIMARY KEY,
  summary TEXT NOT NULL DEFAULT '',
  facts TEXT NOT NULL DEFAULT '',
  covered_until_id INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_chat_session_id ON chat_messages(session_id);
CREATE INDEX IF NOT EXISTS idx_agent_sessions_updated ON agent_sessions(updated_at);
`)
	if err != nil {
		return err
	}
	// Additive columns (ignore if already present).
	for _, ddl := range []string{
		`ALTER TABLE chat_messages ADD COLUMN kind TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE chat_messages ADD COLUMN meta TEXT NOT NULL DEFAULT ''`,
		// Session-level overrides (NULL = inherit global app settings)
		`ALTER TABLE agent_sessions ADD COLUMN ov_max_rounds INTEGER`,
		`ALTER TABLE agent_sessions ADD COLUMN ov_temperature REAL`,
		`ALTER TABLE agent_sessions ADD COLUMN ov_confirm INTEGER`,
		`ALTER TABLE agent_sessions ADD COLUMN ov_prompt TEXT`,
		// User-defined host list order (lower = higher).
		`ALTER TABLE hosts ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0`,
	} {
		if _, e := s.db.Exec(ddl); e != nil {
			msg := strings.ToLower(e.Error())
			if !strings.Contains(msg, "duplicate") {
				return e
			}
		}
	}
	return nil
}

// AgentSession is a durable agent conversation header (Minis-style).
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
		`SELECT id,session_id,role,content,created_at,COALESCE(kind,''),COALESCE(meta,'') FROM (
		   SELECT id,session_id,role,content,created_at,kind,meta FROM chat_messages
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
		var sid, role, content, ca, kind, metaStr string
		if err := rows.Scan(&id, &sid, &role, &content, &ca, &kind, &metaStr); err != nil {
			return nil, err
		}
		row := map[string]any{
			"id": id, "sessionId": sid, "role": role, "content": content, "createdAt": ca,
		}
		if kind != "" {
			row["kind"] = kind
		}
		if metaStr != "" {
			var meta map[string]any
			if json.Unmarshal([]byte(metaStr), &meta) == nil {
				row["meta"] = meta
			}
		}
		out = append(out, row)
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
		`SELECT id,session_id,role,content,created_at,COALESCE(kind,''),COALESCE(meta,'') FROM chat_messages
		 WHERE session_id=? AND id>? ORDER BY id ASC LIMIT ?`,
		sessionID, afterID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []map[string]any
	for rows.Next() {
		var id int64
		var sid, role, content, ca, kind, metaStr string
		if err := rows.Scan(&id, &sid, &role, &content, &ca, &kind, &metaStr); err != nil {
			return nil, err
		}
		row := map[string]any{
			"id": id, "sessionId": sid, "role": role, "content": content, "createdAt": ca,
		}
		if kind != "" {
			row["kind"] = kind
		}
		if metaStr != "" {
			var meta map[string]any
			if json.Unmarshal([]byte(metaStr), &meta) == nil {
				row["meta"] = meta
			}
		}
		out = append(out, row)
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
	return s.AddChatPart(sessionID, role, content, "", nil)
}

// AddChatPart stores a transcript part with optional kind/meta (JSON object).
func (s *Store) AddChatPart(sessionID, role, content, kind string, meta map[string]any) error {
	now := time.Now().UTC().Format(time.RFC3339)
	// Best-effort session header (host filled by EnsureAgentSession from handlers).
	_ = s.EnsureAgentSession(sessionID, "", "")
	metaStr := ""
	if meta != nil {
		b, err := json.Marshal(meta)
		if err == nil {
			metaStr = string(b)
		}
	}
	_, err := s.db.Exec(
		`INSERT INTO chat_messages(session_id,role,content,created_at,kind,meta) VALUES(?,?,?,?,?,?)`,
		sessionID, role, content, now, kind, metaStr,
	)
	if err != nil {
		return err
	}
	if role == "user" && strings.TrimSpace(content) != "" {
		_ = s.TouchAgentSessionPreview(sessionID, content)
	} else {
		// still bump updated_at
		_, _ = s.db.Exec(`UPDATE agent_sessions SET updated_at=? WHERE id=?`, now, sessionID)
	}
	return nil
}

// ListChat returns recent messages (chronological). Prefer ListChatRecent for new code.
func (s *Store) ListChat(sessionID string, limit int) ([]map[string]any, error) {
	return s.ListChatRecent(sessionID, limit)
}
