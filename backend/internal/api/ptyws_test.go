package api

import (
	"net/http/httptest"
	"testing"
)

func TestAllowLocalWSOrigin(t *testing.T) {
	tests := []struct {
		name   string
		origin string
		want   bool
	}{
		{name: "native client", want: true},
		{name: "loopback", origin: "http://127.0.0.1:17890", want: true},
		{name: "localhost", origin: "http://localhost:17890", want: true},
		{name: "ipv6 loopback", origin: "http://[::1]:17890", want: true},
		{name: "remote website", origin: "https://example.com", want: false},
		{name: "invalid", origin: "://bad", want: false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := httptest.NewRequest("GET", "http://127.0.0.1/v1/pty", nil)
			if tt.origin != "" {
				r.Header.Set("Origin", tt.origin)
			}
			if got := allowLocalWSOrigin(r); got != tt.want {
				t.Fatalf("allowLocalWSOrigin() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestClampInt(t *testing.T) {
	for _, tt := range []struct{ value, min, max, want int }{
		{1, 20, 500, 20},
		{80, 20, 500, 80},
		{900, 20, 500, 500},
	} {
		if got := clampInt(tt.value, tt.min, tt.max); got != tt.want {
			t.Fatalf("clampInt(%d) = %d, want %d", tt.value, got, tt.want)
		}
	}
}
