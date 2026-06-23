#!/usr/bin/env bash
# =============================================================================
# Transparent proxy entrypoint (hybrid TPROXY)
#  - dev-container (forwarded) traffic : mangle PREROUTING TPROXY (tcp + udp)
#  - proxy's own egress (healthcheck)  : nat OUTPUT REDIRECT (tcp), uid xray bypassed
# Fail-closed: TPROXY to a non-listening xray drops; 'direct' outbound is private-only.
# =============================================================================
set -euo pipefail

MARK=1
TABLE=100
PORT=12345
PRIVATE=(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8 169.254.0.0/16 224.0.0.0/4)

# --- idempotent cleanup (Docker reuses the netns across restarts) ---
while iptables -t mangle -D PREROUTING -j XRAY 2>/dev/null; do :; done
while iptables -t nat    -D OUTPUT    -j XRAY_OUT 2>/dev/null; do :; done
iptables -t mangle -F XRAY 2>/dev/null || true; iptables -t mangle -X XRAY 2>/dev/null || true
iptables -t nat    -F XRAY_OUT 2>/dev/null || true; iptables -t nat -X XRAY_OUT 2>/dev/null || true
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

# --- nat OUTPUT: REDIRECT the proxy's OWN tcp egress (healthcheck), skip xray's tunnel ---
iptables -t nat -N XRAY_OUT
iptables -t nat -A XRAY_OUT -m owner --uid-owner xray -j RETURN
for net in "${PRIVATE[@]}"; do iptables -t nat -A XRAY_OUT -d "$net" -j RETURN; done
iptables -t nat -A XRAY_OUT -p tcp -j REDIRECT --to-ports $PORT
iptables -t nat -A OUTPUT -p tcp -j XRAY_OUT

# --- IPv6: this transparent proxy is IPv4-only. Fail closed: drop forwarded
#     IPv6 so dev-container v6 egress cannot leak around the v4 TPROXY capture.
#     Guarded so a container without ip6tables still starts. ---
if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -C FORWARD -j DROP 2>/dev/null || ip6tables -I FORWARD -j DROP || true
fi

# --- verify ---
iptables -t mangle -L XRAY -n >/dev/null 2>&1 && iptables -t nat -L XRAY_OUT -n >/dev/null 2>&1 \
  && echo "iptables applied (mangle PREROUTING TPROXY + nat OUTPUT REDIRECT)" \
  || { echo "ERROR: iptables rules failed to apply" >&2; exit 1; }

# --- validate + start xray ---
if ! su -s /bin/sh xray -c "xray run -test -c /etc/xray/config.json" >/dev/null 2>&1; then
    echo "ERROR: xray config validation failed" >&2
    su -s /bin/sh xray -c "xray run -test -c /etc/xray/config.json" >&2
    exit 1
fi
echo "xray config validated"
exec su -s /bin/sh xray -c "xray run -c /etc/xray/config.json"
