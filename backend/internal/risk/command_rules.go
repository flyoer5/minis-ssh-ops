package risk

import "mvdan.cc/sh/v3/syntax"

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
