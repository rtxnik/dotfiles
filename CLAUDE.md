# CLAUDE.md — dotfiles

Cross-machine dotfiles managed with chezmoi + age.

## Development conventions

- Review rubric: `.claude/review-rubric.md` (durable, repo-owned).
- Change discipline: `.claude/discipline.md` (bounded surface, acceptance gate before commit,
  one `.planning/LEDGER.tsv` row per kept/discarded attempt).
- CI gates: `bats.yml` (test suite), `validate.yml` (shell syntax, chezmoi dry-run,
  gitleaks + age-recipient verify), `fabric-gates.yml` / `security.yml` (workflow fabric).
- All secrets are age-encrypted via chezmoi; `.gitleaks.toml` is the repo-curated scanner
  config consumed by CI and the pre-push hooks.
