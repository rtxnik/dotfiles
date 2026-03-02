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
| **devcontainers** | Pre-configured dev environments via `ws` manager |

## Structure

```
.
├── dot_config/
│   ├── alacritty/      # Terminal emulator
│   ├── mise/           # Tool versions
│   ├── nvim/           # Neovim (LazyVim)
│   ├── xray/           # Proxy config example
│   └── workspaces/     # Devcontainer profiles + shared scripts
├── scripts/
│   ├── core/ws         # Workspace manager
│   └── dev/            # Development helpers
└── setup               # Bootstrap script
```

## Devcontainer Workspaces

The `ws` script manages DevPod workspaces with profile-based devcontainers
and an optional transparent VLESS proxy.

```bash
ws new myproject go --proxy   # create workspace with proxy networking
ws start myproject
ws ssh myproject
```

Profiles: `default`, `devops`, `go`, `k8s`, `python`, `rust`, `web`.
See [workspaces/README.md](dot_config/workspaces/README.md) for full
command reference, proxy setup, and profile creation guide.

## Requirements

- macOS (arm64) or Linux
- SSH key for GitHub
- [chezmoi](https://www.chezmoi.io/)
