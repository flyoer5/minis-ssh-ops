package store

import (
	"database/sql"
	"fmt"
	"strings"
	"time"
)

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
