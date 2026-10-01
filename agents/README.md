# Agentic Development System

Install the Amp CLI: `curl -fsSL https://ampcode.com/install.sh | bash`

## Add LLM instructions

[`instructions.md`](instructions.md) holds baseline user-level instructions universal to _any_ project. `setup/symlinks.sh` wires it up for two agents:

- **Amp** reads it as `~/.config/amp/AGENTS.md` — `~/.config/amp` links to `tilde/.config/amp`, whose `AGENTS.md` is a relative link to this file.
- **Codex** (the `codex` cask in the Brewfile) reads it as `~/.codex/AGENTS.md`, linked alongside `tilde/.codex/config.toml`. That config's `[features] codex_hooks = true` line (with its `notchbar-agents-managed-codex-hooks` marker) belongs to NotchBar (Bartender), which adds it for its Codex status hooks in `~/.codex/hooks.json`. It's tracked so the live file matches the repo. If NotchBar rewrites `~/.codex/config.toml` again, it replaces the symlink with a regular file and `setup/symlinks.sh` will ask about it.

**Claude Code** is installed by `setup/misc.sh`, which also connects CodeGraph and mise's MCP server to it (see [setup/README.md](../setup/README.md#misc)). `instructions.md` is _not_ linked into `~/.claude/CLAUDE.md`. Claude Code's own global instructions are rules in [`tilde/.claude/rules/`](../tilde/.claude/rules/), which `setup/symlinks.sh` links one by one into `~/.claude/rules/`.

## Install skills

Follow the [skills repo](https://github.com/jrmatherly/skills) instructions.

## Install plugins

Run `plugins: reload`.

- `block-destructive-git-operations` — lets known-safe git commands through (status, log, diff, add, commit, …) and asks Amp's AI to classify everything else; when it looks destructive (force push, branch deletion, reset, detached HEAD checkout), you're asked to confirm before it runs.

## Claude Code: plugins, settings, skills and catalog

A new Mac gets the same Claude Code setup from `./setup.sh`: `setup/misc.sh` runs `claude-config restore`, then `claude-catalog`.

- [`claude-plugins.txt`](claude-plugins.txt) — marketplaces and user-scope plugins (and which are disabled). Restore adds missing marketplaces and installs missing plugins.
- [`claude-settings.json`](claude-settings.json) — `~/.claude/settings.json` minus the keys tools write themselves (`enabledPlugins`, `extraKnownMarketplaces`, `hooks`), with your home directory as `~`. Secrets stay out: credential helpers (`apiKeyHelper` and the like) are never saved, and of `env` only Claude Code's own switches (`CLAUDE_CODE_*`, `DISABLE_*`, `MAX_*`) are — keep tokens and API keys in `env` on the machine, not in this file. Restore merges it in: values already on the machine win, and permission lists are unioned.
- [`claude-skills.txt`](claude-skills.txt) — user skills installed with the [`skills` CLI](https://github.com/vercel-labs/skills), with their source and agents (`claude-code` → `~/.claude/skills`, `codex` → `~/.agents/skills`). Restore runs `npx skills add` for each missing one (telemetry off).
- The status line script lives in [`tilde/.claude/statusline-command.sh`](../tilde/.claude/statusline-command.sh), linked by `setup/symlinks.sh`; `claude-settings.json` points `statusLine` at it.
- After installing or removing plugins or skills, or changing settings, run `claude-config save` (`upup` does too) and commit the diff. `save` records what this machine has now, so review the diff before committing; it never shrinks a file whose source is missing (a machine that isn't set up yet), it warns and keeps the tracked one. `claude-config restore {plugins|settings|skills} --dry-run` shows what one part would do.
- [`catalog/`](catalog/) generates a catalog of every installed skill, slash command, subagent and MCP server — descriptions, a "which to pick" task guide, usage and per-plugin cleanup status — because the `/` menu shows names only. `claude-catalog` writes `~/.claude/catalog/CATALOG.md` (for AI assistants), `CATALOG-lite.md` (a ~3k-token version) and `catalog.html` (searchable, for you; `claude-catalog --open` rebuilds and opens it). Setup builds it after restoring, and `upup` rebuilds it. Edit [`catalog/curated.toml`](catalog/curated.toml) for task groups, picks, notes and keep/retire decisions; the build exits 1 when it names something that isn't installed. A global rule ([`tilde/.claude/rules/catalog.md`](../tilde/.claude/rules/catalog.md)) points Claude at it.

## References

- [Agent of choice](https://ampcode.com/)
- [AGENTS.md](https://agents.md/)
- [Skills CLI](https://github.com/vercel-labs/skills)
- [Collection of agent skills](https://github.com/jrmatherly/skills)
