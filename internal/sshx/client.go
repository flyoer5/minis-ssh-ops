package sshx

import (
	"bytes"
	"fmt"
	"net"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/ssh"
)

type Auth struct {
	User       string
	Password   string
	PrivateKey string
	Passphrase string
}

type Client struct {
	mu     sync.Mutex
	client *ssh.Client
	addr   string
	user   string
}

type ExecResult struct {
	Stdout   string `json:"stdout"`
	Stderr   string `json:"stderr"`
	ExitCode int    `json:"exit_code"`
	Duration ms     `json:"duration_ms"`
}

type ms int64

func Dial(host string, port int, auth Auth, timeout time.Duration) (*Client, error) {
	if port <= 0 {
		port = 22
	}
	if timeout <= 0 {
		timeout = 15 * time.Second
	}
	var methods []ssh.AuthMethod
	if auth.PrivateKey != "" {
		var signer ssh.Signer
		var err error
		key := []byte(auth.PrivateKey)
		if auth.Passphrase != "" {
			signer, err = ssh.ParsePrivateKeyWithPassphrase(key, []byte(auth.Passphrase))
		} else {
			signer, err = ssh.ParsePrivateKey(key)
		}
		if err != nil {
			return nil, fmt.Errorf("parse private key: %w", err)
		}
		methods = append(methods, ssh.PublicKeys(signer))
	}
	if auth.Password != "" {
		methods = append(methods, ssh.Password(auth.Password))
	}
	if len(methods) == 0 {
		return nil, fmt.Errorf("no auth method provided")
	}
	cfg := &ssh.ClientConfig{
		User:            auth.User,
		Auth:            methods,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(), // personal device; optional TOFU later
		Timeout:         timeout,
	}
	addr := net.JoinHostPort(host, fmt.Sprintf("%d", port))
	c, err := ssh.Dial("tcp", addr, cfg)
	if err != nil {
		return nil, err
	}
	return &Client{client: c, addr: addr, user: auth.User}, nil
}

func (c *Client) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.client != nil {
		err := c.client.Close()
		c.client = nil
		return err
	}
	return nil
}

func (c *Client) Addr() string { return c.addr }
func (c *Client) User() string { return c.user }

// Exec runs a non-interactive command with a timeout.
func (c *Client) Exec(cmd string, timeout time.Duration) (*ExecResult, error) {
	c.mu.Lock()
	client := c.client
	c.mu.Unlock()
	if client == nil {
		return nil, fmt.Errorf("not connected")
	}
	if timeout <= 0 {
		timeout = 60 * time.Second
	}
	sess, err := client.NewSession()
	if err != nil {
		return nil, err
	}
	defer sess.Close()

	var stdout, stderr bytes.Buffer
	sess.Stdout = &stdout
	sess.Stderr = &stderr

	start := time.Now()
	done := make(chan error, 1)
	go func() { done <- sess.Run(cmd) }()

	var runErr error
	select {
	case runErr = <-done:
	case <-time.After(timeout):
		_ = sess.Signal(ssh.SIGKILL)
		return &ExecResult{
			Stdout:   stdout.String(),
			Stderr:   stderr.String() + "\n[timeout]",
			ExitCode: -1,
			Duration: ms(time.Since(start).Milliseconds()),
		}, fmt.Errorf("command timeout after %s", timeout)
	}

	exit := 0
	if runErr != nil {
		if ee, ok := runErr.(*ssh.ExitError); ok {
			exit = ee.ExitStatus()
			runErr = nil
		}
	}
	return &ExecResult{
		Stdout:   stdout.String(),
		Stderr:   stderr.String(),
		ExitCode: exit,
		Duration: ms(time.Since(start).Milliseconds()),
	}, runErr
}

// TestConnection runs a trivial command.
func (c *Client) TestConnection() (string, error) {
	r, err := c.Exec("echo ok && uname -a", 10*time.Second)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(r.Stdout), nil
}

// Pool keeps short-lived connections by host id.
type Pool struct {
	mu    sync.Mutex
	items map[string]*Client
}

func NewPool() *Pool {
	return &Pool{items: make(map[string]*Client)}
}

func (p *Pool) Put(id string, c *Client) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if old, ok := p.items[id]; ok && old != c {
		_ = old.Close()
	}
	p.items[id] = c
}

func (p *Pool) Get(id string) *Client {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.items[id]
}

func (p *Pool) Remove(id string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if c, ok := p.items[id]; ok {
		_ = c.Close()
		delete(p.items, id)
	}
}

func (p *Pool) CloseAll() {
	p.mu.Lock()
	defer p.mu.Unlock()
	for id, c := range p.items {
		_ = c.Close()
		delete(p.items, id)
	}
}
