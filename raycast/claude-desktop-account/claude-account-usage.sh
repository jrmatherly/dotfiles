#!/bin/bash
#
# Raycast inline command: the signed-in saved account with its 5-hour and
# weekly usage. Opt-in: it reads the saved token through the Keychain, see
# `claude-desktop-account --help`, Cautions. The first run shows a macOS
# Keychain dialog for "Claude Safe Storage"; click Always Allow once, or the
# dialog returns on every refresh. Add it in Raycast only if you want that.
#
# @raycast.schemaVersion 1
# @raycast.title Claude Account Usage
# @raycast.mode inline
# @raycast.refreshTime 5m
# @raycast.packageName Claude Desktop
# @raycast.icon 📊

set -euo pipefail

# Raycast runs scripts without the login shell's PATH (jq lives in Homebrew).
export PATH="/opt/homebrew/bin:$PATH"
cda="$(cd "$(dirname "$0")/../.." && pwd -P)/bin/claude-desktop-account"

name=$("$cda" current)
case $name in
  "not saved" | "signed out") echo "$name" ;;
  *) "$cda" usage "$name" ;;
esac
