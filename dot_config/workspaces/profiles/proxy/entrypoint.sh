#!/usr/bin/env bash
# =============================================================================
# Transparent proxy entrypoint
# Sets up iptables NAT rules and starts xray as the xray user
# =============================================================================

set -euo pipefail

# --- iptables NAT rules ---

iptables -t nat -N XRAY

# Skip private networks (direct connection)
iptables -t nat -A XRAY -d 10.0.0.0/8 -j RETURN
iptables -t nat -A XRAY -d 172.16.0.0/12 -j RETURN
iptables -t nat -A XRAY -d 192.168.0.0/16 -j RETURN
iptables -t nat -A XRAY -d 127.0.0.0/8 -j RETURN

# Redirect all remaining TCP to xray dokodemo-door
iptables -t nat -A XRAY -p tcp -j REDIRECT --to-ports 12345

# Apply to OUTPUT, but skip traffic from xray user (prevent loops)
iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner xray -j RETURN
iptables -t nat -A OUTPUT -j XRAY

echo "iptables rules applied"

# --- Start xray ---

exec su -s /bin/sh xray -c "xray run -c /etc/xray/config.json"
