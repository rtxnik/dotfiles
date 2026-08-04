FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# build-essential is load-bearing: `make test` is `CGO_ENABLED=1 go test -race`,
# and the race detector needs a C toolchain.
#
# The mise install here mirrors every other profile in the fleet and is a
# convenience only: the mise the container actually uses is installed for the
# `vscode` user by chezmoi (.chezmoiexternals -> ~/.local/bin/mise) during
# post-create, before anything needs it.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl build-essential git iproute2 unzip \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://mise.jdx.dev/install.sh | sh

ENV PATH="/home/vscode/.local/bin:${PATH}"
