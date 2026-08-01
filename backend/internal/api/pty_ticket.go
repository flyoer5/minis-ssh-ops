package api

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"strings"
	"time"
)

const ptyTicketTTL = 30 * time.Second

type ptyTicket struct {
	hostID    string
	expiresAt time.Time
}

type createPtyTicketRequest struct {
	HostID string `json:"hostId"`
}

// handleCreatePtyTicket exchanges the API token for a short-lived, one-use
// WebSocket credential. Keeping the long-lived local token out of the WS URL
// prevents it from leaking through browser history, logs, and referrers.
func (s *Server) handleCreatePtyTicket(w http.ResponseWriter, r *http.Request) {
	var req createPtyTicketRequest
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024))
	if err := dec.Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid request")
		return
	}
	hostID := strings.TrimSpace(req.HostID)
	if hostID == "" {
		writeErr(w, http.StatusBadRequest, "hostId required")
		return
	}
	if s.Store == nil {
		writeErr(w, http.StatusInternalServerError, "store unavailable")
		return
	}
	if _, err := s.Store.GetHost(hostID); err != nil {
		writeErr(w, http.StatusNotFound, "host not found")
		return
	}

	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		writeErr(w, http.StatusInternalServerError, "could not create ticket")
		return
	}
	ticket := hex.EncodeToString(raw)
	now := time.Now()
	s.ptyTicketMu.Lock()
	if s.ptyTickets == nil {
		s.ptyTickets = make(map[string]ptyTicket)
	}
	for key, value := range s.ptyTickets {
		if !value.expiresAt.After(now) {
			delete(s.ptyTickets, key)
		}
	}
	s.ptyTickets[ticket] = ptyTicket{hostID: hostID, expiresAt: now.Add(ptyTicketTTL)}
	s.ptyTicketMu.Unlock()

	writeJSON(w, http.StatusOK, map[string]any{
		"ticket":    ticket,
		"expiresIn": int(ptyTicketTTL / time.Second),
	})
}

func (s *Server) consumePtyTicket(ticket, hostID string) bool {
	if ticket == "" || hostID == "" {
		return false
	}
	now := time.Now()
	s.ptyTicketMu.Lock()
	defer s.ptyTicketMu.Unlock()
	value, ok := s.ptyTickets[ticket]
	if ok {
		delete(s.ptyTickets, ticket)
	}
	return ok && value.hostID == hostID && value.expiresAt.After(now)
}
