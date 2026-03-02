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

## Workspace Manager (`ws`)

The `ws` script manages DevPod workspaces with profile-based devcontainers.

### Workspace commands

```bash
ws new myproject go          # create workspace with Go profile
ws new myproject go --proxy  # create workspace with transparent proxy
ws list                      # list all workspaces
ws profiles                  # show available profiles
ws start myproject           # start workspace
ws stop myproject            # stop workspace
ws delete myproject          # delete workspace
ws ssh myproject             # SSH into workspace (renames tmux window)
ws code myproject            # open in VS Code
```

### Devcontainer Profiles

| Profile | Tools |
|---------|-------|
| `default` | jq, yq, fzf, ripgrep, fd, bat, lsd, delta |
| `devops` | opentofu, ansible, k9s, network utils |
| `go` | go, golangci-lint, node (lts), dev tools |
| `k8s` | kubectl, helm, k9s, kind, stern, flux, argocd |
| `web` | node (lts), bun, deno, pnpm |

See [workspaces/README.md](dot_config/workspaces/README.md) for details on
creating custom profiles.

## Transparent Proxy

Dev containers can route all TCP traffic through a transparent VLESS proxy.
Uses iptables NAT and xray-core `dokodemo-door` — no env vars or
application-level configuration needed.

### Architecture

```
┌─────────────────────────────────────────┐
│       Shared network namespace          │
│                                         │
│  ┌────────────────┐                     │
│  │  dev-proxy     │                     │
│  │  xray-core     │ ← dokodemo-door    │
│  │  iptables NAT  │   port 12345       │
│  │                │                     │
│  │  OUTPUT TCP ───┼──→ REDIRECT :12345  │
│  │  (skip xray    │──→ xray ──→ VLESS   │
│  │   user + LAN)  │        relay server │
│  └────────────────┘                     │
│         ▲                               │
│         │ --network=container:dev-proxy  │
│  ┌──────┴───────┐  ┌───────────────┐   │
│  │  workspace-1 │  │  workspace-2  │   │
│  │  all TCP via  │  │  all TCP via  │   │
│  │  proxy relay  │  │  proxy relay  │   │
│  └──────────────┘  └───────────────┘   │
└─────────────────────────────────────────┘
```

### Proxy commands

```bash
ws proxy init              # generate config from VLESS URI
ws proxy check             # verify prerequisites
ws proxy up                # start proxy container
ws proxy down              # stop and remove container
ws proxy status            # show container status and health
ws proxy logs              # show recent container logs
ws proxy test              # exit IP, latency, diagnostics
ws proxy rebuild           # force rebuild proxy image
ws proxy debug on|off      # toggle xray debug logging
ws proxy update [vX.Y.Z]   # update xray to latest or pinned version
```

### Quick start

```bash
ws proxy init            # generate config from VLESS URI
ws proxy up              # start transparent proxy container
ws new myproject go --proxy   # create workspace with proxy networking
ws start myproject
ws ssh myproject
# Inside: curl https://ifconfig.me → proxy exit IP
```

## Troubleshooting

**Workspace won't start with proxy:**
Ensure the proxy container is running (`ws proxy status`). If stopped,
run `ws proxy up`. The `ws start` command will prompt to start the proxy
automatically if the workspace uses `--network=container:dev-proxy`.

**`ws proxy test` fails:**
Run `ws proxy test` for built-in diagnostics — it checks xray listener,
DNS resolution, and iptables rules. Common fixes:
- `ws proxy debug on` then `ws proxy logs` for detailed xray output
- `ws proxy rebuild && ws proxy up` to reset the container

**xray version mismatch:**
If the server was updated, run `ws proxy update` to fetch the latest
xray-core release and rebuild the proxy image.

**mise tools not available after workspace start:**
The `post-create.sh` script merges profile and global mise configs
on first run. If tools are missing, SSH in and run `mise install`.

## Requirements

- macOS (arm64) or Linux
- SSH key for GitHub
- [chezmoi](https://www.chezmoi.io/)
- Docker (for devcontainer workspaces)
- [devpod](https://devpod.sh/) (for workspace management)

## License

MIT
