#!/usr/bin/env bash
# PreToolUse(Bash) hook: the fabric's single enforcement floor. Blocks merging a feature
# branch when the work was never recorded (LEDGER.tsv has only its header) AND no review
# verdict exists for the branch. Triggers on `gh pr merge` and `git merge <ref>` (NOT the
# --abort/--continue/--quit control subcommands).
# Exit 0 = allow. Exit 2 = block. Fail-CLOSED only within this narrow case; fail-OPEN on
# everything else. Escape for a trivial merge: export WORKFLOW_DISABLED_HOOKS=merge-gate in the launching env (settings.json `env`).
# Scope (F3 / D1-4, accepted): web-UI merges and `git pull`-driven merges never
# produce a local hook event — that boundary is enforced SERVER-SIDE by the F1
# branch-protection floor (required checks + strict + enforce_admins), not here.
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
hook_enabled "merge-gate" || exit 0
hook_read_input
[ "$TOOL_NAME" != "Bash" ] && exit 0

command=$(hook_command)
[ -z "$command" ] && exit 0

is_merge=0
echo "$command" | grep -qE 'gh[[:space:]]+pr[[:space:]]+merge' && is_merge=1
if echo "$command" | grep -qE 'git[[:space:]]+merge[[:space:]]'; then
  echo "$command" | grep -qE 'git[[:space:]]+merge[[:space:]]+(--abort|--continue|--quit)' || is_merge=1
fi
[ "$is_merge" -eq 1 ] || exit 0

# Review verdict for the current branch, recorded at the CURRENT head? (D4-3: a stale approval —
# recorded head != HEAD — no longer satisfies the gate. Prefix-tolerant: record_review_verdict
# stores whatever git produced, and live review-state uses SHORT shas.)
branch=$(git branch --show-current 2>/dev/null || echo "")
review_ok=0
review_stale=0
pdir=$(planning_dir 2>/dev/null) || pdir=""
if [ -n "$branch" ] && [ -n "$pdir" ] && [ -f "${pdir}/review-state.json" ]; then
  rb=$(jq -r '.branch // empty'    "${pdir}/review-state.json" 2>/dev/null)
  rv=$(jq -r '.verdict // empty'   "${pdir}/review-state.json" 2>/dev/null)
  rr=$(jq -r '.sha_range // empty' "${pdir}/review-state.json" 2>/dev/null)
  rhead="${rr##*..}"
  cur=$(git rev-parse HEAD 2>/dev/null || echo "")
  if [ "$rb" = "$branch" ] && [ "$rv" = "approved" ]; then
    # Fresh iff the recorded head matches current HEAD (either direction's prefix).
    if [ -n "$rhead" ] && { [ "$rhead" = "$cur" ] || [ "${cur#"$rhead"}" != "$cur" ] \
         || [ "${rhead#"$(git rev-parse --short HEAD 2>/dev/null)"}" != "$rhead" ]; }; then
      review_ok=1
    else
      review_stale=1
    fi
  fi
fi

# LEDGER floor (D4-3): branch-scoped to THIS branch's work since fork (rows net-added vs the
# merge-base with origin/main). ledger_rows --since-ref degrades to the cumulative count when
# the ref is empty/unresolvable/==HEAD (unusual topology / on main), so a legitimate merge is
# never spuriously blocked — the F1 server-side branch-protection floor is the real boundary.
ref=$(git merge-base HEAD origin/main 2>/dev/null) || ref=""
[ -n "$ref" ] || ref=$(git merge-base HEAD origin/master 2>/dev/null) || ref=""
rows=$(ledger_rows --since-ref "$ref")

if [ "$review_ok" -eq 1 ] || [ "${rows:-0}" -gt 0 ]; then
  exit 0
fi

if [ "$review_stale" -eq 1 ]; then
  echo "[BLOCKED] Stale review: the approved verdict for '${branch:-?}' was recorded at ${rhead:-?} but HEAD is now $(git rev-parse --short HEAD 2>/dev/null)."
  echo "  New commits landed after the review — re-review and re-record (bash .claude/hooks/lib/hooklib.sh record_review_verdict approved <base> <HEAD>),"
  echo "  or log this branch's work in .planning/LEDGER.tsv, then re-run the merge."
  echo "  Override: export WORKFLOW_DISABLED_HOOKS=merge-gate in the launching env (settings.json env)"
  audit_emit_block merge-gate review_stale
  exit 2
fi

echo "[BLOCKED] Merging a feature branch with no recorded work."
echo "  .planning/LEDGER.tsv has no rows logged for '${branch:-?}' since it forked, and no approved review verdict was recorded."
echo "  Log the change in LEDGER.tsv (or complete a review), then re-run the merge."
echo "  Genuinely trivial? Override: export WORKFLOW_DISABLED_HOOKS=merge-gate in the launching env (settings.json env)"
audit_emit_block merge-gate contract_unmet
exit 2
