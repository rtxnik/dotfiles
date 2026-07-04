#!/usr/bin/env bash
# dependabot-regen.sh - regenerate workflow-factory self-host artifacts for a dependabot
# PR so the freshness/LEDGER gates pass. Run by the CI producer job AND runnable locally.
# Idempotent on a clean tree. Sourcing this file defines the functions without running main.
set -euo pipefail

# Update the single `- uses: <action>@<40hex>  # <ver>` pin line for <action> in <genfile>.
apply_pin_to_generator() {
  local action="$1" sha="$2" ver="$3" gen="$4"
  # `|` delimiter (actions contain `/`, never `|`); literal `@` is matched, not a delimiter.
  sed -i -E "s|(- uses: ${action}@)[0-9a-f]{40}(  # ).*|\1${sha}\2${ver}|" "$gen"
}

# Emit one schema-valid LEDGER row. ASCII only; ts overridable for tests.
build_ledger_row() {
  local files="$1" bump="$2" ts notes
  ts="${LEDGER_TS:-$(date -u +%FT%TZ)}"
  notes="dependabot auto-regen: ${bump}; self-host vendored-dep bump makes the artifact stale and dependabot cannot regenerate it"
  printf '%s\t%s\t%s\t%s\t%s' \
    "$ts" "$files" "kept" "auto-regen (fabric-gates re-run on commit-back)" "$notes"
}

# Restore graphify-out/ when `make workflow-graph` only bumped the per-commit stamps
# (built_at_commit / report date + "Built from commit"). A non-graph bump otherwise churns
# stamps forever -> endless autoregen commit loop. Stamp patterns MIRROR
# scripts/ci/check-graph-freshness.sh (single source of truth for the ignore set).
# shellcheck disable=SC2016  # backticks in pattern B are literal markdown, not a command substitution
restore_if_graph_stamp_only() {
  local root="${1:-.}"
  local IGNORE=(
    -I'^[[:space:]]*"built_at_commit": "[0-9a-f]+"$'
    -I'^- Built from commit: `[0-9a-f]+`$'
    -I'^# Graph Report - .*\([0-9]{4}-[0-9]{2}-[0-9]{2}\)$'
  )
  if git -C "$root" diff "${IGNORE[@]}" --exit-code -- graphify-out/ >/dev/null; then
    git -C "$root" restore -- graphify-out/
  fi
}

# Sync every action pin from the (dependabot-edited) rendered fabric-gates.yml into the
# generator compose.py, so `make compose` renders the bumped SHA instead of reverting it to
# the generator's stale pin. Reads the committed rendered file directly — no base ref, no
# network auth, and no silent-revert failure mode: the rendered file always carries the pins
# `make compose` must reproduce. Non-actions bumps leave fabric-gates.yml == generator, so the
# per-action sed is a no-op. The local `./…/setup-yq` (no @sha) is skipped by the regex.
reconcile_action_pins() {
  local wf=".github/workflows/fabric-gates.yml" gen="tooling/factory/compose.py" line
  while IFS= read -r line; do
    if [[ "$line" =~ -\ uses:\ ([^@]+)@([0-9a-f]{40})[[:space:]]+#[[:space:]]+(.+)$ ]]; then
      apply_pin_to_generator "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "$gen"
    fi
  done < <(grep -E '^[[:space:]]*- uses: [^ ]+@[0-9a-f]{40}[[:space:]]+#' "$wf")
}

main() {
  # wf#20 closure-portability guard (F7 pattern): the regen mutates the FACTORY
  # workspace (tooling/factory/compose.py + root make targets), none of which exist in
  # a consumer closure. No-op honestly so the workflow_run producer yields an empty
  # patch and the commit job's empty-patch classifier keeps the run green.
  if [[ ! -f tooling/factory/compose.py ]]; then
    echo "dependabot-regen: consumer closure (no tooling/factory/compose.py) -- self-host regen not applicable; no-op"
    exit 0
  fi
  local bump changed
  # bump description = the dependabot commit subject at HEAD (before our regen commit).
  bump="$(git log -1 --format=%s HEAD)"

  reconcile_action_pins
  make compose
  make lock
  make workflow-graph
  restore_if_graph_stamp_only "."

  changed="$(git diff --name-only HEAD | tr '\n' ' ' | sed 's/ *$//')"
  if [[ -z "$changed" ]]; then
    echo "dependabot-regen: no artifact drift to fix"; exit 0
  fi
  [ -n "$(tail -c1 .planning/LEDGER.tsv)" ] && printf '\n' >> .planning/LEDGER.tsv
  build_ledger_row "$changed" "$bump" >> .planning/LEDGER.tsv
  echo >> .planning/LEDGER.tsv   # ensure trailing newline
  echo "dependabot-regen: regenerated [$changed] + LEDGER row"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi
