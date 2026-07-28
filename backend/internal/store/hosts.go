package store

import (
	"database/sql"
	"errors"
	"time"

	"github.com/google/uuid"
)

var ErrHostCredentialRequired = errors.New("password or private key required")

type Host struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	Host          string `json:"host"`
	Port          int    `json:"port"`
	Username      string `json:"username"`
	HasPassword   bool   `json:"hasPassword"`
	HasPrivateKey bool   `json:"hasPrivateKey"`
	// Write-only fields (accepted on create/update, never returned plaintext)
	Password        string `json:"password,omitempty"`
	PrivateKeyPEM   string `json:"privateKeyPem,omitempty"`
	Passphrase      string `json:"passphrase,omitempty"`
	ClearPassword   bool   `json:"clearPassword,omitempty"`
	ClearPrivateKey bool   `json:"clearPrivateKey,omitempty"`
	ClearPassphrase bool   `json:"clearPassphrase,omitempty"`
	SortOrder       int    `json:"sortOrder,omitempty"`
	CreatedAt       string `json:"createdAt,omitempty"`
	UpdatedAt       string `json:"updatedAt,omitempty"`
}

type HostSecrets struct {
	Password      string
	PrivateKeyPEM string
	Passphrase    string
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
	if h.ClearPassword {
		pwIn = ""
	}
	if h.ClearPrivateKey {
		pkIn = ""
	}
	if h.ClearPassphrase {
		ppIn = ""
	}
	if h.Password != "" {
		pwIn = h.Password
	}
	if h.PrivateKeyPEM != "" {
		pkIn = h.PrivateKeyPEM
	}
	if h.Passphrase != "" {
		ppIn = h.Passphrase
	}
	if pkIn == "" {
		ppIn = ""
	}
	if pwIn == "" && pkIn == "" {
		return h, ErrHostCredentialRequired
	}
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
