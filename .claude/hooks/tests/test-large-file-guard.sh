#!/usr/bin/env bash
# Tests for large-file-guard.sh hook
set -euo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(dirname "$0")/../large-file-guard.sh"

run_test() {
  local name="$1" input="$2" expect_exit="$3" expect_warn="$4"
  actual_exit=0
  output=$(echo "$input" | bash "$HOOK" 2>&1) || actual_exit=$?
  exit_ok=false; warn_ok=false
  [ "$actual_exit" -eq "$expect_exit" ] && exit_ok=true
  if [ "$expect_warn" = "yes" ] && echo "$output" | grep -q "WARNING"; then
    warn_ok=true
  elif [ "$expect_warn" = "no" ] && ! echo "$output" | grep -q "WARNING"; then
    warn_ok=true
  fi
  if $exit_ok && $warn_ok; then
    echo "PASS: $name"
    pass=$((pass+1))
  else
    echo "FAIL: $name (exit=$actual_exit expect=$expect_exit warn=$(echo "$output" | grep -c WARNING) expect_warn=$expect_warn)"
    fail=$((fail+1))
  fi
}

# Generate a valid JSON payload for a Write tool call with N lines of content
make_payload() {
  local lines="$1" path="$2"
  python3 -c "
import json, sys
content = '\n'.join(['line %d' % i for i in range($lines)])
print(json.dumps({'tool_name': 'Write', 'tool_input': {'file_path': '$path', 'content': content}}))
"
}

# Should warn: >500 lines
run_test "warn 600 lines" \
  "$(make_payload 600 big.py)" \
  0 "yes"

# Should not warn: exactly 500 lines
run_test "no warn 500 lines" \
  "$(make_payload 500 ok.py)" \
  0 "no"

# Should not warn: small file
run_test "no warn 10 lines" \
  "$(make_payload 10 small.py)" \
  0 "no"

# Should passthrough: non-Write tools
run_test "passthrough Edit" \
  '{"tool_name":"Edit","tool_input":{"file_path":"x.py","old_string":"a","new_string":"b"}}' \
  0 "no"

# Always exits 0 (non-blocking)
run_test "always exit 0 even on large" \
  "$(make_payload 2000 huge.py)" \
  0 "yes"

# F2: a warn must leave an audit line.
alog="$(mktemp -d)/audit.jsonl"
printf '%s' "$(make_payload 600 big.py)" | WORKFLOW_AUDIT_PATH="$alog" bash "$HOOK" >/dev/null 2>&1 || true
if [ -s "$alog" ] && tail -n1 "$alog" | jq -e '.result=="warn"' >/dev/null 2>&1; then
  echo "PASS: warn audited"
  pass=$((pass+1))
else
  echo "FAIL: no audit line on warn"; fail=$((fail+1))
fi

t_summary
