package config

import (
	"crypto/rand"
	"encoding/hex"
	"os"
	"path/filepath"
	"strconv"
)

// Config holds process-level settings (not user LLM settings).
type Config struct {
	// ListenAddr must stay on loopback for security.
	ListenAddr string
	// DataDir holds SQLite and key files.
	DataDir string
	// LocalToken protects loopback HTTP from other local processes.
	LocalToken string
	// MasterKeyHex is 32-byte AES key hex; empty means load/create file.
	MasterKeyHex string
}

func Load() (Config, error) {
	home, _ := os.UserHomeDir()
	defaultData := filepath.Join(home, ".ssh-ai-agent")
	if v := os.Getenv("SSH_AI_DATA_DIR"); v != "" {
		defaultData = v
	}
	port := 17890
	if v := os.Getenv("SSH_AI_PORT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			port = n
		}
	}
	cfg := Config{
		ListenAddr:   "127.0.0.1:" + strconv.Itoa(port),
		DataDir:      defaultData,
		LocalToken:   os.Getenv("SSH_AI_LOCAL_TOKEN"),
		MasterKeyHex: os.Getenv("SSH_AI_MASTER_KEY"),
	}
	if err := os.MkdirAll(cfg.DataDir, 0o700); err != nil {
		return cfg, err
	}
	tokenPath := filepath.Join(cfg.DataDir, "local.token")
	if cfg.LocalToken == "" {
		tok, err := loadOrCreateToken(tokenPath)
		if err != nil {
			return cfg, err
		}
		cfg.LocalToken = tok
	} else {
		// Keep file in sync when token is injected via env (Android embedder).
		_ = os.WriteFile(tokenPath, []byte(cfg.LocalToken+"\n"), 0o600)
	}
	return cfg, nil
}

func loadOrCreateToken(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err == nil && len(b) >= 16 {
		return string(bytesTrim(b)), nil
	}
	raw := make([]byte, 24)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	tok := hex.EncodeToString(raw)
	if err := os.WriteFile(path, []byte(tok+"\n"), 0o600); err != nil {
		return "", err
	}
	return tok, nil
}

func bytesTrim(b []byte) []byte {
	for len(b) > 0 && (b[len(b)-1] == '\n' || b[len(b)-1] == '\r' || b[len(b)-1] == ' ') {
		b = b[:len(b)-1]
	}
	return b
}
