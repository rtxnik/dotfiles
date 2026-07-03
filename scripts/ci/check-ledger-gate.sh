#!/usr/bin/env bash
# CI LEDGER gate (F1 / finding D5-4): gives the LEDGER contract CI presence.
#   1. .planning/LEDGER.tsv must pass ledger_validate (always).
#   2. PR builds (BASE_REF set by the workflow): if the diff vs the merge-base
#      touches enforced fabric paths, it must NET-ADD at least one schema-shaped data row.
# Enforced paths mirror the surface fabric-gates.yml path-filtered on before F1.
# CI asserts the artifact (rows), never command patterns — see F1 anti-patterns.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ledger="$root/.planning/LEDGER.tsv"

if ! out="$(bash "$root/.claude/hooks/lib/hooklib.sh" ledger_validate "$ledger")"; then
  echo "FAIL: LEDGER.tsv invalid:" >&2
  printf '%s\n' "$out" >&2
  exit 1
fi
echo "OK: LEDGER.tsv schema valid"

base="${BASE_REF:-}"
if [[ -z "$base" ]]; then
  echo "OK: no BASE_REF (push build) — row check skipped"
  exit 0
fi

# Resolve the base ref portably: prefer origin/<base> (CI checks out with the base fetched),
# then a local <base>. If neither resolves (e.g. a fresh clone with no remote tracking), skip
# the row check rather than hard-fail — CI always provides origin/<base>, so the workspace-meta
# path is unchanged. (Never silently weakens enforcement: it only skips when no diff is computable.)
base_ref=""
if git -C "$root" rev-parse --verify --quiet "origin/${base}^{commit}" >/dev/null; then
  base_ref="origin/${base}"
elif git -C "$root" rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
  base_ref="${base}"
fi
if [[ -z "$base_ref" ]]; then
  echo "OK: base ref '${base}' not resolvable locally — row check skipped (CI provides origin/<base>)"
  exit 0
fi
merge_base="$(git -C "$root" merge-base "$base_ref" HEAD)"
enforced='^(\.claude/|scripts/|tools/factory-map/|Makefile$)'
if ! git -C "$root" diff --name-only "$merge_base" HEAD | grep -Eq "$enforced"; then
  echo "OK: PR does not touch enforced fabric paths — row check skipped"
  exit 0
fi

ledger_diff="$(git -C "$root" diff "$merge_base" HEAD -- .planning/LEDGER.tsv)"
# count_rows <+|-> : schema-shaped data rows (5 TAB columns, not the header) added/removed.
count_rows() {
  printf '%s\n' "$ledger_diff" | grep -e "^$1[^$1]" | cut -c2- \
    | awk -F'\t' 'NF==5 && $1!="timestamp"' | grep -c . || true
}
added="$(count_rows '+')"
removed="$(count_rows '-')"
net=$(( added - removed ))
if [[ "$net" -lt 1 ]]; then
  echo "FAIL: PR touches enforced fabric paths but adds no LEDGER row (.planning/LEDGER.tsv)" >&2
  echo "      Log the change per the loop discipline, then push again." >&2
  exit 1
fi
echo "OK: net +$net LEDGER row(s) added in this PR"
