package risk

import (
	"path"
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

func wordArguments(words []*syntax.Word) []argument {
	args := make([]argument, 0, len(words))
	for _, word := range words {
		text, ok := literalWord(word)
		args = append(args, argument{text: text, static: ok})
	}
	return args
}

func literalWord(word *syntax.Word) (string, bool) {
	if word == nil {
		return "", false
	}
	return literalParts(word.Parts)
}

func literalParts(parts []syntax.WordPart) (string, bool) {
	var value strings.Builder
	for _, part := range parts {
		switch part := part.(type) {
		case *syntax.Lit:
			value.WriteString(part.Value)
		case *syntax.SglQuoted:
			value.WriteString(part.Value)
		case *syntax.DblQuoted:
			quoted, ok := literalParts(part.Parts)
			if !ok {
				return "", false
			}
			value.WriteString(quoted)
		default:
			return "", false
		}
	}
	return value.String(), true
}

func unwrapCommand(fields []argument) []argument {
	for len(fields) > 0 {
		if !fields[0].static {
			return fields
		}
		command := baseName(fields[0].text)
		switch command {
		case "builtin", "command", "nohup", "time":
			fields = skipOptions(fields[1:], nil)
		case "env":
			fields = skipOptions(fields[1:], stringSet("-u", "--unset", "-c", "--chdir"))
			for len(fields) > 0 && fields[0].static && isAssignment(fields[0].text) {
				fields = fields[1:]
			}
		case "sudo":
			fields = skipOptions(fields[1:], stringSet(
				"-c", "--close-from", "-d", "--chdir", "-g", "--group", "-h", "--host",
				"-p", "--prompt", "-r", "--chroot", "-t", "--command-timeout", "-u", "--user",
			))
		default:
			return fields
		}
	}
	return fields
}

func skipOptions(fields []argument, optionsWithValues map[string]bool) []argument {
	for len(fields) > 0 {
		if !fields[0].static {
			return fields
		}
		option := strings.ToLower(strings.TrimSpace(fields[0].text))
		if option == "--" {
			return fields[1:]
		}
		if !strings.HasPrefix(option, "-") || option == "-" {
			return fields
		}

		fields = fields[1:]
		name := option
		if before, _, found := strings.Cut(name, "="); found {
			name = before
			continue
		}
		if optionsWithValues[name] && len(fields) > 0 {
			fields = fields[1:]
		}
	}
	return fields
}

func shellCommandString(args []argument) (argument, bool) {
	for i, arg := range args {
		if !arg.static {
			return argument{}, false
		}
		option := arg.text
		if option == "--" {
			return argument{}, false
		}
		if option == "-c" || (strings.HasPrefix(option, "-") && !strings.HasPrefix(option, "--") && strings.ContainsRune(option[1:], 'c')) {
			if i+1 < len(args) {
				return args[i+1], true
			}
			return argument{}, true
		}
	}
	return argument{}, false
}

func joinStaticArgs(args []argument) (string, bool) {
	values := make([]string, 0, len(args))
	for _, arg := range args {
		if !arg.static {
			return "", false
		}
		values = append(values, arg.text)
	}
	return strings.Join(values, " "), true
}

func firstNonOption(args []argument) string {
	for _, arg := range args {
		if !arg.static {
			continue
		}
		value := strings.ToLower(strings.TrimSpace(arg.text))
		if value != "" && !strings.HasPrefix(value, "-") {
			return value
		}
	}
	return ""
}

func equalArg(arg argument, want string) bool {
	return arg.static && strings.EqualFold(strings.TrimSpace(arg.text), want)
}

func hasArg(args []argument, want string) bool {
	for _, arg := range args {
		if equalArg(arg, want) {
			return true
		}
	}
	return false
}

func hasAnyArg(args []argument, wants ...string) bool {
	for _, want := range wants {
		if hasArg(args, want) {
			return true
		}
	}
	return false
}

func hasArgPrefix(args []argument, prefix string) bool {
	for _, arg := range args {
		if arg.static && strings.HasPrefix(strings.ToLower(strings.TrimSpace(arg.text)), strings.ToLower(prefix)) {
			return true
		}
	}
	return false
}

func hasShortFlag(args []argument, want rune) bool {
	for _, arg := range args {
		if !arg.static {
			continue
		}
		value := strings.TrimSpace(arg.text)
		if strings.HasPrefix(value, "-") && !strings.HasPrefix(value, "--") && strings.ContainsRune(value[1:], want) {
			return true
		}
	}
	return false
}

func baseName(command string) string {
	return strings.ToLower(path.Base(strings.TrimSpace(command)))
}

func isAssignment(value string) bool {
	name, _, ok := strings.Cut(value, "=")
	if !ok || name == "" {
		return false
	}
	for i, r := range name {
		if !(r == '_' || r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || i > 0 && r >= '0' && r <= '9') {
			return false
		}
	}
	return true
}

func allDigits(value string) bool {
	if value == "" {
		return false
	}
	for _, r := range value {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

func hasAnyString(value string, candidates ...string) bool {
	for _, candidate := range candidates {
		if value == candidate {
			return true
		}
	}
	return false
}

func stringSet(values ...string) map[string]bool {
	set := make(map[string]bool, len(values))
	for _, value := range values {
		set[value] = true
	}
	return set
}
