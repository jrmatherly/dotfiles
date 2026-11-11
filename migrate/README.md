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

Moves what Homebrew still owns over to mise, then offers to move the Homebrew program aside (see "Removing Homebrew" below). In order:

1. **mise itself.** When `mise` is Homebrew's copy (under `/opt/homebrew`), the step offers to move it, and nothing below runs until that is done or declined. Homebrew's copy refuses `mise self-update`, so nothing upgrades it. The move runs mise's installer (`curl -fsSL https://mise.run | sh`, to `~/.local/bin/mise`), then `mise reshim --force` with `~/.local/bin` first on `PATH` (mise links each shim to the first `mise` on `PATH`, and rewrites an existing link only with `--force`), then `brew uninstall mise`, a second reshim, and a check that every shim resolves. It then offers to re-register Claude Code's `mise` MCP server with the new path. The reshim comes before the uninstall because every shim is a link to the mise binary: uninstalling first would leave `node`, `python` and the rest dangling for agent and GUI shells until the reshim. If the installer leaves no working `~/.local/bin/mise`, or a shim still points at Homebrew's mise after the reshim, the step stops with exit 1 and Homebrew's mise is untouched. If `brew uninstall mise` fails, both are installed and a second run finishes. A run that finds mise outside Homebrew with dangling shims offers to rebuild them. Open a new terminal afterwards. Way back: `HOMEBREW_NO_ANALYTICS=1 brew install mise && PATH="/opt/homebrew/bin:$PATH" mise reshim --force`.
2. **Formulae** need no migration. mise reads `/opt/homebrew`, so a formula Homebrew installed counts as installed and `mise bootstrap packages upgrade` replaces it with the current bottle. Formulae that need repair are listed.
3. **Packages no config declares.** The formulae `mise bootstrap packages prune --manager brew --dry-run` would remove are listed with a reason each: Homebrew's mise, a keg whose tool moved to mise `[tools]`, installed by hand, or a dependency. The script never prunes. mise keeps a formula that any config it has ever tracked still declares (`~/.local/state/mise/tracked-configs`), so the list can be shorter than what is really undeclared; the step prints that count. For each formula Homebrew's receipt records as installed by hand that no config declares (read from `Cellar`, so one the prune list misses is offered too, and one in the drop file is not), and each folder in `Caskroom` that no declared cask names, it offers to add a line to `tilde/.config/mise/config.local.toml` (`"brew:<name>" = "latest"` or `"brew-cask:<token>" = "latest"`, with the tap in front when it is not Homebrew's own). That file is gitignored and belongs to this Mac only; mise merges its `[bootstrap.packages]` with the tracked one, so a declared package survives a prune and a declared cask joins the lists below on the next run. The file is copied to the backup folder before the first write.
4. **Declared casks that are not installed** (a reinstall that stopped half way) get their command: `mise bootstrap packages apply brew-cask:<token>`.
5. **Homebrew casks that do not update themselves** are listed with version and kind (`app`, `pkg` or `other`). Nothing upgrades these: mise leaves a cask Homebrew installed alone.
6. **Homebrew casks that update themselves** are listed the same way. Moving one gains no upgrades. They are offered because Homebrew can only be removed once no cask is still Homebrew's, so a cask you decline keeps Homebrew installed.
7. Without `brew` on `PATH` the step only lists the casks and moves none.
8. Without network (`curl -fsI --max-time 5 https://formulae.brew.sh/` fails) it moves neither mise nor any cask.
9. **Reinstalling.** For each cask in the first list and then the second, it asks, and on yes runs `brew uninstall --cask <token>` then `mise bootstrap packages apply --yes brew-cask:<token>`, and checks that mise reports the cask `installed` and `managed_by: mise` and that its app bundles exist. A cask whose app is running is skipped with a line naming the app. The app bundle is replaced and not copied to the backup folder (size): the backup records token and version in `casks.tsv`, and the way back is `HOMEBREW_NO_ANALYTICS=1 brew install --cask <token>`. macOS can drop the privacy permissions of a replaced app, so check System Settings > Privacy & Security afterwards. A pkg cask (`dotnet-sdk`, `git-credential-manager`) asks for the password twice, once from each tool. When the apply or the check fails the cask is left uninstalled: the step prints both ways to get it back (the apply command again, or the `brew install --cask` line), exits 1 and touches no further cask.
10. **Leftovers.** Folders in `Cellar` that hold only mise's `.mise-staging.lock` (left when `brew uninstall` removes a formula mise installed) are listed and, on yes, moved to the backup folder.
11. **Removing Homebrew**, below.

`mise bootstrap packages status --json` is the step's source for the lists. mise fetches a tap cask's metadata from GitHub to answer it, so with a tap cask declared the step stops after the mise question when offline.

#### Removing Homebrew

Homebrew's documented uninstaller ([Homebrew/install](https://github.com/Homebrew/install#uninstall-homebrew), [FAQ](https://docs.brew.sh/FAQ#how-do-i-uninstall-homebrew)) is not used. It deletes `Cellar` and `Caskroom`, every broken link under the prefix and `/etc/paths.d/homebrew`, and mise installs its packages into that same `Cellar` and `Caskroom`. So the step moves only the Homebrew program into the backup folder and leaves the prefix in place.

- **Moved:** every top-level name `git -C /opt/homebrew ls-tree --name-only HEAD` prints except `bin` (`Library` with `Homebrew` and the taps, `completions`, `docs`, `manpages`, `package`, the repository's dot-files and top-level files), `bin/brew`, `.git`, the completion and man links `uninstall.sh` removes (`etc/bash_completion.d/brew`, `share/doc/homebrew`, `share/man/man1/brew.1`, `share/zsh/site-functions/_brew`, `share/fish/vendor_completions.d/brew.fish`) when present, and `~/Library/Caches/Homebrew` and `~/Library/Logs/Homebrew`.
- **Left:** `Cellar`, `Caskroom`, `opt`, `bin`, `sbin`, `etc`, `include`, `lib`, `share`, `Frameworks`, `var/homebrew` (the linked-keg records mise reads) and `/etc/paths.d/homebrew` (`/opt/homebrew/bin` stays on `PATH`). mise keeps its own tap list in `[bootstrap.brew.taps]`.

It asks only when every check passes, in this order. A failed check prints its reason and nothing is asked. `--dry-run` prints each result and the list it would move.

1. `/opt/homebrew/bin/brew` and `/opt/homebrew/.git` exist.
2. mise is not Homebrew's (answer yes to the mise move at the start of the step).
3. `mise bootstrap packages status --json` works. It needs a Ruby 3 on `PATH` to read tap definitions, which `brew:ruby` provides.
4. **Nothing Homebrew installed is left outside mise's package state.** Each package that blocks is named on its own line, `  brew-cask:<token>: …` or `  brew:<name>: …`. A package blocks when it is a cask with `managed_by: homebrew` (declared or not), a `Caskroom` folder no status cask names, or a `Cellar` formula whose `INSTALL_RECEIPT.json` says `installed_on_request: true` and that no status formula names. Not counted: `mise`, the seven formulae moved to mise `[tools]`, and dependencies. To drop a package on purpose, add a line `brew:<name>` or `brew-cask:<token>` (tap-qualified or not; blank lines and `#` lines are ignored) to `~/.dotfiles-migration-backup/dropped.txt`, which the script reads and never writes. A dropped package stays installed, and once `brew` is gone nothing updates or removes it. A drop never excuses a cask that is still Homebrew's.
5. No cask has `managed_by: unknown`.
6. The backup folder is on the same volume as `/opt/homebrew`, so each move is a rename.

The prompt lists the dropped packages still installed and the lines in `~/.zsh.local`, `~/.zprofile`, `~/.zshrc`, `~/.bash_profile` and `~/.profile` (real files only) that call `brew shellenv` or set `HOMEBREW_` variables, which it does not edit. `ca-roots trim` (the opt-in `DOTFILES_TRIM_CA_ROOTS` step in `sysup`) runs a script inside `Library` and stops working. Only the typed phrase `remove homebrew` goes ahead. Afterwards the step reads the package status again: if any package's state or manager differs, it moves everything back, prints the differing lines and exits 1. Restore by hand with `sh ~/.dotfiles-migration-backup/<timestamp>/RESTORE.txt`.

### dotfiles

Hands the links the old `setup/symlinks.sh` made over to `mise dot apply`. It runs mise from `$HOME`. In order:

1. **`~/dotfiles`.** Every source in `conf.d/40-dotfiles.toml` goes through it. When it is missing or is not a link to this clone, the step prints the `ln -s` command and exits 1 before anything else.
2. **Whole-directory links.** A `~/.claude/rules` that is one link into the clone is left to mise, which replaces it with a real folder of links. A `~/.ssh` that is one link into the clone stops the step with the commands to fix it by hand (`rm ~/.ssh && mkdir -m 700 ~/.ssh`, then move every file except `config` out of `tilde/.ssh`). The script does not move key files.
3. **Mole's per-Mac lists.** For `whitelist` and `whitelist_optimize`, when `mole/<name>.local` exists and `tilde/.config/mise/config.local.toml` has no `"~/.config/mole/<name>"` key, it asks to add `"~/.config/mole/<name>" = { source = "~/dotfiles/mole/<name>.local", mode = "symlink" }` under `[dotfiles]` (under an existing header, or a new one). Without it the apply repoints the link to the shared list. A key already there, written by hand or by an earlier run, is left as it is and nothing is asked. The file is copied to the backup folder before the first write.
4. **Codex.** `~/.codex/config.toml` as a link into the clone is removed before the apply, which then creates the file at mode 600 (mise would otherwise leave a regular file at 644). A link elsewhere is replaced before the apply by a copy of the file it points to, at mode 600, and mise adds only the keys it lacks (mise stops at any other link). The file it pointed to stays. A regular file is never touched. When it is not valid TOML, the step says so and exits 1 before any prompt: fixing it is yours.
5. **What is in the way.** From `mise dot apply --dry-run`, the paths under `files: refusing to overwrite existing files` are the real files or folders in the way. One that resolves into the clone (through a whole-directory link the script does not know) is named and stops the step, so a tracked file is never moved. From `mise dot status --json`, a declared link that points elsewhere is listed to be repointed. A link whose text starts with the clone's path or `~/dotfiles/` is old-style: it is counted, and mise reads it as applied. A dry run that fails for any other reason is printed and stops the step.
6. **One question.** With anything listed: `Back up the <n> item(s) above and let mise link them?`. With nothing listed but `mise dot status --missing` failing (a run that stopped half way): `Run mise dot apply to link what is missing?`. On yes, each file in the way is moved to the backup folder, each repointed link is recorded in `links.tsv` with an `ln -sfn` line in `RESTORE.txt`, the Codex link is handled as in 4, and then `mise dot apply --yes` runs. When the apply fails, the step exits 1, names the backup folder, and a second run finishes the apply.
7. **Old links nothing declares** are listed, with `(dangling)` when their target is gone, and left in place. It looks at depth 1 in `~`, `~/.claude/rules`, `~/.claude/skills`, `~/.codex`, `~/.gnupg`, `~/.ssh`, `~/.config/mole` and `~/.config`, and at the VS Code `User`, lazydocker and rtk paths: the places the old script linked into.
8. **Firefox.** For `user.js`, `chrome/userContent.css` and `chrome/userChrome.css` in the first `*dev-edition*` profile, it reports whether each is a hard link to the clone's file. `setup/dotfiles-extras.sh` makes the links.
9. It ends with `mise dot status --missing` and exits with its status, printing `All dotfiles are in their declared state.` on 0.

Never `--force`: mise's `--force` replaces a file with no copy, which is why the step moves each conflict to the backup folder first.

### setup

Handles what only the old `setup.sh` and `setup/misc.sh` left behind. In order:

1. **`/etc/pam.d/sudo_local`.** The old `setup.sh` wrote it only when it was missing, so a hand-edited one survived. When its content is exactly `auth       sufficient     pam_tid.so`, the step prints `sudo_local: as declared, kept`. Otherwise it shows the `diff`, copies the file to the backup folder, and says that the first `mise bootstrap` rewrites it and that `sudo cp <backup> /etc/pam.d/sudo_local` restores it. Nothing is removed or asked. A missing file is not mentioned. The path can be overridden with `MIGRATE_SUDO_LOCAL`, for the self-check.
2. **mise's old rust install.** When `${MISE_DATA_DIR:-~/.local/share/mise}/installs/rust` exists, it asks `Forget mise's old rust install so its shims stop shadowing rustup?`. On yes the folder moves to the backup folder and `mise reshim` runs. The old `setup/misc.sh` did this.
3. **`~/.cargo/bin/rustup`.** When it differs from Homebrew's `opt/rustup/bin/rustup`, the step prints the old script's hint (`rm -rf ~/.cargo/bin ~/.rustup && /opt/homebrew/opt/rustup/bin/rustup default stable`) and changes nothing. The toolchain is yours to pick.
4. **The `mise` MCP server.** When Claude Code's `mise` server runs a command other than the mise on `PATH`, it asks to re-register it, as the `packages` step does straight after moving mise. This catches a Mac where mise moved some other way. The old command goes to `mcp.txt` and `RESTORE.txt`.
5. **Kept.** `private/setup-logs/` and `~/dotfiles` are reported as kept when present: the new `setup.sh` still writes the logs, and every `[dotfiles]` source in the mise config resolves through `~/dotfiles`.

The `/etc/shells` entry and the login shell are not mentioned: the new setup leaves them as they were.

## Restoring

Every item a step replaces is moved or copied to `~/.dotfiles-migration-backup/<timestamp>/files/`, at its original path under that folder. `RESTORE.txt` in the same folder lists one command per item that puts it back. Delete the folder by hand once the Mac works.
