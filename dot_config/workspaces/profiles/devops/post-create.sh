#!/usr/bin/env bash
# =============================================================================
# Post-create setup (shared across all profiles)
# =============================================================================

set -euo pipefail

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$1"; }

log "Starting environment setup"

# Zsh as default shell
if command -v zsh &>/dev/null; then
    sudo chsh -s "$(command -v zsh)" "$USER" 2>/dev/null || true
fi

# Dotfiles via chezmoi
if ! command -v chezmoi &>/dev/null; then
    log "Installing chezmoi and applying dotfiles"
    sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply https://github.com/rtxnik/dotfiles.git
else
    log "Updating dotfiles"
    chezmoi update --apply || true
fi

# Pure prompt
if [[ ! -d "$HOME/.zsh/pure" ]]; then
    log "Installing pure prompt"
    mkdir -p "$HOME/.zsh"
    git clone --depth=1 https://github.com/sindresorhus/pure.git "$HOME/.zsh/pure"
fi

# Mise tools
export PATH="$HOME/.local/bin:$PATH"
if [[ -f "$PWD/.mise.toml" ]]; then
    log "Installing mise tools globally"
    mkdir -p "$HOME/.config/mise"
    cp "$PWD/.mise.toml" "$HOME/.config/mise/config.toml"
    mise trust "$HOME/.config/mise/config.toml"
    mise install --yes
fi

log "Setup complete"
