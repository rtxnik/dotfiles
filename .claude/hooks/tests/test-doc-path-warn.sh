#!/usr/bin/env bash
# Tests for doc-path-warn.sh (warn-only via additionalContext)
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(cd "$(dirname "$0")/.." && pwd)/doc-path-warn.sh"

# stdout for a Write to $1 (empty => no warn), optional env in $2..
emit() { # filepath [ENV=val...]
  local fp="$1"; shift
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$fp" \
    | ( env "$@" bash "$HOOK" 2>/dev/null )
}

ok "warns on findings.md"        '[ -n "$(emit findings.md)" ]'
ok "warns on SUMMARY.md (case)"  '[ -n "$(emit SUMMARY.md)" ]'
ok "warns on notes.txt"          '[ -n "$(emit scratch/notes.txt)" ]'
ok "warn is additionalContext"   'emit report.md | jq -e .hookSpecificOutput.additionalContext >/dev/null'

ok "no warn on real spec"        '[ -z "$(emit docs/superpowers/specs/2026-06-02-foo-design.md)" ]'
ok "no warn on plan"             '[ -z "$(emit docs/superpowers/plans/2026-06-02-foo.md)" ]'
ok "no warn in .planning"        '[ -z "$(emit .planning/notes.md)" ]'
ok "no warn on DECISIONS.md"     '[ -z "$(emit DECISIONS.md)" ]'
ok "no warn on quarterly-summary.md (narrow stem)" '[ -z "$(emit quarterly-summary.md)" ]'
ok "no warn on source file"      '[ -z "$(emit src/main.go)" ]'
ok "disabled -> silent"          '[ -z "$(emit findings.md WORKFLOW_DISABLED_HOOKS=doc-path-warn)" ]'

# F2: a warn must leave an audit line.
alog="$(mktemp -d)/audit.jsonl"
printf '{"tool_name":"Write","tool_input":{"file_path":"findings.md","content":"x"}}' \
  | WORKFLOW_AUDIT_PATH="$alog" bash "$HOOK" >/dev/null 2>&1 || true
if [ -s "$alog" ] && tail -n1 "$alog" | jq -e '.result=="warn"' >/dev/null 2>&1; then
  echo "PASS: warn audited"; pass=$((pass+1))
else
  echo "FAIL: no audit line on warn"; fail=$((fail+1))
fi

t_summary
