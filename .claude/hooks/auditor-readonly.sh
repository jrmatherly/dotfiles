#!/bin/bash
#
# Claude Code PreToolUse hook (Bash): inside the docs-auditor subagent, block
# (exit 2) any command that is not on its read-only allowlist. Other agents
# and the main session pass through untouched.
# One quote-aware scan yields the text with quoted spans removed (the allowlist
# and deny patterns run on its segments) and the text with only the quote
# characters removed (deny patterns and the curl URL check run on its segments).
# Accepted gap: quoted text is stripped before matching, so a `sed -n` script
# using its w, W or e commands gets through. This guards the repo's own
# subagent against mistakes; it is not a security boundary. Fail closed on
# quoting it need not parse: a command mixing ' and ", or using $'...' (any $
# outside single quotes), is denied.
# Wired up in .claude/settings.json; self-check: .claude/hooks/test-auditor-readonly.sh

set -uo pipefail

input=$(cat)
[ "$(jq -r '.agent_type // empty' <<< "$input")" = docs-auditor ] || exit 0
command=$(jq -r '.tool_input.command // empty' <<< "$input")

deny() {
  echo "auditor-readonly: not allowed: $1" >&2
  exit 2
}

curl='^curl -sf https?://127\.0\.0\.1(:[0-9]+)?(/[^[:space:]]*)?$'
allowed=(
  '^(sw_vers|mdfind|ls|wc|du|jq|cat|bat|head|tail|grep|rg|find|stat|file|which|sort|uniq|cut|tr|sed -n|diff|test|\[|echo|printf|cd|pwd|true|command -v|help|shellcheck)([[:space:]]|$)'
  '^brew (list|info)([[:space:]]|$)'
  '^mise (--version|ls)([[:space:]]|$)'
  '^defaults read([[:space:]]|$)'
  '^claude (--version|mcp get|plugin list)([[:space:]]|$)'
  '^uv tool list([[:space:]]|$)'
  "$curl"
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

# Drop the tolerated redirects, split on command separators, trim, skip empties.
# The redirects go first, so the `&` in 2>&1 is not taken for a background operator
segments() {
  sed -E 's#2>&1##g; s#2> ?/dev/null##g; s#> ?/dev/null##g; s/(&&|\|\||;|\||&)/\n/g' <<< "$1" \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; /^$/d'
}
check_denied() {
  local re
  for re in "${denied[@]}"; do
    [[ $1 =~ $re ]] && deny "$1"
  done
}

# Bash's own quote rules, left to right: sets stripped (quoted spans dropped)
# and dequoted (quote characters dropped, separators inside spans made spaces,
# so a quoted `;` cannot split a flag off its command). Outside single quotes
# a backslash or `$` would rewrite the words the patterns see, so it is denied,
# and so is an unclosed quote
scan() {
  local c i q=
  stripped='' dequoted=''
  for ((i = 0; i < ${#command}; i++)); do
    c=${command:i:1}
    if [ -n "$q" ] && [ "$c" = "$q" ]; then
      q=
    elif [ -n "$q" ]; then
      [ "$q" = '"' ] && [[ $c == [\\$] ]] && deny "$command"
      [[ $c == [\;\|\&$'\n'] ]] && c=' '
      dequoted+=$c
    elif [[ $c == [\'\"] ]]; then
      q=$c
    else
      [[ $c == [\\$] ]] && deny "$command"
      stripped+=$c
      dequoted+=$c
    fi
  done
  [ -z "$q" ] || deny "$command"
}

case $command in
  *'$('* | *'`'* | *'&>'* | *'<('* | *'>('*) deny "$command" ;;
  *\'*\"* | *\"*\'*) deny "$command" ;;
esac
scan
case $stripped in
  *[\(\)\{\}]*) deny "$command" ;;
esac
[[ $(segments "$stripped") == *'>'* ]] && deny "$command"

while IFS= read -r seg; do
  ok=
  for re in "${allowed[@]}"; do
    [[ $seg =~ $re ]] && ok=1 && break
  done
  [ -n "$ok" ] || deny "$seg"
  check_denied "$seg"
done < <(segments "$stripped")
while IFS= read -r seg; do
  check_denied "$seg"
  [[ $seg == 'curl '* && ! $seg =~ $curl ]] && deny "$seg"
done < <(segments "$dequoted")
exit 0
