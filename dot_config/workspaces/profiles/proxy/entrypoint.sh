#!/usr/bin/env bash
# =============================================================================
# Transparent proxy entrypoint
# Sets up iptables NAT rules and starts xray as the xray user
# =============================================================================

set -euo pipefail

# --- iptables NAT rules ---
#
# On container restart Docker reuses the network namespace, so any rules
# from the previous run persist. Clean up before re-applying to keep the
# entrypoint idempotent (otherwise `-N XRAY` fails with "Chain already
# exists" and `set -e` aborts the whole startup).

# Detach XRAY from OUTPUT/PREROUTING if previously attached, then flush
# and drop the chain so we can recreate it from scratch.
while iptables -t nat -D OUTPUT -j XRAY 2>/dev/null; do :; done
while iptables -t nat -D PREROUTING -j XRAY 2>/dev/null; do :; done
iptables -t nat -D OUTPUT -p tcp -m owner --uid-owner xray -j RETURN 2>/dev/null || true
iptables -t nat -D OUTPUT -p udp -m owner --uid-owner xray -j RETURN 2>/dev/null || true
iptables -t nat -F XRAY 2>/dev/null || true
iptables -t nat -X XRAY 2>/dev/null || true

iptables -t nat -N XRAY

# Skip private networks (direct connection)
iptables -t nat -A XRAY -d 10.0.0.0/8 -j RETURN
iptables -t nat -A XRAY -d 172.16.0.0/12 -j RETURN
iptables -t nat -A XRAY -d 192.168.0.0/16 -j RETURN
iptables -t nat -A XRAY -d 127.0.0.0/8 -j RETURN

# Redirect all remaining TCP and UDP to xray dokodemo-door
iptables -t nat -A XRAY -p tcp -j REDIRECT --to-ports 12345
iptables -t nat -A XRAY -p udp -j REDIRECT --to-ports 12345

# Apply to OUTPUT for proxy's own traffic (skip xray user to prevent loops)
iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner xray -j RETURN
iptables -t nat -A OUTPUT -p udp -m owner --uid-owner xray -j RETURN
iptables -t nat -A OUTPUT -j XRAY

# Apply to PREROUTING for traffic from workspace containers on bridge network
iptables -t nat -A PREROUTING -j XRAY

# Verify iptables rules were applied
if iptables -t nat -L XRAY -n >/dev/null 2>&1; then
    echo "iptables rules applied (OUTPUT + PREROUTING)"
else
    echo "ERROR: iptables rules failed to apply" >&2
    exit 1
fi

# --- Start xray ---

# Validate config before starting
if ! su -s /bin/sh xray -c "xray run -test -c /etc/xray/config.json" >/dev/null 2>&1; then
    echo "ERROR: xray config validation failed" >&2
    su -s /bin/sh xray -c "xray run -test -c /etc/xray/config.json" >&2
    exit 1
fi
echo "xray config validated"

exec su -s /bin/sh xray -c "xray run -c /etc/xray/config.json"
