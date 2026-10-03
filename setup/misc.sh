#!/bin/bash

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd -P)}"
cd "$DOTFILES_DIR"

# Homebrew may not be installed yet (e.g. `setup.sh --skip-brew` on a fresh Mac)
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

BLUE=$(tput setaf 4)
BOLD=$(tput bold)
RESET=$(tput sgr0)

indent() {
  sed 's/^/  /'
}

info() {
  echo
  echo "[ ${BLUE}..${RESET} ] $1" | indent
}

warning() {
  tput setaf 1
  echo "/!\\ $1 /!\\"
  tput sgr0
}

command_exists() {
  command -v "$@" &> /dev/null
}

# Ask for the administrator password upfront
warning "Activate sudo"
sudo echo "Sudo activated!"
echo

# Install Xcode Command Line Tools and accept its license
if ! xcode-select -p &> /dev/null; then
  xcode-select --install &> /dev/null

  # Wait until the Xcode Command Line Tools are installed
  until xcode-select -p &> /dev/null; do
    sleep 5
  done
fi

# Verify Xcode Command Line Tools successful installation
xcode-select -p

# Make custom binary scripts executable
info 'Changing access permissions for binary scripts…'
# shellcheck disable=SC2016 # ${0##*/} is for the inner bash -c, so it must stay unexpanded here
find "$DOTFILES_DIR/bin" -type f -not -name '.DS_Store' -not -name '*.md' -exec chmod +x {} \; -exec bash -c 'printf "\r\033[2K  [ \033[00;32m✔\033[0m ] set for %s\n" "${0##*/}"' {} \;
echo
echo 'Done!' | indent
echo

# Iosevka Code Nerd Font — VS Code's editor and terminal font (companion of the
# SpaceBox theme; no Homebrew cask). Installs it when missing and reinstalls it
# when the upstream release zip changed; unchanged costs one conditional request.
info "🔤 Checking the Iosevka Code font…"
"$DOTFILES_DIR/bin/install-iosevka-code" 2>&1 | indent \
  || warning "Iosevka Code font not installed — run it later: install-iosevka-code"

# VS Code settings.json is rendered from vscode/User/settings.json.j2 with a
# font preset (vscode/presets.toml); a terminal gets the preset menu. It never
# overwrites edits VS Code made since the last render (drift is a warning).
if command_exists minijinja-cli; then
  info "🖋️ Rendering VS Code settings…"
  # The menu runs unpiped: through `| indent`, read -p's prompt (no newline)
  # stays in sed's buffer until after you answer
  if [ -t 0 ]; then
    "$DOTFILES_DIR/bin/vscode-settings" --choose
  else
    "$DOTFILES_DIR/bin/vscode-settings" 2>&1 | indent
  fi || warning "VS Code settings not rendered — fix what's shown above, then run: vscode-settings"
else
  warning "minijinja-cli not found, so VS Code settings weren't rendered — brew install minijinja-cli, then run: vscode-settings"
fi

# GitHub CLI: authenticate if not logged in already. `gh auth login` asks for
# the account, protocol and auth method itself, and writes ~/.config/gh/hosts.yml
# (gitignored — it can hold an OAuth token).
if command_exists gh && ! gh auth status &> /dev/null; then
  # Link the config dir first (symlinks.sh will skip it later as already done)
  # so gh writes its hosts.yml inside the repo's gitignored path rather than
  # creating a real ~/.config/gh that symlinks.sh would then have to replace
  mkdir -p "$HOME/.config"
  if [ ! -e "$HOME/.config/gh" ] || [ -L "$HOME/.config/gh" ]; then
    ln -sfn "$DOTFILES_DIR/tilde/.config/gh" "$HOME/.config/gh"
  fi

  if [ -t 0 ]; then
    read -rp "  [GitHub CLI] Not logged in. Run \`gh auth login\` now? [y/N] " gh_login
    case "$gh_login" in
      y | Y)
        gh auth login || echo "gh auth login failed or was cancelled — run it later" | indent
        ;;
      *) echo "Skipped. Log in later with: ${BOLD}gh auth login${RESET}" | indent ;;
    esac
  else
    echo "[GitHub CLI] You are not logged into any GitHub hosts. To log in, run: ${BOLD}gh auth login${RESET}" | indent
  fi
fi

# Node.js — installed and managed by mise. The global mise config lives in this
# repo; link it first (symlinks.sh runs later and will skip it as already done)
# so `mise install` picks up the tracked tool versions.
if command_exists mise; then
  info "📦 Installing runtimes with mise…"
  mkdir -p "$HOME/.config"
  if [ ! -e "$HOME/.config/mise" ] || [ -L "$HOME/.config/mise" ]; then
    ln -sfn "$DOTFILES_DIR/tilde/.config/mise" "$HOME/.config/mise"
  else
    # A real directory from an earlier mise install: symlinks.sh will ask
    # before replacing it, so don't touch it here — but this `mise install`
    # uses that old config, not the repo's
    # shellcheck disable=SC2088 # display text, not a path
    warning "~/.config/mise is not linked to this repo — installing from its existing config"
    echo "Let symlinks.sh replace it, then run: ${BOLD}mise install${RESET}" | indent
  fi
  # --skip-codegraph: leave it out of this install (doesn't remove an existing
  # one). Scope MISE_DISABLE_TOOLS to `mise install` only, then reshim without
  # it: a reshim while it's set deletes the shim of an already-installed
  # CodeGraph, breaking `codegraph` on PATH and Claude Code's MCP server.
  if [ "${DOTFILES_SKIP_CODEGRAPH:-false}" = true ]; then
    MISE_DISABLE_TOOLS="npm:@colbymchenry/codegraph" mise install | indent
    mise reshim
  else
    mise install | indent
  fi
  # Make node/npm available to the rest of this script. `activate --shims` is
  # just a PATH prepend, so fall back to the shim dir if it can't be evaluated.
  if shims_env="$(mise activate bash --shims 2> /dev/null)"; then
    eval "$shims_env"
  else
    export PATH="${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims:$PATH"
  fi
else
  echo "mise not found — skipping runtime installation" | indent
fi

# Claude Code — Anthropic's native installer, into ~/.local/bin (zsh/path.zsh
# puts it on PATH). Only when missing: it auto-updates itself afterwards.
# https://docs.claude.com/en/docs/claude-code/setup
if [ -x "$HOME/.local/bin/claude" ] || command_exists claude; then
  echo "Claude Code already installed — it updates itself" | indent
else
  info "🤖 Installing Claude Code…"
  curl -fsSL https://claude.ai/install.sh | bash | indent \
    || warning "Claude Code install failed — run it later: curl -fsSL https://claude.ai/install.sh | bash"
fi

# CodeGraph (installed by mise above) — wire its MCP server into Claude Code:
# user-scope entry in ~/.claude.json, auto-allow permission + UserPromptSubmit
# hook in ~/.claude/settings.json, marker-fenced block in ~/.claude/CLAUDE.md.
# Idempotent. Claude Code only: the installer writes via tmp file + rename,
# which would replace the ~/.codex/AGENTS.md symlink with a regular file.
# https://github.com/colbymchenry/codegraph#2-connect-your-agents
if [ "${DOTFILES_SKIP_CODEGRAPH:-false}" = true ]; then
  echo "Skipping CodeGraph (--skip-codegraph)" | indent
elif command_exists codegraph; then
  info "🕸️ Connecting CodeGraph to Claude Code…"
  codegraph install --yes --target claude --location global --no-color | indent \
    || warning "codegraph install failed — run it later: codegraph install --target claude"
  # Persisted opt-out: the MCP server Claude Code spawns may not inherit
  # CODEGRAPH_TELEMETRY=0 from zsh/env.zsh (e.g. GUI-launched)
  codegraph telemetry off | indent || true
else
  echo "codegraph not found — skipping CodeGraph agent setup" | indent
fi

# mise's MCP server for Claude Code (user scope — serves whichever project
# Claude runs in): exposes tools, tasks, env and config, and can run tasks.
# Documented as experimental, hence MISE_EXPERIMENTAL=1. Note `mise://env`
# shows real environment values, secrets included, to the agent.
# https://mise.jdx.dev/mcp.html
claude_bin="$(command -v claude || echo "$HOME/.local/bin/claude")"
if command_exists mise && [ -x "$claude_bin" ]; then
  if "$claude_bin" mcp get mise &> /dev/null; then
    echo "mise MCP server already registered with Claude Code" | indent
  else
    info "🔌 Registering mise's MCP server with Claude Code…"
    "$claude_bin" mcp add --scope user mise -e MISE_EXPERIMENTAL=1 -- "$(command -v mise)" mcp | indent \
      || warning "Registering the mise MCP server failed — run: claude mcp add --scope user mise -e MISE_EXPERIMENTAL=1 -- mise mcp"
  fi
fi

# Serena — symbol-level code tools over language servers, as an MCP server for
# Claude Code. Installed as a uv tool (its only documented install method);
# `bin/upup` upgrades it. Launch invariants (claude-code context, one
# user-scope registration, --project-from-cwd): ~/.claude/rules/serena.md
# https://github.com/oraios/serena
serena_bin="$HOME/.local/bin/serena"
if command_exists uv && [ ! -x "$serena_bin" ]; then
  info "🧰 Installing Serena…"
  uv tool install -p 3.13 serena-agent | indent \
    || warning "Serena install failed — run it later: uv tool install -p 3.13 serena-agent"
fi
if [ -x "$serena_bin" ] && [ -x "$claude_bin" ]; then
  if "$claude_bin" mcp get serena &> /dev/null; then
    echo "Serena MCP server already registered with Claude Code" | indent
  else
    info "🔌 Registering Serena's MCP server with Claude Code…"
    "$claude_bin" mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd | indent \
      || warning "Registering Serena failed — run: claude mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd"
  fi
fi

# Remote documentation MCP servers (HTTP, nothing to install): Astro, Better
# Auth, and Sidero Labs (Talos Linux, Omni; its `siderolabs` skill comes from
# agents/claude-skills.txt via `claude-config restore` below).
# https://docs.siderolabs.com/talos/v1.14/learn-more/ai-agent-integration
if [ -x "$claude_bin" ]; then
  while read -r name url; do
    if "$claude_bin" mcp get "$name" &> /dev/null; then
      echo "$name MCP server already registered with Claude Code" | indent
    else
      info "🔌 Registering the $name MCP server with Claude Code…"
      # stdin is the loop's list: keep claude from reading it
      "$claude_bin" mcp add --scope user --transport http "$name" "$url" < /dev/null | indent \
        || warning "Registering $name failed — run: claude mcp add --scope user --transport http $name $url"
    fi
  done << 'EOF'
astro-docs https://mcp.docs.astro.build/mcp
better-auth https://mcp.better-auth.com/mcp
siderolabs-docs https://docs.siderolabs.com/mcp
EOF
fi

# rtk (Brewfile) — a Claude Code PreToolUse hook that rewrites Bash calls to
# their compact rtk form (`git status` → `rtk git status`). --hook-only: no
# RTK.md or @RTK.md line in ~/.claude/CLAUDE.md. Re-run every time because
# `claude-config` doesn't track hooks; rtk skips it when already present.
# Claude Code only: --codex would write through the ~/.codex/AGENTS.md symlink
# into agents/instructions.md. https://github.com/rtk-ai/rtk#auto-rewrite-hook
if command_exists rtk; then
  info "✂️ Connecting rtk to Claude Code…"
  rtk init -g --hook-only --auto-patch < /dev/null 2>&1 | indent \
    || warning "rtk init failed — run it later: rtk init -g --hook-only"
fi

# PowerShell as a .NET global tool — Microsoft-supported, and uses the official
# dotnet-sdk cask. (The Homebrew `powershell` formula would pull in the
# `dotnet` formula, which takes over /opt/homebrew/bin/dotnet.) Lands in
# ~/.dotnet/tools, which tilde/.zprofile puts on PATH.
# https://learn.microsoft.com/powershell/scripting/install/install-powershell-on-macos
if command_exists dotnet; then
  info "💠 Installing PowerShell (.NET global tool)…"
  if dotnet tool list --global | grep -qi '^powershell[[:space:]]'; then
    dotnet tool update --global PowerShell | indent
  else
    dotnet tool install --global PowerShell | indent
  fi
else
  echo "dotnet not found — skipping PowerShell (install the dotnet-sdk cask first)" | indent
fi

# Aspire HTTPS dev certificate: `aspire run` in a non-interactive session
# creates it without trusting it (macOS can't show the Keychain prompt), so the
# dashboard shows TLS warnings. `aspire certs trust` creates it if missing and
# asks for the login password. The check greps the message rather than trusting
# the exit code (unverified for the untrusted case); a wording change only
# costs a redundant (idempotent) trust run.
if command_exists aspire && command_exists dotnet; then
  if [[ "$(dotnet dev-certs https --check --trust 2>&1)" == *'A trusted certificate was found'* ]]; then
    echo "Aspire HTTPS dev certificate already trusted" | indent
  elif [ -t 0 ]; then
    info "🔐 Trusting the Aspire HTTPS dev certificate (macOS may ask for your password)…"
    aspire certs trust --nologo || warning "aspire certs trust failed — run it later: aspire certs trust"
  else
    echo "[Aspire] HTTPS dev certificate not trusted. Run: ${BOLD}aspire certs trust${RESET}" | indent
  fi
fi

if ! command_exists npm; then
  echo "npm not found — skipping Node.js global config and packages" | indent
  exit 0
fi

# Node.js global config
info "🚀 Configuring npm…"
# Less verbose output
npm config set loglevel warn
# Disable funding messages
npm config set fund false
# Install exact version of packages ("1.2.3" instead of "^1.2.3" or "~1.2.3"). Keeps pinning durable
npm config set save-exact true
# Do not allow installing packages from Git
npm config set allow-git none
# Do not allow installing packages from a file
# npm config set allow-file none
# Do not allow installing packages from remote dependencies (URLs instead of npm registry)
# npm config set allow-remote none
# Only install package versions published at least 7 days ago
npm config set min-release-age 7
# (Bun: the same rules live in tilde/.bunfig.toml)

# Global npm CLIs (serverless, @antfu/ni) are `npm:` tools in the mise config,
# installed by `mise install` above. aws-cdk comes from the Brewfile.

# This repo's own dependencies: `prettier` (+ prettier-plugin-sh) for `pnpm
# format`, and `avif`, which bin/optimize-image expects at node_modules/.bin
if command_exists pnpm; then
  info "📦 Installing this repo's dependencies…"
  pnpm install --dir "$DOTFILES_DIR" | indent
else
  echo "pnpm not found — skipping repo dependencies (run 'pnpm install' later)" | indent
fi

# Last, after the npm settings above (min-release-age, allow-git none) so the
# skills restore's npx runs with them: Claude Code's plugins, base settings and
# user skills from agents/claude-*
# (`claude-config save` refreshes them; restore only adds what's missing and
# never overwrites settings already here), then the catalog of everything
# installed (~/.claude/catalog). claude may not be on PATH yet on a fresh Mac,
# so put its directory first for both.
if [ -x "$claude_bin" ]; then
  info "🧩 Restoring Claude Code plugins, settings and skills…"
  # The private jrmatherly/skills repo (marketplace + coding-standards) is
  # cloned by non-interactive git: Claude Code tries SSH, then HTTPS. On a
  # fresh Mac neither works yet (~/.ssh/config isn't linked until
  # symlinks.sh, nothing stores a GitHub credential), so hand this one
  # command gh's credential helper through the environment. Writing it to
  # ~/.gitconfig.local instead would make symlinks.sh skip git identity
  # setup. (bash 3.2: an empty array under set -u is unbound, hence ${…+…})
  gh_git_env=()
  if command_exists gh && gh auth status &> /dev/null; then
    # The empty first value clears the helper list for github.com, so only gh
    # answers: otherwise git also hands gh's token to Homebrew git's
    # osxkeychain helper on success, and it stays in the keychain
    gh_git_env=(GIT_CONFIG_COUNT=2
      GIT_CONFIG_KEY_0=credential.https://github.com.helper GIT_CONFIG_VALUE_0=
      GIT_CONFIG_KEY_1=credential.https://github.com.helper
      GIT_CONFIG_VALUE_1='!gh auth git-credential')
  fi
  env ${gh_git_env[@]+"${gh_git_env[@]}"} PATH="$(dirname "$claude_bin"):$PATH" "$DOTFILES_DIR/bin/claude-config" restore 2>&1 | indent \
    || warning "Some of it didn't restore — re-run: claude-config restore"
  info "📚 Building the Claude Code catalog…"
  # Its lint lines (stderr) say what's wrong when curated.toml is out of date
  PATH="$(dirname "$claude_bin"):$PATH" "$DOTFILES_DIR/bin/claude-catalog" 2>&1 | indent \
    || warning "Catalog built with problems (listed above) — fix agents/catalog/curated.toml, then run: claude-catalog"
fi
