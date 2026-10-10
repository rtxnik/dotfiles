# cloud — the workspace on claude.ai/code

The DevPod profiles in `../profiles/` give a container its toolchain and the
owner's rules. Claude Code's cloud sessions (claude.ai/code, the phone app) run
instead on Anthropic's VMs — fresh Ubuntu 24.04, root, one repository cloned
under `/home/user/` — which read none of that. This directory is their
counterpart: one bootstrap, versioned here, that every cloud environment loads.

## Wiring a cloud environment (once per environment)

In claude.ai/code open the environment menu in a session's title bar → Edit:

1. **Setup script** — paste `loader.sh` verbatim. It clones this repository to
   `/opt/dotfiles` and runs `setup.sh`; it never fails the session.
2. **Network access** — Full, or Trusted plus the hosts the work needs
   (`api.vercel.com`, `api.timeweb.cloud`, `api.elevenlabs.io`, …).
3. **Network secrets** (Pro/Max) — API keys the proxy attaches to requests
   without the session ever seeing them, one per host:

   | Name | Allowed websites | Header | Prefix | Placeholder variable |
   |------|------------------|--------|--------|----------------------|
   | Vercel | `api.vercel.com` | `Authorization` | `Bearer` | `VERCEL_TOKEN=network-secret` |
   | Timeweb | `api.timeweb.cloud` | `Authorization` | `Bearer` | — |
   | ElevenLabs | `api.elevenlabs.io` | `xi-api-key` | none | `ELEVENLABS_API_KEY=network-secret` |

   A CLI or SDK that refuses to start without its variable (the Vercel CLI,
   the ElevenLabs SDKs and MCP server) gets the placeholder in **Environment
   variables**; a plain `curl` needs no variable at all. On plans without
   network secrets the variables hold the real keys.

Connectors (Notion, Linear, Slack, Google Drive, …) and plugins turned on in
the claude.ai account reach every cloud session by themselves; they are
switched on in claude.ai's settings, not here.

## What setup.sh gives a session

| Piece | Detail |
|-------|--------|
| Toolchain | corepack 0.36 with pnpm shims (each repository gets the pnpm its `packageManager` pins), Vercel CLI, shellcheck, bats, gitleaks v8.30.1, mikefarah yq v4.53.2, graphify 0.9.63, serena 1.7.0, ffmpeg for the voiceovers — on top of the image's Node 22, Python, uv, Go, jq, gh, Playwright Chromium |
| Plugins | superpowers and frontend-design at user scope. A cloud session ignores the plugins a repository's `.claude/settings.json` enables, so the list lives in `setup.sh` and `settings.json` |
| MCP | serena at user scope, `--context=claude-code --project-from-cwd`, as in the workspaces |
| Git identity | `rtxnik <rtxs.nik@gmail.com>` for author and committer through `env` in `~/.claude/settings.json`; the platform's own `~/.gitconfig` names another author |
| Attribution | off: `attribution.commit` and `.pr` empty, `sessionUrl` false |
| Rules | `instructions.md` becomes `~/.claude/CLAUDE.md`: the workspace rules of `WORKSPACE.md` for a session that has no workspace root |
| Self-check | `cloud-doctor` — identity, toolchain, plugins, MCP, and whether Vercel, Timeweb and ElevenLabs accept the session |

Deliberately absent: the `factory` CLI and everything else from private
repositories (the setup script runs with no GitHub credentials), the external
reviewers (each needs an interactive login), claude-mem (its timeline would not
outlive the VM), DevPod, `ws`, the vault, age keys.

## Load-bearing details

- **The setup script runs before the repository is cloned** and its result is
  cached, so nothing repository-specific belongs here: dependencies are
  installed in the session.
- **The environment caches the setup for about seven days** and rebuilds sooner
  only when the setup script's text changes. A change here reaches sessions at
  the next rebuild; bump `revision` in the pasted loader to roll it out now.
- **`~/.claude/settings.json` is read by the cloud session**, unlike the
  laptop's: that is what makes the plugins, the identity and the attribution
  setting stick. The platform rewrites `~/.gitconfig` at every start, which is
  why the identity travels as environment variables instead.
- **Commits stay signed by the platform's key.** Branch commits may read
  "Unverified" on GitHub; the squash commit on main is GitHub's own.
