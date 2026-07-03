#!/usr/bin/env bash
# Tests for tool-loop-guard.sh (warn-only, debounced ring-buffer loop detector)
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(cd "$(dirname "$0")/.." && pwd)/tool-loop-guard.sh"

sess="looptest-$$"
ring="${TMPDIR:-/tmp}/wf-toolloop-${sess}.ring"
warned="${TMPDIR:-/tmp}/wf-toolloop-${sess}.warned"
trap 'rm -f "$ring" "$warned"' EXIT
rm -f "$ring" "$warned"

# stdout for a Bash call running $1 (empty => no warn), optional env in $2..
emit() { # command [ENV=val...]
  local cmd="$1"; shift
  printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$sess" "$cmd" \
    | ( env "$@" bash "$HOOK" 2>/dev/null )
}

# Same call below threshold (default 5) -> no warn.
ok "1st no warn" '[ -z "$(emit "make test")" ]'
ok "2nd no warn" '[ -z "$(emit "make test")" ]'
ok "3rd no warn" '[ -z "$(emit "make test")" ]'
ok "4th no warn" '[ -z "$(emit "make test")" ]'

# 5th hits threshold -> warn once (capture it for the envelope check).
fifth="$(emit "make test")"
ok "5th warns"                  '[ -n "$fifth" ]'
ok "warn is additionalContext" '[ -n "$(printf "%s" "$fifth" | jq -e .hookSpecificOutput.additionalContext 2>/dev/null)" ]'

# 6th identical call -> debounced (silent).
ok "6th debounced (silent)" '[ -z "$(emit "make test")" ]'

# A DIFFERENT call (distinct key, below threshold) -> silent.
ok "different call silent"   '[ -z "$(emit "git status")" ]'

# Disabled -> silent even when looping.
rm -f "$ring" "$warned"
for _ in 1 2 3 4 5; do emit "make x" WORKFLOW_DISABLED_HOOKS=tool-loop-guard >/dev/null 2>&1; done
ok "disabled -> silent" '[ -z "$(emit "make x" WORKFLOW_DISABLED_HOOKS=tool-loop-guard)" ]'

# WORKFLOW_LOOP_THRESHOLD clamp (I7 cfg_int): garbage and out-of-range (>1000) both fall back to
# the default of 5, so the warn still fires only at the 5th identical repeat. Fresh ring per env.
# Pre-I7 (raw ${VAR:-5}) garbage broke the [ -ge ] arithmetic test and 99999 suppressed the warn.
clamp_warns_at_5th() { # label ENV=val
  rm -f "$ring" "$warned"
  local fourth fifth
  emit "spin" "$2" >/dev/null; emit "spin" "$2" >/dev/null; emit "spin" "$2" >/dev/null
  fourth=$(emit "spin" "$2")   # 4th identical -> still under default 5 -> silent
  fifth=$(emit "spin" "$2")    # 5th identical -> default threshold -> warn
  if [ -z "$fourth" ] && [ -n "$fifth" ]; then
    echo "PASS: $1"; pass=$((pass+1))
  else
    echo "FAIL: $1"; fail=$((fail+1))
  fi
}
clamp_warns_at_5th "LOOP_THRESHOLD=garbage clamps to default 5 (warn at 5th)" "WORKFLOW_LOOP_THRESHOLD=garbage"
clamp_warns_at_5th "LOOP_THRESHOLD=99999 clamps to default 5 (warn at 5th)" "WORKFLOW_LOOP_THRESHOLD=99999"

# F2: a warn must leave an audit line.
rm -f "$ring" "$warned"
alog="$(mktemp -d)/audit.jsonl"
for _ in 1 2 3 4 5; do
  printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"make audit-test"}}' "$sess" \
    | ( WORKFLOW_AUDIT_PATH="$alog" bash "$HOOK" 2>/dev/null ) || true
done
if [ -s "$alog" ] && tail -n1 "$alog" | jq -e '.result=="warn"' >/dev/null 2>&1; then
  echo "PASS: warn audited"; pass=$((pass+1))
else
  echo "FAIL: no audit line on warn"; fail=$((fail+1))
fi

t_summary
