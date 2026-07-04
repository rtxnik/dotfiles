#!/usr/bin/env bash
# Test runner for check-ledger-gate.sh: push mode only validates schema; PR mode
# (BASE_REF set) additionally requires a new LEDGER row when the PR diff touches
# enforced fabric paths; invalid LEDGER always fails.
set -uo pipefail
# shellcheck source=../../lib/testlib.sh
source "$(cd "$(dirname "$0")/../../lib" && pwd)/testlib.sh"
t_init
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/../check-ledger-gate.sh"
HOOKLIB="$HERE/../../../.claude/hooks/lib/hooklib.sh"

# Sandbox repo: hooklib + valid LEDGER + one base commit, origin/main pinned to it.
mkrepo() {
  local d; d="$(mktemp -d)"
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t.local
  git -C "$d" config user.name t
  mkdir -p "$d/scripts/ci" "$d/.claude/hooks/lib" "$d/.planning" "$d/docs"
  cp "$SRC" "$d/scripts/ci/"
  cp "$HOOKLIB" "$d/.claude/hooks/lib/hooklib.sh"
  printf 'timestamp\tfiles\toutcome\tgate_result\tnotes\n' > "$d/.planning/LEDGER.tsv"
  printf '2026-06-11T00:00:00Z\tseed\tkept\tpass\tseed row\n' >> "$d/.planning/LEDGER.tsv"
  echo base > "$d/docs/readme.md"
  git -C "$d" add -A
  git -C "$d" commit -qm base
  git -C "$d" update-ref refs/remotes/origin/main HEAD
  echo "$d"
}

# 1. push mode (no BASE_REF): schema check only -> exit 0
w="$(mkrepo)"
OUT="$(cd "$w" && BASE_REF='' bash scripts/ci/check-ledger-gate.sh 2>&1)"; assert_rc "push mode passes" 0 $?
assert_out_has "push-mode skip notice" "$OUT" 'row check skipped'

# 2. PR touches enforced path without a new LEDGER row -> exit 1
w="$(mkrepo)"
echo x > "$w/.claude/hooks/dummy.sh"
git -C "$w" add -A && git -C "$w" commit -qm "touch fabric"
OUT="$(cd "$w" && BASE_REF=main bash scripts/ci/check-ledger-gate.sh 2>&1)"; assert_rc "enforced-no-row fails" 1 $?
assert_out_has "no-row message" "$OUT" 'adds no LEDGER row'

# 3. same + a LEDGER row added -> exit 0
printf '2026-06-11T00:01:00Z\t.claude/hooks/dummy.sh\tkept\tpass\ttest row\n' >> "$w/.planning/LEDGER.tsv"
git -C "$w" add -A && git -C "$w" commit -qm "ledger row"
OUT="$(cd "$w" && BASE_REF=main bash scripts/ci/check-ledger-gate.sh 2>&1)"; assert_rc "enforced-with-row passes" 0 $?

# 4. PR touches only docs/ -> row check skipped, exit 0
w="$(mkrepo)"
echo y >> "$w/docs/readme.md"
git -C "$w" add -A && git -C "$w" commit -qm "docs only"
OUT="$(cd "$w" && BASE_REF=main bash scripts/ci/check-ledger-gate.sh 2>&1)"; assert_rc "docs-only passes" 0 $?
assert_out_has "docs-only skip notice" "$OUT" 'does not touch enforced'

# 5. invalid LEDGER (bad outcome) -> exit 1 even in push mode
w="$(mkrepo)"
printf '2026-06-11T00:02:00Z\tx\twat\tpass\tbad outcome\n' >> "$w/.planning/LEDGER.tsv"
OUT="$(cd "$w" && BASE_REF='' bash scripts/ci/check-ledger-gate.sh 2>&1)"; assert_rc "invalid ledger fails" 1 $?
assert_out_has "invalid-ledger message" "$OUT" 'LEDGER\.tsv invalid'

# 6. PR touches enforced path and only MODIFIES an existing row (no net new row) -> exit 1
w="$(mkrepo)"
echo x > "$w/.claude/hooks/dummy.sh"
sed -i 's/seed row/edited seed row/' "$w/.planning/LEDGER.tsv"
git -C "$w" add -A && git -C "$w" commit -qm "modify row only"
OUT="$(cd "$w" && BASE_REF=main bash scripts/ci/check-ledger-gate.sh 2>&1)"; assert_rc "modified-row-only fails" 1 $?
assert_out_has "no-row message (case 6)" "$OUT" 'adds no LEDGER row'

# 7. external mode (wf#22/ADR-018): passes with NO ledger file at all
w="$(mkrepo)"
rm "$w/.planning/LEDGER.tsv"
OUT="$(cd "$w" && LEDGER_GATE_MODE=external BASE_REF=main bash scripts/ci/check-ledger-gate.sh 2>&1)"; assert_rc "external mode passes without ledger" 0 $?
assert_out_has "external policy line" "$OUT" 'LEDGER gate externalized'

# 8. external mode: passes even with an invalid ledger
w="$(mkrepo)"
printf '2026-06-11T00:02:00Z\tx\twat\tpass\tbad outcome\n' >> "$w/.planning/LEDGER.tsv"
OUT="$(cd "$w" && LEDGER_GATE_MODE=external bash scripts/ci/check-ledger-gate.sh 2>&1)"; assert_rc "external mode ignores invalid ledger" 0 $?

# 9. explicit local mode behaves exactly like the default (invalid ledger fails)
w="$(mkrepo)"
printf '2026-06-11T00:02:00Z\tx\twat\tpass\tbad outcome\n' >> "$w/.planning/LEDGER.tsv"
OUT="$(cd "$w" && LEDGER_GATE_MODE=local BASE_REF='' bash scripts/ci/check-ledger-gate.sh 2>&1)"; assert_rc "local mode still validates" 1 $?

t_summary
