#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
SL="$(cd "$(dirname "$0")/.." && pwd)/statusline.js"
TD="$(mktemp -d)"; trap 'rm -rf "$TD"' EXIT
printf '{"session_id":"a/b..c","workspace":{"current_dir":"%s"},"context_window":{"remaining_percentage":42}}' "$TD" \
  | ( cd "$TD" && TMPDIR="$TD" node "$SL" >/dev/null 2>&1 )
f="$(find "$TD" -maxdepth 1 -name 'claude-ctx-*.json' ! -name '*trend*' | head -1)"
ok "ctx file created"            '[ -n "$f" ]'
ok "filename sanitized"          'case "$(basename "$f")" in *..*|*/*) false ;; *) true ;; esac'
ok "content session_id raw"      '[ "$(jq -r .session_id "$f")" = "a/b..c" ]'
ok "no leftover temp file"       '[ -z "$(find "$TD" -maxdepth 1 -name "*.tmp*" 2>/dev/null)" ]'
t_summary
