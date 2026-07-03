#!/usr/bin/env bash
# Planted-drift suite for scripts/integration-check.sh (gate-registry runner, SP-0).
# Drives the runner via the CHECK_ROOT seam against a fixture root with a
# .claude/gate-registry.json and stub scripts/check-integration-*.sh; never touches the real tree.
set -uo pipefail
SRC="$(cd "$(dirname "$0")/../.." && pwd)/scripts/integration-check.sh"
# shellcheck source=../lib/testlib.sh
source "$(cd "$(dirname "$0")/../lib" && pwd)/testlib.sh"
t_init

fixture() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude" "$d/scripts"
  printf '#!/usr/bin/env bash\necho alpha ok\nexit 0\n' > "$d/scripts/check-integration-alpha.sh"
  printf '#!/usr/bin/env bash\necho beta ok\nexit 0\n'  > "$d/scripts/check-integration-beta.sh"
  cat > "$d/.claude/gate-registry.json" <<'EOF'
{ "gates": [ "check-integration-alpha.sh", "check-integration-beta.sh" ] }
EOF
  printf '%s' "$d"
}

# clean -> 0
d=$(fixture); rc=0; CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1 || rc=$?
assert_rc "clean registry runs all listed gates and passes" 0 "$rc"; rm -rf "$d"

# present-but-unlisted -> 1 'does not match'
d=$(fixture); printf '#!/usr/bin/env bash\nexit 0\n' > "$d/scripts/check-integration-gamma.sh"
out=$(CHECK_ROOT="$d" bash "$SRC" 2>&1); rc=$?
assert_rc "unlisted on-disk gate fails" 1 "$rc"
assert_out_has "unlisted gate reported" "$out" "does not match"
rm -rf "$d"

# listed-but-missing -> 1 'missing'
d=$(fixture); rm -f "$d/scripts/check-integration-beta.sh"
out=$(CHECK_ROOT="$d" bash "$SRC" 2>&1); rc=$?
assert_rc "listed-but-missing gate fails" 1 "$rc"
assert_out_has "missing gate reported" "$out" "missing"
rm -rf "$d"

# a listed gate fails -> aggregated 1
d=$(fixture); printf '#!/usr/bin/env bash\necho boom\nexit 1\n' > "$d/scripts/check-integration-beta.sh"
rc=0; CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1 || rc=$?
assert_rc "a failing listed gate fails the run" 1 "$rc"; rm -rf "$d"

t_summary
