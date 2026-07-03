#!/usr/bin/env bash
# Self-test for scripts/lib/testlib.sh — verifies each primitive's output + exit semantics.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
LIB="$HERE/../testlib.sh"
mpass=0; mfail=0
m_ok() { if eval "$2"; then echo "PASS: $1"; mpass=$((mpass+1)); else echo "FAIL: $1"; mfail=$((mfail+1)); fi; }

# pass/fail counters land in caller scope and t_summary exits 1 on failure
out=$(bash -c "source '$LIB'; t_init; pass a; fail b; t_summary" 2>&1); rc=$?
m_ok "t_summary exit 1 on failure"        '[ "$rc" -eq 1 ]'
m_ok "Results line present"               'printf "%s" "$out" | grep -q "Results: 1 passed, 1 failed"'
m_ok "pass prints PASS:"                  'printf "%s" "$out" | grep -q "^PASS: a"'
m_ok "fail prints FAIL:"                  'printf "%s" "$out" | grep -q "^FAIL: b"'

out=$(bash -c "source '$LIB'; t_init; ok x 'true'; ok y 'false'; t_summary" 2>&1) || true
m_ok "ok evals true -> PASS"              'printf "%s" "$out" | grep -q "^PASS: x"'
m_ok "ok evals false -> FAIL"            'printf "%s" "$out" | grep -q "^FAIL: y"'

out=$(bash -c "source '$LIB'; t_init; assert_eq e1 5 5; assert_eq e2 5 6; t_summary" 2>&1) || true
m_ok "assert_eq match -> PASS"            'printf "%s" "$out" | grep -q "^PASS: e1"'
m_ok "assert_eq mismatch -> FAIL"         'printf "%s" "$out" | grep -q "^FAIL: e2"'

out=$(bash -c "source '$LIB'; t_init; assert_rc r1 0 0; assert_rc r2 2 0; t_summary" 2>&1) || true
m_ok "assert_rc match -> PASS"            'printf "%s" "$out" | grep -q "^PASS: r1"'
m_ok "assert_rc mismatch -> FAIL"         'printf "%s" "$out" | grep -q "^FAIL: r2"'

out=$(bash -c "source '$LIB'; t_init; assert_out_has h1 'hello world' 'wor'; assert_out_lacks h2 'hello' 'zzz'; assert_out_has h3 'a' 'zzz'; t_summary" 2>&1) || true
m_ok "assert_out_has hit -> PASS"         'printf "%s" "$out" | grep -q "^PASS: h1"'
m_ok "assert_out_lacks miss -> PASS"      'printf "%s" "$out" | grep -q "^PASS: h2"'
m_ok "assert_out_has miss -> FAIL"        'printf "%s" "$out" | grep -q "^FAIL: h3"'

out=$(bash -c "source '$LIB'; t_init; skip s1 because; t_summary" 2>&1) || true
m_ok "skip touches neither counter"       'printf "%s" "$out" | grep -q "Results: 0 passed, 0 failed"'
m_ok "skip prints SKIP:"                  'printf "%s" "$out" | grep -q "^SKIP: s1 — because"'

# run_hook returns the invoked script's rc and echoes its output
fakehook=$(mktemp); printf '#!/usr/bin/env bash\necho hi; exit 3\n' > "$fakehook"; chmod +x "$fakehook"
out=$(bash -c "source '$LIB'; run_hook '$fakehook' '{}'" 2>&1); rc=$?
m_ok "run_hook returns hook rc"           '[ "$rc" -eq 3 ]'
m_ok "run_hook echoes hook stdout"        'printf "%s" "$out" | grep -q "^hi"'
rm -f "$fakehook"

# mk_git_sandbox makes a committable repo
d=$(bash -c "source '$LIB'; mk_git_sandbox feat/x");
m_ok "mk_git_sandbox is a git repo"       'git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1'
m_ok "mk_git_sandbox set branch"          '[ "$(git -C "$d" symbolic-ref --short HEAD)" = "feat/x" ]'
( cd "$d" && echo x > f && git add f && git commit -qm t ) >/dev/null 2>&1
m_ok "mk_git_sandbox identity works"      '[ -n "$(git -C "$d" rev-parse HEAD 2>/dev/null)" ]'
rm -rf "$d"

# json_tool_call builds valid envelopes
out=$(bash -c "source '$LIB'; json_tool_call Write '{\"file_path\":\"x\"}' sess9")
m_ok "json_tool_call valid JSON"          'printf "%s" "$out" | jq -e .tool_input.file_path >/dev/null'
m_ok "json_tool_call carries session"     '[ "$(printf "%s" "$out" | jq -r .session_id)" = "sess9" ]'

# assert_audit_result reads the last jsonl line
alog=$(mktemp); printf '{"result":"warn"}\n' > "$alog"
out=$(bash -c "source '$LIB'; t_init; assert_audit_result a1 '$alog' warn; assert_audit_result a2 '$alog' block; t_summary" 2>&1) || true
m_ok "assert_audit_result match -> PASS"  'printf "%s" "$out" | grep -q "^PASS: a1"'
m_ok "assert_audit_result miss -> FAIL"   'printf "%s" "$out" | grep -q "^FAIL: a2"'
rm -f "$alog"

echo ""; echo "Results: $mpass passed, $mfail failed"; [ "$mfail" -eq 0 ] || exit 1
