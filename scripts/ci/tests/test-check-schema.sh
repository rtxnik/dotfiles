#!/usr/bin/env bash
# Test runner for check-schema.sh. Uses the real pinned check-jsonschema when pipx is
# present (positive + negative fixtures); SKIPs the real-validation cases when pipx is absent
# (mirrors the repo's skip-when-tool-absent pattern).
set -uo pipefail
# shellcheck source=../../lib/testlib.sh
source "$(cd "$(dirname "$0")/../../lib" && pwd)/testlib.sh"
t_init
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/../check-schema.sh"
SCHEMA_DIR="$HERE/../../../.factory"

mkroot() {                       # sandbox consumer tree carrying the real schemas
  local d; d="$(mktemp -d)"
  mkdir -p "$d/.factory"
  cp "$SCHEMA_DIR"/*.schema.json "$d/.factory/"
  echo "$d"
}

if [ -z "${CHECK_JSONSCHEMA_CMD:-}" ] && ! command -v pipx >/dev/null 2>&1; then
  echo "SKIP: no check-jsonschema runner (set CHECK_JSONSCHEMA_CMD or install pipx) — real-validation cases skipped"
  t_summary
  exit 0
fi

# Closure-portability (F7, 2026-07-03 dotfiles canary CI): the consumers.json (cases 4-6)
# and bundle-manifest (cases 7-9) families exercise SELF-HOST-only schemas; consumer
# closures ship only the config/lock/overlay schemas. Unguarded, those cases fabricate a
# tooling/factory/consumers.json (or payload bundle) whose schema the sandbox can't carry,
# so the gate exits 1 with "missing schema" — a false RED for every positive case and a
# vacuous (wrong-reason) pass for every negative one. Gate each family on its schema's
# presence in the live tree; self-host keeps the full run.
has_consumers_schema=0; [ -f "$SCHEMA_DIR/consumers.schema.json" ] && has_consumers_schema=1
has_bundle_schema=0;    [ -f "$SCHEMA_DIR/bundle.schema.json" ]    && has_bundle_schema=1

# 1. valid factory.json + factory.lock -> exit 0
d="$(mkroot)"
cat > "$d/factory.json" <<'JSON'
{ "$schema": ".factory/factory.config.schema.json", "config_format": 1, "profile": "full",
  "identity": { "name": "t", "owner": "rtxnik", "year": "2026", "description": "ok" } }
JSON
cat > "$d/factory.lock" <<'JSON'
{ "lock_format": 1, "factory_version": null, "engine_floor": null, "source_sha": null,
  "release_digest": null, "provenance": null, "host_prereqs": null, "profile": "full",
  "resolved_capabilities": ["enforcement-floor"],
  "files": { "CLAUDE.md": { "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
                            "capabilities": ["enforcement-floor"], "provenance": "base" } } }
JSON
OUT="$(CHECK_ROOT="$d" bash "$SRC" 2>&1)"; assert_rc "valid config+lock passes" 0 $?

# 1b. REGRESSION: a real --allow-unsigned consumer lock carries the 7-key provenance block
# with predicate_type:null. The schema MUST accept it (else a valid consumer goes RED).
d="$(mkroot)"
cat > "$d/factory.json" <<'JSON'
{ "config_format": 1, "profile": "full",
  "identity": { "name": "t", "owner": "rtxnik", "year": "2026", "description": "ok" } }
JSON
cat > "$d/factory.lock" <<'JSON'
{ "lock_format": 1, "factory_version": "v1.0.0", "engine_floor": "1.0.0",
  "source_sha": "0000000000000000000000000000000000000000",
  "release_digest": "sha256:0000000000000000000000000000000000000000000000000000000000000000",
  "provenance": { "predicate_type": null, "bundle_sha256": null, "builder_id": null,
                  "source_sha": "0000000000000000000000000000000000000000", "verified": false,
                  "verified_via": "allow-unsigned", "trusted_root_sha256": null },
  "host_prereqs": [ { "tool": "git", "detect_cmd": "command -v git", "install_guidance": "git 2.30+" } ],
  "profile": "full", "resolved_capabilities": ["enforcement-floor"],
  "files": { "CLAUDE.md": { "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
                            "capabilities": ["enforcement-floor"], "provenance": "base" } } }
JSON
OUT="$(CHECK_ROOT="$d" bash "$SRC" 2>&1)"; assert_rc "allow-unsigned 7-key provenance passes" 0 $?

# 2. unknown/mistyped top-level key in factory.json -> exit 1 (lock omitted -> skipped)
d="$(mkroot)"
cat > "$d/factory.json" <<'JSON'
{ "config_format": 1, "profile": "full", "profle": "typo",
  "identity": { "name": "t", "owner": "rtxnik", "year": "2026", "description": "ok" } }
JSON
OUT="$(CHECK_ROOT="$d" bash "$SRC" 2>&1)"; assert_rc "unknown key fails" 1 $?

# 3. illegal files.*.provenance enum in factory.lock -> exit 1
d="$(mkroot)"
cat > "$d/factory.json" <<'JSON'
{ "config_format": 1, "profile": "full",
  "identity": { "name": "t", "owner": "rtxnik", "year": "2026", "description": "ok" } }
JSON
cat > "$d/factory.lock" <<'JSON'
{ "lock_format": 1, "factory_version": null, "engine_floor": null, "source_sha": null,
  "release_digest": null, "provenance": null, "host_prereqs": null, "profile": "full",
  "resolved_capabilities": ["enforcement-floor"],
  "files": { "CLAUDE.md": { "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
                            "capabilities": ["enforcement-floor"], "provenance": "made-up" } } }
JSON
OUT="$(CHECK_ROOT="$d" bash "$SRC" 2>&1)"; assert_rc "bad provenance enum fails" 1 $?

if [ "$has_consumers_schema" -eq 1 ]; then
# 4. valid consumers.json -> exit 0
d="$(mkroot)"; mkdir -p "$d/tooling/factory"
cat > "$d/tooling/factory/consumers.json" <<'JSON'
[ { "repo": "rtxnik/workspace-meta", "default_branch": "main", "profile_hint": "full" } ]
JSON
CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1; assert_rc "valid consumers.json passes" 0 $?

# 5. unknown key in consumers.json -> exit 1
d="$(mkroot)"; mkdir -p "$d/tooling/factory"
cat > "$d/tooling/factory/consumers.json" <<'JSON'
[ { "repo": "rtxnik/x", "default_branch": "main", "bogus": 1 } ]
JSON
CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1; assert_rc "unknown consumers key fails" 1 $?

# 6. bad profile_hint in consumers.json -> exit 1
d="$(mkroot)"; mkdir -p "$d/tooling/factory"
cat > "$d/tooling/factory/consumers.json" <<'JSON'
[ { "repo": "rtxnik/x", "default_branch": "main", "profile_hint": "enormous" } ]
JSON
CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1; assert_rc "bad profile_hint fails" 1 $?
else
  echo "SKIP: consumers.schema.json not in this closure — consumers.json cases (4-6) skipped"
fi

if [ "$has_bundle_schema" -eq 1 ]; then
# 7. valid bundle manifest -> exit 0
d="$(mkroot)"; mkdir -p "$d/payload/bundles/demo"
cat > "$d/payload/bundles/demo/bundle.json" <<'JSON'
{ "schema_version": 1, "name": "demo", "layer": "optional", "paths": ["tools/demo/**"] }
JSON
CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1; assert_rc "valid bundle manifest passes" 0 $?

# 8. bad layer enum -> exit 1
d="$(mkroot)"; mkdir -p "$d/payload/bundles/demo"
cat > "$d/payload/bundles/demo/bundle.json" <<'JSON'
{ "schema_version": 1, "name": "demo", "layer": "tier-3", "paths": [] }
JSON
CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1; assert_rc "bad bundle layer fails" 1 $?

# 9. unknown bundle key -> exit 1
d="$(mkroot)"; mkdir -p "$d/payload/bundles/demo"
cat > "$d/payload/bundles/demo/bundle.json" <<'JSON'
{ "schema_version": 1, "name": "demo", "layer": "optional", "paths": [], "bogus": true }
JSON
CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1; assert_rc "unknown bundle key fails" 1 $?
else
  echo "SKIP: bundle.schema.json not in this closure — bundle-manifest cases (7-9) skipped"
fi

# 10. valid overlay/bundle.toml -> exit 0
d="$(mkroot)"; mkdir -p "$d/overlay"
cat > "$d/overlay/bundle.toml" <<'TOML'
disable = ["hook:doc-path-warn"]
[settings_merge.env]
CORP_PROXY = "https://proxy.corp"
[settings_merge.permissions]
allow = ["mcp__corp_server__query"]
TOML
CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1; assert_rc "valid overlay.toml passes" 0 $?

# 11. unknown top-level overlay key -> exit 1
d="$(mkroot)"; mkdir -p "$d/overlay"
cat > "$d/overlay/bundle.toml" <<'TOML'
bogus_key = 1
TOML
CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1; assert_rc "unknown overlay key fails" 1 $?

# 12. lowercase settings_merge.env key -> exit 1
d="$(mkroot)"; mkdir -p "$d/overlay"
cat > "$d/overlay/bundle.toml" <<'TOML'
[settings_merge.env]
lower_case = "x"
TOML
CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1; assert_rc "lowercase env key fails" 1 $?

# 13. non-mcp permissions allow -> exit 1
d="$(mkroot)"; mkdir -p "$d/overlay"
cat > "$d/overlay/bundle.toml" <<'TOML'
[settings_merge.permissions]
allow = ["Read(./x)"]
TOML
CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1; assert_rc "non-mcp allow fails" 1 $?

t_summary
