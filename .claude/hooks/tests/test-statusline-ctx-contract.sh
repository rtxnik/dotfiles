#!/usr/bin/env bash
# Contract test (D3-4): statusline.js (producer) -> context-exhaustion-gate.sh (consumer)
# over a shared TMPDIR with a HOSTILE session id. Asserts (a) the content-keyed SOFT warn
# still fires through a traversal id, and (b) NO file is written outside TMPDIR (the trend
# file at statusline.js:129 must be sanitized). RED until the trend-file fix lands.
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
SL="$HOOKS/statusline.js"
GATE="$HOOKS/context-exhaustion-gate.sh"
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init

TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT
PARENT=$(dirname "$TD")
MARK="d3-4-$$"                       # unique marker so the stray-file check is unambiguous
# Hostile id. With the buggy (raw) trend name `claude-ctx-trend-${session}.json`, the literal
# prefix "claude-ctx-trend-.." absorbs one "../", so "../../$MARK" lands the trend write at
# "$TD/$MARK.json" — a NON-claude-ctx-* file INSIDE TMPDIR (depth-independent, reliably created).
# (A deeper id can escape above TMPDIR, but a write to / fails silently via the catch{}, so that
# path is not a reliable RED signal — the stray-file-inside-TD check below is the load-bearing one.)
SESS="../../$MARK"

# Build payloads with jq (the id has / and ..; never hand-interpolate).
sl_payload=$(jq -cn --arg s "$SESS" --arg d "$TD" \
  '{session_id:$s, workspace:{current_dir:$d}, context_window:{remaining_percentage:30}}')
gate_payload=$(jq -cn --arg s "$SESS" '{session_id:$s, tool_name:"Bash", tool_input:{command:"x"}}')

# Producer: statusline writes claude-ctx-*.json + the trend file into TMPDIR.
printf '%s' "$sl_payload" | ( cd "$TD" && TMPDIR="$TD" node "$SL" >/dev/null 2>&1 ) || true

# (1) ctx file created, filename sanitized (no / or ..), content session_id raw.
ctx=$(find "$TD" -maxdepth 1 -name 'claude-ctx-*.json' ! -name '*trend*' | head -n1)
ok "ctx file created"            '[ -n "$ctx" ]'
ok "ctx filename sanitized"      'case "$(basename "${ctx:-x}")" in *..*|*/*) false;; *) true;; esac'
ok "ctx content keeps raw id"    '[ "$(jq -r .session_id "$ctx" 2>/dev/null)" = "$SESS" ]'

# (2) Consumer: gate warns SOFT (remaining 30 <= soft 35, > hard 25) through the hostile id.
NOWMS=$(node -e 'process.stdout.write(String(Date.now()))')
out=$(printf '%s' "$gate_payload" | ( cd "$TD" && TMPDIR="$TD" WORKFLOW_NOW_MS="$NOWMS" bash "$GATE" 2>&1 )) || true
ac=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
ok "gate still warns (content-keyed match survives hostile id)" '[ -n "$ac" ]'
assert_out_has "warn is SOFT tier" "$ac" "soft tier"

# (3) THE D3-4 ASSERTION (load-bearing, depth-independent): the producer must write ONLY
# claude-ctx-* files under TMPDIR. The buggy trend write lands as "$MARK.json" (a non
# claude-ctx-* name); the fix makes it "claude-ctx-trend-<safe>.json". Any non-claude-ctx
# file under TD == the bug. This is RED today, GREEN after the Task 4.1 fix.
stray=$(find "$TD" -maxdepth 1 -type f ! -name 'claude-ctx-*' 2>/dev/null)
ok "trend write stays under claude-ctx-* (no stray file)" '[ -z "$stray" ]'
# Secondary (defense-in-depth, always-green): no marker file appeared just above TMPDIR.
escaped=$(find "$PARENT" -maxdepth 1 -name "*$MARK*" 2>/dev/null)
ok "no marker file directly above TMPDIR" '[ -z "$escaped" ]'
ok "no torn temp file left"      '[ -z "$(find "$TD" -maxdepth 1 -name "*.tmp*" 2>/dev/null)" ]'

t_summary
