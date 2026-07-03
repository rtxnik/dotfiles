---
name: optimization-loop
description: Use when optimizing a measurable target — making something faster, smaller, cheaper, or higher-throughput (bundle size, query/endpoint latency, p95, memory, token cost, pass rate). Triggers whenever success is a number you can re-measure, not a behavior change.
---

# Optimization Loop

## Overview

Optimizing is not "make it faster." It is: pick one number, measure it, change one thing, re-measure, and **keep the change only if the number actually moved and the code didn't get worse**. Every change is an experiment with a verdict. Faith ("this should be faster") is not a verdict — the measurement is.

**Core principle (from the autoresearch pattern):** one metric · baseline first · one change at a time · keep or revert by the number · log every attempt · stop at target/budget.

> Canonical workspace rules: `.claude/discipline.md` (single source of truth). This skill specializes them for driving a measurable number.

This is the sibling of `polish-loop`. Use **polish-loop** for behavior-preserving cleanup (pass/fail gate). Use **this** when you're driving a continuous number up or down.

## When to use

- Bundle/asset size, endpoint or query latency, p95, memory, token/$ cost, throughput, test pass rate.
- Any task phrased "make X faster/smaller/cheaper" where you can run a command that prints the number.

**Not for:** features (brainstorm first), or refactors with no metric (that's polish-loop).

## The loop

1. **Define the metric + the measure command.** One deterministic command that prints the number (e.g. `vite build` → main-chunk kB; `EXPLAIN ANALYZE` ms; a timed request). Write the command down. Set a **target or budget** (a number to hit, or N iterations / a time box) so you know when to stop.
2. **Baseline first.** Run the measure command UNCHANGED. Record it as attempt 0 in the ledger. Never skip — without a baseline you can't judge anything.
3. **One change at a time.** Isolate it so the delta is attributable. Never batch optimizations — you won't know which one helped (or hurt).
4. **Re-measure** with the *same* command, same conditions.
5. **Verdict — keep or revert:**
   - Improved meaningfully **and** code is not more complex → **keep**.
   - No real improvement, or regressed → **revert it** (`git checkout --`/`git restore`). A no-op kept "just in case" is debt.
   - Equal-or-better metric **with less/simpler code** → always keep (a deletion win).
6. **Log every attempt** — kept AND discarded. Discards are data: they stop you (and the next agent) re-trying dead ends.
7. **Stop only when you hit the target OR exhaust the budget.** "Diminishing returns" applies only if every *remaining* lever is tiny-gain or complexity-heavy. A clean, untried lever with a plausibly large win while budget remains is NOT diminishing returns — try it before stopping. Gold-plating (which you DO avoid) is squeezing *past* the goal or chasing sub-1% gains with added complexity — not "budget left, big clean lever untried."

## Ledger — one enforced log + a metric sidecar

The **enforced** ledger is `.planning/LEDGER.tsv` (canonical 5-column schema from `.claude/discipline.md`; the push contract and commit hooks read ONLY this file). Per-attempt measurements live in a **sidecar**, `.planning/attempts/<metric>.tsv`, referenced from the LEDGER `notes` column. Nothing syncs between them — the sidecar holds numbers, the LEDGER holds verdicts.

**1. Sidecar — every measurement.** Append one TAB-separated row per attempt to `.planning/attempts/<metric>.tsv` (NOT commas — they break in notes):

```
timestamp	change	before	after	delta	verdict	note
2026-05-26T10:00	baseline	891	891	0	baseline	main chunk kB, `vite build`
2026-05-26T10:12	lazy-load OutreachLayout	891	742	-149	keep	route-level dynamic import
2026-05-26T10:25	manualChunks vendor split	742	744	+2	revert	no win, added config noise
2026-05-26T10:40	precompute size table	742	742	0	dead-end	approach cannot move this metric; skip the lever
```

Verdict column values: `keep` | `revert` | `dead-end` (a conceptual dead end — logged so the next agent skips that lever).

**2. LEDGER.tsv — every attempt verdict.** After each attempt's verdict, append a row to `.planning/LEDGER.tsv`, mapping the sidecar verdict to the discipline vocabulary: `keep`→`kept`, `revert`→`discarded`, `dead-end`→`dead-end`. Put the metric movement in `gate_result` and reference the sidecar in `notes`:

```
2026-05-26T10:12	src/routes/outreach.tsx	kept	main-chunk 891→742 kB	opt:bundle-size; sidecar .planning/attempts/bundle-size.tsv
2026-05-26T10:25	vite.config.ts	discarded	main-chunk 742→744 kB	opt:bundle-size; no win; sidecar .planning/attempts/bundle-size.tsv
2026-05-26T10:40	(none kept)	dead-end	main-chunk 742→742 kB	opt:bundle-size; lever cannot move metric; sidecar .planning/attempts/bundle-size.tsv
```

The baseline row (attempt 0) stays sidecar-only — it changes nothing, so it is not a LEDGER attempt. This is what makes optimization work visible to `pre-push-contract` and `commit-integration` (PATHFINDER Finding I).

## Measurement integrity

- Same command, same conditions every time. Note warm vs cold.
- **Beware noise** (autoresearch's own caveat): timing/latency metrics jitter — measure 2–3× and use the median before trusting a small delta. Size metrics (kB) are deterministic; one read is fine.
- Optimize the metric that matters to a user/SLO, not a proxy that's easy to move.

## Output hygiene (AR-4)

Never flood your context with raw build/measure logs. Redirect verbose output to a file and grep only the number: `<measure-cmd> >/tmp/measure.log 2>&1; grep -E '<signal>' /tmp/measure.log`. Keep the signal (the metric line), discard the noise — a wall of build output buys nothing and crowds out the reasoning you need for the next attempt.

## Simplicity criterion

Weigh complexity cost against gain magnitude. A 0.5% win that adds 20 lines of hacky caching? Skip. A win from deleting code? Always keep. An equal result with simpler code? Keep. When a gain forces ugly complexity, the honest verdict is often **revert**.

This is the metric x simplicity gate from `.claude/discipline.md` (AR-1): a metric-neutral change is worth keeping if it *simplifies*; a metric-positive change that adds ugly complexity is not.

## Failure handling (AR-2) & when stuck (AR-3)

Canonical taxonomy + stuck protocol: `.claude/discipline.md` (AR-2/AR-3). Optimization-loop deltas:
a same-attempt correction is not a separate ledger row; a dead-end means the *lever* cannot move the
metric (skip that lever, try the next); "stuck" levers include combining two near-misses or re-measuring
the baseline to recheck an assumption.

## Red flags — STOP

| Thought | Reality |
|---|---|
| "This should be faster, I'll keep it" | Didn't measure = no verdict. Measure or revert. |
| "Let me change a few things then test" | Batched changes aren't attributable. One at a time. |
| "Skip the baseline, I know it's slow" | No baseline = every later number is meaningless. |
| "Small regression but cleaner, keep it" | This is an optimization task — the number is the gate. |
| "0.3% win, ship the 40-line cache" | Complexity > gain → revert. |
| "Already hit target, but I can squeeze more" | Stop. Gold-plating burns budget. |
| "Diminishing returns, I'll stop" (budget left, big clean lever untried) | That's quitting early, not diminishing returns. Try the lever, measure, then judge. |
| "No need to log the ones that didn't work" | Discards are the most valuable rows — log them. |
