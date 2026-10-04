# Agentic Development System

Install the Amp CLI: `curl -fsSL https://ampcode.com/install.sh | bash`

## Add LLM instructions

[`instructions.md`](instructions.md) holds baseline user-level instructions universal to _any_ project. `setup/symlinks.sh` wires it up for two agents:

- **Amp** reads it as `~/.config/amp/AGENTS.md` — `~/.config/amp` links to `tilde/.config/amp`, whose `AGENTS.md` is a relative link to this file.
- **Codex** (the `codex` cask in the Brewfile) reads it as `~/.codex/AGENTS.md`. Its settings come from `tilde/.codex/config.toml`, which `setup/symlinks.sh` **copies** (never links) into `~/.codex/config.toml` when that file is missing, or when it's still a link from an older setup. Apps rewrite the live file in place to register themselves: NotchBar (Bartender) adds the `[features] codex_hooks = true` line (with its `notchbar-agents-managed-codex-hooks` marker) for its status hooks in `~/.codex/hooks.json`, and Jean adds `[mcp_servers]` entries that carry an access token. Through a link those writes would land in the repo. Later runs leave the live file alone and only warn, listing any tracked line it lacks, so you can add it by hand.

**Claude Code** is installed by `setup/misc.sh`, which also connects CodeGraph, mise's and Serena's MCP servers and three remote docs servers (astro-docs, better-auth, siderolabs-docs) to it (see [setup/README.md](../setup/README.md#misc)). `instructions.md` is _not_ linked into `~/.claude/CLAUDE.md`. Claude Code's own global instructions are rules in [`tilde/.claude/rules/`](../tilde/.claude/rules/), which `setup/symlinks.sh` links one by one into `~/.claude/rules/`.

## Install skills

Follow the [skills repo](https://github.com/jrmatherly/skills) instructions. It's private, and it's also a Claude Code plugin marketplace (`jrmatherly-skills`) that ships two plugins: `jstack` (`/jstack:j-mode`; a fork of pstack by Lauren Tan) and `resume` (22 resume and job-search skills, `/resume:<name>`; a fork of ResumeSkills). Its skills are `coding-standards` and `supabase-prompts` (Supabase's [AI prompts](https://supabase.com/docs/guides/ai-tools/ai-prompts), routed by task). Setup installs both plugins and both skills through `claude-config restore`, below.

## Install plugins

Run `plugins: reload`.

- `block-destructive-git-operations` — lets known-safe git commands through (status, log, diff, add, commit, …) and asks Amp's AI to classify everything else; when it looks destructive (force push, branch deletion, reset, detached HEAD checkout), you're asked to confirm before it runs.

## Claude Code: plugins, settings, skills and catalog

A new Mac gets the same Claude Code setup from `./setup.sh`: `setup/misc.sh` runs `claude-config restore`, then `claude-catalog`.

- [`claude-plugins.txt`](claude-plugins.txt) — marketplaces and user-scope plugins (and which are disabled). Restore adds missing marketplaces and installs missing plugins, refreshing a marketplace that is already on the machine before the first install from it (it may predate the plugin). The private `jrmatherly-skills` marketplace needs GitHub access without a prompt: an SSH key in the agent (this setup's 1Password agent, once `~/.ssh/config` is linked) or a stored HTTPS credential (`gh auth setup-git`, or Git Credential Manager from the Brewfile). `setup/misc.sh` covers a fresh Mac by making `gh` the only github.com credential helper for the restore command, so `gh`'s token is used live and not copied into the keychain. Background auto-update uses the same access and stays quiet when it fails; update by hand with `claude plugin marketplace update jrmatherly-skills`.
- The `supabase` plugin in that list bundles Supabase's two skills (`supabase`, `supabase-postgres-best-practices`) and its [MCP server](https://supabase.com/docs/guides/ai-tools/mcp) (`https://mcp.supabase.com/mcp`) at user scope. The server does nothing until you sign in (`/mcp` → supabase → Authenticate) and pick an organization; after that it can read and write every project in that organization, from every repo. The plugin's URL is fixed, so it has none of the scoping Supabase's guide recommends (`?project_ref=…`, `?read_only=true`). A project that wants that adds its own server in `.mcp.json`, and also turns the plugin's server off for that project in `/mcp`: the two URLs differ, so Claude Code would otherwise connect both. `claude-settings.json` has `permissions.ask` rules for the server's write tools (SQL, migrations, deploys, project and branch changes), so they prompt even in auto mode, as Supabase's guide advises; the names come from that guide, so check them against `/mcp` after signing in and add any write tool it has since gained. Codex doesn't load the plugin and gets the same two skills from `supabase/agent-skills` through `claude-skills.txt`. The Supabase CLI itself is in the Brewfile.
- [`claude-settings.json`](claude-settings.json) — `~/.claude/settings.json` minus the keys tools write themselves (`enabledPlugins`, `extraKnownMarketplaces`, `hooks`), with your home directory as `~`. Secrets stay out: credential helpers (`apiKeyHelper` and the like) are never saved, and of `env` only Claude Code's own switches (`CLAUDE_CODE_*`, `DISABLE_*`, `MAX_*`) are — keep tokens and API keys in `env` on the machine, not in this file. Restore merges it in: values already on the machine win, and permission lists are unioned.
- [`claude-skills.txt`](claude-skills.txt) — user skills installed with the [`skills` CLI](https://github.com/vercel-labs/skills), with their source and agents (`claude-code` → `~/.claude/skills`, `codex` → `~/.agents/skills`). A skill published under a site's `/.well-known/agent-skills` (e.g. `siderolabs`) is saved with the URL as typed (the lock file's `sourceBaseUrl`), since its bare-host `source` fails as a git clone. Restore runs `npx skills add` for each missing one (telemetry off). `claude-config restore skills --update` (run by `upup`) reinstalls all of them for their listed agents, which is how an installed skill picks up upstream changes; the CLI's own `npx skills update` isn't used because it reinstalls with no agent list, so a skill tracked for one agent ends up in all of them.
- The status line script lives in [`tilde/.claude/statusline-command.sh`](../tilde/.claude/statusline-command.sh), linked by `setup/symlinks.sh`; `claude-settings.json` points `statusLine` at it.
- After installing or removing plugins or skills, or changing settings, run `claude-config save` (`upup` does too) and commit the diff. `save` records what this machine has now, so review the diff before committing; it never shrinks a file whose source is missing (a machine that isn't set up yet), it warns and keeps the tracked one. `claude-config restore {plugins|settings|skills} --dry-run` shows what one part would do.
- [`catalog/`](catalog/) generates a catalog of every installed skill, slash command, subagent and MCP server — descriptions, a "which to pick" task guide, usage and per-plugin cleanup status — because the `/` menu shows names only. `claude-catalog` writes `~/.claude/catalog/CATALOG.md` (for AI assistants), `CATALOG-lite.md` (a ~3k-token version) and `catalog.html` (searchable, for you; `claude-catalog --open` rebuilds and opens it). Setup builds it after restoring, and `upup` rebuilds it. Edit [`catalog/curated.toml`](catalog/curated.toml) for task groups, picks, notes and keep/retire decisions; the build exits 1 when it names something that isn't installed. A global rule ([`tilde/.claude/rules/catalog.md`](../tilde/.claude/rules/catalog.md)) points Claude at it.

## References

- [Agent of choice](https://ampcode.com/)
- [AGENTS.md](https://agents.md/)
- [Skills CLI](https://github.com/vercel-labs/skills)
- [Collection of agent skills](https://github.com/jrmatherly/skills)
