FROM ubuntu:24.04@sha256:786a8b558f7be160c6c8c4a54f9a57274f3b4fb1491cf65146521ae77ff1dc54  # = ubuntu:24.04 (manifest-list index); refresh procedure: workspace-cli docs/proxy-runbook.md

ARG XRAY_VERSION=v26.2.6

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl unzip iptables libcap2-bin iproute2 bind9-dnsutils \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -r -s /usr/sbin/nologin xray \
    && ARCH=$(dpkg --print-architecture) \
    && case "$ARCH" in \
         amd64)  XRAY_ARCH="64" ;; \
         arm64)  XRAY_ARCH="arm64-v8a" ;; \
         *)      echo "Unsupported architecture: $ARCH" && exit 1 ;; \
       esac \
    && curl -fsSL \
       "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip" \
       -o /tmp/xray.zip \
    && curl -fsSL \
       "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip.dgst" \
       -o /tmp/xray.zip.dgst \
    && EXPECT=$(grep -ioE 'sha2-256[^0-9a-f]*[0-9a-f]{64}' /tmp/xray.zip.dgst | grep -oiE '[0-9a-f]{64}' | head -1) \
    && ACTUAL=$(sha256sum /tmp/xray.zip | awk '{print $1}') \
    && [ -n "$EXPECT" ] && [ "$EXPECT" = "$ACTUAL" ] \
       || { echo "xray-core checksum mismatch: expected=$EXPECT actual=$ACTUAL" >&2; exit 1; } \
    && unzip /tmp/xray.zip -d /tmp/xray \
    && mv /tmp/xray/xray /usr/local/bin/xray \
    && chmod +x /usr/local/bin/xray \
    && setcap cap_net_admin+ep /usr/local/bin/xray \
    && getcap /usr/local/bin/xray | grep -q cap_net_admin \
       || { echo "setcap failed: xray has no cap_net_admin (nosuid/no-xattr fs?)" >&2; exit 1; } \
    && rm -rf /tmp/xray /tmp/xray.zip /tmp/xray.zip.dgst

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -sf --max-time 5 https://ifconfig.me || exit 1

ENTRYPOINT ["/entrypoint.sh"]
