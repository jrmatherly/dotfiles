#!/bin/bash
#
# Set up computer environment
#
# Usage:
#   ./setup.sh [-y|--yes] [--skip-brew] [--skip-codegraph] [--dash] [-h|--help]
#
#   -y, --yes         Don't wait for confirmation before starting
#   --skip-brew       Skip `brew update` and the Brewfile install (`brewpick
#                     --all`) — handy when re-running for dotfiles changes only
#   --skip-codegraph  Don't install CodeGraph or wire it into Claude Code
#   --dash            Also run the optional Dash docset configuration
#   -h, --help        Print this help and exit
#
# License: MIT

set -euo pipefail

# Where this repo actually lives — the scripts never assume `~/dotfiles`
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd -P)"
export DOTFILES_DIR
cd "$DOTFILES_DIR"

# Telemetry opt-outs for the tools this run installs and invokes (dotnet tool
# install, func, pwsh, az, aspire, codegraph, rtk) — zsh/env.zsh sets the same for
# everyday shells, but it isn't sourced yet on a fresh Mac. Keep the two lists
# in sync.
export FUNCTIONS_CORE_TOOLS_TELEMETRY_OPTOUT=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export POWERSHELL_TELEMETRY_OPTOUT=1
export AZURE_CORE_COLLECT_TELEMETRY=false
export AZURE_MCP_COLLECT_TELEMETRY=false
export ASPIRE_CLI_TELEMETRY_OPTOUT=true
export ASPIRE_DASHBOARD_TELEMETRY_OPTOUT=true
export CODEGRAPH_TELEMETRY=0
export RTK_TELEMETRY_DISABLED=1

SKIP_CONFIRM=false
SKIP_BREW=false
# Read by setup/misc.sh — also settable in the environment
export DOTFILES_SKIP_CODEGRAPH="${DOTFILES_SKIP_CODEGRAPH:-false}"
RUN_DASH=false
orig_args=("$@")

while [ $# -gt 0 ]; do
  case "$1" in
    -y | --yes) SKIP_CONFIRM=true ;;
    --skip-brew) SKIP_BREW=true ;;
    --skip-codegraph) DOTFILES_SKIP_CODEGRAPH=true ;;
    --dash) RUN_DASH=true ;;
    -h | --help)
      # Print the header comment block (everything after the shebang)
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); if ($0 ~ /^License:/) next; print; next } NR > 1 { exit }' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1 (try --help)" >&2
      exit 1
      ;;
  esac
  shift
done

# Record the whole run to private/setup-logs/ (git-ignored) so /validate-setup
# can read it instead of pasted output. `script` keeps a real terminal, so
# prompts, Touch ID and colors still work, and it returns the run's exit code.
# Skipped without a terminal or when already recording.
if [ -t 0 ] && [ -t 1 ] && [ -z "${DOTFILES_SETUP_LOG:-}" ]; then
  mkdir -p "$DOTFILES_DIR/private/setup-logs"
  DOTFILES_SETUP_LOG="$DOTFILES_DIR/private/setup-logs/$(date +%Y%m%d-%H%M%S).log"
  export DOTFILES_SETUP_LOG
  echo "Logging this run to ${DOTFILES_SETUP_LOG#"$DOTFILES_DIR"/}"
  # ${arr[@]+…} keeps an empty array safe under `set -u` in macOS's bash 3.2
  exec script -q "$DOTFILES_SETUP_LOG" "$DOTFILES_DIR/setup.sh" ${orig_args[@]+"${orig_args[@]}"}
fi

# Colors, but only when we're attached to a terminal that supports them
if [ -t 1 ] && command -v tput &> /dev/null && tput setaf 1 &> /dev/null; then
  red=$(tput setaf 1)
  green=$(tput setaf 2)
  yellow=$(tput setaf 3)
  light_red=$(tput setaf 9)
  bold=$(tput bold)
  reset=$(tput sgr0)
else
  red="" green="" yellow="" light_red="" bold="" reset=""
fi

title() {
  echo "${bold}==> $1${reset}"
  echo
}

warning() {
  echo "${red}/!\\ $1 /!\\${reset}"
}

echo -e "
${yellow}
          _ ._  _ , _ ._
        (_ ' ( \`  )_  .__)
      ( (  (    )   \`)  ) _)
     (__ (_   (_ . _) _) ,__)
           ~~\\ ' . /~~
         ,::: ;   ; :::,
        ':::::::::::::::'
 ____________/_ __ \\____________
|                               |
|      Welcome to dotfiles      |
|_______________________________|
"
echo
echo -e "${yellow}!!! ${red}WARNING${yellow} !!!"
echo -e "${light_red}This script replaces your configuration files with symlinks to this repo."
echo -e "${light_red}It asks before overwriting anything, but use it at your own risk.${reset}"
echo -e "${yellow}Repo: ${reset}$DOTFILES_DIR"

if [ "$SKIP_CONFIRM" = false ]; then
  if [ -t 0 ]; then
    echo -e "${yellow}Press Enter key to continue…${reset}\n"
    read -r _ || true
  else
    echo -e "${yellow}Non-interactive shell — continuing without confirmation.${reset}\n"
  fi
fi

# Several configs (e.g. lazygit's `shellFunctionsFile`) can't expand variables,
# so keep the conventional `~/dotfiles` path working as a symlink to the repo
LEGACY_LINK="$HOME/dotfiles"
if [ "$DOTFILES_DIR" != "$LEGACY_LINK" ]; then
  # shellcheck disable=SC2088 # "~/dotfiles" in messages is display text
  if [ ! -e "$LEGACY_LINK" ] && [ ! -L "$LEGACY_LINK" ]; then
    title "🔗 Linking ~/dotfiles → ${DOTFILES_DIR}…"
    ln -s "$DOTFILES_DIR" "$LEGACY_LINK"
  elif [ -L "$LEGACY_LINK" ] && [ "$(readlink "$LEGACY_LINK")" != "$DOTFILES_DIR" ]; then
    warning "~/dotfiles points at $(readlink "$LEGACY_LINK"), not $DOTFILES_DIR"
  elif [ ! -L "$LEGACY_LINK" ]; then
    warning "~/dotfiles exists and is not a symlink — leaving it alone"
  fi
fi

# Use Touch ID to authorize sudo
if [ ! -f /etc/pam.d/sudo_local ]; then
  title "🔒 Enabling Touch ID to authorize sudo commands…"
  echo "auth       sufficient     pam_tid.so" | sudo tee /etc/pam.d/sudo_local > /dev/null
fi

# Ask for the administrator password upfront, then keep the sudo timestamp
# alive for the whole run so app installers don't re-prompt halfway through
warning "Activate sudo"
sudo -v
# `sudo -n -v` is the documented way to *extend* the cached credential without
# prompting (`sudo -n true` only checks it, so it expired after macOS's default
# 5 minutes and printed "sudo: a password is required"). `|| true` keeps one
# failure from killing the loop under the inherited `set -e`.
while true; do
  sudo -n -v 2> /dev/null || true
  sleep 60
  kill -0 "$$" 2> /dev/null || exit
done &
SUDO_KEEPALIVE_PID=$!
# shellcheck disable=SC2064 # expand the PID now, not when the trap fires
trap "kill $SUDO_KEEPALIVE_PID 2> /dev/null || true" EXIT INT TERM
echo "Sudo activated!"
echo

# Install Homebrew and packages/apps
if [ "$SKIP_BREW" = true ]; then
  title "🫖 Skipping Homebrew (--skip-brew)…"
else
  title "🫖 Setting up Homebrew…"
  "$DOTFILES_DIR/setup/brew.sh"
fi
echo

# Setup Zsh and register it as a default shell
title "🐚 Setting up Zsh…"
"$DOTFILES_DIR/setup/zsh.sh"
echo

# Xcode CLT, gh auth, mise tools, Claude Code + CodeGraph + mise/Serena MCP, PowerShell, npm config, then Claude Code's plugins/settings/skills + catalog
title "🚀 Setting up extra tools…"
"$DOTFILES_DIR/setup/misc.sh"
echo

# Install dotfiles symlinks
title "🍤 Setting up symlinks…"
"$DOTFILES_DIR/setup/symlinks.sh"

# Optional: Dash docsets built from local folders
if [ "$RUN_DASH" = true ]; then
  echo
  title "🔍 Configuring Dash docsets…"
  "$DOTFILES_DIR/setup/dash.sh"
fi

echo
echo "🦏 ${green}All done! Open a new terminal for the changes to take effect or run: source ~/.zshrc.${reset}"

"$DOTFILES_DIR/bin/nyan"
