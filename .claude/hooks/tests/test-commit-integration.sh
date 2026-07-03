#!/usr/bin/env bash
# Tests for commit-integration.sh — isolated CLAUDE_PROJECT_DIR sandbox.
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(cd "$(dirname "$0")/.." && pwd)/commit-integration.sh"
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/.planning"; echo '{"phase":"executing"}' > "$sandbox/.planning/workflow-state.json"
run() {
  local name="$1" input="$2" expect="$3"   # remind|silent|revert
  out=$(cd "$sandbox" && echo "$input" | CLAUDE_PROJECT_DIR="$sandbox" bash "$HOOK" 2>&1) || true
  got=silent
  echo "$out" | grep -q 'COMMIT DETECTED' && got=remind
  echo "$out" | grep -q 'REVERT DETECTED' && got=revert
  if [ "$got" = "$expect" ]; then echo "PASS: $name"; pass=$((pass+1));
  else echo "FAIL: $name (got $got)"; fail=$((fail+1)); fi
}
run "commit output reminds" '{"tool_name":"Bash","tool_result":{"stdout":"[main abc1234] feat: x"}}' remind
run "real tool_response reminds" '{"tool_name":"Bash","tool_response":{"stdout":"[main abc1234] feat: x"}}' remind
run "no commit silent"      '{"tool_name":"Bash","tool_result":{"stdout":"nothing to commit"}}' silent
run "non-bash silent"       '{"tool_name":"Write","tool_result":{"stdout":"[main abc1234] x"}}' silent
# F4 / D6-3: a revert-shaped commit subject triggers the advisory (still in executing phase)
run "git revert commit reminds to log discard" \
  '{"tool_name":"Bash","tool_input":{"command":"git revert abc123"},"tool_response":{"stdout":"[main def4567] Revert \"feat: x\""}}' revert
run "Revert-subject commit triggers advisory" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"tool_response":{"stdout":"[main def4567] Revert \"feat: y\""}}' revert
# a normal commit still gives the plain reminder, not the revert advisory
run "normal commit is remind not revert" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"tool_response":{"stdout":"[main abc1234] feat: normal"}}' remind
t_summary
