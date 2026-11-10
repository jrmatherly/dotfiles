---
paths:
  - 'bin/claude-catalog'
  - 'agents/catalog/**'
---

# Claude catalog

- `bin/claude-catalog` builds `~/.claude/catalog/` through `agents/catalog/build_catalog.py`, run with mise's Python 3.11+ (`tomllib`; system python3 is 3.9).
- Hand-edited notes live in `agents/catalog/curated.toml`. The script exits 1 if it names something not installed, except an `[mcp.*]` server (MCP registration is per machine) or a claude.ai skill (synced per organization), which only warn.
- It also writes `catalog.json`, the only thing `bin/claude-stack` (`agents/catalog/stack.py`) reads from it. `[stack.signals]` in `curated.toml` names the plugins `claude-stack` may turn off per project: a plugin that owns a task-guide pick can't be listed (lint fails), and a hooks-only one shouldn't be, because the usage evidence can't see hooks. Don't reword `main`'s `wrote ...`, `added:` or `removed:` lines: `bin/sysup` parses them.
- `catalog_template.html` is the HTML shell. The tracked global rule `tilde/.claude/rules/catalog.md` points Claude at the catalog.
