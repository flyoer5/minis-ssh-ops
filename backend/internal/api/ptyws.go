package api

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/sshx"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  8192,
	WriteBufferSize: 8192,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

type ptyIn struct {
	Type string `json:"type"` // input | resize | ping
	Data string `json:"data,omitempty"`
	Cols int    `json:"cols,omitempty"`
	Rows int    `json:"rows,omitempty"`
}

type ptyOut struct {
	Type string `json:"type"` // ready | error | exit | pong
	Data string `json:"data,omitempty"`
}

func (s *Server) handlePtyWS(w http.ResponseWriter, r *http.Request) {
	// Auth via query token (WS cannot always set custom headers from WebView).
	tok := r.URL.Query().Get("token")
	if tok == "" {
		tok = r.Header.Get("X-Local-Token")
	}
	if s.LocalToken != "" && tok != s.LocalToken {
		writeErr(w, http.StatusUnauthorized, "invalid or missing token")
		return
	}
	hostID := r.URL.Query().Get("hostId")
	if hostID == "" {
		hostID = r.URL.Query().Get("host_id")
	}
	if hostID == "" {
		writeErr(w, http.StatusBadRequest, "hostId required")
		return
	}
	cols := queryInt(r, "cols", 80)
	rows := queryInt(r, "rows", 24)

	h, err := s.Store.GetHost(hostID)
	if err != nil {
		writeErr(w, http.StatusNotFound, "host not found")
		return
	}
	sec, err := s.Store.GetHostSecrets(hostID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}

	pty, err := sshx.StartPty(sshx.ConnectParams{
		Host:          h.Host,
		Port:          h.Port,
		Username:      h.Username,
		Password:      sec.Password,
		PrivateKeyPEM: sec.PrivateKeyPEM,
		Passphrase:    sec.Passphrase,
		HostKeys:      s.HostKeys,
	}, cols, rows)
	if err != nil {
		writeErr(w, http.StatusBadGateway, "pty: "+err.Error())
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		_ = pty.Close()
		log.Printf("ws upgrade: %v", err)
		return
	}

	_ = writeWSJSON(conn, ptyOut{Type: "ready", Data: "connected"})

	var writeMu sync.Mutex
	var once sync.Once
	closeAll := func() {
		once.Do(func() {
			_ = pty.Close()
			_ = conn.Close()
		})
	}

	// SSH -> WS (binary terminal bytes)
	go func() {
		defer closeAll()
		buf := make([]byte, 32*1024)
		for {
			n, err := pty.Stdout().Read(buf)
			if n > 0 {
				writeMu.Lock()
				werr := conn.WriteMessage(websocket.BinaryMessage, buf[:n])
				writeMu.Unlock()
				if werr != nil {
					return
				}
			}
			if err != nil {
				if err != io.EOF {
					writeMu.Lock()
					_ = writeWSJSON(conn, ptyOut{Type: "error", Data: err.Error()})
					writeMu.Unlock()
				}
				writeMu.Lock()
				_ = writeWSJSON(conn, ptyOut{Type: "exit"})
				writeMu.Unlock()
				return
			}
		}
	}()

	go func() {
		_ = pty.Wait()
		closeAll()
	}()

	_ = conn.SetReadDeadline(time.Now().Add(30 * time.Minute))
	conn.SetPongHandler(func(string) error {
		_ = conn.SetReadDeadline(time.Now().Add(30 * time.Minute))
		return nil
	})

	for {
		mt, payload, err := conn.ReadMessage()
		if err != nil {
			closeAll()
			return
		}
		_ = conn.SetReadDeadline(time.Now().Add(30 * time.Minute))
		switch mt {
		case websocket.BinaryMessage, websocket.TextMessage:
			var msg ptyIn
			if json.Unmarshal(payload, &msg) == nil && msg.Type != "" {
				switch msg.Type {
				case "input":
					if msg.Data != "" {
						if _, err := pty.Stdin().Write([]byte(msg.Data)); err != nil {
							closeAll()
							return
						}
					}
				case "resize":
					_ = pty.WindowChange(msg.Cols, msg.Rows)
				case "ping":
					writeMu.Lock()
					_ = writeWSJSON(conn, ptyOut{Type: "pong"})
					writeMu.Unlock()
				}
				continue
			}
			if _, err := pty.Stdin().Write(payload); err != nil {
				closeAll()
				return
			}
		}
	}
}

func writeWSJSON(conn *websocket.Conn, v any) error {
	b, err := json.Marshal(v)
	if err != nil {
		return err
	}
	return conn.WriteMessage(websocket.TextMessage, b)
}

func queryInt(r *http.Request, key string, def int) int {
	v := r.URL.Query().Get(key)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil || n <= 0 {
		return def
	}
	return n
}
