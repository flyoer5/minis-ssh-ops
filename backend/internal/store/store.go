package store

import (
	"database/sql"
	"encoding/json"
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
	SortOrder      int    `json:"sortOrder,omitempty"`
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
type AgentSession struct {
	ID        string `json:"id"`
	HostID    string `json:"hostId,omitempty"`
	Title     string `json:"title"`
	Preview   string `json:"preview"`
	MsgCount  int    `json:"msgCount"`
	CreatedAt string `json:"createdAt"`
	UpdatedAt string `json:"updatedAt"`
	// Overrides: nil pointer / omitted = inherit global client settings.
	OvMaxRounds   *int     `json:"ovMaxRounds,omitempty"`
	OvTemperature *float64 `json:"ovTemperature,omitempty"`
	// OvConfirm: nil inherit; 0 force off; 1 force on.
	OvConfirm *int    `json:"ovConfirm,omitempty"`
	OvPrompt  *string `json:"ovPrompt,omitempty"`
}

// EnsureAgentSession creates the session row if missing and refreshes host/title/preview.
func (s *Store) EnsureAgentSession(id, hostID, titleHint string) error {
	if id == "" {
		return nil
	}
	now := time.Now().UTC().Format(time.RFC3339)
	var exists string
	err := s.db.QueryRow(`SELECT id FROM agent_sessions WHERE id=?`, id).Scan(&exists)
	if err == sql.ErrNoRows {
		title := titleHint
		if title == "" {
			title = "新会话"
		}
		if len(title) > 48 {
			title = title[:48] + "…"
		}
		_, err = s.db.Exec(
			`INSERT INTO agent_sessions(id, host_id, title, preview, created_at, updated_at) VALUES(?,?,?,?,?,?)`,
			id, hostID, title, titleHint, now, now,
		)
		return err
	}
	if err != nil {
		return err
	}
	// Touch updated_at; fill host if empty; keep title unless empty and hint provided.
	title := titleHint
	if len(title) > 48 {
		title = title[:48] + "…"
	}
	_, err = s.db.Exec(
		`UPDATE agent_sessions SET
		   updated_at=?,
		   host_id=CASE WHEN host_id IS NULL OR host_id='' THEN ? ELSE host_id END,
		   title=CASE WHEN (title='' OR title='新会话') AND ?!='' THEN ? ELSE title END
		 WHERE id=?`,
		now, hostID, titleHint, title, id,
	)
	return err
}

// TouchAgentSessionPreview updates preview + msg-derived title if still default.
func (s *Store) TouchAgentSessionPreview(id, preview string) error {
	if id == "" {
		return nil
	}
	now := time.Now().UTC().Format(time.RFC3339)
	p := preview
	if len(p) > 120 {
		p = p[:120] + "…"
	}
	titleFrom := p
	if len(titleFrom) > 48 {
		titleFrom = titleFrom[:48] + "…"
	}
	_, err := s.db.Exec(
		`UPDATE agent_sessions SET
		   preview=?,
		   updated_at=?,
		   title=CASE WHEN title='' OR title='新会话' THEN ? ELSE title END
		 WHERE id=?`,
		p, now, titleFrom, id,
	)
	return err
}

func (s *Store) RenameAgentSession(id, title string) error {
	if id == "" {
		return fmt.Errorf("empty session id")
	}
	t := strings.TrimSpace(title)
	if t == "" {
		return fmt.Errorf("empty title")
	}
	if len(t) > 48 {
		t = t[:48] + "…"
	}
	now := time.Now().UTC().Format(time.RFC3339)
	res, err := s.db.Exec(`UPDATE agent_sessions SET title=?, updated_at=? WHERE id=?`, t, now, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func (s *Store) DeleteAgentSession(id string) error {
	if id == "" {
		return fmt.Errorf("empty session id")
	}
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	if _, err := tx.Exec(`DELETE FROM chat_messages WHERE session_id=?`, id); err != nil {
		return err
	}
	if _, err := tx.Exec(`DELETE FROM session_memory WHERE session_id=?`, id); err != nil {
		return err
	}
	if _, err := tx.Exec(`DELETE FROM agent_sessions WHERE id=?`, id); err != nil {
		return err
	}
	return tx.Commit()
}

const agentSessionSelect = `SELECT s.id, COALESCE(s.host_id,''), s.title, s.preview, s.created_at, s.updated_at,
			        (SELECT COUNT(1) FROM chat_messages m WHERE m.session_id=s.id) AS msg_count,
			        s.ov_max_rounds, s.ov_temperature, s.ov_confirm, s.ov_prompt
			 FROM agent_sessions s`

func scanAgentSession(sc interface {
	Scan(dest ...any) error
}) (AgentSession, error) {
	var a AgentSession
	var ovRounds, ovConfirm sql.NullInt64
	var ovTemp sql.NullFloat64
	var ovPrompt sql.NullString
	err := sc.Scan(&a.ID, &a.HostID, &a.Title, &a.Preview, &a.CreatedAt, &a.UpdatedAt, &a.MsgCount,
		&ovRounds, &ovTemp, &ovConfirm, &ovPrompt)
	if err != nil {
		return a, err
	}
	if ovRounds.Valid {
		v := int(ovRounds.Int64)
		a.OvMaxRounds = &v
	}
	if ovTemp.Valid {
		v := ovTemp.Float64
		a.OvTemperature = &v
	}
	if ovConfirm.Valid {
		v := int(ovConfirm.Int64)
		a.OvConfirm = &v
	}
	if ovPrompt.Valid {
		v := ovPrompt.String
		a.OvPrompt = &v
	}
	return a, nil
}

// ListAgentSessions returns newest sessions first. hostID empty = all.
func (s *Store) ListAgentSessions(hostID string, limit int) ([]AgentSession, error) {
	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}
	var (
		rows *sql.Rows
		err  error
	)
	if hostID == "" {
		rows, err = s.db.Query(agentSessionSelect+` ORDER BY s.updated_at DESC LIMIT ?`, limit)
	} else {
		rows, err = s.db.Query(
			agentSessionSelect+` WHERE s.host_id=? OR s.host_id='' OR s.host_id IS NULL
			 ORDER BY s.updated_at DESC LIMIT ?`, hostID, limit)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]AgentSession, 0)
	for rows.Next() {
		a, err := scanAgentSession(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// SearchAgentSessions matches title/preview (and optionally message content).
func (s *Store) SearchAgentSessions(q, hostID string, limit int) ([]AgentSession, error) {
	q = strings.TrimSpace(q)
	if q == "" {
		return s.ListAgentSessions(hostID, limit)
	}
	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}
	like := "%" + q + "%"
	var (
		rows *sql.Rows
		err  error
	)
	if hostID == "" {
		rows, err = s.db.Query(
			agentSessionSelect+`
			 WHERE s.title LIKE ? OR s.preview LIKE ?
			    OR EXISTS (SELECT 1 FROM chat_messages m WHERE m.session_id=s.id AND m.content LIKE ?)
			 ORDER BY s.updated_at DESC
			 LIMIT ?`, like, like, like, limit)
	} else {
		rows, err = s.db.Query(
			agentSessionSelect+`
			 WHERE (s.host_id=? OR s.host_id='' OR s.host_id IS NULL)
			   AND (s.title LIKE ? OR s.preview LIKE ?
			        OR EXISTS (SELECT 1 FROM chat_messages m WHERE m.session_id=s.id AND m.content LIKE ?))
			 ORDER BY s.updated_at DESC
			 LIMIT ?`, hostID, like, like, like, limit)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]AgentSession, 0)
	for rows.Next() {
		a, err := scanAgentSession(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

func (s *Store) GetAgentSession(id string) (AgentSession, error) {
	row := s.db.QueryRow(agentSessionSelect+` WHERE s.id=?`, id)
	return scanAgentSession(row)
}

// UpdateAgentSessionOverrides sets session-level knobs. Pass nil to clear (inherit).
func (s *Store) UpdateAgentSessionOverrides(id string, maxRounds *int, temp *float64, confirm *int, prompt *string) error {
	if id == "" {
		return fmt.Errorf("empty session id")
	}
	now := time.Now().UTC().Format(time.RFC3339)
	var rounds any
	var temperature any
	var conf any
	var pr any
	if maxRounds != nil {
		v := *maxRounds
		if v < 1 {
			v = 1
		}
		if v > 99 {
			v = 99
		}
		rounds = v
	}
	if temp != nil {
		v := *temp
		if v < 0 {
			v = 0
		}
		if v > 2 {
			v = 2
		}
		temperature = v
	}
	if confirm != nil {
		if *confirm != 0 {
			conf = 1
		} else {
			conf = 0
		}
	}
	if prompt != nil {
		pr = *prompt
	}
	res, err := s.db.Exec(
		`UPDATE agent_sessions SET ov_max_rounds=?, ov_temperature=?, ov_confirm=?, ov_prompt=?, updated_at=? WHERE id=?`,
		rounds, temperature, conf, pr, now, id,
	)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
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

func (s *Store) ListHosts() ([]Host, error) {
	rows, err := s.db.Query(
		`SELECT id,name,host,port,username,password_enc,private_key_enc,created_at,updated_at,
		        COALESCE(sort_order, 0)
		 FROM hosts ORDER BY sort_order ASC, name COLLATE NOCASE, host COLLATE NOCASE`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Host
	for rows.Next() {
		var h Host
		var pw, pk sql.NullString
		var sortOrder int
		if err := rows.Scan(&h.ID, &h.Name, &h.Host, &h.Port, &h.Username, &pw, &pk, &h.CreatedAt, &h.UpdatedAt, &sortOrder); err != nil {
			return nil, err
		}
		h.HasPassword = pw.Valid && pw.String != ""
		h.HasPrivateKey = pk.Valid && pk.String != ""
		h.SortOrder = sortOrder
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
	// Append to end of user order.
	var maxOrd int
	_ = s.db.QueryRow(`SELECT COALESCE(MAX(sort_order), 0) FROM hosts`).Scan(&maxOrd)
	h.SortOrder = maxOrd + 1
	pw, pk, pp, err := s.sealSecrets(h.Password, h.PrivateKeyPEM, h.Passphrase)
	if err != nil {
		return h, err
	}
	_, err = s.db.Exec(
		`INSERT INTO hosts(id,name,host,port,username,password_enc,private_key_enc,passphrase_enc,created_at,updated_at,sort_order)
		 VALUES(?,?,?,?,?,?,?,?,?,?,?)`,
		h.ID, h.Name, h.Host, h.Port, h.Username, pw, pk, pp, h.CreatedAt, h.UpdatedAt, h.SortOrder,
	)
	if err != nil {
		return h, err
	}
	return s.publicHost(h), nil
}

// ReorderHosts sets sort_order = index for each id (0-based list order).
func (s *Store) ReorderHosts(ids []string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	now := time.Now().UTC().Format(time.RFC3339)
	for i, id := range ids {
		if id == "" {
			continue
		}
		if _, err := tx.Exec(`UPDATE hosts SET sort_order=?, updated_at=? WHERE id=?`, i, now, id); err != nil {
			return err
		}
	}
	return tx.Commit()
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
