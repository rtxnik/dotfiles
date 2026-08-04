#!/usr/bin/env bash
# =============================================================================
# rwctl profile bootstrap — host-persisted checkout + agent toolchain
# =============================================================================
# Invoked by the shared post-create.sh with the workspace folder as $PWD.
# Every step is idempotent and guarded: a failure here must never leave a
# rebuilt container without its toolchain.
set -euo pipefail

log() { printf '[rwctl] %s\n' "$1"; }

# --- Step 0: make mise-provisioned tools resolvable ---------------------------
# The shared post-create.sh exports only ~/.local/bin and never activates mise.
export PATH="$HOME/.local/bin:$PATH"
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)" || log "mise activate failed — continuing with PATH only"
fi

REPO_SSH="${RWCTL_REPO_SSH:-git@github.com:rtxnik/rwctl.git}"
REPO_SLUG="${RWCTL_REPO_SLUG:-rtxnik/rwctl}"
CHECKOUT_ROOT="${RWCTL_CHECKOUT_ROOT:-$PWD}"
CHECKOUT="$CHECKOUT_ROOT/${RWCTL_CHECKOUT_NAME:-rwctl}"
LINK_DIR="${RWCTL_LINK_DIR:-$HOME/projects}"

# --- Step 1: clone or refresh, in the host-mounted workspace folder -----------
# $HOME/projects is container-local storage and does not survive a rebuild, so
# the working tree lives on the mount and $HOME/projects/rwctl is a symlink.
sync_checkout() {
    if [ ! -d "$CHECKOUT/.git" ]; then
        if [ -e "$CHECKOUT" ]; then
            log "WARNING: $CHECKOUT exists but is not a git worktree — leaving it untouched"
            return 1
        fi
        log "Cloning $REPO_SLUG into $CHECKOUT"
        local clone_err gh_err
        if ! clone_err="$(GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" git clone "$REPO_SSH" "$CHECKOUT" 2>&1)"; then
            log "git clone failed: $(printf '%s\n' "$clone_err" | tail -n1)"
            if ! gh_err="$(GIT_TERMINAL_PROMPT=0 gh repo clone "$REPO_SLUG" "$CHECKOUT" 2>&1)"; then
                log "gh repo clone failed: $(printf '%s\n' "$gh_err" | tail -n1)"
                log "clone failed — authenticate first (ssh-add, or gh auth login), then run: git clone $REPO_SSH $CHECKOUT"
                return 1
            fi
        fi
        return 0
    fi

    local origin
    origin="$(git -C "$CHECKOUT" remote get-url origin 2>/dev/null || true)"
    case "$origin" in
    *"$REPO_SLUG" | *"$REPO_SLUG".git | *"$REPO_SLUG"/) : ;;
    *)
        log "WARNING: $CHECKOUT has origin '$origin', expected $REPO_SLUG — leaving it untouched"
        return 1
        ;;
    esac

    log "Refreshing $CHECKOUT"
    if ! git -C "$CHECKOUT" fetch --all --prune --quiet 2>/dev/null; then
        log "fetch failed — offline or unauthenticated; the checkout is unchanged"
        return 1
    fi
    # An unborn HEAD means the workspace was created before the repo had content.
    # Adopt the remote's default branch rather than assuming the local unborn
    # branch name (which comes from init.defaultBranch) matches what the first
    # push actually created.
    if ! git -C "$CHECKOUT" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
        git -C "$CHECKOUT" remote set-head origin --auto >/dev/null 2>&1 || true
        local default_branch
        default_branch="$(git -C "$CHECKOUT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
        if [ -z "$default_branch" ]; then
            log "remote has no commits yet — nothing to check out"
            return 0
        fi
        log "adopting the remote default branch '$default_branch'"
        git -C "$CHECKOUT" switch -C "$default_branch" --track "origin/$default_branch" --quiet 2>/dev/null || true
    fi
    git -C "$CHECKOUT" pull --ff-only --quiet 2>/dev/null ||
        log "not fast-forwardable — the branch diverged; resolve by hand"
}

mkdir -p "$CHECKOUT_ROOT" "$LINK_DIR"
# The symlink is created ONLY when the checkout is confirmed ours. A foreign or
# unreachable tree must not capture the conventional path, or the recovery
# command this script prints would operate on the wrong repository.
if sync_checkout; then
    if [ -e "$LINK_DIR/rwctl" ] && [ ! -L "$LINK_DIR/rwctl" ]; then
        log "WARNING: $LINK_DIR/rwctl exists and is not a symlink — leaving it untouched"
    else
        ln -sfn "$CHECKOUT" "$LINK_DIR/rwctl"
        log "linked $LINK_DIR/rwctl -> $CHECKOUT"
    fi
    log "Working tree: $CHECKOUT (host-persisted)"
    log "If this workspace was created before the repo had content, run: git -C $CHECKOUT pull"
else
    log "checkout step incomplete — $LINK_DIR/rwctl left untouched; continuing with the toolchain install"
    log "review the WARNING above and resolve the checkout by hand before trusting $LINK_DIR/rwctl"
fi

# --- Step 2: agent toolchain (absent from a fresh image) ---------------------
if [ "${RWCTL_SKIP_TOOLCHAIN:-0}" != "1" ]; then
    if ! command -v uv >/dev/null 2>&1; then
        log "Installing uv"
        curl -fsSL https://astral.sh/uv/install.sh | sh || log "uv install failed"
    fi
    if ! command -v claude >/dev/null 2>&1; then
        log "Installing Claude Code"
        curl -fsSL https://claude.ai/install.sh | bash || log "claude install failed"
    fi
    if ! command -v factory >/dev/null 2>&1 && command -v uv >/dev/null 2>&1; then
        log "Installing the pinned factory CLI (v1.0.5)"
        uv tool install "git+https://github.com/rtxnik/workflow-factory@v1.0.5#subdirectory=tooling" ||
            log "factory CLI install failed"
    fi
fi

# --- Step 3: next steps ------------------------------------------------------
log "Fabric adoption is a deliberate, reviewed step — author factory.json, then run 'factory install' from a complete v1.0.5 release directory."
log "Setup complete"
