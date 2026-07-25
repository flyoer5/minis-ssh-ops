package risk

// Risk levels are retained for API/UI compatibility only.
// Policy: no command is blocked or gated — the user owns the hosts.
type Level string

const (
	Read        Level = "read"
	Write       Level = "write"
	Destructive Level = "destructive"
	Blocked     Level = "blocked"
)

// Classify always returns Read. Historical write/destructive/blocked patterns
// were removed so run_command is never refused or forced through NEEDS_CONFIRM.
func Classify(cmd string) Level {
	_ = cmd
	return Read
}

func NeedsConfirm(l Level) bool {
	_ = l
	return false
}
