#!/usr/bin/env bats
# The transparent-proxy image must ship a UDP/53 DNS client (dig) so that
# `ws proxy doctor` / `ws proxy test` can run the H10 self-egress UDP/DNS leak
# probe from INSIDE the proxy container (see workspace-meta spec
# 2026-06-26-ws-cli-h10-udp-dns-leak-vantage-redesign-design.md).

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
PROXY_DOCKERFILE="${REPO_ROOT}/dot_config/workspaces/profiles/proxy/Dockerfile"

@test "proxy image installs bind9-dnsutils (dig) for the H10 UDP/DNS probe" {
  run grep -E 'bind9-dnsutils' "${PROXY_DOCKERFILE}"
  [ "$status" -eq 0 ]
}
