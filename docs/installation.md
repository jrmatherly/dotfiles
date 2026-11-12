# Installation

You need macOS on Apple Silicon. On a new Mac, clone over HTTPS — SSH only works after 1Password is set up (keys live there, see [`~/.ssh/github_personal.pub`](local-customizations.md#sshgithub_personalpub)).

1. Install the Command Line Tools (for `git`):

   ```shell
   xcode-select --install
   ```

1. Clone the repo (no GitHub login needed; `setup/misc.sh` offers `gh auth login` later, and setup only warns when gh has no token, see [Run setup](#run-setup)):

   ```shell
   git clone https://github.com/jrmatherly/returnofthemac.git ~/dev/dotfiles
   ```

   Setting up your own Mac? Fork the repo, clone your fork instead, and go through [Make it yours](forking.md) before running setup.

1. Optional, for signed commits from the start: install 1Password (download it: mise isn't installed until `./setup.sh` runs), sign in and turn on **Settings → Developer → Use the SSH agent**. `setup/dotfiles-extras.sh` asks how to sign commits — [SSH via 1Password](https://www.1password.dev/ssh/git-commit-signing) (`op-ssh-sign`; paste your public key when asked), GPG, or none — and writes `~/.gitconfig.local`. Choose none if 1Password isn't ready yet and add signing to `~/.gitconfig.local` later.
1. [Run setup](#run-setup). To see first what it would do, see [Preview](#preview).
1. Finish the steps setup can't do for you: see [After setup](#after-setup).

The repo can live anywhere — the scripts resolve their own location, and `~/.zshenv` exports it as `$DOTFILES`. `setup.sh` also creates a `~/dotfiles` symlink pointing at the clone, for the few configs that can't expand variables (e.g. lazygit's `shellFunctionsFile`).

## Run setup

To automate the setup of your dotfiles on a new machine, use the [setup](../setup.sh) script.

> [!CAUTION]  
> Use at your own risk!

```shell
~/dev/dotfiles/setup.sh # after cloning as in step 2 above
```

`setup.sh` is a thin wrapper around [`mise bootstrap`](https://mise.jdx.dev/bootstrap.html). In order, it:

1. checks for the Command Line Tools, and stops with the install command when they are missing
1. links `~/dotfiles` to the clone and `~/.config/mise` to the clone's mise config, and stops when something else is at either path
1. installs mise into `~/.local/bin` when it is missing
1. links the dotfiles into your home directory, before any package can put a file where a link belongs
1. installs the formulae and casks
1. runs `mise bootstrap`: Touch ID for `sudo` and the login shell
1. installs the runtimes and CLIs with `mise install`
1. runs [`setup/misc.sh`](../setup/README.md#misc), the `bootstrap` task, for everything else
1. installs the VS Code extensions
1. runs [`setup/dotfiles-extras.sh`](../setup/README.md#dotfiles-extrassh)

A package or tool that fails to install only warns, and the run goes on. The last thing on screen is then a list of what failed, with mise's reason when it printed one, and `setup.sh` exits 2 instead of 0. A tool's reason can be cut short: `mise install <tool>` from `~` shows the whole error. Anything else that fails, such as a part of `mise bootstrap` or the task, stops the run with mise's exit status and the earlier steps stay applied: fix what it reported and run `./setup.sh` again. Every step is safe to repeat, and rerunning `./setup.sh` is also how you apply later changes. Use it rather than a bare `mise bootstrap`, which also applies the macOS preferences and restarts Finder and the Dock. Setup never applies those: [`set-defaults`](#set-macos-defaults) does.

It exports telemetry opt-outs (.NET, PowerShell, Azure CLI, Azure MCP server, Azure Functions Core Tools, Aspire, CodeGraph, rtk, Claude Code error reports) before any of those tools is installed.

Everything is then configured by editing files in the clone. For a diagram of what it runs, what it downloads and what needs `sudo`, see [setup/README.md](../setup/README.md#setupsh-wrapper).

Options:

| Flag | Effect |
| --- | --- |
| `-y`, `--yes` | Don't wait for confirmation before starting, and pass `--yes` to mise. The task then takes the default at its own questions: it keeps the saved VS Code font preset and doesn't offer `gh auth login`. The git identity prompt on a new Mac still asks |
| `--skip-codegraph` | Don't install [CodeGraph](https://github.com/colbymchenry/codegraph) or connect it to Claude Code (an existing install is left alone) |
| `--dash` | Also run the optional [Dash docset setup](../setup/dash.sh) |
| `-h`, `--help` | Print usage and exit |
| `-- <args>` | Pass the rest to `mise bootstrap`. `./setup.sh -- --skip packages` leaves the packages alone, `-- --upgrade` also upgrades the packages and tools, `-- --dry-run` previews. A `--skip` list is merged with the `macos-defaults` setup always skips. `--only` is refused: run `mise bootstrap --only <parts>` from `~` instead |

Along the way it prompts for your git identity and commit signing (`~/.gitconfig.local`), asks for your password once more when mise changes the login shell (`chsh` does not use sudo), and offers to run `gh auth login` if the GitHub CLI isn't authenticated yet. A real file or folder where a link belongs stops the run: `mise dotfiles apply` names every such path and writes nothing. Move it aside, or adopt it with `mise dotfiles add <path>` (your file then replaces the tracked one, so check `git diff`), and run again. There is no prompt. `mise dotfiles apply --force` replaces the file with no backup. A link that points somewhere else is repointed without asking.

mise declares `/etc/pam.d/sudo_local`, which enables Touch ID for `sudo` (content, mode, owner `root:wheel`), and rewrites it when any of them differs.

Tap formulae resolve through GitHub's API. mise asks `gh` for a token itself, and `setup.sh` only warns when `gh` isn't signed in and `MISE_GITHUB_TOKEN` is unset. The anonymous limit is 60 calls an hour: one run fits, a second within the hour may not (two runs and a `mise bootstrap packages status` used all 60 on a new Mac). If packages fail to resolve, run `gh auth login` and rerun `./setup.sh`.

## Preview

To see what a run would do on a Mac that has mise but not the `~/.config/mise` link:

```shell
cd ~ && MISE_CONFIG_DIR=~/dev/dotfiles/tilde/.config/mise mise bootstrap --dry-run --skip macos-defaults
```

It changes nothing. `./setup.sh -- --dry-run` previews through the wrapper instead, but it still makes the two links and installs mise.

## After setup

Setup leaves these to you:

1. Open a new terminal, so the shell picks up the new config and `$DOTFILES/bin` is on PATH.
1. Set up GitHub SSH through 1Password: add your key's public half to GitHub, save it as [`~/.ssh/github_personal.pub`](local-customizations.md#sshgithub_personalpub), check with `ssh -T git@github.com`, and optionally switch the clone to SSH: `git remote set-url origin git@github.com:jrmatherly/returnofthemac.git`.
1. Apply the macOS defaults: [`set-defaults`](#set-macos-defaults).
1. In VS Code, run **SpaceBox Enable UI Enhancer** from the Command Palette, then quit and reopen VS Code. The blur settings do nothing until then, and the step is needed again after each VS Code update (see [vscode](../vscode/README.md#spacebox-ui-enhancer)).
1. Install the Obsidian vault settings: [`obsidian-vault install`](#set-up-the-obsidian-vault).
1. Import the color themes that apps can't read from the repo: [`install-color-themes`](#install-color-themes).

## Extras

### Set macOS defaults

```shell
set-defaults
```

Applies the preferences declared in [`20-macos.toml`](../tilde/.config/mise/conf.d/20-macos.toml) with `mise bootstrap macos defaults apply`, which lists the planned writes and asks once before making them, then runs [`setup/macos-extras.sh`](../setup/macos-extras.sh) for what TOML can't express. See [what it changes](../setup/README.md#macos). It asks nothing else. The per-Mac choices are switches in the "macOS (this Mac)" section of [`dotfiles-settings`](../settings/README.md): the screenshot, Time Machine new-disk, TextEdit and Software Update groups, the firewall with stealth mode, and turning Time Machine off (all on unless you switch them off), and HiDPI and the computer name (off or empty unless you set them; `set-defaults --hidpi` and `--computer-name "Name"` do the same for one run). **By default `set-defaults` turns Time Machine backups off.** If this Mac (or your fork) uses Time Machine, run `dotfiles-settings set macos.disable_time_machine off` before the first `set-defaults`; the same applies to a plain `mise bootstrap` run by hand. The rest are tables in the git-ignored `config.local.toml`. `mise bootstrap macos defaults status` shows which preferences have drifted. mise never deletes a preference, never uses sudo for one and doesn't restart apps by itself, so the extras script force-quits Finder, Dock, Activity Monitor, Notification Center, SystemUIServer and Terminal (Terminal is spared when you run it from Terminal.app). Log out afterwards so key repeat takes effect. Safari isn't configured by it; set Safari up in Safari → Settings.

### Use alternative apps icons

Refer to the [icons documentation](../icons/README.md) for available icon variants.

### Install color themes

```shell
install-color-themes
```

The [Squirrelsong](../colors/) theme files are owned by this repo — nothing is downloaded. bat, btop and Ghostty (and cmux) read theirs straight from the repo; the script rebuilds bat's theme cache, prints where to import the Nimble Commander, Syntax Highlight and CotEditor themes, and copies the Obsidian theme into your vault (`$OBSIDIAN_VAULT`) if it exists. To change a theme, edit the file in the repo and commit it.

### Set up the Obsidian vault

```shell
obsidian-vault install # repo → iCloud Drive/Notes (quit Obsidian first)
obsidian-vault capture # bring settings/templates changed in Obsidian back to the repo
```

See [obsidian](../obsidian/README.md) for the vault layout and the first-time walkthrough.

### Configure Dash docsets

Dash's built-in Docset Generator (Settings → Downloads → Docset Generator) can index local folders of **HTML** documentation — not Markdown. The paths are machine-specific, so they're configured interactively rather than committed. Docsets you download inside Dash are separate: Dash stores those in `~/Library/Application Support/Dash/DocSets` and syncs the list itself.

```shell
setup/dash.sh                                          # prompts for folder, name, keyword
setup/dash.sh add ~/dev/myapp/docs/html "My App" myapp # or add one directly
```

This edits the repo's Dash sync file, so it only takes effect once Dash's sync folder (Dash → Settings → General) points at the repo's `dash/` folder. Quit Dash before running it.
