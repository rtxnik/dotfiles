#!/usr/bin/env bash
# Self-test for scripts/lib/check.sh.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
LIB="$HERE/../check.sh"
mpass=0; mfail=0
m_ok() { if eval "$2"; then echo "PASS: $1"; mpass=$((mpass+1)); else echo "FAIL: $1"; mfail=$((mfail+1)); fi; }

out=$(bash -c "source '$LIB'; ck_init; ck_pass a; ck_fail b; ck_skip c; printf 'F=%s\n' \"\$fail\"" 2>&1)
m_ok "ck_pass prints PASS:"   'printf "%s" "$out" | grep -q "^PASS: a"'
m_ok "ck_fail prints FAIL:"   'printf "%s" "$out" | grep -q "^FAIL: b"'
m_ok "ck_skip prints SKIP:"   'printf "%s" "$out" | grep -q "^SKIP: c"'
m_ok "ck_fail bumps counter"  'printf "%s" "$out" | grep -q "^F=1"'
m_ok "ck_skip no counter bump" 'printf "%s" "$out" | grep -q "^F=1"'

out=$(bash -c "source '$LIB'; ck_init; ck_assert_rc 0 r1; ck_assert_rc 2 r2" 2>&1)
m_ok "ck_assert_rc 0 -> PASS" 'printf "%s" "$out" | grep -q "^PASS: r1"'
m_ok "ck_assert_rc nz -> FAIL" 'printf "%s" "$out" | grep -q "^FAIL: r2"'

out=$(bash -c "source '$LIB'; ck_init; ck_assert_jq '{\"a\":1}' '.a==1' j1; ck_assert_jq '{\"a\":1}' '.a==2' j2" 2>&1)
m_ok "ck_assert_jq true -> PASS"  'printf "%s" "$out" | grep -q "^PASS: j1"'
m_ok "ck_assert_jq false -> FAIL" 'printf "%s" "$out" | grep -q "^FAIL: j2"'

echo ""; echo "Results: $mpass passed, $mfail failed"; [ "$mfail" -eq 0 ] || exit 1
