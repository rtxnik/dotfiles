#!/usr/bin/env bash
set -euo pipefail

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$1"; }

log "Starting environment setup"

if command -v zsh &>/dev/null; then
    sudo chsh -s "$(command -v zsh)" "$USER" 2>/dev/null || true
fi

if ! command -v chezmoi &>/dev/null; then
    log "Installing chezmoi and applying dotfiles"
    sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply https://github.com/rtxnik/dotfiles.git
else
    log "Updating dotfiles"
    chezmoi update --apply || true
fi

if [[ ! -d "$HOME/.zsh/pure" ]]; then
    log "Installing pure prompt"
    mkdir -p "$HOME/.zsh"
    git clone --depth=1 https://github.com/sindresorhus/pure.git "$HOME/.zsh/pure"
fi

export PATH="$HOME/.local/bin:$PATH"

# Trust global config from dotfiles
mise trust "$HOME/.config/mise/config.toml" 2>/dev/null || true

# Trust and install workspace profile tools
if [[ -f "$PWD/.mise.toml" ]]; then
    log "Installing mise tools"
    mise trust "$PWD/.mise.toml"
    mise install --yes || true
fi

log "Setup complete"
