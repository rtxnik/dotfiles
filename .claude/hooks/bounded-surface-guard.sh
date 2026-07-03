#!/usr/bin/env bash
# PostToolUse(Edit|Write) hook: warn-only. Tracks the set of distinct files mutated in the
# current session+branch and warns when it exceeds the bounded-surface rule (<=4). The set
# RESETS automatically when HEAD changes (commit detected), keyed by session+branch. Never
# blocks (a plan-approved wide change must not be wedged).
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
wf_reaper "${TMPDIR:-/tmp}" 'wf-surface-*.list'
hook_enabled "bounded-surface-guard" || exit 0
hook_read_input
case "$TOOL_NAME" in Edit|Write) ;; *) exit 0 ;; esac

file_path=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file_path" ] && exit 0

# Doc/planning/audit artifacts are not part of a CODE-change surface — never count them.
case "$file_path" in
  */docs/*|docs/*|*/.planning/*|.planning/*|*/PATHFINDER-*/*|PATHFINDER-*/*|*.md) exit 0 ;;
esac

session=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && session="nosession"
branch=$(git branch --show-current 2>/dev/null || echo "nobranch")
[ -z "$branch" ] && branch="nobranch"
head=$(git rev-parse HEAD 2>/dev/null) || head="NOHEAD"
max=$(cfg_int WORKFLOW_SURFACE_MAX 4 1 100)

safe=$(safe_slug "$session|$branch")
set_file="${TMPDIR:-/tmp}/wf-surface-${safe}.list"

# Reset on commit detection: line 1 stores the HEAD at last reset.
stored_head=""
[ -f "$set_file" ] && stored_head=$(head -n1 "$set_file" 2>/dev/null)
if [ "$stored_head" != "$head" ]; then
  printf '%s\n' "$head" > "$set_file" 2>/dev/null || exit 0   # reset; fail-open on write error
fi

# Already counted this file? -> no change, no warn.
grep -qxF -- "$file_path" "$set_file" 2>/dev/null && exit 0
printf '%s\n' "$file_path" >> "$set_file" 2>/dev/null || exit 0

# Distinct files = lines after the HEAD header.
total=$(wc -l < "$set_file" 2>/dev/null) || total=1
count=$(( total - 1 ))
if [ "$count" -gt "$max" ]; then
  audit_emit_warn bounded-surface-guard surface_exceeded PostToolUse
  emit_additional_context PostToolUse "bounded-surface-guard: this session+branch ($branch) has now mutated $count distinct files, over the bounded-surface rule of <=$max. If this is a plan-approved wide change, continue; otherwise STOP and re-scope to <=$max files (the set resets on your next commit). Disable with WORKFLOW_DISABLED_HOOKS=bounded-surface-guard."
fi
exit 0
