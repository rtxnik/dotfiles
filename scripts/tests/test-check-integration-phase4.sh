#!/usr/bin/env bash
# Planted-drift suite for scripts/check-integration-phase4.sh (F7 / D3-2).
# Largest fixture: copies the REAL Phase-4 inputs (settings.json + the four scoped
# hooks + hooklib.sh + CONFIG.md, plus the two required test stubs) into a fresh
# CHECK_ROOT as the clean baseline, so the gate's many asserts pass, then mutates ONE
# input per case. The gate is driven via the CHECK_ROOT seam; the real .claude tree is
# never touched (fixtures are mktemp copies).
#
# NB: the gate's slug assert (section 9) is host-independent — it derives the root from
# git (fallback $ROOT) and only checks algorithm-equivalence with session-instincts.sh
# (the sed 's:/:-:g' transform). It carries no host literal; we regression-lock that below.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$REPO/scripts/check-integration-phase4.sh"
# shellcheck source=../lib/testlib.sh
source "$(cd "$(dirname "$0")/../lib" && pwd)/testlib.sh"
t_init

# fixture : build a CHECK_ROOT that mirrors the real Phase-4 inputs. Echoes the root.
fixture() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude/hooks/lib" "$d/.claude/hooks/tests"
  cp "$REPO/.claude/settings.json" "$d/.claude/settings.json"
  local h
  for h in context-exhaustion-gate.sh session-instincts.sh bounded-surface-guard.sh tool-loop-guard.sh CONFIG.md; do
    [ -f "$REPO/.claude/hooks/$h" ] && cp "$REPO/.claude/hooks/$h" "$d/.claude/hooks/$h"
  done
  cp "$REPO/.claude/hooks/lib/hooklib.sh" "$d/.claude/hooks/lib/hooklib.sh"
  printf '#!/usr/bin/env bash\necho ok\n' > "$d/.claude/hooks/tests/test-context-exhaustion-gate.sh"
  printf '#!/usr/bin/env bash\necho ok\n' > "$d/.claude/hooks/tests/test-session-instincts.sh"
  printf '%s' "$d"
}

# clean -> 0
d=$(fixture); rc=0; CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1 || rc=$?
assert_rc "clean phase4 fixture passes" 0 "$rc"; rm -rf "$d"

# drift: remove the context-exhaustion-gate command from the PostToolUse block -> 1
d=$(fixture)
python3 - "$d/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]; data = json.load(open(p))
for blk in data["hooks"]["PostToolUse"]:
    blk["hooks"] = [h for h in blk["hooks"] if "context-exhaustion-gate" not in h.get("command", "")]
json.dump(data, open(p, "w"))
PY
out=$(CHECK_ROOT="$d" bash "$SRC" 2>&1); rc=0; CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1 || rc=$?
assert_rc "context-exhaustion-gate unwired fails" 1 "$rc"
assert_out_has "unwired gate reported" "$out" "wired in a PostToolUse block"
rm -rf "$d"

# drift: delete a documented WORKFLOW_* row a hook reads (WORKFLOW_CTX_SOFT_PCT) -> 1 FORWARD drift
d=$(fixture)
grep -v '`WORKFLOW_CTX_SOFT_PCT`' "$d/.claude/hooks/CONFIG.md" > "$d/.claude/hooks/CONFIG.md.tmp" \
  && mv "$d/.claude/hooks/CONFIG.md.tmp" "$d/.claude/hooks/CONFIG.md"
out=$(CHECK_ROOT="$d" bash "$SRC" 2>&1); rc=0; CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1 || rc=$?
assert_rc "deleted CONFIG.md row fails" 1 "$rc"
assert_out_has "FORWARD drift reported" "$out" "FORWARD drift"
rm -rf "$d"

# drift: add session-instincts to the hooklib HOOK_PINNED= line -> 1 'must be non-pinned'
d=$(fixture)
sed 's/^HOOK_PINNED="/HOOK_PINNED="session-instincts /' "$d/.claude/hooks/lib/hooklib.sh" > "$d/.claude/hooks/lib/hooklib.sh.tmp" \
  && mv "$d/.claude/hooks/lib/hooklib.sh.tmp" "$d/.claude/hooks/lib/hooklib.sh"
out=$(CHECK_ROOT="$d" bash "$SRC" 2>&1); rc=0; CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1 || rc=$?
assert_rc "pinned Phase-4 hook fails" 1 "$rc"
assert_out_has "non-pinned violation reported" "$out" "must be non-pinned"
rm -rf "$d"

# regression: the de-slugged gate carries no host-specific literal on either side.
grep -q '/home/vscode/projects' "$SRC"; rc=$?
assert_rc "gate drops the /home/vscode/projects input literal" 1 "$rc"
grep -q -- '-home-vscode-projects' "$SRC"; rc=$?
assert_rc "gate drops the -home-vscode-projects expected literal" 1 "$rc"

# light closure (2026-07-02 canary): session-instincts is memory-stack; a consumer tree
# without it (file absent AND unwired in settings) must PASS the gate.
light_fixture() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude/hooks/lib" "$d/.claude/hooks/tests"
  python3 - "$REPO/.claude/settings.json" "$d/.claude/settings.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for ev in list(data.get("hooks", {})):
    for blk in data["hooks"][ev]:
        blk["hooks"] = [h for h in blk["hooks"] if "session-instincts" not in h.get("command", "")]
json.dump(data, open(sys.argv[2], "w"))
PY
  local h
  for h in context-exhaustion-gate.sh bounded-surface-guard.sh tool-loop-guard.sh CONFIG.md; do
    cp "$REPO/.claude/hooks/$h" "$d/.claude/hooks/$h"
  done
  cp "$REPO/.claude/hooks/lib/hooklib.sh" "$d/.claude/hooks/lib/hooklib.sh"
  printf '#!/usr/bin/env bash\necho ok\n' > "$d/.claude/hooks/tests/test-context-exhaustion-gate.sh"
  printf '%s' "$d"
}
d=$(light_fixture); rc=0; CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1 || rc=$?
assert_rc "light closure (no session-instincts) passes" 0 "$rc"; rm -rf "$d"

# tripwire: wired in settings but file ABSENT -> 1 (works on any closure: the wiring is synthesized)
d=$(light_fixture)
python3 - "$d/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]; data = json.load(open(p))
blocks = data.setdefault("hooks", {}).setdefault("SessionStart", [])
blocks.append({"hooks": [{"type": "command", "command": "bash .claude/hooks/session-instincts.sh || true"}]})
json.dump(data, open(p, "w"))
PY
rc=0; CHECK_ROOT="$d" bash "$SRC" >/dev/null 2>&1 || rc=$?
assert_rc "wired-but-missing session-instincts fails" 1 "$rc"; rm -rf "$d"

t_summary
