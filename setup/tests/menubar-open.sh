#!/bin/bash
#
# Tests setup/menubar-open.sh against a stubbed open and rotm-modules, so nothing
# on this Mac opens. Run by bin/lib/check.

set -u

repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/stubs" "$tmp/dots/bin/lib" "$tmp/apps"
log="$tmp/log"
fails=0
export log

printf '#!/bin/bash\necho "open $*" >> "$log"\n' > "$tmp/stubs/open"
printf '#!/bin/bash\n[ "$1 $2" = "is-on menubar" ] && [ -z "${MENUBAR_OFF:-}" ]\n' > "$tmp/dots/bin/lib/rotm-modules"
chmod +x "$tmp/stubs/open" "$tmp/dots/bin/lib/rotm-modules"

run() {
  : > "$log"
  env PATH="$tmp/stubs:$PATH" DOTFILES_DIR="$tmp/dots" APPLICATIONS_DIR="$tmp/apps" "$@" \
    bash "$repo/setup/menubar-open.sh" > "$tmp/out" 2>&1
}

check() {
  if eval "$2"; then echo "ok   $1"; else
    echo "FAIL $1"
    cat "$tmp/out"
    fails=$((fails + 1))
  fi
}

run
check "a missing app is not opened" "[ ! -s '$log' ] && grep -q 'is not installed' '$tmp/out'"

mkdir "$tmp/apps/Return of the Mac.app"
run
check "the app opens in the background when the module is on" "[ \"\$(cat '$log')\" = 'open -g -a $tmp/apps/Return of the Mac.app' ]"

run MENUBAR_OFF=1
check "the app is not opened when the module is off" "[ ! -s '$log' ] && grep -q 'menubar module is off' '$tmp/out'"

[ "$fails" = 0 ] || exit 1
