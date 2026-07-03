#!/usr/bin/env bash
# SessionStart hook: reconcile a stale workflow-state.json against the live git branch.
# If the recorded branch no longer matches the branch of the repo that owns the state file,
# the recorded phase drove enforcement for a DIFFERENT branch -> reset it to "idle" so no hook
# acts on stale phase. SessionStart cannot block.
# FAILURE-MODE: fail-open (always exit 0). Disable: export WORKFLOW_DISABLED_HOOKS=state-reconciler in the launching env (settings.json `env`).
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
hook_enabled "state-reconciler" || exit 0

sf=$(state_file 2>/dev/null) || exit 0
[ -n "$sf" ] && [ -f "$sf" ] || exit 0

recorded=$(jq -r '.branch // empty' "$sf" 2>/dev/null) || exit 0
[ -n "$recorded" ] || exit 0

# Branch of the repo that OWNS the state file (follows the .planning symlink), not the CWD —
# so reconciliation works even when the session starts at the non-repo workspace root.
state_dir=$(dirname "$(readlink -f "$sf" 2>/dev/null || echo "$sf")")
current=$(git -C "$state_dir" branch --show-current 2>/dev/null || echo "")
[ -n "$current" ] || exit 0                 # detached / not a repo -> cannot compare -> leave as-is
[ "$recorded" = "$current" ] && exit 0      # in sync -> nothing to do

started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
write_phase_state idle "$current" "$started_at" "$sf"
echo "Workflow: reset stale phase (recorded branch '$recorded' != current '$current'). Re-enter a skill to set the phase."
exit 0
