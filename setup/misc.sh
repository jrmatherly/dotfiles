#!/bin/bash

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd -P)}"
cd "$DOTFILES_DIR"

# Homebrew may not be installed yet (e.g. `setup.sh --skip-brew` on a fresh Mac)
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

BLUE=$(tput setaf 4 2> /dev/null || true)
BOLD=$(tput bold 2> /dev/null || true)
RESET=$(tput sgr0 2> /dev/null || true)

indent() {
  sed 's/^/  /'
}

info() {
  echo
  echo "[ ${BLUE}..${RESET} ] $1" | indent
}

warning() {
  tput setaf 1 2> /dev/null || true
  echo "/!\\ $1 /!\\"
  tput sgr0 2> /dev/null || true
}

command_exists() {
  command -v "$@" &> /dev/null
}

# Ask for the administrator password upfront
warning "Activate sudo"
sudo echo "Sudo activated!"
echo

# Install Xcode Command Line Tools and accept its license
if xcode-select -p 2> /dev/null; then
  :
elif [ ! -t 0 ]; then
  # Headless: the install dialog needs someone to click it, so don't wait
  echo "Xcode Command Line Tools missing; run: xcode-select --install" | indent
else
  xcode-select --install > /dev/null 2>&1 || true
  # At most 30 minutes: a cancelled dialog would otherwise hang the run
  for _ in $(seq 1 360); do
    if xcode-select -p &> /dev/null; then break; fi
    sleep 5
  done
  if ! xcode-select -p 2> /dev/null; then
    warning "Xcode Command Line Tools not installed; later steps may fail; run: xcode-select --install"
  fi
fi

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
    MISE_DISABLE_TOOLS="npm:@colbymchenry/codegraph" mise install | indent || warning "mise install had failures; re-run: mise install"
    mise reshim
  else
    mise install | indent || warning "mise install had failures; re-run: mise install"
  fi
  # typescript-language-server (a Terax preset, an `npm:` tool in the config)
  # finds TypeScript in a project's node_modules or by Node resolution from its
  # own install dir, which walks up to mise's data dir. mise gives every npm
  # tool its own prefix, so link the global `npm:typescript` where that walk
  # finds it. The target path carries the exact version: upup relinks after
  # `mise upgrade`.
  if ts_dir="$(mise where npm:typescript 2> /dev/null)"; then
    mkdir -p "${MISE_DATA_DIR:-$HOME/.local/share/mise}/node_modules"
    ln -sfn "$ts_dir/node_modules/typescript" "${MISE_DATA_DIR:-$HOME/.local/share/mise}/node_modules/typescript"
  else
    warning "npm:typescript is not installed — typescript-language-server will only see a project's own TypeScript"
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

# Rust — Homebrew's rustup (Brewfile) is the system toolchain manager. Make
# stable the default when it isn't: a proxy with no default toolchain downloads
# one on first use, which Hindsight's daemon start runs inside a 10 s
# `cargo --version` check. `rustup default` alone is a local read.
rustup=/opt/homebrew/opt/rustup/bin/rustup
if [ -x "$rustup" ]; then
  if "$rustup" default 2> /dev/null | grep -q '^stable-'; then
    echo "Rust: stable is the default toolchain" | indent
  else
    info "🦀 Installing the stable Rust toolchain with rustup…"
    "$rustup" default stable 2>&1 | indent || warning "rustup default stable failed — run it later"
  fi
  # Rust lived in mise before 2026-10-24. A leftover install keeps rustup and
  # cargo shims ahead of this keg on an activated PATH, and its own rustup in
  # ~/.cargo/bin loops back through the shims (`mise uninstall` and `mise
  # prune` run that rustup, so they hang). Forgetting the install is only
  # mise bookkeeping; the proxies and toolchain are the owner's call.
  mise_rust="${MISE_DATA_DIR:-$HOME/.local/share/mise}/installs/rust"
  if [ -d "$mise_rust" ]; then
    info "🦀 Forgetting mise's rust install so its shims stop shadowing rustup…"
    rm -rf "$mise_rust"
    mise reshim 2>&1 | indent || warning "mise reshim failed — run it later"
  fi
  if [ -x "$HOME/.cargo/bin/rustup" ] && ! cmp -s "$HOME/.cargo/bin/rustup" "$rustup"; then
    warning "\$HOME/.cargo/bin/rustup is not Homebrew's rustup (mise's, probably) — run: rm -rf \$HOME/.cargo/bin \$HOME/.rustup && $rustup default stable"
  fi
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

claude_bin="$(command -v claude || echo "$HOME/.local/bin/claude")"

# Registers a stdio MCP server with Claude Code at user scope, once. A server
# of that name registered with the same command, args and environment is left
# alone; one that differs (a `rea setup` registration, a moved binary, a
# changed env path) gets a warning with the command to re-register, since
# `claude mcp add` refuses to overwrite and a silent keep would hide the drift.
# `claude mcp get` prints indented "Command: …", "Args: …" (bare "Args:" when
# none) and "KEY=value" lines; each is matched as a whole line.
# Usage: register_mcp <name> <label> [-e KEY=VALUE]... -- <command> [args...]
register_mcp() {
  local name="$1" label="$2" existing line i
  shift 2
  local -a env_args=()
  while [ "$1" != "--" ]; do
    env_args+=("$1" "$2")
    shift 2
  done
  shift
  if existing=$("$claude_bin" mcp get "$name" 2> /dev/null); then
    local args="${*:2}"
    local -a expect=("Command: $1" "Args:${args:+ $args}")
    for ((i = 1; i < ${#env_args[@]}; i += 2)); do
      expect+=("${env_args[i]}")
    done
    for line in "${expect[@]}"; do
      if ! sed 's/^ *//' <<< "$existing" | grep -qxF -- "$line"; then
        warning "$label MCP server is registered differently (expected '$line') — re-register: claude mcp remove $name -s user && claude mcp add --scope user $name ${env_args[*]+"${env_args[*]}"} -- $*"
        return 0
      fi
    done
    echo "$label MCP server already registered with Claude Code" | indent
  else
    info "🔌 Registering the $label MCP server with Claude Code…"
    "$claude_bin" mcp add --scope user "$name" ${env_args[@]+"${env_args[@]}"} -- "$@" | indent \
      || warning "Registering $label failed — run: claude mcp add --scope user $name ${env_args[*]+"${env_args[*]}"} -- $*"
  fi
}

# mise's MCP server for Claude Code (user scope — serves whichever project
# Claude runs in): exposes tools, tasks, env and config, and can run tasks.
# Note `mise://env` shows real environment values, secrets included, to the
# agent. https://mise.jdx.dev/mcp.html
if command_exists mise && [ -x "$claude_bin" ]; then
  register_mcp mise mise -- "$(command -v mise)" mcp
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
  register_mcp serena Serena -- serena start-mcp-server --context claude-code --project-from-cwd
fi

# Scrapling — web scraping library with an MCP server (plain, Chromium and
# stealth fetches, sessions, screenshots) and a CLI that the scrapling-official
# skill (agents/claude-skills.txt) drives. A uv tool with the `ai` extra (the
# server plus the browser fetchers; `all` only adds IPython); `bin/upup`
# upgrades it. `scrapling install` downloads Playwright's Chromium once and is
# a no-op after. Registered by absolute path so app-launched Claude Code finds
# it without the shell's PATH. https://scrapling.readthedocs.io/en/latest/ai/mcp-server/
scrapling_bin="$HOME/.local/bin/scrapling"
scrapling_mcp_bin="$HOME/.local/bin/scrapling-mcp"
if command_exists uv && [ ! -x "$scrapling_bin" ]; then
  info "🕷️ Installing Scrapling…"
  uv tool install -p 3.13 "scrapling[ai]" | indent \
    || warning "Scrapling install failed — run it later: uv tool install -p 3.13 'scrapling[ai]'"
fi
if [ -x "$scrapling_bin" ]; then
  "$scrapling_bin" install 2>&1 | indent \
    || warning "Scrapling's browser download failed — run it later: scrapling install"
fi
# The entry point exists even for an install without the `ai` extra, and
# `scrapling-mcp --help` passes there (the server module is imported lazily),
# so import it from the tool's venv before registering a server that would
# die on launch
if [ -x "$scrapling_mcp_bin" ] && [ -x "$claude_bin" ] && command_exists uv; then
  if "$(uv tool dir)/scrapling/bin/python" -c 'import scrapling.core.ai' 2> /dev/null; then
    register_mcp scrapling Scrapling -- "$scrapling_mcp_bin"
  else
    warning "scrapling-mcp can't start (installed without the ai extra?) — reinstall: uv tool install --force -p 3.13 'scrapling[ai]'"
  fi
fi

# Hindsight — per-repo long-term memory for Claude Code and Codex via the vendor
# installer (what it writes: setup/README.md and the spec,
# docs/superpowers/specs/completed/2026-10-24-hindsight-memory.md). Tracked snapshots stay
# clean: `claude-config save` drops `hooks`, and the [mcp_servers] block lands in
# the seeded copy ~/.codex/config.toml. It registers its MCP server with
# `claude mcp add`, hence the PATH prefix. `bin/upup` upgrades it.
if command_exists npx && command_exists uvx && command_exists jq && [ -x "$claude_bin" ]; then
  info "🧠 Setting up Hindsight memory…"
  PATH="$(dirname "$claude_bin"):$PATH" "$DOTFILES_DIR/bin/hindsight-memory" init 2>&1 | indent \
    || warning "Hindsight memory setup failed — run it later: hindsight-memory init"
else
  echo "npx, uvx, jq or claude not found — skipping Hindsight memory" | indent
fi

# REA — reverse-engineering MCP server (`rea-agents`, a mise npm tool) for
# Claude Code, driving the Brewfile's Ghidra formula and Hopper cask. The
# registered command is bin/rea-mcp, which resolves GHIDRA_INSTALL_DIR and
# JAVA_HOME from Homebrew at every launch (the ghidra formula's openjdk@N, the
# JDK Homebrew's own ghidraRun wrapper uses) and execs the mise shim. The
# registration therefore holds no versioned path: a JAVA_HOME pinned here
# dangled when Ghidra 12.2 moved from openjdk@21 to @25 (2026-10-22). Hopper's
# cask path is REA's default launcher. The reverse-engineer-anything skill is
# REA's own bundled copy, installed by `rea setup --skill` into ~/.agents/skills
# and ~/.claude/skills (not the skills CLI's copy from the repo's main branch,
# which drifts from the installed server and makes `rea doctor` call it stale).
# https://github.com/morluto/rea
rea_shim="${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims/rea"
if [ -x "$rea_shim" ]; then
  # The skills CLI linked ~/.claude/skills/<name> into ~/.agents/skills; rea setup
  # refuses to replace a link, so an older install's link goes first
  rea_link="$HOME/.claude/skills/reverse-engineer-anything"
  [ -L "$rea_link" ] && rm "$rea_link"
  mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills"
  "$rea_shim" setup --skill-client shared --skill-client claude_code --skill --yes --format json > /dev/null \
    || warning "REA skill install failed — run it later: rea setup --skill-client shared --skill-client claude_code --skill --yes"
fi
if [ -x "$rea_shim" ] && [ -x "$claude_bin" ] && command_exists brew && [ -d "$(brew --prefix ghidra)/libexec" ]; then
  register_mcp rea REA -- "$DOTFILES_DIR/bin/rea-mcp"
else
  echo "rea shim or the ghidra formula not found — skipping REA's MCP server" | indent
fi

# SnippetsLab (Mac App Store, not in the Brewfile): its `lab` helper gives an
# agent skill (a static copy, so upup refreshes it; no git source, so not in
# agents/claude-skills.txt) and a stdio MCP server, registered with Claude
# Code and Codex. The server launches the app on the first tool call, not at
# the handshake (measured), so no --no-launch. Write access for create_snippet
# is the app's own setting (Settings > Integrations).
# https://www.renfei.org/snippets-lab/manual/mac/agentic-tools.html
snippetslab_lab="/Applications/SnippetsLab.app/Contents/Helpers/lab"
if [ -x "$snippetslab_lab" ]; then
  info "📎 Setting up SnippetsLab's agent skill and MCP server…"
  "$DOTFILES_DIR/bin/install-snippetslab-skill" 2>&1 | indent \
    || warning "SnippetsLab skill not written — run it later: install-snippetslab-skill"
  if [ -x "$claude_bin" ]; then
    register_mcp snippetslab SnippetsLab -- "$snippetslab_lab" mcp
  fi
  # `codex mcp get` prints "command: …" and "args: …" lines; compare them the
  # way register_mcp does for Claude Code, so a registration pasted from the
  # app's own setup (another path or args) is reported, not silently kept.
  if command_exists codex; then
    if codex_existing="$(codex mcp get snippetslab 2> /dev/null)"; then
      if grep -qF "command: $snippetslab_lab" <<< "$codex_existing" && grep -qF "args: mcp" <<< "$codex_existing"; then
        echo "SnippetsLab MCP server already registered with Codex" | indent
      else
        warning "SnippetsLab MCP server is registered differently with Codex — re-register: codex mcp remove snippetslab && codex mcp add snippetslab -- $snippetslab_lab mcp"
      fi
    else
      codex mcp add snippetslab -- "$snippetslab_lab" mcp | indent \
        || warning "Registering SnippetsLab with Codex failed — run: codex mcp add snippetslab -- $snippetslab_lab mcp"
    fi
  fi
fi

# Remote documentation MCP servers (HTTP, nothing to install): Astro, Better
# Auth, and Sidero Labs (Talos Linux, Omni; its `siderolabs` skill comes from
# agents/claude-skills.txt via `claude-config restore` below).
# https://docs.siderolabs.com/talos/v1.14/learn-more/ai-agent-integration
if [ -x "$claude_bin" ]; then
  while read -r name url; do
    if existing=$("$claude_bin" mcp get "$name" 2> /dev/null); then
      if grep -qF "$url" <<< "$existing"; then
        echo "$name MCP server already registered with Claude Code" | indent
      else
        warning "$name MCP server is registered with a different URL — expected $url"
      fi
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

# Supabase CLI (Brewfile) — persisted telemetry opt-out, for runs that don't
# inherit DO_NOT_TRACK from zsh/env.zsh (GUI-launched tools, scripts). The
# variable here keeps this call itself from reporting.
if command_exists supabase; then
  DO_NOT_TRACK=1 supabase telemetry disable < /dev/null 2>&1 | indent \
    || warning "supabase telemetry disable failed — run it later"
fi

# PowerShell as a .NET global tool — Microsoft-supported, and uses the official
# dotnet-sdk cask. (The Homebrew `powershell` formula would pull in the
# `dotnet` formula, which takes over /opt/homebrew/bin/dotnet.) Lands in
# ~/.dotnet/tools, which tilde/.zprofile puts on PATH.
# https://learn.microsoft.com/powershell/scripting/install/install-powershell-on-macos
if command_exists dotnet; then
  info "💠 Installing PowerShell (.NET global tool)…"
  if dotnet tool list --global | grep -qi '^powershell[[:space:]]'; then
    dotnet tool update --global PowerShell | indent || warning "PowerShell install failed; re-run: dotnet tool install --global PowerShell"
  else
    dotnet tool install --global PowerShell | indent || warning "PowerShell install failed; re-run: dotnet tool install --global PowerShell"
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

# Without npm only the npm config and the repo's dependencies are skipped;
# the Claude Code restore below still runs
if command_exists npm; then
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
    pnpm install --dir "$DOTFILES_DIR" | indent || warning "pnpm install failed; re-run: pnpm install"
  else
    echo "pnpm not found — skipping repo dependencies (run 'pnpm install' later)" | indent
  fi
else
  echo "npm not found; skipping npm config and repo dependencies" | indent
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
  PATH="$(dirname "$claude_bin"):$PATH" "$DOTFILES_DIR/bin/claude-config" restore 2>&1 | indent \
    || warning "Some of it didn't restore — re-run: claude-config restore"
  info "📚 Building the Claude Code catalog…"
  # Its lint lines (stderr) say what's wrong when curated.toml is out of date
  PATH="$(dirname "$claude_bin"):$PATH" "$DOTFILES_DIR/bin/claude-catalog" 2>&1 | indent \
    || warning "Catalog built with problems (listed above) — fix agents/catalog/curated.toml, then run: claude-catalog"
fi
