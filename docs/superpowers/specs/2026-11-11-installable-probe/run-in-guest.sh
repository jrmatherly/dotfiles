#!/bin/bash
#
# Run probe.sh in the UTM guest and leave its results beside this script.
#
# - Run every probe from the shared folder:
#
# `bash "/Volumes/My Shared Files/vm-proof/p0/run-in-guest.sh"`
#
# - Run only some probes:
#
# `bash "/Volumes/My Shared Files/vm-proof/p0/run-in-guest.sh" {{6 8}}`
#
# ---
# Writes run-<time>/results.txt, probe.err and versions.txt next to itself, so
# on the shared folder the host sees them at ~/vm-proof/p0/. A disposable guest
# loses everything else at shutdown.
#
# License: MIT

set -u

here=$(cd "$(dirname "$0")" && pwd -P)
# mise's installer puts it here, and a fresh guest's PATH does not have it yet
PATH="$HOME/.local/bin:$PATH"

missing=0
for tool in git mise /usr/bin/jq; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "run-in-guest: $tool not found" >&2
    missing=1
  fi
done
# The git stub exists without the Command Line Tools and only opens a dialog
if ! xcode-select -p > /dev/null 2>&1; then
  echo "run-in-guest: Command Line Tools missing; run: xcode-select --install" >&2
  missing=1
fi
[ "$missing" = 0 ] || exit 1

out="$here/run-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out" || exit 1
{
  sw_vers
  mise --version
  git --version
} > "$out/versions.txt" 2>&1

bash "$here/probe.sh" "$@" 2> "$out/probe.err" | grep '^PROBE ' | tee "$out/results.txt"
echo "run-in-guest: wrote $out"
