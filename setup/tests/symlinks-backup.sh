#!/bin/bash
#
# Tests symlink_file's backup answer from setup/symlinks.sh in a temporary HOME.
# Run by bin/lib/check.

set -u

repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
eval "$(sed -nE '/^(indent|tildify|info|user|success|skipped|fail|warn|backup_path|handle_existing_file|symlink_file)\(\) \{/,/^}/p' "$repo/setup/symlinks.sh")"
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT
# install_dotfiles normally declares these; read by the eval-loaded functions
# shellcheck disable=SC2034
overwrite_all=false backup_all=false skip_all=false
src="$HOME/src"
srcdir="$HOME/srcdir"
echo source > "$src"
mkdir "$srcdir"
fails=0

check() {
  if eval "$2"; then echo "ok   $1"; else
    echo "FAIL $1"
    fails=$((fails + 1))
  fi
}

echo first > "$HOME/f"
echo second > "$HOME/f"
printf b | symlink_file "$src" "$HOME/f" > /dev/null 2>&1
rm "$HOME/f"
echo third > "$HOME/f"
printf b | symlink_file "$src" "$HOME/f" > /dev/null 2>&1
check "first backup kept" "[ \"\$(cat '$HOME/f.backup')\" = second ]"
check "second backup has its own name" "find '$HOME' -maxdepth 1 -name 'f.backup.*' | grep -q ."
check "file replaced by the link" "[ -L '$HOME/f' ]"

mkdir "$HOME/d" "$HOME/d.backup"
printf b | symlink_file "$srcdir" "$HOME/d" > /dev/null 2>&1
check "directory backup not nested" "[ ! -e '$HOME/d.backup/d' ]"
check "directory backed up beside the old one" "find '$HOME' -maxdepth 1 -type d -name 'd.backup.*' | grep -q ."

[ "$fails" -eq 0 ] || {
  echo "$fails failed" >&2
  exit 1
}
