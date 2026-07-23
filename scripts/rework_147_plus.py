#!/usr/bin/env python3
"""Re-apply lost post-1.4.7 changes onto clean tree."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


def patch(path: str, old: str, new: str, label: str, optional: bool = False) -> None:
    p = ROOT / path
    t = p.read_text()
    if old not in t:
        if optional:
            print(f"SKIP {label}")
            return
        print(f"FAIL {label}: pattern not found in {path}")
        # show nearby for debug
        key = old[:60].replace("\n", "\\n")
        print(f"  looking for: {key!r}...")
        sys.exit(1)
    n = t.count(old)
    p.write_text(t.replace(old, new))
    print(f"OK {label} x{n}")


def replace_all(path: str, old: str, new: str, label: str) -> None:
    p = ROOT / path
    t = p.read_text()
    if old not in t:
        print(f"FAIL {label}")
        sys.exit(1)
    n = t.count(old)
    p.write_text(t.replace(old, new))
    print(f"OK {label} x{n}")


def main() -> None:
    # ========== BACKEND: probe CPU% ==========
    old_script = (
        "printf '%s\\n' '___U___'; uname -a 2>/dev/null; "
        "printf '%s\\n' '___T___'; uptime 2>/dev/null; "
        "printf '%s\\n' '___L___'; cat /proc/loadavg 2>/dev/null; "
        "printf '%s\\n' '___D___'; df -h 2>/dev/null; "
        "printf '%s\\n' '___M___'; (free -h 2>/dev/null || head -5 /proc/meminfo 2>/dev/null)"
    )
    new_script = (
        "printf '%s\\n' '___U___'; uname -a 2>/dev/null; "
        "printf '%s\\n' '___T___'; uptime 2>/dev/null; "
        "printf '%s\\n' '___L___'; cat /proc/loadavg 2>/dev/null; "
        "printf '%s\\n' '___C___'; "
        "r(){ awk '/^cpu /{print $5+$6, $2+$3+$4+$5+$6+$7+$8+$9+$10+$11}' /proc/stat 2>/dev/null; }; "
        "set -- $(r); i1=$1 t1=$2; sleep 0.5; set -- $(r); i2=$1 t2=$2; "
        "di=$((i2-i1)); dt=$((t2-t1)); "
        "if [ -n \"$dt\" ] && [ \"$dt\" -gt 0 ]; then echo $(( (100*(dt-di))/dt )); else echo 0; fi; "
        "printf '%s\\n' '___D___'; df -h 2>/dev/null; "
        "printf '%s\\n' '___M___'; (free -h 2>/dev/null || head -5 /proc/meminfo 2>/dev/null)"
    )
    replace_all("backend/internal/api/agent_handlers.go", old_script, new_script, "probe script +CPU")

    patch(
        "backend/internal/api/agent_handlers.go",
        'out := map[string]string{"U": "", "T": "", "L": "", "D": "", "M": ""}',
        'out := map[string]string{"U": "", "T": "", "L": "", "C": "", "D": "", "M": ""}',
        "splitProbe C",
    )

    patch(
        "backend/internal/api/agent_handlers.go",
        '''\twriteJSON(w, http.StatusOK, map[string]any{
\t\t"uname":  mk(parts["U"]),
\t\t"uptime": mk(parts["T"]),
\t\t"load":   mk(parts["L"]),
\t\t"disk":   mk(parts["D"]),
\t\t"memory": mk(parts["M"]),
\t\t"durationMs": res.DurationMs,
\t})''',
        '''\twriteJSON(w, http.StatusOK, map[string]any{
\t\t"uname":  mk(parts["U"]),
\t\t"uptime": mk(parts["T"]),
\t\t"load":   mk(parts["L"]),
\t\t"cpu":    mk(parts["C"]),
\t\t"disk":   mk(parts["D"]),
\t\t"memory": mk(parts["M"]),
\t\t"durationMs": res.DurationMs,
\t})''',
        "probe JSON cpu",
    )

    patch(
        "backend/internal/api/agent_handlers.go",
        '''\t\twriteJSON(w, http.StatusOK, map[string]any{
\t\t\t"uname":  map[string]any{"error": err.Error()},
\t\t\t"uptime": map[string]any{"error": err.Error()},
\t\t\t"load":   map[string]any{"error": err.Error()},
\t\t\t"disk":   map[string]any{"error": err.Error()},
\t\t\t"memory": map[string]any{"error": err.Error()},
\t\t})''',
        '''\t\twriteJSON(w, http.StatusOK, map[string]any{
\t\t\t"uname":  map[string]any{"error": err.Error()},
\t\t\t"uptime": map[string]any{"error": err.Error()},
\t\t\t"load":   map[string]any{"error": err.Error()},
\t\t\t"cpu":    map[string]any{"error": err.Error()},
\t\t\t"disk":   map[string]any{"error": err.Error()},
\t\t\t"memory": map[string]any{"error": err.Error()},
\t\t})''',
        "probe err JSON cpu",
        optional=True,
    )

    # ========== STORE: thinkingLevel ==========
    patch(
        "backend/internal/store/store.go",
        '''type LLMSettings struct {
	BaseURL        string `json:"baseUrl"`
	APIKey         string `json:"apiKey,omitempty"` // write full; read may be masked
	APIKeySet      bool   `json:"apiKeySet"`
	APIKeyMasked   string `json:"apiKeyMasked,omitempty"`
	Model          string `json:"model"`
	TimeoutSeconds int    `json:"timeoutSeconds"`
}
''',
        '''type LLMSettings struct {
	BaseURL        string `json:"baseUrl"`
	APIKey         string `json:"apiKey,omitempty"` // write full; read may be masked
	APIKeySet      bool   `json:"apiKeySet"`
	APIKeyMasked   string `json:"apiKeyMasked,omitempty"`
	Model          string `json:"model"`
	TimeoutSeconds int    `json:"timeoutSeconds"`
	// ThinkingLevel: none|low|medium|high|xhigh|auto (Minis thinking_override style)
	ThinkingLevel string `json:"thinkingLevel,omitempty"`
}
''',
        "LLMSettings.ThinkingLevel",
    )

    # ensure strings import
    st = (ROOT / "backend/internal/store/store.go").read_text()
    if '"strings"' not in st:
        st = st.replace('\t"fmt"\n', '\t"fmt"\n\t"strings"\n', 1)
        (ROOT / "backend/internal/store/store.go").write_text(st)
        print("OK store strings import")

    patch(
        "backend/internal/store/store.go",
        '''	st := LLMSettings{
		BaseURL:        get("llm.base_url"),
		Model:          get("llm.model"),
		TimeoutSeconds: timeout,
		APIKeySet:      key != "",
	}
	if st.Model == "" {
		st.Model = "grok-4.5"
	}
	if st.TimeoutSeconds == 0 {
		st.TimeoutSeconds = 180
	}
''',
        '''	st := LLMSettings{
		BaseURL:        get("llm.base_url"),
		Model:          get("llm.model"),
		TimeoutSeconds: timeout,
		APIKeySet:      key != "",
		ThinkingLevel:  get("llm.thinking_level"),
	}
	if st.Model == "" {
		st.Model = "grok-4.5"
	}
	if st.TimeoutSeconds == 0 {
		st.TimeoutSeconds = 180
	}
	if st.ThinkingLevel == "" {
		st.ThinkingLevel = "auto"
	}
''',
        "GetLLM thinking",
    )

    patch(
        "backend/internal/store/store.go",
        '''	if in.TimeoutSeconds > 0 {
		if err := put("llm.timeout_seconds", fmt.Sprintf("%d", in.TimeoutSeconds)); err != nil {
			return in, err
		}
	}
	if in.APIKey != "" {
''',
        '''	if in.TimeoutSeconds > 0 {
		if err := put("llm.timeout_seconds", fmt.Sprintf("%d", in.TimeoutSeconds)); err != nil {
			return in, err
		}
	}
	if in.ThinkingLevel != "" {
		if err := put("llm.thinking_level", strings.ToLower(strings.TrimSpace(in.ThinkingLevel))); err != nil {
			return in, err
		}
	}
	if in.APIKey != "" {
''',
        "PutLLM thinking",
    )

    print("backend probe+store done")


if __name__ == "__main__":
    main()
