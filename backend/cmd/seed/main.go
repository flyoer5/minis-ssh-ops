package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/crypto"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/store"
)

// seed <dataDir> <host.json> <llm.json>
func main() {
	if len(os.Args) < 4 {
		fmt.Fprintln(os.Stderr, "usage: seed <dataDir> <host.json> <llm.json>")
		os.Exit(2)
	}
	dataDir, hostPath, llmPath := os.Args[1], os.Args[2], os.Args[3]
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		panic(err)
	}
	box, err := crypto.NewBox(dataDir, "")
	if err != nil {
		panic(err)
	}
	st, err := store.Open(filepath.Join(dataDir, "data.db"), box)
	if err != nil {
		panic(err)
	}
	defer st.Close()

	hb, err := os.ReadFile(hostPath)
	if err != nil {
		panic(err)
	}
	var h store.Host
	if err := json.Unmarshal(hb, &h); err != nil {
		panic(err)
	}
	// replace existing same name/host if present
	list, _ := st.ListHosts()
	for _, cur := range list {
		if cur.Host == h.Host && cur.Port == h.Port && cur.Username == h.Username {
			_ = st.DeleteHost(cur.ID)
		}
	}
	out, err := st.CreateHost(h)
	if err != nil {
		panic(err)
	}
	fmt.Println("host_ok", out.ID, out.Name, out.Host, out.Port)

	lb, err := os.ReadFile(llmPath)
	if err != nil {
		panic(err)
	}
	var llm store.LLMSettings
	if err := json.Unmarshal(lb, &llm); err != nil {
		panic(err)
	}
	lo, err := st.PutLLM(llm)
	if err != nil {
		panic(err)
	}
	fmt.Println("llm_ok", lo.BaseURL, lo.Model, lo.APIKeySet)
}
