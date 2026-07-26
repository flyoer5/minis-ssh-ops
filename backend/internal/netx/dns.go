package netx

import (
	"context"
	"net"
	"os"
	"strings"
	"sync"
	"time"
)

// Android (and some musl/proot envs) leave Go with no usable DNS: it falls back
// to [::1]:53 / 127.0.0.1:53 and fails with "connection refused". PreferGo +
// public resolvers fixes LLM BaseURL lookups without needing /etc/resolv.conf.

var (
	once     sync.Once
	resolver *net.Resolver
)

// ConfigureDefault installs a PreferGo resolver on net.DefaultResolver.
// Safe to call multiple times; first call wins.
func ConfigureDefault() {
	once.Do(func() {
		resolver = newResolver()
		net.DefaultResolver = resolver
	})
}

// Resolver returns the shared PreferGo resolver (after ConfigureDefault).
func Resolver() *net.Resolver {
	ConfigureDefault()
	return resolver
}

// Dialer returns a Dialer that uses our PreferGo resolver.
func Dialer(timeout time.Duration) *net.Dialer {
	ConfigureDefault()
	return &net.Dialer{
		Timeout:   timeout,
		KeepAlive: 30 * time.Second,
		Resolver:  resolver,
	}
}

func newResolver() *net.Resolver {
	servers := nameservers()
	return &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
			d := net.Dialer{Timeout: 5 * time.Second}
			var last error
			for _, s := range servers {
				// Prefer udp for DNS; fall back to tcp if needed by dialer.
				c, err := d.DialContext(ctx, "udp", s)
				if err == nil {
					return c, nil
				}
				last = err
				c, err = d.DialContext(ctx, "tcp", s)
				if err == nil {
					return c, nil
				}
				last = err
			}
			return nil, last
		},
	}
}

func nameservers() []string {
	seen := map[string]struct{}{}
	var out []string
	add := func(host string) {
		host = strings.TrimSpace(host)
		if host == "" {
			return
		}
		// strip zone / brackets
		host = strings.Trim(host, "[]")
		if i := strings.IndexByte(host, '%'); i >= 0 {
			host = host[:i]
		}
		// if already host:port
		if _, _, err := net.SplitHostPort(host); err == nil {
			if _, ok := seen[host]; !ok {
				seen[host] = struct{}{}
				out = append(out, host)
			}
			return
		}
		// ipv6 needs brackets
		addr := host
		if strings.Contains(host, ":") {
			addr = net.JoinHostPort(host, "53")
		} else {
			addr = host + ":53"
		}
		if _, ok := seen[addr]; !ok {
			seen[addr] = struct{}{}
			out = append(out, addr)
		}
	}

	// Explicit override: SSH_AI_DNS="8.8.8.8,1.1.1.1"
	if v := os.Getenv("SSH_AI_DNS"); v != "" {
		for _, p := range strings.Split(v, ",") {
			add(p)
		}
	}
	// Common Android / DHCP env if launcher injects them
	for _, k := range []string{"ANDROID_DNS1", "ANDROID_DNS2", "DNS1", "DNS2"} {
		add(os.Getenv(k))
	}
	// Public fallbacks (CN-friendly + global)
	for _, s := range []string{
		"223.5.5.5",     // AliDNS
		"119.29.29.29",  // DNSPod
		"8.8.8.8",
		"1.1.1.1",
	} {
		add(s)
	}
	return out
}
