package sshx

import (
	"fmt"
	"io"
	"os"
	"path"
	"time"

	"github.com/pkg/sftp"
)

type FileEntry struct {
	Name    string    `json:"name"`
	Path    string    `json:"path"`
	Size    int64     `json:"size"`
	Mode    string    `json:"mode"`
	IsDir   bool      `json:"isDir"`
	ModTime time.Time `json:"modTime"`
}

func withSFTP(p ConnectParams, fn func(*sftp.Client) error) error {
	if p.Port == 0 {
		p.Port = 22
	}
	if p.Timeout == 0 {
		p.Timeout = 12 * time.Second
	}
	pool := DefaultPool
	key := poolKey(p)
	cli, pooled, err := pool.DialPooled(p)
	if err != nil {
		return fmt.Errorf("ssh dial: %w", err)
	}
	if !pooled {
		defer cli.Close()
	}
	sc, err := sftp.NewClient(cli)
	if err != nil {
		if pooled {
			pool.invalidate(key)
		}
		return fmt.Errorf("sftp: %w", err)
	}
	defer sc.Close()
	if err := fn(sc); err != nil {
		// don't always drop pool; only on channel death handled by next DialPooled
		return err
	}
	return nil
}

func ListDir(p ConnectParams, remote string) (string, []FileEntry, error) {
	var out []FileEntry
	resolved := remote
	err := withSFTP(p, func(sc *sftp.Client) error {
		if remote == "" || remote == "." {
			if wd, err := sc.Getwd(); err == nil {
				remote = wd
			} else {
				remote = "/"
			}
		} else if remote[0] != '/' {
			if wd, err := sc.Getwd(); err == nil {
				remote = path.Join(wd, remote)
			}
		}
		resolved = remote
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
	return resolved, out, err
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

func Mkdir(p ConnectParams, remote string) error {
	return withSFTP(p, func(sc *sftp.Client) error {
		return sc.MkdirAll(remote)
	})
}

func Rename(p ConnectParams, oldPath, newPath string) error {
	return withSFTP(p, func(sc *sftp.Client) error {
		if oldPath == "" || newPath == "" {
			return fmt.Errorf("path required")
		}
		dir := path.Dir(newPath)
		if dir != "" && dir != "." {
			_ = sc.MkdirAll(dir)
		}
		return sc.Rename(oldPath, newPath)
	})
}

func Remove(p ConnectParams, remote string, recursive bool) error {
	return withSFTP(p, func(sc *sftp.Client) error {
		if remote == "" || remote == "/" || remote == "." {
			return fmt.Errorf("refusing to remove path")
		}
		if !recursive {
			return sc.Remove(remote)
		}
		// recursive walk
		var walk func(string) error
		walk = func(p string) error {
			st, err := sc.Stat(p)
			if err != nil {
				return err
			}
			if !st.IsDir() {
				return sc.Remove(p)
			}
			entries, err := sc.ReadDir(p)
			if err != nil {
				return err
			}
			for _, e := range entries {
				if err := walk(path.Join(p, e.Name())); err != nil {
					return err
				}
			}
			return sc.RemoveDirectory(p)
		}
		return walk(remote)
	})
}
