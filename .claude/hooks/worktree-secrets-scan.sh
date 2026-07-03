#!/usr/bin/env bash
# PostToolUse(Bash) hook: working-tree delta secret scan (F3 / D1-3). File writes
# routed through Bash (printf > f, tee, sed -i, python -c ...) bypass the Edit/Write
# secrets-scan veto; this hook closes the hole by scanning working-tree files that
# changed AFTER the session baseline and blocking (exit 2 — the write already
# happened; the agent must remediate before commit) on matches that are net-new
# relative to the file's HEAD version (multiset diff, same idiom as secrets-scan.sh).
# First run per repo per TMPDIR snapshots (mtime-size) of every already-dirty file
# WITHOUT scanning: pre-existing worktree state is push-gate territory
# (pre-push-secrets); this hook polices only what THIS session writes.
# Accepted gaps (by design): pre-existing untracked secrets are caught at push, not
# here; same-second same-size rewrites keep their signature; cwd is assumed to be
# the repo being worked on (D1-1). Layering over one perfect interceptor:
# pre-Edit veto + this working-tree scan + push-range scan.
# shellcheck source=lib/hooklib.sh
source "$(dirname "$0")/lib/hooklib.sh"
hook_enabled "worktree-secrets-scan" || exit 0   # pinned: always true
hook_read_input
[ "$TOOL_NAME" != "Bash" ] && exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
# git status emits ROOT-relative paths — resolve them from the root, not from
# whatever subdirectory the session happens to be in (otherwise every changed
# file silently fails [ -f ] and the D1-3 hole stays open).
cd "$root" || exit 0

cache_dir="${TMPDIR:-/tmp}/wf-ctx/wt-scan-$(wf_safe_id "$root")"
baseline_marker="$cache_dir/.baseline-done"
mkdir -p "$cache_dir" 2>/dev/null || exit 0
first_run=0
[ -f "$baseline_marker" ] || first_run=1

sig_of()      { stat -c '%Y-%s' -- "$1" 2>/dev/null || echo missing; }
sig_file_of() { printf '%s/%s.sig' "$cache_dir" "$(printf '%s' "$1" | cksum | tr -d ' \t')"; }

blocked_report=""
batch_files=()
skip_next=0
while IFS= read -r -d '' entry; do
  # -z rename/copy records emit the ORIGIN path as a bare second record — skip it.
  if [ "$skip_next" -eq 1 ]; then skip_next=0; continue; fi
  st="${entry:0:2}"; f="${entry:3}"
  case "$st" in R*|C*) skip_next=1 ;; esac
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  case "$f" in .claude/hooks/tests/*|scripts/ci/tests/*|.planning/audit/*) continue ;; esac
  sig=$(sig_of "$f"); sf=$(sig_file_of "$f")
  [ -f "$sf" ] && [ "$(cat "$sf" 2>/dev/null)" = "$sig" ] && continue   # unchanged since last scan
  if [ "$first_run" -eq 1 ]; then printf '%s' "$sig" > "$sf" 2>/dev/null; continue; fi
  if [ "$(wc -c < "$f")" -gt 1048576 ] || ! grep -Iq '' "$f"; then      # >1MB / binary / empty
    printf '%s' "$sig" > "$sf" 2>/dev/null; continue
  fi
  pre=$(git show "HEAD:$f" 2>/dev/null) || pre=""
  new=$(comm -13 <(printf '%s' "$pre" | secret_matches_high | sort) \
                 <(secret_matches_high < "$f" | sort) | sed '/^$/d' | sort -u | head -5)
  if [ -n "$new" ]; then
    blocked_report+="  $f:"$'\n'"    ${new//$'\n'/$'\n'    }"$'\n'
  else
    batch_files+=("$f")
    printf '%s' "$sig" > "$sf" 2>/dev/null
  fi
done < <(git status --porcelain=v1 -z -uall 2>/dev/null)

if [ "$first_run" -eq 1 ]; then
  : > "$baseline_marker" 2>/dev/null
  exit 0
fi

# Batched gitleaks layer (F3/D5-1): ONE pre-image pass + ONE post-image pass over
# the floor-clean changed files; net-new engine findings block. Engine
# absent/disabled/errored = floor only (debounced audit line).
if [ "${#batch_files[@]}" -gt 0 ]; then
  post_concat=$(cat "${batch_files[@]}" 2>/dev/null)
  pre_concat=""
  for f in "${batch_files[@]}"; do
    pre_concat+=$(git show "HEAD:$f" 2>/dev/null || true)
    pre_concat+=$'\n'
  done
  if pre_gl=$(printf '%s' "$pre_concat" | secret_matches_gitleaks) \
     && post_gl=$(printf '%s' "$post_concat" | secret_matches_gitleaks); then
    net_gl=$(comm -13 <(printf '%s\n' "$pre_gl" | sort) <(printf '%s\n' "$post_gl" | sort) \
             | sed '/^$/d' | sort -u | head -5)
    if [ -n "$net_gl" ]; then
      for f in "${batch_files[@]}"; do rm -f "$(sig_file_of "$f")"; done   # re-scan until remediated
      blocked_report+="  (gitleaks layer):"$'\n'"    ${net_gl//$'\n'/$'\n'    }"$'\n'
    fi
  else
    wf_log_skip_debounced secret-engine-gitleaks engine_fallback_builtin
  fi
fi

if [ -n "$blocked_report" ]; then
  {
    echo "[BLOCKED] Bash-written working-tree changes contain net-new secret matches:"
    printf '%s' "$blocked_report"
    echo "Remove or neutralize before committing (fixtures: use the token-split idiom)."
  } >&2
  audit_emit_block worktree-secrets-scan bash_written_secret PostToolUse
  exit 2
fi
exit 0
