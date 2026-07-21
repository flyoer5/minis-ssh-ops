package main

import (
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/api"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/config"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/crypto"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/store"
)

func main() {
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

	srv := api.New(st, cfg.LocalToken)
	log.Printf("ssh-ai-agent backend listening on http://%s", cfg.ListenAddr)
	log.Printf("data dir: %s", cfg.DataDir)
	log.Printf("auth: header X-Local-Token (also written to %s/local.token)", cfg.DataDir)

	if err := http.ListenAndServe(cfg.ListenAddr, srv.Handler()); err != nil {
		log.Fatal(err)
	}
}
