# Global rules (`~/.claude/rules/`)

Tracked in the dotfiles repo (`tilde/.claude/rules/`). `~/.claude/CLAUDE.md` is not tracked: `codegraph install` rewrites it.

- **Serena MCP** — launch invariants for Serena in Claude Code (`claude-code` context, plugin disabled, one user-scoped registration, `--project-from-cwd` on so skills must not call `activate_project`). Read `~/.claude/rules/serena.md` before changing any Serena MCP registration, re-enabling the `serena@claude-plugins-official` plugin, or editing a `.serena/` config. It also auto-loads on `.serena/**` edits.
- **Tool checks** — `tool-checks.md`: verify with `command -v` before claiming a CLI isn't installed; a failed `npx --no-install` proves nothing.
