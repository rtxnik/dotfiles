#!/usr/bin/env bash
# shellcheck disable=SC2119  # mk_git_sandbox optional [branch] arg intentionally omitted
set -uo pipefail
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DIR/scripts/lib/testlib.sh"
SRC="$DIR/scripts/check-integration-merge-markers.sh"
t_init

# Clean sandbox: no markers -> pass.
d="$(mk_git_sandbox)"; printf 'hello\nworld\n' > "$d/a.txt"; git -C "$d" add -A >/dev/null
out="$(CHECK_ROOT="$d" bash "$SRC" 2>&1)"; rc=$?
assert_rc "clean tree passes" 0 "$rc"

# Planted conflict marker -> fail.
d2="$(mk_git_sandbox)"; printf 'a\n<<<<<<< HEAD\nb\n=======\nc\n>>>>>>> x\n' > "$d2/m.txt"
git -C "$d2" add -A >/dev/null
out="$(CHECK_ROOT="$d2" bash "$SRC" 2>&1)"; rc=$?
assert_rc "conflict marker fails" 1 "$rc"
assert_out_has "names the file" "$out" "m.txt"

# Planted .rej -> fail.
d3="$(mk_git_sandbox)"; printf 'patch reject\n' > "$d3/p.c.rej"; git -C "$d3" add -A >/dev/null
out="$(CHECK_ROOT="$d3" bash "$SRC" 2>&1)"; rc=$?
assert_rc ".rej file fails" 1 "$rc"

t_summary
