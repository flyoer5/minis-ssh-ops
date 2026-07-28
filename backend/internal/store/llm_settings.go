package store

import (
	"fmt"
	"strings"
)

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
