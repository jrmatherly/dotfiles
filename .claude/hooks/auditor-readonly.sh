#!/bin/bash
#
# Claude Code PreToolUse hook (Bash): inside the docs-auditor subagent, block
# (exit 2) any command that is not on its read-only allowlist. Other agents
# and the main session pass through untouched.
# Accepted gap: quoted text is stripped before matching, so a `sed -n` script
# using its w, W or e commands gets through. This guards the repo's own
# subagent against mistakes; it is not a security boundary.
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
  '^(sw_vers|mdfind|ls|wc|du|jq|cat|bat|head|tail|grep|rg|find|stat|file|which|sort|uniq|cut|tr|sed -n|diff|test|\[|echo|printf|cd|pwd|true|command -v|help|shellcheck)([[:space:]]|$)'
  '^brew (list|info)([[:space:]]|$)'
  '^mise (--version|ls)([[:space:]]|$)'
  '^defaults read([[:space:]]|$)'
  '^claude (--version|mcp get|plugin list)([[:space:]]|$)'
  '^uv tool list([[:space:]]|$)'
  '^curl -sf https?://127\.0\.0\.1(:[0-9]+)?(/[^[:space:]]*)?$'
  '^git (-C [^[:space:]]+ )?(log|show|diff|status|grep|rev-parse|ls-files|check-ignore|remote -v)([[:space:]]|$)'
  '^gh (run (list|view)|api)([[:space:]]|$)'
)
denied=(
  '^find .*(-delete|-exec|-ok|-fprint|-fls)'
  '^sed -n.*[[:space:]]-i'
  '^sort.*[[:space:]](-o|--output|--compress-program)'
  '^gh api.*[[:space:]](-X|-f|-F|--method|--field|--raw-field|--input)'
  '^git .*[[:space:]](-O|--open-files-in-pager|--output|--ext-diff|--textconv)'
  '^bat .*--pager'
  '^rg.*[[:space:]]--pre'
)

case $command in
  *'$('* | *'`'* | *'&>'* | *'<('* | *'>('* | *\\*) deny "$command" ;;
esac
# Quoted text is data, so a quoted `>` or `|` neither redirects nor splits
stripped=$(sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" <<< "$command")
case $stripped in
  *[\(\)\{\}]*) deny "$command" ;;
esac
# Before the split, so the `&` in 2>&1 is not taken for a background operator
stripped=$(sed -E 's#2>&1##g; s#2> ?/dev/null##g; s#> ?/dev/null##g' <<< "$stripped")
[[ $stripped == *'>'* ]] && deny "$command"

while IFS= read -r seg; do
  seg=${seg#"${seg%%[![:space:]]*}"}
  seg=${seg%"${seg##*[![:space:]]}"}
  [ -n "$seg" ] || continue
  ok=
  for re in "${allowed[@]}"; do
    [[ $seg =~ $re ]] && ok=1 && break
  done
  [ -n "$ok" ] || deny "$seg"
  for re in "${denied[@]}"; do
    [[ $seg =~ $re ]] && deny "$seg"
  done
done < <(sed -E 's/(&&|\|\||;|\||&)/\n/g' <<< "$stripped")
exit 0
