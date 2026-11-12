---
name: add-tool
description: Checklist for adding a CLI, app, runtime, VS Code extension or MCP server to these dotfiles: mise package vs mise tool vs uv, taps, setup wiring, telemetry opt-outs, symlinked config and docs. Use whenever a tool is being added ("add X", "we need X installed", a `brew install …` command, a VS Code Marketplace or install-docs link) or an existing one's install method changes.
argument-hint: '[tool name]'
---

Add `$ARGUMENTS` to the dotfiles. Work through every item; say explicitly when one doesn't apply.

0. **Identify the exact tool**: read the linked install docs. If a vendor ships a new and a legacy CLI (e.g. Sentry's `sentry` vs `sentry-cli`), name which one and say so.
1. **Install method** (pick one):
   - macOS app or system CLI: a `"brew-cask:<cask>"` or `"brew:<formula>"` line in `tilde/.config/mise/conf.d/30-packages.toml`, value `"latest"` (mise installs no pinned versions), with a trailing `#` comment. Then update the counts in `bin/lib/test-packages`.
   - VS Code extension: a `"vscode:<publisher.id>"` line in the matching extension section of the same file.
   - A CLI mise's registry carries, a runtime or an npm CLI: `[tools]` in `tilde/.config/mise/config.toml` (`"npm:<pkg>" = "<major>"`), with a comment explaining the pin. Prefer this to a third-party tap. Never `npm install -g`. Add the line and run its `mise install` together: a fuzzy version that is declared but not installed makes every mise call ask GitHub and warn when rate limited. Rust is the exception: the system toolchain is the `brew:rustup` package; only a project that pins another version goes through mise's rust backend.
   - Python CLI: a `brew:` line if a formula exists (e.g. `pipx`, `pre-commit`); otherwise `uv tool install` in `setup/misc.sh`, guarded by `command_exists uv` (`bin/sysup` runs `uv tool upgrade --all`).
2. **Package list specifics**:
   - Third-party tap: write the package `owner/tap/name` and add the tap under `[bootstrap.brew.taps]` (at most 5). The taps table is a reviewed list, not a trust boundary. mise resolves an undeclared `owner/tap` at its default GitHub URL, so only `bin/lib/test-packages` enforces the list, and `mise bootstrap packages apply brew:owner/tap/x` typed by hand bypasses it. Read the formula before you run that.
   - Place it in the matching section, alphabetical by package name; keep the one-line `#` comment style. Add a short comment block above it only for a non-obvious why.
3. **Install it now and check**: ask the user before any apply (Claude Code prompts for every `mise bootstrap` command, the dry run too). `mise bootstrap packages apply <key> --dry-run`, then without `--dry-run`, then `<tool> --version`. Read the formula's `post_install_steps` at `formulae.brew.sh/api/formula/<name>.json` and report anything it writes outside `/opt/homebrew` (shell completions, agent skills, dotfiles). mise links no man pages.
4. **Setup wiring** (`setup/misc.sh`): only when the tool needs post-install steps (MCP registration via `claude mcp get <name> || claude mcp add --scope user …`, telemetry off). Per-account logins (`gh auth`, `sentry auth`) are left to the user unless they ask. Keep it idempotent, and warn instead of failing when a step can't run.
5. **Telemetry**: check the tool's docs for an opt-out. If it honours `DO_NOT_TRACK` (already exported by `zsh/env.zsh`), just name it in `docs/privacy.md`. Otherwise add its variable to `zsh/env.zsh` and `docs/privacy.md`, plus `setup.sh` and `README.md`'s opt-out list if setup itself runs the tool.
6. **Config files**: `$HOME` config goes under `tilde/` at its home-relative path, with a `[dotfiles]` entry in `tilde/.config/mise/conf.d/40-dotfiles.toml` (`pnpm check` fails without it). If the tool rewrites its config via temp-file + rename (breaks symlinks), don't track it, and note that in `setup/README.md`.
7. **Upgrades**: confirm `bin/sysup` covers it (`mise bootstrap packages upgrade`, `mise upgrade` and `uv tool upgrade --all` already do; VS Code updates its own extensions).
8. **Docs**: `setup/README.md` (the section of the script you touched), `README.md` if user-facing, `docs/README.md` if it adds an alias or `bin/` command. A plain package entry needs no README line (they don't list packages).
9. **Verify**: `pnpm check` (it runs `bin/lib/test-packages`); then, if setup scripts changed, tell the user to run `./setup.sh` (interactive) and, if relevant, `/validate-setup`.
