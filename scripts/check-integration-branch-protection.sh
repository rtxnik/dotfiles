#!/usr/bin/env bash
# shellcheck disable=SC2154  # pass/fail are set in the caller's scope by ck_init (lib/check.sh)
# Asserts the server-side enforcement floor (F1 / HP-1, D6-1): branch protection
# on main with the three gate workflows as required checks, strict up-to-date,
# enforce_admins, no force-pushes/deletions. READ-ONLY by design.
# SKIPs gracefully when gh/auth/network are unavailable (CI runners carry no
# admin-scoped token — same posture as check-validator-drift.sh), but FAILS hard
# when the API answers "Branch not protected" or the policy has drifted.
# Test seam: BP_PROTECTION_JSON=<file> bypasses gh entirely.
set -uo pipefail
# shellcheck source=lib/check.sh
source "$(cd "$(dirname "$0")/lib" && pwd)/check.sh"
ck_init
# Target repo: REPO env, else GitHub Actions context, else the local origin remote (parsed to
# owner/name). Empty (no remote) -> the gh path SKIPs. No repo name is hardcoded.
REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
if [ -z "$REPO" ]; then
  REPO="$(git remote get-url origin 2>/dev/null | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##')"
  case "$REPO" in */*) ;; *) REPO="" ;; esac
fi
REQUIRED_CONTEXTS=(fabric-gates workflow-security workflow-graph)

if [ -n "${BP_PROTECTION_JSON:-}" ]; then
  json="$(cat "$BP_PROTECTION_JSON")"; rc=0
elif ! command -v gh >/dev/null 2>&1; then
  echo "SKIP: gh not installed — branch protection not verified here"; exit 0
elif [ -z "$REPO" ]; then
  echo "SKIP: cannot resolve target repo (set REPO or GITHUB_REPOSITORY) — not verified here"; exit 0
else
  json="$(gh api "repos/$REPO/branches/main/protection" 2>&1)"; rc=$?
fi

if [ "$rc" -ne 0 ]; then
  if printf '%s' "$json" | grep -qi "Branch not protected"; then
    echo "FAIL: no branch protection on $REPO main — run scripts/setup-branch-protection.sh" >&2
    exit 1
  fi
  echo "SKIP: protection API unavailable (auth/network) — not verified here"
  exit 0
fi

for ctx in "${REQUIRED_CONTEXTS[@]}"; do
  ck_assert_jq "$json" ".required_status_checks.contexts | index(\"$ctx\") != null" "required check '$ctx'"
done
ck_assert_jq "$json" '.required_status_checks.strict == true' "strict up-to-date enabled"
ck_assert_jq "$json" '.enforce_admins.enabled == true'        "enforce_admins enabled"
ck_assert_jq "$json" '.allow_force_pushes.enabled == false'   "force pushes disabled"
ck_assert_jq "$json" '.allow_deletions.enabled == false'      "deletions disabled"

if [ "$fail" -eq 0 ]; then
  echo "Results: branch-protection floor intact"
else
  echo "Results: FAILED"
  exit 1
fi
