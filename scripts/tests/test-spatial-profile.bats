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

SCRIPT="$PROFILE/post-create-spatial.sh"

# The bootstrap is exercised against a fixture, never against the real HOME.
setup_spatial_fixture() {
  FIXTURE="$(mktemp -d -t spatial-fixture-XXXXXXXX)"
  WSDIR="$FIXTURE/ws"
  SEEDSRC="$FIXTURE/seed"
  mkdir -p "$WSDIR" "$SEEDSRC" "$FIXTURE/links"
  printf '[project]\nname = "seeded"\n' > "$SEEDSRC/pyproject.toml"
  printf 'help:\n\t@echo ok\n' > "$SEEDSRC/Makefile"
  printf '.venv/\n' > "$SEEDSRC/.gitignore"
  printf '# CLAUDE.md — conversion study\n' > "$SEEDSRC/CLAUDE.md"
  printf '# Conversion study\n' > "$SEEDSRC/README.md"
}

run_bootstrap() {
  env SPATIAL_PROJECT_ROOT="$WSDIR" \
      SPATIAL_SEED_DIR="$SEEDSRC" \
      SPATIAL_LINK_DIR="$FIXTURE/links" \
      SPATIAL_SKIP_SYNC=1 \
      SPATIAL_SKIP_TOOLCHAIN=1 \
      SPATIAL_SKIP_DOCTOR=1 \
      bash "$SCRIPT"
}

teardown() {
  [ -n "${FIXTURE:-}" ] && rm -rf "$FIXTURE"
  return 0
}

@test "spatial_bootstrap_is_executable_and_shellcheck_clean" {
  test -x "$SCRIPT"
  if command -v shellcheck >/dev/null 2>&1; then
    run shellcheck --severity=warning "$SCRIPT"
    [ "$status" -eq 0 ]
  fi
}

# The shared post-create.sh exports ~/.local/bin but never activates mise, so a
# bootstrap that does not activate it cannot see the pinned toolchain.
@test "spatial_bootstrap_activates_mise" {
  run grep -F 'mise activate bash' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "spatial_bootstrap_seeds_an_empty_folder" {
  setup_spatial_fixture
  run run_bootstrap
  [ "$status" -eq 0 ]
  test -f "$WSDIR/pyproject.toml"
  test -f "$WSDIR/Makefile"
  # A dotfile in the seed must survive the copy — `cp -r src/. dst/` is chosen
  # over a glob for exactly this reason.
  test -f "$WSDIR/.gitignore"
}

@test "spatial_bootstrap_creates_the_directory_skeleton" {
  setup_spatial_fixture
  run run_bootstrap
  [ "$status" -eq 0 ]
  for d in model source scripts tests out docs; do
    test -d "$WSDIR/$d"
  done
}

@test "spatial_bootstrap_refuses_to_seed_over_an_existing_project" {
  setup_spatial_fixture
  printf '[project]\nname = "mine"\n' > "$WSDIR/pyproject.toml"
  run run_bootstrap
  [ "$status" -eq 0 ]
  # $output belongs to the LAST `run`, so it has to be captured before any other
  # `run` overwrites it — otherwise the assertion at the end of this test would
  # inspect grep's output and fail forever.
  bootstrap_output="$output"
  # The operator's file is untouched...
  run grep -F 'name = "mine"' "$WSDIR/pyproject.toml"
  [ "$status" -eq 0 ]
  # ...and the seed did not land alongside it.
  [ ! -f "$WSDIR/Makefile" ]
  # The manual path is printed, otherwise the skeleton is unreachable.
  [[ "$bootstrap_output" == *"cp -rn $SEEDSRC/. $WSDIR/"* ]]
}

@test "spatial_bootstrap_refuses_to_seed_over_a_git_checkout" {
  setup_spatial_fixture
  mkdir -p "$WSDIR/.git"
  run run_bootstrap
  [ "$status" -eq 0 ]
  [ ! -f "$WSDIR/pyproject.toml" ]
}

@test "spatial_bootstrap_symlinks_the_conventional_path" {
  setup_spatial_fixture
  run run_bootstrap
  [ "$status" -eq 0 ]
  test -L "$FIXTURE/links/ws"
  [ "$(readlink "$FIXTURE/links/ws")" = "$WSDIR" ]
}

# A real directory at the conventional path is someone else's data. Capturing
# it with a symlink would point every later instruction at the wrong tree.
@test "spatial_bootstrap_leaves_a_real_directory_at_the_link_path_untouched" {
  setup_spatial_fixture
  mkdir -p "$FIXTURE/links/ws"
  echo "foreign" > "$FIXTURE/links/ws/DATA"
  run run_bootstrap
  [ "$status" -eq 0 ]
  [ ! -L "$FIXTURE/links/ws" ]
  test -f "$FIXTURE/links/ws/DATA"
  [[ "$output" == *"WARNING"* ]]
}

@test "spatial_bootstrap_is_idempotent" {
  setup_spatial_fixture
  run run_bootstrap
  [ "$status" -eq 0 ]
  echo "edited by hand" >> "$WSDIR/Makefile"
  run run_bootstrap
  [ "$status" -eq 0 ]
  # Second run must not overwrite work: after the first seed the folder holds a
  # pyproject.toml, so the seed is skipped entirely.
  run grep -F "edited by hand" "$WSDIR/Makefile"
  [ "$status" -eq 0 ]
}

@test "spatial_bootstrap_survives_a_missing_seed_directory" {
  setup_spatial_fixture
  rm -rf "$SEEDSRC"
  run run_bootstrap
  [ "$status" -eq 0 ]
  test -L "$FIXTURE/links/ws"
}

# An interrupted copy that already placed pyproject.toml would make every later
# boot skip the seed as "already a project", leaving the skeleton permanently
# half-built and silent about it.
@test "spatial_bootstrap_reports_an_incomplete_seed" {
  setup_spatial_fixture
  rm -f "$SEEDSRC/Makefile"
  run run_bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"seed is incomplete"* ]]
  [[ "$output" == *"Makefile"* ]]
  [[ "$output" == *"cp -rn $SEEDSRC/. $WSDIR/"* ]]
}

# The shared post-create.sh calls this script with no `|| true` under its own
# set -e, so a non-zero exit here aborts container creation over a symlink.
@test "spatial_bootstrap_survives_an_unwritable_link_dir" {
  setup_spatial_fixture
  mkdir -p "$FIXTURE/ro"
  chmod 500 "$FIXTURE/ro"
  run env SPATIAL_PROJECT_ROOT="$WSDIR" \
      SPATIAL_SEED_DIR="$SEEDSRC" \
      SPATIAL_LINK_DIR="$FIXTURE/ro/links" \
      SPATIAL_SKIP_SYNC=1 SPATIAL_SKIP_TOOLCHAIN=1 SPATIAL_SKIP_DOCTOR=1 \
      bash "$SCRIPT"
  chmod 700 "$FIXTURE/ro"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING"* ]]
  # The seed still happened: a link failure must not cost the operator the skeleton.
  test -f "$WSDIR/pyproject.toml"
}

# `seed_project` runs as `seed_project || true`, which suspends errexit for the
# whole function body — without an explicit status check a failed mkdir falls
# through to `return 0` and reports a half-built skeleton as complete.
@test "spatial_bootstrap_reports_a_failed_directory_skeleton" {
  setup_spatial_fixture
  # A regular file where a skeleton directory must go makes mkdir -p fail.
  printf 'not a directory\n' > "$WSDIR/model"
  run run_bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not create the directory skeleton"* ]]
}
