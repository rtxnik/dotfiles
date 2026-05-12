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
| `meta` | go, golangci-lint, goreleaser, node (lts), pnpm, neovim, bats, shellcheck, shfmt, tmux, git-lfs |

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

Workspace containers attach to the `ws-proxy` bridge network. The dev-proxy
container sits at gateway IP `172.28.0.2` and rewrites the workspace's default
route so all TCP/UDP egress is funneled through the proxy's iptables PREROUTING
NAT REDIRECT chain into xray's dokodemo-door on port 12345.

```
┌────────────────────────── ws-proxy bridge (172.28.0.0/16) ──────────────────────────┐
│                                                                                       │
│   ┌─────────────────────────┐                                                         │
│   │  dev-proxy @ 172.28.0.2 │  (gateway for all workspace containers)                 │
│   │  ────────────────────── │                                                         │
│   │  xray-core              │  ← dokodemo-door listens on port 12345                  │
│   │  iptables PREROUTING ───┼──→ NAT REDIRECT to 12345                                │
│   │  iptables OUTPUT (self) │     (skips xray's own --uid-owner; private CIDRs direct)│
│   └─────────────────────────┘                                                         │
│             ▲                                                                         │
│             │ ip route replace default via 172.28.0.2 (on each workspace)             │
│   ┌─────────┴─────────┐  ┌──────────────────┐                                         │
│   │  workspace-1      │  │  workspace-2     │                                         │
│   │  eth0 @ 172.28... │  │  eth0 @ 172.28...│                                         │
│   │  all TCP → proxy  │  │  all TCP → proxy │                                         │
│   └───────────────────┘  └──────────────────┘                                         │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

### How it works

1. Proxy container runs xray-core as user `xray` with `dokodemo-door` inbound on port 12345.
2. `entrypoint.sh` sets up iptables PREROUTING NAT REDIRECT on the dev-proxy: all TCP arriving on the bridge interface from peer containers is redirected to port 12345.
3. Traffic originating inside dev-proxy itself (xray user) is excluded via `--uid-owner` to prevent loops.
4. Private CIDRs (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `127.0.0.0/8`) bypass the proxy and go direct (xray routing rules).
5. Workspace containers attach to the `ws-proxy` bridge network and have their default route replaced with the dev-proxy IP (`ip route replace default via 172.28.0.2`). They keep their OWN network namespace — they do NOT share dev-proxy's netns.

### Quick start

```bash
ws proxy init <vless-uri>       # generate config from VLESS URI (legacy single-config path; see Profile management below for the multi-profile path)
ws proxy check                  # verify prerequisites
ws proxy up                     # start proxy container
ws proxy test                   # exit IP, latency, diagnostics
ws new myproject go --proxy
ws start myproject
ws ssh myproject
# Inside: curl https://ifconfig.me → proxy exit IP
```

### Proxy commands

| Command | Description |
|---------|-------------|
| `ws proxy init <uri>` | Generate single-config xray from a VLESS URI (legacy path) |
| `ws proxy check` | Verify prerequisites (docker, config, image, container) |
| `ws proxy up` | Start proxy container |
| `ws proxy down` | Stop and remove proxy container |
| `ws proxy status` | Show container status and health |
| `ws proxy logs` | Show recent container logs |
| `ws proxy rebuild` | Force rebuild proxy image |
| `ws proxy test` | Exit IP, latency, xray version, diagnostics on failure |
| `ws proxy debug on\|off` | Toggle xray debug logging (restarts container) |
| `ws proxy update [vX.Y.Z]` | Update xray to latest or pinned version |
| `ws proxy fix-routes` | Restore default routes in workspace containers after reboot |
| `ws proxy profile add <name> <uri>` | Add a named VLESS profile from a URI |
| `ws proxy profile list [--json] [--reveal]` | List profiles (active marker, transport, address, masked credentials) |
| `ws proxy profile use <name>` | Validate, swap, and restart to profile `<name>` |
| `ws proxy profile show <name> [--reveal] [--json]` | Show profile details (masked unless `--reveal`) |
| `ws proxy profile current` | Print active profile name |
| `ws proxy profile rm <name> [--force]` | Remove a profile (refuses active; prompts unless `--force`) |
| `ws proxy profile regenerate <name>` | Refresh routing rules in `<name>` from the currently-active profile |

### Profile management

The `ws proxy profile *` subtree manages multiple named VLESS configurations
under `~/.config/xray/profiles/`. The currently-active profile is selected
via a symlink: `~/.config/xray/config.json → profiles/<active>.json`. Switching
is atomic at the symlink level + gated by `xray run -test` validation inside
the dev-proxy container before the swap.

```bash
# Add a primary and a backup profile.
ws proxy profile add primary vless://<uuid>@host1.example:443?type=tcp&security=reality&sni=ozon.ru&pbk=<key>&sid=<sid>#primary
ws proxy profile add backup  vless://<uuid>@host2.example:8443?type=xhttp&security=reality&sni=ozon.ru&pbk=<key>&sid=<sid>#backup

# List profiles with active marker (UUID and REALITY fields masked by default).
ws proxy profile list

# Switch to backup (validates, swaps symlink, restarts dev-proxy, waits for liveness).
ws proxy profile use backup

# Inspect current active profile.
ws proxy profile current

# Show profile details; --reveal opt-in for cleartext credentials.
ws proxy profile show primary           # UUID + REALITY publicKey/shortId masked
ws proxy profile show primary --reveal  # cleartext (for copy-paste; mind screen-share)

# If routing-rule drift develops (e.g., after adding port:22→direct on the active
# profile, the backup profile still has the old rules), refresh the backup:
ws proxy profile use primary
ws proxy profile regenerate backup

# Remove a profile (refuses removal of the currently-active profile).
ws proxy profile rm backup
```

#### Migration from legacy single-config layout

If `~/.config/xray/config.json` is still a regular file (pre-profile-management
layout), the first `ws proxy profile *` invocation auto-migrates: renames the
file to `profiles/primary.json` and creates a relative symlink
`config.json → profiles/primary.json`. The `[migrated]` log line records the
event. Pass `--no-migrate` to refuse auto-migration and surface a manual
remediation message instead.

#### Deprecation: `ws proxy init --add`

The legacy `ws proxy init --add <uri>` path (which appends a VLESS outbound to
the active config rather than creating a separate profile) is deprecated in
favor of `ws proxy profile add <name> <uri>`. A stderr warning fires on
invocation during the grace release; the path will be removed in the next
workspace-cli minor release. Migrate to `profile add` to take advantage of
named profiles, atomic switching, and `xray run -test` validation.

### Switch downtime and recovery

`ws proxy profile use <name>` performs a `docker restart dev-proxy` after the
symlink swap. Total downtime is ~5-15s depending on healthcheck timing. The
CLI waits up to 15s for the dev-proxy healthcheck to return `healthy` before
declaring success.

If validation (`xray run -test`) fails, the symlink is NOT touched — your
previous active profile keeps running. If validation passes but the restart
or post-restart healthcheck fails, the CLI surfaces:

- the failed stage
- the previous active profile name
- the exact recovery command (`ws proxy profile use <previous>`)
- a `docker logs dev-proxy --tail 50` hint

The CLI does NOT automatically roll the symlink back; you decide the next move
with full information. This is intentional — auto-rollback is operationally
the same animal as auto-failover, which the workspace-cli design rejects.

### Config

The proxy config lives at `~/.config/xray/config.json` on the host (not tracked
in this repo — contains secrets). Use `ws proxy profile add` for the
multi-profile path, or `ws proxy init` for a single-config setup. Each profile
file under `~/.config/xray/profiles/<name>.json` is a complete xray config
(full inbounds/outbounds/routing); the active one is selected by symlink.

### Evidence — bridge networking (not shared netns)

The bridge-network claim above is empirically verified (per `feedback_verify_before_claim`):

1. **Live `ip route` from inside a workspace container** (verified 2026-05-12):
   ```
   default via 172.28.0.2 dev eth0
   172.28.0.0/16 dev eth0 proto kernel scope link src 172.28.0.4
   ```
   The workspace has its OWN `eth0` interface on the `ws-proxy` bridge subnet and a default route via the gateway IP. Shared-netns containers would have only `lo` and dev-proxy's interfaces visible.

2. **dev-proxy network attachment** in `workspace-cli/internal/docker/docker.go` (ProxyUp):
   The container is created with `EndpointsConfig` mapping `ws-proxy` to `IPAMConfig.IPv4Address = cfg.ProxyIP` (default `172.28.0.2`). `ensureProxyNetwork` creates the `ws-proxy` bridge with `Driver: "bridge"` and `Subnet: cfg.ProxySubnet` (default `172.28.0.0/16`).

3. **iptables PREROUTING NAT REDIRECT** in `dot_config/workspaces/profiles/proxy/entrypoint.sh`:
   ```bash
   iptables -t nat -A PREROUTING -j XRAY
   ```
   The PREROUTING chain only sees traffic arriving on an interface from a different netns. Shared-netns containers would never traverse PREROUTING.

## Proxy Troubleshooting

**Workspace loses network after proxy rebuild:**

The `ws proxy rebuild` command restarts the proxy container, which
temporarily drops network for all connected workspaces. To restore
connectivity, restart the affected workspace:

```bash
ws stop <name> && ws start <name>
```

**Checking proxy health:**

```bash
ws proxy check    # verify docker, config, image, container are OK
ws proxy test     # check health and uptime
ws proxy logs     # inspect xray logs for errors
```

**Checking workspace connectivity (from inside the container):**

```bash
curl -s https://ifconfig.me   # should show the proxy exit IP
```

**Proxy container won't start:**

```bash
ws proxy check     # identify which prerequisite is failing
ws proxy rebuild   # rebuild the image from scratch
ws proxy up        # try starting again
```

## Requirements

- [devpod](https://devpod.sh/)
- Docker or compatible runtime
- SSH key for GitHub
- VLESS URI or `~/.config/xray/config.json` for proxy networking
