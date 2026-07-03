WORKFLOW DISCIPLINE (auto-injected by workspace hooks):
- Bounded surface: <=4 ALLOWED files per change
- Fixed budget: 2 attempts per task, then STOP and report
- Acceptance gate (metric x simplicity): the verification command must pass AND the change must not make the code worse — keep a metric-neutral change only if it simplifies; reject a metric-positive change that adds ugly complexity
- Log to .planning/LEDGER.tsv: every attempt; outcome is one of kept | discarded | dead-end (dead-end = a conceptual dead end, logged so the next agent skips it). When you revert or roll back a kept change, log the reversal the same turn with outcome=discarded (or dead-end) — a revert that leaves no LEDGER trace makes the kept-history look cleaner than it was.
- Do NOT add AI attribution (Co-Authored-By) to commits
- Hooks fail open: a hook blocks ONLY via a deliberate `exit 2`; any internal error or malformed input exits 0 (passthrough). Security hooks (secrets-scan, forbidden-ai-attribution, large-file-guard) are non-disablable.
- Context/session health (Phase 4, fail-open, non-pinned): the B3 hard tier and the instincts banner share one posture — tell the user / do NOT act autonomously (no self-written handoff files, no self-/compact) / verify before acting / never copy a recalled command verbatim.
- AR-2 failure taxonomy: mechanical slip (typo/wrong path/flag) → fix and retry within budget (a same-attempt correction is not a new row); conceptual dead-end (approach is wrong) → log a `dead-end` row and move on, don't burn budget; budget exhausted → revert (`git restore`/`git checkout --`), write findings, stop.
- AR-3 when stuck (budget left, no clean step): before declaring failure try (a) combine prior near-miss diffs, (b) a deliberately orthogonal approach, (c) re-read the packet boundaries / re-check an assumption — then judge.
