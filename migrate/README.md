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

Turns the `~/.zsh.local` exports of registered settings into mise overrides. It never edits `~/.zsh.local`.

The registered keys are those of every `[[setting]]` in `settings/registry.toml` with `kind = "env"` whose `access` is not `"ro"`. Without the registry the step refuses with exit 3. With no `~/.zsh.local`, or one that exports neither a registered key nor a retired name, it prints `nothing to migrate`.

A value is read as text from the last `export KEY=` line, never by running the file. Three forms are accepted, each optionally followed by spaces and a `# comment`: `'…'` with no `'` inside, `"…"` with none of `"`, `$`, `` ` `` or `\` inside, and a plain word of `A-Z a-z 0-9 _ . / : @ % + , = ~ -` that does not start with `~`. A value holding `$` is refused in every form, because mise expands `$` in `[env]` values. A value in any other form is skipped with the command to set it by hand: `mise set --override KEY=<value>`.

For each registered key with an export it reads the current override (`mise set --file ~/.config/mise/config.override.toml KEY`). A matching override prints `KEY: already an override`. With none it asks to make the value an override. With a different one it prints both values and asks to replace it. The override file is copied to the backup folder before the first write, and each write is `mise set --override "KEY=VALUE"`, run from `$HOME`.

It names exports the new setup no longer reads, once the phase that retired them is here: `DOTFILES_MACOS_YES` and `DOTFILES_MACOS_NO` (with `macos`) and any `HOMEBREW_*` (with `packages`) get "delete its line yourself". The old script's prompt variables `COMPUTERNAME` and `LOCALHOSTNAME` (with `macos`) point at `dotfiles-settings set macos.computer_name <name>` and `macos.local_hostname <host>`. Nothing is written for them.

When at least one override was written or already matched, it ends with:

```text
~/.zsh.local was not edited. Its export lines stay as seeds.
An override beats the seed: while KEY has an override, editing ~/.zsh.local does not change KEY.
Undo one with: mise unset --override KEY
```

### macos

Reports only and changes nothing. From `mise bootstrap macos defaults status --json` it prints `macOS defaults: <a> set, <b> differ, <c> unset.` and one line per entry that differs or is unset, as `<domain> <key> <path>: wants <value>, has <current>` (the dotted `path` only for a value inside a dictionary preference, and `nothing` for no current value).

It then lists the leftovers: preferences the old script set only when asked, which the new setup offers as `config.local.toml` opt-ins: `com.apple.dock` `autohide-delay` and `autohide-time-modifier`, `com.apple.LaunchServices LSQuarantine`, and `com.apple.frameworks.diskimages` `skip-verify`, `skip-verify-locked` and `skip-verify-remote`. One is listed only when `defaults read` finds it and no status entry has its domain and key. A declared one is never a leftover. Each line gives both ways out: declare it in `config.local.toml` (the comment at the top of `conf.d/20-macos.toml` shows the table), or `defaults delete <domain> <key>`.

Two switches are on by default where the old script asked first, and each gets a warning while it is still at its default (not exported in the shell and no override; an empty value means switched off):

- **Time Machine.** When backups are on (`AutoBackup` reads something other than `0`, or `tmutil destinationinfo` names a destination), it warns that `set-defaults` now turns them off and gives `dotfiles-settings set macos.disable_time_machine off`. Run that before `set-defaults`, or the backups stop.
- **Firewall.** When `socketfilterfw --getglobalstate` shows it off, it says `set-defaults` turns it on with stealth mode and asks for the password, and gives `dotfiles-settings set macos.firewall off` to leave it off.

It ends with:

```text
Nothing was changed. The old script already wrote these preferences.
To write the declared values, run: set-defaults
mise never deletes a preference. One the old script set that no config declares stays as it is.
Declare it in config.local.toml to keep it on purpose, or run its defaults delete command.
```

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
