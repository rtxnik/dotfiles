#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(cd "$(dirname "$0")/.." && pwd)/context-exhaustion-gate.sh"

TD="$(mktemp -d)"; export TMPDIR="$TD"
sess="ctxtest-$$"
mkfix() {
  printf '{"session_id":"%s","remaining_percentage":%s,"used_pct":%s,"ts":%s}' \
    "$sess" "$1" "$2" "$3" > "$TD/claude-ctx-${sess}.json"
}
run() {
  printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"x"}}' "$sess" \
    | ( env "$@" bash "$HOOK" 2>/dev/null )
}
clean() { rm -f "$TD"/wf-ctx/*.warned 2>/dev/null; }
trap 'rm -rf "$TD"' EXIT

NOW=1000000000000
mkfix 60 40 "$NOW"; clean
ok "healthy silent" '[ -z "$(run WORKFLOW_NOW_MS=$NOW)" ]'
mkfix 33 67 "$NOW"; clean
soft="$(run WORKFLOW_NOW_MS=$NOW)"
ok "soft warns"            '[ -n "$soft" ]'
ok "soft is addtlContext"  '[ -n "$(printf "%s" "$soft" | jq -e .hookSpecificOutput.additionalContext 2>/dev/null)" ]'
ok "soft mentions soft tier" 'printf "%s" "$soft" | jq -r .hookSpecificOutput.additionalContext | grep -q "soft tier"'
mkfix 22 78 "$NOW"; clean
hard="$(run WORKFLOW_NOW_MS=$NOW)"
ok "hard warns"            '[ -n "$hard" ]'
ok "hard forbids handoff"  'printf "%s" "$hard" | jq -r .hookSpecificOutput.additionalContext | grep -q "Do NOT autonomously write"'
rm -f "$TD/claude-ctx-${sess}.json"; clean
ok "missing silent" '[ -z "$(run WORKFLOW_NOW_MS=$NOW)" ]'
printf '{"session_id":"other","remaining_percentage":10,"used_pct":90,"ts":%s}' "$NOW" > "$TD/claude-ctx-other.json"; clean
ok "mismatch silent" '[ -z "$(run WORKFLOW_NOW_MS=$NOW)" ]'
rm -f "$TD/claude-ctx-other.json"
printf '{"session_id":"%s","remaining_perce' "$sess" > "$TD/claude-ctx-${sess}.json"; clean
ok "malformed silent" '[ -z "$(run WORKFLOW_NOW_MS=$NOW)" ]'
ok "malformed exit 0" 'run WORKFLOW_NOW_MS=$NOW >/dev/null 2>&1; [ $? -eq 0 ]'
mkfix 150 0 "$NOW"; clean
ok "bad_value silent" '[ -z "$(run WORKFLOW_NOW_MS=$NOW)" ]'
mkfix 22 78 "$NOW"; clean
ok "disabled silent" '[ -z "$(run WORKFLOW_NOW_MS=$NOW WORKFLOW_DISABLED_HOOKS=context-exhaustion-gate)" ]'
ok "panic silent"    '[ -z "$(run WORKFLOW_NOW_MS=$NOW WORKFLOW_HOOKS_OFF=1)" ]'
mkfix 22 78 "$NOW"; clean
run WORKFLOW_NOW_MS=$NOW >/dev/null 2>&1; ok "never exit 2 (hard)" '[ $? -ne 2 ]'

# monotonic soft burn -> BOUNDED emits (= MAX_WARNS_PER_BAND), not one-per-cooldown
clean; cnt=0
for r in 36 35 34 33 32 31 30 29; do
  mkfix "$r" $((100-r)) $((NOW + (36-r)*200000))
  out="$(run WORKFLOW_NOW_MS=$((NOW + (36-r)*200000)) WORKFLOW_CTX_MAX_WARNS_PER_BAND=3)"
  [ -n "$out" ] && cnt=$((cnt+1))
done
ok "soft burn bounded to 3 emits" '[ "$cnt" -eq 3 ]'
# soft->hard escalates bypassing cooldown
clean; mkfix 33 67 "$NOW"; run WORKFLOW_NOW_MS=$NOW >/dev/null
mkfix 22 78 $((NOW+1000)); esc="$(run WORKFLOW_NOW_MS=$((NOW+1000)))"
ok "soft->hard escalates immediately" 'printf "%s" "$esc" | grep -q "Do NOT autonomously write"'
# HARD periodic re-assert fires at the interval
clean; mkfix 12 88 "$NOW"; run WORKFLOW_NOW_MS=$NOW >/dev/null
reassert=""; for i in $(seq 1 9); do reassert="$(run WORKFLOW_NOW_MS=$((NOW+i*1000)) WORKFLOW_CTX_HARD_REASSERT_CALLS=8)"; done
ok "hard re-assert at interval" 'printf "%s" "$reassert" | grep -q "do NOT autonomously write"'
# deadband: jitter 34<->36 after a soft warn -> no re-warn
clean; mkfix 34 66 "$NOW"; run WORKFLOW_NOW_MS=$NOW >/dev/null
mkfix 36 64 $((NOW+200000)); ok "deadband absorbs jitter" '[ -z "$(run WORKFLOW_NOW_MS=$((NOW+200000)))" ]'
# recovery above soft+deadband resets counter
clean; mkfix 33 67 "$NOW"; run WORKFLOW_NOW_MS=$NOW >/dev/null
mkfix 45 55 $((NOW+300000)); run WORKFLOW_NOW_MS=$((NOW+300000)) >/dev/null
mkfix 33 67 $((NOW+600000)); ok "reset re-warns on next cross" '[ -n "$(run WORKFLOW_NOW_MS=$((NOW+600000)))" ]'
# hard->soft downward handled per table (no spurious emit)
clean; mkfix 22 78 "$NOW"; run WORKFLOW_NOW_MS=$NOW >/dev/null
mkfix 30 70 $((NOW+300000)); ok "hard->soft no spurious emit" '[ -z "$(run WORKFLOW_NOW_MS=$((NOW+300000)))" ]'
# stale ts, last band hard -> DEGRADED emit with age qualifier
clean; mkfix 12 88 "$NOW"; run WORKFLOW_NOW_MS=$NOW >/dev/null
deg="$(run WORKFLOW_NOW_MS=$((NOW+400000)))"
ok "stale+low degraded-emit" 'printf "%s" "$deg" | grep -q "last reading"'
# stale ts, last band healthy -> silent
clean; mkfix 60 40 "$NOW"; run WORKFLOW_NOW_MS=$NOW >/dev/null
ok "stale+healthy silent" '[ -z "$(run WORKFLOW_NOW_MS=$((NOW+400000)))" ]'
# bad thresholds -> defaults (soft fires at 33)
clean; mkfix 33 67 "$NOW"
mis="$(run WORKFLOW_NOW_MS=$NOW WORKFLOW_CTX_SOFT_PCT=20 WORKFLOW_CTX_HARD_PCT=40)"
ok "misconfig falls to defaults (soft fires at 33)" '[ -n "$mis" ]'
# B3 ignores INSTINCTS_DRYRUN
clean; mkfix 33 67 "$NOW"
ok "B3 ignores DRYRUN" '[ -n "$(run WORKFLOW_NOW_MS=$NOW WORKFLOW_INSTINCTS_DRYRUN=1)" ]'
# determinism: same inputs + same NOW -> byte-identical
clean; mkfix 22 78 "$NOW"; a="$(run WORKFLOW_NOW_MS=$NOW)"; clean; b="$(run WORKFLOW_NOW_MS=$NOW)"
ok "deterministic" '[ "$a" = "$b" ]'

# --- audit schema v2 + session field + value-aware retention (D4-4/D4-5, I3) ----------------
# These cases read the per-session audit JSONL. The harness must run B3 OUTSIDE any git repo so
# planning_dir() refuses and resolve_audit_path() falls back to $TMPDIR/wf-audit/phase4.jsonl.
asess="ctxaudit-$$"
AUD="$TD/wf-audit/phase4.jsonl"
amkfix() {
  printf '{"session_id":"%s","remaining_percentage":%s,"used_pct":%s,"ts":%s}' \
    "$asess" "$1" "$2" "$3" > "$TD/claude-ctx-${asess}.json"
}
arun() {  # run B3 from outside the repo (cwd=$TD) so audit lands in $TMPDIR/wf-audit
  printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"x"}}' "$asess" \
    | ( cd "$TD" && env "$@" bash "$HOOK" >/dev/null 2>&1 )
}
aclean() { rm -f "$TD"/wf-ctx/*.warned 2>/dev/null; }

# (1) A healthy PostToolUse must NOT write a "reason":"healthy" line.
rm -f "$AUD" 2>/dev/null; aclean
amkfix 60 40 "$NOW"; arun WORKFLOW_NOW_MS=$NOW
if [ -f "$AUD" ] && grep -q '"reason":"healthy"' "$AUD"; then healthy_logged=1; else healthy_logged=0; fi
ok "healthy run logs no reason:healthy" '[ "$healthy_logged" -eq 0 ]'

# (2) An emitting decision (soft cross) writes a line with "v":2 and a "session" field.
rm -f "$AUD" 2>/dev/null; aclean
amkfix 33 67 "$NOW"; arun WORKFLOW_NOW_MS=$NOW
ok "emit line has v:2"      'tail -n1 "$AUD" | jq -e ".v == 2" >/dev/null 2>&1'
ok "emit line has session"  'tail -n1 "$AUD" | jq -e "(.session|type) == \"string\" and (.session|length) > 0" >/dev/null 2>&1'

# (3) Value-aware trim: put the non-none signal lines FIRST (oldest), then flood with
#     "result":"none" lines so a plain `tail -n max` would DROP the signal lines. Overflow past
#     max+max/4 with WORKFLOW_AUDIT_MAX_LINES=100, then one more emit (soft cross) triggers the
#     trim. The value-aware retention must keep ALL non-none lines despite their age.
rm -f "$AUD" 2>/dev/null; aclean
mkdir -p "$TD/wf-audit" 2>/dev/null
{
  # 3 OLD signal lines first — a naive tail -n 100 over the 203-line file would discard these.
  printf '{"ts_ms":1,"v":2,"decision_id":"S1","hook":"context-exhaustion-gate","event":"PostToolUse","result":"warn","reason":"soft_keep_1"}\n'
  printf '{"ts_ms":2,"v":2,"decision_id":"S2","hook":"context-exhaustion-gate","event":"PostToolUse","result":"block","reason":"hard_keep_2"}\n'
  printf '{"ts_ms":3,"v":2,"decision_id":"S3","hook":"context-exhaustion-gate","event":"PostToolUse","result":"degraded","reason":"stale_keep_3"}\n'
  for i in $(seq 1 200); do
    printf '{"ts_ms":%s,"v":2,"decision_id":"%s","hook":"context-exhaustion-gate","event":"PostToolUse","result":"none","reason":"deadband_hold"}\n' "$i" "$i"
  done
} > "$AUD"
sig_before="$(grep -vc '"result":"none"' "$AUD")"
amkfix 33 67 "$NOW"; arun WORKFLOW_NOW_MS=$NOW WORKFLOW_AUDIT_MAX_LINES=100
sig_after="$(grep -vc '"result":"none"' "$AUD")"
ok "value-aware trim fired (file <= max+max/4)" '[ "$(wc -l < "$AUD")" -le 125 ]'
ok "value-aware trim keeps OLD signal soft_keep_1" 'grep -q "soft_keep_1" "$AUD"'
ok "value-aware trim keeps OLD signal hard_keep_2" 'grep -q "hard_keep_2" "$AUD"'
ok "value-aware trim keeps OLD signal stale_keep_3" 'grep -q "stale_keep_3" "$AUD"'
ok "value-aware trim retains all pre-existing signal lines" '[ "$sig_after" -ge "$sig_before" ]'

t_summary
