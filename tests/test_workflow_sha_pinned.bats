#!/usr/bin/env bats
# DOT-01 -- static check: every `uses:` in validate.yml must be SHA-pinned (40-hex)
# and the gitleaks job must invoke verify-recipients.sh.
# Production code: .github/workflows/validate.yml gitleaks job (Wave 1, plan 12-02).
# RED until 12-02 ships.

load 'test_helper'

WORKFLOW="$REPO_ROOT/.github/workflows/validate.yml"

@test "workflow_exists: validate.yml exists" {
  test -f "$WORKFLOW"
}

@test "workflow_no_tag_pinned_actions: every uses: line is 40-hex SHA pinned" {
  # Find any `uses: x@<not-40-hex>` line.
  run bash -c "grep -E '^\\s*uses:\\s*\\S+@' '$WORKFLOW' | grep -Ev '@[0-9a-f]{40}([[:space:]]|\$|#)' || true"
  # If output is empty, all uses: lines are SHA-pinned.
  [ -z "$output" ]
}

@test "workflow_has_gitleaks_job: jobs.gitleaks block present" {
  run grep -E '^\s+gitleaks:' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "workflow_gitleaks_action_pinned_to_v239: gitleaks-action SHA matches v2.3.9" {
  run grep -F "gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "workflow_gitleaks_job_runs_verify_script: scripts/verify-recipients.sh invoked" {
  run grep -F "scripts/verify-recipients.sh" "$WORKFLOW"
  [ "$status" -eq 0 ]
}
