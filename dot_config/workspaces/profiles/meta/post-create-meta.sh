#!/usr/bin/env bash
# =============================================================================
# Meta profile bootstrap — prepare project directory
# =============================================================================
set -euo pipefail

log() { printf '[meta] %s\n' "$1"; }

mkdir -p "$HOME/projects"
log "~/projects ready — clone repos manually"
log "Bootstrap complete"
