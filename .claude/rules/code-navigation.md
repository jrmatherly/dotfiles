# Which code tool to use here

- **Understand / locate** (what calls what, where is X): CodeGraph first (`codegraph_explore`), per the global instructions.
- **Read or edit a symbol in a `*.sh` file**: Serena's symbol tools (`get_symbols_overview`, `find_symbol`, `replace_symbol_body`, `find_referencing_symbols`).
- **Everything else** — `bin/` scripts (no extension, so Serena's language server doesn't see them), `zsh/*.zsh`, `tilde/**`, Markdown, JSON/TOML/YAML: native Read and Edit (or Serena's `replace_content`). Serena's "Edit is forbidden for code files" applies only to files its language server serves.
