#!/bin/bash
#
# Set up computer environment: a wrapper around `mise bootstrap`
#
# Usage:
#   ./setup.sh [-y|--yes] [--without <modules>] [--skip-codegraph] [--dash] [-h|--help] [-- <mise bootstrap args>]
#
#   -y, --yes         Don't wait for confirmation, and pass --yes to mise;
#                     the VS Code font menu and the gh login question are skipped
#   --without <a,b>   Turn these modules off before installing (docs/modules.md).
#                     It is remembered: a later run leaves them off
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
# An installed copy is mise's own checkout: its hints name rotm, and nothing may write into it
self=./setup.sh installed=false
if [ "$("$DOTFILES_DIR/bin/lib/rotm-mode" "$DOTFILES_DIR")" = installed ]; then
  self='rotm install' installed=true
fi

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
without=""
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
    --without)
      [ $# -ge 2 ] || {
        echo "--without needs a list of modules" >&2
        exit 1
      }
      without="${without:+$without,}$2"
      shift
      ;;
    --without=*) without="${without:+$without,}${1#--without=}" ;;
    --skip-brew)
      echo "--skip-brew is gone: use $self -- --skip packages" >&2
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

# A typo stops here, before the banner, the password prompt and the mise install
modules="$DOTFILES_DIR/bin/lib/rotm-modules"
if [ -n "$without" ]; then
  IFS=, read -ra without_names <<< "$without"
  for name in "${without_names[@]}"; do
    rc=0
    "$modules" is-on "$name" || rc=$?
    [ "$rc" -ne 2 ] || exit 2
  done
fi

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

# Until 2026-11-12 the config environment was named `installed`, a name a
# project's own mise.installed.toml also answers to. A copy from then still has
# it saved, and without the new name config.rotm-installed.toml is not read.
# Before every check that can stop the run: a copy left with the old name has
# its app-written targets linked into the checkout by the next mise dotfiles apply.
rc_local="$DOTFILES_DIR/tilde/.config/mise/miserc.local.toml"
if [ "$installed" = true ] && [ -z "$dry_run_flag" ] && grep -qE '^env[[:space:]]*=.*"installed"' "$rc_local" 2> /dev/null; then
  sed -i '' -E '/^env[[:space:]]*=/s/"installed"/"rotm-installed"/' "$rc_local"
  echo "Renamed the saved config environment from installed to rotm-installed"
fi

# The clone itself needed git, so on a new Mac the tools are usually there
if ! xcode-select -p > /dev/null 2>&1; then
  echo "Command Line Tools missing; run: xcode-select --install, then rerun $self" >&2
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
  echo "~/dotfiles is not a link to $DOTFILES_DIR. Move it aside and rerun $self" >&2
  exit 1
fi
# mise reads the whole setup through this link. With another config there it
# would find no packages, no dotfiles and no task, and exit 0.
mkdir -p "$HOME/.config"
if ! link_into_repo "$HOME/.config/mise" "$DOTFILES_DIR/tilde/.config/mise"; then
  # shellcheck disable=SC2088 # display text
  echo "~/.config/mise is not a link to $DOTFILES_DIR/tilde/.config/mise. Move it aside (mv ~/.config/mise ~/.config/mise.backup) and rerun $self" >&2
  exit 1
fi

# mise skips a module (conf.d/60-rotm-<name>.toml) only while ignored_config_paths
# in miserc.local.toml names it, so the list is written before any mise call
if [ -n "$dry_run_flag" ]; then
  echo "dry run: the module list is not written"
else
  # The user's settings live in their own folder, linked from the config dir
  "$DOTFILES_DIR/bin/lib/rotm-user-layer" ensure || exit $?
  "$modules" sync ${without:+--without "$without"} || exit $?
fi

# On an installed copy ~/.zshrc and ~/.gitconfig are seeded once and then the
# user's, so mise keeps a file that is already there without a word, and ours
# would never load. Stop instead, as a clone does at a file in the way of a link,
# and before the password prompt.
if [ "$installed" = true ] && [ "$run_dotfiles" = true ]; then
  for ours in tilde/.zshrc tilde/.gitconfig; do
    theirs="$HOME/${ours#tilde/}"
    if [ -f "$theirs" ] && [ ! -L "$theirs" ] && ! grep -qF "$ours" "$theirs"; then
      echo "$theirs is your own and does not load returnofthemac's. Move it aside (mv $theirs $theirs.backup) or add the lines of $DOTFILES_DIR/$ours.installed to it, then rerun $self" >&2
      exit 1
    fi
  done
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

# Again now that mise exists: with a module off, sync has mise trust the module
# files, without which mise dotfiles and mise bootstrap stop at an ignored one
[ -n "$dry_run_flag" ] || "$modules" sync > /dev/null || exit $?

# Read by setup/misc.sh, which reshims without the second one
disable_codegraph() { export DOTFILES_SKIP_CODEGRAPH=true MISE_DISABLE_TOOLS="${MISE_DISABLE_TOOLS:+$MISE_DISABLE_TOOLS,}npm:@colbymchenry/codegraph"; }
[ "$skip_codegraph" != true ] || disable_codegraph

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
  # A trap that returns lets the run carry on past a guarded step, so Ctrl-C exits and EXIT cleans up
  trap sudo_keepalive_stop EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
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

# Every mise call below runs from here: started in the clone, mise would take
# node from the repo's .nvmrc instead of the configured versions
cd "$HOME"

# Linked before any package: packages write into $HOME (the git-credential-manager
# pkg writes ~/.gitconfig, `code` creates Code/User), and a real file where a
# link belongs stops the apply. mise bootstrap's own dotfiles part then finds
# nothing left to do.
if [ "$run_dotfiles" = true ]; then
  title "🔗 Linking the dotfiles…"
  # A folder that config.rotm-installed.toml makes real may still be a link from before
  # that entry arrived. mise keeps such a link and writes the folder's entries
  # through it, into the checkout (probe 14), so the link goes first.
  if [ "$installed" = true ] && [ -z "$dry_run_flag" ]; then
    while IFS= read -r key; do
      path="$HOME/${key#\~/}"
      [ -L "$path" ] || continue
      case "$(cd "$path" 2> /dev/null && pwd -P)" in
        "$DOTFILES_DIR"/*)
          rm "$path"
          echo "Unlinked $path: it is a real folder on an installed copy"
          ;;
      esac
    done < <(sed -n 's/^"\([^"]*\)" = { permissions = .*/\1/p' "$DOTFILES_DIR/tilde/.config/mise/config.rotm-installed.toml" 2> /dev/null)
  fi
  # --yes: the Enter prompt above was the confirmation, and mise asks per file otherwise
  if ! mise dotfiles apply --yes ${dry_run_flag:+"$dry_run_flag"}; then
    warning "mise dotfiles apply stopped. Move aside what it reported, then rerun $self"
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
    local states missing pkg
    states=$(mise bootstrap packages status --json | jq -r --arg m "$1" '.[$m].packages[]? | "\(.state)\t\(.package)"') || states=""
    missing=$(awk -F'\t' '$1 == "missing" { print $2 }' <<< "$states")
    if [ -n "$missing" ]; then
      :
    elif grep -q '^unexpectedly_installed' <<< "$states"; then
      # With --manager mise fails an installed package that a local config declares { state = "absent" }.
      # Nothing is missing, so that choice is not a problem
      echo "Nothing is missing: mise stopped at $2 that are installed and declared absent, and they stay as they are."
    else
      warning "Some $2 failed to install. See above, then rerun $self"
      problem "$3" "some $2" "$out"
    fi
    for pkg in $missing; do
      if ! out=$(mise bootstrap packages apply --yes ${dry_run_flag:+"$dry_run_flag"} "$1:$pkg" 2>&1 | tee /dev/stderr); then
        warning "$1:$pkg failed to install. See above, then rerun $self"
        problem "$3" "$pkg" "$out"
      fi
    done
  fi
  # mise's own --upgrade upgrades packages only in the part setup skips
  if [ "$upgrade" = true ] && ! out=$(mise bootstrap packages upgrade --yes --manager "$1" ${dry_run_flag:+"$dry_run_flag"} 2>&1 | tee /dev/stderr); then
    warning "Some $2 failed to upgrade. See above, then rerun $self -- --upgrade"
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

# mise asks gh for a token itself ([settings.github] in config.toml), so none is
# exported here for every build and hook to inherit
github_token() { [ -n "${MISE_GITHUB_TOKEN:-}" ] || gh auth token > /dev/null 2>&1; }

# The login comes before the package lists and the tools, which are what spend
# the anonymous limit: a rerun in the same hour as the install ran out of it.
# gh is installed alone for that. A run that cannot ask keeps the warning.
github_login() {
  github_token && return 0
  if [ "$run_packages" = true ] && [ -t 0 ] && [ -z "$yes" ] && [ -z "$dry_run_flag" ]; then
    title "🔑 GitHub login…"
    command -v gh > /dev/null || mise bootstrap packages apply --yes brew:gh || true
    if command -v gh > /dev/null; then
      read -rp "Without a login GitHub allows 60 API calls an hour, and the packages and tools use them. Run \`gh auth login\` now? [y/N] " gh_login || gh_login=""
      case "$gh_login" in
        y | Y) gh auth login || echo "gh auth login failed or was cancelled. Run it later." ;;
      esac
    fi
    echo
  fi
  github_token || warning "No GitHub token: tap formulae use the anonymous API limit (60 calls an hour). If packages fail to resolve, run gh auth login and rerun $self"
}

# The pre-packages hook does this for a bare `mise bootstrap`. Before the login,
# whose apply of gh reads a config that declares vscode: keys
[ "$run_packages" != true ] || [ -n "$dry_run_flag" ] || mise plugins link --force vscode "$DOTFILES_DIR/mise-plugins/vscode"
github_login

# The settings a user saved with `rotm settings sync on` load before the package lists. This is
# `sync on`'s lookup in bash, because bin/dotfiles-settings needs uv, which the package lists install
restored=false
load_saved_settings() {
  local origin login repo answer folder aside=""
  [ -z "$dry_run_flag" ] && github_token || return 0
  origin=$(mise dot origin 2>&1) || true
  case "$origin" in *"no setup repository is connected"*) ;; *) return 0 ;; esac
  login=$(gh api user --jq .login 2> /dev/null) && [ -n "$login" ] || return 0
  repo="$login/rotm-settings"
  [ "$(gh repo view "$repo" --json isEmpty --jq .isEmpty 2> /dev/null)" = false ] \
    && [ "$(gh repo view "$repo" --json visibility --jq .visibility 2> /dev/null)" = PRIVATE ] \
    && gh api "repos/$repo/contents/.mise-history/format.toml" > /dev/null 2>&1 || return 0
  if [ ! -t 0 ] || [ -n "$yes" ]; then
    echo "Your saved settings are in $repo. Run \`rotm settings sync on\` after setup to load them."
    return 0
  fi
  read -rp "Load your saved settings from $repo before installing? [Y/n] " answer || answer=n
  case "$answer" in n | N) return 0 ;; esac
  folder=$("$DOTFILES_DIR/bin/lib/rotm-user-layer" dir)
  # This run's --without wrote the list already: set aside, it would conflict with the saved one
  if [ -n "$without" ] && [ -e "$folder/modules-off.local" ]; then
    aside=$(mktemp)
    mv "$folder/modules-off.local" "$aside"
  fi
  if "$DOTFILES_DIR/bin/lib/rotm-user-layer" restore "https://github.com/$repo.git"; then
    restored=true
    echo "Loaded your saved settings from $repo."
  else
    warning "Your saved settings did not load, and setup carries on without them. Run rotm settings sync status to see why"
    [ -z "$aside" ] || [ -e "$folder/modules-off.local" ] || mv "$aside" "$folder/modules-off.local"
  fi
  [ -z "$aside" ] || rm -f "$aside"
  # The flag wins over the saved list, and a module switched off there is off before the packages
  "$modules" sync ${without:+--without "$without"} || exit $?
  # skip_codegraph was read before the restore
  if [ "$restored" = true ] && [ "$skip_codegraph" != true ] \
    && [ "$(mise env --json | /usr/bin/jq -r '.DOTFILES_SKIP_CODEGRAPH // empty')" = true ]; then
    disable_codegraph
  fi
  echo
}
load_saved_settings

if [ "$run_packages" = true ]; then
  # Formulae first: reading the claude-multipass-app tap cask needs the Ruby 3 that brew:ruby installs
  packages_for brew formulae formula
  packages_for brew-cask casks cask
  echo
fi

bootstrap() {
  mise bootstrap ${yes:+--yes} "$@" ${mise_args[@]+"${mise_args[@]}"} || {
    local rc=$?
    warning "mise bootstrap stopped. Earlier steps stay applied. Fix what it reported, then rerun $self"
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
  # The cask is in the base and every extension in the module, so with it off
  # mise has no vscode package and --manager vscode is its fatal "no packages requested"
  if ! "$modules" is-on vscode; then
    echo "The vscode module is off: extensions are skipped."
  elif command -v code > /dev/null; then
    packages_for vscode extensions extension
  else
    echo "VS Code is not installed yet: extensions are skipped. Rerun $self once it is."
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

# After the task's claude-config restore, so the saved tool settings are the last write.
# ROTM_JUST_INSTALLED: this run installed with the restored files, so apply's "run rotm install" would be false
if [ "$restored" = true ] && ! ROTM_JUST_INSTALLED=1 "$DOTFILES_DIR/bin/dotfiles-settings" sync apply; then
  warning "Your saved tool settings did not apply. Run rotm settings sync apply once setup is done"
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
echo "  Everything else is installed. To retry: $self$([ "$upgrade" = false ] || echo ' -- --upgrade')"
case "$problems" in tool$'\t'* | *$'\n'tool$'\t'*) echo "  To see why a tool failed: mise install <tool>" ;; esac
exit 2
