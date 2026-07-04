#!/usr/bin/env bash
# Unit tests for dependabot-regen.sh pure functions (no make, no git).
# shellcheck disable=SC2015
set -uo pipefail
# shellcheck source=../../lib/testlib.sh
source "$(cd "$(dirname "$0")/../../lib" && pwd)/testlib.sh"
t_init
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../dependabot-regen.sh
source "$HERE/../dependabot-regen.sh"

# --- apply_pin_to_generator: bumps the matching pin line, leaves others ---
tmp="$(mktemp)"; cp "$HERE/fixtures/compose-pin-sample.py" "$tmp"
apply_pin_to_generator "actions/checkout" "1111111111111111111111111111111111111111" "v7.0.0" "$tmp"
grep -q 'actions/checkout@1111111111111111111111111111111111111111  # v7.0.0' "$tmp" \
  && pass "checkout pin bumped" || fail "checkout pin not bumped"
grep -q 'actions/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e  # v6.4.0' "$tmp" \
  && pass "setup-node pin untouched" || fail "setup-node pin changed unexpectedly"
rm -f "$tmp"

# --- build_ledger_row: 5 TAB columns, outcome kept, ASCII only ---
row="$(LEDGER_TS=2026-06-30T00:00:00Z build_ledger_row "factory.lock" "chore(deps): bump svelte from 5.56.3 to 5.56.4")"
ncol="$(awk -F'\t' '{print NF}' <<<"$row")"
[ "$ncol" = "5" ] && pass "row has 5 columns" || fail "row has $ncol columns (want 5)"
[ "$(cut -f3 <<<"$row")" = "kept" ] && pass "outcome=kept" || fail "outcome not kept"
LC_ALL=C grep -qP '[^\x00-\x7F]' <<<"$row" && fail "row has non-ASCII" || pass "row is ASCII"

# --- restore_if_graph_stamp_only: stamp-only drift is reverted, content drift is kept ---
_regen_test_repo="$(mktemp -d)"
trap 'rm -rf "$_regen_test_repo"' EXIT
git -C "$_regen_test_repo" init -q
git -C "$_regen_test_repo" config user.email "test@example.com"
git -C "$_regen_test_repo" config user.name "Test"
mkdir -p "$_regen_test_repo/graphify-out"
cat >"$_regen_test_repo/graphify-out/graph.json" <<'ENDJSON'
{
  "content": "original-value",
  "built_at_commit": "abc1234"
}
ENDJSON
git -C "$_regen_test_repo" add graphify-out/graph.json
git -C "$_regen_test_repo" commit -q -m "initial"

# stamp-only drift: change only the built_at_commit value
sed 's/"built_at_commit": "abc1234"/"built_at_commit": "def5678"/' \
  "$_regen_test_repo/graphify-out/graph.json" > "$_regen_test_repo/graphify-out/graph.json.tmp"
mv "$_regen_test_repo/graphify-out/graph.json.tmp" "$_regen_test_repo/graphify-out/graph.json"
restore_if_graph_stamp_only "$_regen_test_repo"
committed_content="$(git -C "$_regen_test_repo" show HEAD:graphify-out/graph.json)"
current_content="$(cat "$_regen_test_repo/graphify-out/graph.json")"
[ "$committed_content" = "$current_content" ] \
  && pass "stamp-only drift restored to committed state" \
  || fail "stamp-only drift NOT restored (file still modified)"

# content drift: change a non-stamp line
sed 's/"content": "original-value"/"content": "changed-value"/' \
  "$_regen_test_repo/graphify-out/graph.json" > "$_regen_test_repo/graphify-out/graph.json.tmp"
mv "$_regen_test_repo/graphify-out/graph.json.tmp" "$_regen_test_repo/graphify-out/graph.json"
restore_if_graph_stamp_only "$_regen_test_repo"
grep -q '"content": "changed-value"' "$_regen_test_repo/graphify-out/graph.json" \
  && pass "content drift preserved (not restored)" \
  || fail "content drift was erroneously restored"

# --- reconcile_action_pins: sync a bumped action pin from the rendered workflow into the generator ---
# The reconcile reads .github/workflows/fabric-gates.yml directly (no base ref) and rewrites the
# matching pin in tooling/factory/compose.py so `make compose` renders the bumped SHA, not the stale one.
_rc_dir="$(mktemp -d)"
mkdir -p "$_rc_dir/.github/workflows" "$_rc_dir/tooling/factory"
printf '      - uses: actions/checkout@1111111111111111111111111111111111111111  # v7.0.0\n' \
  > "$_rc_dir/.github/workflows/fabric-gates.yml"
printf '      - uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10  # v6.0.3\n' \
  > "$_rc_dir/tooling/factory/compose.py"
( cd "$_rc_dir" && reconcile_action_pins )
grep -q 'actions/checkout@1111111111111111111111111111111111111111  # v7.0.0' "$_rc_dir/tooling/factory/compose.py" \
  && pass "reconcile synced bumped pin into generator" \
  || fail "reconcile did not sync the bumped pin"

# no-op when the generator already matches the rendered workflow
_rc_before="$(cat "$_rc_dir/tooling/factory/compose.py")"
( cd "$_rc_dir" && reconcile_action_pins )
[ "$(cat "$_rc_dir/tooling/factory/compose.py")" = "$_rc_before" ] \
  && pass "reconcile is a no-op when generator already matches" \
  || fail "reconcile changed an already-matching generator"

rm -rf "$_rc_dir"

# --- wf#20 consumer-context guard: no tooling/factory/compose.py -> honest no-op, exit 0 ---
_cons_dir="$(mktemp -d)"
git -C "$_cons_dir" init -q
git -C "$_cons_dir" config user.email t@t.local
git -C "$_cons_dir" config user.name t
mkdir -p "$_cons_dir/.github/workflows"
printf 'name: fabric-gates\n' > "$_cons_dir/.github/workflows/fabric-gates.yml"
git -C "$_cons_dir" add -A && git -C "$_cons_dir" commit -qm seed
OUT="$( cd "$_cons_dir" && bash "$HERE/../dependabot-regen.sh" 2>&1 )"; rc=$?
[ "$rc" = "0" ] && pass "consumer no-op exits 0" || fail "consumer no-op rc=$rc (want 0): $OUT"
grep -q 'self-host regen not applicable' <<<"$OUT" \
  && pass "consumer no-op says why" || fail "consumer no-op message missing: $OUT"
[ -z "$(git -C "$_cons_dir" status --porcelain)" ] \
  && pass "consumer tree untouched" || fail "consumer no-op modified the tree"
rm -rf "$_cons_dir"

# --- wf#20 self-host context proceeds past the guard (no false trigger) ---
_sh_dir="$(mktemp -d)"
git -C "$_sh_dir" init -q
git -C "$_sh_dir" config user.email t@t.local
git -C "$_sh_dir" config user.name t
mkdir -p "$_sh_dir/tooling/factory" "$_sh_dir/.github/workflows"
printf '# generator stub\n' > "$_sh_dir/tooling/factory/compose.py"
printf 'name: fabric-gates\n' > "$_sh_dir/.github/workflows/fabric-gates.yml"
git -C "$_sh_dir" add -A && git -C "$_sh_dir" commit -qm seed
OUT="$( cd "$_sh_dir" && bash "$HERE/../dependabot-regen.sh" 2>&1 )" || true
grep -q 'self-host regen not applicable' <<<"$OUT" \
  && fail "guard over-triggered in self-host context: $OUT" \
  || pass "guard not triggered when compose.py present"
rm -rf "$_sh_dir"

t_summary
