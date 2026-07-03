#!/usr/bin/env bash
# Tests for pre-push-contract.sh — throwaway git repo on a feature branch.
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(cd "$(dirname "$0")/.." && pwd)/pre-push-contract.sh"
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
( cd "$sandbox" && git init -q && git checkout -q -b feat/test && mkdir -p .planning && echo '{"phase":"executing"}' > .planning/workflow-state.json )
run() {
  local name="$1" input="$2" expect="$3"  # warn|quiet
  out=$( cd "$sandbox" && echo "$input" | CLAUDE_PROJECT_DIR="$sandbox" bash "$HOOK" 2>&1 ) || true
  got=quiet; echo "$out" | grep -q 'WARNING' && got=warn
  if [ "$got" = "$expect" ]; then echo "PASS: $name"; pass=$((pass+1));
  else echo "FAIL: $name (got $got)"; fail=$((fail+1)); fi
}
run "empty ledger warns" '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/test"}}' warn
run "non-push quiet" '{"tool_name":"Bash","tool_input":{"command":"git status"}}' quiet
( cd "$sandbox" && { printf 'timestamp\tfiles\toutcome\tgate_result\tnotes\n'; printf '2026-05-29\tx\tkept\tok\tnote\n'; } > .planning/LEDGER.tsv )
run "populated ledger quiet" '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/test"}}' quiet
# P3 / Finding M: schema problems warn; the balance line always surfaces the ratio.
( cd "$sandbox" && { printf 'timestamp\tfiles\toutcome\tgate_result\tnotes\n'; printf '2026-06-04\tx\tkeep\tok\tnote\n'; } > .planning/LEDGER.tsv )
run "invalid outcome vocabulary warns" '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/test"}}' warn
( cd "$sandbox" && { printf 'timestamp\tfiles\toutcome\tgate_result\tnotes\n'; printf '2026-06-04\tx\tkept\tok\n'; } > .planning/LEDGER.tsv )
run "wrong column count warns" '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/test"}}' warn
( cd "$sandbox" && { printf 'timestamp\tfiles\toutcome\tgate_result\tnotes\n'; printf '2026-06-04\tx\tkept\tok\tnote\n2026-06-04\ty\tdiscarded\tno win\tnote\n'; } > .planning/LEDGER.tsv )
out=$( cd "$sandbox" && echo '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/test"}}' | CLAUDE_PROJECT_DIR="$sandbox" bash "$HOOK" 2>&1 ) || true
if echo "$out" | grep -q 'LEDGER balance: kept=1 discarded=1 dead-end=0'; then
  echo "PASS: balance line surfaces the ratio"; pass=$((pass+1))
else
  echo "FAIL: balance line surfaces the ratio (out: $out)"; fail=$((fail+1))
fi
if echo "$out" | grep -q 'WARNING'; then
  echo "FAIL: valid mixed ledger must not warn"; fail=$((fail+1))
else
  echo "PASS: valid mixed ledger does not warn"; pass=$((pass+1))
fi
( cd "$sandbox" && { printf 'timestamp\tfiles\toutcome\tgate_result\tnotes\n'; printf '2026-06-04\tx\tkept\tok\tnote\n'; } > .planning/LEDGER.tsv )
out=$( cd "$sandbox" && echo '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/test"}}' | CLAUDE_PROJECT_DIR="$sandbox" bash "$HOOK" 2>&1 ) || true
if echo "$out" | grep -q 'all-kept history'; then
  echo "PASS: all-kept nudge fires (Finding M)"; pass=$((pass+1))
else
  echo "FAIL: all-kept nudge fires (out: $out)"; fail=$((fail+1))
fi
# P5 / D8: a ledger with zero valid rows must warn as empty and must NOT get the all-kept nudge.
( cd "$sandbox" && { printf 'timestamp\tfiles\toutcome\tgate_result\tnotes\n'; printf '\n'; } > .planning/LEDGER.tsv )
out=$( cd "$sandbox" && echo '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/test"}}' | CLAUDE_PROJECT_DIR="$sandbox" bash "$HOOK" 2>&1 ) || true
if echo "$out" | grep -q 'WARNING: Pushing feature branch without LEDGER.tsv entries'; then
  echo "PASS: zero-valid-row ledger warns as empty"; pass=$((pass+1))
else
  echo "FAIL: zero-valid-row ledger warns as empty (out: $out)"; fail=$((fail+1))
fi
if echo "$out" | grep -q 'all-kept history'; then
  echo "FAIL: zero-valid-row ledger must not get the all-kept nudge"; fail=$((fail+1))
else
  echo "PASS: zero-valid-row ledger gets no all-kept nudge"; pass=$((pass+1))
fi

# --- F4 / D4-2: evidence cross-check — kept rows + a PRESENT log with no PASS line -> NOTE ---
# (A MISSING log is deliberately silent — fresh-checkout / gates-run-outside-harness must not
# warn; that is the design, so the fixture writes a present log carrying only a non-pass line.)
( cd "$sandbox" && { printf 'timestamp\tfiles\toutcome\tgate_result\tnotes\n'; printf '2026-06-16\tx\tkept\thooks-test-pass\tn\n'; } > .planning/LEDGER.tsv
  printf '{"v":1,"ts":"2026-06-16T00:00:00Z","event":"gate-evidence","status":"fail","exit":1,"kind":"test","cmd":"make hooks-test","src":"exit_code","branch":"feat/test","sha":"abc","session":"s"}\n' > .planning/gate-evidence.log )
out=$( cd "$sandbox" && echo '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/test"}}' | CLAUDE_PROJECT_DIR="$sandbox" bash "$HOOK" 2>&1 ) || true
if echo "$out" | grep -q 'no observed passing gate run'; then
  echo "PASS: cross-check NOTE fires when kept rows exist and the log has no pass line"; pass=$((pass+1))
else
  echo "FAIL: cross-check NOTE (out: $out)"; fail=$((fail+1))
fi
# A MISSING log stays silent (fail-open by design).
( cd "$sandbox" && rm -f .planning/gate-evidence.log )
out=$( cd "$sandbox" && echo '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/test"}}' | CLAUDE_PROJECT_DIR="$sandbox" bash "$HOOK" 2>&1 ) || true
if echo "$out" | grep -q 'no observed passing gate run'; then
  echo "FAIL: missing log must be silent (out: $out)"; fail=$((fail+1))
else
  echo "PASS: missing evidence log is silent (fail-open)"; pass=$((pass+1))
fi
# With a matching pass line for THIS branch -> silent (no NOTE)
( cd "$sandbox" && printf '{"v":1,"ts":"2026-06-16T00:00:00Z","event":"gate-evidence","status":"pass","exit":0,"kind":"test","cmd":"make hooks-test","src":"exit_code","branch":"feat/test","sha":"abc","session":"s"}\n' > .planning/gate-evidence.log )
out=$( cd "$sandbox" && echo '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/test"}}' | CLAUDE_PROJECT_DIR="$sandbox" bash "$HOOK" 2>&1 ) || true
if echo "$out" | grep -q 'no observed passing gate run'; then
  echo "FAIL: cross-check must be silent when a pass line exists (out: $out)"; fail=$((fail+1))
else
  echo "PASS: cross-check silent when a passing run is observed"; pass=$((pass+1))
fi
rm -f "$sandbox/.planning/gate-evidence.log"

# F2: a warn must leave an audit line.
( cd "$sandbox" && rm -f .planning/LEDGER.tsv && printf 'timestamp\tfiles\toutcome\tgate_result\tnotes\n' > .planning/LEDGER.tsv )
alog="$(mktemp -d)/audit.jsonl"
( cd "$sandbox" && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/test"}}' \
  | WORKFLOW_AUDIT_PATH="$alog" bash "$HOOK" >/dev/null 2>&1 ) || true
if [ -s "$alog" ] && tail -n1 "$alog" | jq -e '.result=="warn"' >/dev/null 2>&1; then
  echo "PASS: warn audited"; pass=$((pass+1))
else
  echo "FAIL: no audit line on warn"; fail=$((fail+1))
fi

t_summary
