#!/bin/bash
#
# Apply the macOS settings that mise's TOML cannot hold: sudo writes, $HOME paths, pmset, file flags, sandboxed apps, the switchable preference groups and app restarts.
#
# - mise's pre-defaults hook: quit System Settings and save the preferences' status:
#
# `setup/macos-extras.sh --before`
#
# - mise's post-defaults hook: apply, restarting apps only when mise wrote a preference:
#
# `setup/macos-extras.sh`
#
# - Apply and always restart the affected apps (set-defaults runs this):
#
# `setup/macos-extras.sh --restart`
#
# - Rename this Mac (the local hostname is derived from the name unless given):
#
# `setup/macos-extras.sh --computer-name "{{name}}"`
#
# - Rename this Mac with a local hostname of your own:
#
# `setup/macos-extras.sh --computer-name "{{name}}" --local-hostname {{host}}`
#
# - Turn on HiDPI display modes for one run:
#
# `setup/macos-extras.sh --hidpi`
#
# - Turn on the firewall and stealth mode for one run:
#
# `setup/macos-extras.sh --firewall`
#
# - Turn Time Machine backups off for one run:
#
# `setup/macos-extras.sh --disable-time-machine`
#
# ---
# DOTFILES_MACOS_SCREENSHOTS, _TIME_MACHINE_NEW_DISKS, _TEXTEDIT, _SOFTWARE_UPDATE,
# _FIREWALL and _DISABLE_TIME_MACHINE are on unless set to the empty string.
# DOTFILES_MACOS_HIDPI, _COMPUTER_NAME and _LOCAL_HOSTNAME are off or empty unless set.
# By default this turns Time Machine backups off: a Mac that uses Time Machine
# switches macos.disable_time_machine off before its first set-defaults.
# dotfiles-settings sets all nine. Safe to repeat: sudo runs only when a value differs.
#
# License: MIT

set -euo pipefail

[ "$(uname -s)" = Darwin ] || exit 0

YELLOW=$(tput setaf 3 2> /dev/null || true)
BLUE=$(tput setaf 4 2> /dev/null || true)
RESET=$(tput sgr0 2> /dev/null || true)
info() { echo "[ ${BLUE}..${RESET} ] $1"; }
warn() { echo "[ ${YELLOW}!!${RESET} ] $1"; }

# The status --before saved; compared once by the next run, then removed whatever fails
snapshot="${TMPDIR:-/tmp}/dotfiles-macos-defaults-before"
trap 'rm -f "$snapshot"' EXIT

before=false restart=false hidpi=${DOTFILES_MACOS_HIDPI:-}
firewall=${DOTFILES_MACOS_FIREWALL-1} disable_tm=${DOTFILES_MACOS_DISABLE_TIME_MACHINE-1}
computer_name=${DOTFILES_MACOS_COMPUTER_NAME:-} local_hostname=${DOTFILES_MACOS_LOCAL_HOSTNAME:-}
while [ $# -gt 0 ]; do
  case $1 in
    --before) before=true ;;
    --restart) restart=true ;;
    --computer-name) computer_name=${2:?--computer-name needs a name} && shift ;;
    --local-hostname) local_hostname=${2:?--local-hostname needs a name} && shift ;;
    --hidpi) hidpi=1 ;;
    --firewall) firewall=1 ;;
    --disable-time-machine) disable_tm=1 ;;
    *)
      echo "macos-extras: unknown flag $1" >&2
      exit 2
      ;;
  esac
  shift
done

if $before; then
  trap - EXIT
  # Close System Settings, to prevent it from overriding settings we're about to
  # change (it was "System Preferences" before macOS 13). A runner without Apple
  # Events permission fails here, which must not stop a bootstrap.
  osascript -e 'tell application "System Settings" to quit' > /dev/null 2>&1 || true
  mise bootstrap macos defaults status --json > "$snapshot" 2> /dev/null || rm -f "$snapshot"
  exit 0
fi

# TextEdit, Preview and Help Viewer keep their preferences in a container that
# refuses a write from a terminal without Full Disk Access. That must cost only
# the one preference, not the rest of the run.
sandboxed() {
  defaults write "$@" 2> /dev/null || warn "Could not write $1 $2. Give this terminal Full Disk Access (System Settings → Privacy & Security) and run again."
}

# The groups below are written here, not declared in mise's fragment, because a
# declared preference cannot be switched off. An empty value is the settings UI's off.

if [ -n "${DOTFILES_MACOS_SCREENSHOTS-1}" ]; then
  # Save screenshots to the desktop (a $HOME path, which mise does not template)
  defaults write com.apple.screencapture location -string "$HOME/Desktop"
  # Save screenshots in PNG format (other options: BMP, GIF, JPG, PDF, TIFF)
  defaults write com.apple.screencapture type -string png
  # Disable shadow in window captures
  defaults write com.apple.screencapture disable-shadow -bool true
  # Show the mouse pointer in screenshots
  defaults write com.apple.screencapture showsCursor -bool true
  # Change the default screenshot name
  defaults write com.apple.screencapture name -string Shot
fi

if [ -n "${DOTFILES_MACOS_TIME_MACHINE_NEW_DISKS-1}" ]; then
  # Suppress Time Machine's "use as backup disk?" prompt for new drives
  defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true
fi

if [ -n "${DOTFILES_MACOS_TEXTEDIT-1}" ]; then
  # Default TextEdit to plain text and UTF-8. TextEdit is sandboxed, so mise
  # cannot read these back, but the writes are honoured.
  sandboxed com.apple.TextEdit RichText -int 0
  sandboxed com.apple.TextEdit PlainTextEncoding -int 4
  sandboxed com.apple.TextEdit PlainTextEncodingForWrite -int 4
fi

if [ -n "${DOTFILES_MACOS_SOFTWARE_UPDATE-1}" ]; then
  # Enable the automatic update check
  defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
  # Check for software updates daily, not just once per week
  defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1
  # Download newly available updates in background, and install system data
  # files and security updates. These two are integers, not booleans.
  defaults write com.apple.SoftwareUpdate AutomaticDownload -int 1
  defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -int 1
fi

# Open new Finder windows in the home folder (NewWindowTarget PfHm is in mise's
# fragment; this half holds a $HOME path, which mise does not template)
defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"

# mise reports these two domains as unset even after a write, so they stay here.
# Set Help Viewer windows to non-floating mode
sandboxed com.apple.helpviewer DevMode -bool true
# Do not open previous previewed files (e.g. PDFs) when opening a new one
sandboxed com.apple.Preview ApplePersistenceIgnoreState YES

# Show the ~/Library folder
# First set the attribute if it doesn't exist, then show folder
xattr -w com.apple.FinderInfo "" ~/Library 2> /dev/null || true
chflags nohidden ~/Library
xattr -d com.apple.FinderInfo ~/Library 2> /dev/null || true

# pmset -g custom omits a key this Mac lacks (lidwake on some models), and
# setting it would fail, so an unreported key is skipped
pmset_ensure() {
  local have
  have=$(pmset -g custom | awk -v k="$1" '$1 == k { print $2 }' | sort -u)
  if [ -n "$have" ] && [ "$have" != "$2" ]; then
    sudo pmset -a "$1" "$2"
  fi
}
# Enable lid wakeup
pmset_ensure lidwake 1
# Put the hard disk(s) to sleep when possible: 10 min
pmset_ensure disksleep 10
# Disable wake for network access
pmset_ensure womp 0
# Hibernation mode
# 0: Disable hibernation (speeds up entering sleep mode)
# 3: Copy RAM to disk so the system state can still be restored in case of a
#    power failure.
pmset_ensure hibernatemode 3

# Show the /Volumes folder
if [[ "$(ls -ldO /Volumes)" == *hidden* ]]; then
  sudo chflags nohidden /Volumes
fi

# Each opt-in below reads the Mac's state without sudo and calls sudo only when
# it differs. A read that fails counts as "differs". Switching one off changes
# nothing on the Mac.

# Set computer name (as done via System Settings → General → Sharing). The
# local hostname is checked too, so a rename that failed halfway is finished
# by the next run.
if [ -n "$computer_name" ]; then
  # Suggest a Bonjour-safe local hostname derived from the computer name
  if [ -z "$local_hostname" ]; then
    local_hostname=$(printf %s "$computer_name" | tr '[:upper:]' '[:lower:]' | sed -E "s/[^a-z0-9]+/-/g; s/^-+|-+\$//g")
  fi
  # A name with no Latin letter or digit derives nothing, and renaming with an
  # empty local hostname would stop halfway
  if [ -z "$local_hostname" ]; then
    warn "Not renaming this Mac: no local hostname can be derived from \"$computer_name\". Set macos.local_hostname or pass --local-hostname."
  elif [ "$(scutil --get ComputerName 2> /dev/null || true)" != "$computer_name" ] \
    || [ "$(scutil --get LocalHostName 2> /dev/null || true)" != "$local_hostname" ]; then
    sudo scutil --set ComputerName "$computer_name"
    sudo scutil --set HostName "$computer_name"
    sudo scutil --set LocalHostName "$local_hostname"
    sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "$local_hostname"
  fi
fi

# Enable HiDPI display modes (requires restart)
if [ -n "$hidpi" ] && [ "$(defaults read /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled 2> /dev/null || true)" != 1 ]; then
  sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true
fi

# Enable macOS Firewall + Stealth Mode. socketfilterfw is not on PATH; the
# command -v lets the self-check stub the two reads. sudo always gets the
# system path, so a file of that name on PATH never runs as root.
if [ -n "$firewall" ]; then
  fw=/usr/libexec/ApplicationFirewall/socketfilterfw
  fw_read=$(command -v socketfilterfw || echo "$fw")
  if [[ "$("$fw_read" --getglobalstate 2> /dev/null || true)" != *"State = "[1-9]* ]]; then
    sudo "$fw" --setglobalstate on
  fi
  if [[ "$("$fw_read" --getstealthmode 2> /dev/null || true)" != *"mode is on"* ]]; then
    sudo "$fw" --setstealthmode on
  fi
fi

# WARNING: this fully disables local Time Machine backups/snapshots.
# It is on by default and stops all backups, so a Mac that uses Time Machine
# switches macos.disable_time_machine off.
if [ -n "$disable_tm" ] && [ "$(defaults read /Library/Preferences/com.apple.TimeMachine AutoBackup 2> /dev/null || true)" != 0 ]; then
  if hash tmutil &> /dev/null; then sudo tmutil disable; fi
fi

# Drift alone must not restart anything (a value macOS keeps rewriting would
# kill Finder and the Dock on every bootstrap), so restart only when the status
# changed since --before, which means mise wrote a preference
if ! $restart && [ -e "$snapshot" ] && ! mise bootstrap macos defaults status --json 2> /dev/null | cmp -s - "$snapshot"; then
  restart=true
fi
if $restart; then
  for app in "Activity Monitor" Dock Finder NotificationCenter SystemUIServer Terminal; do
    # Killing Terminal.app from inside it would end this run
    if [ "$app" = Terminal ] && [ "${TERM_PROGRAM:-}" = Apple_Terminal ]; then
      warn "Not restarting Terminal, which is running this. Quit and reopen it to apply its settings."
      continue
    fi
    killall "$app" > /dev/null 2>&1 || true
  done
  info "Done! Note that some of these changes require a logout/restart to take effect."
fi
