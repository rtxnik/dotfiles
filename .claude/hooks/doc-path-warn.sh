#!/usr/bin/env bash
# PreToolUse(Edit|Write) hook: warn-only. Flags ad-hoc scratch docs (report/summary/findings/
# notes/...) written to arbitrary paths and points to the canonical homes. Never blocks.
# Narrow EXACT lowercased-stem denylist so it never fights ADRs, dated specs/plans, or skills.
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
hook_enabled "doc-path-warn" || exit 0
hook_read_input
case "$TOOL_NAME" in Edit|Write) ;; *) exit 0 ;; esac

file_path=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file_path" ] && exit 0

# Allowlist the canonical doc/planning homes — never warn there.
case "$file_path" in
  *docs/superpowers/specs/*|*docs/superpowers/plans/*|*/.planning/*|.planning/*) exit 0 ;;
esac

base=$(basename -- "$file_path")
stem="${base%.*}"                                  # drop a single extension
stem_lc=$(printf '%s' "$stem" | tr '[:upper:]' '[:lower:]')

DENY="report summary findings analysis notes scratch temp draft wip"
case " $DENY " in
  *" $stem_lc "*) ;;                               # ad-hoc scratch name
  *) exit 0 ;;                                     # specific/real name -> fine
esac

audit_emit_warn doc-path-warn doc_path_hint
emit_additional_context PreToolUse "doc-path-warn: '$file_path' looks like an ad-hoc scratch doc ('$stem'). The workflow forbids loose scratch docs. Put durable design docs in docs/superpowers/specs/ or docs/superpowers/plans/, planning artifacts in .planning/, and record transient findings in .planning/LEDGER.tsv or claude-mem — not a standalone file. If this is a real deliverable, give it a specific descriptive name. Disable with WORKFLOW_DISABLED_HOOKS=doc-path-warn."
exit 0
