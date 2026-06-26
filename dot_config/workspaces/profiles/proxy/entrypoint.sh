#!/usr/bin/env bash
# =============================================================================
# Transparent proxy entrypoint (hybrid TPROXY, single listener)
#  - dev-container (forwarded) traffic      : mangle PREROUTING TPROXY (tcp + udp)
#  - proxy's own egress (healthcheck/doctor) : mangle OUTPUT MARK (tcp + udp),
#    policy-routed back through PREROUTING into the SAME listener; uid xray exempt.
# Fail-closed: TPROXY/marked self-egress to a non-listening xray drops; 'direct'
# outbound is private-only; IPv6 egress (forward + output) is dropped.
# =============================================================================
set -euo pipefail

MARK=1
TABLE=100
PORT=12345
PRIVATE=(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8 169.254.0.0/16 224.0.0.0/4)

# --- idempotent cleanup (Docker reuses the netns across restarts) ---
while iptables -t mangle -D PREROUTING -j XRAY      2>/dev/null; do :; done
while iptables -t mangle -D OUTPUT     -j XRAY_SELF 2>/dev/null; do :; done
while iptables -D INPUT -m mark --mark $MARK -j ACCEPT 2>/dev/null; do :; done
iptables -t mangle -F XRAY      2>/dev/null || true; iptables -t mangle -X XRAY      2>/dev/null || true
iptables -t mangle -F XRAY_SELF 2>/dev/null || true; iptables -t mangle -X XRAY_SELF 2>/dev/null || true
ip rule del fwmark $MARK lookup $TABLE 2>/dev/null || true
ip route flush table $TABLE 2>/dev/null || true

# --- kernel preconditions for TPROXY: reverse-path filtering OFF and
#     route_localnet ON so marked, foreign-destined packets reach the local (lo)
#     transparent socket. Per-interface because the effective rp_filter is
#     max(conf.all, conf.<iface>), so every interface must read 0.
#
#     /proc/sys is mounted read-only inside a default container (runc's default
#     readonlyPaths), so these writes can fail with EROFS even when the values
#     are already correct: the proxy runtime supplies them declaratively via
#     `docker --sysctl` (see workspace-cli internal/docker/docker.go — note `lo`
#     pre-exists the sysctl pass so it needs explicit lo.* entries; eth0 inherits
#     default.*). We therefore write best-effort and then ASSERT the effective
#     state, failing closed only when a value is genuinely wrong (a real
#     silent-drop risk), not merely because /proc/sys is read-only. ---
for f in /proc/sys/net/ipv4/conf/*/rp_filter;      do echo 0 > "$f" 2>/dev/null || true; done
for f in /proc/sys/net/ipv4/conf/*/route_localnet; do echo 1 > "$f" 2>/dev/null || true; done

sysctl_bad=""
for f in /proc/sys/net/ipv4/conf/*/rp_filter; do
    [ "$(cat "$f")" = 0 ] || sysctl_bad="${sysctl_bad} ${f#/proc/sys/}=$(cat "$f")(want 0)"
done
for f in /proc/sys/net/ipv4/conf/*/route_localnet; do
    [ "$(cat "$f")" = 1 ] || sysctl_bad="${sysctl_bad} ${f#/proc/sys/}=$(cat "$f")(want 1)"
done
if [ -n "$sysctl_bad" ]; then
    echo "ERROR: TPROXY sysctl preconditions unmet (read-only /proc/sys and not supplied via 'docker --sysctl'):${sysctl_bad}" >&2
    exit 1
fi
echo "tproxy sysctls verified (rp_filter=0, route_localnet=1 on all interfaces)"

# --- policy routing: deliver marked, foreign-destined packets to the local TPROXY socket ---
ip rule add fwmark $MARK lookup $TABLE
ip route add local default dev lo table $TABLE

# --- mangle PREROUTING: TPROXY forwarded dev-container traffic ---
iptables -t mangle -N XRAY
for net in "${PRIVATE[@]}"; do iptables -t mangle -A XRAY -d "$net" -j RETURN; done
# Established flows already owned by a local transparent socket bypass re-TPROXY.
# Guarded: if the xt_socket module is unavailable the rule is skipped and we fall
# back to plain TPROXY (still correct), never aborting startup.
iptables -t mangle -A XRAY -p tcp -m socket -j RETURN 2>/dev/null || true
iptables -t mangle -A XRAY -p udp -m socket -j RETURN 2>/dev/null || true
iptables -t mangle -A XRAY -p tcp -j TPROXY --on-port $PORT --tproxy-mark $MARK
iptables -t mangle -A XRAY -p udp -j TPROXY --on-port $PORT --tproxy-mark $MARK
iptables -t mangle -A PREROUTING -j XRAY

# --- mangle OUTPUT: MARK the proxy's OWN egress (healthcheck + doctor probes)
#     so the existing fwmark policy route bounces it back through PREROUTING into
#     the SAME tproxy listener with the real destination preserved (no DNAT, no
#     loopback). Replaces nat OUTPUT REDIRECT, which DNAT'd self-egress to
#     127.0.0.1:12345 and tripped xray's loopback guard, and which (being a
#     nat/TCP-only helper) silently leaked the proxy's own UDP/QUIC egress. ---
iptables -t mangle -N XRAY_SELF
# Rule #1 (MUST be first): loop guard. xray's own tunnelled egress (uid xray) is
# exempt; the healthcheck/doctor probes run as ROOT (no USER directive in the
# image) so they are NOT exempt and ARE tunnelled — exactly the desired split.
iptables -t mangle -A XRAY_SELF -m owner --uid-owner xray -j RETURN
# Keep intra-container / LAN / loopback / DNS-to-resolver / management traffic
# direct. PRIVATE includes 127.0.0.0/8, so this loop also provides the
# CVE-2020-8558 (route_localnet) martian rail ahead of the MARK rules.
for net in "${PRIVATE[@]}"; do iptables -t mangle -A XRAY_SELF -d "$net" -j RETURN; done
iptables -t mangle -A XRAY_SELF -p tcp -j MARK --set-mark $MARK
iptables -t mangle -A XRAY_SELF -p udp -j MARK --set-mark $MARK
iptables -t mangle -A OUTPUT -j XRAY_SELF
# Accept the policy-routed self packets re-entering via lo: a default-DROP INPUT
# would silently drop them (XTLS discussion #4039).
iptables -I INPUT -m mark --mark $MARK -j ACCEPT

# --- IPv6: this transparent proxy is IPv4-only. Fail closed so neither
#     forwarded nor the box's own IPv6 egress can leak around the v4 TPROXY
#     capture. Defense in depth: the IPv6 stack is disabled at container-create
#     via the HostConfig sysctl net.ipv6.conf.*.disable_ipv6=1 (ws-cli), and the
#     ip6tables FORWARD/OUTPUT DROP rules below are the belt on top. DROP rules
#     are load-bearing (no `|| true`); ACCEPT rules tighten-only (a failure makes
#     v6 MORE fail-closed) so they keep `|| true`. We only READ disable_ipv6 here
#     -- writing /proc/sys under `set -e` can EROFS-abort on a read-only mount. ---
v6_disabled=0
if [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 0)" = "1" ]; then
    v6_disabled=1
fi

if command -v ip6tables >/dev/null 2>&1; then
    # tighten-only ACCEPTs (loopback + reply traffic)
    ip6tables -C OUTPUT -o lo -j ACCEPT 2>/dev/null || ip6tables -I OUTPUT -o lo -j ACCEPT || true
    ip6tables -C OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
        || ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || true
    # load-bearing DROPs: install idempotently; decide fatality by whether v6 is live
    if ! { ip6tables -C FORWARD -j DROP 2>/dev/null || ip6tables -I FORWARD -j DROP; } \
       || ! { ip6tables -C OUTPUT -j DROP 2>/dev/null || ip6tables -A OUTPUT -j DROP; }; then
        if [ "$v6_disabled" = "1" ]; then
            echo "WARN: ip6tables v6 DROP insert failed, but the IPv6 stack is disabled (disable_ipv6=1) -- still fail-closed" >&2
        else
            echo "ERROR: IPv6 is active but ip6tables FORWARD/OUTPUT DROP could not be installed -- refusing to start (v6 leak risk)" >&2
            exit 1
        fi
    fi
else
    if [ "$v6_disabled" = "1" ]; then
        echo "WARN: ip6tables absent; relying on disabled IPv6 stack (disable_ipv6=1) for fail-closed" >&2
    else
        echo "ERROR: ip6tables absent and IPv6 is active -- cannot fail-close v6 -- refusing to start" >&2
        exit 1
    fi
fi

# --- verify ---
iptables -t mangle -L XRAY -n >/dev/null 2>&1 && iptables -t mangle -L XRAY_SELF -n >/dev/null 2>&1 \
  && echo "iptables applied (mangle PREROUTING TPROXY + mangle OUTPUT MARK self-egress)" \
  || { echo "ERROR: iptables rules failed to apply" >&2; exit 1; }

# --- validate + start xray ---
if ! su -s /bin/sh xray -c "xray run -test -c /etc/xray/config.json" >/dev/null 2>&1; then
    echo "ERROR: xray config validation failed" >&2
    su -s /bin/sh xray -c "xray run -test -c /etc/xray/config.json" >&2
    exit 1
fi
echo "xray config validated"
exec su -s /bin/sh xray -c "xray run -c /etc/xray/config.json"
