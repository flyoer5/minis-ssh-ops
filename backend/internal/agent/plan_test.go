package agent

import (
	"testing"

	"github.com/flyoer5/ssh-ai-agent/backend/internal/risk"
)

func TestParsePlanDoesNotDowngradeClassifiedRisk(t *testing.T) {
	t.Parallel()
	plan, err := ParsePlan(`{
		"reply":"check",
		"commands":[
			{"command":"rm -rf /","side_effect":"write"},
			{"command":"rm /tmp/stale","side_effect":"read"}
		]
	}`)
	if err != nil {
		t.Fatal(err)
	}
	if got := plan.Steps[0].Risk; got != risk.Blocked {
		t.Fatalf("blocked command risk = %s, want %s", got, risk.Blocked)
	}
	if got := plan.Steps[1].Risk; got != risk.Destructive {
		t.Fatalf("destructive command risk = %s, want %s", got, risk.Destructive)
	}
}
