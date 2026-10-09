#!/bin/bash
# The cloud environment's "Setup script" field holds this file, verbatim. It
# fetches the public dotfiles repository and runs the bootstrap in it, so the
# environment never needs editing when the bootstrap changes.
#
# The environment caches the result for about seven days, and rebuilds sooner
# only when this text changes: to roll a new bootstrap out at once, change REF
# (a branch or tag) or the revision note below.
# revision: 1

REF=main
dir=/opt/dotfiles

rm -rf "$dir"
git clone -q --depth 1 --branch "$REF" https://github.com/rtxnik/dotfiles.git "$dir" ||
  { mkdir -p "$dir" &&
    curl -fsSL "https://codeload.github.com/rtxnik/dotfiles/tar.gz/$REF" | tar -xz -C "$dir" --strip-components=1; }
bash "$dir/dot_config/workspaces/cloud/setup.sh" || true
exit 0
