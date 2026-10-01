---
name: add-tool
description: Checklist for adding a CLI, app, runtime or MCP server to these dotfiles — Brewfile vs mise vs uv, setup wiring, telemetry opt-outs, symlinked config and docs. Use whenever a new tool is being added or an existing one's install method changes.
argument-hint: '[tool name]'
---

Add `$ARGUMENTS` to the dotfiles. Work through every item; say explicitly when one doesn't apply.

1. **Install method** (pick one):
   - macOS app or system CLI → `setup/Brewfile` (`brew`/`cask`/`vscode` line with a trailing `#` comment), installed by `bin/brewpick --all`.
   - Runtime or npm CLI → `tilde/.config/mise/config.toml` `[tools]` (`"npm:<pkg>" = "<major>"`), with a comment explaining the pin. Never `npm install -g`.
   - Python CLI → the Brewfile if Homebrew packages it (e.g. `pipx`, `pre-commit`); otherwise `uv tool install` in `setup/misc.sh`, guarded by `command_exists uv` (`bin/upup` runs `uv tool upgrade --all`).
2. **Setup wiring** (`setup/misc.sh`): only when the tool needs post-install steps (auth, MCP registration via `claude mcp get <name> || claude mcp add --scope user …`, telemetry off). Keep it idempotent and warn — don't fail — when a step can't run.
3. **Telemetry**: if the tool phones home, add its opt-out variable to **both** `setup.sh` and `zsh/env.zsh`, and to `docs/privacy.md`.
4. **Config files**: `$HOME` config goes under `tilde/` at its home-relative path. If the tool rewrites its config via temp-file + rename (breaks symlinks), don't track it — note that in `setup/README.md`.
5. **Upgrades**: confirm `bin/upup` covers it (Homebrew, `mise upgrade` and `uv tool upgrade --all` already do).
6. **Docs**: `setup/README.md` (the section of the script you touched), `README.md` if user-facing, `docs/README.md` if it adds an alias or `bin/` command.
7. **Verify**: `pnpm check`; then tell the user to run `./setup.sh --skip-brew` (interactive) and, if relevant, `/validate-setup`.
