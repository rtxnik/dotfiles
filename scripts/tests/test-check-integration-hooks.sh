#!/usr/bin/env bash
# Planted-drift suite for scripts/check-integration-hooks.sh (F7 / D3-2).
# Approach: FULL README fixture. We build a small fixture .claude tree (a minimal
# hooklib stub + settings.json wiring 2 stub hooks + matching hooks/<h>.sh and
# tests/test-<h>.sh) AND copy the real scripts/gen-hooks-readme.sh into the fixture,
# then generate the README into the fixture so the README drift-gate passes on the
# clean case. The gate is driven via the CHECK_ROOT seam; the real .claude tree is
# never touched (fixtures are mktemp copies).
set -uo pipefail
SRC="$(cd "$(dirname "$0")/../.." && pwd)/scripts/check-integration-hooks.sh"
GEN="$(cd "$(dirname "$0")/../.." && pwd)/scripts/gen-hooks-readme.sh"
# shellcheck source=../lib/testlib.sh
source "$(cd "$(dirname "$0")/../lib" && pwd)/testlib.sh"
t_init

# fixture : build a fresh CHECK_ROOT with 2 stub hooks (alpha pinned/block, beta
# non-pinned/warn) wired into settings.json, matching test files, a copy of the real
# generator, and a freshly generated README. Echoes the fixture root.
fixture() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude/hooks/lib" "$d/.claude/hooks/tests" "$d/scripts"
  cat > "$d/.claude/hooks/lib/hooklib.sh" <<'EOF'
#!/usr/bin/env bash
HOOK_IDS="alpha-hook beta-hook"
HOOK_PINNED="alpha-hook"
HOOK_FAILCLOSED=""
hook_ids() { printf '%s\n' $HOOK_IDS; }
EOF
  printf '#!/usr/bin/env bash\nexit 2\n' > "$d/.claude/hooks/alpha-hook.sh"
  printf '#!/usr/bin/env bash\necho "WARNING: advisory"\n' > "$d/.claude/hooks/beta-hook.sh"
  printf '#!/usr/bin/env bash\necho ok\n' > "$d/.claude/hooks/tests/test-alpha-hook.sh"
  printf '#!/usr/bin/env bash\necho ok\n' > "$d/.claude/hooks/tests/test-beta-hook.sh"
  cat > "$d/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/alpha-hook.sh\"" } ] }
    ],
    "PostToolUse": [
      { "matcher": "Edit", "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/beta-hook.sh\"" } ] }
    ]
  }
}
EOF
  cp "$GEN" "$d/scripts/gen-hooks-readme.sh"
  bash "$d/scripts/gen-hooks-readme.sh" > "$d/.claude/hooks/README.md" 2>/dev/null
  printf '%s' "$d"
}

# clean -> 0
d=$(fixture); rc=0; CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1 || rc=$?
assert_rc "clean hooks fixture passes" 0 "$rc"; rm -rf "$d"

# drift: delete beta-hook's command line from settings.json (leave beta-hook.sh present) -> 1 'not wired'
d=$(fixture)
python3 - "$d/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]; data = json.load(open(p))
data["hooks"]["PostToolUse"] = []   # drop the beta-hook wiring; beta-hook.sh stays present
json.dump(data, open(p, "w"))
PY
out=$(CHECK_ROOT="$d" bash "$SRC" 2>&1); rc=0; CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1 || rc=$?
assert_rc "unwired hook fails" 1 "$rc"
assert_out_has "unwired hook reported 'not wired'" "$out" "not wired"
rm -rf "$d"

# drift: delete one tests/test-<h>.sh -> 1 'missing'
d=$(fixture); rm -f "$d/.claude/hooks/tests/test-beta-hook.sh"
out=$(CHECK_ROOT="$d" bash "$SRC" 2>&1); rc=0; CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1 || rc=$?
assert_rc "missing test file fails" 1 "$rc"
assert_out_has "missing test file reported 'missing'" "$out" "missing"
rm -rf "$d"

# drift: corrupt settings.json (invalid JSON) -> 1
d=$(fixture); printf '{ not valid json' > "$d/.claude/settings.json"
out=$(CHECK_ROOT="$d" bash "$SRC" 2>&1); rc=0; CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1 || rc=$?
assert_rc "invalid JSON fails" 1 "$rc"
assert_out_has "invalid JSON reported" "$out" "not valid JSON"
rm -rf "$d"

t_summary
