#!/usr/bin/env bats
# Phase 21 Plan 21-b WR-04 (HARD-05) -- verify-recipients.sh wording regression.
#
# Asserts the post-21b extra/absent SoT-relative wording fires on the right
# fixture inputs. Two cases:
#   1. SoT contains a pubkey absent from AUTHORIZED-HOSTS.md active tier ->
#      stderr cites "extra recipients in".
#   2. AUTHORIZED-HOSTS.md declares an active host without a matching SoT
#      entry -> stderr cites "active hosts absent from".
#
# Pre-Phase-21b wording was "orphan recipients" / "active hosts missing
# from", which was directionally ambiguous (operators consistently
# mis-read which side is the SoT). The new wording is SoT-relative.
#
# Skip when yq is not on PATH (the script itself exits 2 in that case).

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
VERIFY_SH="${REPO_ROOT}/scripts/verify-recipients.sh"

setup() {
    TEST_TMP=$(mktemp -d)
    export DOTFILES_REPO="$TEST_TMP"
    export RECIPIENTS_YAML="$TEST_TMP/.age-recipients.yaml"
    export AUTHORIZED_HOSTS_MD="$TEST_TMP/docs/AUTHORIZED-HOSTS.md"
    mkdir -p "$TEST_TMP/docs"
}

teardown() {
    rm -rf "$TEST_TMP"
    unset DOTFILES_REPO RECIPIENTS_YAML AUTHORIZED_HOSTS_MD
}

# Build a minimal valid SoT YAML containing `pubkeys`.
_write_recipients_yaml() {
    local out="$1"
    shift
    : > "$out"
    echo "active:" >> "$out"
    local i=0
    for k in "$@"; do
        echo "  - name: host-$i" >> "$out"
        echo "    role: vault-mac" >> "$out"
        echo "    pubkey: $k" >> "$out"
        i=$((i + 1))
    done
}

# Build a minimal AUTHORIZED-HOSTS.md table with `pubkeys` tagged active.
# Columns LOCKED per Phase 12 W2: hostname | role | pubkey | fingerprint | provisioned | host_type | tag.
_write_authorized_hosts_md() {
    local out="$1"
    shift
    {
        echo "# AUTHORIZED HOSTS"
        echo ""
        echo "| hostname | role | pubkey | fingerprint | provisioned | host_type | tag |"
        echo "|----------|------|--------|-------------|-------------|-----------|-----|"
        local i=0
        for k in "$@"; do
            echo "| host-$i | vault-mac | $k | fp$i | 2026-01-01 | mac | active |"
            i=$((i + 1))
        done
    } > "$out"
}

@test "WR-04: extra recipient in SoT surfaces 'extra recipients in' wording" {
    command -v yq >/dev/null 2>&1 || skip "yq not installed"
    [ -f "$VERIFY_SH" ] || { echo "FATAL: missing $VERIFY_SH"; return 1; }

    # SoT carries 2 keys; AUTHORIZED-HOSTS.md only declares 1 active.
    # The 2nd SoT key is "extra" (present in SoT, absent from active tier).
    _write_recipients_yaml "$RECIPIENTS_YAML" \
        "age1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
        "age1bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    _write_authorized_hosts_md "$AUTHORIZED_HOSTS_MD" \
        "age1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    run bash "$VERIFY_SH"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"extra recipients in"* ]] || [[ "$output" == *"extra recipients in"* ]]
    # Negative check: old "orphan" wording must be gone.
    [[ "$stderr" != *"orphan recipients"* ]] && [[ "$output" != *"orphan recipients"* ]]
}

@test "WR-04: active host absent from SoT surfaces 'active hosts absent from' wording" {
    command -v yq >/dev/null 2>&1 || skip "yq not installed"
    [ -f "$VERIFY_SH" ] || { echo "FATAL: missing $VERIFY_SH"; return 1; }

    # SoT carries 1 key; AUTHORIZED-HOSTS.md declares 2 active.
    # The 2nd active host is "absent" (declared active but no SoT entry).
    _write_recipients_yaml "$RECIPIENTS_YAML" \
        "age1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    _write_authorized_hosts_md "$AUTHORIZED_HOSTS_MD" \
        "age1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
        "age1ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

    run bash "$VERIFY_SH"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"active hosts absent from"* ]] || [[ "$output" == *"active hosts absent from"* ]]
    # Negative check: old "missing from" wording must be gone.
    [[ "$stderr" != *"active hosts missing from"* ]] && [[ "$output" != *"active hosts missing from"* ]]
}
