#!/bin/bash
#
# Tests for bin/vscode-settings against a temporary target directory, so the
# real vscode/User/settings.json is never touched. Run by bin/lib/check.

set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
cmd="$DOTFILES_DIR/bin/vscode-settings"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export VSCODE_SETTINGS_DIR="$work/User" VSCODE_SETTINGS_ENV="$work/vscode.env"
mkdir -p "$VSCODE_SETTINGS_DIR"
target="$VSCODE_SETTINGS_DIR/settings.json"
fails=0

check() {
  if eval "$2"; then echo "ok   $1"; else
    echo "FAIL $1"
    fails=$((fails + 1))
  fi
}

"$cmd" --preset warp > /dev/null 2>&1
check "renders the chosen preset" "grep -q 'ProFont IIx Nerd Font Mono' '$target'"
check "records the render hash" "[ -s '$VSCODE_SETTINGS_DIR/.settings.rendered' ]"
check "saves the choice" "grep -qx 'VSCODE_FONT_PRESET=warp' '$VSCODE_SETTINGS_ENV'"
check "fills in HOME" "grep -q '\"notes.notesLocation\": \"$HOME/' '$target'"
check "keeps VS Code's own \${version}" "grep -q '\${version}' '$target'"

"$cmd" > /dev/null 2>&1
check "reuses the saved choice" "grep -q 'ProFont IIx Nerd Font Mono' '$target'"
"$cmd" --check > /dev/null 2>&1
check "--check passes when up to date" "[ $? -eq 0 ]"

printf '// edited in VS Code\n' >> "$target"
before=$(shasum -a 256 "$target")
"$cmd" --preset iosevka > "$work/out" 2>&1
status=$?
check "drift: refuses (exit 1)" "[ $status -eq 1 ]"
check "drift: shows the diff" "grep -q 'edited in VS Code' '$work/out'"
check "drift: leaves the file alone" "[ \"\$(shasum -a 256 '$target')\" = \"$before\" ]"

"$cmd" --preset iosevka --force > /dev/null 2>&1
check "--force overwrites drift" "grep -q 'IosevkaCode Nerd Font' '$target' && ! grep -q 'edited in VS Code' '$target'"

before=$(shasum -a 256 "$target")
"$cmd" --preset nope > /dev/null 2>&1
status=$?
check "unknown preset: exit 1" "[ $status -eq 1 ]"
check "unknown preset: nothing written" "[ \"\$(shasum -a 256 '$target')\" = \"$before\" ]"

"$cmd" --bogus > /dev/null 2>&1
status=$?
check "bad flag: exit 2" "[ $status -eq 2 ]"

mkdir -p "$work/repo/vscode/User"
cp "$DOTFILES_DIR/vscode/presets.toml" "$work/repo/vscode/"
printf '{ "a": {{ missing_value }} }\n' > "$work/repo/vscode/User/settings.json.j2"
VSCODE_SETTINGS_TEMPLATE="$work/repo/vscode/User/settings.json.j2" "$cmd" --preset iosevka --force > /dev/null 2>&1
status=$?
check "undefined template variable: exit 1" "[ $status -eq 1 ]"
check "undefined template variable: nothing written" "grep -q 'IosevkaCode Nerd Font' '$target'"

# Font check: a font fc-list knows must not warn; an unknown one must
installed=$(fc-list : family | head -1 | cut -d, -f1)
sed -e "s/'ProFont IIx Nerd Font Mono'/'$installed'/g" "$DOTFILES_DIR/vscode/presets.toml" > "$work/repo/vscode/presets.toml"
cp "$DOTFILES_DIR/vscode/User/settings.json.j2" "$work/repo/vscode/User/settings.json.j2"
VSCODE_SETTINGS_TEMPLATE="$work/repo/vscode/User/settings.json.j2" "$cmd" --preset warp --force > /dev/null 2> "$work/err"
check "installed font: no warning" "! grep -q \"isn't installed\" '$work/err'"
sed -i '' "s/'$installed'/'NoSuchFont Mono'/g" "$work/repo/vscode/presets.toml"
VSCODE_SETTINGS_TEMPLATE="$work/repo/vscode/User/settings.json.j2" "$cmd" --preset warp --force > /dev/null 2> "$work/err"
check "missing font: warns" "grep -q \"'NoSuchFont Mono' isn't installed\" '$work/err'"

[ "$fails" -eq 0 ] || {
  echo "$fails failed" >&2
  exit 1
}
