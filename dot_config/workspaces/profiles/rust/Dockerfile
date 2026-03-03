FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl build-essential git iproute2 pkg-config libssl-dev \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://mise.jdx.dev/install.sh | sh

ENV PATH="/home/vscode/.local/bin:${PATH}"
