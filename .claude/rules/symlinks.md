---
paths:
  - 'tilde/.config/mise/conf.d/40-dotfiles.toml'
  - 'setup/dotfiles-extras.sh'
  - 'tilde/**'
  - 'mole/**'
---

# Symlinks

`conf.d/40-dotfiles.toml` has one `[dotfiles]` entry per top-level file of `tilde/` and per child of `tilde/.config/`. A new one needs an entry, and `bin/lib/test-dotfiles` fails without it. Sources are written `~/dotfiles/…`: `source` is not a template, and a relative source resolves from `~/.config/mise/conf.d`, not from the clone.

- `~/.claude/rules` is the one `symlink-each` entry: a real directory with a link per tracked rule, so a new rule needs no entry. Each skill folder and `statusline-command.sh` has its own entry. Never add a `"~"` walk entry: before its first apply mise searches all of `$HOME`.
- `~/.ssh` and `~/.gnupg` are permissions-only entries (`0700`) beside the linked file. `~/.codex/config.toml` is a `merge = "missing"` edit: created at `0600` when missing, then only keys the live file lacks are added. Setup's `codex mcp add`, Hindsight and Codex write that file, so it is never linked.
- What mise cannot express is in `setup/dotfiles-extras.sh`: Firefox's three hard links, `cot` and `code` in `/usr/local/bin` (`[bootstrap.files]` only copies, and a missing source fails the whole apply), the git identity prompt. `setup.sh` runs it after the apply, never as a mise hook: a hook runs on every `mise dotfiles apply`.
- Mole's two whitelists link to the shared `mole/<name>`. A Mac's `mole/<name>.local` is linked by repeating the entry in the gitignored `config.local.toml`, which replaces the tracked entry.
- A real file in the way stops the whole apply and nothing is written. `--force` replaces with no backup, so no script passes it. A link that points elsewhere is repointed silently.
