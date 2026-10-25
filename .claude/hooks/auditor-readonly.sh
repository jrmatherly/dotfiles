#!/bin/bash
#
# Claude Code PreToolUse hook (Bash): inside the docs-auditor subagent, block
# (exit 2) any command that is not on its read-only allowlist. Other agents
# and the main session pass through untouched.
# Wired up in .claude/settings.json; self-check: .claude/hooks/test-auditor-readonly.sh

set -uo pipefail

input=$(cat)
[ "$(jq -r '.agent_type // empty' <<< "$input")" = docs-auditor ] || exit 0
command=$(jq -r '.tool_input.command // empty' <<< "$input")

deny() {
  echo "auditor-readonly: not allowed: $1" >&2
  exit 2
}

allowed=(
  '^(sw_vers|mdfind|ls|wc|du|jq|cat|bat|head|tail|grep|rg|find|stat|file|which|sort|uniq|cut|tr|awk|sed -n|diff|test|\[|echo|printf|cd|pwd|true|command -v|help|shellcheck)([[:space:]]|$)'
  '^brew (list|info)([[:space:]]|$)'
  '^mise (--version|ls)([[:space:]]|$)'
  '^defaults read([[:space:]]|$)'
  '^claude (--version|mcp get|plugin list)([[:space:]]|$)'
  '^uv tool list([[:space:]]|$)'
  '^curl -sf https?://127\.0\.0\.1(:[0-9]+)?(/|$)'
  '^git (-C [^[:space:]]+ )?(log|show|diff|status|grep|rev-parse|ls-files|check-ignore|remote -v)([[:space:]]|$)'
  '^gh (run (list|view)|api)([[:space:]]|$)'
)
denied=(
  '^find .*(-delete|-exec|-ok|-fprint)'
  '^sed -n.*[[:space:]]-i'
  '^sort.*[[:space:]]-o([[:space:]]|$)'
  '^gh api.*[[:space:]](-X|--method|-f|-F|--field|--raw-field|--input)([[:space:]]|$)'
  '^awk .*system\('
)

case $command in
  *'$('* | *'`'* | *'&>'*) deny "$command" ;;
esac
# Quoted text is data, so a quoted `>` or `|` neither redirects nor splits
stripped=$(sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" <<< "$command")
redirects=$(sed -E 's#2>&1##g; s#2> ?/dev/null##g; s#> ?/dev/null##g' <<< "$stripped")
[[ $redirects == *'>'* ]] && deny "$command"

while IFS= read -r seg; do
  seg=${seg#"${seg%%[![:space:]]*}"}
  [ -n "$seg" ] || continue
  ok=
  for re in "${allowed[@]}"; do
    [[ $seg =~ $re ]] && ok=1 && break
  done
  [ -n "$ok" ] || deny "$seg"
  for re in "${denied[@]}"; do
    [[ $seg =~ $re ]] && deny "$seg"
  done
done < <(sed -E 's/(&&|\|\||;|\|)/\n/g' <<< "$stripped")
exit 0
