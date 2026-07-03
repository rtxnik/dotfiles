---
name: polish-loop
description: Use when polishing, refactoring, deduplicating, extracting, or cleaning up code in a focused change — especially after a planning phase, or any time a small edit risks sprawling into unrelated files, scope-creep, or an ever-growing plan.
---

# Polish Loop

## Overview

A polish/refactor task is not "improve the code." It is one narrow change against a fixed budget with an objective acceptance gate, then keep-or-revert. Plan WHAT thinly; execute HOW under hard constraints (this loop).

**Core principle (from the autoresearch pattern):** one editable surface · fixed budget · objective metric · keep or discard · iterate. Sprawl and "fit everything in one phase" come from missing the *surface* and the *budget* — this loop reinstates both.

> Canonical workspace rules: `.claude/discipline.md` (single source of truth). This skill specializes them for behavior-preserving cleanup.

## When to use

- After a planning phase, to polish the slice.
- Any dedup/extraction/cleanup/rename or small focused fix.
- The moment a change starts touching files you didn't name → STOP and run this loop.

**Not for:** initial feature design (brainstorm first) or genuinely multi-file features (that's a real phase, plan it).

## The loop (one pass = one commit)

1. **Define the surface.** Write the ALLOWED files (the only ones you may edit) and FORBIDDEN set. If you can't list ≤~4 files, the packet is too big — split it.
2. **Branch/isolate.** Work on a branch or worktree, not directly on a dirty `main`.
3. **Implement only within the surface.** Behavior-preserving unless the packet explicitly says otherwise.
4. **Acceptance gate** (see below) — must pass.
5. **Review the diff.** `git diff --stat` — only ALLOWED files appear? If anything else changed, revert it.
6. **Keep or discard.** Pass → one atomic commit. Fail after budget → revert, write findings, stop.
7. **Log & next.** Side-findings → backlog file, never fix inline. Then next packet.

For multi-file mechanical packets, dispatch a bounded subagent with the boundaries below and review its diff yourself before committing. For a 1–3 file surgical change, do it inline.

## Boundaries block (paste into the packet / subagent prompt)

```
ALLOWED files (edit ONLY these): <list>
FORBIDDEN: everything else. If you must touch another file, STOP and explain — don't.
No new abstraction/registry/factory/flags. Prefer deletion over addition.
Side-findings → append to .planning/.backlog-found.md (file:line), do NOT fix them.
Fix budget: 2 attempts. Then STOP and report what changed / what failed / root cause.
```

## Acceptance

Adapt to your repo's quality gates (see repo passport in `workspace-meta/repos/<repo>.md`):

- **workspace-cli (Go):** `go vet ./...` + `go test ./...` + `golangci-lint run`
- **vault-ai (Python/Node):** `bash _tooling/lint/run-all.sh` + `bash _tooling/validator/run-all.sh`
- **dotfiles (Shell):** `shellcheck <file>` + `bats scripts/tests/`
- Behavior-preserving claim must be *verified in the diff*, not asserted.

## Simplicity criterion

A small win that adds ugly complexity is not worth it. Removing code for equal/better behavior is always a win. When unsure: would deleting be simpler? Prefer it.

This is the metric x simplicity gate from `.claude/discipline.md` (AR-1): for a behavior-preserving change the "metric" is the pass/fail gate — keep only if the gate passes AND the diff is simpler-or-equal; a passing change that adds ugly complexity is a revert.

## Failure handling (AR-2) & when stuck (AR-3)

Canonical taxonomy + stuck protocol: `.claude/discipline.md` (AR-2/AR-3). Polish-loop delta:
side-findings and dead-end findings append to `.planning/.backlog-found.md` (file:line) — never fix inline.

## Red flags — STOP, you're sprawling

| Thought | Reality |
|---|---|
| "While I'm here I'll also fix…" | Not in the surface → backlog it, don't touch. |
| "It's in an ALLOWED file so I'll tidy it too" | Allowed ≠ required. Change only what the fix needs; unrequested cleanup is scope-creep even inside an allowed file → backlog it. |
| "Let me make it more flexible/generic" | No. Prefer deletion. No new abstraction. |
| "This needs a few more files" | Packet too big → split into separate passes. |
| "I'll expand the plan to cover X too" | Plan stays thin. Add a *new* packet, don't grow this one. |
| "Tests later / it's obvious" | Every packet ships a test. Now. |
| "Behavior probably unchanged" | Prove it in the diff before committing. |
