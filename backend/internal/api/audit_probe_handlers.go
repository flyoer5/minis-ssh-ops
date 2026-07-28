package api

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"
)

func (s *Server) handleAudit(w http.ResponseWriter, r *http.Request) {
	limit := 100
	if q := r.URL.Query().Get("limit"); q != "" {
		if n, err := strconv.Atoi(q); err == nil {
			if n < 1 {
				n = 1
			}
			if n > 1000 {
				n = 1000
			}
			limit = n
		}
	}
	list, err := s.Store.ListAudit(limit)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"entries": list})
}

func (s *Server) handleProbe(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	// One SSH session / one compound command — much faster than 5 sequential dials.
	// O = os-release pretty name; U = uname -a (arch still parsed client-side)
	const script = `printf '%s\n' '___O___'; ( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-${NAME:-}} ${VERSION_ID:-}" ) | sed 's/  */ /g;s/^ //;s/ $//'; printf '%s\n' '___U___'; uname -a 2>/dev/null; printf '%s\n' '___T___'; uptime 2>/dev/null; printf '%s\n' '___L___'; cat /proc/loadavg 2>/dev/null; printf '%s\n' '___C___'; grep -m1 '^cpu ' /proc/stat 2>/dev/null; sleep 0.12 2>/dev/null || sleep 1; grep -m1 '^cpu ' /proc/stat 2>/dev/null; printf '%s\n' '___D___'; df -h 2>/dev/null; printf '%s\n' '___M___'; (free -h 2>/dev/null || head -5 /proc/meminfo 2>/dev/null)`
	res, err := s.runSSH(id, script)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{
			"os":     map[string]any{"error": err.Error()},
			"uname":  map[string]any{"error": err.Error()},
			"uptime": map[string]any{"error": err.Error()},
			"load":   map[string]any{"error": err.Error()},
			"cpu":    map[string]any{"error": err.Error()},
			"disk":   map[string]any{"error": err.Error()},
			"memory": map[string]any{"error": err.Error()},
		})
		return
	}
	parts := splitProbe(res.Stdout)
	parts["C"] = cpuUsageFromProcStat(parts["C"])
	mk := func(s string) map[string]any {
		return map[string]any{"exitCode": res.ExitCode, "stdout": strings.TrimSpace(s), "stderr": ""}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"os":         mk(parts["O"]),
		"uname":      mk(parts["U"]),
		"uptime":     mk(parts["T"]),
		"load":       mk(parts["L"]),
		"cpu":        mk(parts["C"]),
		"disk":       mk(parts["D"]),
		"memory":     mk(parts["M"]),
		"durationMs": res.DurationMs,
	})
}

// cpuUsageFromProcStat parses two "cpu ..." lines (~1s apart) → utilization 0–100.
func cpuUsageFromProcStat(raw string) string {
	var samples [][]uint64
	for _, line := range strings.Split(raw, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 5 || fields[0] != "cpu" {
			continue
		}
		nums := make([]uint64, 0, len(fields)-1)
		ok := true
		for _, f := range fields[1:] {
			var v uint64
			if _, err := fmt.Sscanf(f, "%d", &v); err != nil {
				ok = false
				break
			}
			nums = append(nums, v)
		}
		if !ok || len(nums) < 4 {
			continue
		}
		samples = append(samples, nums)
		if len(samples) >= 2 {
			break
		}
	}
	if len(samples) < 2 {
		return strings.TrimSpace(raw)
	}
	a, b := samples[0], samples[1]
	for len(a) < 8 {
		a = append(a, 0)
	}
	for len(b) < 8 {
		b = append(b, 0)
	}
	sum8 := func(s []uint64) uint64 {
		var t uint64
		for i := 0; i < 8; i++ {
			t += s[i]
		}
		return t
	}
	idleOf := func(s []uint64) uint64 { return s[3] + s[4] }
	if sum8(b) < sum8(a) || idleOf(b) < idleOf(a) {
		return "0"
	}
	dt := sum8(b) - sum8(a)
	di := idleOf(b) - idleOf(a)
	if dt == 0 {
		return "0"
	}
	busy := dt - di
	pct := (busy * 100) / dt
	if pct > 100 {
		pct = 100
	}
	return fmt.Sprintf("%d", pct)
}

func splitProbe(stdout string) map[string]string {
	out := map[string]string{"O": "", "U": "", "T": "", "L": "", "C": "", "D": "", "M": ""}
	cur := ""
	for _, line := range strings.Split(stdout, "\n") {
		if strings.HasPrefix(line, "___") && strings.HasSuffix(line, "___") && len(line) >= 7 {
			// ___X___
			tag := strings.Trim(line, "_")
			if len(tag) == 1 {
				cur = tag
				continue
			}
		}
		if cur == "" {
			continue
		}
		if out[cur] == "" {
			out[cur] = line
		} else {
			out[cur] += "\n" + line
		}
	}
	return out
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "\n...[truncated]"
}
