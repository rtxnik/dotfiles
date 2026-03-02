FROM ubuntu:24.04

ARG XRAY_VERSION=v26.2.6

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl unzip iptables \
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
    && unzip /tmp/xray.zip -d /tmp/xray \
    && mv /tmp/xray/xray /usr/local/bin/xray \
    && chmod +x /usr/local/bin/xray \
    && rm -rf /tmp/xray /tmp/xray.zip

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -sf --max-time 5 https://ifconfig.me || exit 1

ENTRYPOINT ["/entrypoint.sh"]
