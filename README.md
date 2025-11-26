# Dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Quick Start

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply git@github.com:rtxnik/dotfiles.git
```

## What's Included

| Component | Description |
|-----------|-------------|
| **zsh** | Shell config with pure prompt, vi-mode, fzf integration |
| **neovim** | LazyVim-based setup with Zettelkasten workflow |
| **tmux** | Minimal config with gruvbox theme |
| **alacritty** | Terminal with UbuntuMono Nerd Font |
| **mise** | Runtime version management |
| **devcontainers** | Pre-configured dev environments |

## Structure

```
.
├── dot_config/
│   ├── alacritty/      # Terminal emulator
│   ├── mise/           # Tool versions
│   ├── nvim/           # Neovim (LazyVim)
│   └── workspaces/     # Devcontainer profiles
├── scripts/
│   ├── core/           # Essential utilities
│   └── dev/            # Development helpers
└── setup              # Bootstrap script
```

## Devcontainer Profiles

| Profile | Tools |
|---------|-------|
| `default` | jq, yq, fzf, ripgrep, fd, bat, lsd |
| `devops` | opentofu, ansible, k9s, network utils |
| `k8s` | kubectl, helm, kind, flux, argocd |
| `web` | node, bun, deno, pnpm |

Usage:
```bash
ws new myproject k8s
ws start myproject
ws ssh myproject
```

## Requirements

- macOS (arm64) or Linux
- SSH key for GitHub
- [chezmoi](https://www.chezmoi.io/)

## License

MIT
