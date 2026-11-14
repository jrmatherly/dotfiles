#!/bin/bash
#
# Opens the menu bar app in the background, once: after the first setup run that
# finds it in /Applications. setup/misc.sh runs it when the menubar module is on.
# It skips a running app, because opening one sends it a reopen event and the app
# answers that with its settings window. A user who quits the app later is not
# overruled by the next update.
#
# APPLICATIONS_DIR (default /Applications) lets a self-check point it elsewhere.

set -euo pipefail

app="${APPLICATIONS_DIR:-/Applications}/Return of the Mac.app"
# In the app's own folder, which the cask's zap removes, so a reinstall opens it again
marker="$HOME/Library/Logs/returnofthemac/opened-by-setup"

if [ ! -d "$app" ]; then
  echo "skipped: $app is not installed"
elif [ -e "$marker" ]; then
  echo "skipped: setup opened the app before (delete $marker to open it on the next run)"
elif pgrep -xq ReturnOfTheMac; then
  echo "skipped: the app is already running"
elif open -g -a "$app"; then
  mkdir -p "$(dirname "$marker")" && : > "$marker"
else
  echo "could not open $app; open it from Applications"
fi
