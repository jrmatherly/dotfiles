#!/bin/bash
#
# Self-check for auditor-readonly.sh. Run: .claude/hooks/test-auditor-readonly.sh

set -euo pipefail

hook=$(cd "$(dirname "$0")" && pwd -P)/auditor-readonly.sh

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
# Feed the hook a PreToolUse payload from agent $2 (docs-auditor by default); sets rc and out
run() {
  local payload
  payload=$(jq -cn --arg c "$1" --arg a "${2-docs-auditor}" '{tool_name:"Bash",tool_input:{command:$c},agent_type:$a}')
  rc=0
  out=$("$hook" <<< "$payload" 2> /dev/null) || rc=$?
}
allow() {
  run "$1"
  [ "$rc" -eq 0 ] || fail "denied (rc=$rc): $1"
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$out")" = allow ] || fail "not approved: $1"
}
deny() {
  run "$1"
  [ "$rc" -eq 2 ] || fail "allowed (rc=$rc): $1"
}

allow 'brew list --versions shellcheck'
# Another agent's calls get no decision from this hook, so normal permissions apply
run 'rm -rf x' general-purpose
[ "$rc" -eq 0 ] && [ -z "$out" ] || fail "decided for another agent: rc=$rc out=$out"
allow 'git log --oneline -5 && gh run list --limit 3'
allow "jq '.a | keys' ~/.claude/settings.json"
allow "grep -E 'a|b' README.md"
allow "grep '=>' zsh/aliases.zsh"
deny "sed -n '1p;2p' setup.sh"
allow 'head -n 20 setup.sh | tail -n 5'
allow 'grep -n Brewfile README.md'
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
deny "gh api ';' '-X' DELETE repos/a/b"
deny "echo \"it's\" ; rm x ; echo 'y'"
deny "curl -sf http://127.0.0.1'.evil.com'/x"
deny "curl -sf http://127.0.0.1'@evil.com'/x"
deny 'gh api -X${IFS}DELETE repos/a/b'
deny 'gh api $IFS-X DELETE repos/a/b'
deny 'ls $HOME'
deny 'grep "a$" f'
deny "grep 'a"
allow "grep 'a\$' f"
deny "grep \"it's\" f"
deny "echo \$'x' f"
deny "'rm' ls"
deny '"rm" -rf x'
deny $'ls # "\nrm x # "'
deny $'cat <<EOF\nx\nEOF'
deny $'grep \'a\nb\' f'
deny 'ls # x'
deny 'cat <<EOF'
deny $'grep \'a\nls\' f'
allow "grep '#' README.md"
deny 'sort -uoout in'
deny 'sed -n -Ei.bak 1p f'
deny 'git grep -iOrm foo'
deny 'gh api -iXDELETE repos/a/b'
deny 'sed -n --in-place 1p f'
deny 'git remote -v add evil https://x'
deny 'uniq a b'
allow 'git remote -v'
allow 'sort x | uniq -c'
allow 'uniq -c x'
allow 'git -C /tmp/x log --oneline -3'
allow 'brew list --versions jq'
allow 'gh api --jq .x repos/a/b'
allow 'git log --since 2.days --format=%h -- setup.sh'
allow 'sort -t , -k 2,3 -nr x'
deny 'sort -t, -k2,3 x'
allow 'find . -maxdepth 2 -name x -type f'
allow 'rg -in --glob=*.md foo .'
allow 'bat -pr 1:5 f'
# an abbreviated long option or an unlisted one never matches
deny 'git log --out=/tmp/x'
deny 'sort --outp=x y'
deny 'git -c core.pager=rm log'
deny 'git --exec-path=/tmp log'
deny 'gh api --input x repos/a/b'
deny 'gh run view 1 -w'
deny 'rg -z foo .'
deny 'find . -execdir rm x +'
# a short bundle is allowed letters plus at most a trailing count
allow 'git log -n5 -3'
allow 'git diff -U3'
deny 'git grep -nOrm foo'
deny 'gh api -tXDELETE repos/a/b'
deny "rg -g'*.md' foo ."
# macOS getopt stops at the first operand, so later tokens are operands too
deny 'uniq a -c'
deny 'uniq -- a b'
allow 'rg -iA2 foo .'
deny 'git log -3O/tmp/p'
deny 'sort -n5o x'
deny 'uniq - out'
deny 'file -C -m x'
# sed is off the allowlist: its script can write
deny "sed -n 'w /tmp/x' f"
deny "sed -n '1e rm x' f"
deny "sed -n '1r /etc/passwd' f"
deny "sed -n 's/a/b/w /tmp/x' f"
# another agent, or the main session, is never touched
run 'brew install foo' general-purpose
[ "$rc" -eq 0 ] || fail "non-auditor agent was gated"
run 'brew install foo' ''
[ "$rc" -eq 0 ] || fail "main session was gated"

echo "auditor-readonly: all checks passed"
