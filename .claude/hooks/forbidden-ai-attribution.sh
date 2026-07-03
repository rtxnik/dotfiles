#!/usr/bin/env bash
# PreToolUse hook: blocks git commit/push and gh PR comment/review text with AI attribution.
# Exit 0 = allow. Exit 2 = block.
# Scope (F3): `gh pr create` bodies stay UNSCANNED by accepted decision (D1-5) — PR
# bodies are owner-reviewed surfaces with their own neutral-language policy. Assumes
# cwd == the repo being pushed; `git -C <dir>` / `cd X && git push` compound forms
# are out of scope (D1-1, accepted — layered gates, not shell parsing). Editor
# commits (no -m/-F) are covered at push time via unpushed_range.
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
hook_read_input
[ "$TOOL_NAME" != "Bash" ] && exit 0

command=$(hook_command)
is_git_commit "$command" || is_git_push "$command" || is_gh_pr_text "$command" || exit 0

# git commit: scan the command string AND any -F/--file message payload (D1-2).
# Path extraction is best-effort (quoted, then bare; attached -Ffile not parsed);
# whatever slips through is caught by the push-time scan below.
commit_payload=""
if is_git_commit "$command"; then
  cf=$(echo "$command" | sed -nE 's/.*--file[= ]"([^"]+)".*/\1/p')
  [ -z "$cf" ] && cf=$(echo "$command" | sed -nE 's/.*--file[= ]([^[:space:]"]+).*/\1/p')
  [ -z "$cf" ] && cf=$(echo "$command" | sed -nE 's/.*[[:space:]]-F[[:space:]]+"([^"]+)".*/\1/p')
  [ -z "$cf" ] && cf=$(echo "$command" | sed -nE 's/.*[[:space:]]-F[[:space:]]+([^[:space:]"]+).*/\1/p')
  [ "$cf" = "-" ] && cf=""   # stdin payload (heredoc) is already in the command string
  [ -n "$cf" ] && [ -f "$cf" ] && commit_payload=$(cat "$cf" 2>/dev/null)
  if is_ai_attribution "$command" || { [ -n "$commit_payload" ] && is_ai_attribution "$commit_payload"; }; then
    echo "[BLOCKED] AI attribution in commit message. Policy: no AI mentions in commits/code/docs."
    audit_emit_block forbidden-ai-attribution commit_attribution
    exit 2
  fi
fi

# git push: scan unpushed commit messages over the canonical range (F3 / D1-2 —
# the origin fallback inside unpushed_range makes a branch's FIRST push scannable).
unpushed=""
if is_git_push "$command"; then
  range=$(unpushed_range)
  [ -n "$range" ] && unpushed=$(git log --format='%s%n%b' "$range" 2>/dev/null || echo "")
  if [ -n "$unpushed" ] && is_ai_attribution "$unpushed"; then
    echo "[BLOCKED] AI attribution found in unpushed commits. Amend or rebase to remove before pushing."
    audit_emit_block forbidden-ai-attribution unpushed_attribution
    exit 2
  fi
fi

# gh PR-thread text (comment / review / api comments): scan the command text
# and any --body-file / body=@file payload.
gh_body=""
if is_gh_pr_text "$command"; then
  # Quoted path first (captures interior spaces); then unquoted/whitespace-delimited.
  bf=$(echo "$command" | sed -nE 's/.*--body-file[= ]"([^"]+)".*/\1/p')
  [ -z "$bf" ] && bf=$(echo "$command" | sed -nE 's/.*--body-file[= ]([^[:space:]"]+).*/\1/p')
  [ -z "$bf" ] && bf=$(echo "$command" | sed -nE 's/.*body=@"([^"]+)".*/\1/p')
  [ -z "$bf" ] && bf=$(echo "$command" | sed -nE 's/.*body=@([^[:space:]"]+).*/\1/p')
  [ -n "$bf" ] && [ -f "$bf" ] && gh_body=$(cat "$bf" 2>/dev/null)
  if is_ai_attribution "$command" || { [ -n "$gh_body" ] && is_ai_attribution "$gh_body"; }; then
    echo "[BLOCKED] AI attribution in PR comment/review text. Policy: no AI mentions in commits/code/docs."
    audit_emit_block forbidden-ai-attribution pr_text_attribution
    exit 2
  fi
fi

# Public repos: also block attribution-shaped hints (unless explicitly allowed)
if [ "$(repo_visibility)" = "public" ] && ! ai_mentions_allowed; then
  if { is_git_commit "$command" && { is_ai_hint "$command" || { [ -n "$commit_payload" ] && is_ai_hint "$commit_payload"; }; }; } || { is_git_push "$command" && [ -n "${unpushed:-}" ] && is_ai_hint "$unpushed"; } \
     || { is_gh_pr_text "$command" && { is_ai_hint "$command" || { [ -n "$gh_body" ] && is_ai_hint "$gh_body"; }; }; }; then
    echo "[BLOCKED] AI hint in a public repo. Remove it, or add a .ai-mentions-allowed marker if legitimate."
    audit_emit_block forbidden-ai-attribution public_ai_hint
    exit 2
  fi
fi

exit 0
