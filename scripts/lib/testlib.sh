#!/usr/bin/env bash
# testlib.sh — shared shell-test harness for workspace-meta (U3 / F7).
# Sourced by .claude/hooks/tests/test-*.sh and scripts/ci/tests/test-*.sh.
#
# Design contract (why this is safe to drop into 30+ existing files):
#  - Counters `pass`/`fail` live in the CALLER's scope (exactly the legacy idiom), so a
#    migrated file replaces its local ok()/footer with a `source` + t_init and produces
#    BYTE-IDENTICAL "PASS: x" / "FAIL: x" / "Results: N passed, M failed" output.
#  - NO global EXIT trap is installed — callers keep their own `trap 'rm -rf "$d"' EXIT`.
#  - Every function is `set -e`-safe (no bare command whose nonzero status aborts an
#    `set -euo pipefail` caller); fail()/skip()/assert_* always `return 0`.
#  - This file does NOT source hooklib.sh and defines no hooklib names, so a test that
#    sources BOTH (to exercise hooklib in-process) is unaffected.

# --- lifecycle / counters -----------------------------------------------------
t_init() { pass=0; fail=0; }

pass() { echo "PASS: $1"; pass=$((pass + 1)); }
# fail <name> [detail] : detail (optional) printed indented on a second line.
fail() { echo "FAIL: $1"; [ "$#" -gt 1 ] && echo "  $2"; fail=$((fail + 1)); return 0; }
# skip <name> [reason] : neither pass nor fail (e.g. gitleaks absent).
skip() { echo "SKIP: $1${2:+ — $2}"; return 0; }

# --- assertions ---------------------------------------------------------------
# ok <name> <test-expression-string> : eval arg2; pass/fail on its status.
# Byte-equivalent to the canonical ok() in the 15 ok-eval hook tests.
ok() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

# assert_eq <name> <want> <got> : value comparison (replaces check() in test-audit-helpers).
assert_eq() { if [ "$3" = "$2" ]; then pass "$1"; else fail "$1" "got='$3' want='$2'"; fi; }

# assert_rc <name> <expected_rc> <actual_rc> : exit-code-only assertion.
assert_rc() { if [ "$3" -eq "$2" ]; then pass "$1"; else fail "$1" "exit=$3 want=$2"; fi; }

# assert_out_has  <name> <output> <ERE> : pass iff output matches grep -qE.
assert_out_has() {
  if printf '%s' "$2" | grep -qE -- "$3"; then pass "$1"; else fail "$1" "missing /$3/"; fi
}
# assert_out_lacks <name> <output> <ERE> : pass iff output does NOT match.
assert_out_lacks() {
  if printf '%s' "$2" | grep -qE -- "$3"; then fail "$1" "unexpected /$3/"; else pass "$1"; fi
}

# assert_audit_result <name> <audit_jsonl_path> <warn|block> : the F2 audit-line check.
assert_audit_result() {
  if [ -s "$2" ] && tail -n1 "$2" | jq -e ".result==\"$3\"" >/dev/null 2>&1; then
    pass "$1"
  else
    fail "$1" "no '$3' audit line in $2"
  fi
}

# --- hook invocation ----------------------------------------------------------
# run_hook <hook_path> <json_stdin> [ENV=VAL...] : echo combined stdout+stderr, RETURN hook rc.
# Use:  out=$(run_hook "$HOOK" "$payload" CLAUDE_PROJECT_DIR="$sb"); rc=$?
# cwd control: wrap in a subshell — out=$( ( cd "$sb" && run_hook ... ) ); rc=$?
# set -e callers MUST capture with `|| rc=$?` (run_hook returns the hook's nonzero rc).
run_hook() {
  local hook="$1" input="$2"; shift 2
  printf '%s' "$input" | env "$@" bash "$hook" 2>&1
}

# json_tool_call <tool_name> <tool_input_json> [session_id] : echo a hook input envelope.
# Pass already-built secret strings as VALUES (keeps the runtime-token-assembly convention —
# no raw secret literal in the test source).
json_tool_call() {
  if [ "$#" -ge 3 ]; then
    jq -cn --arg t "$1" --argjson ti "$2" --arg s "$3" '{tool_name:$t, tool_input:$ti, session_id:$s}'
  else
    jq -cn --arg t "$1" --argjson ti "$2" '{tool_name:$t, tool_input:$ti}'
  fi
}

# --- git sandbox --------------------------------------------------------------
# mk_git_sandbox [branch] : print path to a fresh `git init` repo with a throwaway identity
# (set via `git config`, so plain `git commit` works afterwards). Does NOT register cleanup —
# the caller owns `trap 'rm -rf "$d"' EXIT`.
mk_git_sandbox() {
  local d; d=$(mktemp -d)
  git -C "$d" init -q -b "${1:-main}" >/dev/null
  git -C "$d" config user.email t@t.local
  git -C "$d" config user.name t
  printf '%s' "$d"
}

# --- epilogue -----------------------------------------------------------------
# t_summary : the shared footer. Byte-equivalent to the 24-file epilogue.
t_summary() { echo ""; echo "Results: $pass passed, $fail failed"; [ "$fail" -eq 0 ] || exit 1; }
