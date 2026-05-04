# Authorized Hosts — `rtxnik/dotfiles`

This file is the **single source of truth** (per CONTEXT.md D-07) for which age public keys are authorized to decrypt secrets in this repo. The `recipients:` list in `.chezmoi.yaml.tmpl` MUST be a strict subset of the `active`-tagged rows here.

The invariant is enforced bidirectionally by `scripts/verify-recipients.sh` — every active row MUST appear as a recipient, and every recipient MUST appear as an active row. The CI workflow (`.github/workflows/validate.yml` `gitleaks` job) runs the script on every push and pull-request to `main`.

### Tag semantics

- `active` — host is provisioned with a real `age1...` pubkey; bidirectional invariant is enforced.
- `pending` — placeholder row awaiting operator `age-keygen` (Phase 12 deferred-UAT). Ignored by the verify script until the operator substitutes a real pubkey AND flips the tag to `active`.
- `retired` — host has been decommissioned; row preserved for audit trail. Ignored by the verify script.
- `escrow-offline` — escrow keypair stored offline (e.g., YubiKey, USB stick); not expected to be reachable for encryption-at-the-moment. Ignored by the verify script.

## Active Hosts

| hostname | role | pubkey | fingerprint | provisioned | host_type | tag |
|----------|------|--------|-------------|-------------|-----------|-----|
| devpod | primary | age1wa2cuua5lfj26he6qrjrywdvqk3twvyhevfngfzy76ztxj5ex3xs454cgp | xs454cgp | 2026-05-04 | DevPod | active |
| macbook | escrow | age1kre65j3v87d0cru8tkj6g6s2823yncw78qcvu6y2m7h8umxxny6qpupzvq | 6qpupzvq | 2026-05-04 | macOS | active |

## Retired Hosts (kept for audit trail; NOT compared by verify script)

| hostname | role | pubkey | fingerprint | provisioned | host_type | tag |
|----------|------|--------|-------------|-------------|-----------|-----|
| (no retired hosts on file as of 2026-05-03) | | | | | | |

## How to add a host

1. On the new host, run:

   ```bash
   age-keygen -o ~/.age/primary.key
   age-keygen -y ~/.age/primary.key   # prints the public key
   ```

2. Append a row to the **Active Hosts** table above with the printed `age1...` pubkey, last 8 chars as fingerprint, today's ISO date, and `tag = active`. (For Phase 12 deferred-UAT: replace the existing `OPERATOR-FILL-...` row's pubkey + fingerprint and flip its tag from `pending` to `active`.)
3. Add the same `age1...` pubkey to the `recipients:` list in `.chezmoi.yaml.tmpl`.
4. Run `bash scripts/verify-recipients.sh` locally — it MUST exit 0 before commit.
5. On every other authorized host, run `chezmoi apply` to refresh the encryption envelope so the new host can decrypt future commits.

## How to retire a host

1. Move the row from **Active Hosts** to **Retired Hosts** above; change `tag` from `active` to `retired`.
2. Remove the corresponding pubkey from the `recipients:` list in `.chezmoi.yaml.tmpl`.
3. Run `bash scripts/verify-recipients.sh` — must exit 0.
4. **Important per CONTEXT.md D-08:** existing commits encrypted while the retired key was active remain decryptable by anyone holding that private key + a clone of the repo. If the retired host's private key is compromised, **rotate the underlying secret** (do NOT rewrite git history — see `docs/SECURITY-INCIDENTS.md`).

## How the iPhone host is handled

iPhone Obsidian Sync uses a different transport (Obsidian Sync, not chezmoi+age) per ADR-flow-06. The iPhone does NOT participate in age encryption. If a future iOS-side dotfiles deployment becomes relevant, add a row with `host_type = iOS` and run the standard provisioning flow.

## References

- CONTEXT.md D-07: `docs/AUTHORIZED-HOSTS.md` is the single source of truth
- CONTEXT.md D-10: `scripts/verify-recipients.sh` performs the bidirectional diff
- ADR-sec-02 (`vault-ai/docs/adr/adr-sec-02-secrets-stack.md`): chezmoi+age multi-recipient model
- ADR-flow-06 (`vault-ai/docs/adr/adr-flow-06-sync-topology.md`): iPhone Obsidian Sync transport (not chezmoi)
