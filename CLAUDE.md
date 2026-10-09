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

There is no build. `pnpm check` is the gate (its only test is the catalog generator's, run via `mise exec python --` when mise exists since `tomllib` needs 3.11+).

- `pnpm check` (`bin/lib/check`) runs:
  - `bash -n` on `setup.sh`, `setup/*.sh`, `.claude/hooks/*.sh`, `.claude/skills/*/*.sh`, `tilde/.bash_profile`, and `bin/*` scripts with a bash/sh shebang
  - `zsh -n` on `tilde/.zshenv`, `tilde/.zshrc`, `zsh/*.zsh`
  - `shellcheck --severity=warning` on the same bash scripts (`.shellcheckrc` also enables `check-unassigned-uppercase`)
  - `python3 agents/catalog/test_build_catalog.py` (status/cleanup rules of the Claude Code catalog generator)
  - `brew bundle list` on `setup/Brewfile` with `manual` lines stripped (parse check, skipped without `brew`)
  - `vscode/test-vscode-settings.sh` (the renderer's tests) and a Prettier check of every VS Code preset's render (skipped without `minijinja-cli`)
  - `prettier --check` over js/cjs/ts/md/json/sh and `bin/*`
- `pnpm format`: prettier `--write` over the same globs.
- `.prettierignore` also lists zsh files (VS Code's format-on-save runs Prettier's shell plugin, which reads zsh as bash and rewrote `${keys[Ctrl+K]}`); add any new zsh file not ending in `.zsh` there. It skips files that tools rewrite themselves: any `CLAUDE.md`, `.serena/`, `.claude/auto-memory/`, `.claude/settings.local.json`, `docs/superpowers/`, `.superpowers/`, plus the git-ignored local scratch dir `private/`. Don't hand-format them.
- Claude Code hooks: `.claude/settings.json` runs `.claude/hooks/lint-edited.sh` after Edit/Write (and Serena edit tools). It prettier-formats and lints the one edited file, but only within `pnpm check`'s scope (prettier globs and top-level `bin/*`; `bash -n` + shellcheck only for `bin/lib/check`'s list, so sourced snippets like `colors/*.sh` and `bin/lib/` are skipped), exiting 2 so Claude sees problems. Files written through Bash (heredocs, `sed -i`, `tee`) get the same treatment from `lint-bash-edits.sh` (PostToolUse Bash), which reads the changed-file list Claude Code records in `tool_response.bashEditDiff` (`bashEditDiffEnabled: true` in the tracked user settings turns recording on in every permission mode) and feeds each file to `lint-edited.sh`, or asks for `pnpm check` when more than 25 changed. The list is best effort: a file another process saved during the command can appear in it, and a command that exits non-zero or runs in the background records nothing, so `pnpm check` before committing stays the gate. Self-checks: `.claude/hooks/test-lint-edited.sh`, `.claude/hooks/test-lint-bash-edits.sh`.
- Claude Code permissions (`.claude/settings.json`): allowed without prompting are `pnpm check`/`pnpm format`, `shellcheck`, `bash -n`, `zsh -n` and the hook self-checks. Running `setup.sh`, `setup/*`, `set-defaults` or `upup` asks first (they change the machine) — the usual invocation forms are covered (`./`, `bash`/`sh`, absolute path, `bin/`), but it's a guard, not a hard boundary. Edits are denied for `ql-plugins/`, `obsidian/.obsidian/plugins/` and `tilde/.config/gh/hosts.yml`.
- One file: `bash -n <file> && shellcheck --severity=warning <file> && prettier --check <file>`.
- `./setup.sh --skip-brew`: re-apply the dotfiles on this machine. It's interactive. Add `--skip-codegraph` to leave CodeGraph alone; drop `--skip-brew` to also install the Brewfile. Other flags: `-y`, `--dash`, `-h`. From a terminal it logs each run to `private/setup-logs/<timestamp>.log` (via `script`), which `/validate-setup after` reads.
- `./setup/symlinks.sh`: re-link only.
- `upup`: upgrades macOS, Homebrew, mise tools, uv tools (Serena), the Iosevka Code font, the tracked agent skills (`claude-config restore skills --update`) and Amp (only if `amp` is installed; it's installed by hand). `brew upgrade` runs with `--yes` (Homebrew asks by default). A macOS update makes `softwareupdate` ask for the login password (Apple Silicon owner authorization; sudo/Touch ID don't count): optional `DOTFILES_MAC_PASSWORD_OP` (a 1Password secret reference, set in `~/.zsh.local`) feeds it via `op read` and `--stdinpass`, falling back to the prompt. It lists macOS updates first and skips the install when none, and a failed dotfiles pull only warns. `setup.sh` only installs what's missing and never upgrades, except that font: `bin/install-iosevka-code` (VS Code's font, no cask; run by `setup/misc.sh` and `upup`) reinstalls it whenever the upstream zip changed (ETag check; `REVIEWED_SHA256` in the script only triggers a notice).
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
docs/             alias index + docs/gui/<app>.md cheat sheets (rendered by `help`); docs/superpowers/plans/ = open implementation plans (not applied yet); move each to plans/completed/ once fully implemented; docs/superpowers/specs/ = the assessments and designs those plans argue from
vscode/User/      whole dir symlinked to ~/Library/Application Support/Code/User
agents/           instructions.md → Amp/Codex AGENTS.md; catalog/ = generator for `bin/claude-catalog`
obsidian/ firefox/ colors/ ghostty etc.   app config + repo-owned themes
ql-plugins/ icons/                         vendored binaries, don't edit
```

- **Setup order**: `brew.sh` must run first because the later scripts use Homebrew tools. `misc.sh` covers Xcode CLT, `chmod +x` on everything in `bin/` except `*.md` (so `bin/CLAUDE.md` stays non-executable), `gh` auth, mise tools, Claude Code + CodeGraph + the mise MCP server, Serena (`uv tool install -p 3.13 serena-agent`, registered user-scope with Claude Code if missing), the rtk Claude Code hook (`rtk init -g --hook-only`), the Supabase CLI's persisted telemetry opt-out (`supabase telemetry disable`), PowerShell, `aspire certs trust` for the Aspire HTTPS dev cert (no y/N prompt, macOS may ask for the password; skipped when already trusted, only a hint when non-interactive), npm config (`min-release-age`, `allow-git none`) and, last, the Claude Code restore + catalog (so `npx skills` runs with those npm settings). `setup.sh` also does things the manual path skips: Touch ID for sudo (`/etc/pam.d/sudo_local`), a sudo keep-alive loop, and telemetry opt-out exports.
- **Symlinking**: `setup/symlinks.sh` links each top-level item of `tilde/` into `~`, and each child of `tilde/.config/` individually (it holds app-written state next to tracked files). `tilde/.claude` is special-cased: `~/.claude/rules` stays a real directory and each tracked `tilde/.claude/rules/*.md` is symlinked into it individually, so machine-local rules can sit alongside (an older whole-directory link is migrated); top-level files in `tilde/.claude` (e.g. `statusline-command.sh`) are linked into `~/.claude` too. `.codex` and `.ssh` are excluded and handled specially: only `.ssh/config` is linked. `tilde/README.md` itself is not linked. Targets outside `$HOME` (VS Code `User`, lazydocker, gpg, `ql-plugins`, Firefox `user.js` as a hard link) need an explicit `symlink_file` call. `symlink_file` never overwrites silently; it prompts skip/overwrite/backup.
- **Forking**: the repo is public and cloned over HTTPS (no `gh` login needed). `README.md`'s "Make it yours" table lists the files hard-coded to the owner (clone URL, fastfetch, lazygit `authorColors`, VS Code `notes.notesLocation`, `agents/claude-*`, `curated.toml`, Brewfile, LICENSE); update it when adding another owner-specific value.
- **Repo location**: never assumed. Scripts resolve it themselves. Shells get `$DOTFILES` from `tilde/.zshenv`. `~/dotfiles` is only a compatibility symlink for configs that can't expand variables (e.g. lazygit `shellFunctionsFile`).
- **zsh load order** (`tilde/.zshrc`): `path` → `env` → `options` → `aliases` → `completion` → `key-bindings` → plugins → `init.zsh` (mise activate, Homebrew zsh plugins, fast-theme) → `~/.zsh.local`. `tilde/.zprofile` activates mise shims for GUI apps. When `CLAUDECODE` is set (agent shells), `zsh/aliases.zsh` drops the built-in overrides (`cat`→bat, `ls`→eza, `find`→fd, `-i` cp/mv/rm, `grep -i`, …) and `zsh/options.zsh` turns `clobber` back on and autocorrect off.
- **Runtimes**: mise, via the global `tilde/.config/mise/config.toml`. Several Node/Python versions are installed; the first listed is the default. Global npm CLIs are mise `npm:` tools, never `npm -g`. Don't rely on Homebrew's Python. `idiomatic_version_file_enable_tools` makes mise honor `.nvmrc`/`.python-version`.
- **Help system**: `help` shows `docs/README.md`. `help <script>` goes through `bin/lib/get-tldr-md`, which renders the first comment block of `bin/<script>` as a tldr page. `help gui/<app>` renders `docs/gui/<app>.md` with bat.
- **Machine-local config** lives outside the repo: `~/.gitconfig.local` (identity and signing, written by `symlinks.sh`), `~/.ssh/config.local`, `~/.zsh.local`, `~/.ssh/github_personal.pub` (1Password SSH agent). Anything tools append to `~/.gitconfig` (a repo symlink) belongs in `.local`.
- **Agents**: `agents/instructions.md` is linked as `~/.config/amp/AGENTS.md` and `~/.codex/AGENTS.md`, but not as Claude's `CLAUDE.md`. `tilde/.codex/config.toml` is copied (never linked) into `~/.codex/config.toml` when missing: NotchBar (`[features] codex_hooks`) and Jean (`[mcp_servers]` with a token) rewrite the live file, and later setup runs only warn about tracked lines it lacks. CodeGraph config is `codegraph.json`; the `.codegraph/` index is per-machine and gitignored. Serena project config is in `.serena/`; its memories are only a pointer to the `CLAUDE.md` files. Serena's bash language server sees only `*.sh`/`*.bash` files, so extensionless `bin/` scripts, `zsh/*.zsh` and configs need native Read/Edit.
- **Global Claude rules**: `tilde/.claude/rules/*.md` are tracked and linked file-by-file into the real dir `~/.claude/rules` (`serena.md` holds Serena's launch invariants and why `trusted_project_path_patterns` stays `[]` in the untracked `~/.serena/serena_config.yml`; `tool-checks.md` says to verify with `command -v` before claiming a CLI is missing; `verify-first.md` is the never-assume/always-verify working rule; `jstack-models.md` sets the model per jstack role and is rewritten through its symlink by `/jstack:setup-jstack`; `chrome-devtools.md` and `handoffs.md` carry learnings for the chrome-devtools MCP and the `remember` plugin, kept here because edits to a plugin's cached skill are lost on update; `index.md` lists them). `~/.claude/CLAUDE.md` is deliberately NOT tracked, because `codegraph install` rewrites it via rename (which would break a symlink).
- **setup.sh diagram**: `setup/bootstrap-runtime.svg` (embedded in `setup/README.md`, linked from `README.md`) is generated by Archify from `setup/bootstrap-runtime.archify.json` (source line refs pinned to a commit). When step order, sudo use or download sources change, update the JSON, re-run `archify finalize` and re-export the SVG. Archify's per-run `.archify/` folder is gitignored; commit only the exported image.
- **Claude catalog**: `bin/claude-catalog` builds `~/.claude/catalog/{CATALOG.md,CATALOG-lite.md,catalog.html}` (installed skills, commands, subagents, MCP servers) via `agents/catalog/build_catalog.py`, run through mise's Python 3.11+ (`tomllib`; system python3 is 3.9). Hand-edited notes live in `agents/catalog/curated.toml` (the script exits 1 if it names something not installed); `catalog_template.html` is the HTML shell. The tracked global rule `tilde/.claude/rules/catalog.md` points Claude at the catalog. `__pycache__/` is gitignored.
- **Claude config**: `bin/claude-config save` snapshots into tracked files: `agents/claude-plugins.txt` (`save` never shrinks a tracked file: a missing source warns and keeps it, writes via `.tmp` + `mv`; marketplaces + user-scope plugins, `disabled` flag), `agents/claude-settings.json` (`~/.claude/settings.json` minus tool-owned keys `enabledPlugins`/`extraKnownMarketplaces`/`hooks`, `$HOME` written as `~` only where it starts a path, `//$HOME/` as `~/`, permission lists sorted; credential helpers `apiKeyHelper`/`awsCredentialExport`/`awsAuthRefresh`/`otelHeadersHelper` never saved, and of `env` only `CLAUDE_CODE_*`, `DISABLE_*`, `MAX_*` and `AZURE_MCP_COLLECT_TELEMETRY`) and `agents/claude-skills.txt` (`skill <name> <source> <agents>` from `~/.agents/.skill-lock.json`). `restore [plugins|settings|skills] [--dry-run]` re-applies them: missing marketplaces/plugins, settings merged with existing values winning and permission lists unioned (no rewrite if nothing is missing), and `npx skills add` for skills missing on some agents (stdin from `/dev/null`; an invalid settings merge warns instead of aborting). `restore skills --update` reinstalls every tracked skill for its listed agents instead (the CLI's own `skills update` reinstalls with no agent list, so a skill tracked for one agent would spread to all). Wired into `setup/misc.sh` (restore, then `claude-catalog`; restore gets `gh` as the only github.com git credential helper via `GIT_CONFIG_*` env for that run only (the empty first value stops Homebrew git's osxkeychain helper from storing the token), so a fresh Mac can clone the private `jrmatherly/skills` marketplace + its `coding-standards` and `supabase-prompts` skills without writing `~/.gitconfig.local`) and `bin/upup` (`restore skills --update`, `claude-config save || warning`, then catalog; a failure in either doesn't abort upup). `zsh/env.zsh` exports `DO_NOT_TRACK=1` (also used by the skills CLI and the Sentry CLI from the `getsentry/tools` Brewfile tap; see `docs/privacy.md`).
- **Project skills and agents**: `.claude/skills/` has `add-tool` (new-tool checklist), `docs-audit` (forks the read-only `.claude/agents/docs-auditor.md` agent) and `validate-setup` (user-only: before/after snapshot diff around `./setup.sh`, which the user runs in their own terminal, never Claude).
- **VS Code settings template**: `vscode/User/settings.json` is generated and gitignored. `bin/vscode-settings` renders it with minijinja-cli (Brewfile) from the tracked `vscode/User/settings.json.j2` plus a font preset from `vscode/presets.toml` (`iosevka` default, `warp`, `warp-terminal`, `fira`; choice saved in `~/.config/dotfiles/vscode.env`), filling in `$HOME` for `notes.notesLocation`. A hash of the last render (`vscode/User/.settings.rendered`) makes a re-render refuse to overwrite edits VS Code or an extension made; it shows the diff to port into the template, or `--force`. `setup/misc.sh` runs it (`--choose` on a terminal).
- **VS Code SpaceBox UI**: the default preset uses Iosevka Code Nerd Font (FiraCode as fallback). The `spacebox-ui.*` settings (blur) only take effect after the manual **SpaceBox Enable UI Enhancer** command plus a full VS Code quit and restart, which setup can't do (steps in `vscode/README.md`). `workbench.colorCustomizations["[SpaceBox]"]` holds see-through backgrounds for the blur on the Command Palette and hovers only (`menu.*` stays solid: extension panels like Claude Code reuse `menu.background` for their own menus, where the blur can't reach), and its value is what Mintlify Doc Writer writes back on startup, so keep it as is. The `spacebox-ui.stylesheet` rule works around a stuck Command Palette in extension 0.1.5 on VS Code 1.139. `dependi.decoration.incompatible.template` appends `\uFE0F` to the ❌ because Iosevka Code has its own plain glyph for it, which would otherwise render in the text color instead of as the red emoji.
- **Path-scoped rules**: `.claude/rules/` holds rules that load when matching files are touched (`setup.md`, `telemetry-sync.md`, `vscode.md`, `macos-defaults.md`) plus `code-navigation.md` (which tool to use: CodeGraph, Serena, or native Read/Edit).

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

- **Paired lists kept in sync**: telemetry opt-outs live in both `setup.sh` and `zsh/env.zsh` (see `.claude/rules/telemetry-sync.md`).
- **Docs mirror behavior**: every change to setup behavior, the Brewfile or mise tools has a matching edit in `README.md`, `setup/README.md` or a per-directory README in the same commit, and in `CLAUDE.md` itself when architecture, setup order or conventions change (the auto-memory plugin is off for this repo: no `.claude/auto-memory/config.json`).
- **Interactive and idempotent setup**: scripts detect existing state (symlink already correct, tool already installed, Homebrew not yet on PATH) and skip or prompt rather than fail. Re-running `setup.sh` is the normal way to apply changes.
- **Guard optional tools**: shell config checks `command -v` / `command_exists` before sourcing Homebrew plugins or activating tools, so a fresh Mac without them still starts cleanly.
- **Resolve own location**: bash uses `$(cd "$(dirname "$0")/.." && pwd -P)`; Node uses `fileURLToPath(import.meta.url)` with a `$DOTFILES` override.

<!-- END AUTO-MANAGED -->

<!-- MANUAL -->

## Custom Notes

Add project-specific notes here. This section is never auto-modified.

- Standing approval: on `main`, once `pnpm check` passes and the change is what was asked, commit and push without asking. Still ask before running setup scripts, deleting files outside the repo, or rewriting history.

<!-- END MANUAL -->
