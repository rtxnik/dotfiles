---
name: create-pr
description: Use when creating a pull request — auto-fills PR body from branch name, git log, and LEDGER.tsv. Callable from finishing-a-development-branch Option 2 or directly via /create-pr.
---

# Create PR

Auto-fill a PR body from workflow artifacts and create the PR via `gh pr create`.

## Preconditions

When called from `finishing-a-development-branch`: tests passed, branch pushed.
When called directly (`/create-pr`): check remote tracking and push if needed.

## Algorithm

### Step 1: Detect base branch

Find the fork point:

    base=$(git merge-base --fork-point main HEAD 2>/dev/null \
        || git merge-base main HEAD 2>/dev/null \
        || git merge-base master HEAD 2>/dev/null)

If detection fails, ask the user.

### Step 2: Ensure remote tracking

    tracking=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)

If no tracking branch: `git push -u origin $(git branch --show-current)`.

### Step 3: Parse branch name

    branch=$(git branch --show-current)
    prefix=${branch%%/*}
    slug=${branch#*/}

Map prefix to GitHub label:

| Prefix | Label |
|--------|-------|
| feat | type:feature |
| fix | type:bugfix |
| docs | type:docs |
| refactor | type:refactor |
| chore | type:chore |

Type is NOT included in the PR body. It is set as a GitHub label after PR creation (Step 10).

### Step 4: Build Change Log

    git log --format="- %s" ${base}..HEAD

**If 10+ commits:** wrap in a collapsible `<details>` block:

```markdown
<details>
<summary>N commits</summary>

- commit 1
- commit 2
...

</details>
```

**If fewer than 10:** render inline (no collapsible).

### Step 5: Build Summary

Summarize the Change Log into 2-5 bullets. Focus on WHY the changes were made, not WHAT files changed. Use your understanding of the branch's work to write a concise narrative.

After the Summary bullets, add a Related Issues line if applicable:

    Closes #... · Relates to #...

If the branch name contains an issue number (e.g. `feat/123-thing`), link it automatically. If no issues are related, omit the line.

### Step 6: Build Test Plan + Checklist

Read the gate-evidence log for THIS branch (it is the observed record of acceptance-gate runs;
absent on a fresh checkout — that is fine):

    evid="$(bash "${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/lib/hooklib.sh" gate_evidence_path)"
    branch="$(git branch --show-current)"
    # passing gate runs observed on this branch, by kind:
    [ -f "$evid" ] && jq -r --arg b "$branch" 'select(.branch==$b and .status=="pass") | .kind+" "+.cmd' "$evid"

Test Plan: one bullet per acceptance gate named in the `gate_result` of the kept LEDGER rows
**added on this branch** (Step 8 computes that set). For each bullet, check the box ONLY when the
evidence log has a `status=="pass"` line on this branch whose `cmd` plausibly corresponds (e.g. a
`gate_result` of `hooks-test-pass` is confirmed by an evidence line whose `cmd` contains
`hooks-test`). Otherwise leave it UNCHECKED and label it as self-reported:

    - [x] `make hooks-test` — green (evidence-confirmed)
    - [ ] `bash scripts/ci/check-graph-freshness.sh` — reported pass (not evidence-confirmed)

When in doubt, leave the box UNCHECKED — a false "unverified" note is cheap; a false "verified"
check is exactly the laundering F4 removes. A `gate_result` that names no recognizable gate
command is rendered as a plain narrative bullet (no checkbox) — honored, never punished.

Checklist (no longer statically pre-checked):

    - [ ] Tests pass locally        # [x] ONLY if a status=pass test-kind evidence line exists this branch
    - [ ] Lint clean                # [x] ONLY if a status=pass lint-kind evidence line exists this branch
    - [x] No secrets in diff        # stays [x]: backed by the enforced secrets gates
                                     #   (pre-push-secrets, worktree-secrets-scan, CI), not LEDGER self-report

create-pr runs NO test commands (see Constraints) — it only READS the evidence log.

### Step 7: Evaluate Risk & Rollback

Run `git diff --stat ${base}..HEAD` and parse results.

**Include the Risk & Rollback section if ANY of these are true:**
- Files changed > 10
- Total lines changed > 300
- Diff touches `.github/workflows/*`, `**/security*`, `**/auth*`
- Branch prefix is `fix/`

**If included:** assess risk level (low/medium/high), write rollback plan. Default rollback: `git revert <sha>`.

**If none apply:** omit the section entirely (no empty header).

### Step 8: Build Workflow Discipline

    hooklib="${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/lib/hooklib.sh"
    ledger="$(bash "$hooklib" ledger_path)"
    stats="$(bash "$hooklib" ledger_stats "$ledger")"     # kept=N discarded=N dead-end=N
    branch_rows="$(bash "$hooklib" ledger_rows --since-ref "$base" "$ledger")"  # $base from Step 1

**If `branch_rows` > 0** (this branch logged work):
- Render the Workflow Discipline section with a table reading kept/discarded/dead-end straight
  from `$stats` (do NOT hand-roll a second counter).
- State the branch contribution: "`$branch_rows` LEDGER row(s) added on this branch" — describe
  THIS branch's work, not the cumulative file history.
- Extract the `gate_result` of the last kept row added on this branch for the table.

**If `branch_rows` is 0** (no rows logged for this branch): omit the section entirely.

### Step 9: Assemble and create PR

Title format: `<prefix>: <slug-as-sentence>` (convert kebab-case to spaces, max 70 chars).

    gh pr create --title "$title" --body "$body"

Use a HEREDOC to pass the body for correct formatting.

### Step 10: Set metadata and report

After PR creation, set sidebar metadata:

**Assignee** (always):

    gh pr edit <number> --add-assignee @me

**Type label** (from branch prefix):

    gh pr edit <number> --add-label "type:<prefix>"

If the label doesn't exist yet, create it:

    gh label create "type:<prefix>" --description "<Label>" --color <color>

Colors: feature=0E8A16, bugfix=D93F0B, docs=0075CA, refactor=E4E669, chore=CCCCCC.

**Size label** (from diff stats):

| Lines changed | Label |
|---------------|-------|
| < 30 | size:S |
| 30-150 | size:M |
| 150-500 | size:L |
| > 500 | size:XL |

    gh pr edit <number> --add-label "size:<S|M|L|XL>"

Output the PR URL to the user.

## Error Handling

| Error | Action |
|-------|--------|
| `gh` not authenticated | Print error, suggest `gh auth login` |
| No commits vs base | Abort: "No changes to create PR for" |
| Unknown branch prefix | Skip label, continue |
| Label create fails (no permission) | Skip label with warning, PR still created |

## Constraints

- No AI attribution in title or body
- No modification of LEDGER or any source files
- No test execution (already done by finishing-a-development-branch)

## Sanctioned call site (Finding S)

Root CLAUDE.md forbids inline `gh pr create` with a *manually composed* body.
This skill is the mechanism that rule routes to: its body is assembled
programmatically from git log + LEDGER and mirrors
`.github/pull_request_template.md` (Summary / Change Log / Test Plan /
Checklist / Risk & Rollback / Workflow Discipline). The `gh pr create` call in
Step 9 is the single sanctioned exception — do not copy the pattern elsewhere.
