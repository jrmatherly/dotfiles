#!/bin/bash
#
# Set up computer environment: a wrapper around `mise bootstrap`
#
# Usage:
#   ./setup.sh [-y|--yes] [--skip-codegraph] [--dash] [-h|--help] [-- <mise bootstrap args>]
#
#   -y, --yes         Don't wait for confirmation, and pass --yes to mise;
#                     the VS Code font menu and the gh login question are skipped
#   --skip-codegraph  Don't install CodeGraph or wire it into Claude Code
#   --dash            Also run the optional Dash docset configuration
#   -h, --help        Print this help and exit
#   -- <args>         Passed to `mise bootstrap`. `--skip <parts>` is added to
#                     the parts setup always skips, `--upgrade` also upgrades
#                     the packages, `--dry-run` previews and `--only` is refused
#
# Exits 0 when everything installed, and 2 when setup ran to the end but some
# packages or tools failed (listed last). Any other status means a step stopped it.
#
# License: MIT

set -euo pipefail

# Where this repo actually lives — the scripts never assume `~/dotfiles`.
# DOTFILES is what the hooks and the task in conf.d/50-bootstrap.toml read.
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd -P)"
export DOTFILES_DIR DOTFILES="$DOTFILES_DIR"

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

yes=""
# Also settable in the environment
skip_codegraph="${DOTFILES_SKIP_CODEGRAPH:-false}"
RUN_DASH=false
orig_args=("$@")

while [ $# -gt 0 ]; do
  case "$1" in
    -y | --yes)
      yes=true
      # Read by setup/misc.sh, which then takes each prompt's default
      export DOTFILES_YES=true
      ;;
    --skip-codegraph) skip_codegraph=true ;;
    --dash) RUN_DASH=true ;;
    --skip-brew)
      echo "--skip-brew is gone: use ./setup.sh -- --skip packages" >&2
      exit 1
      ;;
    -h | --help)
      # Print the header comment block (everything after the shebang)
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); if ($0 ~ /^License:/) next; print; next } NR > 1 { exit }' "$0"
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Unknown option: $1 (try --help)" >&2
      exit 1
      ;;
  esac
  shift
done

user_skip="" dry_run_flag="" upgrade=false
mise_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --skip)
      [ $# -ge 2 ] || {
        echo "--skip needs a list of parts" >&2
        exit 1
      }
      user_skip="${user_skip:+$user_skip,}$2"
      shift
      ;;
    --skip=*) user_skip="${user_skip:+$user_skip,}${1#--skip=}" ;;
    --only | --only=*)
      echo "--only cannot be combined with the --skip macos-defaults that setup always passes. Run it yourself: cd ~ && mise bootstrap --only <parts>" >&2
      exit 1
      ;;
    --dry-run | -n)
      dry_run_flag=--dry-run
      mise_args+=("$1")
      ;;
    --upgrade)
      upgrade=true
      mise_args+=("$1")
      ;;
    *) mise_args+=("$1") ;;
  esac
  shift
done

# macOS preferences are never part of setup (set-defaults owns them), and
# --only cannot be combined with --skip, so there is one merged list.
skip="macos-defaults${user_skip:+,$user_skip}"
run_packages=true run_dotfiles=true
case ",$user_skip," in *,packages,*) run_packages=false ;; *) skip="$skip,packages" ;; esac
case ",$user_skip," in *,dotfiles,*) run_dotfiles=false ;; esac
# setup installs the tools itself, between two bootstrap calls (below)
run_tools=true run_task=true
case ",$user_skip," in *,tools,*) run_tools=false ;; *) skip="$skip,tools" ;; esac
case ",$user_skip," in *,task,*) run_task=false ;; *) skip="$skip,task" ;; esac
run_extras=$run_dotfiles
[ -z "$dry_run_flag" ] || run_extras=false

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

# tput fails with TERM unset (CI, a launchd job), which would abort this set -e script
tput() { command tput "$@" 2> /dev/null || true; }
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

# The clone itself needed git, so on a new Mac the tools are usually there
if ! xcode-select -p > /dev/null 2>&1; then
  echo "Command Line Tools missing; run: xcode-select --install, then rerun ./setup.sh" >&2
  exit 1
fi

echo -e "${yellow}!!! ${red}WARNING${yellow} !!!"
echo -e "${light_red}This script replaces your configuration files with symlinks to this repo."
echo -e "${light_red}It stops when a file is in the way of a link. Nothing is overwritten.${reset}"
echo -e "${yellow}Repo: ${reset}$DOTFILES_DIR"

if [ -z "$yes" ]; then
  if [ -t 0 ]; then
    echo -e "${yellow}Press Enter key to continue…${reset}\n"
    read -r _ || true
  else
    echo -e "${yellow}Non-interactive shell — continuing without confirmation.${reset}\n"
  fi
fi

# link_into_repo <link> <target>: creates the link when nothing is there.
# Returns 1 when something else is, and leaves it alone.
link_into_repo() {
  [ -e "$1" ] || [ -L "$1" ] || ln -s "$2" "$1"
  [ "$1" -ef "$2" ]
}

# Every [dotfiles] source is written ~/dotfiles/… (mise does not expand
# variables in a source, and neither does lazygit's `shellFunctionsFile`), and
# the hooks and the task fall back to it, so it must be this clone before mise runs
if ! link_into_repo "$HOME/dotfiles" "$DOTFILES_DIR"; then
  # shellcheck disable=SC2088 # display text
  echo "~/dotfiles is not a link to $DOTFILES_DIR. Move it aside and rerun ./setup.sh" >&2
  exit 1
fi
# mise reads the whole setup through this link. With another config there it
# would find no packages, no dotfiles and no task, and exit 0.
mkdir -p "$HOME/.config"
if ! link_into_repo "$HOME/.config/mise" "$DOTFILES_DIR/tilde/.config/mise"; then
  # shellcheck disable=SC2088 # display text
  echo "~/.config/mise is not a link to $DOTFILES_DIR/tilde/.config/mise. Move it aside (mv ~/.config/mise ~/.config/mise.backup) and rerun ./setup.sh" >&2
  exit 1
fi

# mise's installer puts it in ~/.local/bin, and a fresh Mac's PATH lacks both.
# The prefix is here so a code or gh installed earlier in this run is found.
prefix="${HOMEBREW_PREFIX:-/opt/homebrew}"
export PATH="$HOME/.local/bin:$prefix/bin:$prefix/sbin:$PATH"
if ! command -v mise > /dev/null; then
  title "Installing mise…"
  # Installs to ~/.local/bin/mise and checks the archive against checksums in the script
  curl -fsSL https://mise.run | sh
fi
bash "$DOTFILES_DIR/setup/mise-floor.sh" || exit 1

if [ "$skip_codegraph" = true ]; then
  # Read by setup/misc.sh, which reshims without the second one
  export DOTFILES_SKIP_CODEGRAPH=true MISE_DISABLE_TOOLS="${MISE_DISABLE_TOOLS:+$MISE_DISABLE_TOOLS,}npm:@colbymchenry/codegraph"
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
# that follow can't use sudo without asking. Without a keep-alive mise's own
# sudo prompts may have cached one, so it is dropped either way.
sudo_keepalive_stop() {
  if [ -n "${SUDO_KEEPALIVE_PID:-}" ]; then
    kill "$SUDO_KEEPALIVE_PID" 2> /dev/null || true
    SUDO_KEEPALIVE_PID=""
    echo "Sudo released"
  fi
  sudo -k 2> /dev/null || true
}

# Ask for the administrator password once, for the packages, sudo_local and
# the login shell. It is dropped before the tools install.
# Without a terminal mise asks per step, and a dry run needs none.
if [ -t 0 ] && [ -z "$dry_run_flag" ]; then
  warning "Activate sudo"
  sudo -v
  sudo_keepalive_start
  echo "Sudo activated!"
  echo
fi

# mise asks gh for a token itself ([settings.github] in config.toml), so none is
# exported here for every build and hook to inherit
if [ -z "${MISE_GITHUB_TOKEN:-}" ] && ! gh auth token > /dev/null 2>&1; then
  warning "No GitHub token: tap formulae use the anonymous API limit (60 calls an hour). If packages fail to resolve, run gh auth login and rerun ./setup.sh"
fi

# Every mise call below runs from here: started in the clone, mise would take
# node from the repo's .nvmrc instead of the configured versions
cd "$HOME"

# Linked before any package: packages write into $HOME (the git-credential-manager
# pkg writes ~/.gitconfig, `code` creates Code/User), and a real file where a
# link belongs stops the apply. mise bootstrap's own dotfiles part then finds
# nothing left to do.
if [ "$run_dotfiles" = true ]; then
  title "🔗 Linking the dotfiles…"
  # --yes: the Enter prompt above was the confirmation, and mise asks per file otherwise
  if ! mise dotfiles apply --yes ${dry_run_flag:+"$dry_run_flag"}; then
    warning "mise dotfiles apply stopped. Move aside what it reported, then rerun ./setup.sh"
    exit 1
  fi
  echo
fi

# What the run carried on past, listed at the end: one "kind<TAB>name<TAB>reason"
# line each (bash 3.2 has no associative arrays)
problems=""
# problem <kind> <name> [<mise output>]: the reason is mise's own `failed:` or
# ERROR text, and stays empty when mise printed none
problem() {
  local reason
  reason=$(grep -E 'failed: |ERROR ' <<< "${3:-}" | grep -vE 'ERROR +(Version:|Run with)' | tail -1 | sed -E 's/.*(failed: |ERROR +)//' | cut -c1-100) || reason=""
  problems+="$1"$'\t'"$2"$'\t'"$reason"$'\n'
}

# packages_for <manager> <noun> <kind>: setup applies the packages itself, because
# mise bootstrap stops at the first part that fails and one failed cask would
# skip the dotfiles, the login shell and the tools. A failed package warns and
# the run goes on, but "no packages requested" means mise read no package list.
packages_for() {
  local out
  title "🫖 Installing $2 with mise…"
  if ! out=$(mise bootstrap packages apply --yes --manager "$1" ${dry_run_flag:+"$dry_run_flag"} 2>&1 | tee /dev/stderr); then
    if grep -q 'no packages requested' <<< "$out"; then
      warning "mise read no package list from $HOME/.config/mise"
      exit 1
    fi
    # mise stops at the first package that fails, so each one after it gets its own apply
    local missing pkg
    missing=$(mise bootstrap packages status --json | jq -r --arg m "$1" '.[$m].packages[]? | select(.state == "missing") | .package') || missing=""
    if [ -z "$missing" ]; then
      warning "Some $2 failed to install. See above, then rerun ./setup.sh"
      problem "$3" "some $2" "$out"
    fi
    for pkg in $missing; do
      if ! out=$(mise bootstrap packages apply --yes ${dry_run_flag:+"$dry_run_flag"} "$1:$pkg" 2>&1 | tee /dev/stderr); then
        warning "$1:$pkg failed to install. See above, then rerun ./setup.sh"
        problem "$3" "$pkg" "$out"
      fi
    done
  fi
  # mise's own --upgrade upgrades packages only in the part setup skips
  if [ "$upgrade" = true ] && ! out=$(mise bootstrap packages upgrade --yes --manager "$1" ${dry_run_flag:+"$dry_run_flag"} 2>&1 | tee /dev/stderr); then
    warning "Some $2 failed to upgrade. See above, then rerun ./setup.sh -- --upgrade"
    problem upgrade "$2" "$out"
  fi
  # The full install measured about 32 GB; a full disk is the likeliest mid-run failure
  echo "$(df -h / | awk 'NR == 2 { print $4 }') free on /"
}

# The git-credential-manager pkg registers itself with `git config --global`,
# and ~/.gitconfig is a link to the tracked file, so its sections move to the
# local include. A value the local file already has is not added twice.
move_credential_config() {
  local tracked="$DOTFILES_DIR/tilde/.gitconfig" local_file="$HOME/.gitconfig.local" entry key value
  git config --file "$tracked" --get-regexp '^credential\.' > /dev/null 2>&1 || return 0
  # --null prints key, newline, value, NUL: the first helper value is empty
  while IFS= read -r -d '' entry; do
    key=${entry%%$'\n'*} value=${entry#*$'\n'}
    git config --file "$local_file" --get-all "$key" 2> /dev/null | grep -qxF -- "$value" \
      || git config --file "$local_file" --add "$key" "$value" || return 1
  done < <(git config --file "$tracked" --null --get-regexp '^credential\.')
  git config --file "$tracked" --name-only --get-regexp '^credential\.' | sed 's/\.[^.]*$//' | sort -u \
    | while IFS= read -r key; do git config --file "$tracked" --remove-section "$key"; done
  echo "Moved the [credential] sections a package wrote into ~/.gitconfig to ~/.gitconfig.local"
}

if [ "$run_packages" = true ]; then
  # The pre-packages hook does this for a bare `mise bootstrap`
  [ -n "$dry_run_flag" ] || mise plugins link --force vscode "$DOTFILES_DIR/mise-plugins/vscode"
  # Formulae first: reading the claude-multipass-app tap cask needs the Ruby 3 that brew:ruby installs
  packages_for brew formulae formula
  packages_for brew-cask casks cask
  echo
fi

bootstrap() {
  mise bootstrap ${yes:+--yes} "$@" ${mise_args[@]+"${mise_args[@]}"} || {
    local rc=$?
    warning "mise bootstrap stopped. Earlier steps stay applied. Fix what it reported, then rerun ./setup.sh"
    exit "$rc"
  }
}

title "🚀 Running mise bootstrap…"
bootstrap --skip "$skip"
sudo_keepalive_stop

# Not mise's tools part, which stops the whole bootstrap at a failed tool.
# mise install carries on past one and exits 1, and the task needs the rest.
if [ "$run_tools" = true ]; then
  title "🧰 Installing the mise tools…"
  if ! out=$(mise install --yes ${dry_run_flag:+"$dry_run_flag"} 2>&1 | tee /dev/stderr); then
    missing=$(mise ls --missing --json | jq -r 'keys[]') || missing=""
    [ -n "$missing" ] || problem tool "mise install" "$out"
    for tool in $missing; do
      problem tool "$tool" "$(grep -F " $tool@" <<< "$out")"
    done
  fi
  # What mise's --upgrade did in the tools part
  if [ "$upgrade" = true ] && ! out=$(mise upgrade --yes ${dry_run_flag:+"$dry_run_flag"} 2>&1 | tee /dev/stderr); then
    problem upgrade tools "$out"
  fi
  echo
fi

[ "$run_task" = false ] || bootstrap --only task

if [ "$run_packages" = true ]; then
  # The VS Code cask may have arrived in this run, without code on PATH yet
  if command -v code > /dev/null; then
    packages_for vscode extensions extension
  else
    echo "VS Code is not installed yet: extensions are skipped. Rerun ./setup.sh once it is."
  fi
  echo
fi

# Never a mise hook: a post-dotfiles hook also runs on every plain
# `mise dotfiles apply`, where nobody can answer its prompts. It asks for sudo
# itself, and only to link cot or code.
if [ "$run_extras" = true ]; then
  "$DOTFILES_DIR/setup/dotfiles-extras.sh"
  # After the extras script, which writes the identity only while ~/.gitconfig.local is missing
  [ "$run_packages" = false ] || move_credential_config || warning "Could not move the [credential] sections out of tilde/.gitconfig. Move them to ~/.gitconfig.local by hand"
  sudo -k 2> /dev/null || true
fi

# Optional: Dash docsets built from local folders
if [ "$RUN_DASH" = true ]; then
  echo
  title "🔍 Configuring Dash docsets…"
  "$DOTFILES_DIR/setup/dash.sh"
fi

echo
if [ -z "$problems" ]; then
  echo "🦏 ${green}All done! Open a new terminal for the changes to take effect or run: source ~/.zshrc.${reset}"
  "$DOTFILES_DIR/bin/nyan"
  exit 0
fi

# In place of the art, so the list is the last thing on screen
n=$(grep -c . <<< "$problems")
echo "⚠️  ${bold}Setup finished with $n problem$([ "$n" -eq 1 ] || echo s)${reset}"
echo
awk -F '\t' -v x="${red}✗${reset}" 'NF {
    k[++n] = $1; p[n] = $2; r[n] = $3
    if (length($1) > kw) kw = length($1)
    if (length($2) > pw) pw = length($2)
  }
  END { for (i = 1; i <= n; i++) { l = sprintf("  %s %-*s   %-*s   %s", x, kw, k[i], pw, p[i], r[i]); sub(/ +$/, "", l); print l } }' <<< "$problems"
echo
echo "  Everything else is installed. To retry: ./setup.sh$([ "$upgrade" = false ] || echo ' -- --upgrade')"
case "$problems" in tool$'\t'* | *$'\n'tool$'\t'*) echo "  To see why a tool failed: mise install <tool>" ;; esac
exit 2
