#!/bin/bash
#
# Print the machine state that setup.sh manages, sorted, for before/after diffs.
# Used by the /validate-setup skill: snapshot.sh > private/setup-snapshots/<phase>.txt

set -uo pipefail

repo=$(cd "$(dirname "$0")/../../.." && pwd -P)

echo "## symlinks into the repo"
for dir in "$HOME" "$HOME/.config" "$HOME/.codex" "$HOME/.claude" "$HOME/.claude/rules" \
  "$HOME/.gnupg" "$HOME/Library/Application Support/Code"; do
  find "$dir" -maxdepth 1 -type l 2> /dev/null
done | while IFS= read -r link; do
  target=$(readlink "$link")
  [[ $target == "$repo"* ]] && echo "${link/#$HOME/~} -> ${target/#$repo/\$DOTFILES}"
done | sort

echo "## mise (current)"
mise ls --current 2>&1 | sort

echo "## claude mcp (names)"
claude mcp list 2> /dev/null | grep ' - ' | sed 's/: .*//' | sort

echo "## login shell"
dscl . -read "$HOME" UserShell 2>&1

echo "## ~/.gitconfig.local present"
[ -f "$HOME/.gitconfig.local" ] && echo yes || echo no

echo "## Touch ID for sudo"
grep -c pam_tid /etc/pam.d/sudo_local 2> /dev/null || echo 0
