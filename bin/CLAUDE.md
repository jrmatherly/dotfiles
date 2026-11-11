# Module: bin

<!-- AUTO-MANAGED: module-description -->

## Purpose

User CLI scripts, all on `PATH`. `zsh/path.zsh` prepends both `$DOTFILES/bin` and `$DOTFILES/bin/lib`. Each top-level `bin/` script is standalone and doubles as its own documentation through `help <script>`.

<!-- END AUTO-MANAGED -->

<!-- AUTO-MANAGED: architecture -->

## Module Architecture

- `bin/<name>`: an executable with no extension. Most are bash; a few use node, python3, perl or swift, depending on what the task needs.
- `git-*` scripts (`git-find`, `git-pr`, `git-setup`, `git-tidy`) also work as git subcommands (`git tidy`).
- `bin/lib/` holds helpers that are also on PATH: `check` (the `pnpm check` gate), `get-tldr-md` (the header → tldr renderer used by `help`), `starship-git-simple` (the prompt segment) and the `test-*` self-checks that `check` runs. Each self-check's header says what it covers. One that fakes `HOME` and calls a tool a mise shim can provide takes the shims off `PATH`, since a shim under a fake `HOME` starts cold and fetches every tool's versions from the network, which made `test-sysup` fail on timing.
- Long-script details load with the script: `.claude/rules/sysup.md`, `claude-config-tool.md`, `claude-catalog.md`, `hindsight-wiring.md`.
- Setup entrypoints: `set-defaults` (`mise bootstrap macos defaults apply`, then `setup/macos-extras.sh`), `dotfiles` (git pull only; re-run `setup.sh` afterwards to re-apply).
- `install-iosevka-code`: VS Code's font (no cask), with a conditional request so an unchanged zip isn't downloaded. `REVIEWED_SHA256` only flags a change. `install-snippetslab-skill` exits 1 (callers warn) when the app is missing, the output is empty, or a real directory sits at the link path.
- `rea-mcp`: what Claude Code's `rea` registration runs. It resolves `GHIDRA_INSTALL_DIR` and `JAVA_HOME` at every launch so the registration holds no versioned path (a pinned `openjdk@21` dangled when Ghidra 12.2 moved to `@25`). `JAVA_HOME` comes from the keg's `bin/ghidraRun` wrapper, the JDK the GUI uses, not one a newer formula definition only promises. The keg is `${HOMEBREW_PREFIX:-/opt/homebrew}/opt/ghidra`, a fixed path that app-launched Claude Code can reach without the shell's PATH.
- `docker-devcontainer`: what `dev.containers.dockerPath` runs. `BUILDX_BAKE_ENTITLEMENTS_FS=0` works around docker/compose#14285 and devcontainers/cli#1320, scoped to Dev Containers because it restores the pre-advisory behavior, so a compose file in an untrusted repo could read host files during the build. Delete it, the setting and the `dotfiles` template variable once a Compose release carries docker/compose#14325.
- `impeccable`: runs the launcher of the plugin version `installed_plugins.json` names, because the plugin never puts it on PATH and the cache path moves on every update.
- `help`: resolves `docs/<query>.md` first, then the header of `bin/<query>`, and falls back to `tldr`. tlrc rejects a page with a wrapped line, so each header line is one sentence on one line. `get-tldr-md` reads `docs/` and `bin/` only, so `bin/lib/` headers aren't rendered.

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
- Under `set -e`, never test `$?` after a bare assignment like `pids=$(lsof ...)`: a failure exits first and the check never runs (this made `clear-port` exit silently on a free port). Use `if pids=$(...); then` or `|| true`. Pass multi-line results as separate arguments (`clear-port` uses `xargs kill <<< "$port_num"`), not as one quoted string.
- Scripts that touch repo files resolve the repo from their own path (`cd "$(dirname "$0")/.."`, or `import.meta.url` in node) and honor `$DOTFILES`. They never hardcode `~/dotfiles`.
- Output helpers (`header`, `warning`, colors via `tput`) are defined inline. No shared library is sourced.
- Adding a script: create the file, make it executable (`chmod +x`), write the header, check that `help <name>` renders, then run `pnpm check`. If it's user-facing, add it to `docs/README.md`.

<!-- END AUTO-MANAGED -->

<!-- AUTO-MANAGED: dependencies -->

## Key Dependencies

- CLIs from `30-packages.toml`: `gh`, `fzf`, `bat`, `rg`, `jq`, `cwebp`, and `tldr` (tlrc, configured by `tilde/.tlrc.toml`).
- `node` from mise, for `get-tldr-md`, `myip` and other ESM scripts. `package.json` is `"type": "module"`.
- `mise`, for `sysup` and runtime-related scripts.
- macOS system tools: `lsof` (`check-port`/`clear-port`), `defaults`, `softwareupdate`, `dscacheutil`.

<!-- END AUTO-MANAGED -->

<!-- MANUAL -->

## Notes

<!-- END MANUAL -->
