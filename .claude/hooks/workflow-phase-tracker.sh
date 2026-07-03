#!/usr/bin/env bash
# PostToolUse hook: tracks workflow phase transitions when skills are invoked.
# Maintains state under .planning (git root, or walk-up to existing .planning) via hooklib.
# Always exits 0 (non-blocking).
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
hook_enabled "workflow-phase-tracker" || exit 0
hook_read_input
[ "$TOOL_NAME" != "Skill" ] && exit 0

skill=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')
[ -z "$skill" ] && exit 0

# Map skill name to phase
phase=""
if echo "$skill" | grep -q "brainstorming"; then
  phase="designing"
elif echo "$skill" | grep -q "writing-plans"; then
  phase="planning"
elif echo "$skill" | grep -qE "subagent-driven-development|executing-plans|polish-loop|optimization-loop|systematic-debugging"; then
  phase="executing"
elif echo "$skill" | grep -qE "code-review|requesting-code-review"; then
  phase="reviewing"
elif echo "$skill" | grep -q "finishing-a-development-branch"; then
  phase="complete"
elif echo "$skill" | grep -q "create-pr"; then
  phase="complete"
elif echo "$skill" | grep -q "graphify"; then
  phase="querying"
fi

[ -z "$phase" ] && exit 0

# graphify is a read-only query — never clobber an active workflow phase. Write the
# querying phase ONLY when no active workflow phase exists (D20 no-downgrade guard).
if [ "$phase" = "querying" ]; then
  cur=$(hook_phase)
  case "$cur" in ''|idle|complete|querying) ;; *) exit 0 ;; esac
fi

planning="$(planning_dir)" || exit 0   # not in a repo -> nothing to track (fail-open)
state="$(state_file)"
mkdir -p "$planning"

branch=$(git branch --show-current 2>/dev/null || echo "unknown")
[ -z "$branch" ] && branch="unknown"

started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
write_phase_state "$phase" "$branch" "$started_at" "$state"

if [ "$phase" = "executing" ]; then
  ledger="$(ledger_path)"
  [ -f "$ledger" ] || ledger_header > "$ledger"
  echo "Workflow: EXECUTING phase. LEDGER.tsv ready at .planning/LEDGER.tsv. Log every kept/discarded attempt."
elif [ "$phase" = "complete" ]; then
  echo "Workflow: COMPLETE. Record a claude-mem observation summarizing this feature before closing."
fi

exit 0
