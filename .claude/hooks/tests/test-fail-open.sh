#!/usr/bin/env bash
# Conformance: every hook fails OPEN — empty/malformed input never blocks (exit 0).
# A hook may block real violations via exit 2, but never on garbage input.
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
DIR="$(cd "$(dirname "$0")/.." && pwd)"
for hook in "$DIR"/*.sh; do
  base=$(basename "$hook")
  rc=0; echo "" | bash "$hook" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then echo "PASS: $base empty-input fail-open"; pass=$((pass+1));
  else echo "FAIL: $base empty-input (exit=$rc)"; fail=$((fail+1)); fi
  rc=0; printf 'not json {' | bash "$hook" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then echo "PASS: $base garbage-input fail-open"; pass=$((pass+1));
  else echo "FAIL: $base garbage-input (exit=$rc)"; fail=$((fail+1)); fi
done
# --- jq-dependency failure injection (F2 / D2-1) -------------------------------------------
# A broken jq must fail CLOSED (exit 2) for the blocking gates in HOOK_FAILCLOSED and stay
# fail-open (exit 0) — with one loud stderr line — for every other hook.
shim="$(mktemp -d)"
printf '#!/usr/bin/env bash\nexit 127\n' > "$shim/jq"
chmod +x "$shim/jq"
# shellcheck source=../lib/hooklib.sh
source "$DIR/lib/hooklib.sh"   # for $HOOK_FAILCLOSED (derived; core members hard-asserted)
for must in secrets-scan forbidden-ai-attribution config-protection merge-gate; do
  case " $HOOK_FAILCLOSED " in
    *" $must "*) echo "PASS: $must in HOOK_FAILCLOSED"; pass=$((pass+1)) ;;
    *) echo "FAIL: $must missing from HOOK_FAILCLOSED"; fail=$((fail+1)) ;;
  esac
done
payload='{"tool_name":"Bash","tool_input":{"command":"echo hi"},"session_id":"t"}'
for hook in "$DIR"/*.sh; do
  base=$(basename "$hook" .sh)
  rc=0; err=$(printf '%s' "$payload" | PATH="$shim:$PATH" bash "$hook" 2>&1 >/dev/null) || rc=$?
  case " $HOOK_FAILCLOSED " in
    *" $base "*)
      if [ "$rc" -eq 2 ]; then echo "PASS: $base jq-broken fails closed"; pass=$((pass+1));
      else echo "FAIL: $base jq-broken (exit=$rc, want 2)"; fail=$((fail+1)); fi ;;
    *)
      if [ "$rc" -eq 0 ]; then echo "PASS: $base jq-broken fails open"; pass=$((pass+1));
      else echo "FAIL: $base jq-broken (exit=$rc, want 0)"; fail=$((fail+1)); fi ;;
  esac
  # Hooks that consume hook_read_input must announce the degradation on stderr.
  if [ "$rc" -eq 0 ] && grep -q 'hook_read_input' "$hook"; then
    if printf '%s' "$err" | grep -q 'jq missing/broken'; then
      echo "PASS: $base loud fail-open line"; pass=$((pass+1))
    else
      echo "FAIL: $base silent fail-open under broken jq"; fail=$((fail+1))
    fi
  fi
done
rm -rf "$shim"

t_summary
