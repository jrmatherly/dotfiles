# Global rules (`~/.claude/rules/`)

Tracked in the dotfiles repo (`tilde/.claude/rules/`). `~/.claude/CLAUDE.md` is not tracked: `codegraph install` rewrites it.

- **Serena MCP** — launch invariants for Serena in Claude Code (`claude-code` context, plugin disabled, one user-scoped registration, `--project-from-cwd` on so skills must not call `activate_project`). Read `~/.claude/rules/serena.md` before changing any Serena MCP registration, re-enabling the `serena@claude-plugins-official` plugin, or editing a `.serena/` config. It also auto-loads on `.serena/**` edits.
- **Verify first** — `verify-first.md`: never assume or guess; research, investigate, validate and confirm before stating or building on anything, and ask when unclear.
- **Tool checks** — `tool-checks.md`: verify with `command -v` before claiming a CLI isn't installed; a failed `npx --no-install` proves nothing.
- **Catalog** — `catalog.md`: where the catalog of installed skills, commands, subagents and MCP servers lives, and how to rebuild it.
- **Browser checks** — `chrome-devtools.md`: use the chrome-devtools MCP for UI reviews too; `emulate` for phone widths, where screenshots can be saved, reproduce at the reporter's viewport, re-run the motivating metric, close subagent pages.
- **Handoffs** — `handoffs.md`: an open question names the check that settles it; inherited workaround lines are verified or dropped.
- **jstack models** — `jstack-models.md`: which model each jstack role runs on (fable for judgment and synthesis, opus for code, sonnet for exploration). Written by `/jstack:setup-jstack`; re-run it to change the budget.
