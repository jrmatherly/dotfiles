#!/bin/bash
#
# Tests link_config_dir from setup/misc.sh in a temporary HOME.
# Run by bin/lib/check.

set -u

repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT
fails=0

check() {
  if eval "$2"; then echo "ok   $1"; else
    echo "FAIL $1"
    fails=$((fails + 1))
  fi
}

# misc.sh's link_config_dir: only creates or relinks ~/.config/<name> when it is
# missing or already points into the repo
eval "$(sed -nE '/^(warning|link_config_dir)\(\) \{/,/^}/p' "$repo/setup/misc.sh")"
DOTFILES_DIR="$HOME/repo"
mkdir -p "$DOTFILES_DIR/tilde/.config/a" "$DOTFILES_DIR/tilde/.config/b" "$DOTFILES_DIR/tilde/.config/c" "$HOME/elsewhere" "$HOME/.config/d"
ln -s "$HOME/elsewhere" "$HOME/.config/a"
out=$(link_config_dir a 2>&1)
check "foreign link left untouched" "[ \"\$(readlink '$HOME/.config/a')\" = '$HOME/elsewhere' ]"
check "foreign link warned about" "printf '%s' '$out' | grep -q 'links elsewhere'"
link_config_dir b > /dev/null 2>&1
check "missing link created" "[ \"\$(readlink '$HOME/.config/b')\" = '$DOTFILES_DIR/tilde/.config/b' ]"
ln -s "$DOTFILES_DIR/tilde/.config/old" "$HOME/.config/c"
link_config_dir c > /dev/null 2>&1
check "repo link relinked" "[ \"\$(readlink '$HOME/.config/c')\" = '$DOTFILES_DIR/tilde/.config/c' ]"
ln -s "$DOTFILES_DIR" "$HOME/alias"
mkdir -p "$DOTFILES_DIR/tilde/.config/e"
ln -s "$HOME/alias/tilde/.config/e" "$HOME/.config/e"
link_config_dir e > /dev/null 2>&1
check "link through an alias of the repo relinked" "[ \"\$(readlink '$HOME/.config/e')\" = '$DOTFILES_DIR/tilde/.config/e' ]"
link_config_dir d > /dev/null 2>&1
check "real directory left untouched" "[ -d '$HOME/.config/d' ] && [ ! -L '$HOME/.config/d' ]"

[ "$fails" -eq 0 ] || {
  echo "$fails failed" >&2
  exit 1
}
