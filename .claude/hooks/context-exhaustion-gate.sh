#!/usr/bin/env bash
# PostToolUse(broad) hook: context-exhaustion gate (B3). CONSUMER ONLY of statusline's
# claude-ctx-<session>.json. Resolves the ctx file by matching the JSON .session_id field
# (never the filename), validates all four fields in ONE jq -e pass, computes the band against
# cfg_int thresholds with an order-invariant guard, and emits a SOFT/HARD informational warning.
# Never blocks, never exits non-zero (no blocking exit code) — severity lives in the message.
# Task 5 adds the stateful behavior over the Task-4 core: a versioned latch, the full 9-cell
# transition table, deadband jitter absorption, a per-band bounded re-warn cap, SOFT->HARD
# escalation bypass, a never-debounced HARD anti-autonomy periodic re-assert, degraded-emit on
# stale-but-low readings, the misconfig note, and the reason taxonomy.
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
# FAILURE-MODE: fail-open (capacity/observability; never blocks; absent/stale data => silent)
HOOK_FAILMODE='fail-open'
PHASE4_CONTRACT_VERSION='1'

hook_enabled "context-exhaustion-gate" || exit 0

hook_read_input
session=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0

# --- Thresholds with order-invariant guard (B3.1) -----------------------------------------
soft=$(cfg_int WORKFLOW_CTX_SOFT_PCT 35 2 99)
hard=$(cfg_int WORKFLOW_CTX_HARD_PCT 25 1 98)
coerced=''
# Require 0 < hard < soft < 100; otherwise both -> documented defaults, note for audit.
if ! { [ "$hard" -gt 0 ] && [ "$hard" -lt "$soft" ] && [ "$soft" -lt 100 ]; }; then
  soft=35; hard=25; coerced='threshold_order'
fi

# --- Re-warn / transition tunables (B3.1/B3.3) --------------------------------------------
cooldown_ms=$(cfg_int WORKFLOW_CTX_COOLDOWN_MS 120000 0 3600000)
deadband=$(cfg_int WORKFLOW_CTX_DEADBAND_PCT 3 0 20)
max_warns=$(cfg_int WORKFLOW_CTX_MAX_WARNS_PER_BAND 3 1 50)
reassert_calls=$(cfg_int WORKFLOW_CTX_HARD_REASSERT_CALLS 8 1 1000)

now_ms="${WORKFLOW_NOW_MS:-$(date +%s%3N)}"
case "$now_ms" in (''|*[!0-9]*) exit 0 ;; esac   # can't determine integer ms time -> fail-open silent
[ "${#now_ms}" -le 18 ] || exit 0
stale_ms=$(cfg_int WORKFLOW_CTX_STALE_MS 300000 1000 3600000)

# --- Per-session paths (B3.6 / runbook): audit path + versioned latch ----------------------
safe=$(wf_safe_id "$session")
ctxdir="${TMPDIR:-/tmp}/wf-ctx"
mkdir -p "$ctxdir" 2>/dev/null || true
latchfile="${ctxdir}/${safe}.warned"
resolve_audit_path "$session"

# --- Read the versioned latch (fail-open; unknown version prefix => no latch). --------------
# Format: v1|band|emit_ms|last_emit_r|emits_this_band|last_tool_idx
#   band          : last decision band (H|S|D|"" none yet)  [D unused but reserved]
#   emit_ms       : now_ms of the last EMIT
#   last_emit_r   : last EMITTED remaining %
#   emits_this_band: count of emits accumulated in the current (latched) band
#   last_tool_idx : running tool-call index at the last VERBOSE HARD body emit (re-assert anchor)
st_band='' ; st_emit_ms=0 ; st_last_emit_r=101 ; st_emits=0 ; st_idx=0
if [ -s "$latchfile" ]; then
  IFS='|' read -r _v _b _em _lr _ec _ti < "$latchfile" 2>/dev/null || true
  if [ "$_v" = "v1" ]; then
    st_band="$_b"
    st_emit_ms=0;       case "$_em" in (''|*[!0-9]*) ;; (*) [ "${#_em}" -le 18 ] && st_emit_ms=$_em ;; esac
    st_last_emit_r=101; case "$_lr" in (''|*[!0-9]*) ;; (*) [ "${#_lr}" -le 18 ] && st_last_emit_r=$_lr ;; esac
    st_emits=0;         case "$_ec" in (''|*[!0-9]*) ;; (*) [ "${#_ec}" -le 18 ] && st_emits=$_ec ;; esac
    st_idx=0;           case "$_ti" in (''|*[!0-9]*) ;; (*) [ "${#_ti}" -le 18 ] && st_idx=$_ti ;; esac
  fi
  # Unknown version prefix -> ignore (fail-open: treat as no latch).
fi

# write_latch <band> <emit_ms> <last_emit_r> <emits> <idx> -> 0 on success, 1 on failure.
# Caller uses the rc to drive the in-memory idx fallback for the HARD safety re-assert.
write_latch() {
  printf 'v1|%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" \
    | write_state_atomic "$latchfile"
}

# audit_emit <result> <reason> <remaining> <bytes_injected>  (full B3.6 schema; fail-open)
# Thin wrapper over hooklib audit_envelope: same line shape, decision_id and ts as before.
audit_emit() {
  local extra did
  did=$(printf '%s' "${session}${now_ms}$1" | cksum | tr -d ' \t\n')
  extra=$(jq -cn \
    --arg session "$safe" \
    --argjson remaining "$3" \
    --argjson bytes "$4" \
    --argjson soft "$soft" --argjson hard "$hard" --argjson stale_ms "$stale_ms" \
    --argjson cooldown_ms "$cooldown_ms" --argjson deadband "$deadband" \
    --argjson max_warns "$max_warns" --argjson reassert "$reassert_calls" \
    '{session:$session, remaining:$remaining, bytes_injected:$bytes, historical:false, config_snapshot:{soft:$soft, hard:$hard, stale_ms:$stale_ms, cooldown_ms:$cooldown_ms, deadband:$deadband, max_warns:$max_warns, reassert:$reassert}}' \
    2>/dev/null) || return 0
  audit_envelope "context-exhaustion-gate" "PostToolUse" "$1" "$2" "$extra" "$now_ms" "$did"
  return 0
}

# --- Locate ctx by CONTENT match on .session_id (B3.0). First validating match wins. -------
# Reason taxonomy (B3.6): distinguish a missing file from a session mismatch from a
# session-matched-but-invalid candidate (malformed/bad_value).
candidates_seen=0
matched=''
session_matched_invalid=''
for f in "${TMPDIR:-/tmp}"/claude-ctx-*.json; do
  [ -e "$f" ] || continue   # nullglob not assumed
  candidates_seen=$((candidates_seen + 1))
  # ONE jq -e: every field well-typed, session matches, remaining in [0,100].
  # On match, echo the two fields space-separated; nonzero rc => no match / invalid.
  out=$(jq -e -r --arg s "$session" '
    select(
      (.session_id|type=="string") and
      (.remaining_percentage|type=="number") and
      (.used_pct|type=="number") and
      (.ts|type=="number") and
      (.session_id==$s) and
      (.remaining_percentage>=0) and (.remaining_percentage<=100)
    ) | "\(.remaining_percentage) \(.ts)"
  ' "$f" 2>/dev/null) || out=''
  if [ -n "$out" ]; then
    matched="$out"
    break
  fi
  # Second pass: did THIS candidate carry our session_id but fail validation?
  # (Distinguishes malformed/bad_value from a plain session_mismatch.)
  if [ -z "$session_matched_invalid" ]; then
    sid=$(jq -r '.session_id // empty' "$f" 2>/dev/null) || sid=''
    if [ "$sid" = "$session" ]; then
      session_matched_invalid='malformed'
    fi
  fi
done

if [ -z "$matched" ]; then
  if [ "$candidates_seen" -eq 0 ]; then
    audit_emit skip missing 0 0          # no candidate file at all
  elif [ -n "$session_matched_invalid" ]; then
    audit_emit skip "$session_matched_invalid" 0 0 # our session matched but failed validation
  else
    audit_emit skip session_mismatch 0 0 # candidates existed but none carried our session
  fi
  exit 0
fi

remaining=${matched%% *}
ts=${matched##* }
# Floor-truncate fractional remaining from jq (bridge may emit e.g. 42.7).
r=${remaining%%.*}
[ -n "$r" ] || r=0
# ts may carry a fractional part from jq; truncate for integer staleness math.
ts_i=${ts%%.*}
[ -n "$ts_i" ] || ts_i=0

# --- Reusable message builders (literal text per B3.2). ------------------------------------
soft_msg() {
  local pfx="$1"
  printf '%s~%s%%%s' "$pfx" "$r" " remaining, trend falling. This is informational.
Recommended: reach a natural stopping point on the current sub-task soon and surface it to the user.
Output quality declines gradually as context fills (context rot) — there is still runway to act well now.
(B3 soft tier; threshold WORKFLOW_CTX_SOFT_PCT=${soft}. Disable: WORKFLOW_DISABLED_HOOKS=context-exhaustion-gate.)"
}
hard_msg() {
  local pfx="$1"
  printf '%s~%s%%%s' "$pfx" "$r" " remaining and falling; output quality is already degrading (context rot). This is informational state, not a command.
Recommended:
- TELL THE USER NOW, in the chat, that context is nearly exhausted; in one or two lines name what is done vs unfinished.
- Let the USER choose how to proceed: /compact at this logical break, start a fresh session, or continue.
Do NOT:
- Do NOT autonomously write any handoff / summary / progress / continuation .md file.
- Do NOT run /compact yourself, and do NOT 'wrap up' or declare the task done to save tokens.
- Do NOT take large, destructive, or irreversible actions to finish faster.
- Do NOT duplicate existing persistence — claude-mem timeline, auto-memory, and harness compaction already handle that.
The human (not the agent) must pick the breakpoint.
(B3 hard tier; threshold WORKFLOW_CTX_HARD_PCT=${hard}. Disable: WORKFLOW_DISABLED_HOOKS=context-exhaustion-gate.)"
}
# Condensed HARD anti-autonomy safety line (never debounced into silence).
hard_reassert_msg() {
  printf 'CONTEXT BUDGET STATUS (observed): ~%s%% remaining. Reminder: do NOT autonomously write any handoff/summary/.md file and do NOT declare done to save tokens — tell the user and let them pick the breakpoint.' "$r"
}
# Prefix the one-time misconfig note when the threshold guard fired.
misconfig_note() {
  [ "$coerced" = 'threshold_order' ] || return 0
  printf '%s\n' "CONTEXT BUDGET CONFIG NOTE: WORKFLOW_CTX_SOFT_PCT/HARD_PCT were invalid (need 0<hard<soft<100); reverted to defaults soft=35 hard=25."
}

OBS_PFX='CONTEXT BUDGET STATUS (observed): '

# emit_band <soft|hard|hard_reassert|degraded> <result-band-letter> <text> [reason]
# Emits additionalContext, audits, latches the new state, then exits 0.
# Updates: emits_this_band, last_emit_r=r, emit_ms=now_ms; idx anchor as supplied by caller.
emit_band() {
  local result="$1" band="$2" text="$3" reason="${4:-ok}" note out
  # $2 (band) is reserved for call-site symmetry/readability; latching is done by the caller via write_latch.
  note="$(misconfig_note)"
  [ -n "$note" ] && text="${note}${text}"
  out=$(emit_additional_context PostToolUse "$text")
  [ -n "$out" ] && printf '%s' "$out"
  audit_emit "$result" "$reason" "$r" "${#text}"
}

# --- Staleness FIRST (B3.1). CORE: stale=>silent; Task 5: degraded-emit if last band low. ---
# Latch band letters: H=HEALTHY, S=SOFT, D=HARD. Degraded-emit only when last good band was
# SOFT or HARD (a stale-but-low reading is still actionable); HEALTHY/none -> silent.
age=$((now_ms - ts_i))
if [ "$age" -gt "$stale_ms" ]; then
  if [ "$st_band" = 'S' ] || [ "$st_band" = 'D' ]; then
    age_s=$((age / 1000))
    deg_pfx="CONTEXT BUDGET STATUS (last reading ~${age_s}s old): "
    if [ "$st_band" = 'D' ]; then
      msg="$(hard_msg "$deg_pfx")"
    else
      msg="$(soft_msg "$deg_pfx")"
    fi
    emit_band degraded "$st_band" "$msg" "stale_degraded_emit"
    # Keep band/idx; refresh emit bookkeeping so cooldown applies to the degraded emit too.
    write_latch "$st_band" "$now_ms" "$r" "$((st_emits + 1))" "$st_idx" || true
    exit 0
  fi
  audit_emit skip "stale age=${age} last_r=${r}" "$r" 0
  exit 0
fi

# --- Band classification (B3.1): HEALTHY r>soft ; SOFT hard<r<=soft ; HARD r<=hard. ---------
now_band='H'
[ "$r" -le "$soft" ] && now_band='S'
[ "$r" -le "$hard" ] && now_band='D'   # D = HARD band (avoid clash with H=HEALTHY)

reason_note="$coerced"
[ -n "$reason_note" ] || reason_note=ok

soft_plus_db=$((soft + deadband))
hard_plus_db=$((hard + deadband))

# last_tool_idx is a DELTA counter: "HARD tool calls since the last VERBOSE HARD emit".
# Verbose HARD emit (first-cross / permitted re-warn) -> reset to 0; every other HARD
# evaluation increments it; non-HARD bands store 0. The re-assert fires once it reaches
# reassert_calls and stays sticky (re-emits each subsequent call) until a verbose emit or a
# band change re-anchors it — so the anti-autonomy line is never debounced into silence.
hard_delta=$((st_idx + 1))

# ============================ FULL 9-CELL TRANSITION TABLE (B3.1) ==========================
# rows = stored band (st_band), cols = now_band. Cells set: do_emit / result / new latch.

case "$now_band" in
  # ----- now HEALTHY (r > soft) -----------------------------------------------------------
  H)
    # Any stored band: recovery. If above soft+deadband (or first sighting) -> reset HEALTHY,
    # zero the counter. Within deadband of soft while stored SOFT -> stay SOFT, no emit.
    if [ "$st_band" = 'S' ] && [ "$r" -le "$soft_plus_db" ]; then
      audit_emit none deadband_hold "$r" 0
      write_latch S "$st_emit_ms" "$st_last_emit_r" "$st_emits" "0" || true
    else
      # D4-4: the healthy line is per-PostToolUse noise that floods retention — keep the latch
      # write (state) but do NOT audit it. Band-activity none lines (deadband_hold etc.) stay.
      write_latch H "0" "101" "0" "0" || true
    fi
    exit 0
    ;;

  # ----- now SOFT (hard < r <= soft) ------------------------------------------------------
  S)
    case "$st_band" in
      D)
        # HARD -> SOFT downward (B3.1). Hysteresis: only treat it as a genuine recovery out of
        # hard once r climbs above hard+deadband; within the deadband STAY HARD (still in band,
        # no flapping). Either way NO emit (handled, not "fall through"); re-warn only on a
        # later down-cross.
        if [ "$r" -gt "$hard_plus_db" ]; then
          audit_emit none hard_to_soft "$r" 0
          write_latch S "0" "101" "0" "0" || true
        else
          audit_emit none hard_deadband_hold "$r" 0
          write_latch D "$st_emit_ms" "$st_last_emit_r" "$st_emits" "$hard_delta" || true
        fi
        exit 0
        ;;
      S)
        # Same-tier bounded re-warn. Emit only if ALL: cooled down, strictly falling vs last
        # EMIT, and under the per-band cap.
        if [ $((now_ms - st_emit_ms)) -gt "$cooldown_ms" ] \
           && [ "$r" -lt "$st_last_emit_r" ] \
           && [ "$st_emits" -lt "$max_warns" ]; then
          emit_band soft S "$(soft_msg "$OBS_PFX")" "$reason_note"
          write_latch S "$now_ms" "$r" "$((st_emits + 1))" "0" || true
        else
          audit_emit none soft_suppressed "$r" 0
          write_latch S "$st_emit_ms" "$st_last_emit_r" "$st_emits" "0" || true
        fi
        exit 0
        ;;
      *)
        # HEALTHY / none -> SOFT: first cross. Always emit.
        emit_band soft S "$(soft_msg "$OBS_PFX")" "$reason_note"
        write_latch S "$now_ms" "$r" "1" "0" || true
        exit 0
        ;;
    esac
    ;;

  # ----- now HARD (r <= hard) -------------------------------------------------------------
  D)
    if [ "$st_band" != 'D' ]; then
      # HEALTHY/SOFT/none -> HARD: first cross OR SOFT->HARD escalation. NEVER suppressed,
      # bypasses cooldown. Emit verbose body and reset the re-assert delta counter to 0.
      emit_band hard D "$(hard_msg "$OBS_PFX")" "$reason_note"
      write_latch D "$now_ms" "$r" "1" "0" || true
      exit 0
    fi

    # Already HARD. The verbose body is cap/cooldown-gated; the condensed safety re-assert is
    # NEVER fully suppressed — it re-emits once the delta counter reaches reassert_calls,
    # even if the latch write failed (best-effort in-memory delta).
    if [ $((now_ms - st_emit_ms)) -gt "$cooldown_ms" ] \
       && [ "$r" -lt "$st_last_emit_r" ] \
       && [ "$st_emits" -lt "$max_warns" ]; then
      # Verbose HARD re-warn permitted: re-emit body and reset the re-assert window.
      emit_band hard D "$(hard_msg "$OBS_PFX")" "$reason_note"
      write_latch D "$now_ms" "$r" "$((st_emits + 1))" "0" || true
      exit 0
    fi

    if [ "$hard_delta" -ge "$reassert_calls" ]; then
      # Periodic anti-autonomy safety line. The delta keeps advancing (sticky) so the line
      # re-appears every subsequent call until a verbose HARD emit / band change re-anchors it.
      emit_band hard_reassert D "$(hard_reassert_msg)" "hard_reassert"
      if ! write_latch D "$st_emit_ms" "$st_last_emit_r" "$st_emits" "$hard_delta"; then
        # Latch write failed: the re-assert still fired (best-effort, in-memory delta). exit 0.
        :
      fi
      exit 0
    fi

    # HARD, verbose suppressed, not yet at re-assert interval: stay silent, advance delta.
    audit_emit none hard_suppressed "$r" 0
    write_latch D "$st_emit_ms" "$st_last_emit_r" "$st_emits" "$hard_delta" || true
    exit 0
    ;;
esac

exit 0
