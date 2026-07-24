package sshx

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sync"

	"golang.org/x/crypto/ssh"
)

// HostKeyStore is a simple TOFU store (host:port -> key fingerprint + type + raw marshaled key).
type HostKeyStore struct {
	path string
	mu   sync.Mutex
	// key: "host:port" -> entry
	m map[string]hostKeyEntry
}

type hostKeyEntry struct {
	Host        string `json:"host"`
	Port        int    `json:"port"`
	KeyType     string `json:"keyType"`
	Fingerprint string `json:"fingerprint"` // SHA256 base64
	KeyB64      string `json:"keyB64"`      // marshaled public key
}

func NewHostKeyStore(dataDir string) (*HostKeyStore, error) {
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		return nil, err
	}
	s := &HostKeyStore{
		path: filepath.Join(dataDir, "known_hosts.json"),
		m:    map[string]hostKeyEntry{},
	}
	_ = s.load()
	return s, nil
}

func (s *HostKeyStore) load() error {
	b, err := os.ReadFile(s.path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	var m map[string]hostKeyEntry
	if err := json.Unmarshal(b, &m); err != nil {
		return err
	}
	s.mu.Lock()
	s.m = m
	s.mu.Unlock()
	return nil
}

func (s *HostKeyStore) save() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	b, err := json.MarshalIndent(s.m, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(s.path, b, 0o600)
}

func keyID(host string, port int) string {
	if port <= 0 {
		port = 22
	}
	return fmt.Sprintf("%s:%d", host, port)
}

func fingerprint(key ssh.PublicKey) string {
	sum := sha256.Sum256(key.Marshal())
	return base64.StdEncoding.EncodeToString(sum[:])
}

// Callback implements TOFU: first see accept & store; later must match.
func (s *HostKeyStore) Callback(host string, port int) ssh.HostKeyCallback {
	return func(hostname string, remote net.Addr, key ssh.PublicKey) error {
		id := keyID(host, port)
		fp := fingerprint(key)
		kt := key.Type()
		kb := base64.StdEncoding.EncodeToString(key.Marshal())

		s.mu.Lock()
		prev, ok := s.m[id]
		s.mu.Unlock()
		if !ok {
			s.mu.Lock()
			s.m[id] = hostKeyEntry{Host: host, Port: port, KeyType: kt, Fingerprint: fp, KeyB64: kb}
			s.mu.Unlock()
			return s.save()
		}
		if prev.Fingerprint != fp || prev.KeyType != kt {
			return fmt.Errorf("HOSTKEY_MISMATCH: %s expected %s got %s (reset known host if reinstalled)", id, prev.Fingerprint, fp)
		}
		return nil
	}
}

func (s *HostKeyStore) List() []hostKeyEntry {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]hostKeyEntry, 0, len(s.m))
	for _, v := range s.m {
		out = append(out, v)
	}
	return out
}

func (s *HostKeyStore) Delete(host string, port int) error {
	id := keyID(host, port)
	s.mu.Lock()
	delete(s.m, id)
	s.mu.Unlock()
	return s.save()
}

// Clear removes every trusted host key (next connect re-TOFU).
func (s *HostKeyStore) Clear() (int, error) {
	s.mu.Lock()
	n := len(s.m)
	s.m = map[string]hostKeyEntry{}
	s.mu.Unlock()
	if err := s.save(); err != nil {
		return 0, err
	}
	return n, nil
}
