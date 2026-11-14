#!/bin/bash
#
# Measure, on an installed guest, what the P5 plan's console (Task 5) and the app's own update (Task 10) rest on.
#
# - Check the guest is ready, changing nothing:
#
# `/bin/bash "/Volumes/My Shared Files/vm-proof/p5/p5-probe.sh" 0`
#
# - Run one row (1, 2, 4 or 5):
#
# `/bin/bash "/Volumes/My Shared Files/vm-proof/p5/p5-probe.sh" {{2}}`
#
# ---
# Evidence for ../../plans/2026-11-13-p5-menu-bar-app.md (Task 0), not part of the product.
# The guest runs the copy at ~/vm-proof/p5/p5-probe.sh. Unlike the P4 probe this one
# changes the guest for real: rows 1 and 2 run `rotm update -y`, row 4 upgrades a cask
# and row 5 turns sync on. Run it only in the disposable guest, on an installed copy.
#
# Every command runs in the environment the app gives it: a bare environment with the
# app's PATH and TERM=dumb. Rows 2 and 5 run under `script` with stdin a pipe held open,
# as the app's console will, and each line typed here is written to that pipe.
# Row 3 (Touch ID) is skipped: a UTM guest has none.
#
# Row 4 needs an older version of the cask installed, and mise fetches a tap only from
# GitHub's default branch (measured: a local path and a pinned ref are both refused), so
# the row renames mise's own record of the installed cask to the version before. The
# bundle on disk stays the current one: whether mise replaced it is read from its
# creation time and inode, not from its version.
#
# Writes results/ next to itself, so on the shared folder the host sees it at
# ~/vm-proof/p5/results/.
#
# License: MIT

set -u
here=$(cd "$(dirname "$0")" && pwd -P)
out="$here/results"
rotm="$HOME/dotfiles/bin/rotm"
app_path="$HOME/.local/bin:$HOME/.local/share/mise/shims:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cask=claude-multipass-app
package="brew-cask:jrmatherly/tap/$cask"
bundle="/Applications/Claude Multipass.app"
room="/opt/homebrew/Caskroom/$cask"
older=${P5_OLDER_VERSION:-0.13.0}

say() { printf '\np5-probe: %s\n' "$*"; }
die() {
  say "$*" >&2
  exit 1
}

# What a GUI app's child sees: no shell PATH, no terminal type
appenv() {
  env -i HOME="$HOME" USER="${USER:-$(id -un)}" LOGNAME="${LOGNAME:-$(id -un)}" SHELL="${SHELL:-/bin/zsh}" \
    TMPDIR="${TMPDIR:-/tmp}" PATH="$app_path" TERM=dumb "$@"
}

preflight() {
  mkdir -p "$out" || die "cannot write $out"
  [ -x "$rotm" ] || die "$rotm is missing: install first (see the runbook)"
  local mode
  mode=$("$HOME/dotfiles/bin/lib/rotm-mode" "$(cd "$HOME/dotfiles" && pwd -P)" 2>&1)
  [ "$mode" = installed ] || die "this is not an installed copy (rotm-mode says: $mode). Never run this on a development clone"
}

row0() {
  {
    sw_vers
    appenv mise --version
    git -C "$HOME/dotfiles" log --oneline -1
    git -C "$HOME/dotfiles" symbolic-ref --short HEAD
    echo "== rotm settings status, in the app's environment"
    appenv "$rotm" settings status
    echo "exit $?"
    echo "== rotm update --check"
    appenv "$rotm" update --check
    echo "exit $?"
    echo "== gh"
    appenv gh auth status 2>&1
    echo "== the cask"
    ls -la "$room" 2>&1
    (cd "$HOME" && appenv mise bootstrap packages status --json 2>&1 | grep "$cask")
  } > "$out/row0-preflight.txt" 2>&1
  cat "$out/row0-preflight.txt"
}

# Run a command as the app's console will: under script, stdin a pipe that stays open.
# Each line typed here goes down the pipe. Typing is not echoed, so a password stays off the screen.
session() {
  local name=$1 tailer line
  shift
  rm -f "$out/$name.exit" "$out/$name.sent"
  : > "$out/$name.raw"
  date +%s > "$out/$name.start"
  tail -f "$out/$name.raw" &
  tailer=$!
  trap 'stty echo 2> /dev/null; kill "$tailer" 2> /dev/null; exit 130' INT
  say "running. When it asks for something, type the answer and press Return (nothing you type is shown)."
  say "Return alone sends an empty line. Ctrl-C ends the row."
  # An anonymous pipe, as the app's is: script refuses a named one (tcgetattr fails on it)
  while [ ! -e "$out/$name.exit" ]; do
    if IFS= read -r -s -t 2 line; then
      printf '%s\n' "$line"
      printf '%s sent %s characters\n' "$(date +%T)" "${#line}" >> "$out/$name.sent"
    fi
  done 2> /dev/null | {
    /usr/bin/script -q /dev/null "$@" > "$out/$name.raw" 2>&1
    echo "exit $?" > "$out/$name.exit"
  }
  trap - INT
  stty echo 2> /dev/null
  sleep 1
  kill "$tailer" 2> /dev/null
  wait "$tailer" 2> /dev/null
  date +%s >> "$out/$name.start"
  # The raw file keeps the escapes; this copy is the one to read
  sed -e $'s/\x1b\\[[0-9;?]*[A-Za-z]//g' -e $'s/\r$//' "$out/$name.raw" > "$out/$name.txt"
  say "$name ended: $(cat "$out/$name.exit"). Output in $out/$name.txt"
}

row1() {
  say "row 1: rotm update -y with no terminal. Type nothing; this can take several minutes."
  appenv "$rotm" update -y < /dev/null > "$out/row1-update-no-terminal.txt" 2>&1
  echo "exit $?" > "$out/row1-update-no-terminal.exit"
  grep -n -i 'password\|sudo\|a terminal is required\|askpass' "$out/row1-update-no-terminal.txt" > "$out/row1-password-lines.txt"
  say "row 1 ended: $(cat "$out/row1-update-no-terminal.exit"). Lines that mention a password: $(wc -l < "$out/row1-password-lines.txt")"
}

row2() {
  say "row 2: rotm update -y under script. Type the password when it asks."
  session row2-update-console appenv DOTFILES_SETUP_LOG="$out/row2-setup.log" "$rotm" update -y
}

row4() {
  local current pid
  [ -d "$room" ] || die "$room is missing: the cask is not installed here"
  current=$(ls "$room" | head -1)
  {
    echo "== before: the cask as installed"
    ls -la "$room"
    cat "$room/$current/.mise-cask.toml"
    (cd "$HOME" && appenv mise bootstrap packages status --json 2>&1 | grep "$cask")
  } > "$out/row4-1-before.txt" 2>&1
  if [ "$current" != "$older" ]; then
    mv "$room/$current" "$room/$older" || die "could not rename $room/$current"
    sed -i '' "s/^version = \"$current\"/version = \"$older\"/" "$room/$older/.mise-cask.toml"
  fi
  {
    echo "== after renaming mise's record from $current to $older (the bundle is still $current)"
    ls -la "$room"
    (cd "$HOME" && appenv mise bootstrap packages status --json 2>&1 | grep "$cask")
  } > "$out/row4-2-record-renamed.txt" 2>&1
  open -g "$bundle" || die "could not open $bundle"
  sleep 8
  pid=$(pgrep -f "$bundle/Contents/MacOS/" | head -1)
  {
    echo "running pid: ${pid:-none}"
    stat -f 'bundle: inode %i created %SB modified %Sm' "$bundle"
    stat -f 'plist:  inode %i created %SB modified %Sm' "$bundle/Contents/Info.plist"
    plutil -extract CFBundleShortVersionString raw "$bundle/Contents/Info.plist"
  } > "$out/row4-3-running-before.txt" 2>&1
  (cd "$HOME" && appenv mise bootstrap packages upgrade --dry-run "$package") > "$out/row4-4-dry-run.txt" 2>&1
  echo "exit $?" >> "$out/row4-4-dry-run.txt"
  cat "$out/row4-4-dry-run.txt"
  if grep -q 'already up to date' "$out/row4-4-dry-run.txt"; then
    say "mise does not see an update, so the renamed record did not stand in for an older install. Row 4 stops here; the files so far are the result."
    return
  fi
  say "upgrading with no terminal while the app runs (pid ${pid:-none})"
  (cd "$HOME" && appenv mise bootstrap packages upgrade --yes "$package" < /dev/null) > "$out/row4-5-upgrade-no-terminal.txt" 2>&1
  echo "exit $?" >> "$out/row4-5-upgrade-no-terminal.txt"
  {
    echo "old pid ${pid:-none} still running: $(kill -0 "${pid:-0}" 2> /dev/null && echo yes || echo no)"
    echo "pids now: $(pgrep -f "$bundle/Contents/MacOS/" | tr '\n' ' ')"
    stat -f 'bundle: inode %i created %SB modified %Sm' "$bundle"
    stat -f 'plist:  inode %i created %SB modified %Sm' "$bundle/Contents/Info.plist"
    plutil -extract CFBundleShortVersionString raw "$bundle/Contents/Info.plist"
    xattr -l "$bundle"
    ls -la "$room"
    (cd "$HOME" && appenv mise bootstrap packages status --json 2>&1 | grep "$cask")
    grep -n -i 'password\|sudo\|a terminal is required' "$out/row4-5-upgrade-no-terminal.txt"
  } > "$out/row4-6-after.txt" 2>&1
  cat "$out/row4-5-upgrade-no-terminal.txt" "$out/row4-6-after.txt"
}

row5() {
  if appenv gh auth status > /dev/null 2>&1; then
    die "gh is signed in. Run: gh auth logout   then run row 5 again"
  fi
  say "row 5: rotm settings sync on under script. Finish the sign-in in the browser when it opens."
  session row5-sync-on appenv "$rotm" settings sync on
  appenv "$rotm" settings sync status > "$out/row5-sync-status.txt" 2>&1
  echo "exit $?" >> "$out/row5-sync-status.txt"
  cat "$out/row5-sync-status.txt"
}

case "${1:-}" in
  0 | 1 | 2 | 4 | 5)
    preflight
    "row$1"
    date > "$out/row$1.done"
    ;;
  *) die "usage: p5-probe.sh 0|1|2|4|5   (3, Touch ID, is skipped on a guest)" ;;
esac
