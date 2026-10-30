# claude-catalog

`bin/claude-catalog` builds a catalog of every installed Claude Code skill, slash command, subagent and MCP server, because the `/` menu shows names only. It writes `~/.claude/catalog/CATALOG.md` for AI assistants, `CATALOG-lite.md` as a short version to load up front, and `catalog.html`, a searchable page for you. `setup/misc.sh` builds it after `claude-config restore`, and `upup` rebuilds it.

## Summary

- Rebuild after installing, updating or removing plugins or skills: `claude-catalog` (`upup` does it too).
- `claude-catalog --open` rebuilds and opens `catalog.html`.
- The hand-written half lives in `agents/catalog/curated.toml`: task groups, the recommended pick per group, notes, and keep or retire decisions per plugin. The build exits 1 when that file names something that is not installed, except an MCP server (registration is per machine) or an `anthropic-skills:*` skill (synced per claude.ai account), which only warn.
- A global rule, `tilde/.claude/rules/catalog.md`, tells Claude to consult the catalog when choosing a tool.

## Commands

| Command                      | What it does                      |
| ---------------------------- | --------------------------------- |
| `claude-catalog`             | Rebuild into `~/.claude/catalog/` |
| `claude-catalog --out <dir>` | Build somewhere else              |
| `claude-catalog --open`      | Rebuild, then open `catalog.html` |

## What goes into it

The generator, `agents/catalog/build_catalog.py`, scans:

- installed plugins from `~/.claude/plugins/installed_plugins.json`, their manifests and the marketplace entries, collecting skills, commands, agents and MCP servers per plugin, with the enabled flag from `settings.json`;
- user skills, commands and agents under `~/.claude`, the claude.ai skills synced for the signed-in account (`~/.claude/skills/synced/`, and Claude Desktop's copy under `~/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/<org>/<account>/`), and user- and project-scope MCP servers from `~/.claude.json`;
- usage counters Claude Code keeps in `~/.claude.json` (`pluginUsage`, `skillUsage`), undocumented keys that only lower confidence when they vanish;
- each plugin's always-on context cost from `claude plugin details`, cached per version in the output folder, with an estimate for components `details` does not count.

From `curated.toml` it adds the task guide and marks each item recommended, alternative, duplicate, internal, retired, grouped or ungrouped, and flags plugins to review when they are unused, have no recommended pick, and are costly or mostly redundant. The thresholds are the `[cleanup]` table in `curated.toml`.

## Files

| Path | Role |
| --- | --- |
| `agents/catalog/build_catalog.py` | The generator; needs Python 3.11+ (`tomllib`), so the script runs it through mise's Python |
| `agents/catalog/curated.toml` | Groups, picks, notes, retire and duplicate decisions, cleanup thresholds |
| `agents/catalog/catalog_template.html` | The HTML shell |
| `agents/catalog/test_build_catalog.py` | Status and cleanup rules; run by `pnpm check` |
| `~/.claude/catalog/` | Output: `CATALOG.md`, `CATALOG-lite.md`, `catalog.html`, the cost cache and the previous build's item list for the "new since" section |

See also `help claude-config` and [`agents/README.md`](../agents/README.md).
