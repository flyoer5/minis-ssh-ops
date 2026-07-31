package sshx

import (
	"strings"
	"testing"
)

func TestClientConfigRequiresHostKeyStore(t *testing.T) {
	_, err := clientConfig(ConnectParams{
		Host:     "example.com",
		Port:     22,
		Username: "root",
		Password: "secret",
	})
	if err == nil {
		t.Fatal("clientConfig accepted a connection without host-key verification")
	}
	if !strings.Contains(err.Error(), "host key store required") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestClientConfigUsesHostKeyStore(t *testing.T) {
	store, err := NewHostKeyStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := clientConfig(ConnectParams{
		Host:     "example.com",
		Port:     22,
		Username: "root",
		Password: "secret",
		HostKeys: store,
	})
	if err != nil {
		t.Fatal(err)
	}
	if cfg.HostKeyCallback == nil {
		t.Fatal("HostKeyCallback is nil")
	}
}
