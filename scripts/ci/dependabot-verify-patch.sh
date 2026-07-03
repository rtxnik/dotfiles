#!/usr/bin/env bash
# dependabot-verify-patch.sh -- refuse a regen patch that touches anything outside the
# regen allowlist, or a tooling/factory/compose.py change that is not a pure action-pin line.
# Fail-safe (exit 1), never fail-open. Usage: dependabot-verify-patch.sh <patch-file>
set -euo pipefail
patch="${1:?usage: dependabot-verify-patch.sh <patch-file>}"

allow_re='^(factory\.lock|graphify-out/(graph\.json|GRAPH_REPORT\.md|graph\.html)|\.planning/LEDGER\.tsv|tools/factory-map/package-lock\.json|\.claude/settings\.json|\.claude/gate-registry\.json|scripts/check-integration-mcp\.sh|\.gitignore|\.github/workflows/fabric-gates\.yml|\.github/dependabot\.yml|tooling/factory/compose\.py)$'

# Extract affected paths: +++/--- lines, both sides of diff --git a/<src> b/<dst> headers,
# and rename/copy from/to lines.  || true guards against grep exit 1 on no-match.
paths="$(
  {
    grep -E '^(\+\+\+|---) ' "$patch" | sed -E 's@^(\+\+\+|---) [ab]/@@' || true
    grep -E '^diff --git ' "$patch" | sed -E 's@^diff --git a/(.+) b/.+$@\1@' || true
    grep -E '^diff --git ' "$patch" | sed -E 's@^diff --git .+ b/(.+)$@\1@' || true
    grep -E '^(rename|copy) (from|to) ' "$patch" | sed -E 's@^(rename|copy) (from|to) @@' || true
  } | grep -v '^/dev/null$' | grep -v '^$' | sort -u || true
)"
[ -n "$paths" ] || { echo "FAIL: no paths extracted from patch (empty or malformed)" >&2; exit 1; }
bad=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  grep -Eq "$allow_re" <<<"$p" || { echo "FAIL: patch touches non-allowlisted path: $p" >&2; bad=1; }
done <<<"$paths"
[ "$bad" -eq 0 ] || exit 1

# If compose.py is among the extracted paths, a diff --git header must be present.
# A headerless hunk cannot reach the per-line pin-check below, so it would be skipped.
if grep -q '^tooling/factory/compose\.py$' <<<"$paths"; then
  grep -qE '^diff --git .+ b/tooling/factory/compose\.py$' "$patch" \
    || { echo "FAIL: compose.py change has no diff --git header -- cannot verify pin lines" >&2; exit 1; }
fi

# compose.py: every changed (+/-) content line must be an action-pin line.
in=0
while IFS= read -r line; do
  if [[ "$line" == 'diff --git '* ]]; then
    [[ "$line" == *' b/tooling/factory/compose.py' ]] && in=1 || in=0
    continue
  fi
  [ "$in" -eq 1 ] || continue
  case "$line" in
    '+++ '*|'--- '*|'@@'*|'index '*|'new file'*|'deleted file'*|'rename '*) ;;
    '+'*|'-'*)
      content="${line:1}"
      grep -Eq '^[[:space:]]*- uses: [^ ]+@[0-9a-f]{40}  # .+$' <<<"$content" \
        || { echo "FAIL: compose.py change is not a pure action-pin line: $line" >&2; exit 1; } ;;
  esac
done < "$patch"

echo "OK: patch within regen allowlist"
