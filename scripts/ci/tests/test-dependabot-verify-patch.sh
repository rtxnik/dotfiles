#!/usr/bin/env bash
# Tests dependabot-verify-patch.sh: allowlisted paths pass; off-list or non-pin compose.py fail.
# shellcheck disable=SC2015
set -uo pipefail
# shellcheck source=../../lib/testlib.sh
source "$(cd "$(dirname "$0")/../../lib" && pwd)/testlib.sh"
t_init
GATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/dependabot-verify-patch.sh"

mkpatch() { local f; f="$(mktemp)"; cat > "$f"; echo "$f"; }

# (1) allowlisted lock + ledger change -> OK
p="$(mkpatch <<'EOF'
diff --git a/factory.lock b/factory.lock
--- a/factory.lock
+++ b/factory.lock
@@ -1 +1 @@
-old
+new
diff --git a/.planning/LEDGER.tsv b/.planning/LEDGER.tsv
--- a/.planning/LEDGER.tsv
+++ b/.planning/LEDGER.tsv
@@ -1 +1,2 @@
 header
+2026-06-30T00:00:00Z	factory.lock	kept	g	n
EOF
)"
bash "$GATE" "$p" >/dev/null 2>&1 && pass "allowlisted patch passes" || fail "allowlisted patch rejected"
rm -f "$p"

# (2) off-allowlist workflow change -> FAIL
p="$(mkpatch <<'EOF'
diff --git a/.github/workflows/release.yml b/.github/workflows/release.yml
--- a/.github/workflows/release.yml
+++ b/.github/workflows/release.yml
@@ -1 +1 @@
-x
+y
EOF
)"
bash "$GATE" "$p" >/dev/null 2>&1 && fail "off-list patch passed" || pass "off-list patch rejected"
rm -f "$p"

# (3) compose.py pure pin-line change -> OK
p="$(mkpatch <<'EOF'
diff --git a/tooling/factory/compose.py b/tooling/factory/compose.py
--- a/tooling/factory/compose.py
+++ b/tooling/factory/compose.py
@@ -1 +1 @@
-      - uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10  # v6.0.3
+      - uses: actions/checkout@1111111111111111111111111111111111111111  # v7.0.0
EOF
)"
bash "$GATE" "$p" >/dev/null 2>&1 && pass "compose pin-line passes" || fail "compose pin-line rejected"
rm -f "$p"

# (4) compose.py non-pin change -> FAIL
p="$(mkpatch <<'EOF'
diff --git a/tooling/factory/compose.py b/tooling/factory/compose.py
--- a/tooling/factory/compose.py
+++ b/tooling/factory/compose.py
@@ -1 +1 @@
-    runs-on: ubuntu-latest
+    runs-on: ubuntu-24.04
EOF
)"
bash "$GATE" "$p" >/dev/null 2>&1 && fail "compose non-pin passed" || pass "compose non-pin rejected"
rm -f "$p"

# (5) rename-only into non-allowlisted path -> FAIL
p="$(mkpatch <<'EOF'
diff --git a/evil.sh b/.github/workflows/evil.yml
similarity index 100%
rename from evil.sh
rename to .github/workflows/evil.yml
EOF
)"
bash "$GATE" "$p" >/dev/null 2>&1 && fail "rename-only non-allowlisted passed" || pass "rename-only non-allowlisted rejected"
rm -f "$p"

# (6) compose.py change with no diff --git header, non-pin content -> FAIL
p="$(mkpatch <<'EOF'
--- a/tooling/factory/compose.py
+++ b/tooling/factory/compose.py
@@ -1 +1 @@
-  - uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10  # v6.0.3
+  runs-on: evil
EOF
)"
bash "$GATE" "$p" >/dev/null 2>&1 && fail "headerless compose.py non-pin passed" || pass "headerless compose.py non-pin rejected"
rm -f "$p"

# (7) mixed patch: allowlisted content hunk + rename into non-allowlisted path -> FAIL
p="$(mkpatch <<'EOF'
diff --git a/factory.lock b/factory.lock
--- a/factory.lock
+++ b/factory.lock
@@ -1 +1 @@
-old
+new
diff --git a/evil.sh b/.github/workflows/evil.yml
similarity index 100%
rename from evil.sh
rename to .github/workflows/evil.yml
EOF
)"
bash "$GATE" "$p" >/dev/null 2>&1 && fail "mixed rename+content non-allowlisted passed" || pass "mixed rename+content non-allowlisted rejected"
rm -f "$p"

t_summary
