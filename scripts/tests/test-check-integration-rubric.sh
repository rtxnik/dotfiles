#!/usr/bin/env bash
set -uo pipefail
SRC="$(cd "$(dirname "$0")/../.." && pwd)/scripts/check-integration-rubric.sh"
# shellcheck source=../lib/testlib.sh
source "$(cd "$(dirname "$0")/../lib" && pwd)/testlib.sh"
t_init
fixture() { # echoes a CHECK_ROOT with a valid rubric + CLAUDE.md reference
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude"
  echo "rubric body" > "$d/.claude/review-rubric.md"
  echo "see .claude/review-rubric.md for the review rubric" > "$d/CLAUDE.md"
  printf '%s' "$d"
}
# clean -> 0
d=$(fixture); rc=0; CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1 || rc=$?
assert_rc "clean rubric passes" 0 "$rc"; rm -rf "$d"
# drift: rubric missing -> 1
d=$(fixture); rm -f "$d/.claude/review-rubric.md"; rc=0; CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1 || rc=$?
assert_rc "missing rubric fails" 1 "$rc"; rm -rf "$d"
# drift: CLAUDE.md no longer references the rubric -> 1
d=$(fixture); echo "no mention here" > "$d/CLAUDE.md"; rc=0; CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1 || rc=$?
assert_rc "unreferenced rubric fails" 1 "$rc"; rm -rf "$d"
t_summary
