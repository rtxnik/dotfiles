---
schema_version: "1.1"
---

# Passport Schema v1.0

This document is the authoritative contract for repo passport files in `repos/`. Every passport must conform to the field definitions, tier requirements, and body section structure defined here.

For field design rationale (why each field exists and what it enables), see the "Schema Fields Rationale" section in CLAUDE.md. This schema formalizes those fields into MUST/SHOULD/MAY tiers with validation constraints.

## Field Definitions

| Field | Tier | Type | Description |
|-------|------|------|-------------|
| `repo` | MUST | string | Repository directory name, unique within workspace |
| `path` | MUST | string | Absolute path: `~/projects/<repo>` |
| `type` | MUST | enum | One of: `framework`, `application`, `dotfiles`, `knowledge-base`, `meta` |
| `stack` | MUST | string[] | Primary languages and tools |
| `lifecycle` | MUST | enum | One of: `active`, `dormant`, `deprecated` |
| `owner` | MUST | string | Primary maintainer identifier |
| `visibility` | MUST | enum | One of: `public`, `private`. Drives the public-aware AI-attribution guard (`repo_visibility` in `.claude/hooks/lib/hooklib.sh`). Default when absent: `private`. |
| `quality_gates` | SHOULD | object | Contains `lint`, `typecheck`, `test` (each string or null) |
| `planning` | SHOULD | string | Path to `.planning/` directory, or null |
| `memory` | SHOULD | string | Path to `state/learnings.md`, or null |
| `last_verified` | SHOULD | date | ISO 8601 date (YYYY-MM-DD) of last passport review |
| `depends_on` | SHOULD | string[] | Repo names this repo depends on |
| `extensions` | MAY | object | `{}` placeholder for future agent-specific namespacing |

## Tier Definitions

- **MUST** -- Field is required in every passport. Omission is a schema violation.
- **SHOULD** -- Field is expected in active repos. May be null for dormant or minimal repos.
- **MAY** -- Field is optional. Present as placeholder for forward compatibility.

## Body Sections

Every passport includes a Markdown body after the YAML frontmatter. The following sections are defined:

| Section | Required | Description |
|---------|----------|-------------|
| Identity | required | What this repo is, why it exists |
| Stack | required | Tools, languages, key paths |
| Rule packs to load | required | workflow-kit rule references via `@`-syntax |
| Quality gates | required | Exact commands in a table, with not-applicable notes |
| Planning | required | `.planning/` location and initialization policy |
| Memory write-site | required | Where corrections are written |
| Session start checklist | required | Pre-flight steps before working in the repo |
| Commit conventions | required | Overrides to default conventional commits |
| Notes | optional | Quirks and gotchas that would surprise an agent |

## Constraints

- **Size ceiling:** 8192 bytes (8KB) maximum per passport file. SCHEMA.md and TEMPLATE.md are exempt.
- **`last_verified` updates:** Must be set to the current date when passport content is reviewed or changed.
- **`depends_on` direction:** Single-direction only. A passport declares what it depends on. Inverse relationships are not stored in passports -- they are derived by reading all passports or from TOPOLOGY.md.
- **`type` enum is closed:** Adding new values requires a schema version bump.

## Migration Guidance

When the schema version changes:

- **New MUST fields:** Update all passports to include the new field. This is a breaking change.
- **New SHOULD fields:** Do not require immediate migration. Passports without the field remain valid but incomplete.
- **New MAY fields:** No migration required. Passports may adopt at their own pace.
- **Removed fields:** Remove from all passports in the same version bump.

Document all changes in the Changelog section below.

## Changelog

- **1.0** (2026-04-12) -- Initial schema. 6 MUST fields, 5 SHOULD fields, 1 MAY field.
- **1.1** (2026-05-21) -- Size ceiling raised 4096 -> 8192 bytes (power-of-two; covers vault-ai 7219-byte + dotfiles 6207-byte passports empirically observed in v2.1). HARD-06 closure.
