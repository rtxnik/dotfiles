#!/bin/bash
# cloud-doctor: what a cloud session actually has, against what setup.sh and
# the environment's settings promise. Installed to /usr/local/bin by setup.sh.
# Exit 1 when the git identity is wrong (commits would carry another name),
# 0 otherwise; every other gap is reported, not fatal. CLOUD_DOCTOR_OFFLINE=1
# skips the checks that call an API.

set -uo pipefail

owner_name="${CLOUD_OWNER_NAME:-rtxnik}"
owner_email="${CLOUD_OWNER_EMAIL:-rtxs.nik@gmail.com}"
claude_dir="${CLOUD_CLAUDE_DIR:-${HOME:-/root}/.claude}"
rc=0

ok() { printf '  ok    %s\n' "$*"; }
miss() { printf '  MISS  %s\n' "$*"; }

echo "identity"
for who in AUTHOR COMMITTER; do
  ident="$(git var "GIT_${who}_IDENT" 2>/dev/null | sed 's/ [0-9]* [-+][0-9]*$//')"
  if [ "$ident" = "$owner_name <$owner_email>" ]; then
    ok "$who $ident"
  else
    miss "$who is '${ident:-unset}', expected '$owner_name <$owner_email>'"
    rc=1
  fi
done

echo "toolchain"
for tool in node pnpm vercel jq yq uv gh shellcheck bats gitleaks graphify serena; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool $("$tool" --version 2>/dev/null | head -1)"
  else
    miss "$tool"
  fi
done
if yq --version 2>/dev/null | grep -q mikefarah; then
  ok "yq is mikefarah v4"
else
  miss "yq is not mikefarah v4 (the fabric's scripts need it)"
fi

echo "claude code"
if [ -s "$claude_dir/CLAUDE.md" ]; then ok "global instructions"; else miss "global instructions ($claude_dir/CLAUDE.md)"; fi
if jq -e '.attribution.commit == "" and .attribution.pr == "" and .attribution.sessionUrl == false' \
     "$claude_dir/settings.json" >/dev/null 2>&1; then
  ok "attribution off"
else
  miss "attribution not switched off in $claude_dir/settings.json"
fi
plugins="$(claude plugin list 2>/dev/null)"
for plugin in $(jq -r '.enabledPlugins // {} | keys[]' "$claude_dir/settings.json" 2>/dev/null); do
  if grep -q "$plugin" <<<"$plugins"; then ok "plugin $plugin"; else miss "plugin $plugin"; fi
done
if jq -e '.mcpServers.serena' "${HOME:-/root}/.claude.json" >/dev/null 2>&1; then
  ok "mcp serena (user scope)"
else
  miss "mcp serena (user scope)"
fi

[ -n "${CLOUD_DOCTOR_OFFLINE:-}" ] && exit "$rc"

echo "api tokens"
if [ -n "${VERCEL_TOKEN:-}" ]; then
  if vercel whoami >/dev/null 2>&1; then ok "vercel: $(vercel whoami 2>/dev/null | tail -1)"; else miss "vercel: VERCEL_TOKEN set but rejected"; fi
else
  miss "vercel: VERCEL_TOKEN not set"
fi
# With a network secret the proxy attaches the key itself and no variable is set.
auth=()
[ -n "${TIMEWEB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $TIMEWEB_TOKEN")
code="$(curl -s -o /dev/null -w '%{http_code}' "${auth[@]}" https://api.timeweb.cloud/api/v1/apps 2>/dev/null)"
if [ "$code" = 200 ]; then ok "timeweb: API answers 200"; else miss "timeweb: API answers ${code:-nothing} (token missing or rejected)"; fi

exit "$rc"
