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

SCRIPT="$PROFILE/post-create-rwctl.sh"

# A local bare repo stands in for the private remote, so the clone path is
# exercised without network or credentials.
setup_rwctl_fixture() {
  FIXTURE="$(mktemp -d -t rwctl-fixture-XXXXXXXX)"
  SEED="$FIXTURE/seed"
  REMOTE="$FIXTURE/rwctl.git"
  WSDIR="$FIXTURE/ws"
  mkdir -p "$SEED" "$WSDIR"
  git init --quiet --initial-branch=main "$SEED"
  git -C "$SEED" config user.email "test@example.invalid"
  git -C "$SEED" config user.name "rwctl profile test"
  echo "first" > "$SEED/README.md"
  git -C "$SEED" add README.md
  git -C "$SEED" commit --quiet -m "seed"
  git clone --quiet --bare "$SEED" "$REMOTE"
  # The bare clone knows SEED, but SEED has no remote — add it so a later test
  # can push a second commit and prove the refresh path picks it up.
  git -C "$SEED" remote add origin "$REMOTE"
}

run_bootstrap() {
  env RWCTL_REPO_SSH="$REMOTE" \
      RWCTL_REPO_SLUG="rwctl.git" \
      RWCTL_CHECKOUT_ROOT="$WSDIR" \
      RWCTL_LINK_DIR="$FIXTURE/links" \
      RWCTL_SKIP_TOOLCHAIN=1 \
      bash "$SCRIPT"
}

teardown() {
  [ -n "${FIXTURE:-}" ] && rm -rf "$FIXTURE"
  return 0
}

@test "rwctl_bootstrap_is_executable_and_shellcheck_clean" {
  test -x "$SCRIPT"
  if command -v shellcheck >/dev/null 2>&1; then
    run shellcheck --severity=warning "$SCRIPT"
    [ "$status" -eq 0 ]
  fi
}

@test "rwctl_bootstrap_activates_mise_before_tool_installs" {
  run grep -F 'mise activate bash' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "rwctl_bootstrap_pins_the_factory_cli_to_an_immutable_tag" {
  run grep -F 'workflow-factory@v1.0.5#subdirectory=tooling' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "rwctl_bootstrap_clones_into_the_workspace_folder_not_home_projects" {
  setup_rwctl_fixture
  run run_bootstrap
  [ "$status" -eq 0 ]
  test -f "$WSDIR/rwctl/README.md"
  # On a confirmed-ours checkout the recovery hint IS printed — this pins the
  # positive direction against the foreign-worktree test's negative one below.
  [[ "$output" == *"git -C $WSDIR/rwctl pull"* ]]
}

@test "rwctl_bootstrap_symlinks_the_conventional_path" {
  setup_rwctl_fixture
  run run_bootstrap
  [ "$status" -eq 0 ]
  test -L "$FIXTURE/links/rwctl"
  [ "$(readlink "$FIXTURE/links/rwctl")" = "$WSDIR/rwctl" ]
}

@test "rwctl_bootstrap_is_idempotent" {
  setup_rwctl_fixture
  run run_bootstrap
  [ "$status" -eq 0 ]
  run run_bootstrap
  [ "$status" -eq 0 ]
  test -f "$WSDIR/rwctl/README.md"
}

@test "rwctl_bootstrap_fast_forwards_an_existing_checkout" {
  setup_rwctl_fixture
  run run_bootstrap
  [ "$status" -eq 0 ]
  # A later push to the remote must reach the existing checkout on re-run.
  echo "second" > "$SEED/LATER.md"
  git -C "$SEED" add LATER.md
  git -C "$SEED" commit --quiet -m "later"
  git -C "$SEED" push --quiet origin main
  run run_bootstrap
  [ "$status" -eq 0 ]
  test -f "$WSDIR/rwctl/LATER.md"
}

@test "rwctl_bootstrap_leaves_a_foreign_worktree_untouched" {
  setup_rwctl_fixture
  mkdir -p "$WSDIR/rwctl"
  git init --quiet --initial-branch=main "$WSDIR/rwctl"
  git -C "$WSDIR/rwctl" remote add origin "https://example.invalid/someone/other.git"
  echo "mine" > "$WSDIR/rwctl/UNTRACKED.md"
  run run_bootstrap
  [ "$status" -eq 0 ]
  bootstrap_output="$output"
  test -f "$WSDIR/rwctl/UNTRACKED.md"
  run git -C "$WSDIR/rwctl" remote get-url origin
  [ "$output" = "https://example.invalid/someone/other.git" ]
  # "Untouched" includes the conventional path: it must NOT be pointed at a
  # foreign tree, or the documented recovery command would target the wrong repo.
  [ ! -e "$FIXTURE/links/rwctl" ]
  # The recovery hint must not be printed either — it would tell the operator
  # to `git pull` inside a repository this script does not own.
  [[ "$bootstrap_output" != *"git -C $WSDIR/rwctl pull"* ]]
}

@test "rwctl_bootstrap_recovers_a_workspace_created_before_the_first_push" {
  FIXTURE="$(mktemp -d -t rwctl-empty-XXXXXXXX)"
  REMOTE="$FIXTURE/rwctl.git"
  WSDIR="$FIXTURE/ws"
  mkdir -p "$WSDIR"
  git init --quiet --bare --initial-branch=main "$REMOTE"

  # 1. The workspace is created while the remote is still empty.
  run run_bootstrap
  [ "$status" -eq 0 ]
  test -d "$WSDIR/rwctl/.git"

  # 2. The owner pushes the first content.
  SEED="$FIXTURE/seed"
  git init --quiet --initial-branch=main "$SEED"
  git -C "$SEED" config user.email "test@example.invalid"
  git -C "$SEED" config user.name "rwctl profile test"
  echo "first" > "$SEED/README.md"
  git -C "$SEED" add README.md
  git -C "$SEED" commit --quiet -m "seed"
  git -C "$SEED" remote add origin "$REMOTE"
  git -C "$SEED" push --quiet origin main

  # 3. The next container start must pick it up.
  run run_bootstrap
  [ "$status" -eq 0 ]
  test -f "$WSDIR/rwctl/README.md"
}

@test "rwctl_bootstrap_survives_an_unreachable_remote" {
  setup_rwctl_fixture
  # An unreachable remote must not abort the script: the toolchain step must
  # still be reached on every rebuild. The slug must be unresolvable too —
  # a real slug would let the `gh repo clone` fallback succeed on an
  # authenticated machine and the test would pass for the wrong reason.
  run env RWCTL_REPO_SSH="$FIXTURE/does-not-exist.git" \
          RWCTL_REPO_SLUG="rtxnik/rwctl-no-such-repo" \
          RWCTL_CHECKOUT_ROOT="$WSDIR" \
          RWCTL_LINK_DIR="$FIXTURE/links" \
          RWCTL_SKIP_TOOLCHAIN=1 \
          bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clone failed"* ]]
}
