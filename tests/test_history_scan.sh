#!/usr/bin/env bash
# DOT-03 -- full-history leak audit.
# Per Open Q4: JSON output is EPHEMERAL (/tmp), NOT committed to state/.
# Production-code dependency: none (the audit runs against the live repo's
# git history). This script is a verification target -- the assertion is
# `length == 0` after each run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

OUT="/tmp/gitleaks-history-audit-$$.json"
trap 'rm -f "$OUT"' EXIT

# `gitleaks git --report-format json --report-path <file>` -- modern syntax
# (post-v8.19.0; replaces deprecated `gitleaks detect --no-git=false`).
# `--exit-code 0` so we can inspect the report ourselves rather than letting
# gitleaks's own non-zero exit short-circuit the assertion logic.
gitleaks git --report-format json --report-path "$OUT" --redact --no-banner --exit-code 0

if [ ! -s "$OUT" ]; then
  echo "OK: gitleaks produced no findings (empty report)"
  exit 0
fi

count=$(jq 'length' "$OUT")
if [ "$count" -eq 0 ]; then
  echo "OK: zero historical leaks across $(git rev-list --all --count) commits"
  exit 0
else
  echo "FAIL: $count finding(s). Review $OUT (NOT committed); file incident per D-12; rotate per ADR-sec-02." >&2
  jq '.' "$OUT" >&2
  exit 1
fi
