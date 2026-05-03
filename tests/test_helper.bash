#!/usr/bin/env bash
# tests/test_helper.bash — shared bats helpers for Phase 12 dotfiles security audit.
#
# Provides:
#   make_sandbox_repo                                  — mktemp + git-init isolated repo
#   write_fake_aws_key <path>                          — copy fake AWS-key fixture
#   write_fake_age_key <path>                          — copy fake age-key fixture
#   fake_repo_history_with_secret <repo> <fname> <fn>  — drop secret + commit (will be blocked)
#
# REPO_ROOT and FIXTURES_DIR are exposed for caller test files.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
FIXTURES_DIR="$REPO_ROOT/tests/fixtures"

make_sandbox_repo() {
    local sandbox
    sandbox="$(mktemp -d -t dotfiles-sandbox-XXXXXXXX)"
    (
        cd "$sandbox" || exit 1
        git init --quiet --initial-branch=main
        git config user.email "test@example.invalid"
        git config user.name "Phase 12 Test"
        if [ -f "$REPO_ROOT/.gitleaks.toml" ]; then
            cp "$REPO_ROOT/.gitleaks.toml" "$sandbox/"
        fi
        if [ -f "$REPO_ROOT/.pre-commit-config.yaml" ]; then
            cp "$REPO_ROOT/.pre-commit-config.yaml" "$sandbox/"
            pre-commit install --install-hooks >/dev/null 2>&1 || true
        fi
    )
    echo "$sandbox"
}

write_fake_aws_key() {
    cp "$FIXTURES_DIR/secrets/fake-aws-key.txt" "$1"
}

write_fake_age_key() {
    cp "$FIXTURES_DIR/secrets/fake-age-key.txt" "$1"
}

fake_repo_history_with_secret() {
    local repo="$1" filename="$2" writer="$3"
    cd "$repo" || return 1
    "$writer" "$filename"
    git add "$filename"
    git commit -m "test: should be blocked"
}
