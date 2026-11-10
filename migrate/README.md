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

Moves what Homebrew still owns over to mise. Removing the Homebrew program itself is not written yet and comes later, after A6. In order:

1. **mise itself.** When `mise` is Homebrew's copy (under `/opt/homebrew`), the step offers to move it, and nothing below runs until that is done or declined. Homebrew's copy refuses `mise self-update`, so nothing upgrades it. The move runs mise's installer (`curl -fsSL https://mise.run | sh`, to `~/.local/bin/mise`), then `~/.local/bin/mise reshim`, then `brew uninstall mise`, a second reshim, and a check that every shim resolves. It then offers to re-register Claude Code's `mise` MCP server with the new path. The reshim comes before the uninstall because every shim is a link to the mise binary: uninstalling first would leave `node`, `python` and the rest dangling for agent and GUI shells until the reshim. If the installer leaves no working `~/.local/bin/mise`, or a shim still points at Homebrew's mise after the reshim, the step stops with exit 1 and Homebrew's mise is untouched. If `brew uninstall mise` fails, both are installed and a second run finishes. A run that finds mise outside Homebrew with dangling shims offers to rebuild them. Open a new terminal afterwards. Way back: `HOMEBREW_NO_ANALYTICS=1 brew install mise && /opt/homebrew/bin/mise reshim`.
2. **Formulae** need no migration. mise reads `/opt/homebrew`, so a formula Homebrew installed counts as installed and `mise bootstrap packages upgrade` replaces it with the current bottle. Formulae that need repair are listed.
3. **Packages no config declares.** The formulae `mise bootstrap packages prune --manager brew --dry-run` would remove are listed with a reason each: Homebrew's mise, a keg whose tool moved to mise `[tools]`, installed by hand, or a dependency. The script never prunes. mise keeps a formula that any config it has ever tracked still declares (`~/.local/state/mise/tracked-configs`), so the list can be shorter than what is really undeclared; the step prints that count. For each formula installed by hand, and each folder in `Caskroom` that no declared cask names, it offers to add a line to `tilde/.config/mise/config.local.toml` (`"brew:<name>" = "latest"` or `"brew-cask:<token>" = "latest"`, with the tap in front when it is not Homebrew's own). That file is gitignored and belongs to this Mac only; mise merges its `[bootstrap.packages]` with the tracked one, so a declared package survives a prune and a declared cask joins the lists below on the next run. The file is copied to the backup folder before the first write.
4. **Declared casks that are not installed** (a reinstall that stopped half way) get their command: `mise bootstrap packages apply brew-cask:<token>`.
5. **Homebrew casks that do not update themselves** are listed with version and kind (`app`, `pkg` or `other`). Nothing upgrades these: mise leaves a cask Homebrew installed alone.
6. **Homebrew casks that update themselves** are listed the same way. Moving one gains no upgrades. They are offered because Homebrew can only be removed once no cask is still Homebrew's, so a cask you decline keeps Homebrew installed.
7. Without `brew` on `PATH` the step only lists, and stops here.
8. Without network (`curl -fsI --max-time 5 https://formulae.brew.sh/` fails) it moves neither mise nor any cask.
9. **Reinstalling.** For each cask in the first list and then the second, it asks, and on yes runs `brew uninstall --cask <token>` then `mise bootstrap packages apply --yes brew-cask:<token>`, and checks that mise reports the cask `installed` and `managed_by: mise` and that its app bundles exist. A cask whose app is running is skipped with a line naming the app. The app bundle is replaced and not copied to the backup folder (size): the backup records token and version in `casks.tsv`, and the way back is `HOMEBREW_NO_ANALYTICS=1 brew install --cask <token>`. macOS can drop the privacy permissions of a replaced app, so check System Settings > Privacy & Security afterwards. A pkg cask (`dotnet-sdk`, `git-credential-manager`) asks for the password twice, once from each tool. When the apply or the check fails the cask is left uninstalled: the step prints both ways to get it back (the apply command again, or the `brew install --cask` line), exits 1 and touches no further cask.
10. **Leftovers.** Folders in `Cellar` that hold only mise's `.mise-staging.lock` (left when `brew uninstall` removes a formula mise installed) are listed and, on yes, moved to the backup folder.

`mise bootstrap packages status --json` is the step's source for the lists. mise fetches a tap cask's metadata from GitHub to answer it, so with a tap cask declared the step stops after the mise question when offline.

### dotfiles

Not written yet. Lands with phase A5.

### setup

Not written yet. Lands with phase A6.

## Restoring

Every item a step replaces is moved or copied to `~/.dotfiles-migration-backup/<timestamp>/files/`, at its original path under that folder. `RESTORE.txt` in the same folder lists one command per item that puts it back. Delete the folder by hand once the Mac works.
