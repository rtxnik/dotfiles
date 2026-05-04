#!/usr/bin/env bash
# Source: CONTEXT.md D-07 + D-10. Bash-only per workspace CLAUDE.md.
#
# verify-recipients.sh -- bidirectional structural diff between:
#   1. .age-recipients.yaml::active[].pubkey  (Plan 14-15 SoT — committed,
#      audit-trail friendly with name + role + pubkey per entry)
#   2. active-tagged hosts in docs/AUTHORIZED-HOSTS.md
# Exit 0 on equality; exit 1 with human-readable diff on mismatch.
#
# Plan 14-15 (closes 14-REVIEW WR-05) replaced the prior regex-on-.tmpl
# extraction path with a structural compare against `.age-recipients.yaml`
# (single source of truth). The bash-only invariant (workspace CLAUDE.md
# non-negotiable) is preserved: yq is acceptable here because this script
# runs from CI / operator command line, NOT from a pre-commit hook.
#
# Env-var overrides (used by tests):
#   DOTFILES_REPO         -- override the repo root lookup
#                            (default: detected via `git rev-parse` or pwd)
#   RECIPIENTS_YAML       -- path to .age-recipients.yaml SoT
#                            (default: $DOTFILES_REPO/.age-recipients.yaml)
#   AUTHORIZED_HOSTS_MD   -- path to AUTHORIZED-HOSTS.md
#                            (default: $DOTFILES_REPO/docs/AUTHORIZED-HOSTS.md)
#
# AWK FIELD INDICES (locked per Phase 12 Plan 12-03 W2):
# Table format: `| hostname | role | pubkey | fingerprint | provisioned | host_type | tag |`
# With `awk -F '|'`, leading `|` makes $1 empty; visible cols are $2..$8.
# pubkey = $4, tag = $8. Verified against Wave 0 fixtures (12-01 Task 3).

set -euo pipefail

if [ -n "${DOTFILES_REPO:-}" ]; then
  REPO_ROOT="$DOTFILES_REPO"
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
RECIPIENTS_YAML="${RECIPIENTS_YAML:-$REPO_ROOT/.age-recipients.yaml}"
ALLOWLIST="${AUTHORIZED_HOSTS_MD:-$REPO_ROOT/docs/AUTHORIZED-HOSTS.md}"

if ! command -v yq >/dev/null 2>&1; then
  echo "FAIL: yq not installed (need Mike Farah v4 — https://github.com/mikefarah/yq)" >&2
  exit 2
fi

[ -f "$RECIPIENTS_YAML" ] || { echo "FAIL: $RECIPIENTS_YAML not found" >&2; exit 1; }
[ -f "$ALLOWLIST" ] || { echo "FAIL: $ALLOWLIST not found" >&2; exit 1; }

# Extract active pubkeys from SoT YAML (Plan 14-15 canonical extraction).
sot_keys=$(yq -e '.active[].pubkey' "$RECIPIENTS_YAML" 2>/dev/null | sort -u) || {
  echo "FAIL: $RECIPIENTS_YAML missing .active[].pubkey entries" >&2
  exit 1
}

# Extract active-tagged pubkeys from docs/AUTHORIZED-HOSTS.md.
# Table format (D-07): | hostname | role | pubkey | fingerprint | provisioned | host_type | tag |
# Field indices (LOCKED, W2): pubkey=$4, tag=$8.
allowlist_active=$(awk -F '|' '
  /^\|[[:space:]]*hostname/ { in_table=1; next }
  /^\|[[:space:]]*-+/ { next }
  in_table && NF >= 8 {
    pubkey = $4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", pubkey)
    tag = $8;    gsub(/^[[:space:]]+|[[:space:]]+$/, "", tag)
    if (tag == "active") print pubkey
  }
  in_table && /^[^|]/ { in_table=0 }
' "$ALLOWLIST" | sort -u)

# Bidirectional diff via comm.
orphan_in_sot=$(comm -23 <(echo "$sot_keys") <(echo "$allowlist_active") | grep -v '^$' || true)
missing_from_sot=$(comm -13 <(echo "$sot_keys") <(echo "$allowlist_active") | grep -v '^$' || true)

fail=0
if [ -n "$orphan_in_sot" ]; then
  printf 'FAIL: orphan recipients in %s (not in %s active tier):\n%s\n\n' \
    "$RECIPIENTS_YAML" "$ALLOWLIST" "$orphan_in_sot" >&2
  fail=1
fi
if [ -n "$missing_from_sot" ]; then
  printf 'FAIL: active hosts missing from %s (declared active in %s but no recipient):\n%s\n\n' \
    "$RECIPIENTS_YAML" "$ALLOWLIST" "$missing_from_sot" >&2
  fail=1
fi

if [ $fail -eq 0 ]; then
  count=$(echo "$sot_keys" | grep -c . || true)
  printf 'OK: recipients SoT (%s) matches AUTHORIZED-HOSTS.md active tier (%s entries)\n' \
    "$RECIPIENTS_YAML" "$count"
fi
exit $fail
