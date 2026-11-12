# ~jason 🛠️

Jason's personal dotfiles for macOS on Apple Silicon: Zsh, [mise](https://mise.jdx.dev/) for every package and runtime, and one settings UI over all of it. A personalized fork of [nicksp/dotfiles](https://github.com/nicksp/dotfiles).

![terminal screenshot](screenshot.png)

> [!WARNING]  
> These are personal, opinionated dotfiles. Review `tilde/.config/mise/conf.d/20-macos.toml`, `setup/macos-extras.sh` and `tilde/.config/mise/conf.d/30-packages.toml` before running them on a new machine.

## What you get

- **One command sets up a Mac.** [`setup.sh`](setup.sh) wraps [`mise bootstrap`](https://mise.jdx.dev/bootstrap.html): it links the dotfiles into `$HOME` and installs the [formulae, apps and VS Code extensions](tilde/.config/mise/conf.d/30-packages.toml) and the [runtimes and CLIs](tilde/.config/mise/config.toml). Homebrew itself isn't needed.
- **One command keeps it current.** [`sysup`](bin/sysup) updates macOS, mise, the packages, the runtimes and the agent tooling, and prints one status line per step.
- **One place for settings.** [`dotfiles-settings`](settings/README.md) shows every setting the repo manages (environment variables, macOS defaults, packages, dotfile links and the agent tools) in a terminal UI, the same UI in a browser tab, or a scriptable CLI.
- **Shell.** Zsh with a [Starship prompt](tilde/.starship.toml), [fzf](zsh/fzf.zsh) pickers with previews, [aliases](zsh/aliases.zsh), [handy scripts](bin/) and a built-in `help` for all of them.
- **Terminals and editors.** [Ghostty](tilde/.config/ghostty/) and [cmux](tilde/.config/cmux/), [VS Code settings](vscode/) linked from the repo, the [Squirrelsong](colors/) color scheme and the [fonts](fonts/README.md) to go with it.
- **macOS defaults as TOML.** [`20-macos.toml`](tilde/.config/mise/conf.d/20-macos.toml) declares the preferences, `set-defaults` applies them, and mise reports drift.
- **Git.** [Aliases](tilde/.gitconfig), [hunk](https://github.com/modem-dev/hunk) as the diff viewer, and per-Mac identity and commit signing (SSH through 1Password, or GPG).
- **Coding agents.** Claude Code's plugins, settings and skills [restored by setup](agents/), shared instructions for Amp and Codex, a catalog of everything installed, and opt-in per-repo [Hindsight](https://github.com/vectorize-io/hindsight) memory.
- **Apps.** An [Obsidian](obsidian/) vault setup, [Firefox Developer Edition styles](firefox/), [alternative app icons](icons/README.md) and a [Mole](docs/mole.md) cleanup guide.
- **Privacy.** Telemetry opt-outs are exported before any of the tools they cover is installed ([docs/privacy.md](docs/privacy.md)).

![The dotfiles-settings terminal UI showing the Agents section](settings/screenshot.svg)

## Quick start

You need macOS on Apple Silicon. The macOS defaults were reviewed for macOS 27.

### Install without cloning

For using the setup as it is. To change it or make it your own, [clone it](#install-from-a-clone) instead.

```shell
xcode-select --install
curl https://mise.run | sh
~/.local/bin/mise -E installed bootstrap --from 'https://github.com/jrmatherly/returnofthemac.git?ref=stable' --config-dir tilde/.config/mise --save-env --only final-hook && ~/.local/share/mise/bootstrap-repo/setup.sh
```

1. **Install the Command Line Tools and [mise](https://mise.run).** The line names mise by its path, because a new Mac's `PATH` does not have `~/.local/bin` yet.
1. **Run the install line.** mise fetches this repository's `stable` branch and links `~/.config/mise` into it, then `setup.sh` installs from that copy. `--from` trusts this repository's configuration for the run: [read it first](tilde/.config/mise), and add `--dry-run` after `bootstrap` to preview what mise would do.
1. **Move your own files aside first.** Nothing is overwritten: the run stops and names the file. See [what must not be in the way](docs/installation.md#what-must-not-be-in-the-way).
1. **Open a new terminal**, then run `gh auth login`. Without it GitHub allows 60 anonymous API calls an hour, and an update soon after the install can run out.
1. **Update later** with `rotm update`. `rotm settings` opens the settings.

macOS preferences are not applied: `set-defaults` does that, see the warning below. The copy lives in `~/.local/share/mise/bootstrap-repo` and is not for editing: `rotm update` replaces its files.

### Install from a clone

```shell
xcode-select --install
git clone https://github.com/jrmatherly/returnofthemac.git ~/dev/dotfiles
~/dev/dotfiles/setup.sh
```

1. **Install the Command Line Tools**, for `git`.
1. **Clone over HTTPS.** No GitHub login is needed. Setting up your own Mac? Fork first and go through [Make it yours](docs/forking.md).
1. **Run setup.** It asks before it starts, then prompts for your git identity and commit signing. Every step is safe to repeat.
1. **Open a new terminal**, so the shell picks up the new config.
1. **Apply the macOS defaults** with `set-defaults`, and finish [the steps setup leaves to you](docs/installation.md#after-setup).

> [!IMPORTANT]  
> `set-defaults` turns Time Machine backups off by default. If this Mac uses Time Machine, run `dotfiles-settings set macos.disable_time_machine off` first.

> [!TIP]  
> `./setup.sh -- --dry-run` previews a run. The repo can live anywhere: the scripts resolve their own location and export it as `$DOTFILES`.

The full walkthrough, with the flags, what setup prompts for and what to do when a step fails, is in [docs/installation.md](docs/installation.md).

## Everyday commands

| Command | What it does |
| --- | --- |
| `sysup` | Updates everything, from any directory ([details](docs/updating.md)) |
| `"$DOTFILES/setup.sh"` | Applies new links, tools and config after a pull. It installs what is missing, and leaves upgrades to `sysup` |
| `mise dotfiles apply` | Re-links the dotfiles only. `mise dotfiles status` shows drift |
| `set-defaults` | Applies the macOS defaults |
| `dotfiles-settings tui` | Opens the settings UI. `serve` opens it in a browser |
| `help` | Shows the [alias and command index](docs/README.md). `help <command>` documents a script in `bin/`, and `help gui/<app>` shows an app's [shortcut cheat sheet](docs/gui/) |
| `pnpm check` | Runs the checks before a commit (shell syntax, shellcheck, Prettier, the self-checks). `pnpm format` fixes formatting |

Everything in `$HOME` is a symlink into the clone, so you change a config by editing the file in the repo.

## Documentation

| Page | What it covers |
| --- | --- |
| [Installation](docs/installation.md) | The full install, setup's flags and prompts, a preview, the steps after setup, and the extras (color themes, Obsidian, Dash) |
| [Updating](docs/updating.md) | What `sysup` does step by step, Renovate, and the macOS update password from 1Password |
| [Local customizations](docs/local-customizations.md) | The per-Mac files outside the repo: `~/.zsh.local`, `~/.gitconfig.local`, `~/.ssh/config.local` and the 1Password SSH key |
| [Make it yours](docs/forking.md) | The values hard-coded to me, for when you fork |
| [Setup scripts](setup/README.md) | What each setup step does, with a diagram of what it downloads and what needs `sudo` |
| [Settings](settings/README.md) | `dotfiles-settings`: where a value comes from, the commands and exit codes |
| [Agents](agents/README.md) | Claude Code, Amp and Codex config, with [`claude-config`](docs/claude-config.md), [`claude-catalog`](docs/claude-catalog.md), [jstack](docs/jstack.md) and [REA](docs/rea.md) |
| [Home directory](tilde/README.md) | How `tilde/` is linked into `$HOME` |
| [macOS settings](docs/macos%20settings.md), [tips & tricks](docs/macos%20tips%20%26%20tricks.md) | A System Settings checklist that marks what `set-defaults` already applies, and macOS tips |
| [Privacy](docs/privacy.md) | Online privacy steps and the telemetry opt-outs |
| App folders | [VS Code](vscode/README.md), [Obsidian](obsidian/README.md), [Firefox](firefox/README.md), [fonts](fonts/README.md), [colors](colors/README.md), [icons](icons/README.md), [Rectangle](rectangle/README.md), [Syntax Highlight](syntax-highlight/README.md) |

## License

MIT License. The icons in `icons/`, the Squirrelsong theme files and the bundled Obsidian plugins stay under their owners' terms; see the end of [`LICENSE`](LICENSE).

## Inspiration

This repo started as a personalized fork of [nicksp/dotfiles](https://github.com/nicksp/dotfiles), which itself credits:

- [holman/dotfiles](https://github.com/holman/dotfiles)
- [mathiasbynens/dotfiles](https://github.com/mathiasbynens/dotfiles)
- [sapegin/dotfiles](https://github.com/sapegin/dotfiles)
- <https://remysharp.com/2018/08/23/cli-improved>
- <https://evanhahn.com/a-decade-of-dotfiles/>
- <https://cpojer.net/posts/set-up-a-new-mac-fast>
- <https://thevaluable.dev/zsh-install-configure-mouseless/>
