package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"io"

	"golang.org/x/crypto/pbkdf2"
)

const (
	saltSize   = 16
	nonceSize  = 12
	keyLen     = 32
	pbkdfIters = 100_000
)

// MasterKey holds a derived AES-256 key for encrypting secrets at rest.
type MasterKey struct {
	key []byte
}

// DeriveKey derives a master key from password + salt (salt may be nil to generate).
func DeriveKey(password string, salt []byte) (*MasterKey, []byte, error) {
	if password == "" {
		return nil, nil, errors.New("password required")
	}
	if salt == nil {
		salt = make([]byte, saltSize)
		if _, err := io.ReadFull(rand.Reader, salt); err != nil {
			return nil, nil, err
		}
	}
	key := pbkdf2.Key([]byte(password), salt, pbkdfIters, keyLen, sha256.New)
	return &MasterKey{key: key}, salt, nil
}

// NewKeyFromBytes wraps a raw 32-byte key (for device-generated keys).
func NewKeyFromBytes(b []byte) (*MasterKey, error) {
	if len(b) != keyLen {
		return nil, errors.New("key must be 32 bytes")
	}
	cp := make([]byte, keyLen)
	copy(cp, b)
	return &MasterKey{key: cp}, nil
}

// GenerateKey creates a random device master key.
func GenerateKey() (*MasterKey, error) {
	b, err := GenerateKeyBytes()
	if err != nil {
		return nil, err
	}
	return &MasterKey{key: b}, nil
}

// GenerateKeyBytes returns a new random 32-byte key (for persistence).
func GenerateKeyBytes() ([]byte, error) {
	b := make([]byte, keyLen)
	if _, err := io.ReadFull(rand.Reader, b); err != nil {
		return nil, err
	}
	return b, nil
}

// Bytes returns a copy of the raw key material.
func (m *MasterKey) Bytes() []byte {
	cp := make([]byte, len(m.key))
	copy(cp, m.key)
	return cp
}

// Encrypt returns base64(nonce|ciphertext).
func (m *MasterKey) Encrypt(plain []byte) (string, error) {
	block, err := aes.NewCipher(m.key)
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, nonceSize)
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	out := gcm.Seal(nonce, nonce, plain, nil)
	return base64.StdEncoding.EncodeToString(out), nil
}

// Decrypt reverses Encrypt.
func (m *MasterKey) Decrypt(b64 string) ([]byte, error) {
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, err
	}
	if len(raw) < nonceSize {
		return nil, errors.New("ciphertext too short")
	}
	block, err := aes.NewCipher(m.key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	nonce, ct := raw[:nonceSize], raw[nonceSize:]
	return gcm.Open(nil, nonce, ct, nil)
}

// EncryptString encrypts a string.
func (m *MasterKey) EncryptString(s string) (string, error) {
	return m.Encrypt([]byte(s))
}

// DecryptString decrypts to string.
func (m *MasterKey) DecryptString(b64 string) (string, error) {
	b, err := m.Decrypt(b64)
	if err != nil {
		return "", err
	}
	return string(b), nil
}
