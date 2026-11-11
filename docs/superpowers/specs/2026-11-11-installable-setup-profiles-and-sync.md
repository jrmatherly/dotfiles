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
| Install with our config as the global config | `--from <url> --config-dir <dir>` links `~/.config/mise` to a directory of the checkout, "so its `config.toml`, `config.<env>.toml`, `conf.d/`, and `miserc.toml` are the global config from this run on". This is how the repository is laid out today (`tilde/.config/mise`) | [cli/bootstrap](https://mise.jdx.dev/cli/bootstrap.html) |
| Opt out of a group | Machine modules: `mise.<name>.toml` in the project, selected by an `env` list. A project commits its default in `.miserc.toml`; `~/.config/mise/miserc.local.toml` on the Mac replaces the shared list. `[env_sets]` names a group of modules. `mise bootstrap unapply <name>` removes a module's files, services and dotfile entries | [modules](https://mise.jdx.dev/bootstrap/modules.html) |
| Personal and work | Config environments: `mise -E work bootstrap`, `mise.work.toml`. `--save-env` remembers the choice | [bootstrap](https://mise.jdx.dev/bootstrap.html) |
| Background saving | Off unless declared: the watcher is a LaunchAgent that exists only when the global config has `[bootstrap.services.mise-history]` | [history](https://mise.jdx.dev/dotfiles/history.html) |
| Save and sync | `mise dot origin set <private repo> --sync <mode>` shares the history of tracked files. `mise dot sync` and `mise dot pull` exchange and apply. A conflict pauses sync. `mise bootstrap --adopt you/setup` restores on a new Mac | [sync](https://mise.jdx.dev/dotfiles/sync.html) |
| Sign in with GitHub | `gh auth login`, then `gh auth setup-git`. mise's sync uses Git's credential helper | same |
| Cancel one inherited dotfile | `enabled = false` on an entry "turns off an entry inherited from another config file". A more local config file replaces an entry with the same key | [reference](https://mise.jdx.dev/dotfiles/reference.html) |
| A file an app rewrites | `copy` overwrites the target on every apply. `create_if_missing = true` seeds it once and never touches it again. A `merge` edit sets only the keys we ship (`merge = "missing"` only the absent ones) | [managed](https://mise.jdx.dev/dotfiles/managed.html) |
| One file, different per profile or per Mac | `variants` with a `profile` selector, or `machine = true` for a version per machine | reference |
| Keep secrets out of the synced history | Tracked entries take `encrypt = true`, and mise refuses to save a credential-named file in plaintext unless `allow_plaintext` is set | reference |

So the work is mostly restructuring this repository into a bootstrap project, splitting it into modules, and putting `dotfiles-settings` and a menu bar app in front of commands mise already has.

## Design

### Distribution

- `mise bootstrap --from <url>` is the documented install. `setup.sh` stays as the owner's path from a clone, and as the path for a Mac without mise.
- There are two shapes, and P0 measures both before P1 picks one:
  - **Project shape.** The repository gains a root `mise.toml`. The user's `~/.config/mise` stays their own directory and loads on top of ours. This gives the cleanest user layer, and needs the most restructuring: the four `conf.d` fragments move or are included from the root file.
  - **Config-dir shape.** `--from <url> --config-dir tilde/.config/mise` links `~/.config/mise` into the checkout, as `setup.sh` does today. Almost nothing moves. The user layer shrinks to the `*.local.toml` and override files, which then sit inside our checkout (git-ignored), and a user has no global config of their own to sync.
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
| A project can ship its own default module list in `.miserc.toml`, and `miserc.local.toml` in the user's config dir replaces it | Probe 3 |
| The user layer can cancel one package or tool key the project declares | Probe 4 |
| `--update` on a checkout with an uncommitted change: which cases fast-forward and which refuse | Probe 5 |
| `copy` and `create_if_missing` entries keep the checkout clean when the target is rewritten, and only the second keeps the user's edit | Probe 5 |
| `mise dot origin set`, `sync`, `pull` and a conflict between two Macs behave as documented, and `*.local.toml` stays put | Probe 6 |
| `-E work` with `--save-env` selects `mise.work.toml` in a project on later runs | Probe 7 |
| `mise bootstrap unapply <module>` removes that module's dotfile entries and nothing else | Probe 8 |
| `--from <url> --config-dir <dir>` links the config dir into the checkout, and a `*.local.toml` written there does not block `--update` | Probe 9 |

Measured on this Mac on 2026-11-11: `mise --version` prints 2026.11.5, and `mise dot --help` lists `origin`, `sync`, `pull`, `track`, `conflicts` and `exclude`.

Also measured that day: with `HOME` and every `MISE_*_DIR` pointed at a scratch folder, `mise config ls` run from inside this repository still listed the real `~/.config/mise/conf.d/*.toml`, because mise reads config from every parent of the current directory. Run from the scratch home it listed nothing. Two consequences. The probe harness runs every mise command from the scratch home and checks this before anything else. And the install and update commands in P1 must say which directory they run from, as `setup.sh` and `bin/dotfiles-settings` already do by changing to `$HOME`.

## Plans

- `docs/superpowers/plans/2026-11-11-p0-probes-and-model-default.md`: the probes in a scratch home, and the `claude-config save` model rule. Its results fill in this spec and decide the open points.
- P1 to P6 are not written yet. Each gets its own plan file when the one before it has landed. The briefs below are what each plan must be written from.

## Phase briefs

Testing rule for every phase: a real install, update, sync or profile switch is run in the macOS VM, never on the owner's Mac, which is the machine the work is written on. Self-checks with stubs and scratch homes run anywhere, as `bin/lib/test-*` do today. Each plan's Global Constraints repeat this.

How to use these when writing a plan: read the brief, then read "Verified facts" (P0 rewrites the "Not verified" table into it), then read what the earlier phases actually shipped (`git log`, the completed plans, the code). Where a brief and the shipped code disagree, the code wins and the plan says so in one line. Each brief lists what was known on 2026-11-11 and what it was waiting on.

### P1: Install and update without a clone

- **Outcome.** On a Mac with only mise, one documented command installs the setup, a second updates it, and neither needs the user to clone, fork or edit our repository. `./setup.sh` from a clone still works for the owner.
- **Delivers.** The chosen shape from Distribution (project or config-dir). An `update` command that runs `mise bootstrap --from <url> --update` with the flags `setup.sh` passes today. A decision for every `[dotfiles]` entry: symlink, `create_if_missing` copy or `merge` edit. `$DOTFILES` and the `~/dotfiles` link resolved for a checkout under `~/.local/share/mise/bootstrap-repo`.
- **Known.** `setup.sh` does more than `mise bootstrap`: it installs packages one manager at a time so a failure only warns, skips `macos-defaults`, runs `mise install` itself, runs the task as a second call, then `setup/dotfiles-extras.sh` (see `setup/README.md`). An install from mise alone has no `setup.sh`, so each of those either moves into the config (hooks, the `bootstrap` task) or the install command becomes "run mise, then run our script from the checkout". `40-dotfiles.toml` has 38 entries, 36 of them with a `~/dotfiles/…` source.
- **Waiting on.** Probes 2, 5 and 9 (relative sources, updates over a dirty checkout, the config-dir shape). Open point 1 (the name) and open point 2 (whether the owner's Mac uses installed mode).
- **VM baseline.** The existing UTM guest named `macOS` is the baseline as it stands. The A6 plan's Task 6 (`docs/superpowers/plans/completed/2026-11-09-a6-bootstrap-entry-point.md`) records it: UTM 5.0.8, guest macOS 27.2.1 (26B131), 4 cores, 8 GB of memory, a 100 GB disk made at that size in the wizard, a local admin account, no Apple ID, and no Command Line Tools, Xcode or Homebrew. Every A6 run used "Run without saving changes", so nothing from this repository is on it; the owner confirmed on 2026-11-11 that it is still a fresh install. Run each first-install test in that disposable mode. The Command Line Tools stay off the baseline on purpose: installing them is the stranger's real first step, since mise needs `git` to clone. A test that must survive a shutdown (install, log out for the login shell, then update) starts from a UTM snapshot instead, restored afterwards. Measured in A6: a full install took the guest's free space from 68 GiB to 29 GiB, and evidence went to the host's `~/vm-proof/` through a shared folder. Not checked: whether a restart inside one disposable run keeps its changes.
- **Done when.** A fresh macOS VM with mise and nothing else reaches the same `mise bootstrap status` as a `setup.sh` run, an upstream commit arrives with the update command, and an app rewriting its config does not block that update. The `fresh-install` workflow gains a job for this path.

### P2: Modules, opt-outs and the owner's layer

- **Outcome.** A stranger can decline any group before or after installing, and gets nothing that is only true for the owner.
- **Delivers.** The base split into modules (apps, fonts, VS Code extensions, Claude Code plugins and skills, other agent tooling). A default list with everything on. A switch per module in `dotfiles-settings`. A documented way to skip one item. The 13 owner-specific values in `docs/forking.md` moved into an owner layer, with `docs/forking.md` shrinking to match.
- **Known.** `30-packages.toml` declares the formulae, casks and extensions in one `[bootstrap.packages]` table, so splitting it is mechanical. The macOS groups already have switches (`macos.*` in `settings/registry.toml`). `claude-config restore` only adds, so a Claude opt-out means skipping the restore. Turning a module off does not uninstall packages: mise's docs point to `mise bootstrap packages prune`, which is not limited to one module, and `sysup` never runs it for that reason.
- **Waiting on.** Probes 3, 4 and 8 (a shipped default list, cancelling one key, removing a module). Whether a package key can be cancelled from the user layer is not in the pages read, so P2's first task measures it with a dry run against the real package list.
- **Done when.** With one module off, a dry run of the install lists none of that module's packages. With the owner layer absent, `git grep -i` for the owner's name, domain and account finds nothing outside that layer, LICENSE and the README credits.

### P3: Sign in and sync

- **Outcome.** A user signs in with GitHub once, and their own changes follow them to their next Mac. Nothing that looks like a secret leaves the machine.
- **Delivers.** `dotfiles-settings sync on|off|now|status`. Sign-in through `gh`. A private repository created in the user's account. The tracked set and the exclude list. A conflict view. A restore path for a second Mac that composes with P1's install.
- **Known.** mise reads tracking entries only from global and system config, so `dotfiles-settings` writes them into the user's own config, never ours. Connecting an origin shares the whole saved history. mise refuses credential-named files unless `allow_plaintext` is set, and tracked entries can be encrypted. `pull` writes files but does not install tools or render templates, so a pull that changes declarations needs a bootstrap run after it. `mise bootstrap --adopt <setup repo>` is the documented restore, and it and `--from` cannot be combined, so the second-Mac flow is two commands and their order has to be designed. `claude-config save` already has a secrets filter worth reusing as the model for the exclude list.
- **Waiting on.** Probe 6. P1's shape: under the config-dir shape the user has no global config of their own, and what "the user layer" means for sync has to be redefined around the `*.local.toml` and override files. Open point 3 (automatic sync).
- **Done when.** Two scratch homes exchange a changed setting through a private repository, a `*.local.toml` value stays put, a file holding a token is refused, and a conflicting edit pauses with both versions shown.

### P4: Profiles

- **Outcome.** One Mac, or one user across Macs, switches between named variants such as personal and work.
- **Delivers.** `dotfiles-settings profile list|use|new`. A profile as a config environment, with the choice saved. Per-profile module lists and settings. A rule for which settings are machine-scoped and so ignore profiles.
- **Known.** `-E work` selects `mise.work.toml` or `config.work.toml`, and `--save-env` writes the choice to `miserc.local.toml`. `[env_sets]` names a group of environments, so a profile can be "these modules plus these settings". A dotfile entry can differ by profile with `variants`. `-E` replaces the saved selection for that run and does not add to it, so a profile and the module list share one `env` list: P2 and P4 must agree on its shape, and P2 lands first.
- **Waiting on.** Probe 7. P2's module list format.
- **Done when.** Switching profile and applying changes exactly the entries that differ, and switching back restores them.

### P5: Menu bar app

- **Outcome.** A person who never opens a terminal can see the state, change a setting, switch profile, sync and update.
- **Delivers.** A menu bar app that calls `dotfiles-settings` and shows its output. Packaged and distributed the way `~/dev/claude-multipass` is (its tap, its release flow).
- **Known.** `dotfiles-settings` already has `--json` on `list` and `get`, fixed exit codes, and a browser UI through `serve`. The app adds no logic: every action is one command that also works in a terminal. `set`, `reset` and `apply` change the machine, so the app confirms before each.
- **Waiting on.** P1 to P4 being stable, and the name. Read `~/dev/claude-multipass` (its `app/`, `scripts/` and release docs) before writing this plan; that was not done for this spec.
- **Done when.** Each menu action produces the same result as its command, on a Mac that installed through P1.

### P6: Docs for the new path

- **Outcome.** The README leads with the install-from-mise command, and a stranger can follow it without reading the rest.
- **Delivers.** README quick start for installed mode. `docs/installation.md` split into installed mode and clone mode. `docs/forking.md` rewritten around the user layer. A page on sync and profiles. An update to `docs/updating.md`.
- **Known.** The README was rewritten on 2026-11-11 as a short landing page with the detail in four `docs/` pages. A new docs page must not be named after a command, because `help <name>` reads `docs/<name>.md` before tldr.
- **Waiting on.** Everything above. Each earlier phase updates the docs it makes false in its own commits; P6 is the pass that reorders them around the new default.
- **Done when.** `docs-auditor` finds no claim in the README or `docs/` that the shipped code contradicts.

## Open points for the owner

1. The name people type. `dotfiles-settings` describes the owner's repository, not a product. A name is needed before P1 writes it into install commands.
2. Whether the owner's Mac moves to installed mode too, or stays on a clone forever. Staying on a clone means installed mode is only ever tested in a VM.
3. Whether automatic background sync is wanted at all, or manual sync is enough.
