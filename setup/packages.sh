#!/bin/bash
#
# Installs mise when missing, links the in-repo VS Code plugin and applies the
# formulae, casks and extensions declared in tilde/.config/mise/conf.d/30-packages.toml.

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd -P)}"

# setup/misc.sh links ~/.config/mise after this runs, so read the repo's config
# directly: an empty config dir makes mise apply nothing
export MISE_CONFIG_DIR="$DOTFILES_DIR/tilde/.config/mise"
prefix="${HOMEBREW_PREFIX:-/opt/homebrew}"
export PATH="$HOME/.local/bin:$prefix/bin:$prefix/sbin:$PATH"

# tput fails with TERM unset (CI, a launchd job), which would abort this set -e script
tput() { command tput "$@" 2> /dev/null || true; }
bold=$(tput bold)
reset=$(tput sgr0)

title() {
  echo "${bold}==> $1${reset}"
  echo
}

warn() {
  echo "$(tput setaf 1)/!\\ $1 /!\\$(tput sgr0)"
}

if ! command -v mise > /dev/null; then
  title "Installing mise…"
  # Installs to ~/.local/bin/mise and checks the archive against checksums in the script
  curl -fsSL https://mise.run | sh
fi

# Tap formulae resolve through api.github.com, whose anonymous limit is 60 an hour
if [ -z "${MISE_GITHUB_TOKEN:-}" ]; then
  if token=$(gh auth token 2> /dev/null) && [ -n "$token" ]; then
    export MISE_GITHUB_TOKEN="$token"
  else
    warn "No GitHub token from gh: tap formulae may hit GitHub's anonymous rate limit. Re-run after gh auth login"
  fi
fi

mise plugins link --force vscode "$DOTFILES_DIR/mise-plugins/vscode"

# apply_manager <noun> <manager>: a failed package warns and setup goes on, but
# "no packages requested" means mise read no package list at all
apply_manager() {
  local out
  title "Installing $1 with mise…"
  if ! out=$(mise bootstrap packages apply --yes --manager "$2" 2>&1 | tee /dev/stderr); then
    if grep -q 'no packages requested' <<< "$out"; then
      warn "mise read no package list from $MISE_CONFIG_DIR"
      exit 1
    fi
    warn "Some $1 failed to install. See above, then re-run: mise bootstrap packages apply"
  fi
  # The full install measured about 32 GB; a full disk is the likeliest mid-run failure
  echo "$(df -h / | awk 'NR == 2 { print $4 }') free on /"
}

# A project config must not widen the run
cd "$HOME"
# Formulae first: reading the claude-multipass-app tap cask needs the Ruby 3 that brew:ruby installs
apply_manager formulae brew
apply_manager casks brew-cask
# The VS Code cask may have arrived in this run, without code on PATH yet
if command -v code > /dev/null; then
  apply_manager extensions vscode
else
  echo "VS Code's code command not found: extensions are skipped until VS Code is installed. Re-run this script then."
fi
