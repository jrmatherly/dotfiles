---
paths:
  - 'vscode/**'
---

# VS Code settings

- `vscode/User` is symlinked as VS Code's live user dir; VS Code rewrites these files itself. Keep them byte-identical to what VS Code writes: JSONC with no trailing commas (`vscode/User/.prettierrc.yaml`, which both the repo path and VS Code's `~/Library/Application Support/Code/User` path resolve), existing key order and grouping.
- Don't add entries that VS Code rewrites or strips on startup; don't re-add defaults — except a value an extension writes back whenever it's missing: pin it with a comment naming the writer (Mintlify's `workbench.colorCustomizations`, the Python extension's `python.languageServer`), or the repo gets dirtied on every startup.
