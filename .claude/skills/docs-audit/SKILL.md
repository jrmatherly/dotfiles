---
name: docs-audit
description: Audit this repo's Markdown docs and agent instructions against the scripts, configs, installed tools and vendor docs they describe, and report mismatches (never edits). Use after changing setup scripts, the Brewfile, mise config or bin/ scripts, or before a docs pass.
argument-hint: '[doc path or directory; default: all docs]'
context: fork
agent: docs-auditor
background: false
---

Audit these docs: $ARGUMENTS

If no path was given, audit:

- `README.md`, `setup/README.md`, `agents/README.md`, `tilde/README.md`, every other `*/README.md` outside `node_modules/` and `obsidian/.obsidian/plugins/`
- `docs/**/*.md` except `docs/superpowers/` (plans and specs argue from a point in time; they are not documentation of the current tree)
- the agent instructions: every `CLAUDE.md`, `agents/instructions.md`, `.claude/rules/*.md`, `tilde/.claude/rules/*.md`, `.claude/skills/*/SKILL.md`, `.claude/agents/*.md` and `.serena/memories/*.md`

Every claim gets a verdict. A claim about the repo is checked against the file. A claim about this machine (an installed version, a count of commands or tools, a catalog size, a daemon's state, a file outside the repo) is checked by running the read-only command that reads it. A claim about a vendor (a GUI app's shortcuts, Renovate's behaviour, a Homebrew formula's caveats) is checked against the vendor's documentation with WebFetch. A claim is "Unverifiable" only when none of the three can settle it, and then the report names what would.

Recently changed files, to check first:

!`git log --since=14.days --name-only --format= | grep . | sort -u | head -80 || true`
