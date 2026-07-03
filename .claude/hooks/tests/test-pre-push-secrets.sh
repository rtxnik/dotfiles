#!/usr/bin/env bash
# Tests for pre-push-secrets.sh — throwaway git repo with a synthetic origin/main ref.
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(cd "$(dirname "$0")/.." && pwd)/pre-push-secrets.sh"
GHP_TOK="ghp_""ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij"   # assembled at runtime, never raw in source
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
(
  cd "$sandbox" && git init -q -b main &&
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base &&
  git update-ref refs/remotes/origin/main HEAD &&
  git checkout -q -b feat/x
)
run() {
  local name="$1" input="$2" expect="$3"  # warn|quiet
  out=$( cd "$sandbox" && echo "$input" | CLAUDE_PROJECT_DIR="$sandbox" bash "$HOOK" 2>&1 ) || true
  got=quiet; echo "$out" | grep -q 'WARNING' && got=warn
  if [ "$got" = "$expect" ]; then echo "PASS: $name"; pass=$((pass+1));
  else echo "FAIL: $name (got $got, out: $out)"; fail=$((fail+1)); fi
}
# Checks exit code and that output matches a grep pattern.
run_tiered() {
  local name="$1" input="$2" expect_exit="$3" expect_pattern="$4"
  actual_exit=0
  out=$( cd "$sandbox" && echo "$input" | CLAUDE_PROJECT_DIR="$sandbox" bash "$HOOK" 2>&1 ) || actual_exit=$?
  local pat_ok=0; echo "$out" | grep -q "$expect_pattern" && pat_ok=1
  if [ "$actual_exit" -eq "$expect_exit" ] && [ "$pat_ok" -eq 1 ]; then
    echo "PASS: $name"; pass=$((pass+1))
  else
    echo "FAIL: $name (exit=$actual_exit want $expect_exit, pattern='$expect_pattern' found=$pat_ok, out: $out)"
    fail=$((fail+1))
  fi
}
push='{"tool_name":"Bash","tool_input":{"command":"git push origin feat/x"}}'

run "non-push quiet" '{"tool_name":"Bash","tool_input":{"command":"git status"}}' quiet
run "clean range quiet" "$push" quiet

( cd "$sandbox" && printf 'TOKEN=%s\n' "$GHP_TOK" > leak.txt &&
  git add leak.txt && git -c user.email=t@t -c user.name=t commit -q -m leak )
# ghp_ tokens are high-confidence: the hook now BLOCKS (exit 2).
run_tiered "leaked token in pushed range blocks" "$push" 2 '\[BLOCKED\]'

( cd "$sandbox" && git rm -q leak.txt && mkdir -p .claude/hooks/tests &&
  printf 'TOKEN=%s\n' "$GHP_TOK" > .claude/hooks/tests/fixture.txt &&
  git add .claude/hooks/tests/fixture.txt && git -c user.email=t@t -c user.name=t commit -q -m fixtures )
run "scanner fixtures dir is exempt" "$push" quiet

# --- Tier-split cases (D2-2) -------------------------------------------
# (a) High-confidence match in pushed range -> BLOCK (exit 2)
( cd "$sandbox" && printf 'aws_key = AKIA%s\n' 'IOSFODNN7EXAMPLE' > leak_hi.txt &&
  git add leak_hi.txt && git -c user.email=t@t -c user.name=t commit -q -m leak_hi )
run_tiered "high-confidence match blocks (exit 2)" "$push" 2 '\[BLOCKED\]'
run_tiered "high-confidence match output HIGH-CONFIDENCE" "$push" 2 'HIGH-CONFIDENCE'

# (b) Heuristic-only match -> WARN (exit 0)
( cd "$sandbox" && git rm -q leak_hi.txt &&
  printf 'password: "%s"\n' 'correcthorsebatterystaple' > cfg_heur.yaml &&
  git add cfg_heur.yaml && git -c user.email=t@t -c user.name=t commit -q -m heur_only )
run_tiered "heuristic-only match warns (exit 0)" "$push" 0 'WARNING'
run_tiered "heuristic-only match output heuristic" "$push" 0 'heuristic'

# --- F3 / D5-1: batched gitleaks layer catches classes the floor misses ---
AGE_TKN="AGE-SECRET-KEY-1$(printf 'Q%.0s' $(seq 1 58))"
if command -v gitleaks >/dev/null 2>&1; then
  ( cd "$sandbox" && printf 'k=%s\n' "$AGE_TKN" > age.txt &&
    git add age.txt && git -c user.email=t@t -c user.name=t commit -q -m age )
  run_tiered "gitleaks layer blocks age-key class" "$push" 2 'gitleaks layer'
  ( cd "$sandbox" && git rm -q age.txt && git -c user.email=t@t -c user.name=t commit -q -m drop-age )
else
  echo "SKIP: gitleaks not on PATH — batched layer case skipped"
fi

# F3: the sandbox has NO upstream — the scan above only works because of the
# origin/main fallback. Pin that the fallback now comes from unpushed_range:
# a repo with no origin refs at all must skip quietly (empty range policy).
noorigin=$(mktemp -d)
( cd "$noorigin" && git init -q -b main &&
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base &&
  git checkout -q -b feat/y &&
  printf 'TOKEN=%s\n' "$GHP_TOK" > leak2.txt && git add leak2.txt &&
  git -c user.email=t@t -c user.name=t commit -q -m leak2 )
rc=0
out=$( cd "$noorigin" && echo "$push" | CLAUDE_PROJECT_DIR="$noorigin" bash "$HOOK" 2>&1 ) || rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then echo "PASS: no-origin repo skips quietly"; pass=$((pass+1));
else echo "FAIL: no-origin repo (exit=$rc out=$out)"; fail=$((fail+1)); fi
rm -rf "$noorigin"

t_summary
