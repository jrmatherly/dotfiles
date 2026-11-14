# Installable setup, opt-outs, profiles and sync

Date: 2026-11-11. Status: draft for the owner's review. Plans built on this spec are listed in [Plans](#plans).

## Goal

Someone who is not the owner installs mise, runs one command, and gets this setup. They receive our later changes with one more command. Their own changes live outside our repository, so their copy never drifts from ours. They can skip the parts they don't want, keep a "personal" and a "work" variant, and sign in with GitHub to carry their own changes to their next Mac. A menu bar app fronts all of it.

The owner's workflow stays: edit files in a clone, commit, push.

## Decisions the owner made (2026-11-11)

These outrank everything below them. The design sections and phase briefs were written by agent sessions from these decisions, and a line there that contradicts one is wrong: fix the line, do not ask the owner again. Read this list and the Goal in full before proposing anything for a phase. A question one of them answers is not a question.

1. Design for strangers from the first version. The repository is public.
2. A user's synced settings live in a private GitHub repository in their own account. Revisit if it limits us.
3. The base includes everything it does today (apps, VS Code extensions, Claude Code plugins, skills and settings). Every group has an opt-out. Nothing is forced.
4. macOS only. Linux is a later follow-up.
5. The tracked Claude Code default model is `opus`. One Mac's choice does not change it.
6. The product is named `returnofthemac`, and its command is `rotm` (owner, 2026-11-11 evening). It replaces `kitbag`, the choice from earlier that day, which a wider check ruled out (see "Names considered"). Checked for both names: PyPI, crates.io, npm, RubyGems, Homebrew formulae and casks have neither; neither is a command, alias or man page on this Mac; the Mac App Store search returns no app with either name. On GitHub the user `ReturnOfTheMac` (2009, no repositories) and the organization `RoTM` (no repositories) exist, so the project stays under the owner's account. A search for `rotm` finds 865 repositories, mostly for the game Realm of the Mad God, and none is a command-line tool of that name. Domains: `returnofthemac.com` is registered; whois reports `returnofthemac.sh` and `rotm.sh` as not found. Apple's guidelines for third parties treat "Mac" as its trademark and allow it in a product name when combined with another non-generic word, when the product is not a computer or operating system, and when the name suggests no link to Apple. A web search found no trademark registration for the song title "Return of the Mack" (Mark Morrison, 1996) and no software by this name; Paul Graham's 2005 essay is titled "Return of the Mac". Not checked: a search of the USPTO, UK and EU registers themselves.
7. The owner's Mac moves to installed mode on the existing clone (`--from-dir`), and only after installed mode is proven in the VM. **Changed by probe 10 (2026-11-11):** `--update` with `?ref=stable` switched the clone from `main` to `stable`, so the owner's Mac keeps `setup.sh` from the clone and installed mode is proven in the VM only. This was the rule the P0 plan set for that result. **Changed by the owner (2026-11-12):** that holds only while the phases are being built. Once they have landed, the owner's Mac moves to an install from `stable` (P7).
8. Sync is manual first. Automatic background sync is a later opt-in, after manual sync has been used for real.
9. Users follow a `stable` branch. The owner keeps pushing to `main`, and a commit is promoted to `stable` only after the VM install passes on it.
10. mise has a tested minimum version that the install checks, raised deliberately. Each promotion to `stable` is proven in the VM on the mise version current that day.
11. P0's probes run in the VM. P0 is executed natively in a fresh session, with one independent review at the end.
12. (2026-11-12) Decision 3 has no exception for the owner's own projects or values. Nothing is taken out of the base for being the owner's. A value that points at the owner or the owner's domain ships as it is and has a row in `docs/forking.md` saying what a user changes to use that feature themselves.
13. (2026-11-12) A user's "own changes" are the ones they make through `rotm settings` (the browser UI, the terminal UI or the command line) and their opt-outs. Sync exists so that a new Mac loads them and the user does not configure it again. Every setting the tool can change is in scope, whichever file holds it.
14. (2026-11-12) Where mise can hold a setting, mise holds it, so the configuration stays standard. Where it cannot, we build what is needed so that setting still syncs through the same private repository.
15. (2026-11-12) The owner's Mac is moved to `stable` once, by hand, after the last phase (P7). Until then the owner is the only user, nothing is promoted and no VM round is owed.
16. (2026-11-13) The menu bar app's code lives in this repository, under `app/`.
17. (2026-11-13) The app has a native settings window for every setting. The end goal is to remove the browser variant (`rotm settings serve`) once that window covers it, leaving the native window and the command line.
18. (2026-11-13) The app updates itself through mise, by upgrading its own cask, since mise installs the casks with no `brew`. It tells the user an update exists. The user chooses when to install it, and nothing installs by itself.
19. (2026-11-13) The steps that need a terminal today (`rotm update`, `rotm install`, the GitHub sign-in) run inside the app, with no Terminal window. The owner runs the VM probes that prove it, from a step-by-step runbook handed over at the moment it is needed, not earlier.
20. (2026-11-13) P5 is one plan file.

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

Measured in probe 4: a `--from` run reads the user's global config and applies its own entries, but a project entry beats a user entry with the same key, and neither `enabled = false` nor `mode = "absent"` in the user's config cancels it. The user layer adds to the base; it does not override the base's dotfile entries.

The owner's own values (name, clone URL, weather location, personal taps, the `coolify` MCP note) were to move out of the base into the owner's user layer. **Changed by the owner (2026-11-12):** nothing moves out. Everything the project installs and configures today stays in the base for every user, and the user layer is where anyone, the owner included, opts out of a part or changes a value. The owner's user layer is still the first real test of the design.

## How each requirement maps onto mise

Everything in this table is from mise's documentation, read on 2026-11-11. The probes then measured ten of these behaviours in the VM, and two rows did not hold as read: a shipped `.miserc.toml` and `enabled = false` from the user's config. Where this table and [Verified facts](#verified-facts) differ, the measurement wins.

| Requirement | mise feature | Doc |
| --- | --- | --- |
| Install from mise alone | `mise bootstrap --from https://github.com/jrmatherly/returnofthemac.git`: clones a "bootstrap project" (a `mise.toml` and the files it uses) and runs bootstrap from the checkout. It "does not replace your global config" | [from-repository](https://mise.jdx.dev/bootstrap/from-repository.html) |
| Receive updates | `--update` pulls new commits first, fast-forward only. `?ref=v1` pins a branch or tag | same |
| Install with our config as the global config | `--from <url> --config-dir <dir>` links `~/.config/mise` to a directory of the checkout, "so its `config.toml`, `config.<env>.toml`, `conf.d/`, and `miserc.toml` are the global config from this run on". This is how the repository is laid out today (`tilde/.config/mise`) | [cli/bootstrap](https://mise.jdx.dev/cli/bootstrap.html) |
| Opt out of a group | Machine modules: `mise.<name>.toml` in the project, selected by an `env` list. A project commits its default in `.miserc.toml`; `~/.config/mise/miserc.local.toml` on the Mac replaces the shared list. `[env_sets]` names a group of modules. `mise bootstrap unapply <name>` removes a module's files, services and dotfile entries | [modules](https://mise.jdx.dev/bootstrap/modules.html) |
| Personal and work | Config environments: `mise -E work bootstrap`, `mise.work.toml`. `--save-env` remembers the choice | [bootstrap](https://mise.jdx.dev/bootstrap.html) |
| Background saving | Off unless declared: the watcher is a LaunchAgent that exists only when the global config has `[bootstrap.services.mise-history]` | [history](https://mise.jdx.dev/dotfiles/history.html) |
| Save and sync | `mise dot origin set <private repo> --sync <mode>` shares the history of tracked files. `mise dot sync` and `mise dot pull` exchange and apply. A conflict pauses sync. `mise bootstrap --adopt you/setup` restores on a new Mac | [sync](https://mise.jdx.dev/dotfiles/sync.html) |
| Sign in with GitHub | `gh auth login`. **Corrected by P3 (2026-11-12):** the docs also name `gh auth setup-git`, and P3 never runs it, because it writes `~/.gitconfig` and mise passes its own credential helper for github.com to every Git call it makes (see "Verified facts") | same |
| Cancel one inherited dotfile | `enabled = false` on an entry "turns off an entry inherited from another config file". A more local config file replaces an entry with the same key | [reference](https://mise.jdx.dev/dotfiles/reference.html) |
| A file an app rewrites | `copy` overwrites the target on every apply. `create_if_missing = true` seeds it once and never touches it again. A `merge` edit sets only the keys we ship (`merge = "missing"` only the absent ones) | [managed](https://mise.jdx.dev/dotfiles/managed.html) |
| One file, different per profile or per Mac | `variants` with a `profile` selector, or `machine = true` for a version per machine | reference |
| Keep secrets out of the synced history | Tracked entries take `encrypt = true`, and mise refuses to save a credential-named file in plaintext unless `allow_plaintext` is set | reference |

So the work is mostly restructuring this repository into a bootstrap project, splitting it into modules, and putting `dotfiles-settings` and a menu bar app in front of commands mise already has.

## Design

### Distribution

- The documented install is one line with two steps. mise fetches the repository and links `~/.config/mise` into it (`mise -E rotm-installed bootstrap --from <url> --config-dir tilde/.config/mise --save-env --only final-hook`, which applies nothing, probe 11), then `setup.sh` runs from the checkout and does everything it does from a clone. `./setup.sh` from a clone stays the owner's path.
- Installed mode keeps the `~/dotfiles` link. `setup.sh` points it at mise's checkout at `$MISE_DATA_DIR/bootstrap-repo`, so every `[dotfiles]` source stays written `~/dotfiles/…` and both modes read the same entries. Probe 2 measured that a relative source would also resolve into the checkout; P1 did not need it.
- There are two shapes. P0 measured that both work (probes 2 and 9), and P1 shipped the config-dir shape:
  - **Project shape.** The repository gains a root `mise.toml`. The user's `~/.config/mise` stays their own directory and loads on top of ours. This gives the cleanest user layer, and needs the most restructuring: the four `conf.d` fragments move or are included from the root file.
  - **Config-dir shape.** `--from <url> --config-dir tilde/.config/mise` links `~/.config/mise` into the checkout, as `setup.sh` does today. Almost nothing moves. The user layer shrinks to the `*.local.toml` and override files, which then sit inside our checkout (git-ignored), and a user has no global config of their own to sync. Measured in probe 9: mise makes the link, a `config.local.toml` written through it shows in the checkout's `git status` unless the repository ignores it (this one does), and `--update` still fast-forwards.
- Installed mode and clone mode read the same declarations. What differs is where the checkout is and who may edit it.
- The installed checkout must stay fast-forwardable. No app may write into it. Each `[dotfiles]` entry whose target an app rewrites (VS Code's `settings.json`, `gh`'s `config.yml`, and others found by the probe) stops being a symlink in installed mode. It becomes a `merge` edit where we own some keys, as `~/.codex/config.toml` already is, or a `create_if_missing` copy where we only seed the file. A plain `copy` is wrong for these: mise's docs say it overwrites the user's edits on every apply. Probe 5 measured all of it: an edit made through a symlink left the checkout dirty, and `--update` exited 1 when upstream changed that same file (it still fast-forwarded when upstream changed a different one); an edited `copy` target was overwritten; an edited `create_if_missing` target was kept. So P1's first task lists every target an app rewrites, and each becomes a `create_if_missing` or `merge` entry.
- Releases: the install and update commands name `?ref=stable`. mise's docs say `--update` with a branch ref checks the branch out and fast-forwards it, and probe 10 saw exactly that. Promotion is one fast-forward of `stable` to a commit on `main` that passed the VM install, done by the owner. Tags are not used: a user would have to act to get a fix.
- The owner's Mac stays on `setup.sh` from the clone (decision 7, as changed). Probe 10 ran `--from <url>?ref=stable --from-dir <clone>` on a clone that was on `main` with an uncommitted edit. The install applied from the clone as it was and left the branch alone. `--update` then switched the clone to `stable`. The edit survived both. A working clone cannot follow `stable` without losing its branch.

#### How each entry deploys on an installed copy

One row per key in `conf.d/40-dotfiles.toml`. `tilde/.config/mise/config.rotm-installed.toml` holds every row that is not a plain symlink. "read" means the row comes from reading the config and the tool's behaviour, not from a run. `bin/lib/test-dotfiles` applies the environment in a scratch home and checks the wrapper, `gh` and VS Code rows deploy as written. What an app really writes is measured by row 8 of the P1 plan's VM proof, which turns a row into "measured" or into a new entry.

| Target | On an installed copy | Why | Basis |
| --- | --- | --- | --- |
| `~/.ackrc` | symlink | read-only to the tool that uses it | read |
| `~/.bash_profile` | symlink | nothing here writes it; an installer that appends to it would dirty the checkout, as with `~/.zshrc` before the wrapper | read |
| `~/.bunfig.toml` | symlink | read-only to the tool that uses it | read |
| `~/.curlrc` | symlink | read-only to the tool that uses it | read |
| `~/.gitconfig` | wrapper | `git config --global` and package installers write it; the seeded file includes ours | read |
| `~/.gitignore` | symlink | read-only to the tool that uses it | read |
| `~/.gitmessage` | symlink | read-only to the tool that uses it | read |
| `~/.hushlogin` | symlink | read-only to the tool that uses it | read |
| `~/.inputrc` | symlink | read-only to the tool that uses it | read |
| `~/.ripgreprc` | symlink | read-only to the tool that uses it | read |
| `~/.starship.toml` | symlink | read-only to the tool that uses it | read |
| `~/.tlrc.toml` | symlink | read-only to the tool that uses it | read |
| `~/.zprofile` | symlink | as `~/.bash_profile` | read |
| `~/.zshenv` | symlink | as `~/.bash_profile` | read |
| `~/.zshrc` | wrapper | installers append to it; the seeded file sources ours | read |
| `~/.claude/rules` | one symlink per rule | Claude Code reads rules. `/jstack:setup-jstack` and `dotfiles-settings` rewrite `jstack-models.md` through its link, which would dirty the checkout: open, see below | read |
| `~/.claude/statusline-command.sh` | symlink | read-only to the tool that uses it | read |
| `~/.config/amp` | symlink | Amp writes `settings.json.amp-write-meta`, which is git-ignored. Not checked: whether Amp rewrites the tracked `settings.json` | read |
| `~/.config/bat` | symlink | read-only to the tool that uses it | read |
| `~/.config/btop` | symlink | Not checked: btop may rewrite `btop.conf` on quit. Row 8 opens and quits it | read |
| `~/.config/cmux` | symlink | Not checked: whether cmux rewrites `cmux.json`. Row 8 opens it | read |
| `~/.config/fastfetch` | symlink | read-only to the tool that uses it | read |
| `~/.config/gh` | real folder, `config.yml` a seeded copy | `gh config set` rewrites `config.yml` and `gh auth` writes `hosts.yml` beside it | read |
| `~/.config/ghostty` | symlink | Ghostty reads its config and themes and is not known to write them. Row 8 opens it | read |
| `~/.config/hunk` | symlink | hunk keeps its state in `state.json` beside the config, which is git-ignored | read |
| `~/.config/mise` | symlink | mise made this link itself; the files written through it (`config.override.toml`, `*.local.toml`) are git-ignored (probe 9) | read |
| `~/.claude/skills/project-stack` | symlink | read-only to the tool that uses it | read |
| `~/.ssh` | real folder | already a real folder in both modes | read |
| `~/.ssh/config` | symlink | read-only to the tool that uses it | read |
| `~/.gnupg` | real folder | already a real folder in both modes | read |
| `~/.gnupg/gpg-agent.conf` | symlink | read-only to the tool that uses it | read |
| `~/.codex/AGENTS.md` | symlink | read-only to the tool that uses it | read |
| `~/.codex/config.toml/defaults` | merge | already a `merge = "missing"` edit of a real file, the same in both modes | read |
| `~/Library/Application Support/Code/User` | real folder, four seeded copies | VS Code writes keybindings, tasks, snippets and its own state there; `settings.json` is rendered into it | read |
| `~/Library/Application Support/lazydocker/config.yml` | symlink | read-only to the tool that uses it | read |
| `~/Library/Application Support/rtk/config.toml` | symlink | read-only to the tool that uses it | read |
| `~/.config/mole/whitelist` | symlink | Mole writes `clean-list.txt` and `purge_paths` beside it, not this file | read |
| `~/.config/mole/whitelist_optimize` | symlink | as `whitelist` | read |

Measured on 2026-11-11 in the disposable guest (rows 7 and 8 of the P1 plan's VM proof, mise 2026.11.6): after a full install the copy had no changed tracked file, and it still had none after `git config --global`, `gh config set`, an append to `~/.zshrc`, a changed VS Code keybinding and setting, and a first run of btop, Ghostty, cmux and lazygit. So the `~/.gitconfig`, `~/.zshrc`, `~/.config/gh`, `Code/User`, `~/.config/btop`, `~/.config/ghostty` and `~/.config/cmux` rows are measured for those actions. Amp was not on the guest, so its row stays read.

Open after this table: `~/.claude/rules/jstack-models.md` is a link to a tracked file that two tools rewrite, and `~/.config/amp/settings.json` and `~/.config/btop/btop.conf` may be rewritten by their apps. None has an entry yet. Row 8 decides each.

Two more writers were found by review, not by a run. `rotm settings` stored a macOS preference by editing the tracked `conf.d/20-macos.toml`, and a jstack role by editing `jstack-models.md`: on an installed copy it now refuses both and says why, until P2 gives the user a layer of their own. `setup/misc.sh` runs `pnpm install` in the copy without `--frozen-lockfile`. Not checked: whether that can rewrite `pnpm-lock.yaml`. Row 7 shows it if it does.

### Opt-outs

- The base splits into modules by what a person would decline: apps, fonts, VS Code extensions, the Claude Code plugins and skills, the other agent tooling, the macOS defaults groups that already have switches.
- All modules are on by default. A module is a `conf.d` fragment, which mise always loads, and a user turns one off in `dotfiles-settings`, which adds its file to `ignored_config_paths` in `miserc.local.toml` (the owner's decision of 2026-11-12, replacing the `env` list below, which fails off).
- First design, dropped: the base cannot ship a default `env` list: under `--from`, a project's `.miserc.toml` and `.config/miserc.toml` were both ignored (probe 3). So the install command passes the full module list with `-E` and `--save-env`, which writes `env = [...]` to `miserc.local.toml` and is honoured on later runs without `-E` (probe 7). With the ignore list no default list exists to ship or pass: no state means every module.
- Turning a module off removes nothing by itself and offers no removal (`unapply` works on a project's module, probe 8, and a module here is a global `conf.d` fragment). Its packages stay, and `sysup` names how many no config declares. Its tools go at the next `sysup`, whose `mise prune` honours the ignore list (the P2 plan's VM proof, row 4).
- Opting out of one item inside a module: for a dotfile entry, `enabled = false` and `mode = "absent"` from the user's global config did not cancel a project entry (probe 4, project shape). For a package it works under the config-dir shape P1 shipped: `"<manager>:<name>" = { state = "absent" }` in the machine-local `config.local.toml` replaces the base's entry, and `[settings] disable_tools` hides one tool (measured 2026-11-12). So P2 builds no deny list and no hook.
- Claude Code: `claude-config restore` only adds. Opting out skips the restore. It never removes plugins a user installed.

### Sync and sign-in

- `dotfiles-settings sync on` signs in with `gh`, then creates a private repository in the user's account and saves the user's folder, `~/.config/rotm`, to it, or loads a repository that already holds saved settings. mise's history tracks that folder through one entry that `bin/lib/rotm-user-layer` appends to `config.local.toml`. `mise dot track` is never called, because it writes its entry into the tracked `config.toml`. The repository is connected with `mise dot origin set`. No Git credential configuration is written, and `gh auth setup-git` is never run: mise passes its own helper for github.com to every Git call. `sync off` disconnects and leaves the history.
- Manual first (decision 8): `mise dot sync` and `mise dot pull` on demand, and `dotfiles-settings` always passes `--sync manual` when it connects an origin, because mise's own default is automatic and its docs say that mode "lets the origin write your live files". Automatic mode needs mise's background watcher, a LaunchAgent, and is a later opt-in. Restoring on a new Mac needs a second step: `mise bootstrap --adopt` takes no `--sync` flag and the adopted home came up in mode `sync`, the automatic one, although the first Mac was manual. `mise dot origin set <origin> --sync manual` right after it was accepted (probe 6). No mise LaunchAgent was registered in the guest after the run (`launchctl list`), so nothing was running that mode.
- mise leaves `config.local.toml` out of the history by itself ("machine-local configuration"), and it reached neither the second home nor the origin's history (probe 6).
- Never tracked: `*.local.toml`, `~/.gitconfig.local`, `~/.ssh/**`, anything `claude-config save` already strips (`hooks`, credential helpers, token-like `env`). mise's docs warn that connecting an origin shares the whole saved history, so the exclude list is set before the first save, and a secret that was ever saved stays in old commits.
- A conflict is shown, not resolved for the user: `dotfiles-settings` lists the files from `mise dot conflicts`. Measured: two homes editing the same line paused sync, neither side was overwritten, and `mise dot conflicts` named the file and printed the diff (probe 6).
- mise reads tracking entries and its `[history]` table only from system and global config (reference page). So sync belongs to the user layer by construction: our project cannot declare what a user tracks, and `dotfiles-settings` writes those entries into the user's own config.

### Profiles

- A profile is a config environment named `rotm-p-<name>`. `dotfiles-settings profile use work` has mise save it in the `env` list of `miserc.local.toml` beside `rotm-installed` (`mise -E <names> bootstrap --save-env --only final-hook`). The prefix is needed because a bare name in that list also loads a project's `mise.<name>.toml`. **Changed by P4 (2026-11-13):** the first design used the bare name and had the profile share the `env` list with the module list. P2 had already moved the modules to `ignored_config_paths`.
- A profile's settings are mise's per-environment override file, `config.rotm-p-<name>.override.toml`, which mise ranks above `config.override.toml`. It holds only what differs, and every other key falls through to the shared file. A plain `config.<env>.toml` cannot do this: the shared override file beats it.
- The module list is the one thing that does not fall through. mise reads `ignored_config_paths` from `miserc` files only, which have no per-environment form, so each profile has its own off list (`modules-off.rotm-p-<name>.local`), copied from the shared list when the profile is made. The tool settings mise cannot hold get `tools.rotm-p-<name>.toml`, laid over `tools.toml`.
- `rotm settings set` writes to the active profile and `--shared` to the shared files (the owner's question of 2026-11-13, answered in the P4 plan from VS Code's profiles, where a change is recorded in the current profile). Machine-scoped values stay outside profiles.
- Which profile a Mac uses is in `miserc.local.toml`, which never syncs, so the choice is per Mac. Every profile's files sync.
- Not built: `profile delete` and `rename`, per-profile `[dotfiles]` variants (mise supports `variants = [{ profile = "<env>" }]`, and no shipped file needs one), and showing the active profile in the UIs, which belongs to P5.

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
- **`~/dotfiles/…` sources.** They assume a link at `~/dotfiles`. Installed mode keeps that link, pointed at mise's checkout, so a folder of the user's own at `~/dotfiles` stops the install until it is moved aside (P1's VM proof, row 2).
- **Two configs at once.** Installed mode loads our project and the user's global config together. A stranger's existing `~/.config/mise` may declare tools or packages that clash with ours.
- **Trust.** `--from` trusts our configuration for that run. The install page must say so and say how to preview (`--dry-run`).
- **History holds secrets forever.** One bad first save puts a token in a private repository's history.
- **Background writes.** Automatic sync lets a remote change a user's live files.

## Verified facts

Measured on 2026-11-11 in the UTM guest (macOS 27.2.1, mise 2026.11.6, a disposable run), each probe in its own scratch home. The harness is `2026-11-11-installable-probe/probe.sh` and its answers are in `results.txt` beside it.

| Claim | Measured |
| --- | --- |
| mise has `--from`, `--from-dir`, `--config-dir`, `--adopt`, `--update`, `--save-env` and `bootstrap unapply` | Yes, all seven, on 2026.11.6 (probe 1) |
| A bootstrap project resolves a relative `[dotfiles]` source from the project directory | Yes. The symlink points at `$MISE_DATA_DIR/bootstrap-repo/files/…`, and a `copy` entry lands as a regular file (probe 2) |
| A project can ship its own default module list in `.miserc.toml` | No. Under `--from` it was ignored as `.miserc.toml` and as `.config/miserc.toml`, so the override by `miserc.local.toml` could not be tested (probe 3) |
| The user layer can cancel or replace one dotfile entry the project declares | No. `enabled = false` and `mode = "absent"` were both ignored and the project's entry won, although the user's config was read and its own entry applied (probe 4) |
| `--update` on a checkout with an uncommitted change | Fast-forwards when upstream changed a different file. Exits 1 when upstream changed the edited file (probe 5) |
| `copy` and `create_if_missing` entries keep the checkout clean when the target is rewritten, and only the second keeps the user's edit | Yes to both. The update went through, the `copy` target was overwritten and the `create_if_missing` target kept the edit (probe 5) |
| `mise dot origin set`, `sync`, `pull` and a conflict between two Macs behave as documented, and `*.local.toml` stays put | Yes. The shared file arrived, `config.local.toml` stayed, a conflict paused sync without overwriting either side, and `mise dot conflicts` listed the file. An adopted home starts in mode `sync` and accepts `origin set --sync manual` afterwards (probe 6) |
| `-E work` with `--save-env` selects `mise.work.toml` in a project on later runs | Yes. It wrote `env = ["work"]` to `miserc.local.toml`, and a run without `-E` applied the profile again (probe 7) |
| `mise bootstrap unapply <module>` removes that module's dotfile entries and nothing else | Yes, run in the checkout with no trust error (probe 8) |
| `--from <url> --config-dir <dir>` links the config dir into the checkout, and a `*.local.toml` written there does not block `--update` | Yes. The file shows as untracked in the checkout's `git status` (probe 9) |
| `--from <url> --from-dir <clone>` on a clone with uncommitted edits, on a branch other than the ref | The install applies from the clone as it is. `--update` switches the clone to the ref's branch and exits 0. The edit survives both (probe 10) |
| `--only final-hook` with `--from` and `--config-dir` clones and links and applies nothing, and the repository needs no root `mise.toml` | Yes to both (probe 11) |
| A `config.<env>.toml` in the config dir redeclares a `conf.d` dotfile entry, for a file and for a linked folder, and the selection saved by `--save-env` holds for a later `mise dotfiles apply` | Yes: the file became a seeded copy, the folder a real one, and the second apply kept both (probe 12) |
| The fetch-only call with `--update` fast-forwards the checkout | Yes, exit 0 (probe 13) |
| The install line's exact flags (`-E installed --save-env --only final-hook`) save the selection | Yes (probe 14) |
| After `mise dotfiles apply` redeclares the config dir link through `~/dotfiles`, the next `--update` still works | Yes: mise left its own link as it was (probe 14) |
| An environment file that arrives in an update turns an existing linked folder into a real one | No. mise warns that a symlink is never followed and creates the per-file entries through the link, inside the checkout. `setup.sh` on an installed copy must remove the link first (probe 14, P1 Task 4) |
| A `config.<name>.toml` in the config dir adds its packages only when the `env` list in `miserc.local.toml` names it | Yes. Without the list only `conf.d` loaded; with `env = ["fonts"]` the module's cask joined the base's formulae (P2 plan, 2026-11-12, mise 2026.11.5, a scratch home on the owner's Mac, status and dry-run calls only) |
| An `env` entry with no `config.<name>.toml` is an error | No. The other named modules loaded and nothing was reported (P2 plan, 2026-11-12, mise 2026.11.5, a scratch home on the owner's Mac, status and dry-run calls only) |
| `MISE_ENV` adds to the saved `env` list | No. It replaced the list, as the docs say `-E` does (P2 plan, 2026-11-12, mise 2026.11.5, a scratch home on the owner's Mac, status and dry-run calls only) |
| A `[bootstrap.brew.taps]` entry and `[tools]` in a module merge with the base's | Yes to both. A dry run resolved a module's tap formula through the module's tap, and a module's tool was listed only while the module was named (P2 plan, 2026-11-12, mise 2026.11.5, a scratch home on the owner's Mac, status and dry-run calls only) |
| A more local file can cancel one package the base declares | Yes, with `{ state = "absent" }` only, from `config.local.toml` or a module: status reported the key as `absent`. `false` and `{ enabled = false }` are parse errors. Measured for a `brew:` key (P2 plan, 2026-11-12, mise 2026.11.5, a scratch home on the owner's Mac, status and dry-run calls only) |
| One tool can be switched off from `config.local.toml` | Yes: `[settings] disable_tools = ["npm:prettier"]` (P2 plan, 2026-11-12, mise 2026.11.5, a scratch home on the owner's Mac, status and dry-run calls only) |
| A name in the saved `env` list reaches a project's files | Yes. With `env = ["security"]` a project's `mise.security.toml` was loaded in that project. With `env = ["rotm-security"]` and `config.rotm-security.toml` the module loaded and the project's file did not. So module names carry a `rotm-` prefix. P1's `installed` environment had the same exposure, so it was renamed `rotm-installed` on 2026-11-12, and `setup.sh` rewrites the old name in a copy that saved it (P2 plan, 2026-11-12, mise 2026.11.5, a scratch home on the owner's Mac, status and dry-run calls only) |
| A project's own `.miserc.toml` with an `env` list displaces the saved one | No. The module still loaded inside that project (P2 plan, 2026-11-12, mise 2026.11.5, a scratch home on the owner's Mac, status and dry-run calls only) |
| `state = "absent"` works on a `vscode:` key (a plugin manager) | Yes. Status reported an extension that is not installed as `absent`, and an installed one as `unexpectedly_installed` with `desired_state` `absent`. Neither was installed or removed (P2 Task 1, mise 2026.11.5) |
| What `packages apply` exits with when an installed package is declared absent | 1 with `--manager vscode` ("vscode does not support declarative package removal"), 0 with a warning when no manager is named. `setup.sh` passes `--manager`, so it has to read the states. Measured for `vscode` against the fake `code` in `bin/lib/test-packages`, which pins both (P2 Task 1, mise 2026.11.5) |
| With modules as `config.rotm-<name>.toml`, a Mac with no `env` list, or a shell with `MISE_ENV` or `-E` set, keeps its modules | No to each. Only the base loaded: the module's package and tool were gone. So the `env` list fails off (P2 plan after Task 3, 2026-11-12, mise 2026.11.5, a scratch home on the owner's Mac, status, ls and doctor calls only) |
| A `conf.d` fragment's packages, taps and tools load with no state, and under `MISE_ENV` | Yes to both (P2 plan after Task 3, 2026-11-12, mise 2026.11.5, a scratch home on the owner's Mac, status, ls and doctor calls only) |
| `ignored_config_paths` in `miserc.local.toml` switches one `conf.d` fragment off | Yes. Its package and tool left status and `ls`, the other fragments stayed, `mise doctor` listed the file, and `env = ["installed"]` beside it was still honoured. Under `[settings]` in `config.local.toml` the key did nothing (P2 plan after Task 3, 2026-11-12, mise 2026.11.5, a scratch home on the owner's Mac, status, ls and doctor calls only) |
| Which path form `ignored_config_paths` matches | A path relative to the miserc's dir (`conf.d/60-rotm-security.toml`) matched through the `~/.config/mise` link, with `MISE_CONFIG_DIR` set to the real path, and from a project dir. An absolute real path did not match through the link. A listed path with no file was ignored without a warning (P2 plan after Task 3, 2026-11-12, mise 2026.11.5, a scratch home on the owner's Mac, status, ls and doctor calls only) |
| `mise -E <env> bootstrap --save-env` keeps the other lines of `miserc.local.toml` | Yes. It rewrote only the `env` line and kept an `ignored_config_paths` line, a comment and an unknown key. It replaced the `env` list (`installed` became `work`), it did not add to it, which P4's profile switch has to allow for (P2 plan after Task 3, 2026-11-12, mise 2026.11.5, a scratch home on the owner's Mac) |
| `MISE_IGNORED_CONFIG_PATHS` in a shell adds to the saved `ignored_config_paths` | No. It replaced the list: the saved module loaded again (P2 plan after Task 3, 2026-11-12, mise 2026.11.5, a scratch home on the owner's Mac) |
| `mise ls --global` counts a tool a `conf.d` fragment declares | Yes, and not one whose fragment is ignored (P2 plan after Task 3, 2026-11-12, mise 2026.11.5, a scratch home on the owner's Mac) |
| What `packages apply --manager brew-cask` exits with when an installed cask is declared absent | 1, with "brew-cask does not support declarative package removal (cannot remove warp)". `setup.sh` reads the states, finds nothing missing and carries on to "All done" (P2 plan's VM proof, row 5, mise 2026.11.6) |
| `mise prune` deletes the tools of a module that was switched off | Yes, so it honours `ignored_config_paths` from `miserc.local.toml`. With `kubernetes` off, `sysup` removed that module's six tools and left its formula `helm` (P2 plan's VM proof, row 4, mise 2026.11.6). It also removes the `ruby` mise installs for itself to read a tap formula built from source |
| A real install with a module ignored | Yes. Four modules off, and all twelve off, each ended "All done" from a fresh guest (P2 plan's VM proof, rows 1 and 2, mise 2026.11.6) |
| What `mise bootstrap packages upgrade --yes` exits with when an installed package is declared absent | 0. Pinned for a `vscode:` key in `bin/lib/test-packages` (mise 2026.11.5), and `sysup` reported "packages: up to date" with an installed cask declared absent (P2 plan's VM proof, row 5, mise 2026.11.6) |
| One anonymous install fits GitHub's 60 API calls an hour | Yes for one install, no for an install, three updates and two `sysup` runs from one address in the hour. Installing `brew:gh` alone made no rate-limited call, so `setup.sh` offers `gh auth login` before the package lists (P2 plan's VM proof, mise 2026.11.6) |
| mise's sync can save the files that hold a user's choices where P1 and P2 put them | No. `config.override.toml` and `modules-off.local` sit in the config dir, which is a link into mise's checkout under its data dir, and every save left them out as "mise internal directory". The two `*.local.toml` files were left out as "machine-local configuration". Only `~/.zsh.local` reached the origin (P3 research, 2026-11-12, mise 2026.11.5, two scratch homes on the owner's Mac shaped like an installed copy, a local bare repository as the origin) |
| `mise dot track` keeps an installed copy fast-forwardable | No. It wrote its `[dotfiles]` entry into `config.toml`, a tracked file of the checkout, which then showed as modified. `mise dot origin set` wrote `[history.origin]` and the sync mode into `config.local.toml` (P3 research, 2026-11-12, mise 2026.11.5, two scratch homes on the owner's Mac shaped like an installed copy, a local bare repository as the origin) |
| A `mode = "track"` entry written by hand in `config.local.toml` is honoured | Yes. `mise dot paths` listed it, the save and the publish included its files, and the checkout stayed clean (P3 research, 2026-11-12, mise 2026.11.5, two scratch homes on the owner's Mac shaped like an installed copy, a local bare repository as the origin) |
| `config.override.toml` can be a link to a real file outside the checkout | Yes. mise read the value through the link, and `mise set --override` wrote into the real file and left the link in place (P3 research, 2026-11-12, mise 2026.11.5, two scratch homes on the owner's Mac shaped like an installed copy, a local bare repository as the origin) |
| A folder outside the checkout (`~/.config/rotm` in the probe) holding the override file and `modules-off.local` syncs between two installed copies | Yes. Both files reached the origin. On a second installed copy `mise bootstrap --adopt <origin>` created them in the same folder and left that checkout clean. An edit on the second copy arrived on the first with `mise dot sync` then `mise dot pull`, written into the real file behind the link. `config.local.toml` did not travel, so the second copy has no track entry of its own and no links in the config dir until something writes them (P3 research, 2026-11-12, mise 2026.11.5, two scratch homes on the owner's Mac shaped like an installed copy, a local bare repository as the origin) |
| `mise bootstrap --adopt <origin>` only restores the tracked files | No. It then ran a full bootstrap and applied a `[dotfiles]` entry of the base. With `--only final-hook` it restored the files and applied nothing (P3 plan, 2026-11-12, mise 2026.11.5, scratch homes on the owner's Mac) |
| mise's override file can hold more than `[env]` | Yes. A `[bootstrap.macos.defaults."<domain>"]` key, a `[bootstrap.packages]` entry with `state = "absent"` and `[settings] disable_tools` in it each took effect over `conf.d`, and `mise set --override` kept those tables (P3 plan, 2026-11-12, mise 2026.11.5, scratch homes on the owner's Mac) |
| mise needs Git credential configuration to reach a private origin | Not by what it runs: every Git call it made carried its own helper for github.com, `mise token github --git-credential`. Not yet run against a real private repository (P3 plan, 2026-11-12, mise 2026.11.5, scratch homes on the owner's Mac) |
| `config.rotm-installed.toml` can turn one file of the `~/.claude/rules` `symlink-each` folder into a seeded copy | Yes. Redeclaring the folder with `exclude = [".DS_Store", "jstack-models.md"]` and adding that file as `mode = "copy", create_if_missing = true` left the other nine rules links and the file a regular copy of the tracked one, and a user's edit to it survived a second apply. On an install made before the change, where the file is still a link, the first apply removed the link and wrote no copy (exit 0, `status --missing` then exits 1) and the second apply seeded it (P3 plan, 2026-11-12, mise 2026.11.5, scratch homes on the owner's Mac) |
| What `mise dot conflicts` prints and exits with | With no conflict, "mise no sharing conflicts" on stderr. With one, `Conflict: <path> (<reason>)` and a diff on stdout. Exit 0 both ways, so `sync.py` and `rotm-user-layer` read both streams and decide from the text (P3 execution, 2026-11-13, mise 2026.11.5, scratch homes on the owner's Mac, the harness of `bin/lib/test-sync`) |
| What `mise dot sync` and `mise dot pull` exit with while a conflict pauses sync | `sync` exits 0 and warns that a conflict needs a decision. `pull` exits 1 with "sync paused". So `sync.py` checks for a conflict when a mise call fails, and again after the pull (P3 execution, 2026-11-13, mise 2026.11.5, scratch homes on the owner's Mac, the harness of `bin/lib/test-sync`) |
| mise's secret scan stops a token before it is saved | No. `mise dot save` wrote a `GITHUB_TOKEN` line of the override file into the local history and exited 0. The scan ran at `mise dot sync`, which exited 1 with "cannot publish" and named the saved version, and nothing reached the origin. So the guard in `sync.py` runs before the save (P3 execution, 2026-11-13, mise 2026.11.5, scratch homes on the owner's Mac, the harness of `bin/lib/test-sync`) |
| Both pull flags decide a conflict between two connected Macs | Yes, with the path as mise prints it, `'~/.config/rotm/config.override.toml'`. After `--keep-local` and `sync now`, the other Mac's `sync now` loaded that value. `--take-remote` wrote the saved value (P3 execution, 2026-11-13, mise 2026.11.5, scratch homes on the owner's Mac, the harness of `bin/lib/test-sync`) |
| A restore onto a folder that already holds a different file can be decided either way | Only with `--take-remote`. The listing reads "(unsaved edits: save or discard them first)" and its diff shows the local side as empty, though the file is untouched. `mise bootstrap --adopt` exits 1 with the origin connected in mode `sync`, so `rotm-user-layer restore` carries on past an adopt that holds a conflict: manual mode, the track entry and the links are written, then it exits 1 with the listing. `--keep-local` is refused ("it has no saved version on this machine yet"). Any `mise dot save` there, `sync now`'s included, starts a local history unrelated to the origin's, after which every pull flag fails, so `sync now` checks for a conflict before it saves. `--take-remote` then `sync now` loaded the saved values. Copying the file aside, `--take-remote`, copying it back and `sync now` kept this Mac's value, and the first Mac loaded it (P3 execution, 2026-11-13, mise 2026.11.5, scratch homes on the owner's Mac, the harness of `bin/lib/test-sync`) |
| A `config.<env>.toml` file can change a setting the user saved with `rotm settings set` | No. `config.override.toml` and `config.local.toml` both beat it (P4 plan, 2026-11-13, mise 2026.11.5, 2026.11.7 and 2026.11.8; the harness is `2026-11-13-p4-probe/probe.sh`, in scratch homes on the owner's Mac and in the UTM guest) |
| `config.<env>.override.toml` beats `config.override.toml` when `<env>` is in the saved `env` list | Yes, for an `[env]` key, a macOS default, a package marked `state = "absent"` and `[settings] disable_tools`. A key it does not set comes from the shared override file (P4 plan, same runs) |
| `mise set --override --env <env>` with no file present | Creates the file in the config dir, which on an installed copy is the checkout. With the file made first in `~/.config/rotm` and linked, mise writes through the link and the checkout stays clean. So `profile new` makes and links the files, and a write to a profile with no file is refused (P4 plan, same runs) |
| `mise unset --override --env <env> KEY` removes the key from the profile's file | No. It exits 0 and leaves the key. `mise unset --file <path> KEY` removes it, through a link too, so the adapters name the file (P4 plan, same runs) |
| mise can write the `env` line | Yes. `mise -E a,b bootstrap --save-env --only final-hook` writes it, keeps the `ignored_config_paths` line and applies nothing. With no `-E` it errors and leaves the file, so leaving the last profile on a clone removes the line with our own edit (P4 plan, same runs) |
| What drops the saved profile in one shell | `MISE_ENV=<other>` does, and the shared override values stay. `MISE_ENV=<other>,rotm-p-work` keeps it. A project's `.miserc.toml` with its own `env` list does not drop it (P4 plan, same runs) |
| A name in the saved `env` list only selects global config | No. It also loads a project's `mise.<name>.toml`, which is why a profile's environment carries the `rotm-p-` prefix (P4 plan, 2026-11-13, mise 2026.11.5) |
| The track entry on `~/.config/rotm` saves a profile's files | Yes. They reached the origin, and a second home got them with its checkout clean. `bin/lib/test-sync` now exchanges a profile between two Macs (P4, 2026-11-13, mise 2026.11.8) |
| `mise env --dotenv` prints values raw | Only up to 2026.11.5. From 2026.11.6 it quotes a value that holds `#` or `"`, which `zsh/override-env.zsh` then quoted a second time: a shell that never prompts exported the quotes as part of the value. `mise env -s zsh` prints `export` lines that are correct to source on every version measured, and the cache reads those since `61d3baa` (P4 plan, 2026-11-13, guest runs on 2026.11.7 and 2026.11.8) |
| `[bootstrap.settings.macos.defaults]` is read | From 2026.11.8, with no warning. 2026.11.5 and 2026.11.7 answer "unknown field". 2026.11.8 still reads `[bootstrap.macos.defaults]` and prints no warning for it yet. Where both spellings set a key, the file's rank decides, not the spelling. `[[bootstrap.settings.macos.defaults_entries]]` and the named sections are read under the new table too (P4, 2026-11-13, the guest and a scratch home on the owner's Mac) |
| The `macos-defaults` part still applies the renamed table | Yes. `mise bootstrap --skip macos-defaults --dry-run` lists no `defaults write`, so `setup.sh`'s skip holds. `--only settings`, a part new in 2026.11.8, applied nothing (P4, 2026-11-13, mise 2026.11.8, a scratch home on the owner's Mac) |
| `mise self-update` installs a release on the day it is published | No. It holds a release back 24 hours ("minimum release age"). The installer takes a version by name (`MISE_VERSION=v2026.11.8`), which is how the guest and the owner's Mac got 2026.11.8 on its release day. The floor never names a release younger than a day (P4, 2026-11-13) |
| The self-checks pass on a mise newer than 2026.11.5 | Yes on 2026.11.8: `pnpm check` passes on the owner's Mac with only the version strings changed, `bin/lib/test-sync` and `bin/lib/test-modules` included. mise still refuses an ignored module file as untrusted, so `rotm-modules` keeps its `mise trust` call (P4, 2026-11-13) |
| mise reports a package's status offline | No. `mise bootstrap packages status` fetched a cask's metadata and failed with a 404 for a made-up cask, so `bin/lib/test-profiles` checks a module switch through an `[env]` key (P4, 2026-11-13, mise 2026.11.8) |

### Still not verified

| Claim | What settles it |
| --- | --- |
| A real install and a real `rotm update` under the `rotm-installed` name | Not run in the VM: the owner chose on 2026-11-12 to skip it and triage any issue in a later plan. The self-checks cover the rename (`test-dotfiles` applies the environment in a scratch home, `test-bootstrap` the rewrite of an old saved name) |
| A project's `.miserc.toml` is read when `mise bootstrap` runs from inside the checkout, without `--from` | Not measured. It matters only if a later run stops passing `--from` |
| What an adopted home in mode `sync` does once the history watcher is declared | P3, in the VM, against a real private repository |
| Sync against a real private GitHub repository, with mise's own credential helper as the only source | Not run: every self-check uses a local bare repository. The VM proof (P3 plan, Task 9 Step 6) settles it, and it is owed before any promotion of `stable` |
| `gh auth login` on a terminal writes a Git credential helper into `~/.gitconfig` | Read in gh's code by a delegate during P3, never run. `setup.sh` has run a plain `gh auth login` since P2, and `sync on` runs it with `--git-protocol https --web`. The VM proof settles it: compare `~/.gitconfig` before and after the sign-in |
| A profile switch on a real install | Not run in the VM. On a fresh guest after an install: make a profile, use it, change one env setting, one macOS preference and one module, run `rotm install` and `set-defaults`, then `profile use default` and confirm each is back (P4 plan, Task 11 Step 3). Owed with P3's proof before any promotion of `stable` |
| The shipped fragments install on mise 2026.11.8 | The self-checks and a dry run pass on it. A full install on a fresh guest has not run since the floor was raised and the macOS table renamed |

Measured on this Mac on 2026-11-11: `mise --version` prints 2026.11.5, and `mise dot --help` lists `origin`, `sync`, `pull`, `track`, `conflicts` and `exclude`.

Also measured that day: with `HOME` and every `MISE_*_DIR` pointed at a scratch folder, `mise config ls` run from inside this repository still listed the real `~/.config/mise/conf.d/*.toml`, because mise reads config from every parent of the current directory. Run from the scratch home it listed nothing. Two consequences. The probe harness runs every mise command from the scratch home and checks this before anything else. And the install and update commands in P1 must say which directory they run from, as `setup.sh` and `bin/dotfiles-settings` already do by changing to `$HOME`.

## Plans

- `docs/superpowers/plans/completed/2026-11-11-p0-probes-and-model-default.md` (done 2026-11-11): the probes in a scratch home, and the `claude-config save` model rule. Its results fill in this spec and decide the open points.
- `docs/superpowers/plans/completed/2026-11-11-p1-install-and-update.md` (done 2026-11-12): the config-dir shape, mise to fetch and link followed by `setup.sh`, the `rotm` command, and an `installed` config environment for targets apps rewrite.
- `docs/superpowers/plans/completed/2026-11-12-p2-modules-and-opt-outs.md` (done 2026-11-12): twelve modules as always-loaded `conf.d/60-rotm-<name>.toml` files, a helper that derives mise's `ignored_config_paths` line from what is switched off, a switch per module in `dotfiles-settings`, and `--without` on the install line. The owner split P2 that day, and withdrew the split-off half (P2b) the same evening.
- `docs/superpowers/plans/completed/2026-11-12-p3-sign-in-and-sync.md` (done 2026-11-13): a user's folder outside the checkout that mise's history tracks, mise's override file for every setting mise can hold, `tools.toml` for the rest, and `rotm settings sync on|off|now|status|apply`. Its proof in the VM against a real private repository is still owed (its Task 9, Step 6).
- `docs/superpowers/plans/completed/2026-11-13-p4-profiles.md` (done 2026-11-13): a profile as a config environment named `rotm-p-<name>` with its own `config.<env>.override.toml`, a module list and a `tools.toml` per profile, and `rotm settings profile list|use|new` with `--shared` on `set` and `reset`. Its first three tasks fixed the shell cache reading values mise quotes from 2026.11.6, raised the mise floor to 2026.11.8 and moved the macOS preferences to `[bootstrap.settings.macos]`. Its measurements are in `2026-11-13-p4-probe/` beside this file. Its proof in the VM is still owed (its Task 11, Step 3).
- `docs/superpowers/plans/2026-11-13-p5-menu-bar-app.md` (written 2026-11-13, not started): the menu bar app as a Swift package in `app/`, the JSON it needs from `rotm settings`, a console for update, setup and the sign-in, a native settings window, a `menubar` module with a cask in the owner's tap, and an update through mise. Its Task 0 is a set of probes the owner runs in the VM.
- P6 and P7 are not written yet. Each gets its own plan file when the one before it has landed. The briefs below are what each plan must be written from.

## Phase briefs

Testing rule for every phase: a real install, update, sync or profile switch is run in the macOS VM, never on the owner's Mac, which is the machine the work is written on. Self-checks with stubs and scratch homes run anywhere, as `bin/lib/test-*` do today. Each plan's Global Constraints repeat this.

How to use these when writing a plan: read the brief, then read "Verified facts" (P0 rewrites the "Not verified" table into it), then read what the earlier phases actually shipped (`git log`, the completed plans, the code). Where a brief and the shipped code disagree, the code wins and the plan says so in one line. Each brief lists what was known on 2026-11-11 and what it was waiting on.

### P1: Install and update without a clone

- **Outcome.** On a Mac with only mise, one documented command installs the setup, a second updates it, and neither needs the user to clone, fork or edit our repository. `./setup.sh` from a clone still works for the owner.
- **Delivers.** The chosen shape from Distribution (project or config-dir). An `update` command that runs `mise bootstrap --from <url> --update` with the flags `setup.sh` passes today. A decision for every `[dotfiles]` entry: symlink, `create_if_missing` copy or `merge` edit. `$DOTFILES` and the `~/dotfiles` link resolved for a checkout under `~/.local/share/mise/bootstrap-repo`.
- **Known.** `setup.sh` does more than `mise bootstrap`: it installs packages one manager at a time so a failure only warns, skips `macos-defaults`, runs `mise install` itself, runs the task as a second call, then `setup/dotfiles-extras.sh` (see `setup/README.md`). An install from mise alone has no `setup.sh`, so each of those either moves into the config (hooks, the `bootstrap` task) or the install command becomes "run mise, then run our script from the checkout". `40-dotfiles.toml` has 38 entries, 36 of them with a `~/dotfiles/…` source.
- **Shipped.** `docs/superpowers/plans/completed/2026-11-11-p1-install-and-update.md` (2026-11-12): the config-dir shape, the `rotm` command wrapping `dotfiles-settings`, an `installed` (since 2026-11-12 `rotm-installed`) config environment that turns app-written targets into seeded copies, the `stable` branch with its promotion step, and a `fresh-install` job for the installed path. The owner's Mac stays on `setup.sh` from the clone at `~/dev/dotfiles` (decision 7). Renaming `dotfiles-settings`, `$DOTFILES` and the other `dotfiles` names is a later step. Still open: the mise floor (see "Still not verified").
- **VM baseline.** The existing UTM guest named `macOS` is the baseline as it stands. The A6 plan's Task 6 (`docs/superpowers/plans/completed/2026-11-09-a6-bootstrap-entry-point.md`) records it: UTM 5.0.8, guest macOS 27.2.1 (26B131), 4 cores, 8 GB of memory, a 100 GB disk made at that size in the wizard, a local admin account, no Apple ID, and no Command Line Tools, Xcode or Homebrew. Every A6 run used "Run without saving changes", so nothing from this repository is on it; the owner confirmed on 2026-11-11 that it is still a fresh install. Run each first-install test in that disposable mode. The Command Line Tools stay off the baseline on purpose: installing them is the stranger's real first step, since mise needs `git` to clone. A test that must survive a shutdown (install, log out for the login shell, then update) starts from a UTM snapshot instead, restored afterwards. Measured in A6: a full install took the guest's free space from 68 GiB to 29 GiB, and evidence went to the host's `~/vm-proof/` through a shared folder. Not checked: whether a restart inside one disposable run keeps its changes.
- **Done when.** A fresh macOS VM with mise and nothing else reaches the same `mise bootstrap status` as a `setup.sh` run, an upstream commit arrives with the update command, and an app rewriting its config does not block that update. The `fresh-install` workflow gains a job for this path.

### P2: Modules and opt-outs

- **Outcome.** A stranger can decline any group before or after installing.
- **Delivers.** The base split into modules (apps, fonts, VS Code extensions, Claude Code plugins and skills, other agent tooling). A default list with everything on. A switch per module in `dotfiles-settings`. A documented way to skip one item.
- **Known.** `30-packages.toml` declares the formulae, casks and extensions in one `[bootstrap.packages]` table, so splitting it is mechanical. The macOS groups already have switches (`macos.*` in `settings/registry.toml`). `claude-config restore` only adds, so a Claude opt-out means skipping the restore. Turning a module off does not uninstall packages: mise's docs point to `mise bootstrap packages prune`, which is not limited to one module, and `sysup` never runs it for that reason.
- **Shipped.** `docs/superpowers/plans/completed/2026-11-12-p2-modules-and-opt-outs.md` (2026-11-12): twelve modules as always-loaded `conf.d/60-rotm-<name>.toml` fragments, switched off through `ignored_config_paths` by `bin/lib/rotm-modules`, with `--without` on the install line, a `modules.<name>` switch in `dotfiles-settings`, `sysup` and `misc.sh` skipping an off module's steps, and `state = "absent"` for one package. The `env` list of the first design was dropped because it fails off. Proven in the VM on `35dce30`.
- **Done when.** With one module off, a dry run of the install lists none of that module's packages.

### P2b: The owner's layer (withdrawn)

- **Withdrawn by the owner on 2026-11-12.** It was the half of the first P2 brief that moved the 13 owner-specific values in `docs/forking.md` out of the base, split off that morning because it had no design. The owner then decided that nothing leaves the base: what the project installs and configures today is what every user gets, and personalising is the user layer's job (P3). "The owner's layer" always meant the owner's own user layer, never a second kind of layer in this repository.
- **What P3 inherits.** A user can opt out of any part and change any shipped value from their own layer, without editing a tracked file. P2 covers the packages and tools (modules, `state = "absent"`). The values in linked config files are not covered: probe 4 measured that a user's entry cannot cancel or replace a `[dotfiles]` entry the base declares, and fastfetch's folder is one symlink.

### P3: Sign in and sync

- **Outcome.** A user signs in with GitHub once, and their own changes follow them to their next Mac. Nothing that looks like a secret leaves the machine.
- **Scope.** Decisions 13 and 14: every setting `rotm settings` can change, and the opt-outs. On 2026-11-12 the registry held 45 `env` settings and 12 module switches (mise's files, synced by the measured layout), 26 macOS preferences (a tracked fragment, which an installed copy refuses to edit) and 23 agent-tool settings (each tool's own file). The last two groups need a user-side home before they can sync; the plan finds out for each whether mise can hold it.
- **Delivers.** `dotfiles-settings sync on|off|now|status`. Sign-in through `gh`. A private repository created in the user's account. The tracked set and the exclude list. A conflict view. A restore path for a second Mac that composes with P1's install.
- **Known.** mise reads tracking entries only from global and system config, so `dotfiles-settings` writes them into the user's own config, never ours. Connecting an origin shares the whole saved history. mise refuses credential-named files unless `allow_plaintext` is set, and tracked entries can be encrypted. `pull` writes files but does not install tools or render templates, so a pull that changes declarations needs a bootstrap run after it. `mise bootstrap --adopt <setup repo>` is the documented restore, and it and `--from` cannot be combined, so the second-Mac flow is two commands and their order has to be designed. `claude-config save` already has a secrets filter worth reusing as the model for the exclude list.
- **Settled by P0.** Probe 6: sync, local files and conflicts behave as documented, and a restore must set manual mode after `--adopt`.
- **Measured on 2026-11-12 (the last five rows of "Verified facts").** Under the config-dir shape the files that hold a user's choices cannot be synced where they are, and `mise dot track` dirties the checkout. What worked: the user's files live in a real folder outside the checkout, the config dir links to them, and the track entry is written by hand into `config.local.toml`. `--from` and `--adopt` then compose as install first, adopt second. Not designed yet: the folder's name, who writes the links and the track entry on a second Mac, and a home for what cannot sync today (the per-package opt-outs in `config.local.toml`, and the macOS and jstack settings an installed copy refuses to write).
- **Decided.** The base keeps everything it ships today (see P2b, withdrawn), so the user layer must be able to change a shipped value, not only add to the base.
- **Decided.** Manual sync only in this phase. No LaunchAgent, no `[bootstrap.services.mise-history]`. Automatic sync is its own later plan.
- **Shipped.** `docs/superpowers/plans/completed/2026-11-12-p3-sign-in-and-sync.md` (2026-11-13): the user's folder `~/.config/rotm`, linked from the config dir and tracked through an entry that `bin/lib/rotm-user-layer` writes in `config.local.toml`; a `scope = "machine"` field that keeps three settings on their Mac; macOS preferences and the jstack roles file writable on an installed copy; `tools.toml` for the tool settings mise cannot hold; `rotm settings sync on|off|now|status|apply`, with a check for a secret-named key, a check for a stray file and a refusal of a repository that is not private; setup's offer to load saved settings before a first install; and `bin/lib/test-sync`, which runs this brief's "Done when" with real mise in `pnpm check`. Still owed, before any promotion of `stable` (decision 15): the proof in the VM against a real private GitHub repository.
- **Done when.** Two scratch homes exchange a changed setting through a private repository, a `*.local.toml` value stays put, a file holding a token is refused, and a conflicting edit pauses with both versions shown.

### P4: Profiles

- **Outcome.** One Mac, or one user across Macs, switches between named variants such as personal and work.
- **Delivers.** `dotfiles-settings profile list|use|new`. A profile as a config environment, with the choice saved. Per-profile module lists and settings. A rule for which settings are machine-scoped and so ignore profiles.
- **Known.** `-E work` selects `mise.work.toml` or `config.work.toml`, and `--save-env` writes the choice to `miserc.local.toml`. `[env_sets]` names a group of environments, so a profile can be "these modules plus these settings". A dotfile entry can differ by profile with `variants`. `-E` replaces the saved selection for that run and does not add to it, so a profile owns the `env` line of `miserc.local.toml` alone, beside `rotm-installed`: P2's modules never touch it and live in `ignored_config_paths`.
- **Settled by P0.** Probe 7: `--save-env` is remembered. P2 shipped the module list as `modules-off.local` and `ignored_config_paths`.
- **Done when.** Switching profile and applying changes exactly the entries that differ, and switching back restores them.
- **Shipped.** `docs/superpowers/plans/completed/2026-11-13-p4-profiles.md` (2026-11-13): `settings/src/dotfiles_settings/profile.py` and `rotm settings profile list|use|new`; a profile's settings in mise's per-environment override file, its own module off list and tools file; `--shared` on `set` and `reset`; the sync guards, `apply` and the shell cache following the active profile; `bin/lib/test-profiles`, which runs this brief's done-when with real mise, and a profile exchanged between two Macs in `bin/lib/test-sync`. Machine-scoped settings ignore profiles. The mise floor is 2026.11.8 and macOS preferences are declared under `[bootstrap.settings.macos]`. Not run: the switch on a real install in the VM.

### P5: Menu bar app

- **Outcome.** A person who never opens a terminal can see the state, change a setting, switch profile, sync and update.
- **Delivers.** A menu bar app that calls `dotfiles-settings` and shows its output. Packaged and distributed the way `~/dev/claude-multipass` is (its tap, its release flow).
- **Known.** `dotfiles-settings` already has `--json` on `list` and `get`, fixed exit codes, and a browser UI through `serve`. The app adds no logic: every action is one command that also works in a terminal. `set`, `reset` and `apply` change the machine, so the app confirms before each.
- **Waiting on.** P1 to P4 being stable. Read `~/dev/claude-multipass` (its `app/`, `scripts/` and release docs) before writing this plan; that was not done for this spec.
- **Done when.** Each menu action produces the same result as its command, on a Mac that installed through P1.

### P6: Docs for the new path

- **Outcome.** The README leads with the install-from-mise command, and a stranger can follow it without reading the rest.
- **Delivers.** README quick start for installed mode. `docs/installation.md` split into installed mode and clone mode. `docs/forking.md` rewritten around the user layer. A page on sync and profiles. An update to `docs/updating.md`.
- **Known.** The README was rewritten on 2026-11-11 as a short landing page with the detail in four `docs/` pages. A new docs page must not be named after a command, because `help <name>` reads `docs/<name>.md` before tldr.
- **Waiting on.** Everything above. Each earlier phase updates the docs it makes false in its own commits; P6 is the pass that reorders them around the new default.
- **Done when.** `docs-auditor` finds no claim in the README or `docs/` that the shipped code contradicts.

### P7: The owner's Mac moves to stable

- **Outcome.** The Mac this project is written on runs an install from `stable`, like any user's, and has `rotm`.
- **Decided.** By the owner on 2026-11-12: last, after every phase above has landed. Until then that Mac stays on `setup.sh` from the clone, the owner is the only consumer, and nothing is promoted to `stable`. The move is done once, by hand: no command, flag or `setup.sh` branch is added to the product for it, and moving a clone-based Mac to an install is not a path users get.
- **Known.** Probe 10: `--update` with `?ref=stable` switches a clone given as `--from-dir` from `main` to `stable`, so the working clone cannot be the installed copy. `~/dotfiles` has to point at the installed copy instead of the clone. `setup.sh` unlinks the folders `config.rotm-installed.toml` makes real, but only the VM has run that, from a fresh home. The gitignored local files under the clone's `tilde/.config/mise/` and `mole/*.local` do not come with a fresh copy.
- **Waiting on.** P3 to P6, a promotion of `stable` proven in the VM (decisions 9 and 10), and a written runbook for the hand move, including how the development clone and the installed copy live on one Mac.
- **Done when.** `bin/lib/rotm-mode` prints `installed` on that Mac, `rotm update` brings a new `stable` commit, and work in the clone at `~/dev/dotfiles` changes nothing in the live config until it is promoted.

## Open points for the owner

The three that were here (the name, the owner's Mac, background sync) are decisions 6 to 8.

One, raised and answered on 2026-11-12: a few shipped values are facts about the owner, not preferences, and are wrong for anyone else until changed. fastfetch prints the owner's name, site and city (`tilde/.config/fastfetch/config.jsonc`), lazygit's `authorColors` names the owner, and `macos.disable_time_machine` defaults to on, which stops a user's backups when they run `set-defaults`. The owner's answer: they ship as they are, and the docs say so. `docs/forking.md` ("Make it yours") lists each value that points at the owner or the owner's domain and what a user changes to use that feature themselves. Today that page is written for someone who forks; P6 rewrites it around the user layer, and until then a new owner-pointing value gets its row there in the same commit.

## Research notes (2026-11-11)

- **How new the mise features are.** None of the bootstrap or dotfiles pages is marked experimental. A text search of mise's `CHANGELOG.md` puts the first mention of `brew-cask` in 2026.6.15, `unapply` in 2026.7.16, `dot origin` in 2026.8.15 and `--from` in 2026.9.2; `--config-dir` and `--save-env` are not named in the changelog at all. mise was at 2026.11.7 with 449 releases listed. The search is approximate, so probe 1 reports which flags the installed mise has. This is why decisions 9 and 10 exist: young features on a tool that ships almost daily.
- **Secrets in sync.** mise can encrypt a tracked file with age before it reaches Git (`encrypt = true`, recipients in `[history.encryption]`), must be set up before the file's first save, and never saves `*.local.toml` even with encryption on. Deleting or untracking a file later leaves its old versions in history.
- **Conflicts.** `mise dot conflicts <file>` prints a diff; `mise dot pull --take-remote <file>` or `--keep-local <file>` decides one file, and `--take-remote-all` / `--keep-local-all` decide all. Incoming files apply only once every conflict is decided. This is the whole surface the P3 conflict view needs.
- **GitHub relay.** `mise ssh --github-relay-read-only` lends this machine's GitHub read access to a remote host for one session. Not needed for a Mac the user sits at; noted for a later remote-install feature.
- **Names considered.** About ninety candidates were checked against Homebrew and npm over six rounds. Ruled out for collisions: `pantry` (pkgx's package repository), `kitout` (a GitHub project that sets up a Mac declaratively), `yeschef` (Claude Code tooling), `hermit` and `ellipsis` (existing tools in this space), `messkit` (a company at messkit.app), `footlocker` (a retail trademark). Runners-up at the time: `dittybag`, `loadout`, `enplace`. Screened on 2026-11-11 against PyPI, crates.io, npm, Homebrew and GitHub: `dittybag` and `enplace` are free on all five registries (both GitHub user names are taken, and `djcp/enplace` is a one-star recipe CLI); `loadout` is taken on PyPI, crates.io and npm, and `migsilva89/loadout` (104 stars) manages what coding assistants load, so it is out. `kitbag` itself then fell to a wider check: PyPI has a `kitbag` developer CLI (0.3.0, July 2026) that owns the command and `~/.kitbag/`, and `TomaszJanusz/kitbag` (created 2026-10-24, 93 commits) is a Go CLI of that name that syncs coding agents' config between machines and plans a Homebrew formula. The US mark KITBAG (4861547, Fanatics) is live for Class 35 sporting-goods retail only. The owner passed on 24 screened alternatives in the same vein and asked for pop-culture names; 333 more were screened on the five registries, 230 were free, and `returnofthemac` was the pick. Good names lost to a single registry: `moredots` and `zugzug` (npm), `jobsdone` (PyPI).
