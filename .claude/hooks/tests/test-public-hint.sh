#!/usr/bin/env bash
# Integration: public-repo AI-hint scanning across forbidden-ai-attribution, secrets-scan, large-file-guard.
set -uo pipefail
# shellcheck source=../../../scripts/lib/testlib.sh
source "$(cd "$(dirname "$0")/../../../scripts/lib" && pwd)/testlib.sh"
t_init
HOOKDIR="$(cd "$(dirname "$0")/.." && pwd)"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/workspace-meta/repos"

setup_repo() {  # $1=name $2=visibility(public|none)
  local name="$1" vis="$2"
  mkdir -p "$root/$name/.claude/hooks/lib"
  ( cd "$root/$name" && git init -q && git checkout -q -b feat/x )
  cp "$HOOKDIR/lib/hooklib.sh" "$root/$name/.claude/hooks/lib/"
  cp "$HOOKDIR/forbidden-ai-attribution.sh" "$HOOKDIR/secrets-scan.sh" "$HOOKDIR/large-file-guard.sh" "$root/$name/.claude/hooks/"
  [ "$vis" = "public" ] && printf 'visibility: public\n' > "$root/workspace-meta/repos/$name.md"
  return 0
}

run() {  # name repo hook input expect_exit expect_grep(or "")
  local name="$1" repo="$2" hook="$3" input="$4" ee="$5" eg="$6"
  local ae=0 out okx=true
  out=$( cd "$root/$repo" && echo "$input" | bash ".claude/hooks/$hook.sh" 2>&1 ) || ae=$?
  [ "$ae" = "$ee" ] || okx=false
  if [ -n "$eg" ] && ! echo "$out" | grep -q "$eg"; then okx=false; fi
  if $okx; then echo "PASS: $name"; pass=$((pass+1)); else echo "FAIL: $name (exit=$ae want=$ee out=$out)"; fail=$((fail+1)); fi
}

setup_repo pubrepo public
setup_repo privrepo none

run "pub commit hint blocks" pubrepo forbidden-ai-attribution \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: x 🤖\""}}' 2 "BLOCKED"
touch "$root/pubrepo/.ai-mentions-allowed"
run "pub commit hint allowed with marker" pubrepo forbidden-ai-attribution \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: x 🤖\""}}' 0 ""
rm -f "$root/pubrepo/.ai-mentions-allowed"
run "priv commit hint ignored" privrepo forbidden-ai-attribution \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: x 🤖\""}}' 0 ""
run "pub write hint blocks" pubrepo secrets-scan \
  '{"tool_name":"Write","tool_input":{"file_path":"a.md","content":"This file is AI-generated"}}' 2 "BLOCKED"
run "pub write hint warns" pubrepo large-file-guard \
  '{"tool_name":"Write","tool_input":{"file_path":"a.md","content":"This file is AI-generated"}}' 0 "WARNING"
run "priv explicit attribution blocks" privrepo forbidden-ai-attribution \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\n\nCo-Authored-By: Claude <noreply@anthropic.com>\""}}' 2 "BLOCKED"

t_summary
