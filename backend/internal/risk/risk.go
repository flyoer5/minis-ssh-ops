package risk

import (
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

type Level string

const (
	Read        Level = "read"
	Write       Level = "write"
	Destructive Level = "destructive"
	Blocked     Level = "blocked"
)

const maxNestedShellDepth = 4

type argument struct {
	text   string
	static bool
}

type commandClassifier struct {
	depth int
	level Level
}

// Classify parses shell syntax and returns the highest risk from commands,
// substitutions, pipelines, and redirects. Invalid or dynamic commands default
// to Write because their effects cannot be established without execution.
func Classify(command string) Level {
	return classify(command, 0)
}

func classify(command string, depth int) Level {
	if strings.TrimSpace(command) == "" {
		return Read
	}
	if depth > maxNestedShellDepth {
		return Write
	}

	file, err := syntax.NewParser(syntax.Variant(syntax.LangBash)).Parse(strings.NewReader(command), "")
	if err != nil {
		return Write
	}

	c := commandClassifier{depth: depth, level: Read}
	syntax.Walk(file, func(node syntax.Node) bool {
		switch node := node.(type) {
		case *syntax.Redirect:
			c.raise(classifyRedirect(node))
		case *syntax.CallExpr:
			c.raise(classifyCall(node, depth))
		case *syntax.BinaryCmd:
			if isRemoteShellPipeline(node) {
				c.raise(Blocked)
			}
		case *syntax.FuncDecl:
			// The canonical fork bomb redefines ':' and recursively backgrounds it.
			if node.Name != nil && node.Name.Value == ":" {
				c.raise(Blocked)
			}
		}
		return true
	})
	return c.level
}

func (c *commandClassifier) raise(level Level) {
	c.level = Max(c.level, level)
}

func classifyCall(call *syntax.CallExpr, depth int) Level {
	fields := wordArguments(call.Args)
	if len(fields) == 0 {
		return Read
	}

	if fields[0].static && baseName(fields[0].text) == "command" && hasAnyArg(fields[1:], "-v", "-V") {
		return Read
	}
	fields = unwrapCommand(fields)
	if len(fields) == 0 {
		return Read
	}
	if !fields[0].static || strings.TrimSpace(fields[0].text) == "" {
		return Write
	}

	command := baseName(fields[0].text)
	args := fields[1:]

	if shellCommands[command] {
		if script, ok := shellCommandString(args); ok {
			if !script.static {
				return Write
			}
			return classify(script.text, depth+1)
		}
		return Write
	}
	if command == "eval" {
		script, ok := joinStaticArgs(args)
		if !ok {
			return Write
		}
		return classify(script, depth+1)
	}

	if command == "rm" && isForcedRecursiveRootRemove(args) {
		return Blocked
	}
	if isBlockDeviceOperation(command, args) {
		return Blocked
	}

	if strings.HasPrefix(command, "mkfs.") || destructiveCommands[command] {
		return Destructive
	}
	if writeCommands[command] {
		return Write
	}
	if readCommands[command] {
		return Read
	}

	switch command {
	case "date":
		if hasAnyArg(args, "-s", "--set") || hasArgPrefix(args, "--set=") {
			return Write
		}
		return Read
	case "dmesg":
		if hasAnyArg(args, "-c", "--read-clear", "-C", "--clear") {
			return Destructive
		}
		return Read
	case "find":
		if hasArg(args, "-delete") {
			return Destructive
		}
		if hasAnyArg(args, "-exec", "-execdir", "-ok", "-okdir") {
			return Write
		}
		return Read
	case "sed":
		if hasArgPrefix(args, "-i") || hasArg(args, "--in-place") {
			return Write
		}
		return Read
	case "curl":
		if hasAnyArg(args, "-o", "--output") || hasArgPrefix(args, "--output=") {
			return Write
		}
		return Read
	case "wget":
		if hasArg(args, "--spider") {
			return Read
		}
		return Write
	case "ip":
		if hasAnyArg(args, "add", "delete", "del", "flush", "replace", "set") {
			return Write
		}
		return Read
	case "hostname":
		if firstNonOption(args) != "" {
			return Write
		}
		return Read
	case "journalctl":
		if hasAnyArg(args, "--rotate", "--sync", "--flush", "--relinquish-var", "--smart-relinquish-var") ||
			hasArgPrefix(args, "--vacuum-") {
			return Destructive
		}
		return Read
	case "sysctl":
		if hasAnyArg(args, "-w", "--write") {
			return Write
		}
		return Read
	case "systemctl":
		return classifySystemctl(args)
	case "service":
		if len(args) > 1 && equalArg(args[1], "status") {
			return Read
		}
		return Write
	case "apt", "apt-get", "apk", "dnf", "pacman", "yum", "zypper":
		return classifyPackage(args)
	case "git":
		return classifyGit(args)
	case "docker", "podman":
		return classifyContainer(args)
	case "kubectl":
		return classifyKubectl(args)
	case "tar":
		if hasAnyArg(args, "-t", "--list") || hasShortFlag(args, 't') {
			return Read
		}
		return Write
	default:
		return Write
	}
}
