---
paths:
  - 'zsh/**'
  - 'tilde/.zshrc'
  - 'tilde/.zshenv'
  - 'tilde/.zprofile'
  - 'bin/lib/test-shell'
---

# zsh config

- **Load order** (`tilde/.zshrc`): `path` → `env` → `options` → `aliases` → `completion` → `key-bindings` → plugins → `init.zsh` (mise shims, then full `mise activate` deferred to the first prompt; zsh plugin formulae, fast-theme) → `~/.zsh.local` → `override-env.zsh`. `tilde/.zprofile` activates mise shims for GUI apps.
- **Overrides** (`zsh/override-env.zsh`, sourced by `tilde/.zshenv` and again in `tilde/.zshrc` right after `~/.zsh.local`): exports of the `[env]` keys in mise's `config.override.toml`, `config.local.toml` (machine-scoped settings) and each profile's `config.rotm-p-<name>.override.toml`, read from a cache under `~/.cache/dotfiles/` named after the override file's path. The values come from mise, so only the active profile's are exported. mise runs only when one of those files or `miserc.local.toml` is newer than the cache, so a fresh start runs no process. It is sourced twice because `env.zsh` and `~/.zsh.local` are seeds that export after `.zshenv`.
- **Why mise activation is deferred**: `zsh/init.zsh` puts the shims back ahead of `/opt/homebrew/bin` (a formula's own `node`) and runs full `mise activate` from a one-shot precmd hook, so a shell that never prompts keeps shims only. Claude Desktop reads PATH from such an interactive login shell (measured 2026-10-27: its PATH matched `zsh -ilc`) and Claude Code keeps that PATH ahead of everything in its shell snapshot, so activating at startup pinned every global Node for whole agent sessions.
- **Agent shells** (`CLAUDECODE` set): `zsh/aliases.zsh` drops the built-in overrides (`cat`→bat, `ls`→eza, `find`→fd, `-i` cp/mv/rm, `grep -i`, …) and the `git` wrapper (cd after clone), `zsh/init.zsh` keeps the builtin `cd` (zoxide's `z`/`zi` only, no `--cmd cd`), `zsh/env.zsh` skips `RIPGREP_CONFIG_PATH` (stock `rg`) and `zsh/options.zsh` turns `clobber` back on and autocorrect off.
