package api

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/agent"
	"github.com/flyoer5/ssh-ai-agent/backend/internal/store"
)

func (s *Server) handleGetLLM(w http.ResponseWriter, r *http.Request) {
	st, err := s.Store.GetLLM()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, st)
}

// handleListLLMModels proxies OpenAI-compatible GET {base}/models using stored API key.
func (s *Server) handleListLLMModels(w http.ResponseWriter, r *http.Request) {
	full, err := s.Store.GetLLMFull()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	if strings.TrimSpace(full.BaseURL) == "" {
		writeErr(w, http.StatusBadRequest, "configure LLM baseUrl first")
		return
	}
	ids, err := agent.ListModels(full.BaseURL, full.APIKey)
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"models": ids})
}

func (s *Server) handlePutLLM(w http.ResponseWriter, r *http.Request) {
	var in store.LLMSettings
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	out, err := s.Store.PutLLM(in)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, out)
}
