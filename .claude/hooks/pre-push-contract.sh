#!/usr/bin/env bash
# PreToolUse hook: warns before git push when LEDGER.tsv has no entries on a tracked feature branch.
# Non-blocking: always exits 0.
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
hook_enabled "pre-push-contract" || exit 0
hook_read_input
[ "$TOOL_NAME" != "Bash" ] && exit 0

command=$(hook_command)
is_git_push "$command" || exit 0

push_branch=""
if echo "$command" | grep -qoP 'git\s+push\s+\S+\s+\K\S+'; then
  push_branch=$(echo "$command" | grep -oP 'git\s+push\s+\S+\s+\K\S+' | head -1)
fi
if [ -z "$push_branch" ]; then
  push_branch=$(git branch --show-current 2>/dev/null)
fi
[ -z "$push_branch" ] && exit 0
push_branch="${push_branch%%:*}"

if [ "$push_branch" = "main" ] || [ "$push_branch" = "master" ]; then
  exit 0
fi

phase=$(hook_phase)
if [ -z "$phase" ] || [ "$phase" = "idle" ]; then
  exit 0
fi

ledger=$(ledger_path)
stats=$(ledger_stats "$ledger")
total=$(ledger_rows "$ledger")

if [ "$total" -eq 0 ]; then
  audit_emit_warn pre-push-contract ledger_empty
  echo "WARNING: Pushing feature branch without LEDGER.tsv entries."
  echo "If this is a non-trivial change, update .planning/LEDGER.tsv before or after push."
  echo "For a genuinely trivial fix, disable this contract by exporting WORKFLOW_DISABLED_HOOKS=pre-push-contract in the launching env (settings.json env)."
  exit 0
fi

# P3 / Finding M: surface schema problems and the outcome balance. Warn-only — never blocks.
problems=$(ledger_validate "$ledger") || true
if [ -n "$problems" ]; then
  echo "WARNING: LEDGER.tsv schema problems (canonical: 5 TAB columns; outcome kept|discarded|dead-end):"
  echo "$problems"
fi
echo "LEDGER balance: $stats"
case "$stats" in
  *"discarded=0 dead-end=0")
    echo "Note: all-kept history — discards are data. Log reverted and dead-end attempts too." ;;
esac

# F4 / D4-2: advisory evidence cross-check. If this branch logged kept work but gate-evidence.log
# shows no observed passing gate run, the gate_result claims are unverified. Warn-only,
# branch-scoped (legacy rows out of scope via merge-base), fail-open. Missing log -> silent.
evid=$(gate_evidence_path 2>/dev/null) || evid=""
ref=$(git merge-base HEAD origin/main 2>/dev/null) || ref=""
[ -n "$ref" ] || ref=$(git merge-base HEAD origin/master 2>/dev/null) || ref=""
branch_rows=$(ledger_rows --since-ref "$ref" "$ledger")
if [ "${branch_rows:-0}" -gt 0 ] && [ -n "$evid" ] && [ -f "$evid" ]; then
  cur_branch=$(git branch --show-current 2>/dev/null || echo "")
  passes=$(jq -r --arg b "$cur_branch" 'select(.branch==$b and .status=="pass") | .status' "$evid" 2>/dev/null | grep -c . 2>/dev/null)
  if [ "${passes:-0}" -eq 0 ]; then
    echo "NOTE: this branch logged ${branch_rows} LEDGER row(s) but .planning/gate-evidence.log shows no observed passing gate run — verify the acceptance gate actually ran (evidence is advisory)."
    audit_emit_warn pre-push-contract gate_evidence_unmatched
  fi
fi

exit 0
