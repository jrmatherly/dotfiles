#!/bin/bash
#
# Claude Code PreToolUse hook (Bash): before a `git commit`, run `pnpm check`
# in the repo the commit targets and block the call (exit 2, the check's tail
# on stderr) when it fails. When it passes but setup or mise files changed
# with no README, it tells Claude so through additionalContext.
# Wired up in .claude/settings.json; self-check: .claude/hooks/test-commit-gate.sh

set -uo pipefail
# Word splitting below must not expand globs in the command
set -f

input=$(cat)
command=$(jq -r '.tool_input.command // empty' <<< "$input")
cwd=$(jq -r '.cwd // empty' <<< "$input")
cwd=${cwd:-${CLAUDE_PROJECT_DIR:-$(pwd -P)}}

# Resolve $1 against $2 into dir, as cd and git -C would (no quotes, so no
# spaces; a leading ~ is the one expansion a bare word gets)
enter() {
  case $1 in
    /*) dir=$1 ;;
    [~] | [~]/*) dir=$HOME${1:1} ;;
    *) dir=$2/$1 ;;
  esac
}

# A segment is a commit when its command word (after NAME=value prefixes,
# env, time, exec, command and the keywords that open a group or branch) is
# git and a later word is `commit`; quoted text is not parsed. dir follows
# each `cd <dir>` segment before it and the commit's own `git -C <dir>`
is_commit() {
  local seg w first prev gitdir
  dir=$cwd
  while IFS= read -r seg; do
    first=""
    prev=""
    gitdir=$dir
    for w in $seg; do
      # a subshell or brace group glues its bracket to the word
      w=${w#[\({]}
      w=${w%\)}
      w=${w%\}}
      if [ -z "$first" ]; then
        [ -n "$w" ] || continue
        case $w in env | time | exec | command | then | do | else | elif | '!') continue ;; esac
        [[ $w =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && continue
        first=${w##*/}
        [ "$first" = git ] || [ "$first" = cd ] || break
      elif [ "$first" = cd ]; then
        enter "$w" "$dir"
        break
      elif [ "$prev" = -C ]; then
        enter "$w" "$gitdir"
        gitdir=$dir
      elif [ "$w" = commit ]; then
        dir=$gitdir
        return 0
      fi
      prev=$w
    done
  done < <(sed -E 's/(&&|\|\||;|\||&)/\n/g' <<< "$1")
  return 1
}

is_commit "$command" || exit 0
root=$(git -C "$dir" rev-parse --show-toplevel 2> /dev/null) || exit 0
# Gate only repos that ship this very hook (this repo or a worktree of it),
# so a commit in a foreign repo never runs that repo's check script
[ -e "$root/bin/lib/check" ] && cmp -s "$0" "$root/.claude/hooks/commit-gate.sh" || exit 0

if ! out=$(cd "$root" && pnpm check 2>&1); then
  {
    echo "pnpm check failed in $root, so the commit is blocked:"
    tail -n 40 <<< "$out"
  } >&2
  exit 2
fi

# The working tree, not the index: in `git add x && git commit` this runs
# before the add. -uall lists files inside new directories, and the second
# expression keeps a rename's new path
changed=$(git -C "$root" status --porcelain -uall | sed -E 's/^...//; s/.* -> //')
grep -q 'README\.md$' <<< "$changed" && exit 0
setup=$(grep -E '^(setup\.sh|setup/[^/]+\.sh|tilde/\.config/mise/config\.toml)$' <<< "$changed" | paste -sd, - | sed 's/,/, /g')
[ -n "$setup" ] || exit 0
jq -cn --arg c "Changed: $setup. No README is changed; CLAUDE.md's docs-mirror rule expects a README edit in the same commit for setup or mise changes." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}'
