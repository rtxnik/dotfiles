#!/usr/bin/env bats
# DOT-01 -- pre-commit hook integration test: real `git commit` with fake age key
# in a sandboxed repo MUST be blocked by the gitleaks hook.
# Production code: .pre-commit-config.yaml + .gitleaks.toml (Wave 1, plan 12-02).
# RED until 12-02 ships.

load 'test_helper'

setup() {
  SANDBOX="$(make_sandbox_repo)"
  export SANDBOX
}

teardown() {
  if [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ]; then
    rm -rf "$SANDBOX"
  fi
}

@test "precommit_blocks_age_key: git commit with fake age key is rejected" {
  cd "$SANDBOX"
  write_fake_age_key "leaked.txt"
  git add leaked.txt
  run git commit -m "should be blocked"
  [ "$status" -ne 0 ]
  [[ "$output" =~ (gitleaks|leak|secret) ]]
}
