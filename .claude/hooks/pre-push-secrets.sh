#!/usr/bin/env bash
# PreToolUse hook: full-file secret scan of files changed by a git push.
# HIGH tier = builtin patterns per file (attributed) + ONE batched gitleaks pass
# over all candidate files (F3/D5-1; engine absent/error = floor only, audited).
# High-tier matches BLOCK (exit 2); assignment-heuristic matches warn only (D2-2).
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
hook_enabled "pre-push-secrets" || exit 0   # pinned: always true
hook_read_input
[ "$TOOL_NAME" != "Bash" ] && exit 0
command=$(hook_command)
is_git_push "$command" || exit 0

# Canonical pushed range (F3): @{push} -> @{u} -> origin/<default> -> '' (skip —
# no origin baseline at all). Assumes cwd == the repo being pushed; `git -C` /
# `cd X && git push` compound forms are out of scope (D1-1, accepted).
range=$(unpushed_range)
[ -z "$range" ] && exit 0

blocked=0
warned=0
candidates=()
while IFS= read -r f; do
  [ -f "$f" ] || continue                              # deleted in range
  case "$f" in .claude/hooks/tests/*) continue ;; esac # scanner fixtures by design
  [ "$(wc -c < "$f")" -gt 1048576 ] && continue        # >1MB: skip
  grep -Iq '' "$f" || continue                         # binary or empty: skip
  candidates+=("$f")
  hi=$(secret_matches_high < "$f" | sort -u | head -5)
  if [ -n "$hi" ]; then
    if [ "$blocked" -eq 0 ]; then
      echo "[BLOCKED] full-file secret scan ($range) found HIGH-CONFIDENCE matches:"
      blocked=1
    fi
    echo "  $f:"
    echo "    ${hi//$'\n'/$'\n'    }"
    continue
  fi
  heur=$(secret_matches_heuristic < "$f" | sort -u | head -5)
  if [ -n "$heur" ]; then
    if [ "$warned" -eq 0 ]; then
      echo "WARNING: full-file secret scan ($range) found heuristic matches:"
      warned=1
    fi
    echo "  $f:"
    echo "    ${heur//$'\n'/$'\n'    }"
  fi
done < <(git diff --name-only "$range" 2>/dev/null)

# Batched gitleaks layer (F3/D5-1): one engine pass over every candidate file;
# catches classes the builtin floor misses. Floor findings above already printed —
# only NET-extra engine findings are reported here (best-effort file attribution).
if [ "${#candidates[@]}" -gt 0 ]; then
  if gl=$(cat "${candidates[@]}" 2>/dev/null | secret_matches_gitleaks); then
    if [ -n "$gl" ]; then
      floor_all=$(cat "${candidates[@]}" 2>/dev/null | secret_matches_high | sort -u)
      while IFS= read -r s; do
        [ -n "$s" ] || continue
        [ -n "$floor_all" ] && printf '%s\n' "$floor_all" | grep -qF -- "$s" && continue
        if [ "$blocked" -eq 0 ]; then
          echo "[BLOCKED] gitleaks layer ($range) found additional matches:"
          blocked=1
        fi
        hit=$(grep -lF -- "$s" "${candidates[@]}" 2>/dev/null | head -3 | tr '\n' ' ')
        echo "  ${hit:-(multi-line match)}: ${s:0:60}"
      done <<< "$gl"
    fi
  else
    wf_log_skip_debounced secret-engine-gitleaks engine_fallback_builtin
  fi
fi

if [ "$blocked" -eq 1 ]; then
  echo "Purge before push (already-committed secrets need a history rewrite + rotation)."
  audit_emit_block pre-push-secrets high_confidence_secret
  exit 2
fi
if [ "$warned" -eq 1 ]; then
  echo "If real: purge before push (already-committed secrets need a history rewrite + rotation)."
  audit_emit_warn pre-push-secrets heuristic_secret
fi
exit 0
