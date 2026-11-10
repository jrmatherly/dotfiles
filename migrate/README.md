# Migrating from the old setup

`legacy-to-mise` moves a Mac that was set up from this repo before the mise-first setup (the bash scripts and the Brewfile) onto the new layout. A Mac set up with the current `setup.sh` never needs it.

It is temporary. Delete `migrate/` on or after 2027-02-28: from that date `bin/lib/test-conventions`, and so `pnpm check`, fails while `migrate/` exists. Its self-check is `bin/lib/test-migrate`, which runs every step against a scratch `HOME` with fake `brew`, `mise` and `claude`.

## Usage

```text
migrate/legacy-to-mise [--step <env|macos|packages|dotfiles|setup>] [--dry-run] [-h|--help]
0  done, or nothing to migrate
1  a step failed
2  unknown option or step name
3  refused: mise older than 2026.11.5, ~/.config/mise is not this clone's, or the named step's marker file is absent
```

With no `--step` it runs every step whose phase is in this checkout, in the order above, and prints `skipped <name>: its phase is not in this checkout` for the rest. `--dry-run` prints each change and each question without making or asking any. Every change asks first, and a closed stdin answers no.

A step's phase is present when its marker file is in the checkout: `zsh/override-env.zsh` (`env`), and `tilde/.config/mise/conf.d/20-macos.toml`, `30-packages.toml`, `40-dotfiles.toml` and `50-bootstrap.toml` (`macos`, `packages`, `dotfiles`, `setup`).

## Steps

Each step below prints `nothing to migrate yet` until its own change lands.

### env

Not written yet. Its phases, A1 and A2, have landed.

### macos

Not written yet. Its phase, A3, has landed.

### packages

Not written yet. Its phase, A4, has landed. Removing the Homebrew program comes later, after A6.

### dotfiles

Not written yet. Lands with phase A5.

### setup

Not written yet. Lands with phase A6.

## Restoring

Every item a step replaces is moved or copied to `~/.dotfiles-migration-backup/<timestamp>/files/`, at its original path under that folder. `RESTORE.txt` in the same folder lists one command per item that puts it back. Delete the folder by hand once the Mac works.
