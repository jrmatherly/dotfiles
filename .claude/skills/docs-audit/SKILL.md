---
name: docs-audit
description: Audit this repo's Markdown docs against the scripts and configs they describe and report mismatches (read-only). Use after changing setup scripts, the Brewfile, mise config or bin/ scripts, or before a docs pass.
argument-hint: '[doc path or directory; default: all docs]'
context: fork
agent: docs-auditor
background: false
---

Audit these docs: $ARGUMENTS

If no path was given, audit `README.md`, `setup/README.md`, `agents/README.md`, `tilde/README.md`, every other `*/README.md` outside `node_modules/`, `obsidian/` and `ql-plugins/`, and `docs/**/*.md` except `docs/superpowers/` (implementation plans, not documentation).

Recently changed files, to check first:

!`git log --since=30.days --name-only --format= | sort -u | head -50 || true`
