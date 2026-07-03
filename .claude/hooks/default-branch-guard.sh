#!/usr/bin/env bash
# PreToolUse(Bash) hook: blocks `git commit` while on the default branch (main/master).
# Stateless — inspects only the current command + current branch. No cross-invocation state.
# Exit 0 = allow. Exit 2 = block. Fail-open: any detection error / unknown branch -> exit 0.
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
hook_enabled "default-branch-guard" || exit 0
hook_read_input
[ "$TOOL_NAME" != "Bash" ] && exit 0

command=$(hook_command)
is_git_commit "$command" || exit 0

branch=$(git branch --show-current 2>/dev/null) || exit 0
[ -z "$branch" ] && exit 0   # detached HEAD / not a repo -> cannot determine -> allow

case "$branch" in
  main|master)
    echo "[BLOCKED] git commit on the default branch '$branch'. Create a feature branch first:"
    echo "  git switch -c feature/<short-name>   # then re-run your commit"
    echo "(Override: export WORKFLOW_DISABLED_HOOKS=default-branch-guard in the launching env (settings.json env).)"
    audit_emit_block default-branch-guard default_branch_commit
    exit 2
    ;;
esac
exit 0
