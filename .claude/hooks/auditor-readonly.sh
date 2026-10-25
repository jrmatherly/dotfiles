#!/bin/bash
#
# Claude Code PreToolUse hook (Bash): inside the docs-auditor subagent, block
# (exit 2) any command that is not on its read-only allowlist. Other agents
# and the main session pass through untouched.
# One quote-aware scan yields the text with quoted spans removed and the text
# with only the quote characters removed; the segments of both must match the
# allowlist and no deny pattern, and the dequoted ones also face the curl URL check.
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

# deny <rule> <text>: the rule tells the auditor what to change
deny() {
  echo "auditor-readonly: not allowed ($1): $2" >&2
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
  '^git (-C [^[:space:]]+ )?((log|show|diff|status|grep|rev-parse|ls-files|check-ignore)([[:space:]]|$)|remote -v$)'
  '^gh (run (list|view)|api)([[:space:]]|$)'
)
# A segment matching one of these is denied although its prefix is allowed.
# Short flags may be bundled (sort -uo, sed -Ei, git grep -iO), hence the
# letters allowed between the dash and the flag; uniq's second file is its output
denied=(
  '^find .*(-delete|-exec|-ok|-fprint|-fls)'
  '^sed -n.*[[:space:]](-[[:alnum:]]*i|--in-place)'
  '^sort.*[[:space:]](-[[:alnum:]]*o|--output|--compress-program)'
  '^gh api.*[[:space:]](-[[:alnum:]]*[XfF]|--method|--field|--raw-field|--input)'
  '^git .*[[:space:]](-[[:alnum:]]*O|--open-files-in-pager|--output|--ext-diff|--textconv)'
  '^uniq([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^-[:space:]][^[:space:]]*[[:space:]]+[^-[:space:]]'
  '^bat .*--pager'
  '^rg.*[[:space:]]--pre'
)

# Drop the tolerated redirects, split on command separators, trim, skip empties.
# The redirects go first, so the `&` in 2>&1 is not taken for a background operator
segments() {
  sed -E 's#2>&1##g; s#2> ?/dev/null##g; s#> ?/dev/null##g; s/(&&|\|\||;|\||&)/\n/g' <<< "$1" \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; /^$/d'
}
check_allowed() {
  local re
  for re in "${allowed[@]}"; do
    [[ $1 =~ $re ]] && return 0
  done
  deny 'not in the allowlist' "$command"
}
check_denied() {
  local re
  for re in "${denied[@]}"; do
    [[ $1 =~ $re ]] && deny 'denied flag or argument' "$1"
  done
}

# Bash's own quote rules, left to right: sets stripped (quoted spans dropped)
# and dequoted (quote characters dropped, separators inside spans made spaces,
# so a quoted `;` cannot split a flag off its command). Outside single quotes
# a backslash or `$` would rewrite the words the patterns see, and a `#` or
# `<<` would hide the rest of a line or the next lines (a comment, a heredoc),
# so these are denied, as are a quoted newline and an unclosed quote
scan() {
  local c i q=
  stripped='' dequoted=''
  for ((i = 0; i < ${#command}; i++)); do
    c=${command:i:1}
    if [ -n "$q" ] && [ "$c" = "$q" ]; then
      q=
    elif [ -n "$q" ]; then
      [ "$q" = '"' ] && [[ $c == [\\$] ]] && deny 'backslash or $ outside single quotes' "$command"
      [ "$c" = $'\n' ] && deny 'quoted newline' "$command"
      [[ $c == [\;\|\&] ]] && c=' '
      dequoted+=$c
    elif [[ $c == [\'\"] ]]; then
      q=$c
    else
      [[ $c == '\' || $c == '$' ]] && deny 'backslash or $ outside single quotes' "$command"
      [[ $c == '#' || ${command:i:2} == '<<' ]] && deny 'comment or heredoc' "$command"
      stripped+=$c
      dequoted+=$c
    fi
  done
  [ -z "$q" ] || deny 'unclosed quote' "$command"
}

case $command in
  *'$('* | *'`'* | *'<('* | *'>('*) deny 'command or process substitution' "$command" ;;
  *'&>'*) deny 'redirect' "$command" ;;
  *\'*\"* | *\"*\'*) deny 'mixed quotes' "$command" ;;
esac
scan
case $stripped in
  *[\(\)\{\}]*) deny 'braces or parentheses' "$command" ;;
esac
[[ $(segments "$stripped") == *'>'* ]] && deny 'redirect' "$command"

while IFS= read -r seg; do
  check_allowed "$seg"
  check_denied "$seg"
done < <(segments "$stripped")
while IFS= read -r seg; do
  check_allowed "$seg"
  check_denied "$seg"
  [[ $seg == 'curl '* && ! $seg =~ $curl ]] && deny 'curl URL' "$seg"
done < <(segments "$dequoted")
exit 0
