#!/usr/bin/env bats
# Packets of established forwarded flows match `-m socket` in mangle/XRAY. A
# bare RETURN there strips the fwmark, so everything after the first SYN
# misses the `fwmark lookup 100` policy route and leaks out the default route
# to the real server -- the handshake never completes and the forwarding
# datapath is dead, while self-egress (marked per-packet in OUTPUT) stays
# green (2026-07-07 postmortem). The socket match must jump to a DIVERT chain
# that re-applies the mark before ACCEPT (canonical TPROXY DIVERT pattern).

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
ENTRYPOINT="${REPO_ROOT}/dot_config/workspaces/profiles/proxy/entrypoint.sh"

@test "socket-match rules jump to DIVERT, never bare RETURN" {
  run grep -E -- '-m socket.*-j RETURN' "${ENTRYPOINT}"
  [ "$status" -ne 0 ]
  count=$(grep -cE -- '\-A XRAY -p (tcp|udp) -m socket --transparent -j DIVERT' "${ENTRYPOINT}")
  [ "$count" -eq 2 ]
}

@test "DIVERT chain re-applies the TPROXY fwmark before ACCEPT" {
  run grep -E -- '\-A DIVERT -j MARK --set-mark \$MARK' "${ENTRYPOINT}"
  [ "$status" -eq 0 ]
  run grep -E -- '\-A DIVERT -j ACCEPT' "${ENTRYPOINT}"
  [ "$status" -eq 0 ]
}

@test "idempotent cleanup flushes and deletes the DIVERT chain" {
  run grep -E -- 'iptables -t mangle -F DIVERT' "${ENTRYPOINT}"
  [ "$status" -eq 0 ]
  run grep -E -- 'iptables -t mangle -X DIVERT' "${ENTRYPOINT}"
  [ "$status" -eq 0 ]
}
