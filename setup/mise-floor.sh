#!/bin/bash
#
# Fail unless the mise on PATH is at least the version the settings layer needs.
#
# - Run it (setup.sh does before its first mise call); exits 1 with a message below the floor:
#
# `setup/mise-floor.sh`
#
# ---
# The override file (config.override.toml) arrived in mise 2026.10.14, and the
# settings layer was verified on 2026.11.5. bin/lib/test-override-env reads the
# floor= line and checks that check.yml pins mise to the same version.
#
# License: MIT

set -euo pipefail

floor=2026.11.5
found=$(mise --version 2> /dev/null | awk '{ print $1; exit }') || true
if [ -z "$found" ] || [ "$(printf '%s\n%s\n' "$floor" "$found" | sort -V | head -1)" != "$floor" ]; then
  echo "mise $floor or newer is required, found ${found:-none}. Upgrade mise, then run setup again." >&2
  exit 1
fi
