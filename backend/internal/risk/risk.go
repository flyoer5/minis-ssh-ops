package risk

import (
	"regexp"
	"strings"
)

type Level string

const (
	Read         Level = "read"
	Write        Level = "write"
	Destructive  Level = "destructive"
	Blocked      Level = "blocked"
)

var blockedPatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)rm\s+-rf\s+/($|\s)`),
	regexp.MustCompile(`(?i)mkfs(\.|$|\s)`),
	regexp.MustCompile(`(?i)dd\s+.*of=/dev/`),
	regexp.MustCompile(`(?i)curl\s+.*\|\s*(ba)?sh`),
	regexp.MustCompile(`(?i)wget\s+.*\|\s*(ba)?sh`),
	regexp.MustCompile(`(?i)shutdown(\s|$)`),
	regexp.MustCompile(`(?i)\breboot\b`),
	regexp.MustCompile(`(?i)wipefs`),
	regexp.MustCompile(`(?i):(){ :\|:& };:`),
}

var destructivePatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)\brm\s+`),
	regexp.MustCompile(`(?i)\btruncate\b`),
	regexp.MustCompile(`(?i)\bsystemctl\s+(stop|disable|mask)\b`),
	regexp.MustCompile(`(?i)\bkill\s+-9\b`),
	regexp.MustCompile(`(?i)\bmkfs\b`),
	regexp.MustCompile(`(?i)\bfdisk\b`),
	regexp.MustCompile(`(?i)\bchmod\b`),
	regexp.MustCompile(`(?i)\bchown\b`),
	regexp.MustCompile(`(?i)\buserdel\b`),
}

var writePatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)\b(apt|yum|dnf|apk|pacman)\s+(install|add|remove|del)`),
	regexp.MustCompile(`(?i)\bpip[3]?\s+install\b`),
	regexp.MustCompile(`(?i)\bsystemctl\s+(start|restart|reload|enable)\b`),
	regexp.MustCompile(`(?i)\bmv\s+`),
	regexp.MustCompile(`(?i)\bcp\s+`),
	regexp.MustCompile(`(?i)\btouch\s+`),
	regexp.MustCompile(`(?i)\bmkdir\s+`),
	regexp.MustCompile(`(?i)\bsed\s+-i\b`),
	regexp.MustCompile(`(?i)\btee\b`),
	regexp.MustCompile(`(?i)>{1,2}\s*\S+`),
	regexp.MustCompile(`(?i)\bdocker\s+(run|rm|stop|start)`),
}

var devNullRe = regexp.MustCompile(`(?i)\d*>\s*/dev/null`)
var splitRe = regexp.MustCompile(`\s*(?:&&|\|\||;|\n)\s*`)

func Classify(cmd string) Level {
	c := strings.TrimSpace(cmd)
	if c == "" {
		return Read
	}
	highest := Read
	for _, p := range splitRe.Split(c, -1) {
		r := classifyOne(p)
		if rank(r) > rank(highest) {
			highest = r
		}
	}
	return highest
}

func classifyOne(c string) Level {
	c = strings.TrimSpace(devNullRe.ReplaceAllString(c, " "))
	for _, re := range blockedPatterns {
		if re.MatchString(c) {
			return Blocked
		}
	}
	for _, re := range destructivePatterns {
		if re.MatchString(c) {
			return Destructive
		}
	}
	for _, re := range writePatterns {
		if re.MatchString(c) {
			return Write
		}
	}
	return Read
}

func rank(l Level) int {
	switch l {
	case Read:
		return 1
	case Write:
		return 2
	case Destructive:
		return 3
	case Blocked:
		return 4
	default:
		return 0
	}
}

func NeedsConfirm(l Level) bool {
	return l == Write || l == Destructive
}
