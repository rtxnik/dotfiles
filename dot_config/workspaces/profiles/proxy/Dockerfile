FROM ubuntu:24.04

ARG XRAY_VERSION=v24.12.31

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/* \
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

EXPOSE 10808 10809

ENTRYPOINT ["xray", "run", "-c", "/etc/xray/config.json"]
