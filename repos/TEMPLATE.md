---
# Identity (MUST)
repo: <repo-name>
path: ~/projects/<repo-name>
type: <framework|application|dotfiles|knowledge-base|meta>
stack: [<lang1>, <tool1>]
lifecycle: <active|dormant|deprecated>
owner: rtxnik

# Operational (SHOULD)
quality_gates:
  lint: <command or null>
  typecheck: <command or null>
  test: <command or null>
planning: ~/projects/<repo-name>/.planning
memory: ~/projects/<repo-name>/state/learnings.md
last_verified: <YYYY-MM-DD>
depends_on: []

# Extensions (MAY)
extensions: {}
---

# <repo-name>

## Identity

One paragraph: what this repo is, why it exists, who uses it. Write for an
agent that has never seen the codebase -- skip prose, state facts.

## Stack

- **<tool>** -- one-line purpose, conventions, relevant paths
- **<lang>** -- version pin, package manager, entry point

## Rule packs to load

Reference `workflow-kit` rules via `@`-syntax. Only list rules that are
genuinely relevant -- do not cargo-cult everything.

- `@workflow-kit/rules/common/compact/git.md` -- git operations
- `@workflow-kit/rules/common/compact/review.md` -- pre-commit self-review
- `@workflow-kit/rules/common/compact/security.md` -- secrets, input validation
- `@workflow-kit/rules/languages/<lang>/*.md` -- language pack (if exists)
- `@workflow-kit/rules/tools/<tool>/*.md` -- tool pack (if exists)

Note which common rules do NOT apply and why (e.g., "no `tdd.md` -- no test
suite yet").

## Quality gates

| Gate | Command | When |
|------|---------|------|
| Lint | `<exact command>` | after edit |
| Typecheck | `<exact command>` | after edit |
| Test | `<exact command>` | before commit |

List gates that are declared but **not yet implemented** under a "Not
applicable" heading so the agent does not block on missing tools.

## Planning

Where `.planning/` lives for this repo, lazy-init policy if absent, and
whether fast-lane `.planning/quick/` should be gitignored.

## Memory write-site

- Repo-local corrections -> `<repo>/state/learnings.md`
- Cross-repo / meta corrections -> `~/projects/state/learnings.md`

## Session start checklist

1. `cd ~/projects/<repo-name>` before any git operation
2. Repo-specific pre-flight checks (e.g., `chezmoi status`, `go mod verify`)
3. Any non-obvious state to verify before editing

## Commit conventions

Default: `workflow-kit` git rule (conventional commits, English, no AI
attribution). Document any repo-local overrides here.

## Notes

Non-obvious quirks, gotchas, and constraints that would surprise an agent
seeing the repo for the first time. Keep terse -- this is not a wiki.
