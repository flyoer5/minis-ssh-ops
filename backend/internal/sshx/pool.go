package sshx

import (
	"fmt"
	"net"
	"sync"
	"time"

	"golang.org/x/crypto/ssh"
)

// Pool reuses SSH clients per host identity to cut dial latency (probe/agent multi-step).
type Pool struct {
	mu      sync.Mutex
	clients map[string]*pooled
	ttl     time.Duration
}

type pooled struct {
	cli     *ssh.Client
	created time.Time
	last    time.Time
}

func NewPool() *Pool {
	return &Pool{
		clients: map[string]*pooled{},
		ttl:     8 * time.Minute,
	}
}

func poolKey(p ConnectParams) string {
	port := p.Port
	if port <= 0 {
		port = 22
	}
	// auth material fingerprint-ish: user+host+port+len(secret)
	return fmt.Sprintf("%s@%s:%d|p%d|k%d", p.Username, p.Host, port, len(p.Password), len(p.PrivateKeyPEM))
}

func (p *Pool) get(key string) *ssh.Client {
	p.mu.Lock()
	defer p.mu.Unlock()
	e, ok := p.clients[key]
	if !ok {
		return nil
	}
	if time.Since(e.created) > p.ttl {
		_ = e.cli.Close()
		delete(p.clients, key)
		return nil
	}
	// cheap liveness without full session handshake cost
	if _, _, err := e.cli.Conn.SendRequest("kevin@golang.org/keepalive@golang", true, nil); err != nil {
		// fallback: try new session
		s, err2 := e.cli.NewSession()
		if err2 != nil {
			_ = e.cli.Close()
			delete(p.clients, key)
			return nil
		}
		_ = s.Close()
	}
	e.last = time.Now()
	return e.cli
}

func (p *Pool) put(key string, cli *ssh.Client) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if old, ok := p.clients[key]; ok && old.cli != cli {
		_ = old.cli.Close()
	}
	p.clients[key] = &pooled{cli: cli, created: time.Now(), last: time.Now()}
}

func (p *Pool) invalidate(key string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if e, ok := p.clients[key]; ok {
		_ = e.cli.Close()
		delete(p.clients, key)
	}
}

func (p *Pool) CloseAll() {
	p.mu.Lock()
	defer p.mu.Unlock()
	for k, e := range p.clients {
		_ = e.cli.Close()
		delete(p.clients, k)
	}
}

// Dial returns a client (pooled when Pool != nil). Caller must NOT Close if from pool.
// For one-shot Exec, use Exec/ListDir which manage lifecycle.
func Dial(p ConnectParams) (*ssh.Client, bool, error) {
	// returns cli, pooled, err
	if p.Port == 0 {
		p.Port = 22
	}
	if p.Timeout == 0 {
		p.Timeout = 12 * time.Second
	}
	cfg, err := clientConfig(p)
	if err != nil {
		return nil, false, err
	}
	addr := net.JoinHostPort(p.Host, fmt.Sprintf("%d", p.Port))
	cli, err := ssh.Dial("tcp", addr, cfg)
	if err != nil {
		return nil, false, err
	}
	return cli, false, nil
}

// DialPooled uses pool when non-nil.
func (pool *Pool) DialPooled(p ConnectParams) (*ssh.Client, bool, error) {
	if pool == nil {
		return Dial(p)
	}
	key := poolKey(p)
	if cli := pool.get(key); cli != nil {
		return cli, true, nil
	}
	cli, _, err := Dial(p)
	if err != nil {
		return nil, false, err
	}
	pool.put(key, cli)
	return cli, true, nil
}
