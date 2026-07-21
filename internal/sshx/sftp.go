package sshx

import (
	"fmt"
	"io"
	"os"
	"path"
	"strings"
	"time"

	"github.com/pkg/sftp"
)

type FileEntry struct {
	Name    string    `json:"name"`
	Path    string    `json:"path"`
	Size    int64     `json:"size"`
	Mode    string    `json:"mode"`
	IsDir   bool      `json:"is_dir"`
	ModTime time.Time `json:"mod_time"`
}

func (c *Client) sftpClient() (*sftp.Client, error) {
	c.mu.Lock()
	client := c.client
	c.mu.Unlock()
	if client == nil {
		return nil, fmt.Errorf("not connected")
	}
	return sftp.NewClient(client)
}

// ListDir lists a remote directory (default ".").
func (c *Client) ListDir(remote string) ([]FileEntry, error) {
	sc, err := c.sftpClient()
	if err != nil {
		return nil, err
	}
	defer sc.Close()

	if remote == "" {
		remote = "."
	}
	// resolve relative
	if !strings.HasPrefix(remote, "/") {
		wd, err := sc.Getwd()
		if err == nil {
			remote = path.Join(wd, remote)
		}
	}
	infos, err := sc.ReadDir(remote)
	if err != nil {
		return nil, err
	}
	out := make([]FileEntry, 0, len(infos))
	for _, fi := range infos {
		name := fi.Name()
		out = append(out, FileEntry{
			Name:    name,
			Path:    path.Join(remote, name),
			Size:    fi.Size(),
			Mode:    fi.Mode().String(),
			IsDir:   fi.IsDir(),
			ModTime: fi.ModTime().UTC(),
		})
	}
	return out, nil
}

// ReadFile reads a remote file up to maxBytes (0 = 2MiB default).
func (c *Client) ReadFile(remote string, maxBytes int64) ([]byte, error) {
	if maxBytes <= 0 {
		maxBytes = 2 << 20
	}
	sc, err := c.sftpClient()
	if err != nil {
		return nil, err
	}
	defer sc.Close()
	f, err := sc.Open(remote)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return nil, err
	}
	if st.IsDir() {
		return nil, fmt.Errorf("is a directory")
	}
	if st.Size() > maxBytes {
		return nil, fmt.Errorf("file too large: %d > %d", st.Size(), maxBytes)
	}
	return io.ReadAll(io.LimitReader(f, maxBytes+1))
}

// WriteFile writes bytes to remote path (creates/truncates).
func (c *Client) WriteFile(remote string, data []byte) error {
	sc, err := c.sftpClient()
	if err != nil {
		return err
	}
	defer sc.Close()
	// ensure parent
	dir := path.Dir(remote)
	if dir != "" && dir != "." {
		_ = sc.MkdirAll(dir)
	}
	f, err := sc.OpenFile(remote, os.O_WRONLY|os.O_CREATE|os.O_TRUNC)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = f.Write(data)
	return err
}

// Mkdir creates a remote directory (including parents).
func (c *Client) Mkdir(remote string) error {
	sc, err := c.sftpClient()
	if err != nil {
		return err
	}
	defer sc.Close()
	return sc.MkdirAll(remote)
}

// Remove removes a remote file or empty directory.
func (c *Client) Remove(remote string, recursive bool) error {
	sc, err := c.sftpClient()
	if err != nil {
		return err
	}
	defer sc.Close()
	if recursive {
		return sc.RemoveAll(remote)
	}
	return sc.Remove(remote)
}

// Stat returns file info.
func (c *Client) Stat(remote string) (*FileEntry, error) {
	sc, err := c.sftpClient()
	if err != nil {
		return nil, err
	}
	defer sc.Close()
	fi, err := sc.Stat(remote)
	if err != nil {
		return nil, err
	}
	return &FileEntry{
		Name:    path.Base(remote),
		Path:    remote,
		Size:    fi.Size(),
		Mode:    fi.Mode().String(),
		IsDir:   fi.IsDir(),
		ModTime: fi.ModTime().UTC(),
	}, nil
}
