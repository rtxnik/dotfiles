#!/usr/bin/env bash
# Tests for subagent-discipline.sh — uses an isolated CLAUDE_PROJECT_DIR sandbox.
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(cd "$(dirname "$0")/.." && pwd)/subagent-discipline.sh"
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
run() {
  local name="$1" input="$2" expect="$3"   # discipline|rubric|silent
  out=$(cd "$sandbox" && echo "$input" | CLAUDE_PROJECT_DIR="$sandbox" bash "$HOOK" 2>&1) || true
  got=silent
  if echo "$out" | grep -q 'Code Review Rubric'; then got=rubric
  elif echo "$out" | grep -q 'WORKFLOW DISCIPLINE'; then got=discipline; fi
  if [ "$got" = "$expect" ]; then echo "PASS: $name"; pass=$((pass+1));
  else echo "FAIL: $name (got $got)"; fail=$((fail+1)); fi
}
# D21: reviewer detection requires the marker PAIR (AND) — the real superpowers
# code-reviewer template carries BOTH 'Senior Code Reviewer' and 'Ready to merge?'.
reviewer='{"tool_name":"Agent","tool_input":{"description":"Review code changes","prompt":"You are a Senior Code Reviewer with expertise in software architecture. End with your verdict: Ready to merge? Yes/No."}}'
# Anti-spoof: a prompt carrying only ONE marker must NOT trigger the rubric.
lone_persona='{"tool_name":"Agent","tool_input":{"prompt":"You are a Senior Code Reviewer with expertise in software architecture."}}'
lone_verdict='{"tool_name":"Agent","tool_input":{"prompt":"...your verdict: Ready to merge? Yes/No..."}}'

run "no state silent" '{"tool_name":"Agent","tool_input":{}}' silent
run "reviewer with no state gets rubric" "$reviewer" rubric
mkdir -p "$sandbox/.planning"; echo '{"phase":"executing"}' > "$sandbox/.planning/workflow-state.json"
run "executing injects discipline" '{"tool_name":"Agent","tool_input":{"prompt":"implement task 3"}}' discipline
run "reviewer in executing gets rubric (not discipline)" "$reviewer" rubric
run "non-agent silent" '{"tool_name":"Bash","tool_input":{}}' silent
echo '{"phase":"planning"}' > "$sandbox/.planning/workflow-state.json"
run "planning silent for non-reviewer" '{"tool_name":"Agent","tool_input":{"prompt":"research the API"}}' silent
run "reviewer in planning gets rubric" "$reviewer" rubric
# Anti-spoof negatives (D21): one marker alone is silent in executing (where lone
# 'persona' would otherwise be just another agent and get discipline — proving the
# pair is required, lone_persona must NOT get the rubric).
echo '{"phase":"planning"}' > "$sandbox/.planning/workflow-state.json"
run "lone persona marker is silent (anti-spoof)" "$lone_persona" silent
run "lone ready-to-merge marker is silent (anti-spoof)" "$lone_verdict" silent
t_summary
