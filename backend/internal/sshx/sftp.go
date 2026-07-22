package sshx

import (
	"fmt"
	"io"
	"net"
	"os"
	"path"
	"time"

	"github.com/pkg/sftp"
	"golang.org/x/crypto/ssh"
)

type FileEntry struct {
	Name    string    `json:"name"`
	Path    string    `json:"path"`
	Size    int64     `json:"size"`
	Mode    string    `json:"mode"`
	IsDir   bool      `json:"isDir"`
	ModTime time.Time `json:"modTime"`
}

func dialSSH(p ConnectParams) (*ssh.Client, error) {
	if p.Port == 0 {
		p.Port = 22
	}
	if p.Timeout == 0 {
		p.Timeout = 20 * time.Second
	}
	cfg, err := clientConfig(p)
	if err != nil {
		return nil, err
	}
	addr := netJoin(p.Host, p.Port)
	return ssh.Dial("tcp", addr, cfg)
}

func netJoin(host string, port int) string {
	return net.JoinHostPort(host, fmt.Sprintf("%d", port))
}

func withSFTP(p ConnectParams, fn func(*sftp.Client) error) error {
	cli, err := dialSSH(p)
	if err != nil {
		return fmt.Errorf("ssh dial: %w", err)
	}
	defer cli.Close()
	sc, err := sftp.NewClient(cli)
	if err != nil {
		return fmt.Errorf("sftp: %w", err)
	}
	defer sc.Close()
	return fn(sc)
}

func ListDir(p ConnectParams, remote string) ([]FileEntry, error) {
	var out []FileEntry
	err := withSFTP(p, func(sc *sftp.Client) error {
		if remote == "" {
			remote = "."
		}
		if remote[0] != '/' {
			if wd, err := sc.Getwd(); err == nil {
				remote = path.Join(wd, remote)
			}
		}
		infos, err := sc.ReadDir(remote)
		if err != nil {
			return err
		}
		for _, fi := range infos {
			out = append(out, FileEntry{
				Name:    fi.Name(),
				Path:    path.Join(remote, fi.Name()),
				Size:    fi.Size(),
				Mode:    fi.Mode().String(),
				IsDir:   fi.IsDir(),
				ModTime: fi.ModTime().UTC(),
			})
		}
		return nil
	})
	if out == nil {
		out = []FileEntry{}
	}
	return out, err
}

func ReadFile(p ConnectParams, remote string, maxBytes int64) ([]byte, error) {
	if maxBytes <= 0 {
		maxBytes = 2 << 20
	}
	var data []byte
	err := withSFTP(p, func(sc *sftp.Client) error {
		f, err := sc.Open(remote)
		if err != nil {
			return err
		}
		defer f.Close()
		st, err := f.Stat()
		if err != nil {
			return err
		}
		if st.IsDir() {
			return fmt.Errorf("is a directory")
		}
		if st.Size() > maxBytes {
			return fmt.Errorf("file too large: %d > %d", st.Size(), maxBytes)
		}
		data, err = io.ReadAll(io.LimitReader(f, maxBytes+1))
		return err
	})
	return data, err
}

func WriteFile(p ConnectParams, remote string, content []byte) error {
	return withSFTP(p, func(sc *sftp.Client) error {
		dir := path.Dir(remote)
		if dir != "" && dir != "." {
			_ = sc.MkdirAll(dir)
		}
		f, err := sc.OpenFile(remote, os.O_WRONLY|os.O_CREATE|os.O_TRUNC)
		if err != nil {
			return err
		}
		defer f.Close()
		_, err = f.Write(content)
		return err
	})
}
