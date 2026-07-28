package api

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestWithAuthRequiresHeaderToken(t *testing.T) {
	s := &Server{LocalToken: "secret"}
	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})
	h := s.withAuth(next)

	tests := []struct {
		name   string
		path   string
		header string
		want   int
	}{
		{name: "header accepted", path: "/v1/hosts", header: "secret", want: http.StatusNoContent},
		{name: "missing rejected", path: "/v1/hosts", want: http.StatusUnauthorized},
		{name: "query rejected", path: "/v1/hosts?token=secret", want: http.StatusUnauthorized},
		{name: "wrong header rejected", path: "/v1/hosts", header: "wrong", want: http.StatusUnauthorized},
		{name: "health remains public", path: "/v1/health", want: http.StatusNoContent},
		{name: "pty self authenticates", path: "/v1/hosts/id/pty?token=secret", want: http.StatusNoContent},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodGet, tt.path, nil)
			if tt.header != "" {
				r.Header.Set("X-Local-Token", tt.header)
			}
			w := httptest.NewRecorder()
			h.ServeHTTP(w, r)
			if w.Code != tt.want {
				t.Fatalf("status = %d, want %d", w.Code, tt.want)
			}
		})
	}
}
