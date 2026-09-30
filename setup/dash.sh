#!/bin/bash
#
# Optional: configure Dash docsets generated from local folders of HTML
# documentation (Dash's built-in Docset Generator indexes HTML, not Markdown).
# Docsets you download inside Dash are unrelated: Dash manages those itself,
# in ~/Library/Application Support/Dash/DocSets.
#
# Dash stores its synced preferences as a plist of absolute paths and has no
# variable expansion, so the folders to index can't be committed in a portable
# way. This script asks for them interactively and writes the entries into the
# tracked sync file instead.
#
# Usage:
#   setup/dash.sh                            # interactive
#   setup/dash.sh add <folder> [name] [kw]   # add one docset non-interactively
#   ./setup.sh --dash                        # as part of a full setup run
#
# License: MIT

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd -P)}"
PLIST="$DOTFILES_DIR/dash/Dash.dashsync/Preferences.plist"

bold=$(tput bold 2> /dev/null || true)
reset=$(tput sgr0 2> /dev/null || true)

indent() {
  sed 's/^/  /'
}

if [ ! -f "$PLIST" ]; then
  echo "Dash sync file not found: $PLIST" >&2
  echo "Point Dash's sync folder (Dash → Settings → General) at $DOTFILES_DIR/dash first," >&2
  echo "so Dash writes its own sync file there, then re-run this script." >&2
  exit 1
fi

if [ "${1:-}" != "add" ] && [ ! -t 0 ]; then
  echo "Not an interactive shell — skipping Dash docset configuration." | indent
  exit 0
fi

echo "Dash can index local folders of HTML docs as 'docsets' you search with a keyword." | indent
echo "Leave the folder blank to finish." | indent
echo

# Dash only reads this file once its sync folder (Dash → Settings → General) points here
echo "${bold}Sync folder:${reset} $DOTFILES_DIR/dash" | indent
echo

xml_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<< "$1"
}

add_docset() {
  local name="$1" keyword="$2" folder="$3"

  # The dict key doubles as the docset's identifier and as a plutil key path
  # segment, so keep it free of spaces and dots
  local key
  key="$(echo "$name" | tr ' ' '-' | tr -cd '[:alnum:]_-')"
  if [ -z "$key" ]; then
    echo "  ✖ Docset name must contain letters or digits: $name" >&2
    return 1
  fi

  local name_x keyword_x folder_x now
  name_x="$(xml_escape "$name")"
  keyword_x="$(xml_escape "$keyword")"
  folder_x="$(xml_escape "$folder")"
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # Written with `plutil -replace` in one shot: PlistBuddy can't address a path
  # under a key containing spaces, and aborts partway through long -c batches
  plutil -replace "DHDocsetGeneratorRepo.installed.$key" -xml "\
<dict>
  <key>date</key><date>$now</date>
  <key>entry</key>
  <dict>
    <key>name</key><string>$name_x</string>
    <key>platform</key><string>Other</string>
    <key>uniqueIdentifier</key><string>$key</string>
    <key>docsetGeneratorSettings</key>
    <dict>
      <key>docsetName</key><string>$name_x</string>
      <key>docsetKeyword</key><string>$keyword_x</string>
      <key>localFolderPath</key><string>$folder_x</string>
      <key>isFromLocalFolder</key><true/>
      <key>isFromWebsite</key><false/>
      <key>basicIndexEnabled</key><true/>
      <key>javaScriptIndexEnabled</key><false/>
      <key>javaScriptUsedToIndex</key><string></string>
      <key>cssToInject</key><string></string>
      <key>allowFilters</key><string></string>
      <key>denyFilters</key><string></string>
      <key>extraInfoPlist</key><string></string>
    </dict>
  </dict>
</dict>" "$PLIST"

  echo "  ✔ $name ($keyword) → $folder"
}

# Validates the folder/name/keyword, then writes the entry. Returns non-zero
# (without exiting) so the interactive loop can ask again.
add_validated() {
  local folder="$1" name="${2:-}" keyword="${3:-}"

  # Expand a leading ~
  folder="${folder/#\~/$HOME}"

  if [ ! -d "$folder" ]; then
    echo "  ✖ Not a folder: $folder" >&2
    return 1
  fi
  folder="$(cd "$folder" && pwd -P)"

  name="${name:-$(basename "$folder")}"
  # Dash matches a docset by its keyword, e.g. `notes:search terms`
  keyword="${keyword:-$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')}"

  add_docset "$name" "$keyword" "$folder"
}

if [ "${1:-}" = "add" ]; then
  shift
  [ $# -ge 1 ] || {
    echo "Usage: setup/dash.sh add <folder> [name] [keyword]" >&2
    exit 1
  }
  add_validated "$@"
else
  while true; do
    read -rp "  Folder to index (blank to finish): " folder
    [ -z "$folder" ] && break

    read -rp "  Docset name [$(basename "${folder/#\~/$HOME}")]: " name
    read -rp "  Search keyword [derived from name]: " keyword

    add_validated "$folder" "$name" "$keyword" || true
    echo
  done
fi

if ! plutil -lint "$PLIST" > /dev/null; then
  echo "✖ $PLIST is no longer a valid plist — restore it with git checkout" >&2
  exit 1
fi

echo
echo "Done. Make sure Dash's sync folder (Dash → Settings → General) is $DOTFILES_DIR/dash," | indent
echo "then build the new docsets from Settings → Downloads → Docset Generator." | indent
echo "(Quit Dash before running this script so it doesn't overwrite the change.)" | indent
