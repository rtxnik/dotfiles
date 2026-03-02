# Workspace Profiles

Devcontainer profiles for [devpod](https://devpod.sh/).

## Usage

```bash
ws new myproject k8s    # Create workspace
ws start myproject      # Start
ws ssh myproject        # SSH into
ws code myproject       # Open in VS Code
ws stop myproject       # Stop
ws delete myproject     # Delete
```

## Profiles

| Profile | Included Tools |
|---------|---------------|
| `default` | jq, yq, fzf, ripgrep, fd, bat, lsd, delta |
| `devops` | opentofu, ansible, k9s + network utilities |
| `go` | go, golangci-lint, node (lts), jq, yq, fzf, ripgrep, fd |
| `k8s` | kubectl, helm, k9s, kind, stern, flux, argocd |
| `web` | node (lts), bun, deno, pnpm |

## Transparent Proxy

Dev containers route all TCP traffic through a VLESS proxy via iptables NAT
rules. No application-level configuration (env vars) is needed — traffic
interception is fully transparent at the network level.

### Architecture

```
┌──────────────────────────────────────────┐
│        Shared network namespace          │
│                                          │
│  ┌────────────────┐                      │
│  │  dev-proxy     │                      │
│  │  xray-core     │ ← dokodemo-door      │
│  │  iptables NAT  │   port 12345         │
│  │                │                      │
│  │  All OUTPUT    │                      │
│  │  TCP traffic   │──→ REDIRECT :12345   │
│  │  (except xray  │──→ xray ──→ VLESS    │
│  │   user + LAN)  │                      │
│  └────────────────┘                      │
│         ▲                                │
│         │ --network=container:dev-proxy   │
│  ┌──────┴───────┐  ┌───────────────┐    │
│  │  devpod-1    │  │  devpod-2     │    │
│  │              │  │               │    │
│  │  ALL traffic │  │  ALL traffic  │    │
│  │  via VLESS   │  │  via VLESS    │    │
│  └──────────────┘  └───────────────┘    │
└──────────────────────────────────────────┘
```

### How it works

1. Proxy container runs xray-core as user `xray` with `dokodemo-door` inbound
2. `entrypoint.sh` sets up iptables NAT: all OUTPUT TCP redirected to port 12345
3. Traffic from xray user excluded via `--uid-owner` (prevents loops)
4. Private networks (10/8, 172.16/12, 192.168/16, 127/8) go direct
5. Dev containers share proxy's network namespace (`--network=container:dev-proxy`)

### Quick start

```bash
ws proxy init           # generate config from VLESS URI
ws proxy check          # verify prerequisites
ws proxy up             # start proxy container
ws proxy test           # show exit IP
ws new myproject go     # create workspace
ws start myproject
ws ssh myproject
# Inside: curl https://ifconfig.me → proxy exit IP
```

### Proxy commands

| Command | Description |
|---------|-------------|
| `ws proxy init` | Generate xray config from VLESS URI |
| `ws proxy check` | Verify prerequisites (docker, config, image, container) |
| `ws proxy up` | Start proxy container |
| `ws proxy down` | Stop and remove proxy container |
| `ws proxy status` | Show container status |
| `ws proxy logs` | Show recent logs |
| `ws proxy rebuild` | Force rebuild proxy image |
| `ws proxy test` | Show exit IP (verify proxy works) |

### Config

The proxy config lives at `~/.config/xray/config.json` on the host (not tracked
in this repo — contains secrets). Use `ws proxy init` to generate it from a
VLESS URI, or copy `config.json.example` and fill in your values.

## Requirements

- devpod
- Docker or compatible runtime
- SSH key for GitHub
- VLESS URI or `~/.config/xray/config.json` for proxy profiles
