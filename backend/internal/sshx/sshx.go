package sshx

import (
	"bytes"
	"context"
	"fmt"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"
)

type ConnectParams struct {
	Host          string
	Port          int
	Username      string
	Password      string
	PrivateKeyPEM string
	Passphrase    string
	Timeout       time.Duration
	// HostKeys optional TOFU store; if nil, falls back to insecure ignore (not recommended).
	HostKeys *HostKeyStore
}

type ExecResult struct {
	ExitCode int    `json:"exitCode"`
	Stdout   string `json:"stdout"`
	Stderr   string `json:"stderr"`
	DurationMs int64 `json:"durationMs"`
}

// DefaultPool is used by Exec/SFTP when Pool field is not set on params.
var DefaultPool = NewPool()

func Exec(p ConnectParams, command string) (ExecResult, error) {
	return ExecContext(context.Background(), p, command)
}

// ExecContext runs a remote command and aborts the SSH session when ctx is cancelled
// (client disconnect / user stop). Best-effort: SIGKILL then Close.
func ExecContext(ctx context.Context, p ConnectParams, command string) (ExecResult, error) {
	start := time.Now()
	if p.Port == 0 {
		p.Port = 22
	}
	if p.Timeout == 0 {
		p.Timeout = 12 * time.Second
	}
	if ctx == nil {
		ctx = context.Background()
	}
	// Respect overall timeout via context when parent has no deadline.
	var cancel context.CancelFunc
	if _, ok := ctx.Deadline(); !ok && p.Timeout > 0 {
		ctx, cancel = context.WithTimeout(ctx, p.Timeout)
		defer cancel()
	}

	pool := DefaultPool
	key := poolKey(p)
	cli, pooled, err := pool.DialPooled(p)
	if err != nil {
		return ExecResult{}, fmt.Errorf("ssh dial: %w", err)
	}
	if !pooled {
		defer cli.Close()
	}

	sess, err := cli.NewSession()
	if err != nil {
		if pooled {
			pool.invalidate(key)
		}
		return ExecResult{}, err
	}
	defer sess.Close()

	var stdout, stderr bytes.Buffer
	sess.Stdout = &stdout
	sess.Stderr = &stderr

	errCh := make(chan error, 1)
	go func() {
		errCh <- sess.Run(command)
	}()

	var runErr error
	select {
	case <-ctx.Done():
		// Best-effort kill remote process, then tear down session.
		_ = sess.Signal(ssh.SIGKILL)
		_ = sess.Close()
		// Drain Run result (may be closed pipe error)
		select {
		case <-errCh:
		case <-time.After(2 * time.Second):
		}
		res := ExecResult{
			Stdout:     stdout.String(),
			Stderr:     stderr.String(),
			DurationMs: time.Since(start).Milliseconds(),
			ExitCode:   -1,
		}
		if pooled {
			// Session kill can leave connection in bad state
			pool.invalidate(key)
		}
		return res, ctx.Err()
	case runErr = <-errCh:
	}

	res := ExecResult{
		Stdout:     stdout.String(),
		Stderr:     stderr.String(),
		DurationMs: time.Since(start).Milliseconds(),
		ExitCode:   0,
	}
	if runErr != nil {
		if ee, ok := runErr.(*ssh.ExitError); ok {
			res.ExitCode = ee.ExitStatus()
			return res, nil
		}
		// transport error — drop pooled client
		if pooled {
			pool.invalidate(key)
		}
		return res, runErr
	}
	return res, nil
}

func clientConfig(p ConnectParams) (*ssh.ClientConfig, error) {
	var auths []ssh.AuthMethod
	if strings.TrimSpace(p.PrivateKeyPEM) != "" {
		signer, err := parseKey(p.PrivateKeyPEM, p.Passphrase)
		if err != nil {
			return nil, fmt.Errorf("private key: %w", err)
		}
		auths = append(auths, ssh.PublicKeys(signer))
	}
	if p.Password != "" {
		auths = append(auths, ssh.Password(p.Password))
	}
	if len(auths) == 0 {
		return nil, fmt.Errorf("need password or private key")
	}
	hkcb := ssh.InsecureIgnoreHostKey()
	if p.HostKeys != nil {
		hkcb = p.HostKeys.Callback(p.Host, p.Port)
	}
	return &ssh.ClientConfig{
		User:            p.Username,
		Auth:            auths,
		HostKeyCallback: hkcb,
		Timeout:         p.Timeout,
	}, nil
}

func parseKey(pem, passphrase string) (ssh.Signer, error) {
	if passphrase == "" {
		return ssh.ParsePrivateKey([]byte(pem))
	}
	return ssh.ParsePrivateKeyWithPassphrase([]byte(pem), []byte(passphrase))
}
