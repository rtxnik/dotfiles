#!/usr/bin/env bash
# Test runner for check-integration-branch-protection.sh via the BP_PROTECTION_JSON
# fixture seam and gh shims: good config passes, each policy regression fails,
# 404 (unprotected) fails, auth/network errors SKIP (exit 0).
set -uo pipefail
# shellcheck source=../../lib/testlib.sh
source "$(cd "$(dirname "$0")/../../lib" && pwd)/testlib.sh"
t_init
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/../../check-integration-branch-protection.sh"
tmp="$(mktemp -d)"

good='{
  "required_status_checks": {"strict": true, "contexts": ["fabric-gates", "workflow-security", "workflow-graph"]},
  "enforce_admins": {"enabled": true},
  "allow_force_pushes": {"enabled": false},
  "allow_deletions": {"enabled": false}
}'
printf '%s' "$good" > "$tmp/good.json"
printf '%s' "$good" | jq '.required_status_checks.contexts -= ["workflow-graph"]' > "$tmp/missing-ctx.json"
printf '%s' "$good" | jq '.required_status_checks.strict = false' > "$tmp/lax.json"
printf '%s' "$good" | jq '.enforce_admins.enabled = false' > "$tmp/admins-exempt.json"
printf '%s' "$good" | jq '.allow_force_pushes.enabled = true' > "$tmp/force-push.json"

# 1-5. fixture-driven policy asserts
OUT="$(BP_PROTECTION_JSON="$tmp/good.json" bash "$SRC" 2>&1)"; assert_rc "good config passes" 0 $?
assert_out_has "intact summary" "$OUT" 'floor intact'
BP_PROTECTION_JSON="$tmp/missing-ctx.json" bash "$SRC" >/dev/null 2>&1; assert_rc "missing context fails" 1 $?
BP_PROTECTION_JSON="$tmp/lax.json" bash "$SRC" >/dev/null 2>&1; assert_rc "strict=false fails" 1 $?
BP_PROTECTION_JSON="$tmp/admins-exempt.json" bash "$SRC" >/dev/null 2>&1; assert_rc "enforce_admins=false fails" 1 $?
BP_PROTECTION_JSON="$tmp/force-push.json" bash "$SRC" >/dev/null 2>&1; assert_rc "force-push allowed fails" 1 $?

# 6. gh answers "Branch not protected" -> hard FAIL
# REPO is injected so the shim is reached even when the repo has no remote yet.
shim="$(mktemp -d)"
printf '#!/usr/bin/env bash\necho "gh: Branch not protected (HTTP 404)"\nexit 1\n' > "$shim/gh"
chmod +x "$shim/gh"
OUT="$(REPO=owner/repo PATH="$shim:$PATH" bash "$SRC" 2>&1)"; assert_rc "unprotected branch fails" 1 $?
assert_out_has "unprotected message" "$OUT" 'no branch protection'

# 7. gh auth/network error -> SKIP, exit 0 (CI runners have no admin token)
printf '#!/usr/bin/env bash\necho "gh: To get started with GitHub CLI, please run: gh auth login" >&2\nexit 4\n' > "$shim/gh"
OUT="$(REPO=owner/repo PATH="$shim:$PATH" bash "$SRC" 2>&1)"; assert_rc "auth error skips" 0 $?
assert_out_has "SKIP notice" "$OUT" '^SKIP:'

rm -rf "$tmp" "$shim"
t_summary
