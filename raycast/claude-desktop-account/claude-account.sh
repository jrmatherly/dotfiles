#!/bin/bash
#
# Raycast inline command: the saved Claude Desktop account signed in now,
# "not saved" for an unsaved login, or "signed out".
#
# @raycast.schemaVersion 1
# @raycast.title Claude Account
# @raycast.mode inline
# @raycast.refreshTime 1m
# @raycast.packageName Claude Desktop
# @raycast.icon 👤

set -euo pipefail

# Raycast runs scripts without the login shell's PATH (jq lives in Homebrew).
export PATH="/opt/homebrew/bin:$PATH"
cda="$(cd "$(dirname "$0")/../.." && pwd -P)/bin/claude-desktop-account"

"$cda" current
