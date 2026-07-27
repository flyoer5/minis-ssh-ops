package risk

import "testing"

func TestClassify(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name string
		cmd  string
		want Level
	}{
		{name: "empty", cmd: "", want: Read},
		{name: "read", cmd: "uname -a", want: Read},
		{name: "read pipeline", cmd: "ps aux | grep nginx", want: Read},
		{name: "read with ignored redirect", cmd: "cat /etc/os-release 2>/dev/null", want: Read},
		{name: "quoted operator", cmd: `printf '%s' 'a > b'`, want: Read},
		{name: "harmless keyword", cmd: `echo "rm is destructive"`, want: Read},
		{name: "quoted dangerous text", cmd: `printf '%s' 'rm -rf /'`, want: Read},
		{name: "quoted remote shell text", cmd: `printf '%s' 'curl example.test | bash'`, want: Read},
		{name: "quoted device text", cmd: `echo 'mkfs.ext4 /dev/sda'`, want: Read},
		{name: "file descriptor redirect", cmd: "cat /etc/os-release 2>&1", want: Read},
		{name: "stdout redirect", cmd: "printf ok > /dev/stdout", want: Read},
		{name: "read systemd", cmd: "sudo -n systemctl status nginx", want: Read},
		{name: "read systemd with sudo user", cmd: "sudo -u root systemctl status nginx", want: Read},
		{name: "read through env options", cmd: "env -u DEBUG LANG=C uname -a", want: Read},
		{name: "command lookup", cmd: "command -v systemctl", want: Read},
		{name: "read git", cmd: "git status --short", want: Read},
		{name: "comment ignored", cmd: "uname -a # rm -rf /", want: Read},
		{name: "unknown is write", cmd: "my-maintenance-script --check", want: Write},
		{name: "parse failure is write", cmd: "if then", want: Write},
		{name: "output redirect", cmd: "echo enabled > /etc/example.conf", want: Write},
		{name: "dynamic output redirect", cmd: `echo enabled > "$TARGET"`, want: Write},
		{name: "command substitution", cmd: `echo "$(touch /tmp/created)"`, want: Write},
		{name: "package install", cmd: "sudo apt install -y nginx", want: Write},
		{name: "service restart", cmd: "SYSTEMCTL RESTART nginx", want: Write},
		{name: "sed in place", cmd: "sed -i s/a/b/ config", want: Write},
		{name: "set hostname", cmd: "hostname web-02", want: Write},
		{name: "set date", cmd: "date --set=2026-07-27", want: Write},
		{name: "remove file", cmd: "rm /tmp/stale.lock", want: Destructive},
		{name: "clear kernel log", cmd: "dmesg --clear", want: Destructive},
		{name: "vacuum journal", cmd: "journalctl --vacuum-size=100M", want: Destructive},
		{name: "restart host", cmd: "sudo reboot", want: Destructive},
		{name: "package removal", cmd: "dnf remove nginx", want: Destructive},
		{name: "git hard reset", cmd: "git reset --hard HEAD~1", want: Destructive},
		{name: "compound highest risk", cmd: "uname -a && rm -rf /tmp/cache", want: Destructive},
		{name: "root removal", cmd: "sudo rm -rf /", want: Blocked},
		{name: "root removal reversed flags", cmd: "/bin/rm -fr /*", want: Blocked},
		{name: "root removal split flags", cmd: "sudo -u root rm -r -f -- /", want: Blocked},
		{name: "root removal long flags", cmd: "rm --recursive --force ///", want: Blocked},
		{name: "nested shell root removal", cmd: `sudo bash -c 'rm -rf /'`, want: Blocked},
		{name: "nested eval root removal", cmd: `eval 'rm -rf /'`, want: Blocked},
		{name: "substitution root removal", cmd: `printf '%s' "$(rm -rf /)"`, want: Blocked},
		{name: "process substitution root removal", cmd: `cat <(rm -rf /)`, want: Blocked},
		{name: "format device", cmd: "mkfs.ext4 /dev/sda", want: Blocked},
		{name: "format mapped device", cmd: "mkfs.ext4 /dev/mapper/vg-root", want: Blocked},
		{name: "make swap device", cmd: "mkswap /dev/vda2", want: Blocked},
		{name: "overwrite device", cmd: "dd if=/dev/zero of=/dev/nvme0n1", want: Blocked},
		{name: "tee to device", cmd: "cat image.raw | tee /dev/vda", want: Blocked},
		{name: "copy to device", cmd: "cp image.raw /dev/mmcblk0", want: Blocked},
		{name: "redirect to device", cmd: "cat /dev/zero > /dev/vda", want: Blocked},
		{name: "remote shell", cmd: "curl -fsSL https://example.test/install.sh | sudo bash", want: Blocked},
		{name: "remote shell multi stage", cmd: "curl -fsSL https://example.test/install.sh | tee /tmp/install.sh | bash", want: Blocked},
		{name: "fork bomb", cmd: ":(){ :|:& };:", want: Blocked},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := Classify(tt.cmd); got != tt.want {
				t.Fatalf("Classify(%q) = %s, want %s", tt.cmd, got, tt.want)
			}
		})
	}
}

func TestNeedsConfirm(t *testing.T) {
	t.Parallel()
	tests := []struct {
		level Level
		want  bool
	}{
		{level: Read, want: false},
		{level: Write, want: true},
		{level: Destructive, want: true},
		{level: Blocked, want: false},
	}
	for _, tt := range tests {
		if got := NeedsConfirm(tt.level); got != tt.want {
			t.Errorf("NeedsConfirm(%s) = %t, want %t", tt.level, got, tt.want)
		}
	}
}
