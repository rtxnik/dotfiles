#!/usr/bin/env bash
# shellcheck disable=SC2154  # pass/fail set by ck_init (lib/check.sh)
# check-integration-merge-markers.sh — floor gate (ships to consumers). Refuses unresolved
# merge conflict markers / *.rej left by a `factory update` three-way merge (spec §7).
# bash + git only (no external deps — floor-compatible). Honors the CHECK_ROOT seam.
set -uo pipefail
# shellcheck source=lib/check.sh
. "$(cd "$(dirname "$0")/lib" && pwd)/check.sh"
ROOT="${CHECK_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
ck_init
cd "$ROOT" || { ck_fail "cannot cd to $ROOT"; exit 1; }

# Key ONLY on the unambiguous opener/closer markers (both carry a trailing space); a lone
# 7-equals separator line is NOT flagged (avoids false positives on docs/tables — L4). A real
# conflict always has the <<<<<<< opener.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  hits="$(git grep -lE '^(<{7} |>{7} )' -- . 2>/dev/null || true)"
else
  hits="$(grep -rlE '^(<{7} |>{7} )' . 2>/dev/null || true)"
fi
if [ -n "$hits" ]; then
  while IFS= read -r f; do [ -n "$f" ] && ck_fail "unresolved merge conflict markers: $f"; done <<< "$hits"
fi

# Reject leftover *.rej files anywhere tracked.
rejs="$(git ls-files '*.rej' 2>/dev/null || true)"
if [ -n "$rejs" ]; then
  while IFS= read -r f; do [ -n "$f" ] && ck_fail "merge reject file present: $f"; done <<< "$rejs"
fi

ck_pass "no unresolved merge markers"
if [ "$fail" -eq 0 ]; then echo "Results: merge-markers OK"; else exit 1; fi
