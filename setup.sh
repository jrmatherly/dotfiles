#!/bin/bash
#
# Set up computer environment
#
# Usage:
#   ./setup.sh [-y|--yes] [--skip-brew] [--skip-codegraph] [--dash] [-h|--help]
#
#   -y, --yes         Don't wait for confirmation before starting
#   --skip-brew       Skip setup/packages.sh (the mise package install) —
#                     handy when re-running for dotfiles changes only
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
# install, func, pwsh, az, aspire, codegraph, rtk, claude) — zsh/env.zsh sets the same for
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
export DISABLE_ERROR_REPORTING=1

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
echo -e "${light_red}It stops when a file is in the way of a link. Nothing is overwritten.${reset}"
echo -e "${yellow}Repo: ${reset}$DOTFILES_DIR"

if [ "$SKIP_CONFIRM" = false ]; then
  if [ -t 0 ]; then
    echo -e "${yellow}Press Enter key to continue…${reset}\n"
    read -r _ || true
  else
    echo -e "${yellow}Non-interactive shell — continuing without confirmation.${reset}\n"
  fi
fi

# Every [dotfiles] source is written ~/dotfiles/… (mise does not expand
# variables in a source, and neither does lazygit's `shellFunctionsFile`), so
# ~/dotfiles must be this clone before anything is installed
if [ ! -e "$HOME/dotfiles" ] && [ ! -L "$HOME/dotfiles" ]; then
  title "🔗 Linking ~/dotfiles → ${DOTFILES_DIR}…"
  ln -s "$DOTFILES_DIR" "$HOME/dotfiles"
fi
if [ ! "$HOME/dotfiles" -ef "$DOTFILES_DIR" ]; then
  # shellcheck disable=SC2088 # display text
  echo "~/dotfiles is not this clone ($DOTFILES_DIR). Every link goes through it. Move it aside and run setup again." >&2
  exit 1
fi

# Use Touch ID to authorize sudo
if [ ! -f /etc/pam.d/sudo_local ]; then
  title "🔒 Enabling Touch ID to authorize sudo commands…"
  echo "auth       sufficient     pam_tid.so" | sudo tee /etc/pam.d/sudo_local > /dev/null
fi

# Keep the sudo timestamp alive so app installers don't re-prompt halfway.
# `sudo -n -v` extends the credential without prompting (`sudo -n true` only
# checks it); `|| true` keeps one failure from killing the loop under `set -e`.
sudo_keepalive_start() {
  while true; do
    sudo -n -v 2> /dev/null || true
    sleep 60
    kill -0 "$$" 2> /dev/null || exit
  done &
  SUDO_KEEPALIVE_PID=$!
  trap sudo_keepalive_stop EXIT INT TERM
}

# Stop the keep-alive and drop the cached credential (`sudo -k`), so the steps
# that follow can't use sudo without asking. A no-op when none is running.
sudo_keepalive_stop() {
  [ -n "${SUDO_KEEPALIVE_PID:-}" ] || return 0
  kill "$SUDO_KEEPALIVE_PID" 2> /dev/null || true
  SUDO_KEEPALIVE_PID=""
  sudo -k
  echo "Sudo released"
}

# Ask for the administrator password upfront; sudo is held for the packages and
# Zsh, and released before misc.sh (curl | bash, npm, uv, dotnet)
warning "Activate sudo"
sudo -v
# Tells the child scripts sudo is already cached, so they skip their own prompt
export DOTFILES_SUDO_KEPT=1
sudo_keepalive_start
echo "Sudo activated!"
echo

# Install mise and the packages/apps
if [ "$SKIP_BREW" = true ]; then
  title "🫖 Skipping packages (--skip-brew)…"
else
  title "🫖 Installing packages with mise…"
  "$DOTFILES_DIR/setup/packages.sh"
fi
echo

# Setup Zsh and register it as a default shell
title "🐚 Setting up Zsh…"
"$DOTFILES_DIR/setup/zsh.sh"
echo

# Xcode CLT, gh auth, mise tools, Claude Code + CodeGraph + mise/Serena MCP, PowerShell, npm config, then Claude Code's plugins/settings/skills + catalog
# misc.sh needs no sudo, so its installers run without it
sudo_keepalive_stop
title "🚀 Setting up extra tools…"
"$DOTFILES_DIR/setup/misc.sh"
echo

# A real file where a link belongs stops here: mise names it and writes nothing.
# dotfiles-extras.sh asks for sudo itself, and only to link cot or code. It runs
# from here and never as a mise hook: a hook also runs on every plain
# `mise dotfiles apply`, where nobody can answer its prompts.
title "🍤 Linking dotfiles…"
# mise's installer puts it in ~/.local/bin, and a fresh Mac's PATH lacks both
export PATH="$HOME/.local/bin:${HOMEBREW_PREFIX:-/opt/homebrew}/bin:$PATH"
if ! command -v mise > /dev/null; then
  echo "mise not found, so no dotfile was linked. Run setup again without --skip-brew." >&2
  exit 1
fi
# mise reads the [dotfiles] entries through this link (misc.sh makes it). With
# another config there it finds none, links nothing and exits 0.
if [ ! "$HOME/.config/mise" -ef "$DOTFILES_DIR/tilde/.config/mise" ]; then
  # shellcheck disable=SC2088 # display text
  echo "~/.config/mise is not this clone's tilde/.config/mise, so mise cannot read the dotfiles list. Move it aside and run setup again." >&2
  exit 1
fi
# From $HOME, so a project's mise config can't add to the run. It never asks.
(cd "$HOME" && mise dotfiles apply --yes)
"$DOTFILES_DIR/setup/dotfiles-extras.sh"

# Optional: Dash docsets built from local folders
if [ "$RUN_DASH" = true ]; then
  echo
  title "🔍 Configuring Dash docsets…"
  "$DOTFILES_DIR/setup/dash.sh"
fi

echo
echo "🦏 ${green}All done! Open a new terminal for the changes to take effect or run: source ~/.zshrc.${reset}"

"$DOTFILES_DIR/bin/nyan"
