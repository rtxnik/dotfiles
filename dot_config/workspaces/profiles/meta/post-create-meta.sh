#!/usr/bin/env bash
# =============================================================================
# Meta profile bootstrap — clone workflow repos as siblings, set up branches
# =============================================================================
set -euo pipefail

log() { printf '[meta] %s\n' "$1"; }

BRANCH="feat/meta-workspace-profile"
BASE_DIR="$HOME/projects"
mkdir -p "$BASE_DIR"

declare -A REPOS=(
    [dotfiles]="git@github.com:rtxnik/dotfiles.git"
    [workflow-kit]="git@github.com:rtxnik/workflow-kit.git"
    [workspace-cli]="git@github.com:rtxnik/workspace-cli.git"
    # [vault]="git@github.com:rtxnik/vault.git"  # TODO: create repo first
)

clone_or_skip() {
    local name="$1" url="$2" dest="$BASE_DIR/$name"

    if [[ -d "$dest/.git" ]]; then
        log "$name: already cloned, skipping"
        return 0
    fi

    if [[ -d "$dest" ]]; then
        log "$name: directory exists but is not a git repo, skipping"
        return 0
    fi

    log "$name: cloning"
    git clone "$url" "$dest"
}

checkout_branch() {
    local name="$1" dest="$BASE_DIR/$name"

    [[ -d "$dest/.git" ]] || return 0

    cd "$dest"

    # Do not switch if there are uncommitted changes
    if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet HEAD 2>/dev/null; then
        log "$name: uncommitted changes, staying on $(git branch --show-current)"
        return 0
    fi

    if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
        git checkout "$BRANCH"
    elif git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
        git checkout -b "$BRANCH" "origin/$BRANCH"
    else
        git checkout -b "$BRANCH"
    fi
}

# Clone repos (sequential to keep log readable; git itself parallelises fetch)
for name in "${!REPOS[@]}"; do
    clone_or_skip "$name" "${REPOS[$name]}"
done

# Switch branches
for name in "${!REPOS[@]}"; do
    checkout_branch "$name"
done

# Status summary
log "--- status ---"
for name in "${!REPOS[@]}"; do
    dest="$BASE_DIR/$name"
    if [[ -d "$dest/.git" ]]; then
        cd "$dest"
        branch=$(git branch --show-current)
        dirty=""
        git diff --quiet HEAD 2>/dev/null && git diff --cached --quiet HEAD 2>/dev/null || dirty=" (dirty)"
        log "$name: $branch$dirty"
    else
        log "$name: not cloned"
    fi
done

# Install workflow-kit node dependencies if present
if [[ -f "$BASE_DIR/workflow-kit/package.json" ]]; then
    cd "$BASE_DIR/workflow-kit"
    if command -v pnpm &>/dev/null; then
        log "Installing workflow-kit dependencies (pnpm)"
        pnpm install --frozen-lockfile 2>/dev/null || pnpm install || true
    elif command -v npm &>/dev/null; then
        log "Installing workflow-kit dependencies (npm)"
        npm ci 2>/dev/null || npm install || true
    fi
fi

log "Bootstrap complete"
