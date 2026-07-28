package risk

import (
	"path"
	"regexp"
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

var blockDeviceRE = regexp.MustCompile(`^/dev/(?:[shv]d[a-z][0-9]*|xvd[a-z][0-9]*|nvme[0-9]+n[0-9]+(?:p[0-9]+)?|mmcblk[0-9]+(?:p[0-9]+)?|md[0-9]+|loop[0-9]+|dm-[0-9]+)$`)

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
