package sshx

import (
	"bytes"
	"fmt"
	"net"
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
}

type ExecResult struct {
	ExitCode int    `json:"exitCode"`
	Stdout   string `json:"stdout"`
	Stderr   string `json:"stderr"`
	DurationMs int64 `json:"durationMs"`
}

func Exec(p ConnectParams, command string) (ExecResult, error) {
	start := time.Now()
	if p.Port == 0 {
		p.Port = 22
	}
	if p.Timeout == 0 {
		p.Timeout = 20 * time.Second
	}
	cfg, err := clientConfig(p)
	if err != nil {
		return ExecResult{}, err
	}
	addr := net.JoinHostPort(p.Host, fmt.Sprintf("%d", p.Port))
	conn, err := ssh.Dial("tcp", addr, cfg)
	if err != nil {
		return ExecResult{}, fmt.Errorf("ssh dial: %w", err)
	}
	defer conn.Close()

	sess, err := conn.NewSession()
	if err != nil {
		return ExecResult{}, err
	}
	defer sess.Close()

	var stdout, stderr bytes.Buffer
	sess.Stdout = &stdout
	sess.Stderr = &stderr
	runErr := sess.Run(command)
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
	return &ssh.ClientConfig{
		User:            p.Username,
		Auth:            auths,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(), // MVP; known_hosts later
		Timeout:         p.Timeout,
	}, nil
}

func parseKey(pem, passphrase string) (ssh.Signer, error) {
	if passphrase == "" {
		return ssh.ParsePrivateKey([]byte(pem))
	}
	return ssh.ParsePrivateKeyWithPassphrase([]byte(pem), []byte(passphrase))
}
