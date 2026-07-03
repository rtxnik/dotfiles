#!/usr/bin/env bash
# PostToolUse(broad) hook: warn-only loop detector. Maintains a per-session ring buffer of
# `tool:hash(tool_input)` keys; if the same key recurs >= threshold within the window, it warns
# ONCE per loop (debounced via a .warned marker). Catches accidental spin-loops the 2-attempt
# budget can't see mechanically. Never blocks.
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
wf_reaper "${TMPDIR:-/tmp}" 'wf-toolloop-*.ring'
wf_reaper "${TMPDIR:-/tmp}" 'wf-toolloop-*.warned'
hook_enabled "tool-loop-guard" || exit 0
hook_read_input
[ -z "$TOOL_NAME" ] && exit 0

ti=$(echo "$INPUT" | jq -c '.tool_input // empty' 2>/dev/null)
[ -z "$ti" ] && exit 0
session=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && session="nosession"

threshold=$(cfg_int WORKFLOW_LOOP_THRESHOLD 5 2 1000)
window=$(cfg_int WORKFLOW_LOOP_WINDOW 20 1 1000)
safe=$(safe_slug "$session")
ring="${TMPDIR:-/tmp}/wf-toolloop-${safe}.ring"
warned="${TMPDIR:-/tmp}/wf-toolloop-${safe}.warned"

hash=$(printf '%s' "$ti" | cksum | tr -d ' \t\n')
key="${TOOL_NAME}:${hash}"

# Append key, then trim the ring to the last <window> lines.
printf '%s\n' "$key" >> "$ring" 2>/dev/null || exit 0
lines=$(wc -l < "$ring" 2>/dev/null) || lines=0
if [ "$lines" -gt "$window" ]; then
  tail -n "$window" "$ring" > "$ring.tmp" 2>/dev/null && mv -f "$ring.tmp" "$ring" 2>/dev/null
fi

count=$(grep -cxF -- "$key" "$ring" 2>/dev/null) || true
[ -z "$count" ] && count=0
last_warned=""
[ -f "$warned" ] && last_warned=$(cat "$warned" 2>/dev/null)

if [ "$count" -ge "$threshold" ] && [ "$key" != "$last_warned" ]; then
  printf '%s' "$key" > "$warned" 2>/dev/null || true
  audit_emit_warn tool-loop-guard loop_detected PostToolUse
  emit_additional_context PostToolUse "tool-loop-guard: the same $TOOL_NAME call has repeated $count times in the last $window tool uses — this looks like an accidental loop. STOP and rethink: change the input, try a different approach, or report the blocker instead of repeating. (Threshold WORKFLOW_LOOP_THRESHOLD=$threshold; disable with WORKFLOW_DISABLED_HOOKS=tool-loop-guard.)"
fi
exit 0
