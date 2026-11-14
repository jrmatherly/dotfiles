#!/bin/bash
#
# Tests setup/menubar-open.sh against a stubbed open and pgrep, with HOME in a
# temp dir, so nothing on this Mac opens. Run by bin/lib/check.

set -u

repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/stubs" "$tmp/apps" "$tmp/home"
log="$tmp/log"
marker="$tmp/home/Library/Logs/returnofthemac/opened-by-setup"
fails=0
export log

printf '#!/bin/bash\necho "open $*" >> "$log"\n' > "$tmp/stubs/open"
printf '#!/bin/bash\n[ -n "${APP_RUNNING:-}" ]\n' > "$tmp/stubs/pgrep"
chmod +x "$tmp/stubs/open" "$tmp/stubs/pgrep"

run() {
  : > "$log"
  env PATH="$tmp/stubs:$PATH" HOME="$tmp/home" APPLICATIONS_DIR="$tmp/apps" "$@" \
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
check "a missing app is not opened" "[ ! -s '$log' ] && grep -q 'is not installed' '$tmp/out' && [ ! -e '$marker' ]"

mkdir "$tmp/apps/Return of the Mac.app"
run APP_RUNNING=1
check "a running app is not reopened" "[ ! -s '$log' ] && grep -q 'already running' '$tmp/out' && [ ! -e '$marker' ]"

run
check "the app opens in the background" "[ \"\$(cat '$log')\" = 'open -g -a $tmp/apps/Return of the Mac.app' ] && [ -e '$marker' ]"

run
check "the next run does not open it again" "[ ! -s '$log' ] && grep -q 'opened the app before' '$tmp/out'"

[ "$fails" = 0 ] || exit 1
