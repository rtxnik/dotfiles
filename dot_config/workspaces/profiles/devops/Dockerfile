FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    dnsutils iputils-ping netcat-openbsd traceroute mtr-tiny \
    iproute2 tcpdump nmap python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://mise.jdx.dev/install.sh | sh \
    && pip3 install ansible

ENV PATH="/home/vscode/.local/bin:${PATH}"
