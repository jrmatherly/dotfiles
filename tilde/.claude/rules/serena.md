---
paths:
  - '**/.serena/**'
  - '**/serena_config.yml'
---

# Serena MCP — Claude Code launch invariants (global)

How Serena is wired into Claude Code. The `serena` binary lives at `~/.local/bin/serena` (`uv tool install -p 3.13 serena-agent`, upgrade with `uv tool upgrade serena-agent` — the docs' only documented install method). **Verify the live state before changing** — `claude mcp get serena`.

## The one correct launch

Serena MUST run in the **`claude-code` context**, from the local binary, registered **once** at user scope:

```bash
claude mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd
```

- The official **`serena@claude-plugins-official` plugin is disabled** (`~/.claude/settings.json`). Its `.mcp.json` launches `uvx --from git+…/serena start-mcp-server` — **no `--context`, no project flag, floating `main`**. That gives the wrong (`desktop-app`) context — Serena's own file/shell tools (`read_file`/`create_text_file`/`execute_shell_command`/`find_file`/`list_dir`/`search_for_pattern`) stay active, cluttering the tool list and biasing the model toward them over native Read/Write/Bash/Grep/Glob — plus a non-reproducible, slow-starting build (floating `main`, re-synced each launch). Do **not** re-enable it. The plugin ships _only_ this MCP (no skills/commands), so disabling it loses nothing.
- One registration only. Tools are `mcp__serena__*`. If you ever see `mcp__plugin_serena_serena__*`, the plugin got re-enabled → a duplicate server is running; disable the plugin again.

## What `claude-code` context changes (don't fight it)

`excluded_tools` (duplicates of native Claude Code tools — gone, use native instead): `read_file`→Read · `create_text_file`→Write · `execute_shell_command`→Bash · `search_for_pattern`/`find_file`/`list_dir`→Grep/Glob.

**Kept:** symbolic tools (`find_symbol`, `get_symbols_overview`, `find_referencing_symbols`, the `*_symbol` editors) + memory tools (`read_memory`/`write_memory`/`list_memories`) + `get_current_config`. (`activate_project` is in the context's tool set but disabled at runtime because `--project-from-cwd` always supplies a project.) Symbolic tools only pay off where a language server exists (the context prompt forbids Read/Edit on code files in favor of them) — for LSP-less repos (Bicep/XML/JSON), navigate with native Grep/Glob/Read, edit with Edit.

## `--project-from-cwd` is ON (since 2026-09-03; matches the Serena docs' Claude Code recipe)

The flag auto-activates the nearest ancestor with `.serena/project.yml` or `.git` at launch, so one user-scope registration serves every repo on this machine. Because the `claude-code` context sets `single_project: true`, **`activate_project` is disabled whenever a project is supplied at startup** — so no skill or workflow may call it. The ai-hub-gateway `/session-primer` was edited accordingly (it now only reads memories; the explicit activation call was removed). It also removes the race where memory reads issued alongside an explicit `activate_project` failed with "No active project". If a skill ever needs `activate_project` again, the trade is one-for-one: drop the flag from the registration AND restore the explicit call.

## Hooks (`serena-hooks`) are deliberately NOT installed

The docs recommend `serena-hooks remind/activate/auto-approve/cleanup` in `~/.claude/settings.json`, marked alpha and opt-in. Skipped: `remind` nags toward symbolic tools after consecutive Read/Grep calls, which is wrong for LSP-less repos (Bicep/XML); `activate` is redundant with `--project-from-cwd`. Revisit for Python-heavy repos.

## Trusted projects stay empty (`trusted_project_path_patterns: []`)

In `~/.serena/serena_config.yml` (machine state Serena rewrites itself, so it's not tracked). `[]` is the shipped template value (trust arrived in v1.6.0) — it's deliberate, not a gap. Trust only unlocks a project's own `activation_command` (a shell command run in the repo on every activation) and `ls_specific_settings`. With `--project-from-cwd` auto-activating, trusting `~/dev/**` would let any cloned repo run code when Claude Code opens there. No repo here sets either field.

If one ever needs it, add that repo's **exact absolute root** (e.g. `/Users/you/dev/repo`): `~` isn't expanded, and `<root>/**` doesn't match the root itself ([oraios/serena#2001](https://github.com/oraios/serena/issues/2001)). Never `**`. Takes effect on the next Claude Code restart.

## Verify after any change

`claude mcp get serena` → Args `start-mcp-server --context claude-code --project-from-cwd`, **Connected**. In session: `get_current_config` → context `claude-code`, project active, the excluded tools absent. Changes take effect on next Claude Code restart (MCP + plugin enable/disable load at startup).
