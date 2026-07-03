#!/usr/bin/env bash
# PreToolUse hook: injects context into Agent dispatches.
#  - reviewer dispatch (ANY phase): injects .claude/review-rubric.md (U3 — rubric mechanically delivered)
#  - any other Agent dispatch while phase=executing: injects Karpathy discipline
# Non-blocking: always exits 0.
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
hook_read_input
[ "$TOOL_NAME" != "Agent" ] && exit 0

# Reviewer dispatch? Markers from the superpowers code-reviewer.md template
# ("Senior Code Reviewer" persona; "Ready to merge" verdict block). A reviewer
# gets the review rubric, never the mutation discipline.
prompt=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)
if echo "$prompt" | grep -qi 'senior code reviewer' && echo "$prompt" | grep -qi 'ready to merge'; then
  cat "$(dirname "$0")/../review-rubric.md"
  exit 0
fi

# Finding P: discipline injection is disableable like every sibling. The gate sits
# BELOW the rubric branch on purpose — disabling this hook must not silence the
# one-review-path rubric delivery (P2/U3 mechanism).
hook_enabled "subagent-discipline" || exit 0

[ "$(hook_phase)" = "executing" ] || exit 0
cat "$(dirname "$0")/../discipline.md"
exit 0
