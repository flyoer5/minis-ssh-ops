package api

import "github.com/flyoer5/ssh-ai-agent/backend/internal/sshx"

func (s *Server) connectParams(hostID string) (sshx.ConnectParams, error) {
	h, err := s.Store.GetHost(hostID)
	if err != nil {
		return sshx.ConnectParams{}, err
	}
	sec, err := s.Store.GetHostSecrets(hostID)
	if err != nil {
		return sshx.ConnectParams{}, err
	}
	return sshx.ConnectParams{
		Host:          h.Host,
		Port:          h.Port,
		Username:      h.Username,
		Password:      sec.Password,
		PrivateKeyPEM: sec.PrivateKeyPEM,
		Passphrase:    sec.Passphrase,
		HostKeys:      s.HostKeys,
	}, nil
}
