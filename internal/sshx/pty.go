package sshx

import (
	"fmt"
	"io"
	"sync"

	"golang.org/x/crypto/ssh"
)

// PtySession is an interactive remote shell over SSH.
type PtySession struct {
	session *ssh.Session
	stdin   io.WriteCloser
	stdout  io.Reader
	once    sync.Once
}

// StartPty opens a shell with PTY (default xterm-256color).
// With a PTY allocated, remote stdout/stderr both appear on the session stdout stream.
func (c *Client) StartPty(cols, rows int) (*PtySession, error) {
	c.mu.Lock()
	client := c.client
	c.mu.Unlock()
	if client == nil {
		return nil, fmt.Errorf("not connected")
	}
	if cols <= 0 {
		cols = 80
	}
	if rows <= 0 {
		rows = 24
	}
	sess, err := client.NewSession()
	if err != nil {
		return nil, err
	}
	modes := ssh.TerminalModes{
		ssh.ECHO:          1,
		ssh.TTY_OP_ISPEED: 14400,
		ssh.TTY_OP_OSPEED: 14400,
	}
	if err := sess.RequestPty("xterm-256color", rows, cols, modes); err != nil {
		_ = sess.Close()
		return nil, fmt.Errorf("request pty: %w", err)
	}
	stdin, err := sess.StdinPipe()
	if err != nil {
		_ = sess.Close()
		return nil, err
	}
	stdout, err := sess.StdoutPipe()
	if err != nil {
		_ = sess.Close()
		return nil, err
	}
	if err := sess.Shell(); err != nil {
		_ = sess.Close()
		return nil, fmt.Errorf("shell: %w", err)
	}
	return &PtySession{session: sess, stdin: stdin, stdout: stdout}, nil
}

func (p *PtySession) Stdin() io.WriteCloser { return p.stdin }
func (p *PtySession) Stdout() io.Reader     { return p.stdout }
func (p *PtySession) Session() *ssh.Session { return p.session }

func (p *PtySession) WindowChange(cols, rows int) error {
	if cols <= 0 || rows <= 0 {
		return nil
	}
	return p.session.WindowChange(rows, cols)
}

func (p *PtySession) Close() error {
	var err error
	p.once.Do(func() {
		_ = p.stdin.Close()
		err = p.session.Close()
	})
	return err
}

// Wait blocks until remote shell exits.
func (p *PtySession) Wait() error {
	return p.session.Wait()
}
