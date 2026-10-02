# Setup Scripts

## setup.sh (orchestrator)

![setup.sh runtime: the step scripts, what they fetch from the internet, what runs as root, and what lands in $HOME](bootstrap-runtime.svg)

The diagram is generated with [Archify](https://github.com/tt-a1i/archify) from [`bootstrap-runtime.archify.json`](bootstrap-runtime.archify.json), whose source line references are pinned to a commit. When the step order, sudo use or download sources change, update that file, re-run `archify finalize` and re-export the SVG.

`../setup.sh` runs these in order: **brew → zsh → misc → symlinks** (plus `dash` with `--dash`). Flags: `-y/--yes`, `--skip-brew`, `--skip-codegraph`, `--dash`, `-h/--help` — see the table in the [main README](../README.md#automatically).

It resolves its own location, so the repo can live anywhere; it creates a `~/dotfiles` symlink to the clone for configs that can't expand variables, and keeps the sudo timestamp alive so long installs don't re-prompt. If `/etc/pam.d/sudo_local` doesn't exist, it creates it to enable Touch ID for `sudo`. It does **not** touch `~/.zshrc` itself — that goes through `symlinks.sh`'s skip/overwrite/backup prompt like every other file.

When run from a terminal, it records the whole run (prompts included) to `private/setup-logs/<timestamp>.log`, which is git-ignored, by re-running itself under macOS `script`. `/validate-setup after` reads the newest log, so there's no need to paste output.

`macos.sh` is deliberately not part of the run; use `set-defaults`.

## brew

Installs Homebrew (if missing), then packages, applications and VS Code extensions from the [Brewfile](./Brewfile).

Runs through [`bin/brewpick --all`](../bin/brewpick), which strips the Brewfile's `manual` entries (paid downloads with no cask, e.g. the MonoLisa font) before handing it to `brew bundle` — passing the file straight to `brew bundle` fails with `Invalid Brewfile: undefined method 'manual'`. To pick a subset interactively via fzf instead, run `bin/brewpick`.

If an app from the Brewfile is already installed outside Homebrew (downloaded from its website), hand it over first with `brew install --cask --adopt <name>` — otherwise `brew bundle` stops at "It seems there is already an App at …". For casks that update themselves (`auto_updates`, e.g. Comet), `--adopt` keeps the installed copy as-is even when it's newer than the cask.

`brew bundle` upgrades outdated dependencies by default, so there's no separate `brew upgrade`. Pass `--skip-brew` to `setup.sh` to skip this step when re-running for dotfiles changes only. It finishes with `brew cleanup --prune=all`.

Optional-app suggestions (printed at the end, never installed) live in three empty arrays at the end of `brew.sh` — `OPTIONAL_CASKS`, `OPTIONAL_LINKS` (`"Name|https://…"`) and `APP_STORE_LINKS`. Add entries to bring the list back; each section only prints when it has items.

**Tap trust:** Homebrew requires explicit trust before it loads anything from a third-party tap ([docs](https://docs.brew.sh/Tap-Trust)). That's the default in current Homebrew, so no environment variable is needed: the old `HOMEBREW_REQUIRE_TAP_TRUST` opt-in is deprecated and only makes `brew bundle` print a warning. Every package that comes from a tap is fully qualified in the Brewfile and marked `trusted: true` individually — narrower than trusting whole taps, which would also cover anything those taps publish later. The one extra is the `azure/functions` tap line, which also trusts the unversioned `azure-functions-core-tools`: Homebrew _loads_ (never installs) a versioned formula's unversioned sibling when linking `azure-functions-core-tools@4`. When adding a tap package, fully qualify it and add `trusted: true`, or `brew bundle` skips it with "Refusing to load … from untrusted tap".

`brew bundle` also warns that the `verified` parameter in the `url` stanza is deprecated, for `microsoft/aspire/aspire`. That comes from Microsoft's cask in their tap (`aspire` isn't in Homebrew's official catalogue), not from this repo, and it's harmless until they update it.

**.NET / PowerShell:** the Brewfile uses Microsoft's `dotnet-sdk` cask. Don't add the `dotnet` or `powershell` formulae — `powershell` depends on `dotnet`, and that formula takes over `/opt/homebrew/bin/dotnet`. PowerShell is installed as a .NET global tool by `misc.sh` instead.

## zsh

Registers Homebrew's Zsh (installed by the Brewfile) in `/etc/shells` and makes it your login shell with `chsh`. Does nothing if you're already using it.

## misc

- Installs the Xcode Command Line Tools if missing and makes the scripts in `bin/` executable.
- Installs the [Iosevka Code](https://github.com/amnweb/Iosevka-Code) Nerd Font (VS Code's font, no Homebrew cask) into `~/Library/Fonts` with [`bin/install-iosevka-code`](../bin/install-iosevka-code). Unlike the rest of setup it also updates: if the upstream release zip changed since the last install, it's reinstalled (see [fonts](../fonts/README.md)). A failed download warns and setup carries on.
- If the GitHub CLI isn't authenticated, offers to run `gh auth login`. gh keeps the token in the macOS keychain; `~/.config/gh/hosts.yml` is gitignored anyway, since gh falls back to storing the token there in plain text when no keychain is available.
- Installs runtimes and CLIs with [mise](https://mise.jdx.dev/) from the tracked global config [`tilde/.config/mise/config.toml`](../tilde/.config/mise/config.toml). The script links that config into `~/.config/mise` and runs `mise install` before touching npm. When a tool lists several versions, mise installs all of them and the first is the default on PATH:
  - Node `24` (Active LTS, pinned rather than the moving `lts` alias), plus `22` and `26`.
  - Python `3.14`, plus `3.11`–`3.13` and the `3.15` release candidate. Every version's `python3.x` is on PATH.
  - `npm:typescript` (major 6), for a global `tsc`.
  - `npm:@colbymchenry/codegraph` ([CodeGraph](https://github.com/colbymchenry/codegraph)), tracking `latest`. Upgrade it with `mise upgrade`, not `codegraph upgrade`.
  - `npm:serverless` (major 4) and `npm:@antfu/ni` (major 30): global npm CLIs installed by mise instead of `npm install -g`.
  - [Bun](https://bun.com) (`latest`), which runs the jstack plugin's `j-mode` scripts from the private skills repo.

  The config also sets `idiomatic_version_file_enable_tools = ["node", "python"]`, which is off by default in mise. It makes mise honour `.nvmrc`/`.node-version` (like fnm and nvm) and `.python-version` (like pyenv and uv). This repo's own `.nvmrc` (`lts/*`) and `bin/nnn` both rely on this setting.

- Installs [Claude Code](https://docs.claude.com/en/docs/claude-code/setup) with Anthropic's native installer (`curl -fsSL https://claude.ai/install.sh | bash`) into `~/.local/bin`, which `zsh/path.zsh` puts on PATH. It's skipped when `claude` already exists, since the native install updates itself. The Brewfile's `anthropic.claude-code` is only the VS Code extension.
- Connects CodeGraph to Claude Code with `codegraph install --yes --target claude --location global`. This writes the MCP server to `~/.claude.json` (user scope), the `mcp__codegraph__*` permission and a `UserPromptSubmit` hook to `~/.claude/settings.json`, and a marker-fenced block to `~/.claude/CLAUDE.md`. Re-running updates the entries in place instead of duplicating them. Because the installer also rewrites `~/.claude/CLAUDE.md` by renaming a new copy over it, that file isn't tracked; global Claude instructions live in `tilde/.claude/rules/` instead. The step targets Claude Code only on purpose: the installer replaces files by writing a new copy and renaming it over the old one, so running it for Codex would turn the `~/.codex/AGENTS.md` symlink into a regular file. To add another agent, run `codegraph install --target <id>`, but only for agents whose config isn't symlinked into this repo. It then runs `codegraph telemetry off`, which persists the opt-out for agents launched outside a shell (`CODEGRAPH_TELEMETRY=0` in `zsh/env.zsh` covers shells). Indexing a project is still a manual step: `codegraph init` in that repo. Pass `--skip-codegraph` to `setup.sh` (or set `DOTFILES_SKIP_CODEGRAPH=true`) to skip both the mise install and this step. Neither removes an existing install: use `codegraph uninstall` for that.
- Registers [mise's MCP server](https://mise.jdx.dev/mcp.html) with Claude Code at user scope (`claude mcp add --scope user mise -e MISE_EXPERIMENTAL=1 -- "$(command -v mise)" mcp`, i.e. the absolute path to mise). It's skipped if a server named `mise` is already registered. The server lets the agent list mise tools, tasks, env and config, and run tasks. Its `mise://env` resource shows real environment values to the agent, secrets included.
- Installs [Serena](https://github.com/oraios/serena) with `uv tool install -p 3.13 serena-agent` if missing, and registers it with Claude Code at user scope (`serena start-mcp-server --context claude-code --project-from-cwd`) unless a `serena` server exists. Its bash language server only sees `*.sh`/`*.bash` files, so in this repo the extensionless `bin/` scripts are edited with the normal tools (`.claude/rules/code-navigation.md`).
- Connects [rtk](https://github.com/rtk-ai/rtk) (from the Brewfile) to Claude Code with `rtk init -g --hook-only --auto-patch`: a `PreToolUse` hook in `~/.claude/settings.json` that rewrites Bash calls to their compact form (`git status` → `rtk git status`, `cat` → `rtk read`, which is byte-exact by default). It runs every time because `claude-config` leaves hooks out of `agents/claude-settings.json`; rtk skips the entry when it's already there. `--hook-only` keeps it from adding `RTK.md` and an `@RTK.md` line to `~/.claude/CLAUDE.md`. Codex isn't wired up: `rtk init --codex` would write through the `~/.codex/AGENTS.md` symlink into `agents/instructions.md`. Its config (`~/Library/Application Support/rtk/config.toml`, e.g. `[hooks] exclude_commands`) isn't tracked. Remove it with `rtk init -g --uninstall`. `rtk gain` shows the savings.
- Restores Claude Code's plugins, base settings and user skills with `claude-config restore` (see [agents/README.md](../agents/README.md#claude-code-plugins-settings-skills-and-catalog)): missing marketplaces and plugins are installed, [`agents/claude-settings.json`](../agents/claude-settings.json) is merged into `~/.claude/settings.json` without overwriting what's there, and missing skills are added with `npx skills add`. Then builds the catalog of installed skills, agents and MCP servers with `claude-catalog` (`~/.claude/catalog/`). Both warn instead of failing; re-run them by name.
- Installs or updates PowerShell as a .NET global tool (`dotnet tool install --global PowerShell`) in `~/.dotnet/tools`, which `tilde/.zprofile` puts on PATH.
- If the Aspire HTTPS dev certificate isn't trusted yet (checked with `dotnet dev-certs https --check --trust`), runs `aspire certs trust`, which creates the certificate if needed (macOS may ask for your password). Without it, `aspire run` in a non-interactive session creates the certificate untrusted and the dashboard shows TLS warnings. Without a terminal it only prints the command. To start over: `aspire certs clean`, then `aspire certs trust`.
- Sets strict npm defaults (`save-exact`, `allow-git none`, `min-release-age 7`, quieter logs, no funding messages). Bun gets the same two install rules from the tracked `tilde/.bunfig.toml` (`exact`, `minimumReleaseAge` 7 days), linked to `~/.bunfig.toml`. Global npm CLIs (`serverless`, `@antfu/ni`) aren't `npm install -g`'d: they're `npm:` tools in the mise config, installed with everything else by `mise install`, so they survive switching the default Node. (aws-cdk comes from the Brewfile.)
- Runs `pnpm install` for this repo's own dependencies: Prettier for `pnpm format`, and `avif`, which `bin/optimize-image` uses.

## symlinks

Links `tilde/` into your home directory: each dotfile and folder becomes a symlink (e.g. `~/.zshrc`, `~/.gitconfig`), and each item under `tilde/.config/` is linked individually into `~/.config/`. Claude Code's global instructions are the rules in `tilde/.claude/rules/`: each one is linked into `~/.claude/rules/`, which stays a real directory so machine-local rules can sit next to them (an older whole-directory link is migrated). Top-level files in `tilde/.claude/`, such as the status line script `statusline-command.sh`, are linked into `~/.claude/` the same way. `~/.claude/CLAUDE.md` (rewritten by `codegraph install`), `~/.claude/settings.json` (rewritten by Claude Code and plugins) and `~/.claude.json` (auth and machine state) aren't tracked. `tilde/.codex` and `tilde/.ssh` are handled separately. Every existing file prompts for skip/overwrite/backup, and anything unanswered is skipped.

`~/.ssh` is always a real directory (created with `700` permissions if missing); only the tracked `config` is linked into it, so no prompt can ever touch key files. Older setups that linked the whole directory are migrated automatically, moving anything ssh wrote through the link (e.g. `known_hosts`) back into `~/.ssh`. It warns if `~/.ssh/github_personal.pub` — the public key that pins GitHub to your 1Password key — is missing.

Then it runs `configure_git_identity`, which prompts for your git name/email and signing method and writes `~/.gitconfig.local` (never committed — see `tilde/.gitconfig`'s `[include]`). SSH signing means 1Password: it writes `gpg.ssh.program = /Applications/1Password.app/Contents/MacOS/op-ssh-sign` and asks for your public key; GPG asks for a key ID. The whole step is skipped if `~/.gitconfig.local` already exists. `DOTFILES_GIT_NAME`, `DOTFILES_GIT_EMAIL`, `DOTFILES_GIT_SIGN_METHOD` and `DOTFILES_GIT_SIGNINGKEY` pre-fill (and skip) their own prompts; without a name and email the file isn't written.

It also links:

- `vscode/User` → `~/Library/Application Support/Code/User`. The repo is the source of truth, so keep VS Code's built-in Settings Sync off (its `vscode/**/sync/` cache and `vscode/**/profiles/` are gitignored).
- lazydocker's config, `~/.gnupg/gpg-agent.conf`, the QuickLook plugins (`~/Library/QuickLook`), and Codex's `~/.codex/AGENTS.md` and `config.toml`.
- The `cot` and `code` command-line tools into `/usr/local/bin` if they're not already on PATH.
- The Firefox Developer Edition styles, hard-linked into its profile — skipped with a warning if there's no dev-edition profile. The same goes for the CotEditor/VS Code CLIs when those apps aren't installed.

lazygit's `state.yml` is machine-local and not linked. Finally it rebuilds bat's cache so the themes in `tilde/.config/bat/themes` load.

## macos

Sane macOS defaults, run with `set-defaults`. Based on [~/.macos](https://mths.be/macos) by @mathiasbynens, reviewed for macOS 27.

Prompts for a computer name/local hostname (skippable) so the same script works unmodified across machines. Pre-set `COMPUTERNAME`/`LOCALHOSTNAME` env vars to skip the prompt in non-interactive runs.

A handful of higher-impact/opinionated settings are asked about interactively rather than applied unconditionally, since the right answer varies per machine (e.g. a work laptop with firewall/updates managed by MDM). Defaults in brackets:

- Disable the "downloaded from the internet" confirmation for new apps **[N]** — weakens security
- Skip disk image (.dmg) verification **[N]** — weakens security
- Custom screenshot preferences (Desktop, PNG, no shadow, cursor, named "Shot") [Y]
- Custom Dock auto-hide timing [N] — if yes, asks for the reveal delay (0.2 s) and slide animation (0 s); if no, both are left at macOS defaults
- HiDPI display modes [N], firewall + stealth mode [N]
- Suppress Time Machine's new-disk prompt [Y]; disable Time Machine entirely **[N]**
- TextEdit plain text + UTF-8 [Y]; automatic Software Update [Y]

Non-interactive runs use the defaults above. `DOTFILES_MACOS_NO=1` answers every prompt no. **`DOTFILES_MACOS_YES=1` answers every prompt yes — including the two security-weakening ones and disabling Time Machine**, so avoid it unless that's really what you want.

Applied unconditionally:

- Keyboard: very fast key repeat (1 / 10, beyond System Settings' fastest) with press-and-hold off; system-wide autocorrect and smart punctuation off.
- Trackpad: no swipe between pages (natural scrolling is left alone).
- Dock: auto-hide, size 38, no recent apps, "suck" minimize into the app icon, no bouncing; Mission Control groups windows by app.
- Finder: hidden files, extensions, path and status bars, list view, drive icons and Stacks on the desktop, new windows open in your home folder; `~/Library` and `/Volumes` unhidden; no `.DS_Store` files on network/USB drives.
- All hot corners set to no action; ⌘Space freed from Spotlight (for Raycast).
- Language and region: en-US, USD, inches, °F.
- Energy (`pmset`): lid wake on, disk sleep 10 min, no wake for network access, hibernation mode 3.
- Crash-reporter dialog off; Terminal.app uses UTF-8 and Secure Keyboard Entry.

Safari isn't configured — it's sandboxed, so its preferences can't be set from a script; use Safari → Settings. At the end the script force-quits Finder, Dock, Messages, Activity Monitor, Notification Center, SystemUIServer and Terminal (so run it from another terminal app), and key repeat needs a logout to take effect.

## dash

Optional, interactive: adds Dash docsets generated from local folders of **HTML** documentation (Dash's Docset Generator doesn't read Markdown). Docsets you download inside Dash need nothing from this — Dash syncs that list itself.

Prerequisite: in Dash → Settings → General, set the sync folder to the repo's `dash/` folder and tick all four "What to sync" options (General settings, View options, Docsets/search profiles/keywords, Bookmarks and web searches) — but not "Sync Snippets", which would move Dash's snippet database into the repo.

Dash writes absolute paths and has no variable expansion, so folder docsets can't be committed portably — quit Dash, run `setup/dash.sh` (or `setup.sh --dash`) and enter the folders to index, then build them in Dash → Settings → Downloads → Docset Generator. Also usable non-interactively: `setup/dash.sh add <folder> [name] [keyword]`.
