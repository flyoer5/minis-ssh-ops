package sshx

import "testing"

func TestPoolKeySeparatesAuthenticationSecrets(t *testing.T) {
	base := ConnectParams{Host: "example.com", Port: 22, Username: "root", Password: "aaaa"}
	baseKey := poolKey(base)

	tests := []struct {
		name string
		edit func(*ConnectParams)
	}{
		{name: "same-length password", edit: func(p *ConnectParams) { p.Password = "bbbb" }},
		{name: "private key", edit: func(p *ConnectParams) { p.Password = ""; p.PrivateKeyPEM = "key-a" }},
		{name: "same-length private key", edit: func(p *ConnectParams) { p.Password = ""; p.PrivateKeyPEM = "key-b" }},
		{name: "passphrase", edit: func(p *ConnectParams) { p.PrivateKeyPEM = "key"; p.Passphrase = "secret" }},
	}

	keys := map[string]string{"base": baseKey}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := base
			tt.edit(&p)
			got := poolKey(p)
			if previous, exists := keys[got]; exists {
				t.Fatalf("pool key collided with %s", previous)
			}
			keys[got] = tt.name
		})
	}
}

func TestPoolKeyNormalizesDefaultPort(t *testing.T) {
	p := ConnectParams{Host: "example.com", Username: "root", Password: "secret"}
	withDefault := p
	withDefault.Port = 22
	if poolKey(p) != poolKey(withDefault) {
		t.Fatal("port 0 and port 22 should share a pool key")
	}
}
