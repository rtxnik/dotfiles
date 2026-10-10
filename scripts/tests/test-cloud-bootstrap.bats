#!/usr/bin/env bats
# Gate for the cloud-session bootstrap.
# Production artifacts: dot_config/workspaces/cloud/*

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
CLOUD="$REPO_ROOT/dot_config/workspaces/cloud"

@test "cloud_scripts_parse" {
  for script in loader.sh setup.sh doctor.sh; do
    bash -n "$CLOUD/$script" || { echo "syntax error: $script"; return 1; }
  done
}

# A setup script that exits non-zero stops every session from starting.
@test "cloud_scripts_end_in_exit_0" {
  for script in loader.sh setup.sh; do
    [ "$(grep -v '^[[:space:]]*$' "$CLOUD/$script" | tail -1)" = "exit 0" ] ||
      { echo "$script does not end in exit 0"; return 1; }
  done
}

@test "cloud_loader_runs_the_bootstrap_that_exists" {
  path="$(grep -o 'dot_config/workspaces/cloud/[a-z]*\.sh' "$CLOUD/loader.sh")"
  [ "$path" = "dot_config/workspaces/cloud/setup.sh" ]
  test -f "$REPO_ROOT/$path"
}

@test "cloud_settings_carry_the_owner_identity" {
  for key in GIT_AUTHOR GIT_COMMITTER; do
    run jq -r ".env.${key}_NAME + \" <\" + .env.${key}_EMAIL + \">\"" "$CLOUD/settings.json"
    [ "$status" -eq 0 ]
    [ "$output" = "rtxnik <rtxs.nik@gmail.com>" ]
  done
}

@test "cloud_settings_switch_attribution_off" {
  run jq -e '.attribution == {"commit": "", "pr": "", "sessionUrl": false}' "$CLOUD/settings.json"
  [ "$status" -eq 0 ]
}

# A plugin installed but not enabled never loads; one enabled but not installed
# is a dangling entry. The two lists must name the same plugins.
@test "cloud_installed_plugins_are_the_enabled_ones" {
  installed="$(sed -n '/^PLUGINS=(/,/^)/p' "$CLOUD/setup.sh" | grep -v '[()]' | tr -d ' ' | sort)"
  enabled="$(jq -r '.enabledPlugins | to_entries[] | select(.value) | .key' "$CLOUD/settings.json" | sort)"
  [ -n "$installed" ]
  [ "$installed" = "$enabled" ]
}

@test "cloud_instructions_forbid_attribution_and_name_the_owner" {
  grep -q 'No AI attribution anywhere' "$CLOUD/instructions.md"
  grep -q 'rtxnik <rtxs.nik@gmail.com>' "$CLOUD/instructions.md"
}

@test "cloud_doctor_fails_on_a_foreign_identity" {
  cd "$BATS_TEST_TMPDIR"
  git init -q .
  CLOUD_DOCTOR_OFFLINE=1 HOME="$BATS_TEST_TMPDIR" \
    GIT_AUTHOR_NAME=Someone GIT_AUTHOR_EMAIL=someone@example.com \
    GIT_COMMITTER_NAME=Someone GIT_COMMITTER_EMAIL=someone@example.com \
    run bash "$CLOUD/doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISS  AUTHOR"* ]]
}

@test "cloud_doctor_passes_the_owner_identity" {
  cd "$BATS_TEST_TMPDIR"
  git init -q .
  CLOUD_DOCTOR_OFFLINE=1 HOME="$BATS_TEST_TMPDIR" \
    GIT_AUTHOR_NAME=rtxnik GIT_AUTHOR_EMAIL=rtxs.nik@gmail.com \
    GIT_COMMITTER_NAME=rtxnik GIT_COMMITTER_EMAIL=rtxs.nik@gmail.com \
    run bash "$CLOUD/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok    AUTHOR rtxnik <rtxs.nik@gmail.com>"* ]]
}
