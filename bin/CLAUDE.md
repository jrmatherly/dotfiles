# Module: bin

<!-- AUTO-MANAGED: module-description -->

## Purpose

User CLI scripts, all on `PATH`. `zsh/path.zsh` prepends both `$DOTFILES/bin` and `$DOTFILES/bin/lib`. Each top-level `bin/` script is standalone and doubles as its own documentation through `help <script>` (`get-tldr-md` reads `docs/` and `bin/` only, so `bin/lib/` headers aren't rendered).

<!-- END AUTO-MANAGED -->

<!-- AUTO-MANAGED: architecture -->

## Module Architecture

- `bin/<name>`: an executable with no extension. Most are bash; a few use node, python3, perl or swift, depending on what the task needs.
- `git-*` scripts (`git-find`, `git-pr`, `git-setup`, `git-tidy`) also work as git subcommands (`git tidy`).
- `bin/lib/` holds helpers that are also on PATH:
  - `check`: the `pnpm check` gate
  - `get-tldr-md`: the header → tldr renderer used by `help`
  - `starship-git-simple`: the prompt segment
  - `test-upup`: fixture self-check for `upup`'s report against stubbed tools, run by `check`
  - `test-rea-mcp`: fixture self-check for `rea-mcp` (a stubbed `brew`, a fixture Ghidra keg with a Homebrew-style `ghidraRun` wrapper, a fake mise shim that echoes its environment), run by `check`
  - `test-conventions`: tree invariants the docs promise (telemetry pairing between `setup.sh` and `zsh/env.zsh`, every zsh file Prettier-ignored, a header comment on line 2 of every `bin/` script, `trusted: true` on every third-party Brewfile formula or cask), run by `check`
  - `test-hindsight-memory`: fixture self-check for `hindsight-memory` under a temp `HOME` with the vendor installer, `hindsight-embed` and `npm` stubbed (`MISE_STATE_DIR` keeps the real mise trust records, since a shim run under a fake `HOME` refuses the global config), run by `check`
- Setup entrypoints exposed as commands:
  - `brewpick`: Brewfile installer; `--all`, or an fzf checklist
  - `set-defaults`: runs `setup/macos.sh`
  - `dotfiles`: git pull only (re-run `setup.sh` afterwards to re-apply)
  - `upup`: a quiet report, one status line per step from a four-level table (`ok` ✔ green, `changed` ↻ cyan, `notice` ● yellow, `fail` ✖ red with the command to rerun; the sudo prompt in magenta; colors only when stdout is a terminal `tput` knows) with the full tool output in `$DOTFILES/logs/upup-<timestamp>.log` (git-ignored, no color codes; every step's output is captured into it, and only `softwareupdate`'s install and the `git log` of pulled commits also stream to the screen) and a final summary (elapsed time, Changed, Notices, Failed, Action needed, a `file://` link to `catalog.html`, log path, or "Everything up to date."); a failed step never aborts the run, and `Claude config` reports a change only when `claude-config save` altered `agents/` during the run. Self-check: `bin/lib/test-upup` (stubs every external command on PATH, run by `check`). Upgrades (`brew upgrade --greedy --yes`, after an `upgrading N packages: …` line naming them; `rustup update --no-self-update` through `$HOMEBREW_PREFIX/opt/rustup/bin/rustup` when it exists, else the `rustup` on PATH (a mise shim earlier on an activated PATH would otherwise win; one left by a rust toolchain no config pins gets a notice naming `mise prune`), a `Rust` line naming the channel and versions, plus a notice when `cargo --version` fails, the same probe Hindsight's daemon preflight runs, since Homebrew's keg-only rustup puts its proxies in `/opt/homebrew/opt/rustup/bin` and a shell older than that PATH entry can't see them; macOS updates via `softwareupdate`, with the owner password optionally read from 1Password when `DOTFILES_MAC_PASSWORD_OP` is set); also runs `claude update` first (a `Claude Code` line with the version, `before → after` plus a restart action when it changed, from two `claude --version` readings since the update message is not parsed), then `claude-config restore skills --update` (reinstalls the tracked skills for their listed agents), `rea setup --skill-client shared --skill-client claude_code --skill --yes --format json` when `rea` is on PATH (a `REA skill` line: `changed` when `appliedActions` is non-empty, else `ok`), `hindsight-memory upgrade` when `~/.hindsight/coding-agent.json` exists (re-runs the pinned Hindsight installer; a newer npm release is a notice naming the `CODING_AGENTS_VERSION` pin to bump by hand, never installed; the installer's own `▲` warning lines, such as no `cargo` on PATH, become a notice too, since each means the daemon can't cold-start from that shell, and the step prints no `ok` line when either notice fired), `claude plugin marketplace update` and then `claude plugin update <id>` for every key in `installed_plugins.json`, any scope with `-y`, which accepts a marketplace-declared install command unseen, a trust the tracked marketplaces have earned (only updated/downgraded lines are printed; a failure warns), `claude-config save` (a failed save is a `fail` line and does not abort upup; review the repo diff) and `claude-catalog`, then, when `claude mcp get mise` isn't `✔ Connected`, re-registers a user-scope entry whose command isn't `$(command -v mise) mcp`, and otherwise warns: `tools fetch failed` means anthropics/claude-code#88128 is back (re-registering can't fix it), anything else prints the re-register command. No registration, or a local/project one shadowing it, is left alone
  - `nyan`: upup's sign-off; prints Deadpool with his katanas by running `fastfetch --logo tilde/.config/fastfetch/ascii/deadpool-katanas.ascii --logo-type file --structure Break` (logo only, colours from fastfetch's config); exits 0 silently when `fastfetch` is missing
  - `claude-config`: `save` never shrinks a tracked file (a missing source ‒ `installed_plugins.json`, `settings.json`, `.skill-lock.json` ‒ warns and keeps the tracked file; writes go via `.tmp` + `mv`) and writes `agents/claude-plugins.txt` (`marketplace <name> <source>`, `plugin <id>[ disabled]`), `agents/claude-settings.json` (settings.json minus `enabledPlugins`/`extraKnownMarketplaces`/`hooks`, `$HOME`→`~` only where it starts a path and `//$HOME/` (Claude's absolute-path rule syntax) → `~/`, sorted permission lists; never the credential helpers `apiKeyHelper`/`awsCredentialExport`/`awsAuthRefresh`/`otelHeadersHelper`, and of `env` only `CLAUDE_CODE_*` (minus the two switches the LLM Router's gateway profile writes, `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY` and `CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT`), `DISABLE_*`, `MAX_*`, `AZURE_MCP_COLLECT_TELEMETRY`, `HINDSIGHT_API_LLM_PROVIDER` and the `HINDSIGHT_API_*LLM_MODEL` pins, never an API key) and `agents/claude-skills.txt` (`skill <name> <source> <agents>` from `~/.agents/.skill-lock.json`, a `well-known` source written as the URL the CLI stored (`sourceBaseUrl`), since its bare-host `source` fails as a git clone; `claude-code` → `~/.claude/skills`, `codex` → `~/.agents/skills`). `restore [plugins|settings|skills] [--dry-run]` runs commands with stdin from `/dev/null`, adds missing marketplaces, installs missing user-scope plugins (running `claude plugin marketplace update <name>` once first for a marketplace already on the machine, which may predate the plugin; disabling recorded-disabled ones only on a fresh install), merges settings (existing values win, permission lists unioned, no rewrite when nothing is missing) and runs `npx skills add <source> -g -s <name> -a <agents> -y` with `DO_NOT_TRACK=1` for skills, only for the agents that lack them; an invalid settings merge warns instead of aborting. `setup/misc.sh` runs it last (after PowerShell and npm config)
  - `claude-catalog`: builds `~/.claude/catalog/` (see `agents/catalog/`; `--open` then opens `catalog.html`); run by `setup/misc.sh` after `claude-config restore` (its lint lines show, so a stale `curated.toml` entry is named in the setup log). In setup both warn on failure and never abort; in `upup` `save` is `|| warning`
  - `install-iosevka-code`: VS Code's font into `~/Library/Fonts` (no cask); state in `~/Library/Fonts/.IosevkaCodeNerdFont.{sha256,etag}`, conditional request so an unchanged zip isn't downloaded, a changed one is installed and flagged against `REVIEWED_SHA256`. Run by `setup/misc.sh` (`|| warning`) and `upup`
  - `install-snippetslab-skill`: SnippetsLab's agent skill (`lab skill show`, a static copy) into `~/.agents/skills/snippetslab` plus the `~/.claude/skills/snippetslab` link; exits 1 (callers warn) when the app is missing, the output is empty, or a real directory sits at the link path. Run by `setup/misc.sh` and `upup`
  - `hindsight-memory`: wraps the vendor installer `@vectorize-io/hindsight-coding-agents` for opt-in, per-repo Hindsight memory in Claude Code and Codex (`init`, `upgrade`, `paths [list|add|remove]`, `on|off`, `survey on|off`, `status`, `uninstall`). Two pins at the top, `CODING_AGENTS_VERSION` and `EMBED_VERSION`, are the only places versions appear (`embedVersion` in the defaults is built from the second). `init` runs the installer only when `~/.hindsight/coding-agent.json` is missing, then merges the defaults additively through one `jq` writer (keys already in the file win, except `embedVersion`, which always follows the pin, and a `pageTriggerCron` still at the script's earlier default `0 6 * * *`, which moves to the current one; an unreadable or invalid file fails instead of being replaced; the file is never tracked). `upgrade` re-runs the installer unconditionally and prints `newer release <v> on npm; bump CODING_AGENTS_VERSION` when `npm view` reports a version above the pin (`sort -V`). Paths are stored as typed (a relative path is resolved against `$PWD`, since the plugin compares absolute session directories) with one trailing slash stripped and a true `$HOME` prefix written as `~` (`"~${p#"$HOME"}"`, since bash 3.2 prints a literal backslash for `${p/#$HOME/\~}`), no `realpath`, because the plugin expands only `~` and tests a literal prefix. `uninstall` runs the vendor `uninstall all` and stops the daemon and moves the config to `coding-agent.json.uninstalled`, which `init` restores (`upup` keys the step on the config's presence, so a kept config would reinstall the hooks); the database stays. Overrides for the self-check: `HINDSIGHT_CONFIG`, `HINDSIGHT_MEMORY_INSTALLER`, `HINDSIGHT_MEMORY_EMBED`, `HINDSIGHT_MEMORY_NPM` (each split on whitespace). Wired into `setup/misc.sh` (`init`) and `upup` (`upgrade`); spec in `docs/superpowers/specs/completed/2026-10-24-hindsight-memory.md`
  - `rea-mcp`: what Claude Code's `rea` MCP registration runs (`setup/misc.sh` registers it by absolute path). Resolves `GHIDRA_INSTALL_DIR` (`brew --prefix ghidra` plus `libexec`) and `JAVA_HOME` (the default baked into the installed keg's `bin/ghidraRun` wrapper, which Homebrew rewrites with each Ghidra install, so it is the JDK the GUI uses and never one a `brew update` without `brew upgrade` only promises; a `JAVA_HOME` already set wins, and one without `bin/java` is dropped with a warning on stderr) at every launch, then execs the mise `rea` shim with `mcp`, so the registration holds no versioned path (a pinned `openjdk@21` dangled when Ghidra 12.2 moved to `@25`). Without Homebrew Ghidra it warns and still starts REA for the other providers. Finds `brew` at `/opt/homebrew/bin/brew` when it is not on PATH (app-launched Claude Code). `--print-env` prints the two values instead of starting the server.
  - `docker-devcontainer`: what `dev.containers.dockerPath` in the rendered VS Code settings runs. Exports `BUILDX_BAKE_ENTITLEMENTS_FS=0` and execs `docker` (`/opt/homebrew/bin/docker` when PATH lacks it, as in an app-launched VS Code), because buildx 0.37.2 enforces the `fs.read` entitlement under `--progress rawjson` and Compose grants none for the merged Dockerfile the Dev Containers CLI writes under `$TMPDIR` (docker/compose#14285, devcontainers/cli#1320). Scoped to Dev Containers on purpose: the flag restores the pre-advisory behavior, so a compose file in an untrusted repo could read host files during the build. Delete it, the setting and the `dotfiles` template variable once a Compose release carries docker/compose#14325; `upup` won't notice, since the compose plugin in use is OrbStack's, not Homebrew's
  - `impeccable`: runs the Impeccable engine launcher of the plugin version `installed_plugins.json` names (`impeccable@impeccable`, `$CLAUDE_CONFIG_DIR` honoured), for by-hand verbs like `telemetry status`; the plugin itself never puts the launcher on PATH, and the cache path moves on every plugin update, so no symlink. Exits 127 with the install command when the plugin is missing, or when `jq` is
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
