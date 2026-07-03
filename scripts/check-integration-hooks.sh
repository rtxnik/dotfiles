#!/usr/bin/env bash
# shellcheck disable=SC2154  # pass/fail are set in the caller's scope by ck_init (lib/check.sh)
# Asserts EVERY hook script in .claude/hooks/*.sh is wired into settings.json
# (or explicitly allowlisted as deliberately unwired) and has a test file
# tests/test-<hook>.sh. Generalized from the fixed Phase-3 five-hook list
# (PATHFINDER-2026-06-10 D3-3: deregistering an unlisted hook passed every gate).
set -uo pipefail
# shellcheck source=lib/check.sh
source "$(cd "$(dirname "$0")/lib" && pwd)/check.sh"
ck_init
ROOT="${CHECK_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
settings="$ROOT/.claude/settings.json"
hooks_dir="$ROOT/.claude/hooks"

# Hooks deliberately NOT registered in settings.json. Keep empty unless a hook
# is intentionally unwired — add it here together with a reason comment.
UNWIRED_ALLOWLIST=()

if python3 -c "import json; json.load(open('$settings'))" 2>/dev/null; then
  ck_pass "settings.json is valid JSON"
else
  echo "FAIL: settings.json is not valid JSON"
  exit 1
fi

count=0
for f in "$hooks_dir"/*.sh; do
  h="$(basename "$f" .sh)"
  count=$((count + 1))
  allowlisted=0
  for u in ${UNWIRED_ALLOWLIST[@]+"${UNWIRED_ALLOWLIST[@]}"}; do
    [ "$u" = "$h" ] && allowlisted=1
  done
  if grep -q "$h.sh" "$settings"; then
    ck_pass "$h wired in settings.json"
    if [ "$allowlisted" -eq 1 ]; then
      ck_fail "$h is wired but also in UNWIRED_ALLOWLIST — remove one"
    fi
  elif [ "$allowlisted" -eq 1 ]; then
    ck_pass "$h deliberately unwired (allowlisted)"
  else
    ck_fail "$h not wired in settings.json (allowlist it only if deliberate)"
  fi
  if [ -f "$hooks_dir/tests/test-$h.sh" ]; then
    ck_pass "test-$h.sh present"
  else
    ck_fail "test-$h.sh missing"
  fi
done

# Drift gate: the committed .claude/hooks/README.md MUST equal a fresh generator run.
# Use $ROOT for BOTH paths so the gate cannot pass vacuously from a non-root cwd; if the
# generator is missing, HARD FAIL (never skip silently).
if [ -f "$ROOT/scripts/gen-hooks-readme.sh" ]; then
  tmp=$(mktemp)
  if bash "$ROOT/scripts/gen-hooks-readme.sh" > "$tmp" 2>/dev/null && diff -q "$tmp" "$ROOT/.claude/hooks/README.md" >/dev/null 2>&1; then
    ck_pass "hooks README matches generator"
  else
    ck_fail ".claude/hooks/README.md is stale — run: bash scripts/gen-hooks-readme.sh > .claude/hooks/README.md"
  fi
  rm -f "$tmp"
else
  ck_fail "scripts/gen-hooks-readme.sh missing — README cannot be drift-gated"
fi

if [ "$fail" -eq 0 ]; then
  echo "Results: all $count hooks present, wired-or-allowlisted, tested"
else
  echo "Results: FAILED"
  exit 1
fi
