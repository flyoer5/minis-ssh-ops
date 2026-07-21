package agent

import (
	"regexp"
	"strings"
)

// Risk levels: read | write | destructive | blocked
type Risk string

const (
	RiskRead         Risk = "read"
	RiskWrite        Risk = "write"
	RiskDestructive  Risk = "destructive"
	RiskBlocked      Risk = "blocked"
)

var blockedPatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+)?/\s*$`),
	regexp.MustCompile(`(?i)rm\s+-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*.*/\s*($|;)`),
	regexp.MustCompile(`(?i)rm\s+-rf\s+/($|\s)`),
	regexp.MustCompile(`(?i)mkfs(\.|$|\s)`),
	regexp.MustCompile(`(?i)dd\s+.*of=/dev/`),
	regexp.MustCompile(`(?i)>\s*/dev/sd[a-z]`),
	regexp.MustCompile(`(?i)curl\s+.*\|\s*(ba)?sh`),
	regexp.MustCompile(`(?i)wget\s+.*\|\s*(ba)?sh`),
	regexp.MustCompile(`(?i):(){ :\|:& };:`), // fork bomb
	regexp.MustCompile(`(?i)chmod\s+-R\s+777\s+/`),
	regexp.MustCompile(`(?i)shutdown(\s|$)`),
	regexp.MustCompile(`(?i)reboot(\s|$)`),
	regexp.MustCompile(`(?i)init\s+0`),
	regexp.MustCompile(`(?i)mkfs\.`),
	regexp.MustCompile(`(?i)wipefs`),
	regexp.MustCompile(`(?i)userdel\s+-r\s+root`),
}

var destructivePatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)\brm\s+`),
	regexp.MustCompile(`(?i)\btruncate\b`),
	regexp.MustCompile(`(?i)\bdrop\s+table\b`),
	regexp.MustCompile(`(?i)\bmkfs\b`),
	regexp.MustCompile(`(?i)\bfdisk\b`),
	regexp.MustCompile(`(?i)\bparted\b`),
	regexp.MustCompile(`(?i)\biptables\s+-F\b`),
	regexp.MustCompile(`(?i)\bsystemctl\s+(stop|disable|mask)\b`),
	regexp.MustCompile(`(?i)\bkill\s+-9\b`),
	regexp.MustCompile(`(?i)\bpkill\b`),
	regexp.MustCompile(`(?i)\bchmod\b`),
	regexp.MustCompile(`(?i)\bchown\b`),
	regexp.MustCompile(`(?i)\bpasswd\b`),
	regexp.MustCompile(`(?i)\buseradd\b`),
	regexp.MustCompile(`(?i)\buserdel\b`),
}

var writePatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)\b(apt|yum|dnf|apk|pacman)\s+(install|add|remove|del)`),
	regexp.MustCompile(`(?i)\bpip[3]?\s+install\b`),
	regexp.MustCompile(`(?i)\bnpm\s+install\b`),
	regexp.MustCompile(`(?i)\bsystemctl\s+(start|restart|reload|enable)\b`),
	regexp.MustCompile(`(?i)\bservice\s+\S+\s+(start|restart|stop)\b`),
	regexp.MustCompile(`(?i)\bmv\s+`),
	regexp.MustCompile(`(?i)\bcp\s+`),
	regexp.MustCompile(`(?i)\btouch\s+`),
	regexp.MustCompile(`(?i)\bmkdir\s+`),
	regexp.MustCompile(`(?i)\bsed\s+-i\b`),
	regexp.MustCompile(`(?i)\btee\b`),
	// shell redirects to real files (after stripDevNull)
	regexp.MustCompile(`(?i)>{1,2}\s*\S+`),
	regexp.MustCompile(`(?i)\bdocker\s+(run|rm|stop|start)`),
	regexp.MustCompile(`(?i)\bcrontab\b`),
}

// stripDevNull removes common noise redirects so they don't count as writes.
var devNullRe = regexp.MustCompile(`(?i)\d*>\s*/dev/null`)

func stripDevNull(c string) string {
	return strings.TrimSpace(devNullRe.ReplaceAllString(c, " "))
}

// Classify returns risk level for a shell command string.
func Classify(cmd string) Risk {
	c := strings.TrimSpace(cmd)
	if c == "" {
		return RiskRead
	}
	// multi-command: take highest risk of segments
	parts := splitCommands(c)
	highest := RiskRead
	for _, p := range parts {
		r := classifyOne(p)
		if riskRank(r) > riskRank(highest) {
			highest = r
		}
	}
	return highest
}

func classifyOne(c string) Risk {
	c = stripDevNull(c)
	for _, re := range blockedPatterns {
		if re.MatchString(c) {
			return RiskBlocked
		}
	}
	for _, re := range destructivePatterns {
		if re.MatchString(c) {
			return RiskDestructive
		}
	}
	for _, re := range writePatterns {
		if re.MatchString(c) {
			return RiskWrite
		}
	}
	return RiskRead
}

func riskRank(r Risk) int {
	switch r {
	case RiskRead:
		return 1
	case RiskWrite:
		return 2
	case RiskDestructive:
		return 3
	case RiskBlocked:
		return 4
	default:
		return 0
	}
}

func splitCommands(c string) []string {
	// rough split on ; && || \n — good enough for risk gate
	re := regexp.MustCompile(`\s*(?:&&|\|\||;|\n)\s*`)
	return re.Split(c, -1)
}

// NeedsConfirm reports whether UI must ask user before run.
func NeedsConfirm(r Risk) bool {
	return r == RiskWrite || r == RiskDestructive
}

// AllowedToAutoRun is true only for read-only probes.
func AllowedToAutoRun(r Risk) bool {
	return r == RiskRead
}
