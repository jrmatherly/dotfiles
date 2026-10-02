#!/bin/bash
#
# Tests install_codex_config from setup/symlinks.sh in a temporary HOME.
# Run by bin/lib/check.

set -u

repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
# sed -E: BSD sed ignores \| in basic regexes, which silently loaded nothing
eval "$(sed -nE '/^(info|success|warn|tildify)\(\) \{/,/^}/p; /^install_codex_config\(\) \{/,/^}/p' "$repo/setup/symlinks.sh")"
export DOTFILES_DIR="$repo"
src="$repo/tilde/.codex/config.toml"
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT
mkdir -p "$HOME/.codex"
live="$HOME/.codex/config.toml"
fails=0

check() {
  if eval "$2"; then echo "ok   $1"; else
    echo "FAIL $1"
    fails=$((fails + 1))
  fi
}

install_codex_config > /dev/null 2>&1
check "missing → seeded as a regular copy" "[ -f '$live' ] && [ ! -L '$live' ] && cmp -s '$src' '$live'"
check "seeded copy is owner-only (600)" "[ \"\$(stat -f %Lp '$live')\" = 600 ]"

rm "$live"
ln -s "$src" "$live"
install_codex_config > /dev/null 2>&1
check "symlink → replaced by a regular copy" "[ ! -L '$live' ] && cmp -s '$src' '$live'"

{
  cat "$src"
  printf '\n[mcp_servers.app]\ncommand = "x"\n'
} > "$live"
before=$(shasum < "$live")
install_codex_config > "$HOME/out" 2>&1
check "app extras, all tracked lines → silent" "! grep -q 'lacks' '$HOME/out'"
check "helpers loaded (no command not found)" "! grep -q 'command not found' '$HOME/out'"
check "app extras → file unchanged" "[ \"\$(shasum < '$live')\" = '$before' ]"

grep -v '^model = ' "$src" > "$live"
before=$(shasum < "$live")
install_codex_config > "$HOME/out" 2>&1
check "tracked line missing → warns with it" "grep -q 'model = ' '$HOME/out'"
check "tracked line missing → says it lacks lines" "grep -q 'lacks these lines' '$HOME/out'"
check "tracked line missing → file unchanged" "[ \"\$(shasum < '$live')\" = '$before' ]"

[ "$fails" -eq 0 ] || {
  echo "$fails failed" >&2
  exit 1
}
