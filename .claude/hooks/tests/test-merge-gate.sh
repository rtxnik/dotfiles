#!/usr/bin/env bash
# Tests for merge-gate.sh — block a feature-branch merge with an empty ledger.
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(cd "$(dirname "$0")/.." && pwd)/merge-gate.sh"

repo=$(mktemp -d); ( cd "$repo" && git init -q && git checkout -q -b feature/x )
mkdir -p "$repo/.planning"
header() { printf 'timestamp\tfiles\toutcome\tgate_result\tnotes\n' > "$repo/.planning/LEDGER.tsv"; }
# rc for a Bash payload running $1 as the command, with optional env $2..
run() { local cmd="$1"; shift; local rc=0
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd" \
    | ( cd "$repo" && env "$@" bash "$HOOK" >/dev/null 2>&1 ) || rc=$?; echo "$rc"; }

# Empty ledger (header only) + no review -> block a merge.
header
ok "blocks 'gh pr merge' with empty ledger"   '[ "$(run "gh pr merge 12 --squash")" = "2" ]'
ok "blocks 'git merge feature/x' empty ledger" '[ "$(run "git merge feature/x")" = "2" ]'

# Non-merge bash command -> always allow.
ok "allows non-merge command" '[ "$(run "git status")" = "0" ]'
# Merge-control subcommands are not a merge-INTO -> allow.
ok "allows 'git merge --abort'" '[ "$(run "git merge --abort")" = "0" ]'

# Ledger has a real row -> allow the merge.
header; printf '%s\tx\tkept\tok\tn\n' "2026-06-03" >> "$repo/.planning/LEDGER.tsv"
ok "allows merge once ledger has a row" '[ "$(run "gh pr merge 12")" = "0" ]'

# Approved review verdict for THIS branch, recorded at the CURRENT HEAD -> allow (empty ledger).
header
( cd "$repo" && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m base2 )
cur=$( cd "$repo" && git rev-parse HEAD )
printf '{"branch":"feature/x","sha_range":"%s..%s","verdict":"approved","ts":"2026-06-04T00:00:00Z"}' "$cur" "$cur" \
  > "$repo/.planning/review-state.json"
ok "allows merge with fresh approved verdict" '[ "$(run "gh pr merge 12")" = "0" ]'
# Approved verdict whose recorded head != current HEAD -> STALE -> blocked (empty ledger).
( cd "$repo" && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m newer )
ok "blocks on stale approved verdict (head moved)" '[ "$(run "gh pr merge 12")" = "2" ]'
out=$( printf '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 12"}}' \
  | ( cd "$repo" && bash "$HOOK" 2>&1 ) || true )
ok "stale block names the freshness reason" '[[ "$out" == *"Stale review"* ]]'
# Re-recording at the new HEAD clears it.
( cd "$repo" && source "$(dirname "$HOOK")/lib/hooklib.sh" && record_review_verdict approved >/dev/null 2>&1 )
ok "re-recorded fresh verdict allows again" '[ "$(run "gh pr merge 12")" = "0" ]'
rm -f "$repo/.planning/review-state.json"
# Verdict keyed to ANOTHER branch, or non-approved -> still blocked.
header
printf '{"branch":"feature/other","sha_range":"a..b","verdict":"approved","ts":"2026-06-04T00:00:00Z"}' \
  > "$repo/.planning/review-state.json"
ok "blocks when verdict is for another branch" '[ "$(run "gh pr merge 12")" = "2" ]'
printf '{"branch":"feature/x","sha_range":"a..b","verdict":"changes-requested","ts":"2026-06-04T00:00:00Z"}' \
  > "$repo/.planning/review-state.json"
ok "blocks on changes-requested verdict"       '[ "$(run "gh pr merge 12")" = "2" ]'
# End-to-end: the recorder's output is accepted by the gate.
rm -f "$repo/.planning/review-state.json"
( cd "$repo" && source "$(dirname "$HOOK")/lib/hooklib.sh" && record_review_verdict approved >/dev/null 2>&1 )
ok "recorder output accepted by gate"          '[ "$(run "gh pr merge 12")" = "0" ]'
rm -f "$repo/.planning/review-state.json"

# Escape hatch: standard one-shot disable.
header
ok "escape: WORKFLOW_DISABLED_HOOKS=merge-gate allows" '[ "$(run "gh pr merge 12" WORKFLOW_DISABLED_HOOKS=merge-gate)" = "0" ]'

# Fail-open on malformed input.
rc=0; echo "" | bash "$HOOK" >/dev/null 2>&1 || rc=$?
ok "fail-open empty input" '[ "$rc" = "0" ]'

# F2: a block must leave an audit line.
header
alog="$(mktemp -d)/audit.jsonl"
blocking_payload=$(printf '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 12 --squash"}}')
printf '%s' "$blocking_payload" | ( cd "$repo" && WORKFLOW_AUDIT_PATH="$alog" bash "$HOOK" >/dev/null 2>&1 )
if [ -s "$alog" ] && tail -n1 "$alog" | jq -e '.result=="block"' >/dev/null 2>&1; then
  echo "PASS: block audited"; pass=$((pass+1))
else
  echo "FAIL: no audit line on block"; fail=$((fail+1))
fi

# --- F4 / D4-3: branch-scoped floor — ancient main rows do not unlock a feature merge ---
bs=$(mktemp -d)
( cd "$bs" && git init -q -b main && git config user.email t@t && git config user.name t
  mkdir -p .planning
  printf 'timestamp\tfiles\toutcome\tgate_result\tnotes\n2026-05-01\ta\tkept\tok\tancient\n' > .planning/LEDGER.tsv
  git add -A && git commit -q -m seed && git update-ref refs/remotes/origin/main HEAD
  git checkout -q -b feature/scoped && git commit -q --allow-empty -m work )
bsrun() { local rc=0; printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" \
  | ( cd "$bs" && bash "$HOOK" >/dev/null 2>&1 ) || rc=$?; echo "$rc"; }
ok "branch-scope blocks: only ancient main rows, none on this branch" '[ "$(bsrun "gh pr merge 1")" = "2" ]'
( cd "$bs" && printf '2026-06-16T09:00:00Z\tb\tkept\tok\tbranch work\n' >> .planning/LEDGER.tsv \
  && git add -A && git commit -q -m "log work" )
ok "branch-scope allows once THIS branch logs a row" '[ "$(bsrun "gh pr merge 1")" = "0" ]'
rm -rf "$bs"

rm -rf "$repo"
t_summary
