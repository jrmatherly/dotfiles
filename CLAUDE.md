# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

<!-- AUTO-MANAGED: project-description -->

## Overview

Personal macOS dotfiles for Apple Silicon (mise installs formulae and casks into `/opt/homebrew`; that zsh is the login shell); a personalized fork of nicksp/dotfiles.

- No application code: bash setup scripts, `bin/` CLI scripts, zsh config, and app config files.
- The repo is the source of truth. Everything is symlinked into `$HOME` and configured by editing files in the clone.
- Covers formulae, casks and VS Code extensions (`tilde/.config/mise/conf.d/30-packages.toml`, installed by mise; nothing calls `brew`), runtimes via mise, macOS defaults, VS Code, Ghostty/cmux, Obsidian, Firefox, and coding-agent config (Claude Code, Amp, Codex).
- Squirrelsong color theme files for many apps are owned by the repo.

<!-- END AUTO-MANAGED -->

<!-- AUTO-MANAGED: build-commands -->

## Build & Development Commands

There is no build. `pnpm check` (`bin/lib/check`) is the gate: syntax checks, shellcheck, Prettier, actionlint and every self-check. It exports `LC_ALL=en_US.UTF-8` because the self-checks grep for UTF-8 glyphs.

- `pnpm format`: prettier `--write` over the same globs. YAML is covered only under `.github/`, because app-written configs like `tilde/.config/gh/config.yml` aren't Prettier-clean.
- `.prettierignore` also lists zsh files (VS Code's format-on-save runs Prettier's shell plugin, which reads zsh as bash and rewrote `${keys[Ctrl+K]}`); add any new zsh file not ending in `.zsh` there. It skips files that tools rewrite themselves: any `CLAUDE.md`, `.serena/`, `.claude/auto-memory/`, `.claude/settings.local.json`, `docs/superpowers/`, `.superpowers/`, `tilde/.claude/rules/jstack-models.md` (rewritten whole by `/jstack:setup-jstack`), plus the git-ignored `private/` and `logs/`. Don't hand-format them.
- One file: `bash -n <file> && shellcheck --severity=warning <file> && prettier --check <file>`.
- `./setup.sh`: links the mise config, installs mise and the packages, then runs `mise bootstrap` (never macOS preferences, which are `set-defaults`). It's interactive. Flags: `-y`, `--skip-codegraph`, `--dash`, `-h`, `-- <mise args>`. From a terminal it logs each run to `private/setup-logs/<timestamp>.log` (via `script`), which `/validate-setup after` reads.
- `mise dotfiles apply`: re-link only (`mise dotfiles status` shows drift). `./setup/dotfiles-extras.sh`: git identity, Firefox hard links, the `cot` and `code` links.
- `sysup`: upgrades macOS, mise and its packages, runtimes and the agent tooling, printing one status line per step with full output in the git-ignored `logs/sysup-<timestamp>.log`. `setup.sh` only installs what's missing, unless run with `-- --upgrade`. Details: `.claude/rules/sysup.md`.
- `help <bin-script>`: renders a script's header. Use it to verify new or edited `bin/` scripts.

<!-- END AUTO-MANAGED -->

<!-- AUTO-MANAGED: architecture -->

## Architecture

```text
setup.sh          wrapper → packages, mise bootstrap (conf.d/*.toml, task setup/misc.sh), setup/dotfiles-extras.sh (+ dash.sh with --dash)
setup/            per-step scripts, macos-extras.sh (what the macOS TOML can't express), README.md (per-script docs)
tilde/            mirrors $HOME (dotfiles, .config/*, .codex, .ssh/config)
zsh/              sourced by tilde/.zshrc
bin/              CLI scripts on PATH (see bin/CLAUDE.md); bin/lib/ helpers also on PATH
settings/         uv package dotfiles-settings: registry.toml + adapters, CLI, Textual UI (bin/dotfiles-settings)
docs/             alias index + docs/gui/<app>.md cheat sheets (rendered by `help`); docs/superpowers/plans/ = open implementation plans (not applied yet); move each to plans/completed/ once fully implemented; docs/superpowers/specs/ = the assessments and designs those plans argue from; a spec moves to specs/completed/ when every plan built on it is completed (a spec with no plan, when its "built" or decision section records the work as shipped)
vscode/User/      whole dir symlinked to ~/Library/Application Support/Code/User
.github/          workflows: check.yml = `pnpm check` on macOS for PRs and pushes to main; fresh-install.yml = a manual `./setup.sh` run
agents/           instructions.md → Amp/Codex AGENTS.md; catalog/ = generator for `bin/claude-catalog`
obsidian/ firefox/ mole/ colors/ etc.     app config + repo-owned themes
icons/                                     vendored binaries, don't edit
```

- **Setup order**: mise is installed first and its part order is fixed. `setup.sh` installs packages itself first, so one failed package doesn't stop the run. What each step does is in `setup/README.md`; the constraints are in `.claude/rules/setup.md`.
- **Symlinking**: `tilde/.config/mise/conf.d/40-dotfiles.toml` declares every link and `mise dotfiles apply` makes them. A real file in the way stops the apply, and `--force` replaces with no backup. Details: `.claude/rules/symlinks.md`.
- **Forking**: the repo is public and cloned over HTTPS (no `gh` login needed). `README.md`'s "Make it yours" table lists the files hard-coded to the owner (clone URL, fastfetch, lazygit `authorColors`, `agents/claude-*`, `curated.toml`, `30-packages.toml`, LICENSE, `package.json` author, the archify diagram source); update it when adding another owner-specific value.
- **Repo location**: never assumed. Scripts resolve it themselves. Shells get `$DOTFILES` from `tilde/.zshenv`. `~/dotfiles` must be a symlink to the clone: every `[dotfiles]` source goes through it, because a `source` is not a template and cannot expand `$DOTFILES`. `setup.sh` creates it and stops when a different `~/dotfiles` is in the way.
- **Shell**: `tilde/.zshrc` sources `zsh/`. Agent shells differ from user shells on purpose: `.claude/rules/zsh.md`.
- **Runtimes**: mise, via the global `tilde/.config/mise/config.toml`. Several Node/Python versions are installed; the first listed is the default. Global npm CLIs are mise `npm:` tools, never `npm -g` (the common spellings are denied by a user-settings permission rule, tracked in `agents/claude-settings.json`). Don't rely on Homebrew's Python. Rust is the one runtime outside mise's `[tools]`: the keg-only `rustup` formula is the system toolchain manager (PATH order explained in `zsh/path.zsh`), and a project that pins another version uses mise's rust backend, which reuses that rustup; a global mise `rust` entry would override a project's `rust-toolchain.toml`, so none is declared. `idiomatic_version_file_enable_tools` makes mise honor `.nvmrc`/`.python-version`.
- **Help system**: `help` shows `docs/README.md`. `help <script>` goes through `bin/lib/get-tldr-md`, which renders the first comment block of `bin/<script>` as a tldr page. `help gui/<app>` renders `docs/gui/<app>.md` with bat.
- **Machine-local config** lives outside the repo: `~/.gitconfig.local` (identity and signing, written by `setup/dotfiles-extras.sh`), `~/.ssh/config.local`, `~/.zsh.local`, `~/.ssh/github_personal.pub` (1Password SSH agent). Anything tools append to `~/.gitconfig` (a repo symlink) belongs in `.local`. The in-repo exceptions are gitignored and lost on a re-clone: `mole/*.local` (kept next to the shared file it replaces, linked through an entry in `config.local.toml`) and mise's local files under `tilde/.config/mise/` (`config.override.toml`, `config.local.toml`, `miserc.local.toml`), which land in the clone because `~/.config/mise` is a link. A `mise set --override` value beats the same export in `~/.zsh.local` (`zsh/override-env.zsh`).
- **Agents**: `agents/instructions.md` is linked as `~/.config/amp/AGENTS.md` and `~/.codex/AGENTS.md`, but not as Claude's `CLAUDE.md`. `tilde/.codex/config.toml` is never linked: setup's `codex mcp add`, Hindsight and Codex write the live file, so mise adds only the keys it lacks (`merge = "missing"`). CodeGraph config is `codegraph.json`; the `.codegraph/` index is per-machine and gitignored. Serena project config is in `.serena/`; its memories are only a pointer to the `CLAUDE.md` files. Serena's bash language server sees only `*.sh`/`*.bash` files, so extensionless `bin/` scripts, `zsh/*.zsh` and configs need native Read/Edit.
- **Path-scoped rules**: `.claude/rules/` holds topic rules that load when matching files are touched (each file's `paths:` says which). Of the tracked ones, only `code-navigation.md` loads in every session.

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
- A new `$HOME` config goes under `tilde/` at its home-relative path and gets a `[dotfiles]` entry in `40-dotfiles.toml`. `bin/lib/test-dotfiles` fails without it. Rules under `tilde/.claude/rules/` need none.
- Commit subjects are short, imperative, sentence case, with no conventional-commit prefix (e.g. "Fix --skip-codegraph deleting CodeGraph's mise shim").

<!-- END AUTO-MANAGED -->

<!-- AUTO-MANAGED: patterns -->

## Detected Patterns

- **Paired lists kept in sync**: telemetry opt-outs live in both `setup.sh` and `zsh/env.zsh` (see `.claude/rules/telemetry-sync.md`; checked by `bin/lib/test-conventions`).
- **Docs mirror behavior**: a change to setup behavior, the package list or mise tools has a matching edit in `README.md`, `setup/README.md` or a per-directory README in the same commit. Instruction files are not a changelog: edit `CLAUDE.md` or a rule only when a stated fact becomes false or there's a why or constraint the code can't show, and prefer deleting text that restates the code over extending it. `bin/lib/test-conventions` caps their size (the auto-memory plugin is off for this repo: no `.claude/auto-memory/config.json`).
- **Interactive and idempotent setup**: scripts detect existing state (symlink already correct, tool already installed, mise not yet on PATH) and skip or prompt rather than fail. Re-running `setup.sh` is the normal way to apply changes. A run is not a transaction: rerun after a failure.
- **Guard optional tools**: shell config checks `command -v` / `command_exists` before sourcing zsh plugins or activating tools, so a fresh Mac without them still starts cleanly.
- **Resolve own location**: bash uses `$(cd "$(dirname "$0")/.." && pwd -P)`; Node uses `fileURLToPath(import.meta.url)` with a `$DOTFILES` override.

<!-- END AUTO-MANAGED -->

<!-- MANUAL -->

## Custom Notes

Add project-specific notes here. This section is never auto-modified.

- Standing approval: on `main`, once `pnpm check` passes (the commit-gate hook runs it) and the change is what was asked, commit and push without asking. Still ask before running setup scripts, deleting files outside the repo, or rewriting history.

<!-- END MANUAL -->
