#!/bin/bash
#
# Opens the menu bar app once, in the background, when the menubar module is on
# and the cask has put the app in place. Run by setup/misc.sh at the end of
# every bootstrap; opening a running app only reactivates it.
#
# APPLICATIONS_DIR (default /Applications) lets a self-check point it elsewhere.

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd -P)}"
app="${APPLICATIONS_DIR:-/Applications}/Return of the Mac.app"

if ! "$DOTFILES_DIR/bin/lib/rotm-modules" is-on menubar; then
  echo "skipped: the menubar module is off"
elif [ ! -d "$app" ]; then
  echo "skipped: $app is not installed"
else
  open -g -a "$app" || echo "could not open $app; open it from Applications"
fi
