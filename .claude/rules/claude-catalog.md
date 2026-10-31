---
paths:
  - 'bin/claude-catalog'
  - 'agents/catalog/**'
---

# Claude catalog

- `bin/claude-catalog` builds `~/.claude/catalog/` through `agents/catalog/build_catalog.py`, run with mise's Python 3.11+ (`tomllib`; system python3 is 3.9).
- Hand-edited notes live in `agents/catalog/curated.toml`. The script exits 1 if it names something not installed, except an `[mcp.*]` server (MCP registration is per machine) or a claude.ai skill (synced per organization), which only warn.
- `catalog_template.html` is the HTML shell. The tracked global rule `tilde/.claude/rules/catalog.md` points Claude at the catalog.
