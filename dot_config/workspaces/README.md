# Workspace Profiles

Devcontainer profiles for [devpod](https://devpod.sh/).

## Usage

```bash
ws new myproject k8s          # create workspace
ws new myproject go --proxy   # create workspace with proxy networking
ws start myproject            # start
ws ssh myproject              # SSH into (renames tmux window)
ws code myproject             # open in VS Code
ws stop myproject             # stop
ws delete myproject           # delete
```

## Profiles

| Profile | Included Tools |
|---------|---------------|
| `default` | jq, yq, fzf, ripgrep, fd, bat, lsd, delta |
| `devops` | opentofu, ansible, k9s + network utilities |
| `go` | go, golangci-lint, node (lts), jq, yq, fzf, ripgrep, fd |
| `k8s` | kubectl, helm, k9s, kind, stern, flux, argocd |
| `python` | python, uv, ruff, jq, yq, fzf, ripgrep, fd |
| `rust` | rust, cargo-binstall, jq, yq, fzf, ripgrep, fd |
| `web` | node (lts), bun, deno, pnpm |

## Auto-detect

When creating a workspace without specifying a profile, `ws new` scans
the current directory for project markers and suggests a matching profile:

```bash
ws new myproject              # auto-detects profile from cwd
ws detect ~/projects/myapp    # check which profile would be detected
```

| Marker file | Detected profile |
|-------------|-----------------|
| `Cargo.toml` | rust |
| `go.mod` | go |
| `pyproject.toml`, `setup.py`, `requirements.txt`, `Pipfile` | python |
| `package.json` | web |
| `helmfile.yaml`, `kustomization.yaml`, `Chart.yaml` | k8s |
| `Dockerfile` (no language markers) | devops |

## Profile Management

```bash
ws profile list               # list available profiles
ws profile create myprofile   # interactive profile generator
ws profile delete myprofile   # delete a custom profile
```

The `create` command walks through base image selection, system packages,
mise tools, and Docker-in-docker support. Built-in profiles cannot be
deleted.

## Creating a New Profile (manual)

Each profile lives in `profiles/<name>/` with these files:

```
profiles/myprofile/
├── devcontainer.json   # required — container config
├── Dockerfile          # required — base image + system packages
└── mise.toml           # optional — tool versions for this profile
```

### Step 1: Create directory

```bash
mkdir -p profiles/myprofile
```

### Step 2: Create `devcontainer.json`

```jsonc
{
	"name": "MyProfile",
	"build": { "dockerfile": "Dockerfile" },
	"features": {
		"ghcr.io/devcontainers/features/common-utils:2": {
			"installZsh": true,
			"configureZshAsDefaultShell": true,
			"installOhMyZsh": false
		},
		"ghcr.io/devcontainers/features/git:1": {},
		"ghcr.io/devcontainers/features/github-cli:1": {}
	},
	"mounts": [],
	"containerEnv": { "WORKSPACE_PROFILE": "myprofile" },
	"postCreateCommand": "bash .devcontainer/post-create.sh",
	"remoteUser": "vscode"
}
```

The `WORKSPACE_PROFILE` env var identifies the profile in `ws list` output.

### Step 3: Create `Dockerfile`

```dockerfile
FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://mise.jdx.dev/install.sh | sh

ENV PATH="/home/vscode/.local/bin:${PATH}"
```

Add any system-level packages your profile needs to the `apt-get install` line.

### Step 4: Add tools via `mise.toml` (optional)

```toml
[tools]
node = "lts"
python = "latest"
```

Tools listed here are merged with the global mise config by
`shared/post-create.sh` during first startup. Use `latest` unless a
specific version is required.

### Customization examples

**Add extra devcontainer features:**

```jsonc
"features": {
	// ... common-utils, git, github-cli ...
	"ghcr.io/devcontainers/features/docker-in-docker:2": {}
}
```

**Mount host directories:**

```jsonc
"mounts": [
	"source=${localEnv:HOME}/.ssh,target=/home/vscode/.ssh,type=bind,readonly"
]
```

## Transparent Proxy

Dev containers can route all TCP traffic through a VLESS proxy via iptables
NAT rules. No application-level configuration (env vars) is needed — traffic
interception is fully transparent at the network level.

Use `--proxy` when creating a workspace to opt in:

```bash
ws new myproject go --proxy
```

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

### How it works

1. Proxy container runs xray-core as user `xray` with `dokodemo-door` inbound
2. `entrypoint.sh` sets up iptables NAT: all OUTPUT TCP redirected to port 12345
3. Traffic from xray user excluded via `--uid-owner` (prevents loops)
4. Private networks (10/8, 172.16/12, 192.168/16, 127/8) go direct
5. Dev containers share proxy's network namespace (`--network=container:dev-proxy`)

### Quick start

```bash
ws proxy init              # generate config from VLESS URI
ws proxy check             # verify prerequisites
ws proxy up                # start proxy container
ws proxy test              # exit IP, latency, diagnostics
ws new myproject go --proxy
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
| `ws proxy status` | Show container status and health |
| `ws proxy logs` | Show recent container logs |
| `ws proxy rebuild` | Force rebuild proxy image |
| `ws proxy test` | Exit IP, latency, xray version, diagnostics on failure |
| `ws proxy debug on\|off` | Toggle xray debug logging (restarts container) |
| `ws proxy update [vX.Y.Z]` | Update xray to latest or pinned version |

### Config

The proxy config lives at `~/.config/xray/config.json` on the host (not tracked
in this repo — contains secrets). Use `ws proxy init` to generate it from a
VLESS URI, or copy `config.json.example` and fill in your values.

## Requirements

- [devpod](https://devpod.sh/)
- Docker or compatible runtime
- SSH key for GitHub
- VLESS URI or `~/.config/xray/config.json` for proxy networking
