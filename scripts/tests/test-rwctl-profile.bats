#!/usr/bin/env bats
# Gate for the rwctl DevPod profile closure.
# Production artifacts: dot_config/workspaces/profiles/rwctl/*

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
PROFILE="$REPO_ROOT/dot_config/workspaces/profiles/rwctl"

@test "rwctl_profile_dir_exists" {
  test -d "$PROFILE"
}

@test "rwctl_dockerfile_base_image_matches_fleet" {
  run grep -Fx "FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04" "$PROFILE/Dockerfile"
  [ "$status" -eq 0 ]
}

@test "rwctl_dockerfile_installs_build_essential_for_race_detector" {
  run grep -F "build-essential" "$PROFILE/Dockerfile"
  [ "$status" -eq 0 ]
}

@test "rwctl_dockerfile_omits_openssl" {
  # The file must exist first: grep also exits non-zero on a missing file, so a
  # bare absence-check would pass vacuously during the red phase.
  [ -f "$PROFILE/Dockerfile" ]
  run grep -Ew "openssl" "$PROFILE/Dockerfile"
  [ "$status" -ne 0 ]
}

@test "rwctl_mise_pins_go_to_ci_version" {
  run grep -Ex 'go[[:space:]]*=[[:space:]]*"1\.25"' "$PROFILE/mise.toml"
  [ "$status" -eq 0 ]
}

@test "rwctl_mise_has_no_floating_go" {
  [ -f "$PROFILE/mise.toml" ]
  run grep -Ex 'go[[:space:]]*=[[:space:]]*"latest"' "$PROFILE/mise.toml"
  [ "$status" -ne 0 ]
}

@test "rwctl_mise_carries_required_tools" {
  for tool in golangci-lint goreleaser node jq yq fzf ripgrep fd; do
    run grep -E "^${tool}[[:space:]]*=" "$PROFILE/mise.toml"
    [ "$status" -eq 0 ]
  done
}

@test "rwctl_mise_excludes_release_only_tools" {
  [ -f "$PROFILE/mise.toml" ]
  for tool in cosign syft; do
    run grep -E "^${tool}[[:space:]]*=" "$PROFILE/mise.toml"
    [ "$status" -ne 0 ]
  done
}

@test "rwctl_devcontainer_is_valid_json" {
  run jq -e . "$PROFILE/devcontainer.json"
  [ "$status" -eq 0 ]
}

@test "rwctl_devcontainer_enables_docker_in_docker" {
  run jq -e '.features["ghcr.io/devcontainers/features/docker-in-docker:2"]' "$PROFILE/devcontainer.json"
  [ "$status" -eq 0 ]
}

@test "rwctl_devcontainer_sets_workspace_profile" {
  run jq -er '.containerEnv.WORKSPACE_PROFILE' "$PROFILE/devcontainer.json"
  [ "$status" -eq 0 ]
  [ "$output" = "rwctl" ]
}

@test "rwctl_devcontainer_uses_shared_post_create" {
  run jq -er '.postCreateCommand' "$PROFILE/devcontainer.json"
  [ "$status" -eq 0 ]
  [ "$output" = "bash .devcontainer/post-create.sh" ]
}
