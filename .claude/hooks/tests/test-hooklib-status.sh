#!/usr/bin/env bash
# test-hooklib-status.sh — bash hooklib.sh status output + HOOK_IDS<->settings drift
# NOTE the 4 verifier-fixed pitfalls baked in below: isolated TMPDIR (no host /tmp/wf-ctx
# pollution), sandbox branch == review branch (so fresh is reachable + the SHA path is exercised),
# verdict-THEN-id grep order (status prints "<verdict>  <id>"), and a SET-diff drift gate.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); LIB="$HERE/../lib/hooklib.sh"
ROOT=$(cd "$HERE/../../.." && pwd)
TMPDIR=$(mktemp -d); export TMPDIR                          # isolate skip-marker checks from the host session
fail=0; ok(){ echo "ok - $1"; }; bad(){ echo "NOT ok - $1"; fail=1; }

# --- drift: HOOK_IDS == settings.json-registered .sh hook ids (SET equality, not just count) ---
# Both sides now derive from settings.json (the ownership oracle), so this regression-locks
# the settings-extraction round-trip rather than guarding a hand-maintained roster; file-vs-
# settings drift (a hook .sh with no settings.json entry, or vice versa) is guarded separately
# by scripts/check-integration-hooks.sh.
got=$(bash "$LIB" hook_ids | sort -u)
want=$( jq -r '.hooks|to_entries[].value[].hooks[].command' "$ROOT/.claude/settings.json" 2>/dev/null \
  | grep -oE '[a-z0-9-]+\.sh' | sed 's/\.sh$//' | grep -vx 'check-symlinks' | sort -u )
if [ "$got" = "$want" ]; then ok "HOOK_IDS == settings.json hook ids"; else bad "HOOK_IDS drift:"; diff <(printf '%s\n' "$got") <(printf '%s\n' "$want"); fi

# --- status output in a seeded sandbox; branch ALIGNED to the review branch ---
SB=$(mktemp -d); ( cd "$SB" && git init -q && git checkout -q -b feature/x && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )
mkdir -p "$SB/.planning"
printf '{"phase":"executing","branch":"feature/x","started_at":"2026-06-16T10:00:00Z"}' > "$SB/.planning/workflow-state.json"
H=$(cd "$SB" && git rev-parse HEAD)
printf '{"branch":"feature/x","sha_range":"aaa..%s","verdict":"approved","ts":"t"}' "$H" > "$SB/.planning/review-state.json"
printf 'timestamp\tfiles\toutcome\tgate_result\tnotes\n2026\tf\tkept\tg\tn\n' > "$SB/.planning/LEDGER.tsv"
out=$(cd "$SB" && bash "$LIB" status 2>&1)
if echo "$out" | grep -q "executing"; then ok "phase shown"; else bad "phase missing"; fi
if echo "$out" | grep -qi "kept=1"; then ok "ledger stats shown"; else bad "ledger stats missing"; fi
if echo "$out" | grep -qi "approved"; then ok "verdict shown"; else bad "verdict missing"; fi
if echo "$out" | grep -qi "fresh"; then ok "review fresh (head==HEAD, branch aligned)"; else bad "fresh flag missing"; fi
# STALE only via the SHA advance (branch stays feature/x) — genuinely exercises the sha_range head-split
(cd "$SB" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m next)
out2=$(cd "$SB" && bash "$LIB" status 2>&1)
if echo "$out2" | grep -qi "stale"; then ok "review STALE after new commit (sha head advanced)"; else bad "stale not flagged"; fi
# per-hook verdicts + unknown id — status prints "<verdict>  <id>"
out3=$(cd "$SB" && WORKFLOW_DISABLED_HOOKS=doc-path-warn,bogus-xyz bash "$LIB" status 2>&1)
if echo "$out3" | grep -Eq "disabled +doc-path-warn"; then ok "disabled id shown"; else bad "disabled verdict missing"; fi
if echo "$out3" | grep -q "bogus-xyz"; then ok "unknown id surfaced"; else bad "unknown id missing"; fi
if echo "$out3" | grep -Eq "enabled +secrets-scan"; then ok "pinned stays enabled"; else bad "pinned verdict wrong"; fi
# no skip-debounce side effects from the verdict loop (TMPDIR is fresh)
if [ ! -e "$TMPDIR/wf-ctx/skip-logged-doc-path-warn" ]; then ok "no skip markers from status"; else bad "status polluted skip markers"; fi
rm -rf "$SB" "$TMPDIR"
if [ "$fail" = 0 ]; then echo "PASS test-hooklib-status"; else echo "FAIL test-hooklib-status"; exit 1; fi
