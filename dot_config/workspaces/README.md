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

The `go` profile connects to the `devnet` Docker network and sets proxy
environment variables (`HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`) pointing
to `dev-proxy:10808/10809`. Start the proxy first with `ws proxy up`.

## Proxy Container

The `proxy` profile builds a standalone proxy container (not a dev environment):

```bash
ws proxy up      # Create devnet network + start dev-proxy container
ws proxy status  # Show container status
ws proxy logs    # Show recent logs
ws proxy down    # Stop and remove container
```

Requires `~/.config/xray/config.json` on the host (not tracked in this repo).

## Network Architecture

```
Docker: devnet
  dev-proxy (:10808 SOCKS5, :10809 HTTP)
    └── go workspaces connect via HTTP_PROXY / ALL_PROXY env vars
```

## Requirements

- devpod
- Docker or compatible runtime
- SSH key for GitHub
- `~/.config/xray/config.json` for the `go` profile (proxy config)
