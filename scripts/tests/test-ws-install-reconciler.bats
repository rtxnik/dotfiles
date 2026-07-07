#!/usr/bin/env bats
# The ws install script is a state reconciler: it must no-op silently when the
# installed binary is healthy and current, keep a healthy binary when the
# latest-check is unreachable (fail-open on the check), refuse an installer
# whose embedded signing key differs from the pinned one (the trust root must
# not float with the "latest" channel), and repair a missing binary end-to-end.
# All network access goes through the WS_API_URL / WS_RAW_BASE seams (file://).

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
SCRIPT="${REPO_ROOT}/.chezmoiscripts/run_after_install-ws.sh.tmpl"
PUBKEY="RWS9SKDBxXVQRL27p1aOVmdoSffl83dqJqKtnwDO6IqEMpdoRf+AMDGL"

setup() {
  H="${BATS_TEST_TMPDIR}/home"; mkdir -p "$H/.local/bin"
  API="${BATS_TEST_TMPDIR}/api.json"
  RAW="${BATS_TEST_TMPDIR}/raw"
  STUB="${BATS_TEST_TMPDIR}/stub"; mkdir -p "$STUB"
  printf '#!/bin/sh\nexit 0\n' > "${STUB}/minisign"; chmod +x "${STUB}/minisign"
}

mk_ws() { # $1 = version the fake binary reports
  printf '#!/bin/sh\necho "ws %s"\n' "$1" > "$H/.local/bin/ws"
  chmod +x "$H/.local/bin/ws"
}

@test "runs every apply (run_after_, not run_onchange_) and pins no version" {
  [ -f "$SCRIPT" ]
  [ ! -f "${REPO_ROOT}/.chezmoiscripts/run_onchange_after_install-ws.sh.tmpl" ]
  run grep -E '^WS_VERSION="v[0-9]' "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "healthy and current: silent no-op, binary untouched" {
  mk_ws 9.9.9
  printf '{"tag_name": "v9.9.9"}\n' > "$API"
  before=$(ls -i "$H/.local/bin/ws" | awk '{print $1}')
  run env HOME="$H" WS_API_URL="file://${API}" sh "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  after=$(ls -i "$H/.local/bin/ws" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "latest unreachable + healthy binary: fail-open keep with warning" {
  mk_ws 9.9.9
  run env HOME="$H" WS_API_URL="file://${BATS_TEST_TMPDIR}/nonexistent.json" sh "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"keeping installed ws 9.9.9"* ]]
}

@test "latest unreachable + no working binary: fails with actionable message" {
  run env HOME="$H" WS_API_URL="file://${BATS_TEST_TMPDIR}/nonexistent.json" sh "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"WS_PIN"* ]]
}

@test "WS_PIN overrides the latest channel entirely" {
  mk_ws 9.9.9
  run env HOME="$H" WS_PIN=v9.9.9 WS_API_URL="file://${BATS_TEST_TMPDIR}/nonexistent.json" sh "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "installer embedding a different signing key is refused" {
  mk_ws 9.9.9
  printf '{"tag_name": "v9.9.10"}\n' > "$API"
  mkdir -p "${RAW}/v9.9.10/scripts"
  printf '#!/bin/sh\nRELEASE_PUBKEY="RWSFAKEKEYFAKEKEYFAKEKEY"\n' > "${RAW}/v9.9.10/scripts/install.sh"
  run env HOME="$H" PATH="${STUB}:${PATH}" WS_API_URL="file://${API}" WS_RAW_BASE="file://${RAW}" sh "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unexpected signing key"* ]]
}

@test "missing binary: installs via the fetched installer and verifies the result" {
  printf '{"tag_name": "v9.9.10"}\n' > "$API"
  mkdir -p "${RAW}/v9.9.10/scripts"
  cat > "${RAW}/v9.9.10/scripts/install.sh" <<EOF
#!/bin/sh
RELEASE_PUBKEY="${PUBKEY}"
mkdir -p "\${HOME}/.local/bin"
printf '#!/bin/sh\necho "ws 9.9.10"\n' > "\${HOME}/.local/bin/ws"
chmod +x "\${HOME}/.local/bin/ws"
EOF
  run env HOME="$H" PATH="${STUB}:${PATH}" WS_API_URL="file://${API}" WS_RAW_BASE="file://${RAW}" sh "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ws 9.9.10 verified"* ]]
}

@test "broken binary (executes but reports nothing) triggers reinstall" {
  printf '#!/bin/sh\nexit 137\n' > "$H/.local/bin/ws"; chmod +x "$H/.local/bin/ws"
  printf '{"tag_name": "v9.9.10"}\n' > "$API"
  mkdir -p "${RAW}/v9.9.10/scripts"
  cat > "${RAW}/v9.9.10/scripts/install.sh" <<EOF
#!/bin/sh
RELEASE_PUBKEY="${PUBKEY}"
mkdir -p "\${HOME}/.local/bin"
printf '#!/bin/sh\necho "ws 9.9.10"\n' > "\${HOME}/.local/bin/ws"
chmod +x "\${HOME}/.local/bin/ws"
EOF
  run env HOME="$H" PATH="${STUB}:${PATH}" WS_API_URL="file://${API}" WS_RAW_BASE="file://${RAW}" sh "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"installing ws v9.9.10 (no working binary"* ]]
  [[ "$output" == *"ws 9.9.10 verified"* ]]
}
