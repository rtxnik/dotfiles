#!/usr/bin/env bash
# Tests for worktree-secrets-scan.sh — PostToolUse(Bash) working-tree delta scan (F3/D1-3).
# Each scenario gets a FRESH TMPDIR (the hook keys its baseline+cache off TMPDIR).
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(cd "$(dirname "$0")/.." && pwd)/worktree-secrets-scan.sh"
GHP_TOK="ghp_""ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij"
BASH_CALL='{"tool_name":"Bash","tool_input":{"command":"echo done"},"session_id":"t"}'

mkrepo() {  # $1 = dir
  ( cd "$1" && git init -q -b main &&
    printf 'clean\n' > seed.txt && git add seed.txt &&
    git -c user.email=t@t -c user.name=t commit -q -m base )
}
invoke() {  # $1 = repo dir, $2 = tmpdir; echoes output, returns hook rc
  ( cd "$1" && printf '%s' "$BASH_CALL" \
    | TMPDIR="$2" CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>&1 )
}
check() {  # $1 name, $2 got_rc, $3 want_rc
  if [ "$2" -eq "$3" ]; then echo "PASS: $1"; pass=$((pass+1));
  else echo "FAIL: $1 (exit=$2 want $3)"; fail=$((fail+1)); fi
}

# 1. non-Bash tool passes through
r1=$(mktemp -d); t1=$(mktemp -d); mkrepo "$r1"
rc=0; ( cd "$r1" && printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"x","content":"y"}}' \
  | TMPDIR="$t1" bash "$HOOK" ) >/dev/null 2>&1 || rc=$?
check "non-Bash passthrough" "$rc" 0

# 2. outside a git repo: quiet exit 0
nr=$(mktemp -d); t2=$(mktemp -d)
rc=0; ( cd "$nr" && printf '%s' "$BASH_CALL" | TMPDIR="$t2" bash "$HOOK" ) >/dev/null 2>&1 || rc=$?
check "non-repo quiet" "$rc" 0

# 3. FIRST run baselines pre-existing dirty files WITHOUT blocking
r3=$(mktemp -d); t3=$(mktemp -d); mkrepo "$r3"
printf 'TOKEN=%s\n' "$GHP_TOK" > "$r3/preexisting.txt"
rc=0; invoke "$r3" "$t3" >/dev/null || rc=$?
check "first run baselines, never blocks" "$rc" 0

# 4. ...but a file written AFTER the baseline blocks (the D1-3 hole)
printf 'TOKEN=%s\n' "$GHP_TOK" > "$r3/bash-written.txt"
rc=0; out=$(invoke "$r3" "$t3") || rc=$?
check "post-baseline secret blocks" "$rc" 2
if echo "$out" | grep -q '\[BLOCKED\]'; then
  echo "PASS: block message shown"; pass=$((pass+1))
else
  echo "FAIL: no [BLOCKED] in output: $out"; fail=$((fail+1))
fi

# 5. block persists until remediated (signatures not saved on block), then clears
rc=0; invoke "$r3" "$t3" >/dev/null || rc=$?
check "unremediated secret re-blocks" "$rc" 2
printf 'clean now\n' > "$r3/bash-written.txt"
rc=0; invoke "$r3" "$t3" >/dev/null || rc=$?
check "remediated file passes" "$rc" 0

# 6. net-new only: a committed match does not re-block on unrelated edits
r6=$(mktemp -d); t6=$(mktemp -d); mkrepo "$r6"
( cd "$r6" && printf 'TOKEN=%s\n' "$GHP_TOK" > committed.txt && git add committed.txt &&
  git -c user.email=t@t -c user.name=t commit -q -m fixture )
rc=0; invoke "$r6" "$t6" >/dev/null || rc=$?   # baseline run
printf 'TOKEN=%s\nharmless addition\n' "$GHP_TOK" > "$r6/committed.txt"
rc=0; invoke "$r6" "$t6" >/dev/null || rc=$?
check "pre-existing committed match is not net-new" "$rc" 0

# 7. fixture dirs exempt
r7=$(mktemp -d); t7=$(mktemp -d); mkrepo "$r7"
rc=0; invoke "$r7" "$t7" >/dev/null || rc=$?   # baseline run
mkdir -p "$r7/.claude/hooks/tests"
printf 'TOKEN=%s\n' "$GHP_TOK" > "$r7/.claude/hooks/tests/fixture.txt"
rc=0; invoke "$r7" "$t7" >/dev/null || rc=$?
check "fixture dir exempt" "$rc" 0

# 8. a block leaves an audit line
r8=$(mktemp -d); t8=$(mktemp -d); mkrepo "$r8"
rc=0; invoke "$r8" "$t8" >/dev/null || rc=$?   # baseline run
printf 'TOKEN=%s\n' "$GHP_TOK" > "$r8/leak.txt"
alog="$t8/audit.jsonl"
rc=0; ( cd "$r8" && printf '%s' "$BASH_CALL" \
  | TMPDIR="$t8" WORKFLOW_AUDIT_PATH="$alog" bash "$HOOK" ) >/dev/null 2>&1 || rc=$?
if [ -s "$alog" ] && tail -n1 "$alog" | jq -e '.result=="block"' >/dev/null 2>&1; then
  echo "PASS: block audited"; pass=$((pass+1))
else
  echo "FAIL: no audit line on block"; fail=$((fail+1))
fi

# 9. gitleaks layer (conditional): age-key class blocks post-baseline
if command -v gitleaks >/dev/null 2>&1; then
  AGE_TKN="AGE-SECRET-KEY-1$(printf 'Q%.0s' $(seq 1 58))"
  r9=$(mktemp -d); t9=$(mktemp -d); mkrepo "$r9"
  rc=0; invoke "$r9" "$t9" >/dev/null || rc=$?   # baseline run
  printf 'k=%s\n' "$AGE_TKN" > "$r9/age.txt"
  rc=0; invoke "$r9" "$t9" >/dev/null || rc=$?
  check "gitleaks layer blocks age-key class" "$rc" 2
  rm -rf "$r9" "$t9"
else
  echo "SKIP: gitleaks not on PATH — layer case skipped"
fi

# 10. subdir cwd: git status paths are root-relative — the hook must cd to root,
#     otherwise a root-level secret written while cwd is a subdir escapes (D1-3)
r10=$(mktemp -d); t10=$(mktemp -d); mkrepo "$r10"
mkdir -p "$r10/sub"
rc=0; invoke "$r10" "$t10" >/dev/null || rc=$?   # baseline run (from root)
printf 'TOKEN=%s\n' "$GHP_TOK" > "$r10/leak-root.txt"
rc=0; ( cd "$r10/sub" && printf '%s' "$BASH_CALL" \
  | TMPDIR="$t10" CLAUDE_PROJECT_DIR="$r10" bash "$HOOK" ) >/dev/null 2>&1 || rc=$?
check "subdir cwd still blocks root-written secret" "$rc" 2

rm -rf "$r1" "$t1" "$nr" "$t2" "$r3" "$t3" "$r6" "$t6" "$r7" "$t7" "$r8" "$t8" "$r10" "$t10"
t_summary
