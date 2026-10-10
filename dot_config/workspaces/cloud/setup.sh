#!/bin/bash
# Bootstrap of the cloud environment that runs Claude Code sessions on
# claude.ai/code: the toolchain, plugins, git identity and rules of the DevPod
# workspaces, applied to the cloud's fresh Ubuntu 24.04 VM.
#
# The environment's "Setup script" field holds only the loader shown in
# README.md, which fetches this repository and runs this file as root before
# Claude Code starts. The filesystem it leaves is snapshotted and reused by
# later sessions, so this script
#   - finishes well inside five minutes (about two), or the cache is not kept;
#   - exits 0 whatever happens: a non-zero exit stops sessions from starting;
#   - runs before any repository is cloned, so it carries nothing repo-specific.
# Every step is best-effort and the summary names what failed; `cloud-doctor`
# repeats the checks inside a session.
#
# Safe to re-run inside a session: bash setup.sh

set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
export PATH="/opt/node22/bin:/usr/local/go/bin:${HOME:-/root}/.local/bin:${PATH}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
claude_dir="${CLOUD_CLAUDE_DIR:-${HOME:-/root}/.claude}"
bin_dir="${CLOUD_BIN_DIR:-/usr/local/bin}"

COREPACK_VERSION=0.36.0   # the image's corepack cannot run pnpm 12
VERCEL_VERSION=63.1.0
GITLEAKS_VERSION=v8.30.1  # .pre-commit-config.yaml
YQ_VERSION=v4.53.2        # the fabric's setup-yq action
GRAPHIFY_VERSION=0.9.63   # tools/workflow-graph/uv.lock in the fabric consumers
SERENA_VERSION=1.7.0
PLUGINS=(
  superpowers@claude-plugins-official
  frontend-design@claude-plugins-official
)

failed=()
log() { printf '[cloud-setup %s] %s\n' "$(date +%T)" "$*"; }

# step <label> <command...>: run quietly, report the outcome, never fail the script.
step() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    log "ok      $label"
  else
    log "FAILED  $label"
    return 1
  fi
}

# Independent installs run in parallel; each records its own failure in a file
# because a background subshell cannot append to the parent's array.
status_dir="$(mktemp -d)"
bg() { local label=$1; shift; { step "$label" "$@" || touch "$status_dir/$label"; } & }

bg "node tools (corepack, vercel)" \
  npm install -g --no-fund --no-audit "corepack@${COREPACK_VERSION}" "vercel@${VERCEL_VERSION}"
# ffmpeg cuts, fades and levels the presentations' voiceovers (ElevenLabs takes);
# the image carries it today, this keeps it when the image changes.
bg "apt (shellcheck, bats, ffmpeg)" \
  sh -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends shellcheck bats ffmpeg'
bg "gitleaks ${GITLEAKS_VERSION}" \
  env GOBIN="$bin_dir" go install \
    -ldflags "-X=github.com/zricethezav/gitleaks/v8/version.Version=${GITLEAKS_VERSION}" \
    "github.com/zricethezav/gitleaks/v8@${GITLEAKS_VERSION}"
bg "yq ${YQ_VERSION}" \
  env GOBIN="$bin_dir" go install "github.com/mikefarah/yq/v4@${YQ_VERSION}"
bg "graphify ${GRAPHIFY_VERSION}" \
  uv tool install --force "graphifyy==${GRAPHIFY_VERSION}"
bg "serena ${SERENA_VERSION}" \
  uv tool install --force "serena-agent==${SERENA_VERSION}"
wait

for f in "$status_dir"/*; do [ -e "$f" ] && failed+=("$(basename "$f")"); done
rm -rf "$status_dir"

# pnpm through corepack: every repository gets the version its packageManager
# field pins, downloaded on first use.
step "pnpm shims (corepack)" corepack enable pnpm || failed+=("pnpm shims")

# Plugins at user scope: a cloud session loads these, unlike the ones a
# repository's .claude/settings.json enables.
step "plugin marketplace" \
  claude plugin marketplace add anthropics/claude-plugins-official || true
for plugin in "${PLUGINS[@]}"; do
  step "plugin $plugin" claude plugin install "$plugin" --scope user || failed+=("$plugin")
done

# serena as a user-level MCP server, the way the workspaces register it.
if command -v serena >/dev/null 2>&1; then
  claude mcp remove --scope user serena >/dev/null 2>&1 || true
  step "mcp serena" claude mcp add --scope user serena -- \
    serena start-mcp-server --context=claude-code --project-from-cwd || failed+=("mcp serena")
fi

# User settings: the template's keys win over whatever the plugin installs wrote,
# and enabledPlugins from both are kept.
mkdir -p "$claude_dir"
settings="$claude_dir/settings.json"
[ -s "$settings" ] || printf '{}\n' > "$settings"
if jq -s '.[0] * .[1]' "$settings" "$here/settings.json" > "$settings.tmp"; then
  mv "$settings.tmp" "$settings"
  log "ok      user settings"
else
  rm -f "$settings.tmp"
  log "FAILED  user settings"
  failed+=("user settings")
fi

# Global instructions: Claude Code reads ~/.claude/CLAUDE.md in every session.
if install -m 644 "$here/instructions.md" "$claude_dir/CLAUDE.md"; then
  log "ok      global instructions"
else
  failed+=("global instructions")
fi

install -m 755 "$here/doctor.sh" "$bin_dir/cloud-doctor" || failed+=("cloud-doctor")

if [ "${#failed[@]}" -eq 0 ]; then
  log "done: everything installed"
else
  log "done with failures: ${failed[*]}"
fi
exit 0
