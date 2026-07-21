package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"

	"minis-ssh-ops/internal/api"
	"minis-ssh-ops/internal/crypto"
	"minis-ssh-ops/internal/sshx"
	"minis-ssh-ops/internal/storage"
)

func main() {
	addr := flag.String("addr", "127.0.0.1:18765", "listen address (loopback only recommended)")
	dataDir := flag.String("data", "", "data directory (default: ./data)")
	token := flag.String("token", "", "API token (default: env OPSD_TOKEN or auto-generate)")
	webDir := flag.String("web", "", "static web UI directory (optional)")
	flag.Parse()

	if *dataDir == "" {
		if env := os.Getenv("OPSD_DATA"); env != "" {
			*dataDir = env
		} else {
			*dataDir = "data"
		}
	}
	if err := os.MkdirAll(*dataDir, 0o700); err != nil {
		log.Fatal(err)
	}

	key, err := loadOrCreateKey(filepath.Join(*dataDir, "master.key"))
	if err != nil {
		log.Fatal("master key:", err)
	}

	store, err := storage.Open(filepath.Join(*dataDir, "ops.db"), key)
	if err != nil {
		log.Fatal("db:", err)
	}
	defer store.Close()

	if *token == "" {
		*token = os.Getenv("OPSD_TOKEN")
	}

	var static http.FileSystem
	if *webDir == "" {
		if _, err := os.Stat("web/static"); err == nil {
			*webDir = "web/static"
		}
	}
	if *webDir != "" {
		static = http.Dir(*webDir)
	}

	pool := sshx.NewPool()
	defer pool.CloseAll()

	srv := api.New(store, pool, *token, static)
	fmt.Fprintf(os.Stderr, "minis-ssh-ops opsd\n  data:  %s\n  addr:  http://%s\n  token: %s\n", *dataDir, *addr, srv.Token)
	if err := srv.Listen(*addr); err != nil {
		log.Fatal(err)
	}
}

func loadOrCreateKey(path string) (*crypto.MasterKey, error) {
	if b, err := os.ReadFile(path); err == nil && len(b) == 32 {
		return crypto.NewKeyFromBytes(b)
	}
	raw, err := crypto.GenerateKeyBytes()
	if err != nil {
		return nil, err
	}
	if err := os.WriteFile(path, raw, 0o600); err != nil {
		return nil, err
	}
	return crypto.NewKeyFromBytes(raw)
}
