#!/usr/bin/env bats
# The TPROXY sysctl ASSERT must cover only datapath interfaces
# (all/default/lo/eth0). A glob over /proc/sys/net/ipv4/conf/* also matches
# kernel fallback tunnel devices (gre0, sit0, tunl0, erspan0, ...) that are
# auto-created in every netns on hosts with tunnel modules loaded (e.g. Docker
# Desktop VMs) BEFORE docker applies --sysctl, so conf.default never reaches
# them. They carry no traffic, so asserting their values only bricks startup.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
ENTRYPOINT="${REPO_ROOT}/dot_config/workspaces/profiles/proxy/entrypoint.sh"

@test "sysctl assert iterates the scoped datapath interface list" {
  run grep -E 'for ifc in all default lo eth0' "${ENTRYPOINT}"
  [ "$status" -eq 0 ]
}

@test "only the two best-effort write loops glob conf/* (asserts must not)" {
  count=$(grep -c 'for f in /proc/sys/net/ipv4/conf/' "${ENTRYPOINT}")
  [ "$count" -eq 2 ]
}
