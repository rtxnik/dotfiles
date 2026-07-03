#!/usr/bin/env bash
# Runs the check-integration-*.sh gates listed in the committed gate registry
# (.claude/gate-registry.json) and asserts the registry and the on-disk gate set agree
# exactly (no listed-but-missing, no present-but-unlisted). Replaces the former
# unconditional check-integration-*.sh glob, so the run-set is explicit and — under the
# future bundle model — scoped to exactly the gates a consumer selected.
set -uo pipefail
ROOT="${CHECK_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
gates_dir="$ROOT/scripts"
registry="$ROOT/.claude/gate-registry.json"
rc=0

if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$registry" 2>/dev/null; then
  echo "FAIL: $registry missing or not valid JSON"
  exit 1
fi

mapfile -t listed < <(jq -r '.gates[]' "$registry" 2>/dev/null | sort -u)
mapfile -t ondisk < <(find "$gates_dir" -maxdepth 1 -name 'check-integration-*.sh' -type f -exec basename {} \; 2>/dev/null | sort -u)

if [ "$(printf '%s\n' ${listed[@]+"${listed[@]}"})" != "$(printf '%s\n' ${ondisk[@]+"${ondisk[@]}"})" ]; then
  echo "FAIL: gate-registry.json does not match the on-disk check-integration-*.sh set"
  echo "  listed : ${listed[*]+"${listed[*]}"}"
  echo "  on-disk: ${ondisk[*]+"${ondisk[*]}"}"
  rc=1
fi

for g in ${listed[@]+"${listed[@]}"}; do
  if [ ! -f "$gates_dir/$g" ]; then
    echo "FAIL: registry lists $g but it is missing on disk"
    rc=1
    continue
  fi
  echo "== $gates_dir/$g =="
  CHECK_ROOT="$ROOT" bash "$gates_dir/$g" || rc=1
done

exit "$rc"
