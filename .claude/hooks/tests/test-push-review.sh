#!/usr/bin/env bash
# Tests for push-review.sh hook
set -euo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(cd "$(dirname "$0")/.." && pwd)/push-review.sh"

run_test() {
  local name="$1" input="$2" expect_exit="$3" expect_output="$4"
  actual_exit=0
  output=$(echo "$input" | bash "$HOOK" 2>&1) || actual_exit=$?
  exit_ok=false; output_ok=false
  [ "$actual_exit" -eq "$expect_exit" ] && exit_ok=true
  if [ "$expect_output" = "review" ] && echo "$output" | grep -c "Push Review" > /dev/null; then
    output_ok=true
  elif [ "$expect_output" = "none" ] && [ -z "$output" ]; then
    output_ok=true
  fi
  if $exit_ok && $output_ok; then
    echo "PASS: $name"
    pass=$((pass+1))
  else
    echo "FAIL: $name (exit=$actual_exit output_has_review=$(echo "$output" | grep -c 'Push Review'))"
    fail=$((fail+1))
  fi
}

# Should show review on git push
run_test "show review on push" \
  '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
  0 "review"

# Should show review on plain git push
run_test "show review on plain push" \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  0 "review"

# Should not fire on non-push commands
run_test "skip non-push" \
  '{"tool_name":"Bash","tool_input":{"command":"git status"}}' \
  0 "none"

# Should not fire on non-Bash tools
run_test "skip non-Bash" \
  '{"tool_name":"Write","tool_input":{"file_path":"x","content":"y"}}' \
  0 "none"

# Always exits 0 (non-blocking)
run_test "always exit 0" \
  '{"tool_name":"Bash","tool_input":{"command":"git push --force origin feature"}}' \
  0 "review"

# F3: no-origin repo -> the hook's OWN empty-range policy = last-5 commits note.
nor=$(mktemp -d)
( cd "$nor" && git init -q -b main &&
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m one &&
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m two )
out=$( printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
  | ( cd "$nor" && bash "$HOOK" ) 2>&1 ) || true
if echo "$out" | grep -q "last 5 commits" && echo "$out" | grep -q "two"; then
  echo "PASS: no-origin falls back to last-5 note"; pass=$((pass+1))
else
  echo "FAIL: no-origin last-5 fallback (out: $out)"; fail=$((fail+1))
fi
rm -rf "$nor"

# F2: a warn must leave an audit line.
alog="$(mktemp -d)/audit.jsonl"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
  | WORKFLOW_AUDIT_PATH="$alog" bash "$HOOK" >/dev/null 2>&1 || true
if [ -s "$alog" ] && tail -n1 "$alog" | jq -e '.result=="warn"' >/dev/null 2>&1; then
  echo "PASS: warn audited"
  pass=$((pass+1))
else
  echo "FAIL: no audit line on warn"; fail=$((fail+1))
fi

t_summary
