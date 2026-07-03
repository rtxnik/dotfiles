#!/usr/bin/env bash
# PreToolUse(Edit|Write) hook: blocks MODIFICATION of lint/format/quality-gate config files
# (an agent must not silently weaken a gate). First-time CREATION is allowed. Fail-CLOSED
# within the narrow protected allowlist; fail-OPEN on malformed input / non-config paths.
# Exit 0 = allow. Exit 2 = block. Escape hatch: export WORKFLOW_DISABLED_HOOKS=config-protection in the launching env (settings.json `env`).
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
hook_enabled "config-protection" || exit 0
hook_read_input
case "$TOOL_NAME" in Edit|Write) ;; *) exit 0 ;; esac

file_path=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file_path" ] && exit 0          # malformed -> fail open
base=$(basename -- "$file_path")

# Protected lint/format/quality-gate config basenames. pyproject.toml and tsconfig.json are
# intentionally NOT here (commonly edited for deps/compiler options -> too many false hits).
PROTECTED=".eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yml .eslintrc.yaml \
.prettierrc .prettierrc.json .prettierrc.yml .prettierrc.yaml .prettierrc.js prettier.config.js \
.editorconfig .shellcheckrc .golangci.yml .golangci.yaml \
ruff.toml .ruff.toml .flake8 .pylintrc biome.json .stylelintrc .stylelintrc.json"
case " $PROTECTED " in
  *" $base "*) ;;        # protected -> decide create vs modify below
  *) exit 0 ;;           # not a protected config -> allow
esac

# Decide create vs modify. Default to BLOCK (fail-closed) unless we can PROVE the file is
# absent (genuine ENOENT: parent dir exists and is readable, and nothing is there).
if [ -e "$file_path" ] || [ -L "$file_path" ]; then
  : # exists (incl. dangling symlink) -> modification -> block
else
  parent=$(dirname -- "$file_path")
  if [ -d "$parent" ] && [ -r "$parent" ]; then
    exit 0   # proven absent -> first-time creation -> allow
  fi
  # cannot prove absence (parent missing/unreadable) -> fail closed -> block
fi

echo "[BLOCKED] '$base' is a protected lint/format/quality-gate config."
echo "Modifying it can silently weaken a quality gate. If this change is intentional,"
echo "export WORKFLOW_DISABLED_HOOKS=config-protection in the launching env (settings.json env), restart, and re-run."
audit_emit_block config-protection protected_config_edit
exit 2
