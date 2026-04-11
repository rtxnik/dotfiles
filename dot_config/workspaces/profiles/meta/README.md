# Meta Profile

Unified development environment for working on the entire workflow
infrastructure in a single DevPod container.

## Included Projects

| Repository | Purpose |
|------------|---------|
| `dotfiles` | chezmoi-managed dotfiles and workspace profiles |
| `workflow-kit` | Bash/Node framework wrapping Claude Code |
| `workspace-cli` | Go CLI for DevPod workspace management |
| `vault` | Obsidian vault (planned, not yet created) |

## Toolchain

- **Go** (latest) + golangci-lint, goreleaser — workspace-cli development
- **Node.js** (LTS) + pnpm — workflow-kit dependencies
- **Neovim** (v0.10+, official tarball) — editor, LazyVim config via chezmoi
- **bats-core** — bash test framework for workflow-kit hooks
- **shellcheck**, **shfmt** — shell script linting and formatting
- **Python 3** — system utilities and nvim plugin support
- **chezmoi** — installed by shared post-create script
- **git-lfs** — large file support for vault attachments
- **tmux** — multi-project terminal sessions
- **gh** — GitHub CLI (installed via devcontainer feature)
- ripgrep, fd, fzf, jq, yq, bat, delta — search and data tools

## Usage

```bash
ws new workflow-meta meta
ws start workflow-meta
ws ssh workflow-meta
```

On first start, the post-create hook clones all four repositories into
`~/projects/` and checks out the working branch. Subsequent starts skip
already-cloned repos and preserve local changes.

## Architecture Detection

Both the Neovim tarball and the base image support amd64 and arm64.
No manual configuration needed when switching between platforms.
