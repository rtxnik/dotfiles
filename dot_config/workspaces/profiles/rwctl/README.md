# rwctl Profile

Development environment for `rwctl` — declarative deployment and lifecycle
management for Remnawave control planes and Xray data-plane nodes.

## Toolchain

| Tool | Version | Why |
|------|---------|-----|
| Go | 1.25 (pinned) | Matches the project's CI `GO_VERSION`; a floating local toolchain causes green-locally / red-in-CI |
| build-essential | apt | `make test` is `CGO_ENABLED=1 go test -race`; the race detector needs a C toolchain |
| golangci-lint | latest | Mirrors the CI lint job, which itself runs `version: latest` |
| goreleaser | latest | `goreleaser check` and snapshot builds before cutting a tag |
| Docker-in-Docker | feature | **Required.** See below |
| Node.js | LTS | `npx` for agent tooling and MCP servers |
| jq, yq, fzf, ripgrep, fd | latest | The config gate checks rendered Xray profiles with `jq -e` |

`cosign` and `syft` are deliberately absent — signing and SBOM generation are
keyless in the release workflow. Host `openssl` is absent too: the gate's
`openssl req` calls run inside the nginx container.

## Why Docker-in-Docker is required

The `config-validation` CI job renders every example deployment and then
validates it by running `docker run "nginx:$TAG" … nginx -t` per rendered
`nginx.conf` and `docker compose --env-file .env config -q` per rendered stack.
Without a Docker daemon, that gate cannot be reproduced locally at all — a
change can only be judged after it reaches CI.

## Usage

```bash
ws new rwctl rwctl        # add --proxy for proxy networking
ws start rwctl
ws ssh rwctl
```

## Where the code lives

The bootstrap clones into the **host-mounted workspace folder**, not
`~/projects`. `~/projects` is container-local storage: it does not survive a
rebuild or `ws delete`, so a checkout there puts unpushed work one container
lifecycle away from unrecoverable loss. `~/projects/rwctl` is a symlink to the
real, host-persisted tree.

If the symlink is absent — most likely because the first boot ran before SSH
or `gh` were authenticated against the private repo — read the `[rwctl]
WARNING` line in the container create log, then clone by hand into the
workspace folder.

If the workspace was created before the repository had content, the first push
is picked up on the next rebuild — or immediately with:

```bash
git -C ~/projects/rwctl pull
```

The clone uses the SSH remote (the host forwards SSH into the container) and
falls back to `gh repo clone`. If neither is authenticated, the bootstrap logs
the prerequisite and continues, so the toolchain still installs.

## Fabric adoption

Not automatic. Materializing the development fabric writes dozens of files into
the product tree, so it is a deliberate, reviewed step: author `factory.json`,
download a **complete** `v1.0.5` release directory (the payload, both
`.sigstore.jsonl` bundles, the SBOM, `factory.lock` and `release.json` —
verification is fail-closed and a partial download aborts), then run
`factory install --from <dir>` and `factory verify`.

### Prerequisites the install does not provide

`factory install` vendors the fabric; it does not install what the fabric runs
*on*. The `standard` profile pulls five bundles, and each declares host
prerequisites that are **probed, not installed** — a missing one surfaces only
as a failed `factory verify`:

| Prerequisite | Bundle | Install |
|---|---|---|
| gitleaks | `secrets-deep` | `mise use -g gitleaks@8.30.1` |
| superpowers plugin | `workflow-spine` | `claude plugin install superpowers@claude-plugins-official` |
| claude-mem plugin | `memory-stack` | `claude plugin install claude-mem@thedotmack` |
| serena MCP server | `serena-stack` | `uv tool install serena-agent` |

The image and `mise.toml` above already carry the rest — shellcheck, shfmt,
bats, bun, python3 and PyYAML — because the fabric's vendored gate suites run
inside this container.

**serena must be registered at user scope.** The default `local` scope writes
the server under `.projects["<path>"].mcpServers` in `~/.claude.json`, but the
factory probes `jq -e '.mcpServers.serena' ~/.claude.json` — the **top level**
only. A local-scope registration is therefore invisible to `factory verify`
however well serena works in the session:

```bash
claude mcp add --scope user serena -- \
  serena start-mcp-server --context=claude-code --project-from-cwd
```

### The consumer must own a root CLAUDE.md

`scripts/check-integration-rubric.sh`, a hard step of the vendored
`integration-check` gate, runs `grep -q 'review-rubric.md' "$ROOT/CLAUDE.md"`.
A repo with no root `CLAUDE.md` — or one that never mentions the rubric — fails
that gate, and the failure names the rubric rather than the missing file. Write
the file and have it reference `.claude/review-rubric.md` before installing.
