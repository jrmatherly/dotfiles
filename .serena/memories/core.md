# dotfiles — core

Project context (commands, architecture, conventions, completion checks) lives in `CLAUDE.md`, `bin/CLAUDE.md` and `.claude/rules/` — read those, don't duplicate them here.

## Serena-specific

- Language server: bash-language-server, via `FilenameMatcher(".sh", ".bash")` — symbol tools only see `setup.sh`, `setup/*.sh` and other `*.sh` files.
- Invisible to symbol tools: every script in `bin/` (extensionless, shebang only), `zsh/*.zsh` and `tilde/.zsh*`, configs. Use `replace_content` / native Read+Edit there (upstream oraios/serena#2020).
