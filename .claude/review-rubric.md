# Code Review Rubric (workspace-owned, durable)

> Applies to every code review in this workspace — the built-in `/code-review`,
> `superpowers:requesting-code-review`, and any reviewer subagent. This file is the
> durable home of the rubric (it survives plugin-cache updates). When you review,
> apply these rules in addition to whatever reviewer template you are using.

## Proof required for HIGH / CRITICAL findings
A finding may be labeled **Critical** or **Important/High** only with concrete proof:
the exact `file:line`, the input or path that triggers it, and the consequence. "This
could be unsafe" with no demonstrated trigger is at most a Minor/observation. No proof
→ downgrade or drop it.

## Zero findings is a valid result
A clean diff, after genuine line-by-line inspection, gets an explicit **APPROVE /
Ready to merge: Yes**. Do not invent issues to look thorough. This does NOT license
"looks good" without reading the code: APPROVE means you read the diff and found nothing
that clears the bar — say what you checked.

## False-positive skip-list (do not flag these as defects)
- Behavior mandated verbatim by an approved plan/spec → at most a Recommendation noting
  the deviation, never a Critical/Important.
- Style/idiom that matches the surrounding file's established convention.
- Missing executable bit on a test that is run via `bash <file>` (the canonical runner).
- Absolute paths in `CLAUDE.md`/docs (the workspace mandates them).
- Intentional fail-open `exit 0` on malformed hook input (the reliability contract).

## Severity calibration
Critical = broken / unsafe / data-loss with a demonstrated trigger. Important = a real
defect or a missing required behavior. Minor = style / polish. When torn between two
levels, pick the lower and say why.

## Reconciliation with the superpowers reviewer
The superpowers rule "never say 'looks good' without checking / never skip review"
stands. This rubric refines it: after a real check, a clean verdict is correct and
expected — rigor is about evidence, not about always finding something to report.

## Record the verdict (machine-readable)
After delivering the assessment, the CALLING agent records the verdict so the
merge gate can read it (`.planning/review-state.json`, read by `merge-gate.sh`):

    bash .claude/hooks/lib/hooklib.sh record_review_verdict approved <BASE_SHA> <HEAD_SHA>
    bash .claude/hooks/lib/hooklib.sh record_review_verdict changes-requested <BASE_SHA> <HEAD_SHA>

Map the reviewer's "Ready to merge: Yes" → `approved`; "No" / "With fixes" →
`changes-requested`. After fixes land, re-review and re-record. The verdict is
keyed to the current branch: merging a feature branch with no `approved` verdict
AND an empty LEDGER is blocked by the merge gate.
