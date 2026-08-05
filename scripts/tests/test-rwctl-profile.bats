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

# The ubuntu-24.04 base carries neither. The fabric's large-file-guard test
# suite shells out to python3, and its serena integration check needs PyYAML.
@test "rwctl_dockerfile_installs_python_for_the_fabric_gates" {
  # Anchored on whitespace, not -w: under -w the "python3" probe would also be
  # satisfied by "python3-yaml" alone and pass without the interpreter.
  for pkg in python3 python3-yaml; do
    run grep -E "(^|[[:space:]])${pkg}([[:space:]]|\\\\|\$)" "$PROFILE/Dockerfile"
    [ "$status" -eq 0 ]
  done
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

# The fabric's vendored gate suites run inside this container, so the profile
# has to carry their toolchain even though the product itself never uses it.
@test "rwctl_mise_carries_the_fabric_gate_tools" {
  for tool in shellcheck shfmt bats bun; do
    run grep -E "^${tool}[[:space:]]*=" "$PROFILE/mise.toml"
    [ "$status" -eq 0 ]
  done
}

# shellcheck 0.10+ adds checks that fail code which is clean under 0.9, so a
# floating pin reds the vendored suites on code nobody touched.
@test "rwctl_mise_pins_shellcheck_to_the_hook_authoring_version" {
  run grep -Ex 'shellcheck[[:space:]]*=[[:space:]]*"0\.9\.0"' "$PROFILE/mise.toml"
  [ "$status" -eq 0 ]
}

@test "rwctl_mise_pins_shfmt" {
  run grep -Ex 'shfmt[[:space:]]*=[[:space:]]*"3\.13\.1"' "$PROFILE/mise.toml"
  [ "$status" -eq 0 ]
}

@test "rwctl_mise_has_no_floating_shellcheck_or_shfmt" {
  [ -f "$PROFILE/mise.toml" ]
  for tool in shellcheck shfmt; do
    run grep -Ex "${tool}[[:space:]]*=[[:space:]]*\"latest\"" "$PROFILE/mise.toml"
    [ "$status" -ne 0 ]
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

@test "rwctl_bootstrap_activates_mise" {
  run grep -F 'mise activate bash' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "rwctl_bootstrap_pins_the_factory_cli_to_an_immutable_tag" {
  run grep -F 'workflow-factory@v1.0.5#subdirectory=tooling' "$SCRIPT"
  [ "$status" -eq 0 ]
}

# The factory repo is private and post-create has the forwarded SSH agent but no
# git credential helper, so an HTTPS-only install fails and the `|| log` guard
# hides it. Both transports must be present, SSH must be attempted first, and
# the fallback must be pinned to the same tag.
@test "rwctl_bootstrap_installs_the_factory_cli_over_ssh_first" {
  ssh_line="$(grep -nF 'git+ssh://git@github.com/rtxnik/workflow-factory.git@v1.0.5#subdirectory=tooling' "$SCRIPT" | head -n1 | cut -d: -f1)"
  https_line="$(grep -nF 'git+https://github.com/rtxnik/workflow-factory@v1.0.5#subdirectory=tooling' "$SCRIPT" | head -n1 | cut -d: -f1)"
  [ -n "$ssh_line" ]
  [ -n "$https_line" ]
  [ "$ssh_line" -lt "$https_line" ]
}

# BatchMode keeps a missing key a fast failure instead of an interactive prompt
# that would hang the container create.
@test "rwctl_bootstrap_factory_ssh_install_is_non_interactive" {
  run grep -F 'GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new"' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F 'GIT_TERMINAL_PROMPT=0' "$SCRIPT"
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

@test "rwctl_bootstrap_defaults_checkout_root_to_pwd_when_unset" {
  setup_rwctl_fixture
  # RWCTL_CHECKOUT_ROOT is deliberately absent — CHECKOUT_ROOT must fall back
  # to $PWD, which is why this test cd's into the workspace dir itself rather
  # than passing it through the env var like every other test in this file.
  cd "$WSDIR"
  run env RWCTL_REPO_SSH="$REMOTE" \
      RWCTL_REPO_SLUG="rwctl.git" \
      RWCTL_LINK_DIR="$FIXTURE/links" \
      RWCTL_SKIP_TOOLCHAIN=1 \
      bash "$SCRIPT"
  [ "$status" -eq 0 ]
  test -f "$WSDIR/rwctl/README.md"
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

@test "rwctl_bootstrap_treats_a_slug_prefixed_foreign_origin_as_foreign" {
  setup_rwctl_fixture
  # A second, unrelated but REACHABLE repo whose path is REPO_SLUG plus a
  # suffix ("rwctl-mirror.git" extends "rwctl"). Reachability matters: an
  # unanchored substring match would not just misclassify this origin, it
  # would let the script actually fetch and pull from it, so the test must
  # give the bug something real to adopt or a network failure would mask it.
  MIRROR="$FIXTURE/rtxnik/rwctl-mirror.git"
  mkdir -p "$(dirname "$MIRROR")"
  git init --quiet --bare --initial-branch=main "$MIRROR"
  MIRROR_SEED="$FIXTURE/mirror-seed"
  git init --quiet --initial-branch=main "$MIRROR_SEED"
  git -C "$MIRROR_SEED" config user.email "test@example.invalid"
  git -C "$MIRROR_SEED" config user.name "rwctl profile test"
  echo "not ours" > "$MIRROR_SEED/MIRROR.md"
  git -C "$MIRROR_SEED" add MIRROR.md
  git -C "$MIRROR_SEED" commit --quiet -m "mirror seed"
  git -C "$MIRROR_SEED" remote add origin "$MIRROR"
  git -C "$MIRROR_SEED" push --quiet origin main

  mkdir -p "$WSDIR/rwctl"
  git init --quiet --initial-branch=main "$WSDIR/rwctl"
  git -C "$WSDIR/rwctl" remote add origin "$MIRROR"
  echo "mine" > "$WSDIR/rwctl/UNTRACKED.md"
  run env RWCTL_REPO_SSH="$REMOTE" \
      RWCTL_REPO_SLUG="rtxnik/rwctl" \
      RWCTL_CHECKOUT_ROOT="$WSDIR" \
      RWCTL_LINK_DIR="$FIXTURE/links" \
      RWCTL_SKIP_TOOLCHAIN=1 \
      bash "$SCRIPT"
  [ "$status" -eq 0 ]
  bootstrap_output="$output"
  test -f "$WSDIR/rwctl/UNTRACKED.md"
  # The mirror's content must never land here — that would mean the script
  # adopted a repository it does not own.
  test ! -f "$WSDIR/rwctl/MIRROR.md"
  run git -C "$WSDIR/rwctl" remote get-url origin
  [ "$output" = "$MIRROR" ]
  [ ! -e "$FIXTURE/links/rwctl" ]
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

@test "rwctl_readme_documents_the_load_bearing_decisions" {
  [ -f "$PROFILE/README.md" ]
  # These three are the decisions a reader must not have to rediscover.
  for phrase in "Docker-in-Docker" "host-mounted workspace folder" "Not automatic"; do
    run grep -F "$phrase" "$PROFILE/README.md"
    [ "$status" -eq 0 ]
  done
}

# The fabric probes these four but installs none of them, so a missing one
# surfaces only as a failed `factory verify` — the README is the only warning.
@test "rwctl_readme_lists_the_fabric_host_prerequisites" {
  [ -f "$PROFILE/README.md" ]
  for phrase in "gitleaks@8.30.1" "superpowers@claude-plugins-official" \
    "claude-mem@thedotmack" "uv tool install serena-agent"; do
    run grep -F "$phrase" "$PROFILE/README.md"
    [ "$status" -eq 0 ]
  done
}

# A default local-scope registration lands in .projects[...] and the factory's
# top-level `.mcpServers.serena` probe cannot see it.
@test "rwctl_readme_warns_that_serena_needs_user_scope" {
  [ -f "$PROFILE/README.md" ]
  run grep -F -- "--scope user" "$PROFILE/README.md"
  [ "$status" -eq 0 ]
  run grep -F "jq -e '.mcpServers.serena' ~/.claude.json" "$PROFILE/README.md"
  [ "$status" -eq 0 ]
}

# check-integration-rubric.sh greps $ROOT/CLAUDE.md; without that file the
# vendored integration-check gate is red and the message names the rubric,
# not the missing file.
@test "rwctl_readme_states_the_consumer_claude_md_obligation" {
  [ -f "$PROFILE/README.md" ]
  for phrase in "CLAUDE.md" "review-rubric.md" "check-integration-rubric.sh"; do
    run grep -F "$phrase" "$PROFILE/README.md"
    [ "$status" -eq 0 ]
  done
}
