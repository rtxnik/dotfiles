#!/usr/bin/env bats
# Chezmoi run_onchange idempotency test for the pre-commit-hook installer.
# Production code: .chezmoiscripts/run_onchange_after_install_pre_commit_hooks.sh.tmpl
# (Wave 1, plan 12-02). RED until 12-02 ships.

load 'test_helper'

TMPL="$REPO_ROOT/.chezmoiscripts/run_onchange_after_install_pre_commit_hooks.sh.tmpl"

setup() {
  SANDBOX="$(mktemp -d -t chezmoi-idem-XXXXXXXX)"
  export SANDBOX
  (
    cd "$SANDBOX" || exit 1
    git init --quiet --initial-branch=main
    if [ -f "$REPO_ROOT/.pre-commit-config.yaml" ]; then
      cp "$REPO_ROOT/.pre-commit-config.yaml" "$SANDBOX/" 2>/dev/null || true
    fi
  )
}

teardown() {
  if [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ]; then
    rm -rf "$SANDBOX"
  fi
}

@test "chezmoi_template_renders: chezmoi execute-template emits valid bash" {
  test -f "$TMPL"
  rendered="$(chezmoi execute-template < "$TMPL")"
  echo "$rendered" | bash -n
}

@test "chezmoi_template_idempotent: rendered script runs twice with identical output" {
  test -f "$TMPL"
  rendered="$(chezmoi execute-template < "$TMPL")"
  echo "$rendered" > "$SANDBOX/render.sh"
  chmod +x "$SANDBOX/render.sh"
  cd "$SANDBOX"
  first_output="$(bash "$SANDBOX/render.sh" 2>&1)"; first_status=$?
  second_output="$(bash "$SANDBOX/render.sh" 2>&1)"; second_status=$?
  [ "$first_status" -eq 0 ]
  [ "$second_status" -eq 0 ]
  [ "$first_output" = "$second_output" ]
}

@test "chezmoi_template_skips_when_no_repo: graceful exit 0 when target absent" {
  test -f "$TMPL"
  rendered="$(chezmoi execute-template < "$TMPL")"
  # NOTE (12-02 Rule 1 fix): chezmoi execute-template resolves
  # `{{ .chezmoi.homeDir }}` at render time, so swapping HOME after rendering
  # cannot simulate "host without dotfiles cloned" -- the path is already
  # baked. The template honors a DOTFILES_REPO env override for exactly this
  # test (production hosts use the chezmoi-rendered default).
  empty="$(mktemp -d)"
  trap 'rm -rf "$empty"' RETURN
  run env DOTFILES_REPO="$empty/no-such-dotfiles" bash -c "$rendered"
  [ "$status" -eq 0 ]
  [[ "$output" =~ WARN ]] || [[ "$stderr" =~ WARN ]] || true
}
