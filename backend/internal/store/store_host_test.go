package store

import (
	"path/filepath"
	"testing"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/crypto"
)

func TestUpdateHostExplicitlyClearsSecrets(t *testing.T) {
	dataDir := t.TempDir()
	box, err := crypto.NewBox(dataDir, "")
	if err != nil {
		t.Fatal(err)
	}
	st, err := Open(filepath.Join(dataDir, "data.db"), box)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = st.Close() })

	host, err := st.CreateHost(Host{
		Name:          "test",
		Host:          "127.0.0.1",
		Port:          22,
		Username:      "root",
		Password:      "old-password",
		PrivateKeyPEM: "old-key",
		Passphrase:    "old-passphrase",
	})
	if err != nil {
		t.Fatal(err)
	}

	if _, err := st.UpdateHost(host.ID, Host{ClearPassword: true}); err != nil {
		t.Fatal(err)
	}
	secrets, err := st.GetHostSecrets(host.ID)
	if err != nil {
		t.Fatal(err)
	}
	if secrets.Password != "" {
		t.Fatalf("password was not cleared: %q", secrets.Password)
	}
	if secrets.PrivateKeyPEM != "old-key" || secrets.Passphrase != "old-passphrase" {
		t.Fatalf("unrelated secrets changed: %#v", secrets)
	}

	if _, err := st.UpdateHost(host.ID, Host{
		Password:        "new-password",
		ClearPrivateKey: true,
		ClearPassphrase: true,
	}); err != nil {
		t.Fatal(err)
	}
	secrets, err = st.GetHostSecrets(host.ID)
	if err != nil {
		t.Fatal(err)
	}
	if secrets.PrivateKeyPEM != "" || secrets.Passphrase != "" {
		t.Fatalf("key secrets were not cleared: %#v", secrets)
	}
}

func TestUpdateHostNewSecretOverridesClearFlag(t *testing.T) {
	dataDir := t.TempDir()
	box, err := crypto.NewBox(dataDir, "")
	if err != nil {
		t.Fatal(err)
	}
	st, err := Open(filepath.Join(dataDir, "data.db"), box)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = st.Close() })

	host, err := st.CreateHost(Host{
		Host:     "127.0.0.1",
		Port:     22,
		Username: "root",
		Password: "old-password",
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := st.UpdateHost(host.ID, Host{
		ClearPassword: true,
		Password:      "new-password",
	}); err != nil {
		t.Fatal(err)
	}
	secrets, err := st.GetHostSecrets(host.ID)
	if err != nil {
		t.Fatal(err)
	}
	if secrets.Password != "new-password" {
		t.Fatalf("password = %q, want new-password", secrets.Password)
	}
}
func TestUpdateHostRejectsClearingLastCredential(t *testing.T) {
	dataDir := t.TempDir()
	box, err := crypto.NewBox(dataDir, "")
	if err != nil {
		t.Fatal(err)
	}
	st, err := Open(filepath.Join(dataDir, "data.db"), box)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = st.Close() })

	host, err := st.CreateHost(Host{
		Host:     "127.0.0.1",
		Port:     22,
		Username: "root",
		Password: "password",
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := st.UpdateHost(host.ID, Host{ClearPassword: true}); err == nil {
		t.Fatal("expected clearing the last credential to fail")
	}
	secrets, err := st.GetHostSecrets(host.ID)
	if err != nil {
		t.Fatal(err)
	}
	if secrets.Password != "password" {
		t.Fatalf("password changed after rejected update: %q", secrets.Password)
	}
}
