FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# System packages required for Go builds, Node native addons, neovim deps,
# git-lfs (Obsidian vault attachments), tmux, shellcheck, and general utilities.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl wget unzip \
    git-lfs iproute2 \
    python3 python3-pip python3-venv \
    tmux shellcheck \
    && rm -rf /var/lib/apt/lists/*

# Neovim — latest stable release tarball with architecture detection.
RUN ARCH="$(dpkg --print-architecture)" \
    && case "$ARCH" in \
         amd64) NVIM_ARCH="x86_64" ;; \
         arm64) NVIM_ARCH="arm64"  ;; \
         *)     echo "unsupported arch: $ARCH" && exit 1 ;; \
       esac \
    && curl -fsSL -L "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.tar.gz" \
         -o /tmp/nvim.tar.gz \
    && tar xzf /tmp/nvim.tar.gz -C /opt \
    && mv /opt/nvim-linux-"${NVIM_ARCH}" /opt/nvim \
    && ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim \
    && rm /tmp/nvim.tar.gz

# bats-core — bash test framework (workflow-kit tests require >= 1.11)
ARG BATS_VERSION=1.11.1
RUN git clone --depth 1 --branch "v${BATS_VERSION}" \
      https://github.com/bats-core/bats-core.git /tmp/bats \
    && /tmp/bats/install.sh /usr/local \
    && rm -rf /tmp/bats

# mise — runtime/tool version manager
RUN curl -fsSL https://mise.jdx.dev/install.sh | sh

ENV PATH="/home/vscode/.local/bin:${PATH}"
