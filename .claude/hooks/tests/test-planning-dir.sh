#!/usr/bin/env bash
# Tests for hooklib planning_dir() deterministic resolution.
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
LIB="$(cd "$(dirname "$0")/.." && pwd)/lib/hooklib.sh"

# (a) Inside a git repo -> <repo-root>/.planning, regardless of CWD depth.
repo=$(mktemp -d); ( cd "$repo" && git init -q )
mkdir -p "$repo/sub/deep"
got=$(cd "$repo/sub/deep" && bash "$LIB" planning_dir)
ok "git repo resolves to repo-root/.planning" '[ "$got" = "$repo/.planning" ]'

# (b) Not a repo, but a parent has an existing .planning -> that one (walk-up).
nrepo=$(mktemp -d); mkdir -p "$nrepo/.planning" "$nrepo/a/b"
got=$(cd "$nrepo/a/b" && bash "$LIB" planning_dir)
ok "non-repo walk-up finds existing .planning" '[ "$got" = "$nrepo/.planning" ]'

# (c) Not a repo, no .planning anywhere up to / -> refuse (non-zero, empty stdout).
bare=$(mktemp -d)
out=$(cd "$bare" && bash "$LIB" planning_dir); rc=$?
ok "non-repo with no .planning refuses (rc!=0)" '[ "$rc" -ne 0 ]'
ok "non-repo with no .planning emits nothing"  '[ -z "$out" ]'

rm -rf "$repo" "$nrepo" "$bare"
t_summary
