#!/usr/bin/env bash
# Tests for bounded-surface-guard.sh (warn-only, stateful, reset-on-commit)
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(cd "$(dirname "$0")/.." && pwd)/bounded-surface-guard.sh"

repo=$(mktemp -d)
( cd "$repo" && git init -q && git checkout -q -b feature/s \
  && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )
sess="testsess-$$"
setf="${TMPDIR:-/tmp}/wf-surface-${sess}_feature_s.list"
trap 'rm -rf "$repo"; rm -f "$setf"' EXIT
rm -f "$setf"

# stdout for a Write to $1 (empty => no warn), optional env in $2..; run inside the repo.
emit() { # filepath [ENV=val...]
  local fp="$1"; shift
  printf '{"session_id":"%s","tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$sess" "$fp" \
    | ( cd "$repo" && env "$@" bash "$HOOK" 2>/dev/null )
}

ok "file1 no warn" '[ -z "$(emit f1)" ]'
ok "file2 no warn" '[ -z "$(emit f2)" ]'
ok "file3 no warn" '[ -z "$(emit f3)" ]'
ok "file4 no warn" '[ -z "$(emit f4)" ]'
ok "file5 warns (>4)" '[ -n "$(emit f5)" ]'
ok "warn is additionalContext" 'emit f6 | jq -e .hookSpecificOutput.additionalContext >/dev/null'
ok "re-edit f1 no re-warn (already counted)" '[ -z "$(emit f1)" ]'

# Commit -> HEAD changes -> set resets -> back under threshold.
( cd "$repo" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m next )
ok "after commit, f1 no warn (reset)" '[ -z "$(emit f1)" ]'

# Disabled -> silent even past threshold.
rm -f "$setf"
for f in f1 f2 f3 f4 f5; do emit "$f" WORKFLOW_DISABLED_HOOKS=bounded-surface-guard >/dev/null 2>&1; done
ok "disabled -> silent at f6" '[ -z "$(emit f6 WORKFLOW_DISABLED_HOOKS=bounded-surface-guard)" ]'

# Commit-less repo: git rev-parse HEAD fails -> "NOHEAD" sentinel must be stable so the
# guard still accumulates and warns (regression for the multi-line-HEAD reset bug).
norepo=$(mktemp -d)
( cd "$norepo" && git init -q && git symbolic-ref HEAD refs/heads/feature/nc )
nsess="ncsess-$$"
nsetf="${TMPDIR:-/tmp}/wf-surface-${nsess}_feature_nc.list"
rm -f "$nsetf"
nemit() { local fp="$1"; shift; printf '{"session_id":"%s","tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$nsess" "$fp" | ( cd "$norepo" && env "$@" bash "$HOOK" 2>/dev/null ); }
nemit g1 >/dev/null; nemit g2 >/dev/null; nemit g3 >/dev/null; nemit g4 >/dev/null
ok "commit-less repo: g5 warns (NOHEAD sentinel stable)" '[ -n "$(nemit g5)" ]'
rm -rf "$norepo"; rm -f "$nsetf"

# D15 allowlist (I7): doc/planning/audit artifacts never count toward the CODE surface. Each arm
# edits a distinct allowlisted path 10x (5 distinct paths + re-edits) — well past the <=4 rule —
# and must stay silent: pre-I7 (no allowlist) these counted as CODE and warned by the 5th distinct
# file. docs/*+*.md (spec), PATHFINDER-*/*+*.md, and bare *.md each exercise a distinct case arm.
rm -f "$setf"
ok_allow() { # label dir
  rm -f "$setf"
  local out
  for i in 1 2 3 4 5 6 7 8 9 10; do out=$(emit "${2}${i}.md"); done
  if [ -z "$out" ]; then pass "$1"; else fail "$1"; fi
}
ok_allow "allowlist: docs/superpowers/specs/*.md never warns" "docs/superpowers/specs/x"
ok_allow "allowlist: PATHFINDER-2026-06-10/*.md never warns" "PATHFINDER-2026-06-10/y"
ok_allow "allowlist: bare *.md never warns" "foo"

# WORKFLOW_SURFACE_MAX clamp (I7 cfg_int): garbage and out-of-range (>100) both fall back to
# the default of 4, so the warn still fires only at the 5th distinct CODE file. Fresh set each.
clamp_warns_at_5th() { # label ENV=val
  rm -f "$setf"
  emit c1 "$2" >/dev/null; emit c2 "$2" >/dev/null
  emit c3 "$2" >/dev/null; emit c4 "$2" >/dev/null
  local fourth fifth
  fourth=$(emit c4 "$2")   # re-edit of an already-counted file: still under threshold, silent
  fifth=$(emit c5 "$2")    # 5th DISTINCT code file: over default 4 -> warn
  if [ -z "$fourth" ] && [ -n "$fifth" ]; then
    pass "$1"
  else
    fail "$1"
  fi
}
clamp_warns_at_5th "SURFACE_MAX=garbage clamps to default 4 (warn at 5th)" "WORKFLOW_SURFACE_MAX=garbage"
clamp_warns_at_5th "SURFACE_MAX=99999 clamps to default 4 (warn at 5th)" "WORKFLOW_SURFACE_MAX=99999"

# safe_slug sanity (I7): after the inline tr -c -> safe_slug switch the set-file path the hook
# computes must still equal the hard-coded $setf at the top of this file (byte-identical slug).
source "$(cd "$(dirname "$0")/.." && pwd)/lib/hooklib.sh"
hook_slug="${TMPDIR:-/tmp}/wf-surface-$(safe_slug "$sess|feature/s").list"
ok "safe_slug path matches hard-coded \$setf" '[ "$hook_slug" = "$setf" ]'

# F2: a warn must leave an audit line.
rm -f "$setf"
alog="$(mktemp -d)/audit.jsonl"
for f in a1 a2 a3 a4 a5; do
  printf '{"session_id":"%s","tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$sess" "$f" \
    | ( cd "$repo" && WORKFLOW_AUDIT_PATH="$alog" bash "$HOOK" 2>/dev/null ) || true
done
if [ -s "$alog" ] && tail -n1 "$alog" | jq -e '.result=="warn"' >/dev/null 2>&1; then
  echo "PASS: warn audited"; pass=$((pass+1))
else
  echo "FAIL: no audit line on warn"; fail=$((fail+1))
fi

t_summary
