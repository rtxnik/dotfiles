#!/usr/bin/env bash
# check.sh — shared PASS/FAIL/SKIP idiom for scripts/check-integration-*.sh (U3 / F7).
# Promotes phase4's documented ok()/bad()/assert() trio to a single home. Accumulates
# (never fail-fast); each adopting script keeps its OWN summary tail (their existing tests
# grep specific summary substrings — do NOT route the summary through this lib).
# Counters `pass`/`fail` live in the caller's scope. -e-safe.

ck_init() { pass=0; fail=0; }
ck_pass() { echo "PASS: $1"; pass=$((pass + 1)); }
ck_fail() { echo "FAIL: $1"; fail=$((fail + 1)); return 0; }
ck_skip() { echo "SKIP: $1"; return 0; }

# ck_assert_rc <rc> <label> : consume a PRECEDING command's exit status (0 -> PASS else FAIL).
# Dodges the `A && ok || bad` (SC2015) pitfall and the pipefail + `grep -q` SIGPIPE trap.
ck_assert_rc() { if [ "$1" -eq 0 ]; then ck_pass "$2"; else ck_fail "$2"; fi; }

# ck_assert_jq <json> <jq-bool-expr> <label> : PASS iff `jq -e <expr>` is truthy.
ck_assert_jq() {
  if printf '%s' "$1" | jq -e "$2" >/dev/null 2>&1; then ck_pass "$3"; else ck_fail "$3"; fi
}
