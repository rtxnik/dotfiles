#!/usr/bin/env bats
# DOT-01 -- .gitleaks.toml validity tests.
# Production code: .gitleaks.toml at repo root (Wave 1, plan 12-02). RED until 12-02 ships.

load 'test_helper'

CONFIG="$REPO_ROOT/.gitleaks.toml"

@test "gitleaks_config_valid: gitleaks parses .gitleaks.toml without error" {
  cd "$REPO_ROOT"
  run gitleaks git --no-git --config .gitleaks.toml --no-banner
  [ "$status" -eq 0 ]
}

@test "gitleaks_config_extends_defaults: useDefault = true present" {
  test -f "$CONFIG"
  run grep -E 'useDefault\s*=\s*true' "$CONFIG"
  [ "$status" -eq 0 ]
}

@test "gitleaks_config_allowlists_secrets_fixture_path: tests/fixtures/secrets path entry present" {
  test -f "$CONFIG"
  run grep -F 'tests/fixtures/secrets' "$CONFIG"
  [ "$status" -eq 0 ]
}

@test "gitleaks_config_allowlists_placeholder_pubkeys: anchored placeholder regex present" {
  test -f "$CONFIG"
  run grep -E 'age1\[a-z\]\*placeholder\[a-z0-9\]\+' "$CONFIG"
  [ "$status" -eq 0 ]
}

@test "gitleaks_config_no_redundant_age_rule: no custom rule with id=age-secret-key" {
  test -f "$CONFIG"
  # Per Open Q1 + 12-RESEARCH: gitleaks 8.30.1 default ruleset already includes
  # `id = "age-secret-key"` with the canonical bech32 alphabet; a custom rule
  # would either conflict (same id) or be strictly looser. Defaults suffice.
  run bash -c "grep -A 2 '^\\[\\[rules\\]\\]' '$CONFIG' | grep -E 'id\\s*=\\s*\"age-secret-key\"'"
  [ "$status" -ne 0 ]
}
