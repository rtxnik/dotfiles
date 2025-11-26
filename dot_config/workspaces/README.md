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
| `k8s` | kubectl, helm, k9s, kind, stern, flux, argocd |
| `web` | node (lts), bun, deno, pnpm |

## Requirements

- devpod
- Docker or compatible runtime
- SSH key for GitHub
