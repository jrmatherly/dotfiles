#!/bin/bash
#
# Tests setup/macos-extras.sh against stubbed sudo, defaults, pmset, socketfilterfw,
# mise and killall, so nothing on this Mac changes. Run by bin/lib/check.

set -u

repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
stubs="$tmp/stubs" reads="$tmp/reads"
log="$tmp/log" status_out="$tmp/status.json" pmset_out="$tmp/pmset"
mkdir -p "$stubs" "$reads" "$tmp/home" "$tmp/tmpdir"
export HOME="$tmp/home" TMPDIR="$tmp/tmpdir" log reads status_out pmset_out
echo '{}' > "$status_out"

stub() {
  printf '#!/bin/bash\necho "%s $*" >> "$log"\n%s\n' "$1" "${2:-}" > "$stubs/$1"
  chmod +x "$stubs/$1"
}
stub sudo
stub defaults '[ "$1" = read ] || exit 0; f="$reads/${*: -1}"; [ -e "$f" ] || exit 1; cat "$f"'
stub killall
stub osascript 'exit "${OSASCRIPT_RC:-0}"'
stub scutil 'case "$1 $2" in
  "--get LocalHostName") echo old-name ;;
  --get*) echo "Old Name" ;;
esac'
stub chflags
stub xattr
stub tmutil
stub socketfilterfw 'case $1 in
  --getglobalstate) echo "${FW_GLOBAL:-Firewall is disabled. (State = 0)}" ;;
  --getstealthmode) echo "${FW_STEALTH:-Firewall stealth mode is off}" ;;
esac'
stub mise 'cat "$status_out"'
stub pmset '[ "$*" = "-g custom" ] && cat "$pmset_out"; exit 0'
export PATH="$stubs:$PATH"

# A1's override cache may export these into the shell that runs pnpm check
unset DOTFILES_MACOS_SCREENSHOTS DOTFILES_MACOS_TIME_MACHINE_NEW_DISKS DOTFILES_MACOS_TEXTEDIT \
  DOTFILES_MACOS_SOFTWARE_UPDATE DOTFILES_MACOS_FIREWALL DOTFILES_MACOS_DISABLE_TIME_MACHINE \
  DOTFILES_MACOS_HIDPI DOTFILES_MACOS_COMPUTER_NAME DOTFILES_MACOS_LOCAL_HOSTNAME

fails=0
check() {
  if eval "$2"; then echo "ok   $1"; else
    echo "FAIL $1"
    fails=$((fails + 1))
  fi
}

# Run directly, not through bash, the way the hooks do, so a missing mode bit fails
run() {
  : > "$log"
  "$repo/setup/macos-extras.sh" "$@" > /dev/null 2>&1
  # shellcheck disable=SC2034 # read inside the eval of check
  rc=$?
}

printf ' hibernatemode 3\n womp 0\n disksleep 10\n' > "$pmset_out"
run
check "matching pmset values need no sudo" "! grep -q '^sudo pmset' '$log'"
check "no restart without a snapshot" "! grep -q '^killall' '$log'"

check "screenshots are written when unset" "grep -q 'defaults write com.apple.screencapture location -string $HOME/Desktop' '$log' && grep -q 'defaults write com.apple.screencapture name -string Shot' '$log'"
check "the Time Machine new-disk prompt is suppressed when unset" "grep -q 'defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true' '$log'"
check "TextEdit is written when unset" "grep -q 'defaults write com.apple.TextEdit RichText -int 0' '$log'"
check "Software Update is written when unset" "grep -q 'defaults write com.apple.SoftwareUpdate AutomaticDownload -int 1' '$log'"

DOTFILES_MACOS_SCREENSHOTS='' DOTFILES_MACOS_TIME_MACHINE_NEW_DISKS='' DOTFILES_MACOS_TEXTEDIT='' DOTFILES_MACOS_SOFTWARE_UPDATE='' run
check "screenshots switched off" "! grep -q 'com.apple.screencapture' '$log'"
check "Time Machine new-disk switch off" "! grep -q 'com.apple.TimeMachine DoNotOfferNewDisksForBackup' '$log'"
check "TextEdit switched off" "! grep -q 'com.apple.TextEdit' '$log'"
check "Software Update switched off" "! grep -q 'com.apple.SoftwareUpdate' '$log'"
check "the other writes still happen" "grep -q 'defaults write com.apple.helpviewer' '$log'"

DOTFILES_MACOS_SOFTWARE_UPDATE=1 run
check "a group switched on is written" "grep -q 'defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true' '$log'"

run
check "the firewall is turned on by default" "grep -q '^sudo .*socketfilterfw --setglobalstate on$' '$log' && grep -q '^sudo .*socketfilterfw --setstealthmode on$' '$log'"
check "Time Machine is turned off by default" "grep -qx 'sudo tmutil disable' '$log'"
check "HiDPI and the name are left alone by default" "! grep -q 'scutil --set\|windowserver' '$log'"

DOTFILES_MACOS_FIREWALL=1 DOTFILES_MACOS_HIDPI=1 DOTFILES_MACOS_DISABLE_TIME_MACHINE=1 DOTFILES_MACOS_COMPUTER_NAME="Jason's Mac" run
check "the firewall is turned on" "grep -q '^sudo .*socketfilterfw --setglobalstate on$' '$log' && grep -q '^sudo .*socketfilterfw --setstealthmode on$' '$log'"
check "HiDPI is turned on" "grep -q '^sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true' '$log'"
check "Time Machine is turned off" "grep -qx 'sudo tmutil disable' '$log'"
check "the Mac is renamed" "grep -qx \"sudo scutil --set ComputerName Jason's Mac\" '$log'"
check "the local hostname is derived" "grep -qx 'sudo scutil --set LocalHostName jason-s-mac' '$log'"

echo 1 > "$reads/DisplayResolutionEnabled"
echo 0 > "$reads/AutoBackup"
export FW_GLOBAL='Firewall is enabled. (State = 1)' FW_STEALTH='Firewall stealth mode is on'
DOTFILES_MACOS_HIDPI=1 DOTFILES_MACOS_COMPUTER_NAME='Old Name' run
check "a matching Mac needs no sudo for the default-on opt-ins" "! grep -q '^sudo \(.*socketfilterfw\|tmutil\|scutil\|defaults\)' '$log'"
DOTFILES_MACOS_FIREWALL=1 DOTFILES_MACOS_HIDPI=1 DOTFILES_MACOS_DISABLE_TIME_MACHINE=1 DOTFILES_MACOS_COMPUTER_NAME='Old Name' run
check "a matching Mac needs no sudo for the opt-ins set to 1" "! grep -q '^sudo \(.*socketfilterfw\|tmutil\|scutil\|defaults\)' '$log'"
DOTFILES_MACOS_COMPUTER_NAME='Old Name' DOTFILES_MACOS_LOCAL_HOSTNAME=new-host run
check "a rename left half done is finished" "grep -qx 'sudo scutil --set LocalHostName new-host' '$log'"
FW_GLOBAL='Firewall is enabled. (State = 2)' run
check "a firewall in another enabled state is left alone" "! grep -q 'setglobalstate' '$log'"
unset FW_GLOBAL FW_STEALTH
rm -f "$reads/DisplayResolutionEnabled" "$reads/AutoBackup"

DOTFILES_MACOS_FIREWALL='' DOTFILES_MACOS_DISABLE_TIME_MACHINE='' DOTFILES_MACOS_HIDPI='' DOTFILES_MACOS_COMPUTER_NAME='' run
check "an opt-in switched off does nothing" "! grep -q 'socketfilterfw --set\|tmutil\|scutil --set\|windowserver' '$log'"

DOTFILES_MACOS_FIREWALL='' DOTFILES_MACOS_DISABLE_TIME_MACHINE='' run --firewall --disable-time-machine
check "a flag turns a switched-off opt-in on" "grep -q '^sudo .*socketfilterfw --setglobalstate on$' '$log' && grep -qx 'sudo tmutil disable' '$log'"
DOTFILES_MACOS_COMPUTER_NAME='From Setting' run --computer-name 'From Flag' --local-hostname custom-host
check "the flag's name wins" "grep -qx 'sudo scutil --set ComputerName From Flag' '$log' && grep -qx 'sudo scutil --set LocalHostName custom-host' '$log'"

printf ' hibernatemode 3\n womp 0\n disksleep 0\n' > "$pmset_out"
run
check "a differing value is set" "grep -qx 'sudo pmset -a disksleep 10' '$log'"
check "only that one" "[ \"\$(grep -c '^sudo pmset' '$log')\" = 1 ]"
check "an unreported key is skipped" "! grep -q 'lidwake' '$log'"

snapshot="$TMPDIR/dotfiles-macos-defaults-before"
echo '{"state": "differs"}' > "$status_out"
run --before
check "--before saves the status" "cmp -s '$snapshot' '$status_out'"
check "--before quits System Settings" "grep -q '^osascript' '$log'"
check "--before writes nothing" "! grep -q '^defaults write' '$log'"

run
check "an unchanged status restarts nothing" "! grep -q '^killall' '$log'"
check "the snapshot is removed" "[ ! -e '$snapshot' ]"

run --before
echo '{"state": "set"}' > "$status_out"
run
check "a changed status restarts the Dock" "grep -qx 'killall Dock' '$log'"
check "the snapshot is removed again" "[ ! -e '$snapshot' ]"

run --before
run --nope
check "a failed run leaves no snapshot" "[ ! -e '$snapshot' ]"

OSASCRIPT_RC=1 run --before
check "--before survives a failing osascript" "[ \$rc = 0 ] && [ -e '$snapshot' ]"
rm -f "$snapshot"

TERM_PROGRAM=Apple_Terminal run --restart
check "Terminal.app is spared from inside Terminal.app" "! grep -qx 'killall Terminal' '$log' && grep -qx 'killall Finder' '$log'"

run --nope
check "an unknown flag exits 2" "[ \$rc = 2 ]"

[ "$fails" -eq 0 ] || {
  echo "$fails failed" >&2
  exit 1
}
