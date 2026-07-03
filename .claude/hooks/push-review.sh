#!/usr/bin/env bash
# PreToolUse hook: shows diff summary before git push.
# Non-blocking: always exits 0. Injects diff stats into agent context.
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
hook_enabled "push-review" || exit 0
hook_read_input
[ "$TOOL_NAME" != "Bash" ] && exit 0
command=$(hook_command)
is_git_push "$command" || exit 0

audit_emit_warn push-review review_reminder
echo "=== Push Review ==="

# Canonical range (F3); empty range -> this hook's OWN policy: show last 5 commits.
range=$(unpushed_range)
if [ -n "$range" ]; then
  commits=$(git log --oneline "$range" 2>/dev/null || true)
  stats=$(git diff --stat "$range" 2>/dev/null || true)
else
  commits=$(printf '(no unpushed range — showing last 5 commits)\n%s' \
    "$(git log --oneline -5 2>/dev/null || echo '(not in a git repo)')")
  stats=$(git diff --stat HEAD~1..HEAD 2>/dev/null || echo "(could not determine changes)")
fi
echo "Commits:"
echo "$commits"
echo ""
echo "Changes:"
echo "$stats"

echo "==================="
exit 0
