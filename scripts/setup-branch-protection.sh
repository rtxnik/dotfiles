#!/usr/bin/env bash
# One-shot (idempotent) enable of the server-side enforcement floor on main
# (F1 / HP-1). Requires gh authenticated as a repo ADMIN — this is the only
# write-path; the integration check stays read-only.
# required_pull_request_reviews stays null: GitHub rejects self-approval, so a
# review requirement would deadlock a solo-owner repo.
# Rollback: gh api -X DELETE "repos/$REPO/branches/main/protection"
set -euo pipefail
# Target repo: explicit REPO env, else GitHub Actions context, else the gh-authenticated checkout.
REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
[ -n "$REPO" ] || REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
[ -n "$REPO" ] || { echo "ERROR: cannot resolve target repo — set REPO=owner/name" >&2; exit 1; }

gh api -X PUT "repos/$REPO/branches/main/protection" --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["fabric-gates", "workflow-security", "workflow-graph"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": false,
  "required_conversation_resolution": false,
  "lock_branch": false,
  "block_creations": false
}
JSON

echo "Branch protection applied. Verifying:"
bash "$(dirname "$0")/check-integration-branch-protection.sh"
