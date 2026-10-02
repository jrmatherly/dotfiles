---
paths:
  - 'vscode/**'
---

# VS Code settings

- `vscode/User/settings.json` is generated and gitignored: edit `vscode/User/settings.json.j2` (minijinja; fonts in `vscode/presets.toml`) and run `bin/vscode-settings`. The template sees only `preset`, `presets` and `home` (no `--env`, so no environment variable can be rendered into the file). Values are unquoted `{{ … }}` (JSON auto-escaping adds the quotes); VS Code's own `${…}` placeholders pass through untouched.
- `vscode/User` is symlinked as VS Code's live user dir; VS Code rewrites these files itself. Keep them byte-identical to what VS Code writes: JSONC with no trailing commas (`vscode/User/.prettierrc.yaml`, which both the repo path and VS Code's `~/Library/Application Support/Code/User` path resolve), existing key order and grouping.
- Don't add entries that VS Code rewrites or strips on startup; don't re-add defaults — except a value an extension writes back whenever it's missing: pin it with a comment naming the writer (Mintlify's `workbench.colorCustomizations`, the Python extension's `python.languageServer`), or the repo gets dirtied on every startup.
