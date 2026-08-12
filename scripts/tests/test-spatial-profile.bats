#!/usr/bin/env bats
# Gate for the spatial DevPod profile closure.
# Production artifacts: dot_config/workspaces/profiles/spatial/*

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
PROFILE="$REPO_ROOT/dot_config/workspaces/profiles/spatial"

@test "spatial_profile_dir_exists" {
  test -d "$PROFILE"
}

@test "spatial_dockerfile_base_image_matches_fleet" {
  run grep -Fx "FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04" "$PROFILE/Dockerfile"
  [ "$status" -eq 0 ]
}

# Package assertions must see the apt payload, never the rationale comments. The
# Dockerfile explains why each package is there and therefore NAMES most of them
# in prose: a grep over the whole file passes while the install list is empty,
# and the pre-noble absence check below could never pass at all, because the
# comment contains the very token it forbids.
dockerfile_payload() {
  sed -n '/^RUN apt-get update/,/^$/p' "$PROFILE/Dockerfile" | grep -v '^[[:space:]]*#'
}

payload_has() { # <payload> <pkg>
  printf '%s\n' "$1" | grep -qE "(^|[[:space:]])${2}([[:space:]]|\\\\|\$)"
}

# cairosvg renders through libcairo and picks fonts through fontconfig. Without a
# Cyrillic-capable font the text is dropped with no error at all, so the font
# packages are as load-bearing as the library.
@test "spatial_dockerfile_installs_the_cairo_and_font_layer" {
  payload="$(dockerfile_payload)"
  # An empty extraction would make every loop below vacuous.
  [ -n "$payload" ]
  for pkg in libcairo2 fontconfig fonts-dejavu-core fonts-noto-core; do
    payload_has "$payload" "$pkg" || { echo "missing from the apt payload: $pkg"; return 1; }
  done
}

# The t64 ABI transition renamed the package; the pre-noble name installs nothing
# and fails the build.
@test "spatial_dockerfile_uses_the_t64_glib_package" {
  payload="$(dockerfile_payload)"
  [ -n "$payload" ]
  payload_has "$payload" 'libglib2\.0-0t64'
}

@test "spatial_dockerfile_does_not_use_the_pre_noble_glib_name" {
  # The payload must be non-empty first: an absence check over nothing passes
  # vacuously, which is exactly how this assertion would lie during the red phase.
  payload="$(dockerfile_payload)"
  [ -n "$payload" ]
  ! payload_has "$payload" 'libglib2\.0-0'
}

@test "spatial_dockerfile_installs_the_opencv_and_raster_layer" {
  payload="$(dockerfile_payload)"
  [ -n "$payload" ]
  for pkg in libgl1 poppler-utils imagemagick; do
    payload_has "$payload" "$pkg" || { echo "missing from the apt payload: $pkg"; return 1; }
  done
}

# A profile that installs a Docker daemon nothing uses pays for it on every
# rebuild.
@test "spatial_devcontainer_omits_docker_in_docker" {
  [ -f "$PROFILE/devcontainer.json" ]
  run grep -F "docker-in-docker" "$PROFILE/devcontainer.json"
  [ "$status" -ne 0 ]
}

@test "spatial_devcontainer_sets_workspace_profile" {
  run jq -r '.containerEnv.WORKSPACE_PROFILE' "$PROFILE/devcontainer.json"
  [ "$status" -eq 0 ]
  [ "$output" = "spatial" ]
}

@test "spatial_devcontainer_uses_shared_post_create" {
  run jq -r '.postCreateCommand' "$PROFILE/devcontainer.json"
  [ "$status" -eq 0 ]
  [ "$output" = "bash .devcontainer/post-create.sh" ]
}

@test "spatial_devcontainer_forwards_the_preview_ports" {
  run jq -r '.forwardPorts | @csv' "$PROFILE/devcontainer.json"
  [ "$status" -eq 0 ]
  [ "$output" = "8000,5173" ]
}

# The whole wheel set was verified on 3.12/linux-arm64. `latest` is a standing
# source of "no wheel for the newest interpreter -> build from source -> red".
@test "spatial_mise_pins_python_to_312" {
  run grep -Ex 'python[[:space:]]*=[[:space:]]*"3\.12"' "$PROFILE/mise.toml"
  [ "$status" -eq 0 ]
}

@test "spatial_mise_has_no_floating_python" {
  [ -f "$PROFILE/mise.toml" ]
  run grep -Ex 'python[[:space:]]*=[[:space:]]*"latest"' "$PROFILE/mise.toml"
  [ "$status" -ne 0 ]
}

@test "spatial_mise_carries_the_toolchain" {
  for tool in uv ruff pandoc typst node pnpm jq yq fzf ripgrep fd; do
    run grep -E "^${tool}[[:space:]]*=" "$PROFILE/mise.toml"
    [ "$status" -eq 0 ]
  done
}
