#!/bin/bash

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd -P)}"
cd "$DOTFILES_DIR"

bold=$(tput bold)
reset=$(tput sgr0)

title() {
  echo "${bold}==> $1${reset}"
  echo
}

indent() {
  sed 's/^/  /'
}

# Check for Homebrew and install it if required
if ! command -v brew &> /dev/null; then
  title "Installing Homebrew…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Make sure we’re working with the latest version of Homebrew and its formulae
brew update

# Install fonts, tools, apps & vscode extensions. `brew bundle` upgrades
# outdated dependencies by default, so no separate `brew upgrade` is needed
# (pass --skip-brew to setup.sh to skip this step entirely).
#
# Goes through `brewpick --all`, which strips the Brewfile's `manual` entries
# (paid downloads with no cask) that `brew bundle` would otherwise reject with
# "Invalid Brewfile: undefined method 'manual'".
title "Installing software…"
# `brew bundle` exits non-zero when *any* entry fails (a flaky cask download, a
# removed formula). Don't let one package abort setup.sh before misc.sh
# installs the mise runtimes — report it and carry on.
if ! "$DOTFILES_DIR/bin/brewpick" --all | indent; then
  echo
  echo "$(tput setaf 1)/!\\ Some Brewfile entries failed to install — see above, then re-run \`brewpick --all\` /!\\$(tput sgr0)"
fi

# Optional apps: suggestions printed at the end of the run, NOT installed.
# Add entries to re-populate a list — each section only prints if it has items.
#
#   OPTIONAL_CASKS    — Homebrew cask names, e.g. "zoom"
#   OPTIONAL_LINKS    — "Name|https://…" for apps installed from a website
#   APP_STORE_LINKS   — Mac App Store URLs (https://apps.apple.com/…)
OPTIONAL_CASKS=()
OPTIONAL_LINKS=()
APP_STORE_LINKS=()

if [ ${#OPTIONAL_CASKS[@]} -gt 0 ] || [ ${#OPTIONAL_LINKS[@]} -gt 0 ]; then
  echo ""
  title "☕️ Install more apps if you need them:"
  for cask in "${OPTIONAL_CASKS[@]+"${OPTIONAL_CASKS[@]}"}"; do
    echo "brew install --cask $cask"
  done
  for link in "${OPTIONAL_LINKS[@]+"${OPTIONAL_LINKS[@]}"}"; do
    echo "${bold}${link%%|*}${reset} − ${link#*|}"
  done
fi

if [ ${#APP_STORE_LINKS[@]} -gt 0 ]; then
  echo ""
  title "🍏 Install additional apps from App Store:"
  for url in "${APP_STORE_LINKS[@]}"; do
    echo "$url"
  done
fi
echo ""

# Remove outdated versions of formulae and casks from the cellar
# Besides, this will run `brew autoremove` to remove all the hanging, no longer needed packages
brew cleanup --prune=all
