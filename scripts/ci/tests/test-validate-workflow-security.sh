#!/usr/bin/env bash
# Test runner for validate-workflow-security.sh. Asserts exit codes and that
# the expected rule tag appears (or is absent) for each fixture.
set -uo pipefail
# shellcheck source=../../lib/testlib.sh
source "$(cd "$(dirname "$0")/../../lib" && pwd)/testlib.sh"
t_init
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$HERE/../validate-workflow-security.sh"
FX="$HERE/fixtures"

# assert_exit <expected-code> <fixture> ; captures combined output into global $OUT
# so the following assert_has/assert_lacks read it (same flow as the legacy helper).
assert_exit() {
  fixture_label="$2"
  OUT="$(bash "$VALIDATOR" "$FX/$2" 2>&1)"; assert_rc "$2" "$1" "$?"
}
assert_has()  { assert_out_has  "$fixture_label $1" "$OUT" "$1"; }
assert_lacks(){ assert_out_lacks "$fixture_label !$1" "$OUT" "$1"; }

# ---- R1 ----
assert_exit 0 clean.yml;            assert_lacks '\[R1\]'
assert_exit 1 r1-missing-perms.yml; assert_has 'missing top-level permissions'
assert_exit 1 r1-top-write.yml;     assert_has '\[R1\].*id-token'

# ---- R2 ----
assert_exit 1 r2-unpinned.yml; assert_has '\[R2\].*actions/checkout@v4'; assert_lacks 'setup-go'

# ---- R3 ----
assert_exit 1 r3-injection.yml; assert_has '\[R3\]'
assert_exit 0 clean.yml;        assert_lacks '\[R3\]'   # env:-routed interpolation is safe

# ---- review-hardening regressions ----
assert_exit 1 r1-multidoc.yml;  assert_has '\[R1\].*multi-document'
assert_exit 1 r2-templated.yml; assert_has '\[R2\].*unresolvable expression'
assert_exit 1 r3-ghscript.yml;  assert_has '\[R3\].*github-script'

# ---- D1-6: extended INJ_RE (inputs / github.event.inputs) ----
assert_exit 1 r3-inputs.yml; assert_has '\[R3\]'
# ---- D1-11: composite-action run: bodies are scanned (R3 only; R1/R2 skipped on composites) ----
assert_exit 1 composite-injection.yml; assert_has '\[R3\]'; assert_lacks '\[R1\]'
assert_exit 0 composite-clean.yml;     assert_lacks '\[R3\]'

t_summary
