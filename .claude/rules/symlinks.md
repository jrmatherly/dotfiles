---
paths:
  - 'setup/symlinks.sh'
  - 'tilde/**'
  - 'mole/**'
---

# Symlinks

`setup/symlinks.sh` links each top-level item of `tilde/` into `~`, and each child of `tilde/.config/` individually (it holds app-written state next to tracked files).

- `tilde/.claude` is special-cased: `~/.claude/rules` stays a real directory and each tracked `tilde/.claude/rules/*.md` is symlinked into it individually, so machine-local rules can sit alongside (an older whole-directory link is migrated); top-level files in `tilde/.claude` (e.g. `statusline-command.sh`) are linked into `~/.claude` too.
- `.codex` and `.ssh` are excluded and handled specially: only `.ssh/config` is linked. `tilde/README.md` itself is not linked.
- Targets outside `$HOME` (VS Code `User`, lazydocker, gpg, Firefox `user.js` as a hard link) need an explicit `symlink_file` call.
- So do Mole's two whitelists (`install_mole_config`): `mole/<name>` or, when present, the gitignored `mole/<name>.local` is linked as `~/.config/mole/<name>` (Mole writes other files in that folder), and a link to the other candidate is replaced without a prompt.
- `symlink_file` never overwrites silently; it prompts skip/overwrite/backup.
