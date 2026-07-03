#!/usr/bin/env bash
# PreToolUse hook: warns when Write targets >500 lines.
# Non-blocking: always exits 0. Outputs warning to agent context.
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
hook_enabled "large-file-guard" || exit 0   # pinned: always true — pin exercised (Finding Q)
hook_read_input
[ "$TOOL_NAME" != "Write" ] && exit 0
content=$(hook_content)
[ -z "$content" ] && exit 0
file_path=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
line_count=$(echo "$content" | wc -l | tr -d ' ')
if [ "$line_count" -gt 500 ]; then
  audit_emit_warn large-file-guard large_file
  echo "[WARNING] Writing $line_count lines to $file_path. Files >500 lines may be doing too much — consider splitting with /polish-loop."
fi

# Public repos: warn on attribution-shaped AI hints in written content
if [ "$(repo_visibility)" = "public" ] && ! ai_mentions_allowed && is_ai_hint "$content"; then
  echo "[WARNING] Content contains an AI hint and this is a public repo. Remove it before committing, or add a .ai-mentions-allowed marker."
fi

exit 0
