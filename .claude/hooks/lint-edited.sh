#!/bin/bash
#
# Claude Code PostToolUse hook (Edit|Write): format and lint the one file that
# was just edited, with the same tools and scope as `pnpm check`. Problems go
# to stderr with exit 2, which Claude Code shows to Claude so it fixes them in
# the same turn (exit 1 would only reach the user). Wired up in
# .claude/settings.json; self-check: .claude/hooks/test-lint-edited.sh

set -uo pipefail

project=${CLAUDE_PROJECT_DIR:-$(pwd -P)}
# Edit/Write send an absolute file_path; Serena's edit tools a relative_path
file=$(jq -r '.tool_input.file_path // .tool_input.relative_path // empty')
[ -n "$file" ] || exit 0
[[ $file == /* ]] || file="$project/$file"

# Only existing files inside this checkout (a directory, e.g. from
# replace_in_files, is skipped: pnpm check covers multi-file edits)
[ -f "$file" ] || exit 0
case $file in
  "$project"/*) ;;
  *) exit 0 ;;
esac

# prettier resolves its plugin, .gitignore and .prettierignore from the cwd
cd "$project" || exit 0
rel=${file#"$project"/}

# Machine-local files (private/, .codegraph/, …) aren't ours to lint
git check-ignore -q -- "$rel" && exit 0

problems=""
run() {
  local out
  if ! out=$("$@" 2>&1); then
    problems+="\$ $*"$'\n'"$out"$'\n'
  fi
}

# Prettier: the globs `pnpm check` uses — any *.{js,cjs,ts,md,json,sh} plus
# the top level of bin/ (`bin/*`); zsh never (prettier-plugin-sh parses it as
# bash and corrupts it)
case $rel in
  *.zsh | tilde/.zshrc | tilde/.zshenv | tilde/.zprofile)
    run zsh -n "$rel"
    ;;
  tilde/.bash_profile)
    run bash -n "$rel"
    ;;
  *.js | *.cjs | *.ts | *.md | *.json | *.sh | bin/*)
    # bin/* here means the top level only, like the prettier glob
    if [[ $rel != bin/*/* ]] && [ -x node_modules/.bin/prettier ]; then
      run node_modules/.bin/prettier --write --ignore-unknown --log-level warn -- "$rel"
    fi
    ;;
esac

# bash -n + shellcheck: exactly bin/lib/check's script list — setup.sh,
# setup/*.sh, .claude/hooks/*.sh, .claude/skills/*/*.sh, and top-level bin/
# scripts with a bash/sh shebang except bin/license. Sourced snippets (e.g.
# colors/*.sh) and bin/lib/ aren't gated, so they aren't linted here either.
gated=false
if [[ $rel == setup.sh || $rel =~ ^setup/[^/]+\.sh$ || $rel =~ ^\.claude/hooks/[^/]+\.sh$ || $rel =~ ^\.claude/skills/[^/]+/[^/]+\.sh$ ]]; then
  gated=true
elif [[ $rel =~ ^bin/[^/]+$ && $rel != bin/license ]] \
  && head -n 1 "$rel" | grep -Eq '^#!(/bin/(ba)?sh|/usr/bin/env (ba)?sh)$'; then
  gated=true
fi
if [ "$gated" = true ]; then
  run bash -n "$rel"
  run shellcheck --severity=warning "$rel"
fi

if [ -n "$problems" ]; then
  printf 'lint-edited: problems in %s (the edit was applied; fix and re-edit)\n%s' "$rel" "$problems" >&2
  exit 2
fi
exit 0
