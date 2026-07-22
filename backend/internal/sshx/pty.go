package sshx

import (
	"fmt"
	"io"
	"net"
	"sync"
	"time"

	"golang.org/x/crypto/ssh"
)

// PtySession is an interactive remote shell.
type PtySession struct {
	client  *ssh.Client
	session *ssh.Session
	stdin   io.WriteCloser
	stdout  io.Reader
	once    sync.Once
}

// StartPty dials SSH and opens a login shell with PTY.
func StartPty(p ConnectParams, cols, rows int) (*PtySession, error) {
	if p.Port == 0 {
		p.Port = 22
	}
	if p.Timeout == 0 {
		p.Timeout = 20 * time.Second
	}
	if cols <= 0 {
		cols = 80
	}
	if rows <= 0 {
		rows = 24
	}
	cfg, err := clientConfig(p)
	if err != nil {
		return nil, err
	}
	addr := net.JoinHostPort(p.Host, fmt.Sprintf("%d", p.Port))
	cli, err := ssh.Dial("tcp", addr, cfg)
	if err != nil {
		return nil, fmt.Errorf("ssh dial: %w", err)
	}
	sess, err := cli.NewSession()
	if err != nil {
		_ = cli.Close()
		return nil, err
	}
	modes := ssh.TerminalModes{
		ssh.ECHO:          1,
		ssh.TTY_OP_ISPEED: 14400,
		ssh.TTY_OP_OSPEED: 14400,
	}
	if err := sess.RequestPty("xterm-256color", rows, cols, modes); err != nil {
		_ = sess.Close()
		_ = cli.Close()
		return nil, fmt.Errorf("request pty: %w", err)
	}
	stdin, err := sess.StdinPipe()
	if err != nil {
		_ = sess.Close()
		_ = cli.Close()
		return nil, err
	}
	stdout, err := sess.StdoutPipe()
	if err != nil {
		_ = sess.Close()
		_ = cli.Close()
		return nil, err
	}
	// With a PTY, stderr is typically merged into the terminal stream.
	if err := sess.Shell(); err != nil {
		_ = sess.Close()
		_ = cli.Close()
		return nil, fmt.Errorf("shell: %w", err)
	}
	return &PtySession{client: cli, session: sess, stdin: stdin, stdout: stdout}, nil
}

func (p *PtySession) Stdin() io.WriteCloser { return p.stdin }
func (p *PtySession) Stdout() io.Reader     { return p.stdout }

func (p *PtySession) WindowChange(cols, rows int) error {
	if cols <= 0 || rows <= 0 {
		return nil
	}
	return p.session.WindowChange(rows, cols)
}

func (p *PtySession) Wait() error { return p.session.Wait() }

func (p *PtySession) Close() error {
	var err error
	p.once.Do(func() {
		_ = p.stdin.Close()
		_ = p.session.Close()
		if p.client != nil {
			err = p.client.Close()
		}
	})
	return err
}
