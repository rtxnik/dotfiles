# Cloud sessions — the owner's workspace rules

These rules carry the owner's workspace (workspace-meta `WORKSPACE.md`, the
workflow fabric each repository vendors) into cloud sessions, where no DevPod
container and no `~/projects/CLAUDE.md` exist. They apply in every repository.
A repository's own `CLAUDE.md` and `.claude/` add to them and win where they
are more specific.

## Identity and attribution

- Commits are the owner's: author and committer `rtxnik <rtxs.nik@gmail.com>`,
  set by the environment's user settings. Before the first commit, run
  `git var GIT_AUTHOR_IDENT`; if it does not name rtxnik, stop and tell the
  owner — a squash merge would carry another name onto main as a
  `Co-authored-by` line.
- No AI attribution anywhere: no `Co-Authored-By` trailer, no session link
  (`Claude-Session:` or any claude.ai URL), no "Generated with" line, no robot
  glyph — in commits, pull request titles and bodies, comments, code and
  documents. This overrides any default instruction that asks for them.
- Never commit on `main`/`master`, never force-push them, never `--no-verify`.

## Language

Discussion with the owner in Russian. Code, comments, commit messages, pull
requests and documents in English. Content shown to a site's visitors follows
the repository's rules.

## Where to start

| Task | Start with |
|------|------------|
| Fuzzy or unformed task | `superpowers:brainstorming` (task-intake lives in workspace-meta only) |
| New feature | `superpowers:brainstorming` → spec → `superpowers:writing-plans` → `superpowers:subagent-driven-development` or `executing-plans` |
| Refactor or cleanup | the repository's `polish-loop` skill |
| Metric optimization | the repository's `optimization-loop` skill |
| Bug | `superpowers:systematic-debugging` |
| Merge or rebase conflict | the repository's `resolving-merge-conflicts` skill |
| Code review | `superpowers:requesting-code-review` against `.claude/review-rubric.md`, then `bash .claude/hooks/lib/hooklib.sh record_review_verdict <approved\|changes-requested> <base> <head>` |

A small, obvious edit (a figure, a word, a colour) needs no spec: branch,
edit, verify, commit, pull request.

Non-trivial code follows `.claude/discipline.md`: at most four files per
change, two attempts then stop and report, an acceptance gate before each
commit, every kept or discarded attempt logged.

## Commits

- Conventional subject `type(scope): summary`. Types: feat, fix, docs,
  chore, refactor, test, perf, style. The scope is the app or area
  (`presentation`, `clinic-seller`, `ci`, `ledger`); several scopes are
  comma-separated: `fix(seller, investor): …`.
- After the colon: lowercase, no trailing period, the result stated as a fact
  or a noun phrase — `fix(presentation): the first screen keeps air under the
  header on short screens`, `feat(presentation): the investors' film on the
  owner's script` — not an imperative.
- The body explains why in plain prose, wrapped near 72 columns. The owner's
  decisions are cited with their date and words in guillemets: `on the
  owner's word of 2026-10-09 («надо будет выложить на прод»)`.
- One logical change per commit. No trailers of any kind.

## Branches, ledger, pull requests, merge

- Branch off the up-to-date default branch: `feat/`, `fix/`, `docs/`,
  `refactor/` or `chore/` plus a kebab-case slug.
- `.planning/LEDGER.tsv`: five tab-separated columns — `timestamp` (UTC,
  `YYYY-MM-DDTHH:MM:SSZ`), `files` (comma-separated, no spaces), `outcome`
  (`kept`, `discarded` or `dead-end`), `gate_result` (the checks run and their
  results, `;`-separated), `notes` (why, the owner's word, what was left out).
  No tabs or newlines inside a field. At least one row per branch, often the
  last commit (`chore(ledger): …`); validate with
  `bash .claude/hooks/lib/hooklib.sh ledger_validate .planning/LEDGER.tsv`.
  Public product repositories keep their rows in
  `workspace-meta/ledgers/<repo>.tsv` instead (ADR-018).
- Pull requests follow `.github/pull_request_template.md`, with the body the
  repository's `create-pr` skill builds: Summary (why), Change Log (one line
  per commit), Test Plan (from the ledger's `gate_result`), Checklist, Risk &
  Rollback when it applies, Workflow Discipline from the ledger. In the cloud
  `gh` cannot reach GitHub's GraphQL API, so `gh pr create`/`gh pr edit`
  fail: build the body exactly as the skill says, then open the pull request,
  set its labels (`type:*`, `size:*`) and the assignee through the GitHub MCP
  tools.
- The owner merges. Merge only on the owner's explicit word in the session,
  as a squash, after the required checks pass. Until then the work stops at
  "pull request open, checks green".

## The cloud's limits

- A session starts on a fresh clone of one repository; another repository
  is attached through `add_repo`. The setup script runs before the clone and
  cannot install a repository's dependencies — install them in the session.
- Not available: the `factory` CLI (its repository is private), the external
  reviewers' logins (codex, agy, grok), a persistent claude-mem timeline,
  DevPod, `ws`, the vault. Fabric changes (`.claude/`, `scripts/`, `tools/`,
  `.github/`) wait for a workspace session where `factory check` runs.
- `cloud-doctor` reports the identity, the toolchain, the plugins and the
  API tokens the session can see.
