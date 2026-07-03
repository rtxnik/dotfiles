#!/usr/bin/env bash
# Tests for config-protection.sh
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(cd "$(dirname "$0")/.." && pwd)/config-protection.sh"

sb=$(mktemp -d); trap 'rm -rf "$sb"' EXIT

# exit code for an Edit/Write payload targeting $1, optional env in $2..
run() { # filepath tool [ENV=val...]
  local fp="$1" tool="$2"; shift 2
  local rc=0
  if [ "$tool" = "Write" ]; then
    payload=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$fp")
  else
    payload=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' "$fp")
  fi
  echo "$payload" | ( env "$@" bash "$HOOK" >/dev/null 2>&1 ) || rc=$?
  echo "$rc"
}

# An EXISTING protected config -> modification blocked.
touch "$sb/.shellcheckrc" "$sb/.prettierrc" "$sb/biome.json"
ok "blocks Edit of existing .shellcheckrc" '[ "$(run "$sb/.shellcheckrc" Edit)" = "2" ]'
ok "blocks Write over existing .prettierrc" '[ "$(run "$sb/.prettierrc" Write)" = "2" ]'
ok "blocks Edit of existing biome.json"    '[ "$(run "$sb/biome.json" Edit)" = "2" ]'

# First-time CREATION of a protected config (does not exist, parent readable) -> allowed.
ok "allows Write create of new .eslintrc.json" '[ "$(run "$sb/.eslintrc.json" Write)" = "0" ]'

# Non-protected configs -> always allowed (excluded by design).
touch "$sb/pyproject.toml" "$sb/tsconfig.json"
ok "allows Edit of pyproject.toml (excluded)" '[ "$(run "$sb/pyproject.toml" Edit)" = "0" ]'
ok "allows Edit of tsconfig.json (excluded)"  '[ "$(run "$sb/tsconfig.json" Edit)" = "0" ]'

# Unrelated file -> allowed.
touch "$sb/main.go"
ok "allows Edit of source file" '[ "$(run "$sb/main.go" Edit)" = "0" ]'

# Escape hatch.
ok "disabled -> allows existing config edit" '[ "$(run "$sb/.shellcheckrc" Edit WORKFLOW_DISABLED_HOOKS=config-protection)" = "0" ]'

# Fail-open on malformed input.
rc=0; echo "" | bash "$HOOK" >/dev/null 2>&1 || rc=$?
ok "fail-open empty input" '[ "$rc" = "0" ]'

# F2: a block must leave an audit line.
alog="$(mktemp -d)/audit.jsonl"
blocking_payload=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' "$sb/.shellcheckrc")
printf '%s' "$blocking_payload" | WORKFLOW_AUDIT_PATH="$alog" bash "$HOOK" >/dev/null 2>&1
if [ -s "$alog" ] && tail -n1 "$alog" | jq -e '.result=="block"' >/dev/null 2>&1; then
  echo "PASS: block audited"; pass=$((pass+1))
else
  echo "FAIL: no audit line on block"; fail=$((fail+1))
fi

t_summary
