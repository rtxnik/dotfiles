#!/usr/bin/env bash
# Tests for state-reconciler.sh — reset stale phase on branch mismatch.
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(cd "$(dirname "$0")/.." && pwd)/state-reconciler.sh"

repo=$(mktemp -d); ( cd "$repo" && git init -q && git checkout -q -b feature/live )
mkdir -p "$repo/.planning"
phase_of() { jq -r '.phase' "$repo/.planning/workflow-state.json"; }

# Mismatch: recorded branch != current -> phase reset to idle.
echo '{"phase":"executing","branch":"old-branch","started_at":"x"}' > "$repo/.planning/workflow-state.json"
( cd "$repo" && echo '{"source":"startup"}' | bash "$HOOK" >/dev/null 2>&1 )
ok "stale branch -> phase reset to idle" '[ "$(phase_of)" = "idle" ]'
ok "stale branch -> branch updated to current" '[ "$(jq -r .branch "$repo/.planning/workflow-state.json")" = "feature/live" ]'

# Match: recorded branch == current -> untouched.
echo '{"phase":"executing","branch":"feature/live","started_at":"x"}' > "$repo/.planning/workflow-state.json"
( cd "$repo" && echo '{"source":"startup"}' | bash "$HOOK" >/dev/null 2>&1 )
ok "matching branch -> phase preserved" '[ "$(phase_of)" = "executing" ]'

# No state file -> no error, exit 0.
rm -f "$repo/.planning/workflow-state.json"
rc=0; ( cd "$repo" && echo '{"source":"startup"}' | bash "$HOOK" >/dev/null 2>&1 ) || rc=$?
ok "missing state -> exit 0" '[ "$rc" = "0" ]'

rm -rf "$repo"
t_summary
