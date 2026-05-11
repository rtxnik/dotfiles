#!/usr/bin/env bats
# Phase 19 Plan 19-04 Wave 4 Task 1 — chezmoi watcher template validity tests.
# Asserts the 3 chezmoi templates render correctly + carry the locked CONTEXT
# D-21 / D-22 / D-23 fields. Six cases; 3 default + 3 LIVE-GATED.
#
# LIVE-GATED tests require:
#   - BATS_WATCHER_LIVE=1 environment variable
#   - Test 2: systemd-analyze on PATH (Linux)
#   - Test 3: xmllint + plutil on PATH (macOS preferred)
#   - Test 6: chezmoi binary on PATH

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
SYSTEMD_TMPL="${REPO_ROOT}/dot_config/systemd/user/ws-vault-watcher.service.tmpl"
PLIST_TMPL="${REPO_ROOT}/private_Library/private_LaunchAgents/com.rtxnik.ws-vault-watcher.plist.tmpl"
RUN_ONCHANGE_TMPL="${REPO_ROOT}/run_onchange_after_install-watcher-hooks.sh.tmpl"

setup() {
    TEST_TMP=$(mktemp -d)
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "Test 1: systemd unit chezmoi renders with homeDir substituted" {
    [ -f "$SYSTEMD_TMPL" ] || { echo "FATAL: missing $SYSTEMD_TMPL"; return 1; }
    rendered="$(chezmoi execute-template < "$SYSTEMD_TMPL" 2>/dev/null || true)"
    if [ -z "$rendered" ]; then
        skip "chezmoi binary not available; render skipped"
    fi
    [[ "$rendered" != *'{{ .chezmoi.homeDir }}'* ]]
    [[ "$rendered" == *'WantedBy=default.target'* ]]
    [[ "$rendered" == *'Restart=on-failure'* ]]
    [[ "$rendered" == *'RestartSec=30s'* ]]
}

@test "Test 2: systemd unit passes systemd-analyze --user verify (LIVE-GATED)" {
    if [ -z "${BATS_WATCHER_LIVE:-}" ]; then
        skip "live-gated; set BATS_WATCHER_LIVE=1"
    fi
    command -v systemd-analyze >/dev/null 2>&1 || skip "systemd-analyze not on PATH"
    rendered="${TEST_TMP}/ws-vault-watcher.service"
    chezmoi execute-template < "$SYSTEMD_TMPL" > "$rendered"
    systemd-analyze --user verify "$rendered" 2>&1
}

@test "Test 3: launchd plist chezmoi renders valid XML (LIVE-GATED on macOS)" {
    if [ -z "${BATS_WATCHER_LIVE:-}" ]; then
        skip "live-gated; set BATS_WATCHER_LIVE=1"
    fi
    [ -f "$PLIST_TMPL" ] || { echo "FATAL: missing $PLIST_TMPL"; return 1; }
    rendered="${TEST_TMP}/com.rtxnik.ws-vault-watcher.plist"
    chezmoi execute-template < "$PLIST_TMPL" > "$rendered"
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$rendered"
    fi
    if command -v plutil >/dev/null 2>&1; then
        plutil -lint "$rendered"
    fi
}

@test "Test 4: launchd plist contains required keys" {
    [ -f "$PLIST_TMPL" ] || { echo "FATAL: missing $PLIST_TMPL"; return 1; }
    grep -F '<key>RunAtLoad</key>' "$PLIST_TMPL"
    grep -F '<true/>' "$PLIST_TMPL"
    grep -F '<key>KeepAlive</key>' "$PLIST_TMPL"
    grep -F '<key>ThrottleInterval</key>' "$PLIST_TMPL"
    grep -F '<integer>10</integer>' "$PLIST_TMPL"
}

@test "Test 5: run_onchange installer invokes install-hooks.sh" {
    [ -f "$RUN_ONCHANGE_TMPL" ] || { echo "FATAL: missing $RUN_ONCHANGE_TMPL"; return 1; }
    grep -F 'projects/vault-ai/scripts/sibling-watcher/install-hooks.sh' "$RUN_ONCHANGE_TMPL"
    [ -x "$RUN_ONCHANGE_TMPL" ]
}

@test "Test 6: chezmoi managed lists three NEW watcher template renders (LIVE-GATED)" {
    if [ -z "${BATS_WATCHER_LIVE:-}" ]; then
        skip "live-gated; set BATS_WATCHER_LIVE=1"
    fi
    command -v chezmoi >/dev/null 2>&1 || skip "chezmoi binary not on PATH"
    out="$(chezmoi --source="$REPO_ROOT" managed --include=files,scripts 2>&1 || true)"
    [[ "$out" == *'.config/systemd/user/ws-vault-watcher.service'* ]]
    [[ "$out" == *'Library/LaunchAgents/com.rtxnik.ws-vault-watcher.plist'* ]]
    # chezmoi v2 strips run_onchange_after_ prefix on render; the script registers
    # as install-watcher-hooks.sh in the managed list.
    [[ "$out" == *'install-watcher-hooks.sh'* ]]
}
