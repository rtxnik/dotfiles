#!/usr/bin/env bash
# shellcheck disable=SC2154  # pass/fail are set in the caller's scope by ck_init (lib/check.sh)
# Asserts the A6 reviewer rubric is durable (design spec §6): it lives in the
# workspace repo (so it survives a plugin-cache reset), is referenced from CLAUDE.md,
# and is NOT sourced from any ephemeral plugin-cache path. Fails (exit 1) on drift.
set -uo pipefail
# shellcheck source=lib/check.sh
source "$(cd "$(dirname "$0")/lib" && pwd)/check.sh"
ck_init
ROOT="${CHECK_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
rubric="$ROOT/.claude/review-rubric.md"
if [ -f "$rubric" ]; then ck_pass "rubric present in repo"; else ck_fail "rubric missing at $rubric"; fi
case "$rubric" in */plugins/cache/*) ck_fail "rubric under plugin cache (not durable)" ;; esac
if grep -q 'review-rubric.md' "$ROOT/CLAUDE.md"; then ck_pass "CLAUDE.md references the rubric"; else ck_fail "CLAUDE.md does not reference review-rubric.md"; fi
if [ "$fail" -eq 0 ]; then echo "PASS rubric durable"; else echo "FAIL rubric durability"; exit 1; fi
