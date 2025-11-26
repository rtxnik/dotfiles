FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl python3-pip \
        dnsutils iputils-ping netcat-openbsd traceroute mtr-tiny iproute2 tcpdump nmap \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://mise.jdx.dev/install.sh | sh \
    && pip3 install --user ansible --break-system-packages

ENV PATH="/home/vscode/.local/bin:${PATH}"
