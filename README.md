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
│   ├── xray/           # Proxy config example
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
| `go` | go, golangci-lint, node (lts), dev tools |
| `k8s` | kubectl, helm, kind, flux, argocd |
| `web` | node, bun, deno, pnpm |

Dev containers route all TCP traffic through a transparent VLESS proxy
(iptables NAT). No env vars needed — traffic interception is automatic.

```bash
ws proxy init            # generate config from VLESS URI
ws proxy up              # start transparent proxy container
ws new myproject go      # create Go workspace (shared network namespace)
ws start myproject
ws ssh myproject
# Inside: curl https://ifconfig.me → proxy exit IP
```

## Requirements

- macOS (arm64) or Linux
- SSH key for GitHub
- [chezmoi](https://www.chezmoi.io/)

## License

MIT
