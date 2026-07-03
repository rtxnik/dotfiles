#!/usr/bin/env bash
# UserPromptSubmit hook: route a prompt toward the matching CLAUDE.md entry point
# (root CLAUDE.md "Entry Points" table — all 5). Matches keywords against the
# extracted .prompt field, NOT the raw JSON envelope (Finding T). Advisory only:
# plain stdout on UserPromptSubmit is injected into the model's context.
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
hook_enabled "suggest-loop-skill" || exit 0
hook_read_input
prompt=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
[ -z "$prompt" ] && exit 0
shopt -s nocasematch
# Order matters: first match wins. Optimization before polish (optimization prompts
# often contain refactor-ish words too); debugging before feature (bug reports often
# say "make it work").
if [[ "$prompt" =~ (optimi[sz]|оптимиз|bundle|latency|p95|ускор|быстрее|faster|smaller) ]]; then
  audit_emit_warn suggest-loop-skill loop_skill_hint UserPromptSubmit
  echo "[hint] Metric-optimization task → invoke 'optimization-loop' (baseline first, keep/revert by the number, log to .planning/LEDGER.tsv)."
elif [[ "$prompt" =~ (polish|polir|refactor|рефактор|clean[-_\ ]?up|cleanup|почист|чист|dedup|deduplicat|дубл|extract|извлеч|вынес) ]]; then
  echo "[hint] Focused-change task → invoke 'polish-loop' (behavior-preserving cleanup/refactor — one surface, fix-budget, ship a test)."
elif [[ "$prompt" =~ (debug|bug|баг|broken|слома|crash|пада|not\ work|не\ работает|fail(s|ing|ed)|ошибк|разбер) ]]; then
  echo "[hint] Bug investigation → invoke 'systematic-debugging' (reproduce first; no fix without understanding the root cause)."
elif [[ "$prompt" =~ (code\ ?review|review\ (the\ |this\ |my\ )?(code|pr|diff|changes)|ревью|проверь\ (код|изменения)) ]]; then
  echo "[hint] Code review → invoke 'code-review' (the one review path; rubric-driven)."
elif [[ "$prompt" =~ (new\ feature|implement|новую?\ фичу|новая\ фича|реализуй|add\ support|создай|build\ a\ ) ]]; then
  echo "[hint] New feature → invoke 'brainstorming' (explore intent and design before any code)."
fi
exit 0
