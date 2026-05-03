#!/usr/bin/env bats
# DOT-03 -- SECURITY-INCIDENTS.md baseline-entry static check.
# Production code: docs/SECURITY-INCIDENTS.md (Wave 1, plan 12-04).
# RED until 12-04 ships.

load 'test_helper'

INCIDENTS="$REPO_ROOT/docs/SECURITY-INCIDENTS.md"

@test "incidents_file_exists: docs/SECURITY-INCIDENTS.md exists" {
  test -f "$INCIDENTS"
}

@test "incidents_has_d12_baseline_string: literal '(no incidents recorded as of 2026-05-03)' present" {
  test -f "$INCIDENTS"
  run grep -F "(no incidents recorded as of 2026-05-03)" "$INCIDENTS"
  [ "$status" -eq 0 ]
}

@test "incidents_documents_rotate_not_rewrite_policy: rotate-not-rewrite mention present" {
  test -f "$INCIDENTS"
  run grep -iE 'rotat.*not.*rewrit|rotat.*rewrit' "$INCIDENTS"
  [ "$status" -eq 0 ]
}

@test "incidents_has_entry_template: D-12 template fields present" {
  test -f "$INCIDENTS"
  for field in "Severity" "Scope" "Discovery" "Affected secrets" "Rotation log" "References"; do
    grep -F "$field" "$INCIDENTS" || {
      echo "FAIL: missing template field: $field" >&2
      return 1
    }
  done
}
