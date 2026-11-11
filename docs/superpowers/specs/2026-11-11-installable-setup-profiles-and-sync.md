# Installable setup, opt-outs, profiles and sync

Date: 2026-11-11. Status: draft for the owner's review. Plans built on this spec are listed in [Plans](#plans).

## Goal

Someone who is not the owner installs mise, runs one command, and gets this setup. They receive our later changes with one more command. Their own changes live outside our repository, so their copy never drifts from ours. They can skip the parts they don't want, keep a "personal" and a "work" variant, and sign in with GitHub to carry their own changes to their next Mac. A menu bar app fronts all of it.

The owner's workflow stays: edit files in a clone, commit, push.

## Decisions the owner made (2026-11-11)

1. Design for strangers from the first version. The repository is public.
2. A user's synced settings live in a private GitHub repository in their own account. Revisit if it limits us.
3. The base includes everything it does today (apps, VS Code extensions, Claude Code plugins, skills and settings). Every group has an opt-out. Nothing is forced.
4. macOS only. Linux is a later follow-up.
5. The tracked Claude Code default model is `opus`. One Mac's choice does not change it.

## Where we are

- The clone is the install. `setup.sh` links `~/dotfiles` and `~/.config/mise` to the clone, then runs `mise bootstrap`.
- Every `[dotfiles]` source is written `~/dotfiles/…`, and most targets are symlinks into the clone. An app that rewrites its config writes into the clone.
- Per-Mac values already have homes outside git: `config.override.toml` and `config.local.toml` in the mise config dir (git-ignored, but inside the clone because `~/.config/mise` is a link), `~/.zsh.local`, `~/.gitconfig.local`, `~/.ssh/config.local`.
- `docs/forking.md` lists 13 places hard-coded to the owner. A stranger gets all of them today.
- `dotfiles-settings` reads and writes every setting through adapters and has a terminal UI and a browser UI.

## Target: three layers

VS Code's Settings Sync is the model: a shared base, a per-user layer that syncs, and machine-scoped settings that never leave the machine.

| Layer | Who owns it | Where it lives | How it changes |
| --- | --- | --- | --- |
| Base | Us | A checkout mise keeps at `~/.local/share/mise/bootstrap-repo` | `mise bootstrap --update` fast-forwards it |
| User | The user | Their own `~/.config/mise` (a real directory, not a link into our checkout), and the files they choose to track | They edit it, or `dotfiles-settings` does. It syncs through their private repository |
| Machine | The user, on one Mac | `*.local.toml` in `~/.config/mise`, `~/.zsh.local`, `~/.gitconfig.local`, `~/.ssh/config.local` | Never synced. mise's docs say files ending `.local.toml` stay on each machine |

The owner's own values (name, clone URL, weather location, personal taps, the `coolify` MCP note) move out of the base into the owner's user layer. That layer is the first real test of the design.

## How each requirement maps onto mise

Everything in this table is from mise's documentation, read on 2026-11-11. None of it has been run against this repository. See [Not verified](#not-verified-and-the-check-that-settles-each).

| Requirement | mise feature | Doc |
| --- | --- | --- |
| Install from mise alone | `mise bootstrap --from https://github.com/jrmatherly/dotfiles.git`: clones a "bootstrap project" (a `mise.toml` and the files it uses) and runs bootstrap from the checkout. It "does not replace your global config" | [from-repository](https://mise.jdx.dev/bootstrap/from-repository.html) |
| Receive updates | `--update` pulls new commits first, fast-forward only. `?ref=v1` pins a branch or tag | same |
| Opt out of a group | Machine modules: `mise.<name>.toml` in the project, selected by an `env` list. `miserc.local.toml` on the Mac replaces the shared list. `mise bootstrap unapply <name>` removes a module's files, services and dotfile entries | [modules](https://mise.jdx.dev/bootstrap/modules.html) |
| Personal and work | Config environments: `mise -E work bootstrap`, `mise.work.toml`. `--save-env` remembers the choice | [bootstrap](https://mise.jdx.dev/bootstrap.html) |
| Save and sync | `mise dot origin set <private repo> --sync <mode>` shares the history of tracked files. `mise dot sync` and `mise dot pull` exchange and apply. A conflict pauses sync. `mise bootstrap --adopt you/setup` restores on a new Mac | [sync](https://mise.jdx.dev/dotfiles/sync.html) |
| Sign in with GitHub | `gh auth login`, then `gh auth setup-git`. mise's sync uses Git's credential helper | same |
| Cancel one inherited dotfile | `enabled = false` on an entry "turns off an entry inherited from another config file". A more local config file replaces an entry with the same key | [reference](https://mise.jdx.dev/dotfiles/reference.html) |
| A file an app rewrites | `copy` overwrites the target on every apply. `create_if_missing = true` seeds it once and never touches it again. A `merge` edit sets only the keys we ship (`merge = "missing"` only the absent ones) | [managed](https://mise.jdx.dev/dotfiles/managed.html) |
| One file, different per profile or per Mac | `variants` with a `profile` selector, or `machine = true` for a version per machine | reference |
| Keep secrets out of the synced history | Tracked entries take `encrypt = true`, and mise refuses to save a credential-named file in plaintext unless `allow_plaintext` is set | reference |

So the work is mostly restructuring this repository into a bootstrap project, splitting it into modules, and putting `dotfiles-settings` and a menu bar app in front of commands mise already has.

## Design

### Distribution

- The repository gains a root `mise.toml`. `mise bootstrap --from <url>` is the documented install. `setup.sh` stays as the owner's path from a clone, and as the path for a Mac without mise.
- Installed mode and clone mode read the same declarations. What differs is where the checkout is and who may edit it.
- The installed checkout must stay fast-forwardable. No app may write into it. Each `[dotfiles]` entry whose target an app rewrites (VS Code's `settings.json`, `gh`'s `config.yml`, and others found by the probe) stops being a symlink in installed mode. It becomes a `merge` edit where we own some keys, as `~/.codex/config.toml` already is, or a `create_if_missing` copy where we only seed the file. A plain `copy` is wrong for these: mise's docs say it overwrites the user's edits on every apply.
- Releases: users follow the default branch at first. A `stable` branch or tags come when the first breaking change needs them.

### Opt-outs

- The base splits into modules by what a person would decline: apps, fonts, VS Code extensions, the Claude Code plugins and skills, the other agent tooling, the macOS defaults groups that already have switches.
- All modules are on by default. A user turns one off in `dotfiles-settings`, which writes the `env` list in `miserc.local.toml`.
- Opting out of one item inside a module needs a way for the user layer to cancel a key the base declares. For a dotfile entry the docs give one: `enabled = false`. For a package or a tool (one cask, one extension) no such key was found in the pages read, so the probe measures it. If there is none, the fallback is a deny list that `setup.sh` and `sysup` already know how to pass as skips.
- Claude Code: `claude-config restore` only adds. Opting out skips the restore. It never removes plugins a user installed.

### Sync and sign-in

- `dotfiles-settings sync on` signs in with `gh`, creates a private repository in the user's account, connects it with `mise dot origin set`, and tracks the user layer. `sync off` disconnects and leaves the history.
- Default mode is manual (`mise dot sync`, `mise dot pull` on demand). Automatic mode needs mise's background watcher and is an opt-in after manual works.
- Never tracked: `*.local.toml`, `~/.gitconfig.local`, `~/.ssh/**`, anything `claude-config save` already strips (`hooks`, credential helpers, token-like `env`). mise's docs warn that connecting an origin shares the whole saved history, so the exclude list is set before the first save, and a secret that was ever saved stays in old commits.
- A conflict is shown, not resolved for the user: `dotfiles-settings` lists the files from `mise dot conflicts`.
- mise reads tracking entries and its `[history]` table only from system and global config (reference page). So sync belongs to the user layer by construction: our project cannot declare what a user tracks, and `dotfiles-settings` writes those entries into the user's own config.

### Profiles

- A profile is a config environment. `dotfiles-settings profile use work` runs with `-E work` and saves the choice.
- A profile can change the module list and any setting. A file that differs by profile uses a `variants` entry with a `profile` selector. Machine-scoped values stay outside profiles.

### Menu bar app

- A thin front end over `dotfiles-settings` (list, set, sync, profile, update). No logic of its own.
- Built last, after the commands it calls are stable. `~/dev/claude-multipass` is the reference for packaging and distribution.

### Claude Code default model

`claude-config save` keeps the tracked `model` and ignores the Mac's. Today `sysup` runs `save` on every run, so a Mac set to another model rewrites the tracked file. The tracked value changes only by editing `agents/claude-settings.json`.

## Alternative considered: chezmoi

The owner raised [chezmoi](https://www.chezmoi.io/) on 2026-11-11. Its site describes a dotfile manager for keeping several machines in sync, with `init`, `apply` and `update` commands, templates with per-machine data and install-time prompts, encryption, and functions that read 1Password and other password managers. Only its "What does chezmoi do?" page and its documentation index were read. Nothing was run.

It does the same job as mise's `[dotfiles]`, history and origin sync, which this repository moved onto in plan A5. It does not install packages, tools or macOS defaults by itself (its docs list "install packages declaratively" under scripts), so mise would stay either way.

Decision for now: stay on mise alone. Two tools owning the same files is the thing this repository just finished removing. chezmoi becomes the fallback for the user layer if probe 5 or probe 6 shows mise cannot keep a checkout clean or sync safely. Its password-manager functions are the part mise has no equal for, and are worth a second look when P3 decides how a synced file refers to a secret.

## Non-goals

- Linux and Windows.
- Our own sync service. The store is the user's GitHub repository.
- Syncing secrets. 1Password stays the place for them.
- Removing what an opt-out would have installed, beyond what `mise bootstrap unapply` and `mise bootstrap packages prune` already do.

## Risks

- **A dirty checkout blocks updates.** One symlinked file an app rewrites, and `--update` may refuse. This decides how every dotfile entry deploys.
- **`~/dotfiles/…` sources.** They assume a link at `~/dotfiles`. A bootstrap project may resolve relative sources itself, which would remove the link, or it may not.
- **Two configs at once.** Installed mode loads our project and the user's global config together. A stranger's existing `~/.config/mise` may declare tools or packages that clash with ours.
- **Trust.** `--from` trusts our configuration for that run. The install page must say so and say how to preview (`--dry-run`).
- **History holds secrets forever.** One bad first save puts a token in a private repository's history.
- **Background writes.** Automatic sync lets a remote change a user's live files.

## Not verified, and the check that settles each

| Claim | Check |
| --- | --- |
| mise 2026.11.5 (the floor in `setup/mise-floor.sh`) has `--from`, `--adopt`, `--update` and `unapply` | Probe 1 |
| A bootstrap project resolves a relative `[dotfiles]` source from the project directory. The managed-files page says a relative source starts from the directory of the config file that declares it | Probe 2 |
| A project can ship its own default module list, and `miserc.local.toml` in the user's config dir replaces it | Probe 3 |
| The user layer can cancel one package or tool key the project declares | Probe 4 |
| `--update` on a checkout with an uncommitted change: which cases fast-forward and which refuse | Probe 5 |
| `copy` and `create_if_missing` entries keep the checkout clean when the target is rewritten, and only the second keeps the user's edit | Probe 5 |
| `mise dot origin set`, `sync`, `pull` and a conflict between two Macs behave as documented, and `*.local.toml` stays put | Probe 6 |
| `-E work` with `--save-env` selects `mise.work.toml` in a project on later runs | Probe 7 |
| `mise bootstrap unapply <module>` removes that module's dotfile entries and nothing else | Probe 8 |

Measured on this Mac on 2026-11-11: `mise --version` prints 2026.11.5, and `mise dot --help` lists `origin`, `sync`, `pull`, `track`, `conflicts` and `exclude`.

## Plans

- `docs/superpowers/plans/2026-11-11-p0-probes-and-model-default.md`: the eight probes above in a scratch home, and the `claude-config save` model rule. Its results fill in this spec and decide the open points below.
- P1, bootstrap project: root `mise.toml`, installed mode, the dotfile deploy modes, the update command. Written after P0.
- P2, modules and opt-outs, and the owner's values moved to a user layer. Written after P0.
- P3, sync and sign-in in `dotfiles-settings`.
- P4, profiles.
- P5, the menu bar app.
- P6, the install docs and README for the new path.

## Open points for the owner

1. The name people type. `dotfiles-settings` describes the owner's repository, not a product. A name is needed before P1 writes it into install commands.
2. Whether the owner's Mac moves to installed mode too, or stays on a clone forever. Staying on a clone means installed mode is only ever tested in a VM.
3. Whether automatic background sync is wanted at all, or manual sync is enough.
