package risk

import (
	"path"
	"regexp"
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

var blockDeviceRE = regexp.MustCompile(`^/dev/(?:[shv]d[a-z][0-9]*|xvd[a-z][0-9]*|nvme[0-9]+n[0-9]+(?:p[0-9]+)?|mmcblk[0-9]+(?:p[0-9]+)?|md[0-9]+|loop[0-9]+|dm-[0-9]+)$`)

var readCommands = stringSet(
	"[", "alias", "apropos", "arch", "basename", "cat", "cksum", "column",
	"comm", "cut", "df", "diff", "dig", "dirname", "du", "echo", "false",
	"file", "free", "getent", "grep", "head", "id", "jq", "last", "less",
	"ls", "lsof", "md5sum", "netstat",
	"nproc", "ping", "printenv", "printf", "ps", "pwd", "readlink", "realpath",
	"sha1sum", "sha224sum", "sha256sum", "sha384sum", "sha512sum", "sleep", "sort",
	"ss", "stat", "strings", "tail", "test", "top", "tr", "tree", "true",
	"uname", "uniq", "uptime", "wc", "which", "who", "whoami",
)

var writeCommands = stringSet(
	"addgroup", "adduser", "chgrp", "chmod", "chown", "chpasswd", "cp", "groupadd",
	"install", "kill", "killall", "ln", "mkdir", "mount", "mv", "passwd", "pkill",
	"swapoff", "swapon", "tee", "touch", "umount", "useradd",
)

var destructiveCommands = stringSet(
	"blkdiscard", "cfdisk", "dd", "delgroup", "deluser", "fdisk", "groupdel", "halt",
	"mkfs", "mkswap", "parted", "poweroff", "reboot", "rm", "rmdir", "sfdisk",
	"shutdown", "shred", "truncate", "unlink", "userdel", "wipefs",
)

var shellCommands = stringSet("ash", "bash", "dash", "ksh", "sh", "zsh")

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

func classifyRedirect(redir *syntax.Redirect) Level {
	switch redir.Op {
	case syntax.RdrOut, syntax.AppOut, syntax.RdrInOut, syntax.ClbOut, syntax.RdrAll, syntax.AppAll:
		target, ok := literalWord(redir.Word)
		if !ok {
			return Write
		}
		if isBlockDevicePath(target) {
			return Blocked
		}
		if isNonPersistentOutput(target) {
			return Read
		}
		return Write
	case syntax.DplOut:
		target, ok := literalWord(redir.Word)
		if !ok {
			return Write
		}
		if target == "-" || allDigits(target) {
			return Read
		}
		if isBlockDevicePath(target) {
			return Blocked
		}
		if isNonPersistentOutput(target) {
			return Read
		}
		return Write
	default:
		return Read
	}
}

func classifySystemctl(args []argument) Level {
	sub := firstNonOption(args)
	switch sub {
	case "halt", "hibernate", "hybrid-sleep", "kexec", "poweroff", "reboot", "suspend":
		return Destructive
	case "cat", "is-active", "is-enabled", "is-failed", "list-dependencies", "list-jobs",
		"list-sockets", "list-timers", "list-unit-files", "list-units", "show", "status":
		return Read
	default:
		return Write
	}
}

func classifyPackage(args []argument) Level {
	sub := firstNonOption(args)
	switch sub {
	case "autoremove", "erase", "purge", "remove", "uninstall":
		return Destructive
	case "check", "depends", "info", "list", "policy", "search", "show":
		return Read
	default:
		return Write
	}
}

func classifyGit(args []argument) Level {
	sub := firstNonOption(args)
	if sub == "clean" && (hasArg(args, "--force") || hasShortFlag(args, 'f')) {
		return Destructive
	}
	if sub == "reset" && hasArg(args, "--hard") {
		return Destructive
	}
	switch sub {
	case "blame", "describe", "diff", "grep", "log", "ls-files", "ls-tree", "rev-parse", "shortlog", "show", "status":
		return Read
	default:
		return Write
	}
}

func classifyContainer(args []argument) Level {
	sub := firstNonOption(args)
	if sub == "system" && hasArg(args, "prune") {
		return Destructive
	}
	switch sub {
	case "container", "image", "network", "volume":
		if hasAnyArg(args, "prune", "rm") {
			return Destructive
		}
		return Write
	case "prune", "rm", "rmi":
		return Destructive
	case "images", "info", "inspect", "logs", "port", "ps", "search", "stats", "top", "version":
		return Read
	default:
		return Write
	}
}

func classifyKubectl(args []argument) Level {
	sub := firstNonOption(args)
	if sub == "delete" {
		return Destructive
	}
	switch sub {
	case "api-resources", "api-versions", "cluster-info", "describe", "explain", "get", "logs", "top", "version":
		return Read
	default:
		return Write
	}
}

func isRemoteShellPipeline(binary *syntax.BinaryCmd) bool {
	if binary.Op != syntax.Pipe && binary.Op != syntax.PipeAll {
		return false
	}

	var stages []*syntax.Stmt
	flattenPipeline(binary.X, &stages)
	flattenPipeline(binary.Y, &stages)
	downloadSeen := false
	for _, stage := range stages {
		call := simpleCall(stage)
		if call == nil {
			continue
		}
		fields := unwrapCommand(wordArguments(call.Args))
		if len(fields) == 0 || !fields[0].static {
			continue
		}
		command := baseName(fields[0].text)
		if command == "curl" || command == "wget" {
			downloadSeen = true
			continue
		}
		if downloadSeen && shellCommands[command] {
			return true
		}
	}
	return false
}

func flattenPipeline(stmt *syntax.Stmt, stages *[]*syntax.Stmt) {
	if binary, ok := stmt.Cmd.(*syntax.BinaryCmd); ok && (binary.Op == syntax.Pipe || binary.Op == syntax.PipeAll) {
		flattenPipeline(binary.X, stages)
		flattenPipeline(binary.Y, stages)
		return
	}
	*stages = append(*stages, stmt)
}

func simpleCall(stmt *syntax.Stmt) *syntax.CallExpr {
	switch command := stmt.Cmd.(type) {
	case *syntax.CallExpr:
		return command
	case *syntax.Subshell:
		if len(command.Stmts) == 1 {
			return simpleCall(command.Stmts[0])
		}
	case *syntax.Block:
		if len(command.Stmts) == 1 {
			return simpleCall(command.Stmts[0])
		}
	}
	return nil
}

func isForcedRecursiveRootRemove(args []argument) bool {
	recursive := false
	force := false
	rootTarget := false
	options := true
	for _, arg := range args {
		if !arg.static {
			continue
		}
		value := strings.TrimSpace(arg.text)
		if options && value == "--" {
			options = false
			continue
		}
		if options && strings.HasPrefix(value, "--") {
			recursive = recursive || value == "--recursive"
			force = force || value == "--force"
			continue
		}
		if options && strings.HasPrefix(value, "-") && value != "-" {
			flags := strings.TrimLeft(value, "-")
			recursive = recursive || strings.ContainsAny(flags, "rR")
			force = force || strings.ContainsRune(flags, 'f')
			continue
		}
		rootTarget = rootTarget || isRootTarget(value)
	}
	return recursive && force && rootTarget
}

func isRootTarget(target string) bool {
	if target == "" || target[0] != '/' {
		return false
	}
	cleaned := path.Clean(target)
	return cleaned == "/" || cleaned == "/*"
}

func isBlockDeviceOperation(command string, args []argument) bool {
	if strings.HasPrefix(command, "mkfs.") || hasAnyString(command, "mkfs", "mkswap", "wipefs", "shred", "blkdiscard") {
		return anyBlockDeviceArg(args)
	}
	if hasAnyString(command, "tee", "truncate") {
		return anyBlockDeviceArg(args)
	}
	if hasAnyString(command, "cp", "install", "mv") && len(args) > 0 {
		target := args[len(args)-1]
		return target.static && isBlockDevicePath(target.text)
	}
	if command == "cryptsetup" && hasArg(args, "luksformat") {
		return anyBlockDeviceArg(args)
	}
	if command == "badblocks" && hasShortFlag(args, 'w') {
		return anyBlockDeviceArg(args)
	}
	if command == "dd" {
		for _, arg := range args {
			if !arg.static {
				continue
			}
			key, value, ok := strings.Cut(arg.text, "=")
			if ok && strings.EqualFold(strings.TrimSpace(key), "of") && isBlockDevicePath(value) {
				return true
			}
		}
	}
	return false
}

func anyBlockDeviceArg(args []argument) bool {
	for _, arg := range args {
		if arg.static && isBlockDevicePath(arg.text) {
			return true
		}
	}
	return false
}

func isBlockDevicePath(target string) bool {
	target = path.Clean(strings.TrimSpace(target))
	return blockDeviceRE.MatchString(target) ||
		strings.HasPrefix(target, "/dev/mapper/") ||
		strings.HasPrefix(target, "/dev/disk/") ||
		strings.HasPrefix(target, "/dev/block/")
}

func isNonPersistentOutput(target string) bool {
	target = path.Clean(strings.TrimSpace(target))
	return target == "/dev/null" || target == "/dev/stdout" || target == "/dev/stderr" ||
		strings.HasPrefix(target, "/dev/fd/") || strings.HasPrefix(target, "/proc/self/fd/")
}

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

func rank(level Level) int {
	switch level {
	case Read:
		return 0
	case Write:
		return 1
	case Destructive:
		return 2
	case Blocked:
		return 3
	default:
		return -1
	}
}

func Max(a, b Level) Level {
	if rank(b) > rank(a) {
		return b
	}
	return a
}

func NeedsConfirm(level Level) bool {
	return level == Write || level == Destructive
}
