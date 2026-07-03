#!/usr/bin/env bash
# PreToolUse hook: blocks Edit/Write that INTRODUCE secret patterns.
#  - Write: full content scanned (unchanged behavior).
#  - Edit: post-edit file content is simulated in-process; the MULTISET of
#    matches before vs after is diffed and any net-new occurrence blocks
#    (delta scan, Finding J). Removing or replacing a secret with a non-secret
#    is never blocked; a different secret value, a duplicated copy, or one
#    assembled across the edit boundary is caught; fixture-bearing files stay
#    editable (their existing matches are not net-new).
#    Engine (F3 / D5-1): matches come from the hybrid secret_matches — builtin
#    floor + gitleaks layer when gitleaks is on PATH (fail-open to the floor,
#    audited). Cost: the delta scan pays ~2 gitleaks spawns (~1.3s) per Edit;
#    WORKFLOW_SECRETS_GITLEAKS=off restores floor-only speed. Bash-authored
#    writes are covered by worktree-secrets-scan.sh.
# Exit 0 = allow. Exit 2 = block (stdout shown to agent).
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
hook_enabled "secrets-scan" || exit 0   # pinned: always true — pin exercised (Finding Q)
hook_read_input
case "$TOOL_NAME" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

content=$(hook_content)   # Write: content; Edit: new_string (used for the AI-hint check)

found=""
if [ "$TOOL_NAME" = "Write" ]; then
  [ -z "$content" ] && exit 0
  found=$(printf '%s' "$content" | secret_matches | sort -u)
else
  file_path=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  old_string=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null)
  new_string=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
  replace_all=$(echo "$INPUT" | jq -r '.tool_input.replace_all // false' 2>/dev/null)
  [ -z "$new_string" ] && exit 0
  pre=""
  if [ -n "$file_path" ] && [ -f "$file_path" ] && [ -r "$file_path" ]; then
    pre=$(cat "$file_path" 2>/dev/null) || pre=""
  fi
  if [ -z "$pre" ] || [ -z "$old_string" ]; then
    post="$new_string"   # no pre-image to diff against: scan the new text alone
  elif [ "$replace_all" = "true" ]; then
    post="${pre//"$old_string"/$new_string}"
  else
    post="${pre/"$old_string"/$new_string}"
  fi
  # Block only matches that are new relative to the pre-edit content (multiset diff).
  found=$(comm -13 \
    <(printf '%s' "$pre"  | secret_matches | sort) \
    <(printf '%s' "$post" | secret_matches | sort) | sed '/^$/d' | sort -u)
fi

if [ -n "$found" ]; then
  echo "[BLOCKED] Secret pattern detected (introduced by this $TOOL_NAME):"
  echo "  ${found//$'\n'/$'\n'  }"
  echo "Remove the secret and use environment variables or a secrets manager instead."
  audit_emit_block secrets-scan secret_match
  exit 2
fi

# Public repos: block attribution-shaped AI hints in written content
if [ -n "$content" ] && [ "$(repo_visibility)" = "public" ] && ! ai_mentions_allowed && is_ai_hint "$content"; then
  echo "[BLOCKED] AI hint in content for a public repo. Remove it, or add a .ai-mentions-allowed marker if legitimate."
  audit_emit_block secrets-scan public_ai_hint
  exit 2
fi

exit 0
