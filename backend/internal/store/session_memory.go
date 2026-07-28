package store

import (
	"database/sql"
	"time"
)

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
