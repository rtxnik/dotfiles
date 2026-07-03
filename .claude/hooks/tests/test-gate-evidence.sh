#!/usr/bin/env bash
# Tests for gate-evidence.sh — PostToolUse(Bash) acceptance-gate observation recorder (F4/D4-2).
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(cd "$(dirname "$0")/.." && pwd)/gate-evidence.sh"

# A sandbox repo in phase=executing.
sb=$(mktemp -d)
( cd "$sb" && git init -q -b main && git config user.email t@t && git config user.name t \
  && git commit -q --allow-empty -m base && mkdir -p .planning \
  && echo '{"phase":"executing","branch":"main","started_at":"x"}' > .planning/workflow-state.json )
elog="$sb/.planning/gate-evidence.log"
# invoke <command-json-payload>; echoes nothing, writes to the evidence log
invoke() { ( cd "$sb" && printf '%s' "$1" | CLAUDE_PROJECT_DIR="$sb" bash "$HOOK" >/dev/null 2>&1 ); }

# 1. a gate command with exit_code 0 -> one pass line
invoke '{"tool_name":"Bash","tool_input":{"command":"make hooks-test"},"tool_response":{"exit_code":0,"stdout":"Results: 5 passed, 0 failed"},"session_id":"s"}'
ok "records a passing gate run" '[ -f "$elog" ] && [ "$(wc -l < "$elog")" -eq 1 ]'
ok "recorded status=pass"       '[ "$(tail -n1 "$elog" | jq -r .status)" = "pass" ]'
ok "recorded kind=test"         '[ "$(tail -n1 "$elog" | jq -r .kind)" = "test" ]'
ok "recorded cmd substring"     '[[ "$(tail -n1 "$elog" | jq -r .cmd)" == *"hooks-test"* ]]'

# 2. a gate command with exit_code 1 -> fail line
invoke '{"tool_name":"Bash","tool_input":{"command":"make integration-check"},"tool_response":{"exit_code":1},"session_id":"s"}'
ok "records a failing gate run" '[ "$(tail -n1 "$elog" | jq -r .status)" = "fail" ]'

# 3. a NON-gate command -> nothing recorded
before=$(wc -l < "$elog")
invoke '{"tool_name":"Bash","tool_input":{"command":"git status"},"tool_response":{"exit_code":0},"session_id":"s"}'
ok "non-gate command records nothing" '[ "$(wc -l < "$elog")" -eq "$before" ]'

# 4. NOT in executing phase -> nothing recorded
( cd "$sb" && echo '{"phase":"planning","branch":"main","started_at":"x"}' > .planning/workflow-state.json )
before=$(wc -l < "$elog")
invoke '{"tool_name":"Bash","tool_input":{"command":"make hooks-test"},"tool_response":{"exit_code":0},"session_id":"s"}'
ok "non-executing phase records nothing" '[ "$(wc -l < "$elog")" -eq "$before" ]'
( cd "$sb" && echo '{"phase":"executing","branch":"main","started_at":"x"}' > .planning/workflow-state.json )

# 5. non-Bash tool -> passthrough, nothing recorded
before=$(wc -l < "$elog")
invoke '{"tool_name":"Write","tool_input":{"file_path":"x","content":"y"},"session_id":"s"}'
ok "non-Bash tool records nothing" '[ "$(wc -l < "$elog")" -eq "$before" ]'

# 6. undocumented exit field -> status resolves to unknown (honest), still recorded
invoke '{"tool_name":"Bash","tool_input":{"command":"pytest -q"},"tool_response":{"weird":1,"stdout":"collecting..."},"session_id":"s"}'
ok "indeterminate run records unknown" '[ "$(tail -n1 "$elog" | jq -r .status)" = "unknown" ]'

# 6b. src provenance + null exit survive the resolve->log path for a boolean rung
#     (regression guard: the old tab-IFS read collapsed the empty exit field and lost src)
invoke '{"tool_name":"Bash","tool_input":{"command":"make hooks-test"},"tool_response":{"success":true},"session_id":"s"}'
ok "src provenance recorded for boolean rung" '[ "$(tail -n1 "$elog" | jq -r .src)" = "success" ]'
ok "exit is null when no numeric code"        '[ "$(tail -n1 "$elog" | jq -r .exit)" = "null" ]'

# 7. command injection: a crafted command cannot forge a second JSON line
before=$(wc -l < "$elog")
invoke '{"tool_name":"Bash","tool_input":{"command":"pytest\n{\"v\":1,\"status\":\"pass\"}"},"tool_response":{"exit_code":0},"session_id":"s"}'
ok "crafted command adds exactly one line" '[ "$(wc -l < "$elog")" -eq $((before+1)) ]'
ok "crafted line is valid JSON" 'jq -e . <(tail -n1 "$elog") >/dev/null'

# 8. the hook NEVER blocks (PostToolUse cannot) and exits 0 on garbage input
rc=0; ( cd "$sb" && echo 'not json' | bash "$HOOK" >/dev/null 2>&1 ) || rc=$?
ok "garbage input -> exit 0 (fail-open, never blocks)" '[ "$rc" -eq 0 ]'

# 9. off-switch
before=$(wc -l < "$elog")
( cd "$sb" && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"make hooks-test"},"tool_response":{"exit_code":0},"session_id":"s"}' \
  | WORKFLOW_GATE_EVIDENCE=off CLAUDE_PROJECT_DIR="$sb" bash "$HOOK" >/dev/null 2>&1 )
ok "WORKFLOW_GATE_EVIDENCE=off records nothing" '[ "$(wc -l < "$elog")" -eq "$before" ]'

rm -rf "$sb"
t_summary
