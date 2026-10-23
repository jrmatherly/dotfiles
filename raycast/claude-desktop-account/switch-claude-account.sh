#!/bin/bash
#
# Raycast command: switch Claude Desktop to a saved account (quits and
# relaunches the app).
#
# @raycast.schemaVersion 1
# @raycast.title Switch Claude Account
# @raycast.mode compact
# @raycast.packageName Claude Desktop
# @raycast.icon 🔀
# @raycast.needsConfirmation true
# @raycast.argument1 { "type": "text", "placeholder": "account name" }

set -euo pipefail

# Raycast runs scripts without the login shell's PATH (jq lives in Homebrew).
export PATH="/opt/homebrew/bin:$PATH"
cda="$(cd "$(dirname "$0")/../.." && pwd -P)/bin/claude-desktop-account"

"$cda" switch "$1"
# compact mode shows only the last line as the toast
echo "Switched to $1"
