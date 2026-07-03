#!/usr/bin/env bash
# hooklib.sh — shared helpers sourced by every workspace hook.
# Source it: source "$(dirname "$0")/lib/hooklib.sh"
# Or call one function directly: bash hooklib.sh <function> [args...]

# Gates that fail CLOSED (exit 2) when the jq dependency is broken — exactly the hooks that
# can block (exit 2) on real violations. ORTHOGONAL to HOOK_PINNED (= cannot be disabled):
# large-file-guard is pinned but warn-only -> fail-open; config-protection/merge-gate are
# unpinned but blocking -> fail-closed. (F2 / D2-1)
HOOK_FAILCLOSED="secrets-scan forbidden-ai-attribution config-protection merge-gate pre-push-secrets worktree-secrets-scan"

# Reads stdin once; sets INPUT and TOOL_NAME in the caller's scope.
# Probes jq first: a hook cannot inspect its input without jq, so a gate in HOOK_FAILCLOSED
# blocks outright (better no mutation than an unscanned one); every other hook degrades to
# no-op with ONE loud stderr line (never silently — D2-1).
hook_read_input() {
  INPUT=$(cat)
  if ! printf '{}' | jq -e . >/dev/null 2>&1; then
    local hid
    hid="$(basename "$0" .sh)"
    case " $HOOK_FAILCLOSED " in
      *" $hid "*)
        echo "[BLOCKED] hook $hid: jq is missing or broken — this gate fails CLOSED."
        echo "Fix jq (check PATH / mise install jq), then retry the action."
        exit 2
        ;;
      *)
        echo "hook $hid: jq missing/broken — degraded to no-op (fail-open). Enforcement coverage reduced; fix jq." >&2
        ;;
    esac
  fi
  TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
}

# Echo the Bash command from the tool input.
hook_command() { echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null; }

# Echo Edit/Write content (new_string for Edit, content for Write).
hook_content() { echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null; }

# The single canonical .planning directory, resolved deterministically:
#   1. inside a git repo -> <repo-root>/.planning
#   2. else walk up for an EXISTING .planning (the restored symlink lives at the workspace root)
#   3. else refuse (return 1) — NEVER create a .planning outside a repo (that forks an orphan).
planning_dir() {
  local root d
  if root=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$root" ]; then
    echo "${root}/.planning"; return 0
  fi
  d="$PWD"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -d "$d/.planning" ]; then echo "${d}/.planning"; return 0; fi
    d=$(dirname "$d")
  done
  return 1
}

# Inline "$(planning_dir)/<file>" so the self-model extractor (parse_hooks._analyze_lib)
# resolves these accessors. planning_dir refuses (empty) outside a repo; every caller guards
# the result with `[ -f ]` / its own `planning_dir || exit 0`, so no separate refusal needed.
state_file()   { echo "$(planning_dir)/workflow-state.json"; }
ledger_path()  { echo "$(planning_dir)/LEDGER.tsv"; }
ledger_header() { printf 'timestamp\tfiles\toutcome\tgate_result\tnotes\n'; }
review_state_file() { echo "$(planning_dir)/review-state.json"; }
gate_evidence_path() { echo "$(planning_dir)/gate-evidence.log"; }

# ledger_validate [path] : validate a LEDGER.tsv against the canonical 5-column schema
# (header == ledger_header; every data row has exactly 5 TAB fields; outcome is one of
# kept|discarded|dead-end per discipline.md). Echoes one problem line per violation.
# rc 0 = clean or file missing (fail-open: emptiness is pre-push-contract's concern);
# rc 1 = problems found. Read-only — never blocks on its own.
ledger_validate() {
  local path="${1:-$(ledger_path)}" problems hdr
  [ -f "$path" ] || return 0
  hdr=$(ledger_header); hdr="${hdr%$'\n'}"
  problems=$(awk -F'\t' -v hdr="$hdr" '
    NR==1 { if ($0 != hdr) print "line 1: header is not the canonical 5-column schema"; next }
    NF == 0 { next }
    NF != 5 { printf "line %d: %d columns (expected 5)\n", NR, NF; next }
    $3 != "kept" && $3 != "discarded" && $3 != "dead-end" {
      printf "line %d: outcome \"%s\" not in kept|discarded|dead-end\n", NR, $3 }
  ' "$path")
  [ -z "$problems" ] && return 0
  printf '%s\n' "$problems"
  return 1
}

# ledger_stats [path] : echo "kept=N discarded=N dead-end=N" over data rows (header excluded).
# Missing file -> all zeros. Never errors (fail-open).
ledger_stats() {
  local path="${1:-$(ledger_path)}"
  [ -f "$path" ] || { echo "kept=0 discarded=0 dead-end=0"; return 0; }
  awk -F'\t' 'NR>1 { c[$3]++ }
    END { printf "kept=%d discarded=%d dead-end=%d\n", c["kept"]+0, c["discarded"]+0, c["dead-end"]+0 }' "$path"
}

# ledger_rows [--since-ref <ref>] [path] : count schema-shaped data rows (NF==5, non-header).
# Default: every such row in the file (the one canonical emptiness predicate — replaces
# merge-gate's wc-l and pre-push's ledger_stats sum; DUP-2). With --since-ref <ref>: only rows
# NET-ADDED in `git diff <ref> HEAD -- <path>` (branch-scoped, SHA-anchored — the
# check-ledger-gate.sh idiom; immune to the LEDGER's mixed date-only/ISO timestamps). The ref
# DEGRADES to the cumulative count when it is empty, unresolvable, or resolves to HEAD itself
# (on main / no fork) — so the merge floor is never spuriously zero on unusual topology and the
# F1 server-side floor remains the real enforcement boundary. Missing file -> 0. Always rc 0.
ledger_rows() {
  local ref=""
  if [ "${1:-}" = "--since-ref" ]; then ref="${2:-}"; shift 2; fi
  local path="${1:-$(ledger_path)}" n
  [ -f "$path" ] || { echo 0; return 0; }
  if [ -n "$ref" ] \
     && git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1 \
     && [ "$(git rev-parse "${ref}^{commit}" 2>/dev/null)" != "$(git rev-parse HEAD 2>/dev/null)" ]; then
    n=$(git diff "$ref" HEAD -- "$path" 2>/dev/null \
        | grep -e '^+[^+]' | cut -c2- \
        | awk -F'\t' 'NF==5 && $1!="timestamp"' | grep -c . 2>/dev/null)
    echo "${n:-0}"; return 0
  fi
  awk -F'\t' 'NR>1 && NF==5 && $1!="timestamp"{n++} END{print n+0}' "$path"
  return 0
}

# Atomically replace a file with stdin: write to a temp file in the same dir, then mv.
# A crash mid-write leaves the previous file intact (never empty/half-written).
# Returns non-zero on failure; callers treat state as advisory and proceed (fail-open).
write_state_atomic() {
  local target="$1" dir tmp
  dir=$(dirname "$target")
  tmp=$(mktemp "${dir}/.wf-state.XXXXXX" 2>/dev/null) || return 1
  if cat >"$tmp"; then
    mv -f "$tmp" "$target" && return 0
  fi
  rm -f "$tmp"
  return 1
}

# write_phase_state <phase> <branch> <started_at> [state_path] : the SINGLE canonical
# {phase,branch,started_at} writer (DUP-WSL-1). jq-builds the object and atomically replaces
# the state file. Returns write_state_atomic's rc (advisory; callers fail-open).
write_phase_state() {
  jq -n --arg phase "$1" --arg branch "$2" --arg started_at "$3" \
    '{phase:$phase, branch:$branch, started_at:$started_at}' \
    | write_state_atomic "${4:-$(state_file)}"
}

# Record the machine-readable review verdict that merge-gate.sh reads at the merge boundary.
# Usage: record_review_verdict <approved|changes-requested> [base_sha] [head_sha]
# CLI (from the rubric): bash .claude/hooks/lib/hooklib.sh record_review_verdict approved <base> <head>
# NOT a hook: called deliberately by the agent after a review, so it fails LOUDLY (rc 1 + stderr).
record_review_verdict() {
  local verdict="${1:-}" base="${2:-}" head="${3:-}" pdir branch ts
  case "$verdict" in
    approved|changes-requested) ;;
    *) echo "usage: record_review_verdict <approved|changes-requested> [base_sha] [head_sha]" >&2; return 1 ;;
  esac
  pdir=$(planning_dir) || { echo "record_review_verdict: not inside a repo (no .planning root)" >&2; return 1; }
  branch=$(git branch --show-current 2>/dev/null)
  [ -n "$branch" ] || { echo "record_review_verdict: cannot resolve the current branch" >&2; return 1; }
  [ -n "$head" ] || head=$(git rev-parse HEAD 2>/dev/null || echo "")
  [ -n "$base" ] || { base=$(git rev-parse 'HEAD~1' 2>/dev/null) || base=$head; }
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  mkdir -p "$pdir" 2>/dev/null
  jq -n --arg branch "$branch" --arg range "${base}..${head}" --arg verdict "$verdict" --arg ts "$ts" \
    '{branch:$branch, sha_range:$range, verdict:$verdict, ts:$ts}' \
    | write_state_atomic "$(review_state_file)"
}

# cfg_int NAME DEFAULT MIN MAX -> echoes a valid integer in [MIN,MAX].
# Any non-digit/empty input, overlong (>18 digits), or out-of-range -> DEFAULT.
# Leading zeros are canonicalized base-10 (007 -> 7). NEVER errors, never echoes garbage,
# never writes to stderr. (fail-open config)
cfg_int() {
  local name="$1" def="$2" min="$3" max="$4" val
  val="${!name-}"
  case "$val" in
    ''|*[!0-9]*) echo "$def"; return 0 ;;
  esac
  [ "${#val}" -le 18 ] || { echo "$def"; return 0; }
  val=$((10#$val))
  if [ "$val" -lt "$min" ] || [ "$val" -gt "$max" ]; then echo "$def"; return 0; fi
  echo "$val"
}

# cfg_flag NAME DEFAULT(0|1) -> echoes 0 or 1. Case-insensitive.
# {off,0,false,no} -> 0 ; {on,1,true,yes} -> 1 ; ANYTHING ELSE -> DEFAULT.
cfg_flag() {
  local name="$1" def="$2" val
  val="$(printf '%s' "${!name-}" | tr '[:upper:]' '[:lower:]')"
  case "$val" in
    off|0|false|no)  echo 0; return 0 ;;
    on|1|true|yes)   echo 1; return 0 ;;
    *)               echo "$def"; return 0 ;;
  esac
}

# --- Secret detection (shared by secrets-scan.sh and pre-push-secrets.sh) ---

# One PCRE per line. This is the single source for both hooks.
secret_patterns() {
  cat <<'EOF'
AKIA[0-9A-Z]{16}
-----BEGIN\s*(RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----
gh[ps]_[A-Za-z0-9_]{36,}
xox[bpas]-[A-Za-z0-9-]{10,}
sk-[A-Za-z0-9]{20,}
glpat-[A-Za-z0-9_-]{20,}
EOF
}

# High-confidence matches ONLY (the secret_patterns set) — these BLOCK at push time (D2-2).
secret_matches_high() {
  local text pat
  text=$(cat)
  while IFS= read -r pat; do
    printf '%s' "$text" | grep -oP -- "$pat" 2>/dev/null || true
  done < <(secret_patterns)
}

# Assignment-shaped heuristic matches ONLY — warn-tier (too false-positive-prone to block).
secret_matches_heuristic() {
  printf '%s' "$(cat)" \
    | grep -oiP -- '(password|secret|api_key|api_secret|access_token|auth_token)\s*[:=]\s*"[^"]{8,}"' 2>/dev/null || true
}

# --- F3 / D5-1: hybrid engine. The builtin patterns above are the always-on ---
# --- floor; gitleaks (when on PATH — NEVER vendored) layers its default     ---
# --- ruleset on top via `gitleaks stdin`. Engine absent/disabled/errored =  ---
# --- fail-open to the floor with ONE debounced audit line.                  ---

# Path to the repo-level gitleaks config (shared with CI/manual scans).
secret_gitleaks_config() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || root="${CLAUDE_PROJECT_DIR:-.}"
  printf '%s/.gitleaks.toml' "$root"
}

# stdin -> gitleaks Secret strings, ONE PER LINE (multi-line PEM-class secrets are
# collapsed to a single \n-escaped line so the line-oriented comm/sort/grep set
# algebra downstream stays sound). rc 0 = engine ran (stdout = found secrets,
# possibly empty); rc 1 = engine unavailable/disabled/errored — the caller MUST
# fall back to the builtin floor.
secret_matches_gitleaks() {
  command -v gitleaks >/dev/null 2>&1 || return 1
  [ "$(cfg_flag WORKFLOW_SECRETS_GITLEAKS 1)" = "1" ] || return 1
  local cfg out rc=0
  cfg=$(secret_gitleaks_config)
  if [ -f "$cfg" ]; then
    out=$(gitleaks stdin --no-banner --log-level error --config "$cfg" \
          --exit-code 7 --report-format json --report-path /dev/stdout 2>/dev/null) || rc=$?
  else
    out=$(gitleaks stdin --no-banner --log-level error \
          --exit-code 7 --report-format json --report-path /dev/stdout 2>/dev/null) || rc=$?
  fi
  case "$rc" in
    0) return 0 ;;                                                          # engine ran, no leaks
    7) printf '%s\n' "$out" | jq -r '.[]?.Secret // empty | gsub("\n";"\\n")' 2>/dev/null | sed '/^$/d'; return 0 ;;  # leaks found
    *) return 1 ;;                                                          # config/runtime error -> caller falls back
  esac
}

# High tier for blocking gates: builtin floor + gitleaks layer.
secret_matches_blocking() {
  local text gl
  text=$(cat)
  printf '%s' "$text" | secret_matches_high
  if gl=$(printf '%s' "$text" | secret_matches_gitleaks); then
    [ -n "$gl" ] && printf '%s\n' "$gl"
  else
    wf_log_skip_debounced secret-engine-gitleaks engine_fallback_builtin
  fi
  return 0
}

# Print every match found in stdin, one per line (unsorted, may repeat). Union of
# the blocking tier (builtin floor + gitleaks layer) and the assignment heuristic —
# consumed by secrets-scan.sh's multiset delta. Callers sort/compare.
secret_matches() {
  local text
  text=$(cat)
  printf '%s' "$text" | secret_matches_blocking
  printf '%s' "$text" | secret_matches_heuristic
}

# Hooks that may never be disabled (security / non-negotiable enforcement).
HOOK_PINNED="secrets-scan forbidden-ai-attribution large-file-guard pre-push-secrets worktree-secrets-scan"

# HOOK_IDS — the live hook roster, derived from settings.json (the ownership oracle) at
# source time, so the roster is correct on ANY closure (self-host full tree AND light
# consumers alike; the 2026-07-02 canary showed a hardcoded roster drift-fails every
# non-self-host install). `check-symlinks` is the canonical-private self-host hook and is
# NOT part of the roster (same exclusion the status drift-test applies). FAIL-OPEN: if jq
# or settings.json is unavailable the roster is empty — status shows no per-hook verdicts
# and the unknown-token classifier treats every id as unknown; nothing blocks.
_HOOKLIB_SETTINGS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/settings.json"
HOOK_IDS="$(jq -r '.hooks|to_entries[].value[].hooks[].command' "$_HOOKLIB_SETTINGS" 2>/dev/null \
  | grep -oE '[a-z0-9-]+\.sh' | sed 's/\.sh$//' | grep -vx 'check-symlinks' | sort -u | tr '\n' ' ')"
# shellcheck disable=SC2086  # intentional word-split: emit one id per line
hook_ids() { printf '%s\n' $HOOK_IDS; }

# hook_enabled_quiet <id> — same verdict as hook_enabled but NEVER logs a skip (no audit side
# effect). Used by `status` to poll all ids without spamming the audit / skip-debounce markers.
hook_enabled_quiet() {
  local id="$1"
  case " $HOOK_PINNED " in *" $id "*) return 0 ;; esac
  case "$(printf '%s' "${WORKFLOW_HOOKS_OFF:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 1 ;;
  esac
  case ",${WORKFLOW_DISABLED_HOOKS:-}," in *",$id,"*) return 1 ;; esac
  return 0
}

# True unless the hook id is listed in WORKFLOW_DISABLED_HOOKS (comma-separated).
# Pinned hooks are always enabled regardless of the disable list.
hook_enabled() {
  local id="$1"
  case " $HOOK_PINNED " in *" $id "*) return 0 ;; esac           # pinned: always on
  case "$(printf '%s' "${WORKFLOW_HOOKS_OFF:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) wf_log_skip_debounced "$id"; return 1 ;;       # panic-off all non-pinned
  esac
  case ",${WORKFLOW_DISABLED_HOOKS:-}," in *",$id,"*) wf_log_skip_debounced "$id"; return 1 ;; esac
  return 0
}

# Echo the current workflow phase (empty if state missing/unreadable).
hook_phase() {
  local sf
  sf=$(state_file)
  [ -f "$sf" ] || return 0
  jq -r '.phase // empty' "$sf" 2>/dev/null || true
}

# Emit a non-blocking additionalContext envelope (warn-only hooks).
# Usage: emit_additional_context <PreToolUse|PostToolUse> "message"
# jq safely escapes the message; on any jq failure nothing is emitted (fail-open).
emit_additional_context() {
  jq -cn --arg e "$1" --arg c "$2" \
    '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}' 2>/dev/null || true
}


# --- F2 audit plumbing (extracted from context-exhaustion-gate/session-instincts, DUP-HR-2) ---

# safe_slug <raw> [fallback] : filesystem-safe slug — every byte outside A-Za-z0-9._- becomes
# '_'; empty input -> fallback (default 'nosession'). The canonical id normalizer.
safe_slug() {
  local out
  out=$(printf '%s' "${1:-}" | tr -c 'A-Za-z0-9._-' '_')
  [ -n "$out" ] || out="${2:-nosession}"
  printf '%s' "$out"
}
# wf_safe_id — back-compat alias delegating to safe_slug (output byte-identical; existing audit
# path/cache keys unchanged).
wf_safe_id() { safe_slug "$@"; }

# resolve_audit_path <session-id> : resolve WORKFLOW_AUDIT_PATH once per session and cache it
# in ${TMPDIR}/wf-ctx/<safe>.auditpath (a mid-session cwd change cannot split the audit).
# .planning repo -> <planning>/audit/phase4.jsonl ; else ${TMPDIR}/wf-audit/phase4.jsonl.
resolve_audit_path() {
  local safe ctxdir cache pdir
  safe=$(wf_safe_id "${1:-}")
  ctxdir="${TMPDIR:-/tmp}/wf-ctx"
  mkdir -p "$ctxdir" 2>/dev/null || true
  cache="${ctxdir}/${safe}.auditpath"
  if [ -s "$cache" ]; then
    WORKFLOW_AUDIT_PATH=$(cat "$cache" 2>/dev/null)
  else
    pdir=$(planning_dir 2>/dev/null) || pdir=''
    if [ -d "$pdir" ]; then
      WORKFLOW_AUDIT_PATH="${pdir}/audit/phase4.jsonl"
    else
      WORKFLOW_AUDIT_PATH="${TMPDIR:-/tmp}/wf-audit/phase4.jsonl"
    fi
    { printf '%s' "$WORKFLOW_AUDIT_PATH" > "$cache"; } 2>/dev/null || true
  fi
  export WORKFLOW_AUDIT_PATH
}

# audit_envelope <hook> <event> <result> <reason> [extra-json] [ts_ms] [decision_id]
# ONE canonical phase4.jsonl line (envelope: ts_ms, v:2, decision_id, hook, event, result,
# reason) with optional extra fields merged in. ts_ms/decision_id are overridable so domain
# emitters (audit_emit/audit_si) keep their exact historical values (incl. WORKFLOW_NOW_MS
# test seam). Fail-open: any jq failure -> no line, exit 0.
audit_envelope() {
  local hook="$1" event="$2" result="$3" reason="$4" extra="${5:-}" ts_ms="${6:-}" did="${7:-}" line
  if [ -z "$ts_ms" ]; then ts_ms=$(date +%s%3N 2>/dev/null) || ts_ms=0; fi
  case "$ts_ms" in ''|*[!0-9]*) ts_ms=0 ;; esac
  if [ -z "$did" ]; then
    did=$(printf '%s' "${hook}${ts_ms}${result}${reason}" | cksum 2>/dev/null | tr -d ' \t\n') || did=0
  fi
  [ -n "$did" ] || did=0
  [ -n "$extra" ] || extra='{}'
  line=$(jq -cn \
    --argjson ts_ms "$ts_ms" --arg did "$did" --arg hook "$hook" --arg event "$event" \
    --arg result "$result" --arg reason "$reason" --argjson extra "$extra" \
    '{ts_ms:$ts_ms, v:2, decision_id:$did, hook:$hook, event:$event, result:$result, reason:$reason} + $extra' \
    2>/dev/null) || return 0
  [ -n "$line" ] && audit_log "$line"
  return 0
}

# audit_emit_block <hook-id> <reason> [event] — ONE line to drop at every exit-2 site (D4-1).
# Self-resolves the audit path from $INPUT's session_id when the hook has not done so.
audit_emit_block() {
  [ -n "${WORKFLOW_AUDIT_PATH:-}" ] \
    || resolve_audit_path "$(printf '%s' "${INPUT:-}" | jq -r '.session_id // empty' 2>/dev/null)"
  audit_envelope "$1" "${3:-PreToolUse}" block "$2"
}

# audit_emit_warn <hook-id> <reason> [event] — same, for warn emissions.
audit_emit_warn() {
  [ -n "${WORKFLOW_AUDIT_PATH:-}" ] \
    || resolve_audit_path "$(printf '%s' "${INPUT:-}" | jq -r '.session_id // empty' 2>/dev/null)"
  audit_envelope "$1" "${3:-PreToolUse}" warn "$2"
}

# wf_log_skip_debounced <hook-id> : audit a hook_enabled()==false skip ONCE per hook per
# TMPDIR lifetime (marker file; reaped by wf_reaper alongside the wf-ctx caches). Fail-open.
wf_log_skip_debounced() {
  local id="$1" reason="${2:-disabled_by_env}" dir marker
  dir="${TMPDIR:-/tmp}/wf-ctx"
  marker="${dir}/skip-logged-${id}"
  [ -f "$marker" ] && return 0
  ( umask 077; mkdir -p "$dir" && : > "$marker" ) 2>/dev/null || return 0
  [ -n "${WORKFLOW_AUDIT_PATH:-}" ] \
    || resolve_audit_path "$(printf '%s' "${INPUT:-}" | jq -r '.session_id // empty' 2>/dev/null)"
  audit_envelope "$id" config skip "$reason"
  return 0
}

# wf_once <key> : rc 0 the FIRST call per session-scoped marker, rc 1 thereafter. Marker under
# ${TMPDIR}/wf-ctx/once-<safe>; reaped by wf_reaper. Session is keyed from $INPUT's session_id.
wf_once() {
  local key="$1" sid dir marker
  sid=$(printf '%s' "${INPUT:-}" | jq -r '.session_id // empty' 2>/dev/null)
  dir="${TMPDIR:-/tmp}/wf-ctx"
  marker="${dir}/once-$(safe_slug "${sid}_${key}")"
  [ -f "$marker" ] && return 1
  ( umask 077; mkdir -p "$dir" && : > "$marker" ) 2>/dev/null || return 1
  return 0
}

# audit_trim_value_aware <path> <max> : keep ALL signal lines (result != "none") plus the newest
# none lines up to <max>, preserving chronological order. Fail-open: any error -> plain tail -n max.
audit_trim_value_aware() {
  local path="$1" max="$2" sig tmp="$1.tmp.$$"
  sig=$(grep -vc '"result":"none"' "$path" 2>/dev/null) || { tail -n "$max" "$path" > "$tmp" 2>/dev/null && mv -f "$tmp" "$path" 2>/dev/null; return 0; }
  if [ "${sig:-0}" -ge "$max" ]; then
    tail -n "$max" "$path" > "$tmp" 2>/dev/null && mv -f "$tmp" "$path" 2>/dev/null; return 0
  fi
  if awk -v keep="$(( max - sig ))" '
    { lines[NR]=$0; isnone[NR]=($0 ~ /"result":"none"/)?1:0; if (isnone[NR]) nones++ }
    END { cut=nones-keep; c=0;
      for (i=1;i<=NR;i++){ if (isnone[i]){c++; if (c<=cut) continue} print lines[i] } }
  ' "$path" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$path" 2>/dev/null
  else
    # awk failed -> degrade to a plain tail rather than leave the file untrimmed (verifier V2).
    tail -n "$max" "$path" > "$tmp" 2>/dev/null && mv -f "$tmp" "$path" 2>/dev/null
  fi
  return 0
}

# audit_log <json-line> : append ONE <3500-byte JSON line to the per-session audit file.
# Path from WORKFLOW_AUDIT_PATH (resolved once per session by the caller). Append-only +
# lazy tail-trim when oversized (race-tolerant). umask 077 / chmod 700. Fail-open: any error
# is swallowed (exit 0). WORKFLOW_AUDIT=off disables.
audit_log() {
  [ "$(cfg_flag WORKFLOW_AUDIT 1)" = "1" ] || return 0
  local line="$1" path="${WORKFLOW_AUDIT_PATH:-}" dir max n
  [ -n "$path" ] || return 0
  [ "${#line}" -le 3500 ] || return 0
  dir="$(dirname "$path")"
  ( umask 077; mkdir -p "$dir" 2>/dev/null && chmod 700 "$dir" 2>/dev/null
    printf '%s\n' "$line" >> "$path" ) 2>/dev/null || return 0
  max="$(cfg_int WORKFLOW_AUDIT_MAX_LINES 2000 100 100000)"
  n="$(wc -l < "$path" 2>/dev/null)" || return 0
  if [ "${n:-0}" -gt $(( max + max / 4 )) ]; then
    audit_trim_value_aware "$path" "$max"
  fi
  return 0
}

# wf_reaper <dir> <glob> : delete dir/glob entries older than WORKFLOW_TMP_TTL_DAYS. Fail-open.
wf_reaper() {
  local dir="$1" glob="$2" ttl
  [ -d "$dir" ] || return 0
  ttl="$(cfg_int WORKFLOW_TMP_TTL_DAYS 7 1 365)"
  find "$dir" -maxdepth 1 -name "$glob" -mtime "+$ttl" -delete 2>/dev/null || true
  return 0
}

# --- F4 / D4-2: gate evidence. An append-only RAW OBSERVATION of acceptance-gate runs ---
# --- (no crypto, no attestation). Recorded by gate-evidence.sh; read by pre-push-contract ---
# --- and create-pr to stop laundering unverified gate_result self-report into checked claims. ---

# gate_cmd_kind <command> : echo the gate kind (test|lint|secrets) if the command is a
# recognized acceptance-gate run, else nothing. THE single source of "what counts as a gate" —
# extend here (one alternation) to teach the fabric a new gate command. Tool tokens are
# word-anchored (leading + trailing boundary) so substrings inside filenames/args
# (cat gitleaksconfig.toml, rm pytest_cache) do NOT match; git is never a gate (skipped up
# front) so a tool name inside `git commit -m "...pytest..."` is not misclassified. Residual
# limitation (documented, advisory-only): a compound like `cd x && pytest` is still matched
# (correct), and a gate word inside a NON-git compound could over-match — acceptable for an
# advisory recorder.
gate_cmd_kind() {
  local c="$1"
  case "$c" in git|git\ *) return 0 ;; esac
  if printf '%s' "$c" | grep -qE '(^|[;&|[:space:]])(shellcheck|golangci-lint)([[:space:]]|$)'; then echo lint; return 0; fi
  if printf '%s' "$c" | grep -qE '(^|[;&|[:space:]])gitleaks([[:space:]]|$)'; then echo secrets; return 0; fi
  if printf '%s' "$c" | grep -qE '(^|[;&|[:space:]])(make[[:space:]]+(hooks-test|integration-check|ci-scripts-test|ci-security-test|check-validator-drift|test)([[:space:]]|$)|bats([[:space:]]|$)|pytest([[:space:]]|$)|python[0-9]*[[:space:]]+-m[[:space:]]+pytest([[:space:]]|$)|go[[:space:]]+test([[:space:]]|$)|node[[:space:]]+--test([[:space:]]|$)|npm[[:space:]]+(test|run[[:space:]]+test)([[:space:]]|$)|pnpm[[:space:]]+(test|run[[:space:]]+test)([[:space:]]|$)|cargo[[:space:]]+test([[:space:]]|$)|bash[[:space:]]+[^[:space:]]*scripts/ci/|bash[[:space:]]+[^[:space:]]*tests?/[^[:space:]]*test-)'; then
    echo test; return 0
  fi
  return 0
}

# resolve_gate_status : read a tool_response JSON object on stdin; echo "<status>\t<exit>\t<src>"
# (TAB-separated) where status=pass|fail|unknown, exit=<int>|"" , src names the field that
# resolved it. Defensive across the undocumented Bash tool_response exit-code shape; records an
# honest "unknown" when indeterminate (NEVER coerces unknown to pass). Always rc 0.
resolve_gate_status() {
  local tr ec b out status="" exit_v="" src="none"
  tr=$(cat)
  ec=$(printf '%s' "$tr" | jq -r '(.exit_code // .exitCode // .returnCode // .code) | select(type=="number")' 2>/dev/null)
  if [ -n "$ec" ]; then
    exit_v="$ec"; src="exit_code"
    if [ "$ec" = "0" ]; then status="pass"; else status="fail"; fi
  fi
  if [ -z "$status" ]; then
    b=$(printf '%s' "$tr" | jq -r '
      if (.success|type)=="boolean" then (if .success then "pass:success" else "fail:success" end)
      elif (.is_error|type)=="boolean" and .is_error then "fail:is_error"
      elif (.isError|type)=="boolean" and .isError then "fail:isError"
      elif .interrupted==true then "fail:interrupted"
      else empty end' 2>/dev/null)
    if [ -n "$b" ]; then status="${b%%:*}"; src="${b#*:}"; fi
  fi
  if [ -z "$status" ]; then
    out=$(printf '%s' "$tr" | jq -r '[(.stdout//""),(.stderr//"")] | join("\n")' 2>/dev/null)
    # FAIL markers must require a NON-ZERO count or a colon/keyword form — a bare `failed`
    # alternative would match the " failed" inside the canonical pass summary "N passed, 0
    # failed" (verified defect). Fail is checked BEFORE pass so a genuine "3 passed, 2 failed"
    # ([1-9][0-9]* failed) resolves fail rather than mis-passing on "3 passed".
    if printf '%s' "$out" | grep -qiE '(^|[^a-z])([1-9][0-9]* (failed|errors?)|fail(ed|ure)?:|error:|not ok|panic:|traceback|exit (status|code) [1-9])'; then
      status="fail"; src="stderr_marker"
    elif printf '%s' "$out" | grep -qiE '([0-9]+ passed, 0 failed|all tests passed|results: [0-9]+ passed|(^|[^a-z])(ok|pass|passed)([^a-z]|$))'; then
      status="pass"; src="stdout_marker"
    fi
  fi
  [ -n "$status" ] || status="unknown"
  printf '%s\t%s\t%s\n' "$status" "$exit_v" "$src"
}

# gate_evidence_log <status> <exit> <kind> <cmd> <src> : append ONE JSONL observation to
# $(planning_dir)/gate-evidence.log. cmd is jq --arg-escaped (caller pre-truncates/sanitizes).
# WORKFLOW_GATE_EVIDENCE=off disables. Append-only + lazy tail-trim to WORKFLOW_AUDIT_MAX_LINES
# (shared observability-retention dial). File created under umask 077 (0600); the shared
# .planning dir perms are deliberately NOT tightened (unlike audit_log, whose subdir it owns).
# Fail-open: any error -> no line, rc 0.
gate_evidence_log() {
  [ "$(cfg_flag WORKFLOW_GATE_EVIDENCE 1)" = "1" ] || return 0
  local status="$1" exit_v="$2" kind="$3" cmd="$4" src="$5" path dir ts branch sha sess line max n
  path=$(gate_evidence_path 2>/dev/null) || return 0
  case "$path" in */gate-evidence.log) ;; *) return 0 ;; esac
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || ts=""
  branch=$(git branch --show-current 2>/dev/null || echo "")
  sha=$(git rev-parse --short HEAD 2>/dev/null || echo "")
  sess=$(wf_safe_id "$(printf '%s' "${INPUT:-}" | jq -r '.session_id // empty' 2>/dev/null)")
  # Normalize exit to a JSON-safe token: an integer (optionally signed) or null. NOTE the
  # negated class lists '-' FIRST (`[!-0-9]`) — hyphen last (after digits) is the banned buggy
  # glob that scripts/check-integration-phase4.sh greps for and rejects.
  case "$exit_v" in ''|*[!-0-9]*) exit_v="null" ;; esac
  line=$(jq -cn --arg ts "$ts" --arg status "$status" --argjson exit "$exit_v" \
    --arg kind "$kind" --arg cmd "$cmd" --arg src "$src" \
    --arg branch "$branch" --arg sha "$sha" --arg session "$sess" \
    '{v:2, ts:$ts, event:"gate-evidence", status:$status, exit:$exit, kind:$kind, cmd:$cmd, src:$src, branch:$branch, sha:$sha, session:$session}' 2>/dev/null) || return 0
  [ -n "$line" ] || return 0
  [ "${#line}" -le 3500 ] || return 0
  # Create the dir at the DEFAULT umask (do NOT tighten the shared .planning dir — unlike
  # audit_log, which owns its audit/ subdir). Only the evidence FILE is owner-only (umask 077
  # applies to the new file inside the subshell).
  dir=$(dirname "$path")
  mkdir -p "$dir" 2>/dev/null || return 0
  ( umask 077; printf '%s\n' "$line" >> "$path" ) 2>/dev/null || return 0
  max=$(cfg_int WORKFLOW_AUDIT_MAX_LINES 2000 100 100000)
  n=$(wc -l < "$path" 2>/dev/null) || return 0
  if [ "${n:-0}" -gt $(( max + max / 4 )) ]; then
    tail -n "$max" "$path" > "$path.tmp.$$" 2>/dev/null && mv -f "$path.tmp.$$" "$path" 2>/dev/null
  fi
  return 0
}

is_git_commit() { echo "$1" | grep -qE 'git\s+commit'; }
is_git_push()   { echo "$1" | grep -qE 'git\s+push'; }

# True if the command posts PR-thread text: gh pr comment/review, or gh api on a comments/reviews endpoint.
is_gh_pr_text() {
  echo "$1" | grep -qE 'gh[[:space:]]+pr[[:space:]]+(comment|review)\b' && return 0
  echo "$1" | grep -qE 'gh[[:space:]]+api[[:space:]]' && echo "$1" | grep -qE '/(comments|reviews)\b' && return 0
  return 1
}

# Canonical "what is being pushed" range (F3 / D1-2, DUP-7): ONE policy for every
# push-time hook. Chain: @{push} -> @{u} -> origin/<default branch> -> ''.
# The origin fallback makes a branch's FIRST push scannable (the old
# @{push}/@{upstream}-only chains silently skipped it — the standard feature-branch
# flow). Empty output = no origin baseline at all (brand-new repo); each caller
# applies its own empty-range policy. Always rc 0.
unpushed_range() {
  local base
  base=$(git rev-parse --abbrev-ref --symbolic-full-name '@{push}' 2>/dev/null) \
    || base=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) \
    || base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) \
    || base=""
  if [ -z "$base" ]; then
    if git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then base="origin/main"
    elif git rev-parse --verify --quiet origin/master >/dev/null 2>&1; then base="origin/master"
    fi
  fi
  [ -n "$base" ] && printf '%s..HEAD' "$base"
  return 0
}

# Echo public|private for the current repo (default private on any ambiguity).
# Resolution order (first hit wins): explicit env override -> in-repo passport
# (portable single-project layout) -> sibling workspace-meta/repos passport (multi-repo
# workspace) -> private. For workspace-meta the in-repo passport IS the sibling passport
# (repo root is named workspace-meta), so the result is unchanged.
repo_visibility() {
  local root repo passport
  case "$(printf '%s' "${WORKFLOW_REPO_VISIBILITY:-}" | tr '[:upper:]' '[:lower:]')" in
    public)  echo public;  return ;;
    private) echo private; return ;;
  esac
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo private; return; }
  repo=$(basename "$root")
  passport="${root}/repos/${repo}.md"
  [ -f "$passport" ] || passport="${root}/../workspace-meta/repos/${repo}.md"
  if grep -qiE '^visibility:[[:space:]]*public' "$passport" 2>/dev/null; then
    echo public
  else
    echo private
  fi
}

# True if a .ai-mentions-allowed marker exists at the repo root.
ai_mentions_allowed() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -f "${root}/.ai-mentions-allowed" ]
}

# True if text carries explicit AI attribution (blocked in ALL repos).
# Name list broadened (F3 / D1-5); the anthropic-noreply trailer is caught
# regardless of display name. `gh pr create` bodies stay out of scope by
# accepted decision — see forbidden-ai-attribution.sh header.
is_ai_attribution() {
  echo "$1" | grep -qiP 'Co-Authored-By:.*\b(Claude|GPT|Copilot|Anthropic|OpenAI|Gemini|Codex|Cursor|Devin|Aider|Windsurf|Grok|Llama|Mistral|Cohere|DeepSeek|Qwen)\b' && return 0
  echo "$1" | grep -qiP 'Co-Authored-By:.*noreply@anthropic\.com' && return 0
  echo "$1" | grep -qiP '(Generated|Built|Created|Written|Assisted)\s+(by|with|using)\s+\[?(Claude|GPT|AI|Copilot|Anthropic|OpenAI|Gemini|Codex|Cursor|Devin|Aider)' && return 0
  return 1
}

# True if text carries an attribution-shaped AI hint (blocked only in PUBLIC repos).
# Deliberately does NOT match the bare word "Claude" (legitimate in dotfiles config).
is_ai_hint() {
  echo "$1" | grep -qiP '🤖|AI[- ]generated|AI[- ]assisted|Generated with \[?(Claude|GPT|Copilot|Codex)' && return 0
  return 1
}

# hook_unknown_disabled — WORKFLOW_DISABLED_HOOKS ids that match NO known hook (typo detector).
hook_unknown_disabled() {
  local tok out=""; local IFS=','
  for tok in ${WORKFLOW_DISABLED_HOOKS:-}; do
    [ -n "$tok" ] || continue
    case " $HOOK_IDS " in *" $tok "*) ;; *) out="$out $tok" ;; esac
  done
  printf '%s' "${out# }"
}

# status — human-readable workflow/enforcement snapshot (D4-6). Read-only, fail-open: prints
# n/a for absent state, never errors, exits 0. Composes existing accessors only.
status() {
  local sf rf lp phase branch started v_branch v_verdict v_range v_head cur_head cur_branch fresh id
  sf=$(state_file 2>/dev/null) || sf=''
  echo "workflow-meta status"
  echo "===================="
  if [ -n "$sf" ] && [ -f "$sf" ]; then
    phase=$(jq -r '.phase // "n/a"' "$sf" 2>/dev/null); branch=$(jq -r '.branch // "n/a"' "$sf" 2>/dev/null)
    started=$(jq -r '.started_at // "n/a"' "$sf" 2>/dev/null)
  else phase="n/a"; branch="n/a"; started="n/a"; fi
  echo "phase:      $phase"
  echo "branch:     $branch (git: $(git branch --show-current 2>/dev/null || echo n/a))"
  echo "started_at: $started"
  lp=$(ledger_path 2>/dev/null) || lp=''
  # Pass an explicit path arg so shellcheck sees ledger_stats/ledger_rows called WITH args in-file
  # (avoids SC2119/SC2120 — these helpers are otherwise only ever called with args from other files).
  echo "ledger:     $(ledger_stats "$lp" 2>/dev/null || echo 'kept=0 discarded=0 dead-end=0')  rows=$(ledger_rows "$lp" 2>/dev/null || echo 0)"
  if [ -n "$lp" ] && [ -f "$lp" ]; then
    echo "last row:   $(awk -F'\t' 'NF==5 && NR>1{r=$0} END{print (r==""?"(none)":r)}' "$lp" 2>/dev/null)"
  else echo "last row:   n/a"; fi
  rf=$(review_state_file 2>/dev/null) || rf=''
  if [ -n "$rf" ] && [ -f "$rf" ]; then
    v_branch=$(jq -r '.branch // "n/a"' "$rf" 2>/dev/null); v_verdict=$(jq -r '.verdict // "n/a"' "$rf" 2>/dev/null)
    v_range=$(jq -r '.sha_range // ""' "$rf" 2>/dev/null); v_head="${v_range##*..}"
    cur_head=$(git rev-parse HEAD 2>/dev/null || echo ''); cur_branch=$(git branch --show-current 2>/dev/null || echo '')
    if [ -n "$v_head" ] && [ "$v_head" = "$cur_head" ] && [ "$v_branch" = "$cur_branch" ]; then fresh="fresh"; else fresh="STALE (review head/branch != current HEAD/branch)"; fi
    echo "review:     $v_verdict  branch=$v_branch  sha_range=$v_range  -> $fresh"
  else echo "review:     n/a"; fi
  echo "hooks:"
  for id in $(hook_ids); do
    if hook_enabled_quiet "$id"; then echo "  enabled   $id"; else echo "  disabled  $id"; fi
  done
  # Surface WORKFLOW_DISABLED_HOOKS tokens that match no known hook id (typos).
  local unknown; unknown=$(hook_unknown_disabled 2>/dev/null)
  [ -n "$unknown" ] && echo "unknown disabled ids (typos?): $unknown"
  return 0
}

# CLI dispatch so the markdown create-pr skill can call e.g. `bash hooklib.sh ledger_path`.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  "$@"
fi
