---
name: add-tool
description: Checklist for adding a CLI, app, runtime, VS Code extension or MCP server to these dotfiles — Brewfile vs mise vs uv, tap trust, setup wiring, telemetry opt-outs, symlinked config and docs. Use whenever a tool is being added ("add X", "we need X installed", a `brew install …` command, a VS Code Marketplace or install-docs link) or an existing one's install method changes.
argument-hint: '[tool name]'
---

Add `$ARGUMENTS` to the dotfiles. Work through every item; say explicitly when one doesn't apply.

0. **Identify the exact tool**: read the linked install docs. If a vendor ships a new and a legacy CLI (e.g. Sentry's `sentry` vs `sentry-cli`), name which one and say so.
1. **Install method** (pick one):
   - macOS app or system CLI → `setup/Brewfile` (`brew`/`cask` line with a trailing `#` comment), installed by `bin/brewpick --all`.
   - VS Code extension → a `vscode "<publisher.id>"` line in the matching extension section of `setup/Brewfile`.
   - Runtime or npm CLI → `tilde/.config/mise/config.toml` `[tools]` (`"npm:<pkg>" = "<major>"`), with a comment explaining the pin. Never `npm install -g`.
   - Python CLI → the Brewfile if Homebrew packages it (e.g. `pipx`, `pre-commit`); otherwise `uv tool install` in `setup/misc.sh`, guarded by `command_exists uv` (`bin/upup` runs `uv tool upgrade --all`).
2. **Brewfile specifics**:
   - Third-party tap: add `tap "<org>/<tap>"` to the Taps block, and write the package fully qualified with `trusted: true` (trust per package, never the whole tap; see the Brewfile header).
   - Place it in the matching section, alphabetical by package name; keep the one-line `#` comment style. Add a short comment block above it only for a non-obvious why.
3. **Install it now and check**: `brew install …` / `code --install-extension <id>` (says "already installed" if present), then `<tool> --version`. Read the formula's `post_install` (`brew cat <formula>`) and report anything it writes outside Homebrew (shell completions, agent skills, dotfiles).
4. **Setup wiring** (`setup/misc.sh`): only when the tool needs post-install steps (MCP registration via `claude mcp get <name> || claude mcp add --scope user …`, telemetry off). Per-account logins (`gh auth`, `sentry auth`) are left to the user unless they ask. Keep it idempotent and warn — don't fail — when a step can't run.
5. **Telemetry**: check the tool's docs for an opt-out. If it honours `DO_NOT_TRACK` (already exported by `zsh/env.zsh`), just name it in `docs/privacy.md`. Otherwise add its variable to `zsh/env.zsh` and `docs/privacy.md`, plus `setup.sh` and `README.md`'s opt-out list if setup itself runs the tool.
6. **Config files**: `$HOME` config goes under `tilde/` at its home-relative path. If the tool rewrites its config via temp-file + rename (breaks symlinks), don't track it — note that in `setup/README.md`.
7. **Upgrades**: confirm `bin/upup` covers it (Homebrew, `mise upgrade` and `uv tool upgrade --all` already do).
8. **Docs**: `setup/README.md` (the section of the script you touched), `README.md` if user-facing, `docs/README.md` if it adds an alias or `bin/` command. A plain Brewfile entry needs no README line (they don't list packages).
9. **Verify**: `pnpm check` (it also parses the Brewfile); then, if setup scripts changed, tell the user to run `./setup.sh --skip-brew` (interactive) and, if relevant, `/validate-setup`.
