#!/bin/bash
#
# Self-check for auditor-readonly.sh. Run: .claude/hooks/test-auditor-readonly.sh

set -euo pipefail

hook=$(cd "$(dirname "$0")" && pwd -P)/auditor-readonly.sh

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
# Feed the hook a PreToolUse payload from agent $2 (docs-auditor by default); sets rc
run() {
  local payload
  payload=$(jq -cn --arg c "$1" --arg a "${2-docs-auditor}" '{tool_name:"Bash",tool_input:{command:$c},agent_type:$a}')
  rc=0
  "$hook" <<< "$payload" 2> /dev/null || rc=$?
}
allow() {
  run "$1"
  [ "$rc" -eq 0 ] || fail "denied (rc=$rc): $1"
}
deny() {
  run "$1"
  [ "$rc" -eq 2 ] || fail "allowed (rc=$rc): $1"
}

allow 'brew list --versions shellcheck'
allow 'git log --oneline -5 && gh run list --limit 3'
allow "jq '.a | keys' ~/.claude/settings.json"
allow "grep -E 'a|b' README.md"
allow "grep '=>' zsh/aliases.zsh"
allow "sed -n '1p;2p' setup.sh"
allow 'curl -sf http://127.0.0.1:9077/health 2>&1'
allow 'ls /nonexistent > /dev/null 2>&1'
allow 'git -C /tmp/x show HEAD'
allow 'help upup'
deny 'brew install foo'
deny 'cat x > y'
deny 'jq . a | tee b'
deny 'git log; rm -rf x'
deny 'ls $(rm x)'
deny 'find . -name x -delete'
deny 'sed -n -i 1p x'
deny 'gh api -X DELETE repos/a/b'
deny 'curl -sf http://127.0.0.1.evil/x'
deny 'git diff 2> /tmp/x'
deny 'defaults write com.apple.dock tilesize 36'
deny 'sudo ls'
deny 'claude plugin install foo'
deny "echo 'x' > out"
deny 'sort -o x y'
deny 'cat <(rm x)'
allow "grep 'a\.b' README.md"
deny "echo \\\"x; rm f"
deny "grep 'it\\'s' f"
deny 'ls & rm x'
deny '(rm x)'
deny '{ rm x; }'
deny "awk '{print > \"f\"}' x"
deny 'curl -sf http://127.0.0.1:9077/health -o /tmp/x'
deny 'curl -sf http://127.0.0.1:9077/health -d @x'
deny 'git log -O/tmp/p'
deny 'git diff --output=/tmp/x'
deny 'gh api -XDELETE repos/a/b'
deny 'gh api --method=DELETE repos/a/b'
deny 'sort --output=x y'
deny 'find . -fls /tmp/x'
deny "bat --pager 'rm x' f"
deny 'rg --pre rm x'
deny "gh api '-X' DELETE repos/a/b"
deny "sort '-o' x y"
deny 'git log -"O"/tmp/p'
deny "curl -sf http://127.0.0.1:9077/x '-o' /tmp/f"
deny 'rg \--pre=sh x .'
deny 'find . -e\xec rm {} +'
deny 'find . -e\xec rm +'
deny 'grep "a\.b" f'
# another agent, or the main session, is never touched
run 'brew install foo' general-purpose
[ "$rc" -eq 0 ] || fail "non-auditor agent was gated"
run 'brew install foo' ''
[ "$rc" -eq 0 ] || fail "main session was gated"

echo "auditor-readonly: all checks passed"
