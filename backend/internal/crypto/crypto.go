package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// Box encrypts sensitive strings with AES-256-GCM.
type Box struct {
	gcm cipher.AEAD
}

func NewBox(dataDir, masterKeyHex string) (*Box, error) {
	key, err := resolveKey(dataDir, masterKeyHex)
	if err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	return &Box{gcm: gcm}, nil
}

func resolveKey(dataDir, masterKeyHex string) ([]byte, error) {
	if masterKeyHex != "" {
		b, err := hex.DecodeString(masterKeyHex)
		if err != nil {
			return nil, fmt.Errorf("master key hex: %w", err)
		}
		if len(b) != 32 {
			// allow any length via SHA-256
			sum := sha256.Sum256(b)
			return sum[:], nil
		}
		return b, nil
	}
	path := filepath.Join(dataDir, "master.key")
	if raw, err := os.ReadFile(path); err == nil {
		b, err := hex.DecodeString(string(bytesTrimSpace(raw)))
		if err == nil && len(b) == 32 {
			return b, nil
		}
	}
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		return nil, err
	}
	if err := os.WriteFile(path, []byte(hex.EncodeToString(key)+"\n"), 0o600); err != nil {
		return nil, err
	}
	return key, nil
}

func bytesTrimSpace(b []byte) []byte {
	for len(b) > 0 && (b[len(b)-1] == '\n' || b[len(b)-1] == '\r' || b[len(b)-1] == ' ') {
		b = b[:len(b)-1]
	}
	return b
}

// Seal returns base64(nonce|ciphertext).
func (b *Box) Seal(plain string) (string, error) {
	if plain == "" {
		return "", nil
	}
	nonce := make([]byte, b.gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	out := b.gcm.Seal(nonce, nonce, []byte(plain), nil)
	return base64.StdEncoding.EncodeToString(out), nil
}

// Open decrypts Seal output.
func (b *Box) Open(sealed string) (string, error) {
	if sealed == "" {
		return "", nil
	}
	raw, err := base64.StdEncoding.DecodeString(sealed)
	if err != nil {
		return "", err
	}
	ns := b.gcm.NonceSize()
	if len(raw) < ns {
		return "", errors.New("ciphertext too short")
	}
	plain, err := b.gcm.Open(nil, raw[:ns], raw[ns:], nil)
	if err != nil {
		return "", err
	}
	return string(plain), nil
}
