#!/usr/bin/env bash
# Tests for workflow-phase-tracker.sh — runs inside a throwaway git repo.
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(cd "$(dirname "$0")/.." && pwd)/workflow-phase-tracker.sh"
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
( cd "$sandbox" && git init -q && git checkout -q -b feat/test )
run() {
  local name="$1" skill="$2" expect_phase="$3" expect_ledger="$4"  # yes|no
  echo "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"$skill\"}}" \
    | ( cd "$sandbox" && CLAUDE_PROJECT_DIR="$sandbox" bash "$HOOK" >/dev/null 2>&1 ) || true
  got_phase=$(jq -r '.phase // empty' "$sandbox/.planning/workflow-state.json" 2>/dev/null)
  got_ledger=no; [ -f "$sandbox/.planning/LEDGER.tsv" ] && got_ledger=yes
  if [ "$got_phase" = "$expect_phase" ] && [ "$got_ledger" = "$expect_ledger" ]; then
    echo "PASS: $name"; pass=$((pass+1))
  else
    echo "FAIL: $name (phase=$got_phase ledger=$got_ledger)"; fail=$((fail+1))
  fi
}
# D4-8 panic-switch: with the hook disabled (panic OR explicit disable list), a phase-mapping
# Skill must NOT write workflow-state.json and must NOT create LEDGER.tsv. Uses a fresh sandbox
# per case so the absence of state is unambiguous.
run_disabled() {
  local name="$1" skill="$2"; shift 2  # remaining args = NAME=val env assignments
  local sb; sb=$(mktemp -d); ( cd "$sb" && git init -q && git checkout -q -b feat/test )
  echo "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"$skill\"}}" \
    | ( cd "$sb" && env CLAUDE_PROJECT_DIR="$sb" "$@" bash "$HOOK" >/dev/null 2>&1 ) || true
  local state_present=no ledger_present=no
  [ -f "$sb/.planning/workflow-state.json" ] && state_present=yes
  [ -f "$sb/.planning/LEDGER.tsv" ] && ledger_present=yes
  if [ "$state_present" = no ] && [ "$ledger_present" = no ]; then
    echo "PASS: $name"; pass=$((pass+1))
  else
    echo "FAIL: $name (state=$state_present ledger=$ledger_present)"; fail=$((fail+1))
  fi
  rm -rf "$sb"
}
run_disabled "panic off: no state written on executing skill"     "polish-loop" WORKFLOW_HOOKS_OFF=1
run_disabled "disable list: no state written on executing skill"  "polish-loop" WORKFLOW_DISABLED_HOOKS=workflow-phase-tracker

# Fresh-sandbox runner: each case starts from NO prior workflow-state.json, so the
# resulting phase/ledger are unambiguous (used for D19/D20 terminal + read-only maps).
run_fresh() {
  local name="$1" skill="$2" expect_phase="$3" expect_ledger="$4"  # yes|no
  local sb; sb=$(mktemp -d); ( cd "$sb" && git init -q && git checkout -q -b feat/test )
  echo "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"$skill\"}}" \
    | ( cd "$sb" && CLAUDE_PROJECT_DIR="$sb" bash "$HOOK" >/dev/null 2>&1 ) || true
  local got_phase got_ledger=no
  got_phase=$(jq -r '.phase // empty' "$sb/.planning/workflow-state.json" 2>/dev/null)
  [ -f "$sb/.planning/LEDGER.tsv" ] && got_ledger=yes
  if [ "$got_phase" = "$expect_phase" ] && [ "$got_ledger" = "$expect_ledger" ]; then
    echo "PASS: $name"; pass=$((pass+1))
  else
    echo "FAIL: $name (phase=$got_phase ledger=$got_ledger)"; fail=$((fail+1))
  fi
  rm -rf "$sb"
}
# D19: create-pr is terminal -> phase complete, NO LEDGER bootstrap.
run_fresh "create-pr -> complete, no ledger" "create-pr" complete no
# D20: graphify is a read-only query -> phase querying when no prior workflow exists,
# and it must never bootstrap a LEDGER.
run_fresh "graphify -> querying (no prior state), no ledger" "graphify" querying no

run "brainstorming -> designing, no ledger" "superpowers:brainstorming" designing no
# P3 Decision 1b: claude-mem's make-plan/do are NOT wired — phase must not move,
# no LEDGER bootstrap. Phase stays "designing" from the previous run.
run "make-plan is unwired (P3-1b): no transition" "claude-mem:make-plan" designing no
run "do is unwired (P3-1b): no transition"        "claude-mem:do"        designing no
run "polish-loop -> executing, ledger created" "polish-loop" executing yes
# D20 no-downgrade guard: graphify mid-flow (phase already executing) must NOT clobber
# the active phase — it stays executing. Ledger already exists (yes) and is untouched.
run "graphify while executing -> stays executing (no-downgrade)" "graphify" executing yes
ok_json=$(jq -e . "$sandbox/.planning/workflow-state.json" >/dev/null 2>&1 && echo yes || echo no)
residue=$(find "$sandbox/.planning" -name ".wf-state.*" -print -quit)
if [ "$ok_json" = "yes" ] && [ -z "$residue" ]; then
  echo "PASS: state file is valid JSON with no temp residue"; pass=$((pass+1))
else
  echo "FAIL: state json=$ok_json residue=$residue"; fail=$((fail+1))
fi
header=$(head -1 "$sandbox/.planning/LEDGER.tsv")
if [ "$header" = "$(printf 'timestamp\tfiles\toutcome\tgate_result\tnotes')" ]; then
  echo "PASS: ledger header schema"; pass=$((pass+1))
else echo "FAIL: ledger header schema (got '$header')"; fail=$((fail+1)); fi
t_summary
