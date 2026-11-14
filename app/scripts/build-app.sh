#!/bin/bash
#
# Build the menu bar app: swift build in release, assemble dist/Return of the Mac.app from Info.plist.in, sign it with sign-mac-app.sh, and with --dmg package, sign and notarize a DMG.
#
# - Build app/dist/Return of the Mac.app, unsigned when no Developer ID identity exists:
#
# `app/scripts/build-app.sh`
#
# - Also write app/dist/returnofthemac-app_<version>_<arch>.dmg and its .sha256:
#
# `app/scripts/build-app.sh --dmg`
#
# ---
# Adapted from jrmatherly/claude-multipass (scripts/build-app.sh at v0.14.0),
# without the bundled tool, the icon, Sparkle and the entitlements.
#
# The app module uses SwiftUI macros whose compiler plugin only Xcode ships, so
# when xcode-select points at the Command Line Tools and Xcode is installed the
# build goes through Xcode's developer dir.
#
# Environment, all optional:
#   APP_BUNDLE_ID   default: net.matherly.returnofthemac
#   and sign-mac-app.sh's MACOS_SIGN_* and APPLE_API_* variables
#
# License: MIT
set -euo pipefail

cd "$(dirname "$0")/.."

die() {
  echo "build-app: $1" >&2
  exit 1
}

dmg=''
for arg in "$@"; do
  case $arg in
    --dmg) dmg=1 ;;
    *)
      echo "usage: app/scripts/build-app.sh [--dmg]" >&2
      exit 2
      ;;
  esac
done

swiftui_plugin=Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib
if [[ -z ${DEVELOPER_DIR:-} && ! -e "$(xcode-select -p)/$swiftui_plugin" && -e /Applications/Xcode.app/Contents/Developer/$swiftui_plugin ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

version=$(cat VERSION)
bundle_id=${APP_BUNDLE_ID:-net.matherly.returnofthemac}
app="dist/Return of the Mac.app"
plist="$app/Contents/Info.plist"

swift build --package-path . -c release
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/ReturnOfTheMac "$app/Contents/MacOS/ReturnOfTheMac"
sed -e "s/@VERSION@/$version/g" -e "s/@BUNDLE_ID@/$bundle_id/g" Info.plist.in > "$plist"
printf 'APPL????' > "$app/Contents/PkgInfo"
# Before signing, so a bad bundle never reaches notarization
if grep -Eq '@[A-Z_]*@' "$plist"; then die "a placeholder is left in Info.plist"; fi
bash scripts/sign-mac-app.sh sign-app "$app"
echo "build-app: $app ($version)"

[[ -n $dmg ]] || exit 0
out="dist/returnofthemac-app_${version}_$(uname -m).dmg"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
rm -f "$out"
hdiutil create -quiet -volname "Return of the Mac" -srcfolder "$staging" -format UDZO "$out"
bash scripts/sign-mac-app.sh sign-dmg "$out"
(cd dist && shasum -a 256 "$(basename "$out")" > "$(basename "$out").sha256")
echo "build-app: $out"
cat "$out.sha256"
