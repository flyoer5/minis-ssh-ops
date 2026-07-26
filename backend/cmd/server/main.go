package main

import (
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/api"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/config"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/crypto"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/netx"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/sshx"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/store"
)

func main() {
	// Android: pure Go DNS, not [::1]:53
	netx.ConfigureDefault()

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	// Safety: refuse non-loopback binds unless explicitly overridden (debug only).
	if host, _, err := net.SplitHostPort(cfg.ListenAddr); err == nil {
		if host != "127.0.0.1" && host != "localhost" && os.Getenv("SSH_AI_ALLOW_NON_LOOPBACK") != "1" {
			log.Fatalf("refusing to listen on %s (only 127.0.0.1 allowed)", cfg.ListenAddr)
		}
	}

	box, err := crypto.NewBox(cfg.DataDir, cfg.MasterKeyHex)
	if err != nil {
		log.Fatalf("crypto: %v", err)
	}
	dbPath := filepath.Join(cfg.DataDir, "data.db")
	st, err := store.Open(dbPath, box)
	if err != nil {
		log.Fatalf("store: %v", err)
	}
	defer st.Close()

	hk, err := sshx.NewHostKeyStore(cfg.DataDir)
	if err != nil {
		log.Fatalf("known_hosts: %v", err)
	}
	srv := api.New(st, cfg.LocalToken, hk)
	log.Printf("ssh-ai-agent backend listening on http://%s", cfg.ListenAddr)
	log.Printf("data dir: %s", cfg.DataDir)
	log.Printf("auth: header X-Local-Token (also written to %s/local.token)", cfg.DataDir)

	// Timeouts: ReadHeaderTimeout guards slow-loris / stuck clients. Read/Write
	// are left 0 because PTY (websocket) and LLM streaming are long-lived by
	// design; the per-request clients above carry their own timeouts.
	httpSrv := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 15 * time.Second,
	}
	if err := httpSrv.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}
