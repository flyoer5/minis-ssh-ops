package agent

import (
	"net/http"
	"testing"
	"time"
)

func TestNewClientHasDedicatedReusableStreamTransport(t *testing.T) {
	client := NewClient("http://example.com/v1", "", "model")
	defer client.Close()
	if client.HTTP == nil || client.StreamHTTP == nil {
		t.Fatal("both regular and stream HTTP clients are required")
	}
	if client.HTTP == client.StreamHTTP {
		t.Fatal("stream client must not inherit the regular overall timeout")
	}
	if client.HTTP.Timeout != 120*time.Second {
		t.Fatalf("regular timeout = %v", client.HTTP.Timeout)
	}
	if client.StreamHTTP.Timeout != 0 {
		t.Fatalf("stream timeout = %v, want 0", client.StreamHTTP.Timeout)
	}
	regularTransport, ok := client.HTTP.Transport.(*http.Transport)
	if !ok {
		t.Fatalf("regular transport type = %T", client.HTTP.Transport)
	}
	streamTransport, ok := client.StreamHTTP.Transport.(*http.Transport)
	if !ok {
		t.Fatalf("stream transport type = %T", client.StreamHTTP.Transport)
	}
	if regularTransport == streamTransport {
		t.Fatal("regular and stream clients unexpectedly share one transport")
	}
	if streamTransport.ResponseHeaderTimeout != 120*time.Second {
		t.Fatalf("stream header timeout = %v", streamTransport.ResponseHeaderTimeout)
	}
}
