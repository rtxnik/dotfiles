#!/usr/bin/env bash
# Tests for secrets-scan.sh hook
set -euo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOK="$(dirname "$0")/../secrets-scan.sh"

run_test() {
  local name="$1" input="$2" expect_exit="$3"
  actual_exit=0
  output=$(echo "$input" | bash "$HOOK" 2>&1) || actual_exit=$?
  if [ "$actual_exit" -eq "$expect_exit" ]; then
    echo "PASS: $name"
    pass=$((pass+1))
  else
    echo "FAIL: $name (expected exit $expect_exit, got $actual_exit)"
    echo "  output: $output"
    fail=$((fail+1))
  fi
}

# Should block: AWS access key
run_test "block AWS key" \
  '{"tool_name":"Write","tool_input":{"file_path":"config.py","content":"aws_key = \"AKIAIOSFODNN7EXAMPLE\""}}' \
  2

# Should block: private key
run_test "block private key" \
  '{"tool_name":"Write","tool_input":{"file_path":"key.pem","content":"-----BEGIN RSA PRIVATE KEY-----\nMIIEpA..."}}' \
  2

# Should block: GitHub token
run_test "block GitHub token" \
  '{"tool_name":"Write","tool_input":{"file_path":"ci.sh","content":"TOKEN=ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij"}}' \
  2

# Should block: password assignment
run_test "block password assignment" \
  '{"tool_name":"Write","tool_input":{"file_path":"config.py","content":"db_password = \"SuperSecret123!\""}}' \
  2

# Should block: OpenAI/Anthropic key
run_test "block sk- key" \
  '{"tool_name":"Write","tool_input":{"file_path":"ai.py","content":"api_key = \"sk-proj-abcdefghijklmnopqrstuv\""}}' \
  2

# Should allow: normal code
run_test "allow normal code" \
  '{"tool_name":"Write","tool_input":{"file_path":"main.py","content":"def hello():\n    return \"world\""}}' \
  0

# Should allow: Edit with no secrets
run_test "allow clean Edit" \
  '{"tool_name":"Edit","tool_input":{"file_path":"main.py","old_string":"foo","new_string":"bar"}}' \
  0

# Should allow: non-Edit/Write tools (passthrough)
run_test "passthrough Bash" \
  '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
  0

# Should allow: env var reference (not literal secret)
run_test "allow env var reference" \
  '{"tool_name":"Write","tool_input":{"file_path":"config.py","content":"password = os.environ[\"DB_PASSWORD\"]"}}' \
  0

# Should block: Slack token
run_test "block Slack token" \
  '{"tool_name":"Write","tool_input":{"file_path":"bot.py","content":"SLACK_TOKEN=\"xoxb-1234567890-abcdefghij\""}}' \
  2

# Should block: GitLab token
run_test "block GitLab token" \
  '{"tool_name":"Edit","tool_input":{"file_path":".env","old_string":"TOKEN=old","new_string":"TOKEN=glpat-abcdefghijklmnopqrstuv"}}' \
  2

# --- P5 / Finding J: delta scan of simulated post-edit content ---
# Tokens are assembled at runtime so this file never contains a raw match.
SK_TOK="sk-""ABCDEFGHIJKLMNOPQRSTUV"
GHP_TOK="ghp_""ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij"
AKIA_TOK="AKIA""IOSFODNN7EXAMPLE"
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

# Secret assembled across the edit boundary: neither old_string nor new_string
# matches alone; the simulated post-edit content does.
printf 'token = "sk-" + suffix\n' > "$sandbox/join.py"
run_test "block secret assembled across edit boundary" \
  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$sandbox/join.py\",\"old_string\":\"\\\" + suffix\",\"new_string\":\"ABCDEFGHIJKLMNOPQRSTUV\\\"\"}}" \
  2

# Removing an existing secret must stay allowed (remediation).
printf 'key = "%s"\n' "$SK_TOK" > "$sandbox/fix.py"
run_test "allow removing an existing secret" \
  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$sandbox/fix.py\",\"old_string\":\"key = \\\"$SK_TOK\\\"\",\"new_string\":\"key = os.environ[\\\"KEY\\\"]\"}}" \
  0

# A clean edit to a file that ALREADY contains fixture secrets must stay allowed
# (this is the regression a naive full-file scan would introduce).
printf 'example = "%s"\nhello\n' "$AKIA_TOK" > "$sandbox/fixture.py"
run_test "allow clean edit to fixture-bearing file" \
  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$sandbox/fixture.py\",\"old_string\":\"hello\",\"new_string\":\"world\"}}" \
  0

# Unreadable/absent file: fall back to scanning new_string alone (old behavior).
run_test "block secret in new_string when file absent" \
  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/nonexistent/x.py\",\"old_string\":\"a\",\"new_string\":\"TOKEN=$GHP_TOK\"}}" \
  2

# replace_all join: every occurrence replaced before the delta is computed.
printf 'a = "sk-" + s\nb = "sk-" + s\n' > "$sandbox/all.py"
run_test "block secret assembled via replace_all" \
  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$sandbox/all.py\",\"old_string\":\"\\\" + s\",\"new_string\":\"ABCDEFGHIJKLMNOPQRSTUV\\\"\",\"replace_all\":true}}" \
  2

# F2: a block must leave an audit line.
# Token assembled at runtime (two halves) so this file never contains a contiguous literal.
alog="$(mktemp -d)/audit.jsonl"
_tok=$(printf '%s%s' "AKIA" "IOSFODNN7EXAMPLE")
blocking_payload=$(jq -cn --arg tok "$_tok" '{"tool_name":"Write","tool_input":{"file_path":"cfg.py","content":("k = \"" + $tok + "\"")}}')
printf '%s' "$blocking_payload" | WORKFLOW_AUDIT_PATH="$alog" bash "$HOOK" >/dev/null 2>&1 || true
if [ -s "$alog" ] && tail -n1 "$alog" | jq -e '.result=="block"' >/dev/null 2>&1; then
  echo "PASS: block audited"
  pass=$((pass+1))
else
  echo "FAIL: no audit line on block"; fail=$((fail+1))
fi

# --- F3 / D5-1: the Edit/Write veto inherits the gitleaks layer ---
AGE_TKN="AGE-SECRET-KEY-1$(printf 'Q%.0s' $(seq 1 58))"
if command -v gitleaks >/dev/null 2>&1; then
  run_test "block gitleaks-class secret (age key)" \
    "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"x.txt\",\"content\":\"k=$AGE_TKN\"}}" 2
  # floor-only mode misses this class — proves the layer (not the floor) caught it
  rc=0
  printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"x.txt\",\"content\":\"k=$AGE_TKN\"}}" \
    | WORKFLOW_SECRETS_GITLEAKS=off bash "$HOOK" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then echo "PASS: engine-off falls back to floor (age key passes)"; pass=$((pass+1));
  else echo "FAIL: engine-off fallback (exit=$rc)"; fail=$((fail+1)); fi
else
  echo "SKIP: gitleaks not on PATH — hybrid veto case skipped"
fi

t_summary
