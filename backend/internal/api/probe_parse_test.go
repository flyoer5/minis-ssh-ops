package api

import (
	"strings"
	"testing"
)

func TestSplitProbeTags(t *testing.T) {
	stdout := "___O___\nUbuntu 22.04\n___U___\nLinux host 5.15 x86_64\n___C___\ncpu  1 2 3 4 5 6 7 8\n___M___\nMem: 8G 4G\n"
	m := splitProbe(stdout)
	// values may carry a trailing newline from the final split segment;
	// consumers TrimSpace, so compare trimmed.
	if strings.TrimSpace(m["O"]) != "Ubuntu 22.04" {
		t.Errorf("O=%q", m["O"])
	}
	if strings.TrimSpace(m["U"]) != "Linux host 5.15 x86_64" {
		t.Errorf("U=%q", m["U"])
	}
	if strings.TrimSpace(m["C"]) != "cpu  1 2 3 4 5 6 7 8" {
		t.Errorf("C=%q", m["C"])
	}
	if strings.TrimSpace(m["M"]) != "Mem: 8G 4G" {
		t.Errorf("M=%q", m["M"])
	}
	if m["T"] != "" || m["L"] != "" || m["D"] != "" {
		t.Errorf("unexpected defaults: %+v", m)
	}
}

func TestSplitProbeMultiLine(t *testing.T) {
	stdout := "___D___\nline1\nline2\n___T___\nup 3 days\n"
	m := splitProbe(stdout)
	if strings.TrimSpace(m["D"]) != "line1\nline2" {
		t.Errorf("D=%q", m["D"])
	}
	if strings.TrimSpace(m["T"]) != "up 3 days" {
		t.Errorf("T=%q", m["T"])
	}
}

func TestSplitProbeGarbageBeforeFirstTag(t *testing.T) {
	stdout := "noise\nmore noise\n___U___\nuname here\n"
	m := splitProbe(stdout)
	if strings.TrimSpace(m["U"]) != "uname here" {
		t.Errorf("U=%q", m["U"])
	}
}

func TestSplitProbeEmpty(t *testing.T) {
	m := splitProbe("")
	for k, v := range m {
		if v != "" {
			t.Errorf("key %s should be empty, got %q", k, v)
		}
	}
}

func TestCpuUsageFromProcStatValid(t *testing.T) {
	raw := "cpu  100 0 100 800 50 0 0 0\ncpu  200 0 200 1600 100 0 0 0"
	got := cpuUsageFromProcStat(raw)
	// dt=(200+200+1600+100)-(100+100+800+50)=1050, di=(1600+100)-(800+50)=850
	// busy=200, pct=200*100/1050=19
	if got != "19" {
		t.Errorf("pct=%q want 19", got)
	}
}

func TestCpuUsageFromProcStatSingleSample(t *testing.T) {
	raw := "cpu  100 0 100 800 50 0 0 0"
	got := cpuUsageFromProcStat(raw)
	if got != "cpu  100 0 100 800 50 0 0 0" {
		t.Errorf("single sample should passthrough, got %q", got)
	}
}

func TestCpuUsageFromProcStatCounterReset(t *testing.T) {
	raw := "cpu  500 0 500 9000 200 0 0 0\ncpu  100 0 100 800 50 0 0 0"
	if got := cpuUsageFromProcStat(raw); got != "0" {
		t.Errorf("counter reset should give 0, got %q", got)
	}
}

func TestCpuUsageFromProcStatGarbage(t *testing.T) {
	if got := cpuUsageFromProcStat("not a stat"); got != "not a stat" {
		t.Errorf("garbage passthrough, got %q", got)
	}
}
