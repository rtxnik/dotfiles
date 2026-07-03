#!/usr/bin/env bash
# check-schema.sh (SP-7) — validate factory.json + factory.lock against the vendored
# JSON-Schemas in .factory/ using a pinned, CI-only check-jsonschema (run via pipx; NEVER an
# engine runtime dependency). Identical relative paths in the canonical repo and any consumer.
# pipx is preinstalled on GitHub-hosted runners; if absent (and no CHECK_JSONSCHEMA_CMD
# override) the gate SKIPs with a notice rather than hard-failing a tool-less environment.
set -uo pipefail
ROOT="${CHECK_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
PIN="0.31.2"   # exact == pin (mirrors uvx zizmor@1.25.2); confirmed installable in the plan

if [ -n "${CHECK_JSONSCHEMA_CMD:-}" ]; then
  read -r -a RUN <<< "$CHECK_JSONSCHEMA_CMD"
elif command -v pipx >/dev/null 2>&1; then
  RUN=(pipx run "check-jsonschema==$PIN")
else
  echo "check-schema: pipx not found — SKIP (set CHECK_JSONSCHEMA_CMD to override)"
  exit 0
fi

fail=0
validate() {                       # $1 schema basename under .factory/, $2 doc rel to ROOT
  local schema="$ROOT/.factory/$1" doc="$ROOT/$2"
  if [ ! -f "$doc" ]; then echo "check-schema: $2 absent — skip"; return 0; fi
  if [ ! -f "$schema" ]; then echo "check-schema: FAIL missing schema .factory/$1" >&2; fail=1; return 1; fi
  if "${RUN[@]}" --schemafile "$schema" "$doc"; then
    echo "check-schema: OK $2"
  else
    echo "check-schema: FAIL $2 does not validate against .factory/$1" >&2
    fail=1
  fi
}
validate "factory.config.schema.json" "factory.json"
validate "factory.lock.schema.json"   "factory.lock"
validate "consumers.schema.json" "tooling/factory/consumers.json"
if [ -d "$ROOT/payload/bundles" ]; then
  for m in "$ROOT"/payload/bundles/*/bundle.json; do
    [ -f "$m" ] || continue
    if "${RUN[@]}" --schemafile "$ROOT/.factory/bundle.schema.json" "$m"; then
      echo "check-schema: OK ${m#"$ROOT"/}"
    else
      echo "check-schema: FAIL ${m#"$ROOT"/} does not validate against .factory/bundle.schema.json" >&2
      fail=1
    fi
  done
fi
validate "overlay.schema.json" "overlay/bundle.toml"
if [ "$fail" -ne 0 ]; then echo "Results: FAILED" >&2; exit 1; fi
echo "Results: factory + consumers + bundle + overlay configs valid against .factory/ schemas"
