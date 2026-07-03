Single source of truth for hook configuration knobs — Phase-4 session/context health AND the Phase-3 enforcement-floor guards (bounded-surface, tool-loop). Edited together with the hooks; drift is gated by scripts/check-integration-phase4.sh.

---

## Full schema — `WORKFLOW_*` configuration knobs

Every knob read by a Phase-4 hook, a Phase-3 floor guard (bounded-surface-guard, tool-loop-guard),
or by hooklib on their behalf is listed here. `check-integration-phase4.sh` asserts both
directions: every knob read in those hooks must have a row here, and every row here must be
read in a hook (config-read lines only — lines matching `cfg_int|cfg_flag|\${?WORKFLOW`;
message-text and comment mentions never trip the check).

| Env var | Default | Type | Valid range | On bad input | Hook | Failure-mode |
|---|---|---|---|---|---|---|
| `WORKFLOW_CTX_SOFT_PCT` | `35` | int (% remaining) | `2..99` and `> hard` | → default 35 | context-exhaustion-gate (B3) | fail-open |
| `WORKFLOW_CTX_HARD_PCT` | `25` | int (% remaining) | `1..98` and `< soft` | → default 25 | context-exhaustion-gate (B3) | fail-open |
| `WORKFLOW_CTX_STALE_MS` | `300000` | int (ms) | `1000..3600000` | → default 300000 | context-exhaustion-gate (B3) | fail-open |
| `WORKFLOW_CTX_DEADBAND_PCT` | `3` | int (% pts) | `0..20` | → default 3 | context-exhaustion-gate (B3) | fail-open |
| `WORKFLOW_CTX_COOLDOWN_MS` | `120000` | int (ms) | `0..3600000` | → default 120000 | context-exhaustion-gate (B3) | fail-open |
| `WORKFLOW_CTX_MAX_WARNS_PER_BAND` | `3` | int (count) | `1..50` | → default 3 | context-exhaustion-gate (B3) | fail-open |
| `WORKFLOW_CTX_HARD_REASSERT_CALLS` | `8` | int (tool calls) | `1..1000` | → default 8 | context-exhaustion-gate (B3) | fail-open |
| `WORKFLOW_INSTINCTS_MAX_AGE_DAYS` | `30` | int (days) | `1..3650` | → default 30 | session-instincts | fail-open |
| `WORKFLOW_INSTINCTS_TOP_N` | `2` | int (count) | `1..10` | → default 2 | session-instincts | fail-open |
| `WORKFLOW_INSTINCTS_CHAR_CAP` | `1800` | int (chars/bytes) | `200..20000` | → default 1800 | session-instincts | fail-open |
| `WORKFLOW_INSTINCTS_ITEM_CAP` | `900` | int (chars/bytes) | `100..20000` then cross-clamped to `min(item_cap, char_cap)` | → default 900 | session-instincts | fail-open |
| `WORKFLOW_INSTINCTS_MAX_CANDIDATES` | `50` | int (files) | `1..1000` | → default 50 | session-instincts | fail-open |
| `WORKFLOW_INSTINCTS_DEDUP_PCT` | `60` | int (Jaccard %) | `0..100` | → default 60 | session-instincts | fail-open |
| `WORKFLOW_INSTINCTS_MEMDIR` | (computed — walk-up ancestor resolution) | path | any readable dir; its `realpath` becomes the containment root | → computed default | session-instincts | fail-open |
| `WORKFLOW_INSTINCTS_SKIP_RESUME` | `0` | flag | `0/1` (off/false/no → 0; on/true/yes → 1) | → default 0 | session-instincts | fail-open |
| `WORKFLOW_INSTINCTS_DRYRUN` | `0` | flag | `0/1` | → default 0 | session-instincts only | fail-open |
| `WORKFLOW_TMP_TTL_DAYS` | `7` | int (days) | `1..365` | → default 7 | session-instincts + bounded-surface/tool-loop reapers (hooklib) | fail-open |
| `WORKFLOW_NOW_MS` | (unset — wall clock) | int (ms epoch) | `0..` (test seam only) | unset = `date +%s%3N` | context-exhaustion-gate (B3) | fail-open |
| `WORKFLOW_AUDIT` | `on` | flag | on/off | → default on | both (hooklib `audit_log`) | fail-open |
| `WORKFLOW_AUDIT_MAX_LINES` | `2000` | int (lines) | `100..100000` | → default 2000 | both (hooklib `audit_log`) | fail-open |
| `WORKFLOW_SECRETS_GITLEAKS` | `1` | flag | `0/1` (off/false/no → 0; on/true/yes → 1) | → default 1 | hooklib secret engine (secrets-scan, pre-push-secrets, worktree-secrets-scan) | fail-open to builtin floor |
| `WORKFLOW_GATE_EVIDENCE` | `1` | flag | `0/1` (off/false/no → 0; on/true/yes → 1) | → default 1 | hooklib gate-evidence engine (gate-evidence) | fail-open (recorder, never blocks) |
| `WORKFLOW_DISABLED_HOOKS` | (empty) | comma-separated hook ids | hook ids matching the `hook_enabled` id argument | unmatched ids ignored (but surfaced by the session-start diagnosis notice + make wf-status) | global — hooklib `hook_enabled` (Phase 1) | n/a |
| `WORKFLOW_HOOKS_OFF` | (unset) | flag | truthy set: `1`, `true`, `yes`, `on` (case-insensitive) | unset/other = inactive | global — hooklib `hook_enabled` (panic switch) | n/a |
| `WORKFLOW_SURFACE_MAX` | `4` | int (distinct files) | `1..100` | → default 4 | bounded-surface-guard (Phase 3) | warn-only |
| `WORKFLOW_LOOP_THRESHOLD` | `5` | int (repeat count) | `2..1000` | → default 5 | tool-loop-guard (Phase 3) | warn-only |
| `WORKFLOW_LOOP_WINDOW` | `20` | int (tool uses) | `1..1000` | → default 20 | tool-loop-guard (Phase 3) | warn-only |

`WORKFLOW_SECRETS_GITLEAKS` adds one `gitleaks stdin` spawn (~0.6s) per engine call — the Edit/Write veto pays it twice (pre+post delta, ~1.3s per edit); push and worktree hooks batch to one spawn. `off` restores floor-only speed.

`WORKFLOW_GATE_EVIDENCE=off` disables the append-only acceptance-gate observation log (`.planning/gate-evidence.log`, written by `gate-evidence.sh` via hooklib's `gate_evidence_log`); the log reuses `WORKFLOW_AUDIT_MAX_LINES` for its rolling tail-trim. It is advisory observability only — disabling it never affects any gate.

**Char/byte counting:** `WORKFLOW_INSTINCTS_CHAR_CAP` and `WORKFLOW_INSTINCTS_ITEM_CAP` are
counted as **bytes** (not Unicode codepoints) via `LC_ALL=C ${#var}` throughout, so they are
also the read-cap (`head -c 2*char_cap`) applied per candidate file.

---

## Precedence (highest wins)

```
HOOK_PINNED (always on)
  > WORKFLOW_HOOKS_OFF truthy (panic-off — silences all non-pinned hooks; every non-pinned hook calls hook_enabled, asserted by check-integration-phase4.sh)
    > WORKFLOW_DISABLED_HOOKS per-id (disable one hook by id)
      > per-feature toggle (WORKFLOW_INSTINCTS_DRYRUN suppresses injection but is NOT a disable;
        it is scoped to session-instincts only — B3 ignores it; silence B3 via disable/panic)
        > default-on
```

`WORKFLOW_*` config value precedence: **validated env var > documented default**.
No file-based or per-repo override store — only environment variables.

`hook_enabled` evaluation order (verbatim from hooklib):

1. If `id` is in `$HOOK_PINNED` → always on (return 0), no further checks.
2. If `WORKFLOW_HOOKS_OFF` lowercased is in `{1,true,yes,on}` → all non-pinned off (return 1).
3. If `id` is in `WORKFLOW_DISABLED_HOOKS` (comma-separated) → off (return 1).
4. Otherwise → on (return 0).

---

## Dependencies & failure semantics (F2)

Every hook needs **jq** to parse its stdin payload. `hook_read_input` probes jq on every
invocation (`printf '{}' | jq -e .`):

| jq state | Hook in `HOOK_FAILCLOSED` | Any other hook |
|---|---|---|
| working | normal operation | normal operation |
| missing/broken | **fails CLOSED**: `[BLOCKED] … jq is missing or broken` + exit 2 | fails OPEN: no-op + ONE loud stderr line (`jq missing/broken — degraded to no-op`) |

`HOOK_FAILCLOSED` = `secrets-scan forbidden-ai-attribution config-protection merge-gate
pre-push-secrets worktree-secrets-scan` — exactly the gates that block (exit 2) on real violations. It is
**orthogonal** to `HOOK_PINNED` (= cannot be disabled by env): large-file-guard is pinned
but warn-only → fail-open; config-protection/merge-gate are unpinned but blocking →
fail-closed. Consequence by design: while jq is broken, Bash/Edit/Write mutations are
blocked with a clear message — fix jq rather than work unscanned.

Other interpreter dependencies in the same fail-open class (documented, not gated here):

| Dependency | Consumer | Side | Failure looks like |
|---|---|---|---|
| node | `statusline.js` (statusline + ctx snapshots) | session | statusline empty; B3 gets no `claude-ctx-*.json` → audit `skip/missing`; no enforcement impact |
| python3 | settings.json inline graphify-hint hook; `check-integration-serena.sh`; `refresh-plugins-pin.sh` | session + CI | hint hook degrades silently (`\|\| true`); integration checks fail LOUDLY in `make integration-check`/CI |
| uv | workflow-graph extractor (`make workflow-graph`) | dev + CI | build/freshness gate fails loudly — nothing silent |
| dot (graphviz) | factory-map render | dev | `make`/render fails loudly — nothing silent |

---

## Hard-coded weights note

The instinct ranking weights are **hard-coded constants in `session-instincts.sh`**, NOT env knobs:

```
W_BRANCH=40   W_REPO=25   W_PATH=15
```

A ranking change is a code edit + LEDGER row, not a config change.  Rationale: per-weight env
vars are tuning no operator sets by hand; making them env knobs would add four drift-check rows
for zero practical benefit.  `W_KEYWORD*` was removed entirely when IDF scoring was cut (IDF is
degenerate at N=3 and non-deterministic on mawk).

---

## Audit-line field schemas

Both hooks write one JSON line per decision-relevant evaluation to the Phase-4 audit log
(`$(planning_dir)/audit/phase4.jsonl` when `.planning` exists, else
`${TMPDIR:-/tmp}/wf-audit/phase4.jsonl`).  The path is resolved once per session (on first
write) and cached in `${TMPDIR}/wf-ctx/<safe-session>.auditpath` so a mid-session cwd change
cannot split one session's audit.  Dir created with `mkdir -p` + `chmod 700`; files written
under `umask 077`.

### B3 audit line (§B3.6) — `context-exhaustion-gate`

| Field | Type | Notes |
|---|---|---|
| `ts_ms` | int | wall-clock ms at decision time |
| `v` | literal `2` | schema version |
| `decision_id` | string | cksum of `session_id + ts_ms + result` |
| `session` | string | sanitized session id (`wf_safe_id`) |
| `hook` | string | `"context-exhaustion-gate"` |
| `event` | string | `"PostToolUse"` |
| `result` | enum | `soft \| hard \| hard_reassert \| degraded \| skip \| none` |
| `reason` | string | free-form reason tag (e.g. `missing`, `stale age=<n>ms last_r=<r>`, `malformed`, `session_mismatch`, `bad_value`, `threshold_order`, `ok`, `deadband_hold`, `hard_suppressed`, `soft_suppressed`, `stale_degraded_emit`, `hard_reassert`, `hard_to_soft`, `hard_deadband_hold`) |
| `config_snapshot` | object | `{soft, hard, stale_ms, cooldown_ms, deadband, max_warns, reassert}` — resolved values at decision time |
| `remaining` | int | `remaining_percentage` from the ctx file (0 on non-match) |
| `bytes_injected` | int | **always present**; 0 on non-inject decisions |
| `historical` | literal `false` | distinguishes B3 lines from instincts lines |

`result` enum semantics:
- `soft` — soft-tier message emitted
- `hard` — hard-tier verbose body emitted (first cross or permitted re-warn)
- `hard_reassert` — condensed anti-autonomy safety line emitted (periodic; never debounced)
- `degraded` — stale-but-low reading; emitted with age qualifier
- `skip` — no emission (absent/stale/malformed/mismatch); `reason` carries the taxonomy tag
- `none` — band transition with no emission (healthy, deadband hold, suppressed re-warn)

As of v2, the per-PostToolUse `none`/`healthy` line is not logged (D4-4); band-activity `none` lines remain. `audit_log` trims value-aware — non-`none` lines are never evicted by healthy-noise overflow.

### Instincts audit line (§I.6) — `session-instincts`

| Field | Type | Notes |
|---|---|---|
| `ts_ms` | int | wall-clock ms at decision time |
| `v` | literal `2` | schema version |
| `decision_id` | string | cksum of `session_id + ts_ms + result` |
| `session` | string | sanitized session id (`wf_safe_id`) |
| `hook` | string | `"session-instincts"` |
| `event` | string | `"SessionStart"` |
| `result` | enum | `injected \| skipped \| dryrun` |
| `reason` | string | free-form reason tag (e.g. `injected`, `source_compact`, `source_resume_skip`, `no_dir`, `no_files`, `no_worktree_match`, `all_pruned`, `dedup_dropped=<name>`, `post_assembly_marker_collision`, `no_delimiter_entropy`, `emit_failed`, `dryrun`, `unknown_source_proceed`) |
| `source` | string | raw `.source` field from SessionStart stdin |
| `resolved_memdir` | string | absolute path of the resolved memory directory |
| `candidates` | int | total `*.md` files found (before eligibility filtering) |
| `eligible` | int | count of files that passed the structural-signal + age gate |
| `selected` | array of strings | relpaths of files actually injected |
| `bytes_injected` | int | **always present**; 0 on non-inject decisions |
| `truncated` | bool | true if any per-item or overall budget truncation occurred |
| `historical` | literal `true` | marks this as an instincts injection line |
| `config_snapshot` | object | `{char_cap, item_cap, top_n, max_candidates, max_age_days, dedup_pct}` — resolved values |

`result` enum semantics:
- `injected` — one `additionalContext` block emitted successfully
- `skipped` — no injection; `reason` carries the taxonomy tag
- `dryrun` — `WORKFLOW_INSTINCTS_DRYRUN=1`; full scoring table written to stderr, nothing injected

`bytes_injected` is always present in both schemas (value `0` on all non-inject results).

---

## Operational runbook (§(e))

**Disable one hook:**
> Set these in the environment that LAUNCHES the session (or settings.json `env`) — e.g.
> `export WORKFLOW_DISABLED_HOOKS=merge-gate` before starting Claude Code. A per-command
> inline prefix (`WORKFLOW_DISABLED_HOOKS=x <bash command>`) does NOT reach the hook: the
> harness spawns the hook with its own env, before your Bash command runs.
```
WORKFLOW_DISABLED_HOOKS=session-instincts          # silence instincts only
WORKFLOW_DISABLED_HOOKS=context-exhaustion-gate    # silence B3 only
WORKFLOW_DISABLED_HOOKS=session-instincts,context-exhaustion-gate   # both
```

**Panic-off all non-pinned hooks:**
> Same scoping: `export` it in the launching env (or settings.json `env`) before starting
> Claude Code — a per-command inline prefix does NOT reach the hook.
```
WORKFLOW_HOOKS_OFF=1    # also accepts: true  yes  on  (case-insensitive)
```
Pinned security hooks (`HOOK_PINNED`) remain active by design — they are not affected by the
panic switch.

**Dry-run instincts** (full scoring table to stderr, empty stdout, audit `result=dryrun`):
```bash
echo '{"source":"startup","cwd":"'"$PWD"'"}' \
  | WORKFLOW_INSTINCTS_DRYRUN=1 bash .claude/hooks/session-instincts.sh
```
Prints resolved `MEMDIR`, every candidate with its signal values (`S_branch`/`S_repo`/`S_path`),
`RAW`, recency factor, `FINAL`, eligible/pruned + reason, and confidence tier.
`WORKFLOW_INSTINCTS_DRYRUN` is **instincts-only** — B3 ignores it.  To silence B3 use
`WORKFLOW_DISABLED_HOOKS=context-exhaustion-gate` or the panic switch.

**Inspect B3 live state:**
```bash
cat "${TMPDIR:-/tmp}/claude-ctx-<session>.json"   # producer's ctx snapshot
```
Shows `remaining_percentage` and `ts` (epoch ms) that B3 reads on the next PostToolUse.

**Where logs live (one path per session, resolved once):**
```
$(planning_dir)/audit/phase4.jsonl      # when .planning/ exists
${TMPDIR:-/tmp}/wf-audit/phase4.jsonl  # fallback
```

**Diagnose "a hook didn't fire":**
When `WORKFLOW_HOOKS_OFF` is truthy or `WORKFLOW_DISABLED_HOOKS` is non-empty, `session-instincts`
prints ONE stderr line at session start naming the active suppression and any disabled id that
matches no known hook (typo). To replay any hook by hand and read its exit code:
```bash
echo '<representative stdin payload>' | bash .claude/hooks/<hook>.sh; echo "exit=$?"
# e.g. a SessionStart payload:
echo '{"source":"startup","cwd":"'"$PWD"'"}' | bash .claude/hooks/session-instincts.sh; echo "exit=$?"
```
`make wf-status` also lists every hook's enabled/disabled verdict and unknown disabled ids.

**Inspect workflow status:**
```bash
make wf-status          # or: bash .claude/hooks/lib/hooklib.sh status
```
Prints the current phase/branch/started_at, the LEDGER kept/discarded/dead-end tally + last row,
the recorded review verdict with a `fresh`/`STALE` flag (stale = review head or branch no longer
matches the current HEAD/branch), and the enabled/disabled verdict for every hook id under the
current env — plus any `WORKFLOW_DISABLED_HOOKS` token that matches no known hook (typo). Read-only.
See the precedence rules above for what drives each verdict.

Query examples:
```bash
# All B3 decisions
jq -c 'select(.hook=="context-exhaustion-gate")' .planning/audit/phase4.jsonl
# Non-none B3 results (actual emits and skips with reasons)
jq 'select(.hook=="context-exhaustion-gate" and .result!="none")' .planning/audit/phase4.jsonl
# All instincts injections
jq 'select(.hook=="session-instincts" and .result=="injected")' .planning/audit/phase4.jsonl
# Debug why a memory was / was not surfaced
jq 'select(.hook=="session-instincts")' .planning/audit/phase4.jsonl
```

**Debug why a memory was surfaced (or wasn't):**
Run `WORKFLOW_INSTINCTS_DRYRUN=1` (see above) — prints every candidate's score and the reason
for eligible/pruned.  The provenance line inside a live injection also states signals, score,
age, and confidence at point-of-use.

**Tune thresholds:**
Export the relevant `WORKFLOW_*` env var before launching the harness.  Bad values (garbage,
out-of-range, negative) silently fall back to the documented default (visible only in the
decision's `config_snapshot`; `cfg_int` never errors or writes to stderr). The misconfigured-B3-thresholds
case (`soft <= hard`) is the one coercion that also surfaces a one-time visible `additionalContext`
note and an audit `reason=threshold_order`.

---

## Internal seams (not user config)

These tokens appear in the hook source but are **not user-configurable knobs** — they are
internal implementation seams set by the hook and consumed within the same process:

| Token | What it is |
|---|---|
| `WORKFLOW_AUDIT_PATH` | Absolute path to the session's audit JSONL file. Resolved once by the hook from `planning_dir()` or `$TMPDIR`, cached in `${TMPDIR}/wf-ctx/<safe-session>.auditpath`, then exported for hooklib's `audit_log` to consume. Not a user knob — setting it externally would redirect audit writes to an arbitrary path. |

`check-integration-phase4.sh` intentionally excludes `WORKFLOW_AUDIT_PATH` from the
bidirectional config-drift check (it is an assigned/exported internal value, not a `cfg_int` /
`cfg_flag` / `${WORKFLOW_...:-default}` read).
