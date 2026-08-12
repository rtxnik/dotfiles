#!/usr/bin/env bash
# =============================================================================
# spatial profile bootstrap — host-persisted tree, project seed, self-check
# =============================================================================
# Invoked by the shared post-create.sh with the workspace folder as $PWD.
# Every step is guarded and idempotent: a failure here must never leave a
# rebuilt container without its toolchain.
set -euo pipefail

log() { printf '[spatial] %s\n' "$1"; }

# --- Step 0: make mise-provisioned tools resolvable ---------------------------
# The shared post-create.sh exports ~/.local/bin and never activates mise.
export PATH="$HOME/.local/bin:$PATH"
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)" || log "mise activate failed — continuing with PATH only"
fi

PROJECT_ROOT="${SPATIAL_PROJECT_ROOT:-$PWD}"
SEED_DIR="${SPATIAL_SEED_DIR:-$HOME/.config/workspaces/profiles/spatial/seed}"
LINK_DIR="${SPATIAL_LINK_DIR:-$HOME/projects}"
DOCTOR="${SPATIAL_DOCTOR:-$HOME/.config/workspaces/profiles/spatial/doctor.sh}"
PROJECT_NAME="$(basename "$PROJECT_ROOT")"

# --- Step 1: conventional path -> host-mounted workspace folder ---------------
# $HOME/projects is container-local storage: it does not survive a rebuild or a
# `ws delete`, so unpushed work there is one container lifecycle away from
# unrecoverable loss. The tree stays on the mount; ~/projects/<name> is a link.
mkdir -p "$LINK_DIR" || log "WARNING: could not create $LINK_DIR — the conventional path will be missing"
link="$LINK_DIR/$PROJECT_NAME"
if [ -e "$link" ] && [ ! -L "$link" ]; then
    log "WARNING: $link exists and is not a symlink — leaving it untouched"
elif ln -sfn "$PROJECT_ROOT" "$link"; then
    log "linked $link -> $PROJECT_ROOT"
else
    log "WARNING: could not link $link -> $PROJECT_ROOT — the working tree is still at $PROJECT_ROOT"
fi

# --- Step 2: seed, only into a folder that is not already a project -----------
seed_project() {
    local missing="" f
    if [ ! -d "$SEED_DIR" ]; then
        log "seed directory $SEED_DIR is absent — skipping seed"
        return 1
    fi
    if [ -e "$PROJECT_ROOT/pyproject.toml" ] || [ -e "$PROJECT_ROOT/.git" ]; then
        log "$PROJECT_ROOT already holds a project — seed skipped"
        log "to apply the skeleton by hand: cp -r --update=none $SEED_DIR/. $PROJECT_ROOT/ && mkdir -p $PROJECT_ROOT/model $PROJECT_ROOT/source $PROJECT_ROOT/scripts $PROJECT_ROOT/tests $PROJECT_ROOT/out $PROJECT_ROOT/docs"
        return 1
    fi
    log "seeding the project skeleton into $PROJECT_ROOT"
    # `src/.` rather than `src/*`: the glob would leave .gitignore behind.
    # `--update=none` (coreutils 9.3+) is the non-deprecated spelling of the old
    # `-n`: same "never overwrite" behaviour, without the "-n is non-portable"
    # warning `-n` prints to stderr — and into the container-create log — on
    # every seeded boot. The copy's own exit status is not gated on: the
    # completeness check right below already renders the verdict.
    cp -r --update=none "$SEED_DIR/." "$PROJECT_ROOT/" ||
        log "WARNING: the seed copy reported an error — the completeness check below decides what actually landed"
    # Git cannot track empty directories, so the skeleton is created here rather
    # than carried as .gitkeep files that would land in the project as clutter.
    # Unconditional and ahead of the completeness check below: mkdir -p is
    # idempotent, and a folder that fails that check still benefits from having
    # its layout.
    if ! mkdir -p "$PROJECT_ROOT/model" "$PROJECT_ROOT/source" "$PROJECT_ROOT/scripts" \
                  "$PROJECT_ROOT/tests" "$PROJECT_ROOT/out" "$PROJECT_ROOT/docs"; then
        log "WARNING: could not create the directory skeleton in $PROJECT_ROOT"
        return 1
    fi
    # A copy that died after placing pyproject.toml would make every later boot
    # skip the seed as "already a project" and leave the skeleton permanently
    # half-built. Completeness is therefore verified, not assumed.
    for f in pyproject.toml Makefile CLAUDE.md README.md .gitignore; do
        [ -e "$PROJECT_ROOT/$f" ] || missing="$missing $f"
    done
    if [ -n "$missing" ]; then
        log "WARNING: the seed is incomplete, missing:$missing"
        log "complete it by hand: cp -r --update=none $SEED_DIR/. $PROJECT_ROOT/"
        return 1
    fi
    return 0
}
seed_project || true

# --- Step 3: python environment ----------------------------------------------
if [ "${SPATIAL_SKIP_SYNC:-0}" != "1" ] && [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
    log "resolving the python environment (uv sync)"
    (cd "$PROJECT_ROOT" && uv sync) ||
        log "uv sync failed — offline or unauthenticated; run 'uv sync' by hand"
fi

# --- Step 4: agent toolchain (absent from a fresh image) ----------------------
# uv already comes from mise, so unlike the rwctl profile there is nothing to
# bootstrap before this point.
if [ "${SPATIAL_SKIP_TOOLCHAIN:-0}" != "1" ] && ! command -v claude >/dev/null 2>&1; then
    log "Installing Claude Code"
    curl -fsSL https://claude.ai/install.sh | bash || log "claude install failed"
fi

# --- Step 5: prove the container ---------------------------------------------
# Advisory at this point: a network hiccup in step 3 must not abort container
# creation. The table is the record; the exit code is logged, not propagated.
if [ "${SPATIAL_SKIP_DOCTOR:-0}" != "1" ]; then
    if [ -f "$DOCTOR" ]; then
        log "running the environment self-check"
        bash "$DOCTOR" || log "self-check reported failures — rerun with: bash $DOCTOR"
    else
        log "self-check not found at $DOCTOR — skipping"
    fi
fi

log "Setup complete"
