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

# A segment is a commit when its command word (after NAME=value prefixes) is
# git and a later word is `commit`; quoted text is not parsed
is_commit() {
  local seg w first
  while IFS= read -r seg; do
    first=""
    for w in $seg; do
      if [ -z "$first" ]; then
        [[ $w =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && continue
        first=${w##*/}
        [ "$first" = git ] || break
      elif [ "$w" = commit ]; then
        return 0
      fi
    done
  done < <(sed -E 's/(&&|\|\||;|\|)/\n/g' <<< "$1")
  return 1
}

is_commit "$command" || exit 0
root=$(git -C "$cwd" rev-parse --show-toplevel 2> /dev/null) || exit 0
[ -e "$root/bin/lib/check" ] || exit 0

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
