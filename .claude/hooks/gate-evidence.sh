#!/usr/bin/env bash
# PostToolUse(Bash) hook (F4 / D4-2): records an append-only observation of every acceptance-gate
# run during phase=executing, so the LEDGER's self-reported gate_result becomes cross-checkable
# (pre-push warns on kept rows with no observed passing run; create-pr stops checking unverified
# Test Plan claims). A PostToolUse hook CANNOT block — this hook NEVER exits 2; it only appends
# ONE JSONL line to .planning/gate-evidence.log and exits 0. The recorded status is resolved
# DEFENSIVELY from tool_response (the Bash exit-code sub-field is undocumented): numeric exit ->
# boolean success/error -> stdout/stderr markers -> honest "unknown". Append-only RAW OBSERVATION,
# never a signed attestation (no crypto). Fail-open everywhere.
# Disable: WORKFLOW_DISABLED_HOOKS=gate-evidence  (or WORKFLOW_GATE_EVIDENCE=off to keep the hook
# wired but silent). Not pinned, not fail-closed (a recorder, never a gate).
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
hook_enabled "gate-evidence" || exit 0
hook_read_input
[ "$TOOL_NAME" != "Bash" ] && exit 0
[ "$(hook_phase)" = "executing" ] || exit 0

command=$(hook_command)
[ -z "$command" ] && exit 0
kind=$(gate_cmd_kind "$command")
[ -n "$kind" ] || exit 0          # not an acceptance-gate command -> record nothing

# Sanitize the command for storage: strip control chars, keep first 200 bytes.
cmd=$(printf '%s' "$command" | tr -d '\000-\037' | LC_ALL=C cut -c1-200)

# resolve_gate_status echoes "<status>\t<exit>\t<src>". Use cut, NOT `IFS=$'\t' read`: tab is an
# IFS-whitespace char, so `read` collapses the empty middle field (exit) of marker/boolean rungs
# and drops src (verified defect). cut -f preserves empty fields.
ev=$(printf '%s' "$INPUT" | jq -c '.tool_response // .tool_result // {}' 2>/dev/null | resolve_gate_status)
status=$(printf '%s' "$ev" | cut -f1)
exit_v=$(printf '%s' "$ev" | cut -f2)
src=$(printf '%s' "$ev" | cut -f3)

gate_evidence_log "${status:-unknown}" "${exit_v:-}" "$kind" "$cmd" "${src:-none}"
exit 0
