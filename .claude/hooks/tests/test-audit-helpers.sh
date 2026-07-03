#!/usr/bin/env bash
# Tests for the F2 hooklib audit helpers: wf_safe_id sanitization+fallback,
# resolve_audit_path resolution+cache, audit_envelope line shape + overrides,
# audit_emit_block/audit_emit_warn one-liners, debounced disabled-skip logging.
# shellcheck source=../lib/hooklib.sh
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../lib/hooklib.sh"

# Isolated TMPDIR per run so caches/markers never leak between test invocations.
TMPDIR="$(mktemp -d)"
export TMPDIR

# 1. wf_safe_id: sanitize + fallback
got=$(bash "$LIB" wf_safe_id 'ab/c:d e')
assert_eq "wf_safe_id sanitizes" "ab_c_d_e" "$got"
got=$(bash "$LIB" wf_safe_id '')
assert_eq "wf_safe_id empty -> nosession" "nosession" "$got"

# 2. resolve_audit_path: outside a repo -> tmp fallback; cached on second call
work="$(mktemp -d)"
out=$(cd "$work" && source "$LIB" && resolve_audit_path sess1 && printf '%s' "$WORKFLOW_AUDIT_PATH")
assert_eq "resolve_audit_path tmp fallback" "${TMPDIR}/wf-audit/phase4.jsonl" "$out"
if [ -s "${TMPDIR}/wf-ctx/sess1.auditpath" ]; then pass "auditpath cached"; else fail "cache file missing"; fi

# 3. resolve_audit_path: inside a repo with .planning -> repo path
repo="$(mktemp -d)"; git -C "$repo" init -q; mkdir -p "$repo/.planning"
out=$(cd "$repo" && source "$LIB" && resolve_audit_path sess2 && printf '%s' "$WORKFLOW_AUDIT_PATH")
assert_eq "resolve_audit_path repo path" "$repo/.planning/audit/phase4.jsonl" "$out"

# 4. audit_envelope: writes one line with the canonical envelope; honors ts/did overrides
log="$(mktemp -d)/audit.jsonl"
( export WORKFLOW_AUDIT_PATH="$log"; source "$LIB"; audit_envelope my-hook PreToolUse block my_reason '{"x":1}' 1234 99 )
line=$(tail -n1 "$log")
assert_eq "envelope ts override"  "1234"      "$(printf '%s' "$line" | jq -r .ts_ms)"
assert_eq "envelope did override" "99"        "$(printf '%s' "$line" | jq -r .decision_id)"
assert_eq "envelope hook"         "my-hook"   "$(printf '%s' "$line" | jq -r .hook)"
assert_eq "envelope result"       "block"     "$(printf '%s' "$line" | jq -r .result)"
assert_eq "envelope reason"       "my_reason" "$(printf '%s' "$line" | jq -r .reason)"
assert_eq "envelope v"            "2"         "$(printf '%s' "$line" | jq -r .v)"
assert_eq "envelope extra merged" "1"         "$(printf '%s' "$line" | jq -r .x)"

# 5. audit_emit_block: resolves path from $INPUT session_id when unset
work2="$(mktemp -d)"
( cd "$work2" && source "$LIB" \
  && INPUT='{"session_id":"sessB"}' && audit_emit_block some-hook some_reason )
blockline=$(tail -n1 "${TMPDIR}/wf-audit/phase4.jsonl")
assert_eq "emit_block result" "block"     "$(printf '%s' "$blockline" | jq -r .result)"
assert_eq "emit_block hook"   "some-hook" "$(printf '%s' "$blockline" | jq -r .hook)"

# 6. wf_log_skip_debounced: first call logs, second call debounces
n0=$(wc -l < "${TMPDIR}/wf-audit/phase4.jsonl")
( cd "$work2" && source "$LIB" && wf_log_skip_debounced merge-gate && wf_log_skip_debounced merge-gate )
n1=$(wc -l < "${TMPDIR}/wf-audit/phase4.jsonl")
assert_eq "skip logged exactly once" "$((n0+1))" "$n1"
skipline=$(tail -n1 "${TMPDIR}/wf-audit/phase4.jsonl")
assert_eq "skip result" "skip" "$(printf '%s' "$skipline" | jq -r .result)"

t_summary
