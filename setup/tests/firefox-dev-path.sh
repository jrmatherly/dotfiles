#!/bin/bash
#
# Tests firefox/lib/get-firefox-dev-path's profiles.ini fallback in a temporary HOME.
# Run by bin/lib/check.

set -u

repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
HOME=$(mktemp -d)
export HOME
trap 'rm -rf "$HOME"' EXIT
ff="$HOME/Library/Application Support/Firefox"
# Profile dirs avoid "dev-edition" so the find branch misses and the fallback resolves them
mkdir -p "$ff/Profiles/abc.custom" "$HOME/elsewhere/xyz.custom"
fails=0

check() {
  if eval "$2"; then echo "ok   $1"; else
    echo "FAIL $1"
    fails=$((fails + 1))
  fi
}

printf '[Profile1]\nName=default\nIsRelative=1\nPath=Profiles/other.default\n\n[Profile0]\nName=dev-edition-default\nIsRelative=1\nPath=Profiles/abc.custom\n' > "$ff/profiles.ini"
check "relative Path resolves" "[ \"\$('$repo/firefox/lib/get-firefox-dev-path')\" = '$ff/Profiles/abc.custom' ]"

printf '[Profile0]\nName=dev-edition-default\nIsRelative=0\nPath=%s\n\n[Profile1]\nName=default\nIsRelative=1\nPath=Profiles/other.default\n' "$HOME/elsewhere/xyz.custom" > "$ff/profiles.ini"
check "absolute Path used as is" "[ \"\$('$repo/firefox/lib/get-firefox-dev-path')\" = '$HOME/elsewhere/xyz.custom' ]"

[ "$fails" -eq 0 ] || {
  echo "$fails failed" >&2
  exit 1
}
