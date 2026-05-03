# Security Incidents — `rtxnik/dotfiles`

Format: reverse-chronological. Each entry: date, severity, scope, discovery, rotation log, references. Empty body = no incidents.

This file is the authoritative incident log for `rtxnik/dotfiles`. It is committed to the repo so the audit trail travels with the code (per CONTEXT.md D-08 rationale: dotfiles is public; clones already exist; commit history is the only durable record).

## Policy: Rotate, Not Rewrite

Per CONTEXT.md D-08 (`vault-ai/docs/adr/adr-sec-02-secrets-stack.md` §Multi-recipient age cross-reference): the **default response to any historical leak is to ROTATE the affected secret, NOT to rewrite git history**.

Rationale: `dotfiles` is a public repo. Forks, clones, and archive mirrors exist on third-party machines. A `git filter-repo` rewrite + force-push only updates the canonical remote; it does NOT retract the secret from the world. The leak is durable; the remediation is rotation.

The rewrite path is documented as a **secondary** response with three preconditions that ALL must hold:
1. The leaked secret is already revoked (rotation completed first).
2. Future-clone hygiene is the only remaining concern (no in-the-wild concern).
3. The operator is willing to coordinate force-push + re-clone with every collaborator (currently a single operator, so coordination cost is low — but the policy still defaults to rotate).

## Incident-entry template

Every future incident entry MUST follow this shape:

```
## YYYY-MM-DD — <one-line title>

- **Severity:** critical | high | medium | low
- **Scope:** <files / commits / time range>
- **Discovery:** <pre-commit hook | CI | manual audit | external report>
- **Affected secrets:** <list with rotation status per item>
- **Rotation log:** <ISO timestamps + commands run>
- **References:** <ADR / commit SHA / PR link>
```

---

## (no incidents recorded as of 2026-05-03)

Phase 12 historical audit (`gitleaks git --report-format json` over full repo history, executed via `tests/test_history_scan.sh`) returned zero findings; baseline established.

- **Audit date:** 2026-05-03
- **Audit scope:** full git history (117 commits across all refs; 98 commits on main lineage)
- **Audit tool:** gitleaks 8.30.1 with `.gitleaks.toml` extending defaults
- **Pre-flight check:** scoped scan over last 10 commits returned zero findings, confirming `[allowlist] paths` applies retroactively to history scans (per Phase 12 Plan 04 B3 mitigation)
- **Audit result:** zero findings (`jq 'length == 0' /tmp/audit.json` exit 0)
- **Audit artifact:** ephemeral (`/tmp/gitleaks-history-audit-$$.json`); not committed (Open Question 4 resolution; respects existing `state/` gitignore policy)
- **References:** `.planning/phases/12-dotfiles-security-audit/12-04-PLAN.md`, ADR-sec-02 (`vault-ai/docs/adr/adr-sec-02-secrets-stack.md`)
