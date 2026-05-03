#!/usr/bin/env bats
# DOT-02 -- recipient verification script tests.
# Production code: scripts/verify-recipients.sh (Wave 1, plan 12-03). RED until 12-03 ships.

load 'test_helper'

SCRIPT="$REPO_ROOT/scripts/verify-recipients.sh"

@test "happy_path: exit 0 when template matches active allowlist exactly" {
  CHEZMOI_TMPL="$FIXTURES_DIR/orphan-recipients/happy-path/.chezmoi.yaml.tmpl" \
  AUTHORIZED_HOSTS_MD="$FIXTURES_DIR/orphan-recipients/happy-path/AUTHORIZED-HOSTS.md" \
    run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ OK ]]
}

@test "orphan_in_template: exit 1 when template has a pubkey not in the allowlist" {
  CHEZMOI_TMPL="$FIXTURES_DIR/orphan-recipients/orphan-in-template/.chezmoi.yaml.tmpl" \
  AUTHORIZED_HOSTS_MD="$FIXTURES_DIR/orphan-recipients/orphan-in-template/AUTHORIZED-HOSTS.md" \
    run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ orphan ]]
  [[ "$output" =~ age19x9x9x ]]
}

@test "missing_from_template: exit 1 when allowlist has an active host with no recipient" {
  CHEZMOI_TMPL="$FIXTURES_DIR/orphan-recipients/missing-from-template/.chezmoi.yaml.tmpl" \
  AUTHORIZED_HOSTS_MD="$FIXTURES_DIR/orphan-recipients/missing-from-template/AUTHORIZED-HOSTS.md" \
    run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ missing ]]
  [[ "$output" =~ age18g8g8g ]]
}

@test "ignores_retired: exit 0 when allowlist has a retired row not present in template" {
  CHEZMOI_TMPL="$FIXTURES_DIR/orphan-recipients/ignores-retired/.chezmoi.yaml.tmpl" \
  AUTHORIZED_HOSTS_MD="$FIXTURES_DIR/orphan-recipients/ignores-retired/AUTHORIZED-HOSTS.md" \
    run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "missing_files: exit 1 when CHEZMOI_TMPL points at a nonexistent file" {
  CHEZMOI_TMPL="/tmp/nonexistent-$$.tmpl" \
  AUTHORIZED_HOSTS_MD="$FIXTURES_DIR/orphan-recipients/happy-path/AUTHORIZED-HOSTS.md" \
    run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "not found" ]] || [[ "$output" =~ "FAIL" ]]
}
