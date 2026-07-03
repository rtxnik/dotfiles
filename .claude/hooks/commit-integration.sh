#!/usr/bin/env bash
# PostToolUse hook: detects git commits and reminds to update LEDGER + claude-mem.
# Non-blocking: always exits 0. Outputs reminder to agent context.
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
hook_enabled "commit-integration" || exit 0
hook_read_input
[ "$TOOL_NAME" != "Bash" ] && exit 0

stdout=$(echo "$INPUT" | jq -r '.tool_response.stdout // .tool_result.stdout // empty')
[ -z "$stdout" ] && exit 0

echo "$stdout" | grep -qE '^\[.* [a-f0-9]{7,}\]' || exit 0

[ "$(hook_phase)" = "executing" ] || exit 0

echo "COMMIT DETECTED — integration actions required:
1. LEDGER: Append a row to .planning/LEDGER.tsv with: timestamp, changed files, outcome (kept/discarded/dead-end), gate result
2. OBSERVATION: If this completes a plan task, record a claude-mem observation summarizing what was done"

# F4 / D6-3: revert/rollback advisory. A revert is an OUTCOME, not a non-event — nudge logging it
# as discarded/dead-end so the all-kept history stops hiding the discards. Advisory only (no gate).
command=$(hook_command)
if echo "$stdout" | grep -qiE '^\[[^]]*\][[:space:]]+revert|this reverts commit' \
   || echo "$command" | grep -qE 'git[[:space:]]+revert'; then
  echo "REVERT DETECTED — a revert is data, not an erasure:
3. Log the reverted attempt in .planning/LEDGER.tsv with outcome=discarded (or dead-end if the approach is a conceptual dead end), naming what was undone in notes."
  audit_emit_warn commit-integration revert_advisory PostToolUse
fi

exit 0
