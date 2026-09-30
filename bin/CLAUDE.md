# Module: bin

<!-- AUTO-MANAGED: module-description -->

## Purpose

User CLI scripts, all on `PATH`. `zsh/path.zsh` prepends both `$DOTFILES/bin` and `$DOTFILES/bin/lib`. Each script is standalone and doubles as its own documentation through `help <script>`.

<!-- END AUTO-MANAGED -->

<!-- AUTO-MANAGED: architecture -->

## Module Architecture

- `bin/<name>`: an executable with no extension. Most are bash; a few use node, python3, perl or swift, depending on what the task needs.
- `git-*` scripts (`git-find`, `git-pr`, `git-setup`, `git-tidy`) also work as git subcommands (`git tidy`).
- `bin/lib/` holds helpers that are also on PATH:
  - `check`: the `pnpm check` gate
  - `get-tldr-md`: the header → tldr renderer used by `help`
  - `starship-git-simple`: the prompt segment
- Setup entrypoints exposed as commands:
  - `brewpick`: Brewfile installer; `--all`, or an fzf checklist
  - `set-defaults`: runs `setup/macos.sh`
  - `dotfiles`: git pull only (re-run `setup.sh` afterwards to re-apply)
  - `upup`: upgrades (`brew upgrade --greedy --yes`; macOS updates via `softwareupdate`, with the owner password optionally read from 1Password when `DOTFILES_MAC_PASSWORD_OP` is set); also runs `claude-config save || warning` (a failed save no longer aborts upup; review the repo diff) and `claude-catalog`
  - `nyan`: upup's sign-off; prints Deadpool with his katanas by running `fastfetch --logo tilde/.config/fastfetch/ascii/deadpool-katanas.ascii --logo-type file --structure Break` (logo only, colours from fastfetch's config); exits 0 silently when `fastfetch` is missing
  - `claude-config`: `save` never shrinks a tracked file (a missing source ‒ `installed_plugins.json`, `settings.json`, `.skill-lock.json` ‒ warns and keeps the tracked file; writes go via `.tmp` + `mv`) and writes `agents/claude-plugins.txt` (`marketplace <name> <source>`, `plugin <id>[ disabled]`), `agents/claude-settings.json` (settings.json minus `enabledPlugins`/`extraKnownMarketplaces`/`hooks`, `$HOME`→`~` only where it starts a path and `//$HOME/` (Claude's absolute-path rule syntax) → `~/`, sorted permission lists; never the credential helpers `apiKeyHelper`/`awsCredentialExport`/`awsAuthRefresh`/`otelHeadersHelper`, and of `env` only `CLAUDE_CODE_*`, `DISABLE_*`, `MAX_*`) and `agents/claude-skills.txt` (`skill <name> <source> <agents>` from `~/.agents/.skill-lock.json`; `claude-code` → `~/.claude/skills`, `codex` → `~/.agents/skills`). `restore [plugins|settings|skills] [--dry-run]` runs commands with stdin from `/dev/null`, adds missing marketplaces, installs missing user-scope plugins (disabling recorded-disabled ones only on a fresh install), merges settings (existing values win, permission lists unioned, no rewrite when nothing is missing) and runs `npx skills add <source> -g -s <name> -a <agents> -y` with `DO_NOT_TRACK=1` for skills, only for the agents that lack them; an invalid settings merge warns instead of aborting. `setup/misc.sh` runs it last (after PowerShell and npm config)
  - `claude-catalog`: builds `~/.claude/catalog/` (see `agents/catalog/`); run by `setup/misc.sh` after `claude-config restore` (its stderr is hidden, only the summary line shows). In setup both warn on failure and never abort; in `upup` `save` is `|| warning`
  - `install-iosevka-code`: VS Code's font into `~/Library/Fonts` (no cask); state in `~/Library/Fonts/.IosevkaCodeNerdFont.{sha256,etag}`, conditional request so an unchanged zip isn't downloaded, a changed one is installed and flagged against `REVIEWED_SHA256`. Run by `setup/misc.sh` (`|| warning`) and `upup`
  - `install-color-themes`, `obsidian-vault`
- `help`: resolves `docs/<query>.md` first, then the header of `bin/<query>`, and falls back to `tldr`.

<!-- END AUTO-MANAGED -->

<!-- AUTO-MANAGED: conventions -->

## Module-Specific Conventions

- Every script starts with a header comment block right after the shebang. `get-tldr-md` renders the first contiguous `#` or `//` comment block and cuts it at `---`:

  ```bash
  #!/bin/bash
  #
  # One-line description.
  #
  # - What this invocation does:
  #
  # `name {{arg}}`
  #
  # ---
  # License: MIT
  ```

  Use `{{placeholder}}` for arguments, since tldr highlights them. Everything after `---` (license, source credit) is hidden.

- Bash is the default language. `pnpm check` only lints scripts with a `#!/bin/bash`, `#!/bin/sh` or `#!/usr/bin/env (ba)sh` shebang; other languages get prettier only (node) or nothing. `bin/license` is excluded from shellcheck.
- Shellcheck runs at `--severity=warning` with `check-unassigned-uppercase` (`.shellcheckrc`): write optional env vars as `${VAR:-}`. SC2088 (`~` in quotes) is fixed per line (tildify, or a scoped `# shellcheck disable=SC2088` with a reason), never disabled globally.
- Under `set -e`, never test `$?` after a bare assignment like `pids=$(lsof ...)`: a failure exits first and the check never runs (this made `clear-port` exit silently on a free port). Use `if pids=$(...); then` or `|| true`. Pass multi-line results as separate arguments (`clear-port` uses `xargs kill <<< "$pids"`), not as one quoted string.
- Scripts that touch repo files resolve the repo from their own path (`cd "$(dirname "$0")/.."`, or `import.meta.url` in node) and honor `$DOTFILES`. They never hardcode `~/dotfiles`.
- Output helpers (`header`, `warning`, colors via `tput`) are defined inline. No shared library is sourced.
- Adding a script: create the file, make it executable (`chmod +x`), write the header, check that `help <name>` renders, then run `pnpm check`. If it's user-facing, add it to `docs/README.md` or the README's script list.

<!-- END AUTO-MANAGED -->

<!-- AUTO-MANAGED: dependencies -->

## Key Dependencies

- Homebrew CLIs: `brew`, `gh`, `fzf`, `bat`, `rg`, `jq`, `cwebp`, and `tldr` (tlrc, configured by `tilde/.tlrc.toml`).
- `node` from mise, for `get-tldr-md`, `myip` and other ESM scripts. `package.json` is `"type": "module"`.
- `mise`, for `upup` and runtime-related scripts.
- macOS system tools: `lsof` (`check-port`/`clear-port`), `defaults`, `softwareupdate`, `dscacheutil`.

<!-- END AUTO-MANAGED -->

<!-- MANUAL -->

## Notes

<!-- END MANUAL -->
