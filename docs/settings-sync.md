# Settings sync: your settings on your next Mac

`rotm settings sync` saves the settings you changed with `rotm settings`, and the parts you opted out of, to a private GitHub repository in your own account. Your next Mac loads them, so you do not configure it a second time. Sync is manual. Nothing is saved, sent or loaded until you run one of the commands on this page.

## What is saved

Sync saves one folder, `~/.config/rotm`, which holds three files:

| File | What it holds |
| --- | --- |
| `config.override.toml` | The settings that `rotm settings` stores as environment variables, the macOS preferences you changed on an installed copy, and the [single packages and tools you skipped](modules.md#skipping-one-package-or-tool) |
| `modules-off.local` | The [modules](modules.md) you switched off |
| `tools.toml` | The agent-tool settings you changed with `rotm settings`, such as the Claude Code default model and the jstack roles |

Each [profile](#profiles) adds up to three files of its own beside them, named after it.

## What is never saved

- The three settings that describe one Mac: the computer name (`macos.computer_name`), the local hostname (`macos.local_hostname`) and the Hindsight opt-in paths (`hindsight.paths`).
- Every `*.local.toml` file in mise's config dir, `config.local.toml` and `miserc.local.toml` among them. mise never syncs a file with that ending.
- `~/.zsh.local`, `~/.gitconfig.local` and `~/.ssh`, the [per-Mac files](local-customizations.md).
- A change that another program made to a tool's file. `tools.toml` records a setting when `rotm settings` sets or resets it. A role that `/jstack:setup-jstack` wrote, or an edit you made to `~/.claude/settings.json` by hand, stays on that Mac.
- A macOS preference changed on a clone. There `rotm settings` edits the tracked `20-macos.toml`, and you commit the change. A preference that your saved settings already hold, because you changed it on an installed copy, is the exception: it is changed and reset in `config.override.toml`, and sync saves it.

## The commands

| Command | What it does |
| --- | --- |
| `rotm settings sync on` | Connects this Mac. It signs in to GitHub through `gh` when `gh` is not signed in. With no repository yet, it creates the private repository `rotm-settings` in your account and saves your folder to it. When that repository already holds saved settings, it loads them onto this Mac. `--repo NAME` uses another repository name |
| `rotm settings sync now` | Saves this Mac's changes, sends them, and loads what your other Macs sent. Run it after you change a setting, and then on each other Mac to receive the change |
| `rotm settings sync status` | Shows the repository, what is not saved or loaded yet, and any conflict. It changes nothing |
| `rotm settings sync off` | Disconnects this Mac. The folder, the repository and its history stay |

A fifth command, `rotm settings sync apply`, puts loaded settings into effect without the network. `on` and `now` run it for you, and [one case](#during-the-first-install) needs it by hand.

The sign-in needs a terminal. There `sync on` runs `gh auth login --hostname github.com --git-protocol https --web`, which opens GitHub in your browser. Without a terminal it stops and names that command.

The [Sync section of the settings README](../settings/README.md#sync) lists the exit codes and the mise commands behind each action.

## Load your settings on a second Mac

### During the first install

After the GitHub login that setup offers, setup looks in your account for a private repository named `rotm-settings` that holds saved settings. When it finds one, it asks whether to load your saved settings before installing. Press Enter to load them.

- The settings load before any package is installed, so a module you switched off on the first Mac is not installed on this one.
- The agent-tool settings are applied at the end of the run, when the tools exist.
- With `-y` or without a terminal, setup does not ask. It prints that `rotm settings sync on` loads them later.
- Setup looks only for the name `rotm-settings`. If you passed `--repo` on the first Mac, load the settings [after the install](#after-the-install).

If that setup run fails after it loaded your settings, run setup again as you would after any failure. The second run finds this Mac already connected. It does not ask again, and it does not apply your saved agent-tool settings. When setup has finished, apply them yourself:

```shell
rotm settings sync apply
```

[Installation](installation.md#run-setup) describes the rest of that run.

### After the install

```shell
rotm settings sync on
```

Add `--repo NAME` if you chose another repository name on the first Mac. The command loads your saved settings and puts them into effect.

If you already changed a setting or switched a module off on this Mac, its files differ from the saved ones and the command stops with a conflict. See [when this Mac's folder already held a different file](#when-this-macs-folder-already-held-a-different-file).

## Finish a sync with `rotm install` and `set-defaults`

Loaded settings take effect without another command where they can. A new terminal has the new environment variables, mise stops loading a module that arrived switched off, and each agent tool has its saved setting.

Two things remain, and the sync command prints a line that names the command for each:

- **Packages.** Sync installs nothing and removes nothing. Run `rotm install` to install what is now on, such as a module that arrived switched back on. A module or a package that arrived switched off stays installed, and [Modules](modules.md#switching-a-module-off-or-on) says how to remove it.
- **macOS preferences.** Sync does not write them. Run `set-defaults`.

When setup loaded your settings during the first install, that run installed with them, so only `set-defaults` remains.

## Profiles

A profile is a named variant of your settings, such as `work` beside what you use at home. Switching to it changes what differs, and switching back restores what was there.

| Command | What it does |
| --- | --- |
| `rotm settings profile new work` | Makes the profile `work`. It starts with no settings of its own and a copy of your module switches. The name is up to 31 lowercase letters, digits or hyphens |
| `rotm settings profile use work` | Switches this Mac to `work`. Open a new terminal afterwards. It prints the `rotm install` and `set-defaults` lines when the switch changed modules, packages or macOS preferences |
| `rotm settings profile use default` | Leaves the profile. `default` is the name for your shared settings alone |
| `rotm settings profile list` | Lists the profiles and marks the one in use |

**What a profile holds.** Only what you changed while it was in use. A setting the profile does not set comes from your shared settings, so a change to a shared setting reaches every profile that has no value of its own for it. The files are in `~/.config/rotm`:

| File | What it holds |
| --- | --- |
| `config.rotm-p-work.override.toml` | The profile's environment-variable settings, macOS preferences and skipped packages. It is laid over `config.override.toml` |
| `modules-off.rotm-p-work.local` | The modules that are off in the profile. This list is the profile's own copy and does not follow the shared list: a module you switch off for everything later stays on in a profile made earlier |
| `tools.rotm-p-work.toml` | The agent-tool settings changed in the profile, laid over `tools.toml`. It exists once you change one |

**Where a change goes.** While a profile is in use, `rotm settings set` and `reset` change the profile. Add `--shared` to change your shared settings instead:

```shell
rotm settings set --shared shell.editor vim
```

When the profile has its own value for that setting, the profile's value stays in effect there and the command says so. `rotm settings reset <id>` removes the profile's value, and the shared one shows through. A second `reset` removes the shared value. The three settings that [describe one Mac](#what-is-never-saved) ignore profiles.

**Which Mac uses which profile.** Sync carries every profile to every Mac, and each Mac chooses for itself. A profile made on one Mac appears in `profile list` on the next after `rotm settings sync now`, and that Mac stays on `default` until you run `profile use` there.

Two things turn a profile off without `profile use`:

- **`MISE_ENV` in a shell.** mise uses that variable in place of the saved profile, in that shell only. `profile list` says when it is set. `MISE_ENV=staging,rotm-p-work` keeps the profile.
- **Running the install line again.** The line in [Installation](installation.md) names its own environment, which replaces the saved choice, so this Mac is back on `default`. The profile's files are untouched and one `profile use` restores it. `rotm install` and `rotm update` keep the profile.

There is no command to delete or rename a profile. Switch away from it, then delete or rename its three files in `~/.config/rotm` and the links of the same names in `~/.config/mise`.

## What stops a save

`sync on` and `sync now` check the folder before every save. When a check fails, the command exits 1, names what it found and saves nothing.

- **A file that is not one of the three, or one of a profile's.** mise would save it with the rest. Finder leaves a `.DS_Store` file when you open the folder, and that file is enough to stop the save. Move the file out of `~/.config/rotm`, or delete it, and run the command again.
- **A setting named like a secret.** The check looks at the keys under `[env]` in `config.override.toml` and in each profile's override file, in every table when it is written as `[[env]]`, and stops at one that ends in `TOKEN`, `SECRET`, `PASSPHRASE`, `PASSWORD`, `API_KEY`, `ACCESS_KEY` or `CLIENT_KEY`, in any case. Run the `mise unset` command the message names (`mise unset --override <KEY>` for the shared file, `mise unset --file <file> <KEY>` for a profile's), keep the value in `~/.zsh.local`, and run the command again.
- **A setting that describes one Mac, left in `config.override.toml`.** A version from before these settings stayed on their Mac kept the computer name and the local hostname there. Run the `rotm settings set <id> <value>` the message names, which moves the value to `config.local.toml`, and run the command again.

The secret check reads the name, not the value, so a secret under another name passes it. mise has a check of its own that refuses to send a line that looks like a secret. By then mise has already saved the line in the history on this Mac, and its message says how to remove it. Keep secrets out of `rotm settings` and out of the folder.

The repository must be private. `sync on` creates it private. When a repository of that name already exists and is not private, `sync on` stops and prints the `gh repo edit` command that makes it private. Setup offers to load settings only from a private repository.

> [!WARNING]  
> The repository keeps every version you ever saved. Changing a value later, or deleting it, does not remove the old value from the history, and anyone you give access to the repository can read all of it. If a secret was saved, replace the secret itself.

## Decide a conflict

When two Macs change the same setting between syncs, mise pauses sync and overwrites neither file. `rotm settings sync now` exits 1 and prints the file with both versions, and `rotm settings sync status` shows them again. While sync is paused, nothing is loaded from any file.

Decide each file that mise lists. The first command takes the saved copy, and the second keeps this Mac's copy:

```shell
mise dot pull --take-remote '~/.config/rotm/config.override.toml'
mise dot pull --keep-local '~/.config/rotm/config.override.toml'
```

Write the path as mise prints it, in quotes. Then run `rotm settings sync now`. After `--keep-local`, that sync sends this Mac's copy, and your other Macs load it at their next sync.

### When this Mac's folder already held a different file

A Mac can have settings of its own before you connect it, and the repository can already hold saved ones. `sync on` then stops with a listing that reads "(unsaved edits: save or discard them first)", and its diff shows this Mac's side as empty. Your file is intact. mise has no saved version of it yet, which is why the diff shows nothing on that side.

`sync on` has still connected this Mac for manual sync. mise refuses `--keep-local` here, and don't run the `mise dot save` it suggests: on this Mac it starts a history the repository won't accept. Instead:

1. To keep this Mac's copy, copy the file to a place outside `~/.config/rotm`.
1. Take the saved copy with `mise dot pull --take-remote '~/.config/rotm/config.override.toml'`.
1. If you kept your copy, copy it back.
1. Run `rotm settings sync now`. It sends the copy you put back, and your other Macs load it at their next sync.

The same steps apply when setup's question during a first install ends in the warning that your saved settings did not load.
