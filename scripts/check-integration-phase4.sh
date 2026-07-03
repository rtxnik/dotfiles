#!/usr/bin/env bash
# shellcheck disable=SC2154  # pass/fail are set in the caller's scope by ck_init (lib/check.sh)
# Phase-4 structural assertion gate. Asserts the Session/Context-Health hooks
# (context-exhaustion-gate.sh + session-instincts.sh) are present, wired into settings.json
# (B3 in PostToolUse, instincts in SessionStart with `|| true`), tested, fail-open, non-pinned,
# source hooklib, carry no blocking exit code, and that the hooklib helpers they depend on plus
# the bidirectional CONFIG.md config-drift contract, the slug algorithm, the defense markers, and
# the audit-line fields all hold. Since P4 the config-drift contract also covers the Phase-3 floor
# guards (bounded-surface-guard.sh, tool-loop-guard.sh).
# Auto-discovered by integration-check.sh (check-integration-*.sh).
# Design source: docs/superpowers/specs/2026-06-02-phase4-session-context-health-design.md
# (§TEST MATRIX -> check-integration-phase4). Fails (exit 1) on any drift.
set -uo pipefail
# shellcheck source=lib/check.sh
source "$(cd "$(dirname "$0")/lib" && pwd)/check.sh"
ck_init
ROOT="${CHECK_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
settings="$ROOT/.claude/settings.json"
hooks_dir="$ROOT/.claude/hooks"
lib="$hooks_dir/lib/hooklib.sh"
config_md="$hooks_dir/CONFIG.md"
gate="$hooks_dir/context-exhaustion-gate.sh"
instincts="$hooks_dir/session-instincts.sh"
surface_guard="$hooks_dir/bounded-surface-guard.sh"   # Phase-3 floor — in drift-gate scope since P4
loop_guard="$hooks_dir/tool-loop-guard.sh"            # Phase-3 floor — in drift-gate scope since P4

# Presence probe: session-instincts is MEMORY-STACK-owned; on a light closure the file is
# legitimately absent and every instincts assert below is skipped. Tripwire: wired in
# settings but file absent is ALWAYS a failure (protects self-host deletions).
has_instincts=0; [ -f "$instincts" ] && has_instincts=1

# ---------------------------------------------------------------------------------------------
# 1. settings.json is valid JSON.
# ---------------------------------------------------------------------------------------------
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$settings" 2>/dev/null
ck_assert_rc $? "settings.json is valid JSON"

# ---------------------------------------------------------------------------------------------
# 2. Both hooks exist.
# ---------------------------------------------------------------------------------------------
[ -f "$gate" ];      ck_assert_rc $? "context-exhaustion-gate.sh present"
if [ "$has_instincts" -eq 1 ]; then ck_pass "session-instincts.sh present"; else
  if jq -e '.hooks.SessionStart[].hooks[].command | select(test("session-instincts"))' "$settings" >/dev/null 2>&1; then
    ck_fail "session-instincts wired in settings.json but the hook file is ABSENT"
  else
    ck_pass "session-instincts absent and unwired (light closure) — instincts asserts skipped"
  fi
fi

# ---------------------------------------------------------------------------------------------
# 3. Wiring: B3 in a PostToolUse block; instincts in a SessionStart block AND its command has `|| true`.
#    Inspect the JSON structure rather than grepping the raw file (block-scoped, not anywhere).
# ---------------------------------------------------------------------------------------------
jq -e '.hooks.PostToolUse[].hooks[].command | select(test("context-exhaustion-gate"))' "$settings" >/dev/null 2>&1
ck_assert_rc $? "context-exhaustion-gate wired in a PostToolUse block"
if [ "$has_instincts" -eq 1 ]; then
  si_cmd=$(jq -r '.hooks.SessionStart[].hooks[].command | select(test("session-instincts"))' "$settings" 2>/dev/null)
  [ -n "$si_cmd" ]
  ck_assert_rc $? "session-instincts wired in a SessionStart block"
  grep -qF '|| true' <<<"$si_cmd"
  ck_assert_rc $? "session-instincts SessionStart command includes '|| true'"
fi

# ---------------------------------------------------------------------------------------------
# 4. Each hook ships its test.
# ---------------------------------------------------------------------------------------------
[ -f "$hooks_dir/tests/test-context-exhaustion-gate.sh" ]
ck_assert_rc $? "test-context-exhaustion-gate.sh present"
if [ "$has_instincts" -eq 1 ]; then
  [ -f "$hooks_dir/tests/test-session-instincts.sh" ]
  ck_assert_rc $? "test-session-instincts.sh present"
fi

# ---------------------------------------------------------------------------------------------
# 5. Each hook: carries `# FAILURE-MODE: fail-open`, sources hooklib, has NO real `exit 2`.
# ---------------------------------------------------------------------------------------------
p4_hooks=("$gate"); [ "$has_instincts" -eq 1 ] && p4_hooks+=("$instincts")
for h in "${p4_hooks[@]}"; do
  base=$(basename "$h")
  grep -qF '# FAILURE-MODE: fail-open' "$h"
  ck_assert_rc $? "$base carries '# FAILURE-MODE: fail-open'"
  grep -qE 'source .*lib/hooklib.sh' "$h"
  ck_assert_rc $? "$base sources hooklib.sh"
  n=$(grep -c 'exit 2' "$h")
  [ "$n" -eq 0 ]
  ck_assert_rc $? "$base contains no 'exit 2' (never blocks; found $n)"
done

# ---------------------------------------------------------------------------------------------
# 6. Both hooks are NON-pinned: neither id appears in the HOOK_PINNED= line of hooklib.sh.
# ---------------------------------------------------------------------------------------------
pinned_line=$(grep -E '^HOOK_PINNED=' "$lib")
for id in context-exhaustion-gate session-instincts; do
  if grep -qF "$id" <<<"$pinned_line"; then
    ck_fail "$id appears in HOOK_PINNED (Phase-4 hooks must be non-pinned)"
  else
    ck_pass "$id is NON-pinned (absent from HOOK_PINNED)"
  fi
done

# ---------------------------------------------------------------------------------------------
# 7. hooklib.sh helpers: rewritten strict cfg_int guard, length guard, NO old broken glob;
#    plus cfg_flag, audit_log, wf_reaper, and the WORKFLOW_HOOKS_OFF token.
# ---------------------------------------------------------------------------------------------
grep -qF "''|*[!0-9]*" "$lib"
ck_assert_rc $? "hooklib cfg_int has the strict '''|*[!0-9]*' guard"
grep -qF -- '-le 18' "$lib"
ck_assert_rc $? "hooklib cfg_int has the length guard (-le 18)"
if grep -qF '[!0-9-]' "$lib"; then
  ck_fail "hooklib still contains the OLD broken glob '[!0-9-]' (buggy hyphen class)"
else
  ck_pass "hooklib does not contain the OLD broken glob '[!0-9-]'"
fi
for tok in cfg_flag audit_log wf_reaper WORKFLOW_HOOKS_OFF; do
  grep -qF "$tok" "$lib"
  ck_assert_rc $? "hooklib contains '$tok'"
done

# ---------------------------------------------------------------------------------------------
# 8. Bidirectional config drift vs CONFIG.md.
#    Scope: the two Phase-4 hooks + the Phase-3 floor guards (bounded-surface, tool-loop) — P4.
#    FORWARD: every config-read token in the scoped hooks (except WORKFLOW_AUDIT_PATH, an
#             internal seam) must be documented in CONFIG.md.
#    REVERSE: every WORKFLOW_* token in CONFIG.md schema rows must be read somewhere in
#             {the scoped hooks, hooklib.sh}.
# ---------------------------------------------------------------------------------------------
# FORWARD: config-read lines only (cfg_int|cfg_flag|${?WORKFLOW), tokens, minus the seam.
fwd_undoc=''
while IFS= read -r tok; do
  [ -n "$tok" ] || continue
  [ "$tok" = "WORKFLOW_AUDIT_PATH" ] && continue   # internal seam, documented as such
  grep -qF "$tok" "$config_md" || fwd_undoc="${fwd_undoc} ${tok}"
done < <(grep -hE 'cfg_int|cfg_flag|\$\{?WORKFLOW' "${p4_hooks[@]}" "$surface_guard" "$loop_guard" \
           | grep -oE 'WORKFLOW_[A-Z_]+' | sort -u)
if [ -z "$fwd_undoc" ]; then
  ck_pass "FORWARD drift: every hook-read knob is documented in CONFIG.md"
else
  ck_fail "FORWARD drift: undocumented knob(s) read by hooks but absent from CONFIG.md:${fwd_undoc}"
fi
# REVERSE: schema-table rows only (lines starting with '| `WORKFLOW_'); each must be read in
# {the two hooks, hooklib.sh}. Grep the files directly (no pipe-into-grep-q SIGPIPE under pipefail).
rev_stale=''
while IFS= read -r tok; do
  [ -n "$tok" ] || continue
  case "$tok" in WORKFLOW_INSTINCTS_*) [ "$has_instincts" -eq 0 ] && continue ;; esac
  grep -qF "$tok" "${p4_hooks[@]}" "$lib" "$surface_guard" "$loop_guard" || rev_stale="${rev_stale} ${tok}"
done < <(grep -E '^\| `WORKFLOW_' "$config_md" | grep -oE 'WORKFLOW_[A-Z_]+' | sort -u)
if [ -z "$rev_stale" ]; then
  ck_pass "REVERSE drift: every CONFIG.md schema row is read in {hooks, hooklib}"
else
  ck_fail "REVERSE drift: stale CONFIG.md row(s) not read anywhere:${rev_stale}"
fi

# ---------------------------------------------------------------------------------------------
# 9. Slug algorithm is host-independent: derive the project root from git (fallback $ROOT) and
#    reproduce the memory-dir slug the SAME way session-instincts.sh does (sed 's:/:-:g'),
#    asserting algorithm-equivalence with the live hook rather than equality to a host literal.
# ---------------------------------------------------------------------------------------------
root=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$ROOT")
slug=$(printf '%s' "$root" | sed 's:/:-:g')
{ [ -n "$slug" ] && ! printf '%s' "$slug" | grep -q '/'; }
ck_assert_rc $? "slug derivation produces a slash-free key (got '$slug')"
if [ "$has_instincts" -eq 1 ]; then
  grep -qF "sed 's:/:-:g'" "$instincts"
  ck_assert_rc $? "session-instincts.sh uses the same slug transform (sed 's:/:-:g')"
fi

# ---------------------------------------------------------------------------------------------
# 10. Defense markers present in session-instincts.sh.
# ---------------------------------------------------------------------------------------------
if [ "$has_instincts" -eq 1 ]; then
  for m in 'command elided' 'WF_DATA_' 'END HISTORICAL MEMORY' 'RECALLED PRIOR-SESSION CONTEXT'; do
    grep -qF "$m" "$instincts"
    ck_assert_rc $? "session-instincts contains defense marker '$m'"
  done
fi

# ---------------------------------------------------------------------------------------------
# 11. Audit-field completeness (static source presence).
# ---------------------------------------------------------------------------------------------
for fld in decision_id config_snapshot historical; do
  grep -qF "$fld" "$gate"
  ck_assert_rc $? "context-exhaustion-gate audit field '$fld' present"
done
if [ "$has_instincts" -eq 1 ]; then
  for fld in decision_id config_snapshot historical truncated; do
    grep -qF "$fld" "$instincts"
    ck_assert_rc $? "session-instincts audit field '$fld' present"
  done
fi

# ---------------------------------------------------------------------------------------------
# 12. Audit schema v2 + session field (D4-5). Assert the jq object KEY specifically — a loose
#     `grep -qF session` would match the pre-existing `session_id` token and pass even if the
#     audit field were dropped.
# ---------------------------------------------------------------------------------------------
grep -q 'session:$session' "$gate"
ck_assert_rc $? "B3 audit line carries session field"
if [ "$has_instincts" -eq 1 ]; then
  grep -q 'session:$session' "$instincts"
  ck_assert_rc $? "instincts audit line carries session field"
fi
grep -q 'v:2' "$lib"
ck_assert_rc $? "audit_envelope stamps v:2"
# CONFIG.md schema docs bumped to v2 (exact rendered schema-version row, not a brittle regex).
grep -qF '| `v` | literal `2` | schema version |' "$config_md"
ck_assert_rc $? "CONFIG.md audit schema documents v2"

# ---------------------------------------------------------------------------------------------
# 13. Panic/disable honored everywhere (D4-8/D12): every .claude/hooks/*.sh whose id is NOT in
#     HOOK_PINNED must contain a `hook_enabled` token (calls the disable/panic switch). Pinned
#     hooks are exempt (un-disableable by design). Regression-locks workflow-phase-tracker (D11)
#     and any future non-pinned hook.
# ---------------------------------------------------------------------------------------------
pinned=$(grep -E '^HOOK_PINNED=' "$lib" | sed 's/^HOOK_PINNED=//; s/"//g')
for f in "$hooks_dir"/*.sh; do
  h=$(basename "$f" .sh)
  case " $pinned " in *" $h "*) continue ;; esac        # pinned hooks are exempt
  grep -q 'hook_enabled' "$f"
  ck_assert_rc $? "$h (non-pinned) calls hook_enabled"
done

# ---------------------------------------------------------------------------------------------
# Summary.
# ---------------------------------------------------------------------------------------------
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
