package api

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  8192,
	WriteBufferSize: 8192,
	CheckOrigin:     func(r *http.Request) bool { return true }, // local app only
}

type ptyClientMsg struct {
	Type string `json:"type"` // input | resize | ping
	Data string `json:"data,omitempty"`
	Cols int    `json:"cols,omitempty"`
	Rows int    `json:"rows,omitempty"`
}

type ptyServerMsg struct {
	Type string `json:"type"` // output | error | ready | exit | pong
	Data string `json:"data,omitempty"`
}

func (s *Server) handlePtyWS(w http.ResponseWriter, r *http.Request) {
	tok := r.URL.Query().Get("token")
	if tok == "" {
		tok = r.Header.Get("X-Ops-Token")
	}
	if tok == "" {
		auth := r.Header.Get("Authorization")
		if len(auth) > 7 && auth[:7] == "Bearer " {
			tok = auth[7:]
		}
	}
	if tok != s.Token {
		writeErr(w, 401, "unauthorized")
		return
	}
	hostID := r.URL.Query().Get("host_id")
	if hostID == "" {
		writeErr(w, 400, "host_id required")
		return
	}
	cols := queryInt(r, "cols", 80)
	rows := queryInt(r, "rows", 24)

	cli, err := s.ensureConn(hostID)
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	pty, err := cli.StartPty(cols, rows)
	if err != nil {
		writeErr(w, 502, "pty: "+err.Error())
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		_ = pty.Close()
		log.Printf("ws upgrade: %v", err)
		return
	}

	_ = writeWSJSON(conn, ptyServerMsg{Type: "ready", Data: "pty connected"})

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
					_ = writeWSJSON(conn, ptyServerMsg{Type: "error", Data: err.Error()})
					writeMu.Unlock()
				}
				writeMu.Lock()
				_ = writeWSJSON(conn, ptyServerMsg{Type: "exit"})
				writeMu.Unlock()
				return
			}
		}
	}()

	go func() {
		_ = pty.Wait()
		closeAll()
	}()

	conn.SetReadLimit(1 << 20)
	_ = conn.SetReadDeadline(time.Now().Add(10 * time.Minute))
	conn.SetPongHandler(func(string) error {
		_ = conn.SetReadDeadline(time.Now().Add(10 * time.Minute))
		return nil
	})

	for {
		mt, payload, err := conn.ReadMessage()
		if err != nil {
			closeAll()
			return
		}
		_ = conn.SetReadDeadline(time.Now().Add(10 * time.Minute))

		switch mt {
		case websocket.BinaryMessage, websocket.TextMessage:
			var msg ptyClientMsg
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
					_ = writeWSJSON(conn, ptyServerMsg{Type: "pong"})
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
	var n int
	for _, c := range v {
		if c < '0' || c > '9' {
			return def
		}
		n = n*10 + int(c-'0')
	}
	if n == 0 {
		return def
	}
	return n
}
