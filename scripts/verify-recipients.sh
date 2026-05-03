#!/usr/bin/env bash
# Source: CONTEXT.md D-07 + D-10. Bash-only per workspace CLAUDE.md.
#
# verify-recipients.sh -- bidirectional diff between:
#   1. recipients: list in .chezmoi.yaml.tmpl
#   2. active-tagged hosts in docs/AUTHORIZED-HOSTS.md
# Exit 0 on equality; exit 1 with human-readable diff on mismatch.
#
# Env-var overrides (used by tests):
#   CHEZMOI_TMPL          -- path to .chezmoi.yaml.tmpl
#                            (default: $REPO_ROOT/.chezmoi.yaml.tmpl)
#   AUTHORIZED_HOSTS_MD   -- path to AUTHORIZED-HOSTS.md
#                            (default: $REPO_ROOT/docs/AUTHORIZED-HOSTS.md)
#
# AWK FIELD INDICES (locked per Phase 12 Plan 12-03 W2):
# Table format: `| hostname | role | pubkey | fingerprint | provisioned | host_type | tag |`
# With `awk -F '|'`, leading `|` makes $1 empty; visible cols are $2..$8.
# pubkey = $4, tag = $8. Verified against Wave 0 fixtures (12-01 Task 3).

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TMPL="${CHEZMOI_TMPL:-$REPO_ROOT/.chezmoi.yaml.tmpl}"
ALLOWLIST="${AUTHORIZED_HOSTS_MD:-$REPO_ROOT/docs/AUTHORIZED-HOSTS.md}"

[ -f "$TMPL" ] || { echo "FAIL: $TMPL not found" >&2; exit 1; }
[ -f "$ALLOWLIST" ] || { echo "FAIL: $ALLOWLIST not found" >&2; exit 1; }

# Extract recipients from .chezmoi.yaml.tmpl YAML block.
# State machine: enter on `recipients:`, emit pubkey lines, exit on next non-indented key.
template_recipients=$(awk '
  /^[[:space:]]*recipients:[[:space:]]*$/ { in_block=1; next }
  in_block && /^[[:space:]]*-[[:space:]]+"age1[^"]+"[[:space:]]*$/ {
    match($0, /"age1[^"]+"/); pk = substr($0, RSTART+1, RLENGTH-2); print pk; next
  }
  in_block && /^[a-zA-Z]/ { in_block=0 }
' "$TMPL" | sort -u)

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
orphan_in_template=$(comm -23 <(echo "$template_recipients") <(echo "$allowlist_active") | grep -v '^$' || true)
missing_from_template=$(comm -13 <(echo "$template_recipients") <(echo "$allowlist_active") | grep -v '^$' || true)

fail=0
if [ -n "$orphan_in_template" ]; then
  printf 'FAIL: orphan recipients in %s (not in %s active tier):\n%s\n\n' \
    "$TMPL" "$ALLOWLIST" "$orphan_in_template" >&2
  fail=1
fi
if [ -n "$missing_from_template" ]; then
  printf 'FAIL: active hosts missing from %s (declared active in %s but no recipient):\n%s\n\n' \
    "$TMPL" "$ALLOWLIST" "$missing_from_template" >&2
  fail=1
fi
[ $fail -eq 0 ] && printf 'OK: recipients list matches AUTHORIZED-HOSTS.md active tier (%d entries)\n' \
  "$(echo "$template_recipients" | grep -c . || true)"
exit $fail
