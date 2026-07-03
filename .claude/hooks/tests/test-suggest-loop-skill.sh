#!/usr/bin/env bash
# Tests for suggest-loop-skill.sh
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(dirname "$0")/../suggest-loop-skill.sh"
run() {
  local name="$1" input="$2" expect="$3"   # expect: output substring, or "nohint"
  out=$(echo "$input" | bash "$HOOK" 2>&1) || true
  if [ "$expect" = "nohint" ]; then
    if echo "$out" | grep -q '\[hint\]'; then echo "FAIL: $name (got hint: $out)"; fail=$((fail+1));
    else echo "PASS: $name"; pass=$((pass+1)); fi
  else
    if echo "$out" | grep -q "$expect"; then echo "PASS: $name"; pass=$((pass+1));
    else echo "FAIL: $name (out: $out)"; fail=$((fail+1)); fi
  fi
}
run "hint on refactor"          '{"prompt":"please refactor this module"}' "polish-loop"
run "hint on optimize"          '{"prompt":"optimize the bundle size"}' "optimization-loop"
run "hint on bug"               '{"prompt":"there is a bug, the parser is broken on empty input"}' "systematic-debugging"
run "hint on review"            '{"prompt":"review the code in my latest changes"}' "code-review"
run "hint on new feature"       '{"prompt":"implement a new feature: export to CSV"}' "brainstorming"
run "hint on russian refactor"  '{"prompt":"отрефактори этот модуль"}' "polish-loop"
run "hint on russian bug"       '{"prompt":"почини баг: парсер падает"}' "systematic-debugging"
run "no hint on plain"          '{"prompt":"what time is it"}' nohint
run "no hint on envelope keyword (Finding T)" '{"prompt":"hello","session_id":"refactor-9f3","cwd":"/tmp/refactor-work"}' nohint
run "no hint on missing prompt" '{"tool_name":"Bash"}' nohint
# F2: a warn must leave an audit line.
alog="$(mktemp -d)/audit.jsonl"
printf '%s' '{"prompt":"optimize the bundle size"}' \
  | WORKFLOW_AUDIT_PATH="$alog" bash "$HOOK" >/dev/null 2>&1 || true
if [ -s "$alog" ] && tail -n1 "$alog" | jq -e '.result=="warn"' >/dev/null 2>&1; then
  echo "PASS: warn audited"; pass=$((pass+1))
else
  echo "FAIL: no audit line on warn"; fail=$((fail+1))
fi
t_summary
