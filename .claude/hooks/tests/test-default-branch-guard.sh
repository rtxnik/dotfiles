#!/usr/bin/env bash
# Tests for default-branch-guard.sh
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(cd "$(dirname "$0")/.." && pwd)/default-branch-guard.sh"

# Run the hook inside a repo with a payload + optional env; echo the exit code.
run() { # repo payload [ENV=val...]
  local repo="$1" payload="$2"; shift 2
  local rc=0
  echo "$payload" | ( cd "$repo" && env "$@" bash "$HOOK" >/dev/null 2>&1 ) || rc=$?
  echo "$rc"
}

commit='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\""}}'
noncommit='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
nonbash='{"tool_name":"Write","tool_input":{"file_path":"x","content":"y"}}'

# symbolic-ref sets the unborn branch on any git version with no risk of colliding
# with the repo's default branch name (which `git checkout -b main` would hit).
mainrepo=$(mktemp -d);   ( cd "$mainrepo"   && git init -q && git symbolic-ref HEAD refs/heads/main )
masterrepo=$(mktemp -d); ( cd "$masterrepo" && git init -q && git symbolic-ref HEAD refs/heads/master )
featrepo=$(mktemp -d);   ( cd "$featrepo"   && git init -q && git symbolic-ref HEAD refs/heads/feature/x )
trap 'rm -rf "$mainrepo" "$masterrepo" "$featrepo"' EXIT

ok "blocks commit on main"        '[ "$(run "$mainrepo" "$commit")" = "2" ]'
ok "blocks commit on master"      '[ "$(run "$masterrepo" "$commit")" = "2" ]'
ok "allows commit on feature"     '[ "$(run "$featrepo" "$commit")" = "0" ]'
ok "allows non-commit on main"    '[ "$(run "$mainrepo" "$noncommit")" = "0" ]'
ok "passthrough non-Bash on main" '[ "$(run "$mainrepo" "$nonbash")" = "0" ]'
ok "disabled -> allows on main"   '[ "$(run "$mainrepo" "$commit" WORKFLOW_DISABLED_HOOKS=default-branch-guard)" = "0" ]'
ok "fail-open empty input"        '[ "$(run "$mainrepo" "")" = "0" ]'

# F2: a block must leave an audit line.
alog="$(mktemp -d)/audit.jsonl"
printf '%s' "$commit" | ( cd "$mainrepo" && WORKFLOW_AUDIT_PATH="$alog" bash "$HOOK" >/dev/null 2>&1 )
if [ -s "$alog" ] && tail -n1 "$alog" | jq -e '.result=="block"' >/dev/null 2>&1; then
  echo "PASS: block audited"; pass=$((pass+1))
else
  echo "FAIL: no audit line on block"; fail=$((fail+1))
fi

t_summary
