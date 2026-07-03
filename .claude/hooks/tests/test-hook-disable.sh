#!/usr/bin/env bash
# Advisory hooks must no-op when listed in WORKFLOW_DISABLED_HOOKS, and act otherwise.
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Sandbox repo on a feature branch with an executing-phase state and no ledger,
# so pre-push-contract and commit-integration have something to act on.
sb=$(mktemp -d); trap 'rm -rf "$sb"' EXIT
( cd "$sb" && git init -q && git checkout -q -b feature/x )
mkdir -p "$sb/.planning"
printf '{"phase":"executing","branch":"feature/x","started_at":"t"}' > "$sb/.planning/workflow-state.json"

emit() { # id payload [VAR=val ...] -> stdout, run inside the sandbox
  # NB: use `env` so a NAME=val argument is parsed as an assignment; a bare
  # "$@" prefix would NOT be recognized as an env assignment by bash.
  local id="$1" payload="$2"; shift 2
  echo "$payload" | ( cd "$sb" && env CLAUDE_PROJECT_DIR="$sb" "$@" bash "$DIR/$id.sh" 2>/dev/null )
}

refactor='{"prompt":"please refactor and clean up this module"}'
push='{"tool_name":"Bash","tool_input":{"command":"git push origin feature/x"}}'
commit='{"tool_name":"Bash","tool_result":{"stdout":"[feature/x abc1234] msg"}}'
# workflow-phase-tracker fires on a phase-mapping Skill (executing -> emits the EXECUTING line).
phaseskill='{"tool_name":"Skill","tool_input":{"skill":"polish-loop"}}'

# Positive controls: enabled hooks emit on a triggering payload
ok "suggest-loop-skill emits"  '[ -n "$(emit suggest-loop-skill "$refactor")" ]'
ok "push-review emits"         '[ -n "$(emit push-review "$push")" ]'
ok "pre-push-contract emits"   '[ -n "$(emit pre-push-contract "$push")" ]'
ok "commit-integration emits"  '[ -n "$(emit commit-integration "$commit")" ]'
ok "workflow-phase-tracker emits" '[ -n "$(emit workflow-phase-tracker "$phaseskill")" ]'

# Disabled: each hook is silent on the same payload
ok "suggest-loop-skill silenced" '[ -z "$(emit suggest-loop-skill "$refactor" WORKFLOW_DISABLED_HOOKS=suggest-loop-skill)" ]'
ok "push-review silenced"         '[ -z "$(emit push-review "$push" WORKFLOW_DISABLED_HOOKS=push-review)" ]'
ok "pre-push-contract silenced"   '[ -z "$(emit pre-push-contract "$push" WORKFLOW_DISABLED_HOOKS=pre-push-contract)" ]'
ok "commit-integration silenced"  '[ -z "$(emit commit-integration "$commit" WORKFLOW_DISABLED_HOOKS=commit-integration)" ]'
ok "workflow-phase-tracker silenced" '[ -z "$(emit workflow-phase-tracker "$phaseskill" WORKFLOW_DISABLED_HOOKS=workflow-phase-tracker)" ]'
ok "workflow-phase-tracker panic silenced" '[ -z "$(emit workflow-phase-tracker "$phaseskill" WORKFLOW_HOOKS_OFF=1)" ]'

# --- P5 / Findings Q+P: pins are exercised; subagent-discipline is gated ---
AKIA_TOK="AKIA""IOSFODNN7EXAMPLE"
secretpayload="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"x.py\",\"content\":\"k = \\\"$AKIA_TOK\\\"\"}}"
bigpayload=$(jq -nc --arg c "$(printf 'x\n%.0s' $(seq 501))" \
  '{tool_name:"Write",tool_input:{file_path:"big.txt",content:$c}}')
agentpayload='{"tool_name":"Agent","tool_input":{"prompt":"implement task 3"}}'
# D21: reviewer detection now requires BOTH markers (persona AND verdict prompt),
# so the fixture must carry both for "rubric survives disable" to still hold.
reviewerpayload='{"tool_name":"Agent","tool_input":{"prompt":"You are a Senior Code Reviewer. End with: Ready to merge? Yes/No."}}'

ok "secrets-scan ignores disable list"     '[ -n "$(emit secrets-scan "$secretpayload" WORKFLOW_DISABLED_HOOKS=secrets-scan)" ]'
ok "secrets-scan ignores panic switch"     '[ -n "$(emit secrets-scan "$secretpayload" WORKFLOW_HOOKS_OFF=1)" ]'
ok "large-file-guard ignores disable list" '[ -n "$(emit large-file-guard "$bigpayload" WORKFLOW_DISABLED_HOOKS=large-file-guard)" ]'
ok "subagent-discipline emits in executing" '[ -n "$(emit subagent-discipline "$agentpayload")" ]'
ok "subagent-discipline silenced"           '[ -z "$(emit subagent-discipline "$agentpayload" WORKFLOW_DISABLED_HOOKS=subagent-discipline)" ]'
ok "subagent-discipline rubric survives disable" '[ -n "$(emit subagent-discipline "$reviewerpayload" WORKFLOW_DISABLED_HOOKS=subagent-discipline)" ]'

# shellcheck source=../lib/hooklib.sh
source "$DIR/lib/hooklib.sh"

# --- WORKFLOW_HOOKS_OFF panic switch ---
for t in 1 true yes on TRUE Yes ON; do
  ok "panic [$t] disables a normal hook" '! ( WORKFLOW_HOOKS_OFF='"$t"' hook_enabled "context-exhaustion-gate" )'
done
ok "panic does NOT disable a pinned hook" 'WORKFLOW_HOOKS_OFF=1 hook_enabled "secrets-scan"'
ok "panic unset -> hook enabled"          'hook_enabled "session-instincts"'
ok "panic garbage -> not panic (enabled)" 'WORKFLOW_HOOKS_OFF=maybe hook_enabled "session-instincts"'

t_summary
