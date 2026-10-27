#!/bin/bash
#
# Claude Code PreToolUse hook (Bash): inside the docs-auditor subagent, block
# (exit 2) any command that is not on its read-only allowlist. Other agents
# and the main session pass through untouched.
# One quote-aware scan yields the text with quoted spans removed and the text
# with only the quote characters removed; the segments of both must match the
# allowlist, and the dequoted ones also face the curl URL check. For the tools
# whose options can write or run programs (git, gh, sort, uniq, find, bat, rg)
# every option token must be on that tool's allowlist: short options letter by
# letter, long options and find primaries as whole names, so an abbreviation
# like --out never passes as --output. sed is not allowed at all: its script
# can write (w, W, e, r) and is invisible once quotes are stripped; head, tail
# and grep -n cover line ranges. This guards the repo's own subagent against
# mistakes; it is not a security boundary. Fail closed on quoting it need not
# parse: a command mixing ' and ", or using $'...' (any $ outside single
# quotes), is denied.
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
  '^(sw_vers|mdfind|ls|wc|du|jq|cat|bat|head|tail|grep|rg|find|stat|which|sort|uniq|cut|tr|diff|test|\[|echo|printf|cd|pwd|true|command -v|help|shellcheck)([[:space:]]|$)'
  '^brew (list|info)([[:space:]]|$)'
  '^mise (--version|ls)([[:space:]]|$)'
  '^defaults read([[:space:]]|$)'
  '^claude (--version|mcp get|plugin list)([[:space:]]|$)'
  '^uv tool list([[:space:]]|$)'
  "$curl"
  '^git (-C [^[:space:]]+ )?((log|show|diff|status|grep|rev-parse|ls-files|check-ignore)([[:space:]]|$)|remote -v$)'
  '^gh (run (list|view)|api)([[:space:]]|$)'
)
# Per tool, the options it may take: single letters for short options, whole
# names for long options and find's primaries. Left out on purpose: git -O
# --output --ext-diff --textconv -c --git-dir --exec-path, gh -X --method -f -F
# --field --raw-field --input -w --web, sort -o --output --compress-program -T,
# find -exec -ok -execdir -delete -fprint -fls, bat --pager, rg --pre -z.
# curl needs no entry: its allow pattern admits -sf and a 127.0.0.1 URL only,
# and file is off the allowlist because file -C compiles a magic file into the
# working directory. A short option's value goes in its own word (sort -k 2,3,
# rg -g '*.md'): which letters take a value differs per subcommand (git grep -n
# is a switch, git log -n a count), so an attached value cannot be told from
# more options, and only a trailing count (-n5, -U3, -3) is admitted
flags_git='C n p a b w M i I E e v s z q r l u L S G W R U oneline graph decorate stat shortstat numstat summary name-only name-status format pretty date relative-date since until after before author committer grep all branches tags remotes abbrev-commit no-abbrev-commit abbrev no-pager no-color color cached staged porcelain short branch untracked-files ignored word-diff no-merges merges first-parent reverse follow patch no-patch max-count skip verify show-toplevel abbrev-ref is-inside-work-tree others exclude-standard full-history check unified ignore-space-change ignore-all-space quiet verbose line-number count files-with-matches extended-regexp fixed-strings ignore-case word-regexp invert-match only-matching no-index untracked recurse-submodules topo-order date-order'
flags_gh='L limit b branch workflow s status e event u user c commit created json jq q t template R repo a all log log-failed j job v verbose exit-status H header hostname paginate cache slurp i include silent'
flags_sort='n r u f b i d g h M V k t s c C z m numeric-sort reverse unique ignore-case ignore-leading-blanks dictionary-order general-numeric-sort human-numeric-sort month-sort version-sort key field-separator stable check zero-terminated merge ignore-nonprinting'
flags_uniq='c d u i f s w D count repeated unique ignore-case skip-fields skip-chars check-chars all-repeated'
flags_find='name iname path ipath regex iregex type maxdepth mindepth depth not o a or and size newer newermt mtime mmin ctime cmin atime amin empty prune print print0 ls perm user group links E L H P x d s'
flags_bat='p n l H r A P plain number language highlight-line line-range show-all paging style color decorations theme wrap tabs list-languages list-themes map-syntax'
flags_rg='i n l c v w F e g t T m A B C S s x o H N p L u a ignore-case smart-case case-sensitive line-number no-line-number files-with-matches files-without-match count count-matches invert-match word-regexp fixed-strings regexp glob iglob type type-not type-list max-count after-context before-context context only-matching with-filename no-filename hidden no-ignore files color heading no-heading max-depth sort sortr follow multiline multiline-dotall pcre2 trim vimgrep json stats no-messages quiet passthru text'

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
# Every option token of a flag-bearing tool must be on its list. A short bundle
# is allowed letters, then at most a trailing count; a long option is checked by
# the whole name before any `=`. uniq's second operand is its output, so it may
# name only one: `-` (stdin) is an operand, and so is any token after the first
# operand or after `--`, because macOS getopt stops parsing options there
# (`uniq a -c` writes a file named -c)
check_flags() {
  local set toks tok name c i positional=0 operands_only=
  read -ra toks <<< "$1"
  case ${toks[0]} in
    git) set=$flags_git ;;
    gh) set=$flags_gh ;;
    sort) set=$flags_sort ;;
    uniq) set=$flags_uniq ;;
    find) set=$flags_find ;;
    bat) set=$flags_bat ;;
    rg) set=$flags_rg ;;
    *) return 0 ;;
  esac
  for tok in "${toks[@]:1}"; do
    if [ "${toks[0]}" = uniq ] && { [ -n "$operands_only" ] || [ "$positional" -gt 0 ]; }; then
      positional=$((positional + 1))
      continue
    fi
    case $tok in
      --) operands_only=1 ;;
      -) positional=$((positional + 1)) ;;
      --*)
        name=${tok#--}
        name=${name%%=*}
        [[ " $set " == *" $name "* ]] || deny "${toks[0]} option not allowed" "$tok"
        ;;
      -*)
        name=${tok#-}
        if [ "${toks[0]}" = find ]; then
          [[ " $set " == *" $name "* ]] || deny 'find primary not allowed' "$tok"
        else
          name=${name%%[0-9]*}
          [[ $tok =~ ^-[[:alpha:]]*[0-9]*$ ]] || deny "${toks[0]} option value must be its own word" "$tok"
          for ((i = 0; i < ${#name}; i++)); do
            c=${name:i:1}
            [[ " $set " == *" $c "* ]] || deny "${toks[0]} option not allowed" "$tok"
          done
        fi
        ;;
      *) positional=$((positional + 1)) ;;
    esac
  done
  [ "${toks[0]}" = uniq ] && [ "$positional" -gt 1 ] && deny 'uniq writes its second file' "$1"
  return 0
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
  check_flags "$seg"
done < <(segments "$stripped")
while IFS= read -r seg; do
  check_allowed "$seg"
  check_flags "$seg"
  [[ $seg == 'curl '* && ! $seg =~ $curl ]] && deny 'curl URL' "$seg"
done < <(segments "$dequoted")

# Every segment passed the allowlist, so approve the call: the forked auditor
# runs non-interactive, and a call auto mode's classifier escalated to a
# prompt was denied with nobody to ask (2026-10-27). Deny and ask rules still
# apply over a hook's allow
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"auditor-readonly: every command is on the read-only allowlist"}}'
exit 0
