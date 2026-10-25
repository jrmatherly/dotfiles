# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

<!-- AUTO-MANAGED: project-description -->

## Overview

Personal macOS dotfiles for Apple Silicon (Homebrew at `/opt/homebrew`, Homebrew zsh as login shell); a personalized fork of nicksp/dotfiles.

- No application code: bash setup scripts, `bin/` CLI scripts, zsh config, and app config files.
- The repo is the source of truth. Everything is symlinked into `$HOME` and configured by editing files in the clone.
- Covers Homebrew packages (`setup/Brewfile`), runtimes via mise, macOS defaults, VS Code, Ghostty/cmux, Obsidian, Firefox, and coding-agent config (Claude Code, Amp, Codex).
- Squirrelsong color theme files for many apps are owned by the repo.

<!-- END AUTO-MANAGED -->

<!-- AUTO-MANAGED: build-commands -->

## Build & Development Commands

There is no build. `pnpm check` is the gate. Its tests are the self-checks and tree checks listed below, and it exports `LC_ALL=en_US.UTF-8` because they grep for UTF-8 glyphs.

- `pnpm check` (`bin/lib/check`) runs:
  - `bash -n` on `setup.sh`, `setup/*.sh`, `setup/tests/*.sh`, `vscode/*.sh`, `bin/lib/test-*`, `.claude/hooks/*.sh`, `.claude/skills/*/*.sh`, `raycast/*/*.sh`, `tilde/.claude/*.sh`, `tilde/.bash_profile`, and `bin/*` scripts with a bash/sh shebang
  - `zsh -n` on `tilde/.zshenv`, `tilde/.zprofile`, `tilde/.zshrc`, `zsh/*.zsh`
  - `shellcheck --severity=warning` on the same bash scripts except `tilde/.bash_profile`, which only gets `bash -n` (`.shellcheckrc` also enables `check-unassigned-uppercase`)
  - `agents/catalog/test_build_catalog.py` (status/cleanup rules of the Claude Code catalog generator), through `mise exec python --` when mise exists because `tomllib` needs Python 3.11+
  - `setup/tests/codex-config.sh` (`~/.codex/config.toml` is seeded as a copy, never linked), `bin/lib/test-upup` (the update report against stubbed tools), `bin/lib/test-rea-mcp` (the REA launcher against a stubbed brew, a fixture Ghidra keg and a fake mise shim), `bin/lib/test-hindsight-memory` (the Hindsight wrapper under a temp `HOME`, the vendor installer stubbed), `bin/lib/test-claude-desktop-account` (the account switcher against a fixture Desktop folder, with `pgrep`/`osascript`/`pkill`/`open`/`fzf`/`security`/`curl` stubbed on PATH) and the four Claude Code hook self-checks (`.claude/hooks/test-lint-edited.sh`, `.claude/hooks/test-lint-bash-edits.sh`, `.claude/hooks/test-commit-gate.sh`, `.claude/hooks/test-auditor-readonly.sh`, against sample payloads)
  - `bin/lib/test-conventions` (tree invariants: every `setup.sh` telemetry export is also in `zsh/env.zsh`, Prettier ignores every zsh file, every `bin/` script has a header comment on line 2, every third-party Brewfile formula or cask carries `trusted: true`)
  - `brew bundle list` on `setup/Brewfile` with `manual` lines stripped (parse check, skipped without `brew`)
  - `vscode/test-vscode-settings.sh` (the renderer's tests) and a Prettier check of every VS Code preset's render (skipped without `minijinja-cli`)
  - `prettier --check` over js/cjs/ts/md/json/sh, `.github/**/*.yml` and `bin/*` (not all YAML: app-written configs like `tilde/.config/gh/config.yml` aren't Prettier-clean)
- `pnpm format`: prettier `--write` over the same globs.
- Renovate (Mend app, `renovate.json`) opens update PRs for `package.json` and the global mise config's single-version tools (`node`/`python` are disabled: its mise manager reads only a list's first entry); the `check` workflow (`.github/workflows/check.yml`) runs `pnpm check` on macOS for every PR and push to `main`, its PRs included. Keep its `minimumReleaseAge` in step with `pnpm-workspace.yaml`'s, and add an `allowedVersions` rule when a mise comment holds a tool back a major (as for `npm:typescript`).
- `.prettierignore` also lists zsh files (VS Code's format-on-save runs Prettier's shell plugin, which reads zsh as bash and rewrote `${keys[Ctrl+K]}`); add any new zsh file not ending in `.zsh` there. It skips files that tools rewrite themselves: any `CLAUDE.md`, `.serena/`, `.claude/auto-memory/`, `.claude/settings.local.json`, `docs/superpowers/`, `.superpowers/`, `tilde/.claude/rules/jstack-models.md` (rewritten whole by `/jstack:setup-jstack`), plus the git-ignored `private/` and `logs/`. Don't hand-format them.
- One file: `bash -n <file> && shellcheck --severity=warning <file> && prettier --check <file>`.
- `./setup.sh --skip-brew`: re-apply the dotfiles on this machine. It's interactive. Add `--skip-codegraph` to leave CodeGraph alone; drop `--skip-brew` to also install the Brewfile. Other flags: `-y`, `--dash`, `-h`. From a terminal it logs each run to `private/setup-logs/<timestamp>.log` (via `script`), which `/validate-setup after` reads.
- `./setup/symlinks.sh`: re-link only.
- `upup`: prints one status line per step (ok, changed, notice, fail) and a final summary of changes, notices, failures and actions, with each run's full output in the git-ignored `logs/upup-<timestamp>.log`; self-check `bin/lib/test-upup`. It upgrades macOS, Homebrew, mise tools, uv tools (Serena, Scrapling), the Iosevka Code font, the tracked agent skills (`claude-config restore skills --update`), the Claude Code marketplaces and plugins (`claude plugin marketplace update`, then `claude plugin update` per installed plugin) and Amp (only if `amp` is installed; it's installed by hand). `brew upgrade` runs with `--yes` (Homebrew asks by default). A macOS update makes `softwareupdate` ask for the login password (Apple Silicon owner authorization; sudo/Touch ID don't count): optional `DOTFILES_MAC_PASSWORD_OP` (a 1Password secret reference, set in `~/.zsh.local`) feeds it via `op read` and `--stdinpass`, falling back to the prompt. It lists macOS updates first and skips the install when none, and a failed dotfiles pull only warns. `setup.sh` only installs what's missing and never upgrades, except that font: `bin/install-iosevka-code` (VS Code's font, no cask; run by `setup/misc.sh` and `upup`) reinstalls it whenever the upstream zip changed (ETag check; `REVIEWED_SHA256` in the script only triggers a notice).
- `help <bin-script>`: renders a script's header. Use it to verify new or edited `bin/` scripts.

<!-- END AUTO-MANAGED -->

<!-- AUTO-MANAGED: architecture -->

## Architecture

```text
setup.sh          orchestrator → setup/{brew,zsh,misc,symlinks}.sh (+ dash.sh with --dash)
setup/            Brewfile, per-step scripts, macos.sh (defaults), README.md (per-script docs)
tilde/            mirrors $HOME (dotfiles, .config/*, .codex, .ssh/config)
zsh/              sourced by tilde/.zshrc
bin/              CLI scripts on PATH (see bin/CLAUDE.md); bin/lib/ helpers also on PATH
docs/             alias index + docs/gui/<app>.md cheat sheets (rendered by `help`); docs/superpowers/plans/ = open implementation plans (not applied yet); move each to plans/completed/ once fully implemented; docs/superpowers/specs/ = the assessments and designs those plans argue from; a spec moves to specs/completed/ when every plan built on it is completed (a spec with no plan, when its "built" or decision section records the work as shipped)
vscode/User/      whole dir symlinked to ~/Library/Application Support/Code/User
.github/          workflows/check.yml = `pnpm check` on macOS for PRs and pushes to main
agents/           instructions.md → Amp/Codex AGENTS.md; catalog/ = generator for `bin/claude-catalog`
obsidian/ firefox/ mole/ colors/ etc.     app config + repo-owned themes
ql-plugins/ icons/                         vendored binaries, don't edit
```

- **Setup order**: `brew.sh` must run first because the later scripts use Homebrew tools. `misc.sh` covers Xcode CLT, `chmod +x` on everything in `bin/` except `*.md` (so `bin/CLAUDE.md` stays non-executable), `gh` auth, mise tools (then a `<mise data dir>/node_modules/typescript` link to the global `npm:typescript`, so Terax's `typescript-language-server` finds TypeScript outside projects; `upup` relinks it), the stable Rust toolchain as rustup's default (`rustup default stable` when `rustup default` doesn't already say so; `upup` runs `rustup update`), Claude Code + CodeGraph + the mise MCP server, Serena (`uv tool install -p 3.13 serena-agent`, registered user-scope with Claude Code if missing), Scrapling (`uv tool install -p 3.13 "scrapling[ai]"`, `scrapling install` for its Chromium, `scrapling-mcp` registered user-scope by absolute path), Hindsight memory (`bin/hindsight-memory init`, the pinned vendor installer that wires hooks into Claude Code and Codex), REA (`rea-agents` from mise, registered user-scope as `bin/rea-mcp`, which resolves the Homebrew Ghidra and JDK paths at each launch and execs the mise shim's `mcp`), SnippetsLab's skill and MCP server when the App Store app is present (skill regenerated by `upup`), the rtk Claude Code hook (`rtk init -g --hook-only --auto-patch`), the Supabase CLI's persisted telemetry opt-out (`supabase telemetry disable`), PowerShell, `aspire certs trust` for the Aspire HTTPS dev cert (no y/N prompt, macOS may ask for the password; skipped when already trusted, only a hint when non-interactive), npm config (`min-release-age`, `allow-git none`) and, last, the Claude Code restore + catalog (so `npx skills` runs with those npm settings). `setup.sh` also does things the manual path skips: Touch ID for sudo (`/etc/pam.d/sudo_local`), a sudo keep-alive loop, and telemetry opt-out exports.
- **Symlinking**: `setup/symlinks.sh` links each top-level item of `tilde/` into `~`, and each child of `tilde/.config/` individually (it holds app-written state next to tracked files). `tilde/.claude` is special-cased: `~/.claude/rules` stays a real directory and each tracked `tilde/.claude/rules/*.md` is symlinked into it individually, so machine-local rules can sit alongside (an older whole-directory link is migrated); top-level files in `tilde/.claude` (e.g. `statusline-command.sh`) are linked into `~/.claude` too. `.codex` and `.ssh` are excluded and handled specially: only `.ssh/config` is linked. `tilde/README.md` itself is not linked. Targets outside `$HOME` (VS Code `User`, lazydocker, gpg, `ql-plugins`, Firefox `user.js` as a hard link) need an explicit `symlink_file` call. So do Mole's two whitelists (`install_mole_config`): `mole/<name>` or, when present, the gitignored `mole/<name>.local` is linked as `~/.config/mole/<name>` (Mole writes other files in that folder), and a link to the other candidate is replaced without a prompt. `symlink_file` never overwrites silently; it prompts skip/overwrite/backup.
- **Forking**: the repo is public and cloned over HTTPS (no `gh` login needed). `README.md`'s "Make it yours" table lists the files hard-coded to the owner (clone URL, fastfetch, lazygit `authorColors`, `agents/claude-*`, `curated.toml`, Brewfile, LICENSE); update it when adding another owner-specific value.
- **Repo location**: never assumed. Scripts resolve it themselves. Shells get `$DOTFILES` from `tilde/.zshenv`. `~/dotfiles` is only a compatibility symlink for configs that can't expand variables (e.g. lazygit `shellFunctionsFile`).
- **zsh load order** (`tilde/.zshrc`): `path` → `env` → `options` → `aliases` → `completion` → `key-bindings` → plugins → `init.zsh` (mise activate, Homebrew zsh plugins, fast-theme) → `~/.zsh.local`. `tilde/.zprofile` activates mise shims for GUI apps. When `CLAUDECODE` is set (agent shells), `zsh/aliases.zsh` drops the built-in overrides (`cat`→bat, `ls`→eza, `find`→fd, `-i` cp/mv/rm, `grep -i`, …) and `zsh/options.zsh` turns `clobber` back on and autocorrect off.
- **Runtimes**: mise, via the global `tilde/.config/mise/config.toml`. Several Node/Python versions are installed; the first listed is the default. Global npm CLIs are mise `npm:` tools, never `npm -g` (the common spellings are denied by a user-settings permission rule, tracked in `agents/claude-settings.json`). Don't rely on Homebrew's Python. Rust is the one runtime outside mise: Homebrew's keg-only `rustup` is the system toolchain manager (PATH order explained in `zsh/path.zsh`), and a project that pins another version uses mise's rust backend, which reuses that rustup; a global mise `rust` entry would override a project's `rust-toolchain.toml`, so none is declared. `idiomatic_version_file_enable_tools` makes mise honor `.nvmrc`/`.python-version`.
- **Help system**: `help` shows `docs/README.md`. `help <script>` goes through `bin/lib/get-tldr-md`, which renders the first comment block of `bin/<script>` as a tldr page. `help gui/<app>` renders `docs/gui/<app>.md` with bat.
- **Machine-local config** lives outside the repo: `~/.gitconfig.local` (identity and signing, written by `symlinks.sh`), `~/.ssh/config.local`, `~/.zsh.local`, `~/.ssh/github_personal.pub` (1Password SSH agent). Anything tools append to `~/.gitconfig` (a repo symlink) belongs in `.local`. The one in-repo exception is `mole/*.local` (gitignored, kept next to the shared file it replaces); a re-clone loses it.
- **Agents**: `agents/instructions.md` is linked as `~/.config/amp/AGENTS.md` and `~/.codex/AGENTS.md`, but not as Claude's `CLAUDE.md`. `tilde/.codex/config.toml` is copied (never linked) into `~/.codex/config.toml` when missing: NotchBar (`[features] codex_hooks`) and Jean (`[mcp_servers]` with a token) rewrite the live file, and later setup runs only warn about tracked lines it lacks. CodeGraph config is `codegraph.json`; the `.codegraph/` index is per-machine and gitignored. Serena project config is in `.serena/`; its memories are only a pointer to the `CLAUDE.md` files. Serena's bash language server sees only `*.sh`/`*.bash` files, so extensionless `bin/` scripts, `zsh/*.zsh` and configs need native Read/Edit.
- **Path-scoped rules**: `.claude/rules/` holds rules that load when matching files are touched (`setup.md`, `telemetry-sync.md`, `vscode.md`, `macos-defaults.md` and `claude-config.md`, which covers hooks, permissions, skills, agents, catalog, `claude-config` and Hindsight wiring and loads on `.claude/**`, `agents/claude-*`, `agents/catalog/**`, `tilde/.claude/**`, `bin/claude-*` and `bin/hindsight-memory` edits) plus `code-navigation.md` (which tool to use: CodeGraph, Serena, or native Read/Edit).

<!-- END AUTO-MANAGED -->

<!-- AUTO-MANAGED: conventions -->

## Code Conventions

- `.editorconfig`: 2-space indent, LF, UTF-8, final newline. Markdown keeps trailing whitespace.
- Prettier with `prettier-plugin-sh`:
  - defaults: `singleQuote`, `semi: false`, `trailingComma: 'es5'`
  - `*.md`: `printWidth: 70`, `proseWrap: 'never'`, `trailingComma: 'none'`
  - `vscode/User/.prettierrc.yaml`: `trailingComma: none` (VS Code writes jsonc). It is not a root override because VS Code opens settings via `~/Library/Application Support/Code/User`, outside the repo, where the Prettier extension finds no root config and adds trailing commas. The nearest config wins, so it also governs `pnpm format`. `python.languageServer` in `settings.json` is pinned because the Python extension writes it back.
  - `firefox/user.js`: `semi: true`
- Bash scripts start with `#!/bin/bash` and a header comment. Setup scripts use `set -euo pipefail`.
- Output helpers (`info`, `warn`, `header`, `success`, `fail`) are defined inline per script with `tput` colors. No shared shell library is sourced.
- Comments explain the non-obvious _why_ (version pins, tool quirks, macOS behavior), and configs keep that comment density (`mise/config.toml`, `.gitignore`, `prettier.config.cjs`).
- A new `$HOME` config goes under `tilde/` at its home-relative path, and `symlinks.sh` picks it up automatically.
- Commit subjects are short, imperative, sentence case, with no conventional-commit prefix (e.g. "Fix --skip-codegraph deleting CodeGraph's mise shim").

<!-- END AUTO-MANAGED -->

<!-- AUTO-MANAGED: patterns -->

## Detected Patterns

- **Paired lists kept in sync**: telemetry opt-outs live in both `setup.sh` and `zsh/env.zsh` (see `.claude/rules/telemetry-sync.md`; checked by `bin/lib/test-conventions`).
- **Docs mirror behavior**: every change to setup behavior, the Brewfile or mise tools has a matching edit in `README.md`, `setup/README.md` or a per-directory README in the same commit, and in `CLAUDE.md` itself when architecture, setup order or conventions change (the auto-memory plugin is off for this repo: no `.claude/auto-memory/config.json`).
- **Interactive and idempotent setup**: scripts detect existing state (symlink already correct, tool already installed, Homebrew not yet on PATH) and skip or prompt rather than fail. Re-running `setup.sh` is the normal way to apply changes.
- **Guard optional tools**: shell config checks `command -v` / `command_exists` before sourcing Homebrew plugins or activating tools, so a fresh Mac without them still starts cleanly.
- **Resolve own location**: bash uses `$(cd "$(dirname "$0")/.." && pwd -P)`; Node uses `fileURLToPath(import.meta.url)` with a `$DOTFILES` override.

<!-- END AUTO-MANAGED -->

<!-- MANUAL -->

## Custom Notes

Add project-specific notes here. This section is never auto-modified.

- Standing approval: on `main`, once `pnpm check` passes (the commit-gate hook runs it) and the change is what was asked, commit and push without asking. Still ask before running setup scripts, deleting files outside the repo, or rewriting history.

<!-- END MANUAL -->
