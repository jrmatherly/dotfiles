# Shell Aliases & Commands

> Shell aliases, key bindings, and `bin/` commands available in this setup. Run `help` to show this page again.

## Getting help

| Command | Description |
| --- | --- |
| `help` | Show this page (`docs/README.md`) |
| `help {{command}}` | For a script in `bin/` (e.g. `help br`), show a tldr-style page generated from the script's header comment; for any other command, show its [tldr-pages](https://tldr.sh/) entry |
| `help gui/{{app}}` | Show keyboard shortcuts for a GUI app (see [GUI app shortcuts](#gui-app-shortcuts)) |
| `help "macos settings"` `help "macos tips & tricks"` | Show the other pages in `docs/` |
| `alias` | List all active aliases |

## Enhanced CLI tools

| Tool | Command | Description |
| --- | --- | --- |
| fzf | `fzf` | Open fuzzy file finder |
| fd | `fd {{file}}` | Find file by name or regexp within the current tree (`find` is aliased to `fd`) |
| fd | `fd {{file}} /` | Search the entire file system for a file |
| fd | `fd {{file}} / -H` | Search the entire file system, including hidden directories |
| eza | `ls` | Get a clickable directory listing with more information, color, and icons |
| eza | `lt` | Get two-deep level listing |
| eza | `lsa` | Get a listing including hidden files |
| eza | `lta` | Get a nested listing with hidden files |
| bat | `cat {{file}}` | Show file contents with syntax highlighting (replaces `cat`) |
| btop | `top` | Open the interactive system resource monitor (replaces `top`) |
| tldr | `man {{command}}` | Show simplified, example-driven help for a command (replaces `man`) |
| prettyping | `ping {{host}}` | Ping a host with nicer, compact output (replaces `ping`) |
| trash | `rm {{file}}` | Move files to the macOS Trash instead of permanently deleting them (replaces `rm`; falls back to `rm -iv` if `trash` isn't installed) |
| zoxide | `cd {{part_of_dir_path}}` | Jump to a frequently or recently visited directory by part of its path (`cd` is replaced by `zoxide`, which ranks the directories you visit). More information: <https://github.com/ajeetdsouza/zoxide>. |

Each replacement only applies when the tool is installed. Run the original command with a leading backslash (e.g. `\cat`) or `command {{name}}`.

## Safer built-in defaults & typos

| Command | Description |
| --- | --- |
| `cp` `mv` | Run as `cp -iv` / `mv -iv`: ask before overwriting and print each file |
| `grep` | Runs as `grep -i --color=auto` (case-insensitive, colored) |
| `mkdir` | Runs as `mkdir -p` (creates parent directories) |
| `sudo {{alias}}` | Aliases also work after `sudo` |
| `sl` `gut` `gti` `mdkir` `brwe` `cd..` | Typo fixes for `ls`, `git`, `git`, `mkdir`, `brew`, `cd ..` |

## Key bindings

| Keys | Description |
| --- | --- |
| `Ctrl+R` | Fuzzy find in your command history (inside: `Ctrl+Y` copies the command, `Ctrl+/` toggles the full-command preview) |
| `Ctrl+T` | Fuzzy find files and paste the selection onto the command line (with a `bat` preview) |
| `Alt+C` | Fuzzy find a directory and `cd` into it (Option acts as Alt in Ghostty and cmux by default on U.S. keyboard layouts; other terminals may need their "Option as Meta/Alt" setting) |
| `{{command}} **` then `Tab` | Fuzzy completion for paths, e.g. `cd **` + `Tab` |
| `Ctrl+O` | In any fzf list: open the selected file in VS Code |
| `Ctrl+/` | In any fzf list: show/hide the preview window |
| `Up` `Down` | Search history for commands starting with what you've typed |
| `Esc` `Esc` | Add or remove `sudo` at the start of the current command |
| `Ctrl+K` | Erase the whole line |
| `Shift+←` `Shift+→` (add `Option` for words) | Select text on the command line; `Delete`/`Backspace` removes the selection (typing just deselects) |

## Navigation

| Command | Description |
| --- | --- |
| `.` | Print the current directory path |
| `..` `...` `....` | Navigate to 1/2/3 parent directories up |
| `-` | Navigate to a previous working directory |
| `library` | Navigate to the user `~/Library` directory |
| `proj` | Navigate to the workspace projects directory (`$WORKSPACE`, `~/dev`) |

## Zsh config

| Command      | Description                       |
| ------------ | --------------------------------- |
| `zshrc`      | Open `~/.zshrc` in `$EDITOR`      |
| `reload` `s` | Reload Zsh config from `~/.zshrc` |

## Apps & shortcuts

`$EDITOR` is CotEditor (`cot`) locally and `nano` over SSH.

| Command | Description |
| --- | --- |
| `+x {{file}}` | Make a file executable |
| `o {{file_or_dir}}` | Open with the default app (`open`) |
| `oo` | Open current directory in Finder |
| `e {{file}}` | Open the specified file in `$EDITOR` |
| `c` | Open current directory in Visual Studio Code |
| `g {{args}}` | Run `git` |
| `d {{args}}` | Run the Docker CLI |
| `dc {{args}}` | Run Docker Compose |
| `sops {{file}}` | Edit an encrypted secrets file with `sops` using VS Code as the editor |
| `where {{command}}` | Locate a command (alias for `which`) |
| `python` | Run Python 3 (alias for `python3`) |
| `ff` | Open current directory in Nimble Commander |
| `lg` | Run [`lazygit`](https://github.com/jesseduffield/lazygit) in terminal (with this repo's config) |
| `ld` | Run [`lazydocker`](https://github.com/jesseduffield/lazydocker) in terminal |
| `gpgkeys` | List all secret GPG keys with long key ID format |

## Node & package management

| Command | Description |
| --- | --- |
| `pn {{args}}` | Run `pnpm` |
| `nnn` | Install and activate the Node.js version the current project asks for (via `mise`) |
| `mise use node@{{version}}` | Switch the current project's Node version ([mise](https://mise.jdx.dev/)). For the global default, reorder the version list in `tilde/.config/mise/config.toml` (first = default) rather than `mise use -g`, which replaces the whole list |
| `mise install` | Install the versions a project asks for (`mise.toml`, `.nvmrc`, `.node-version`, `.python-version`) |
| `mise exec node@{{version}} -- {{command}}` | Run a command with another installed version (Node 22/24/26, Python 3.11–3.15). Python versions also work directly: `python3.12` |
| `nio` | Install dependencies, preferring the offline cache. More information: <https://github.com/antfu/ni>. |
| `ns` `nd` `nb` `nbw` `nt` `ntw` `ntc` `nf` | Run common package scripts through `nr` (`@antfu/ni`): `ns` → `start`, `nd` → `dev`, `nb` → `build`, `nbw` → `build --watch`, `nt` → `test`, `ntw` → `test --watch`, `ntc` → `typecheck`, `nf` → `format` |
| `lint` `lintf` | Run the project linter (optionally with `--fix`) |
| `release` `re` | Run the project release script |

## Files & utilities

| Command | Description |
| --- | --- |
| `get {{url}}` | Download file and save it with the name of the remote file in the current working directory |
| `take {{dirname}}` | Create a directory and navigate to it |
| `preview` | Browse files in the current dir with a `bat` preview; `Ctrl+O` opens the selected file in VS Code |
| `path` | Print each PATH entry on a separate line |
| `cdf` | Navigate to the directory shown by the front-most Finder window |
| `gf {{pattern}}` | Search files recursively with ripgrep (`help gf` for filters by file type, glob, word, case) |
| `wg {{pattern}} --replace {{replacement}}` | Replace in files; preview first with `gf {{pattern}} --replace {{replacement}}` |

## Git

| Command | Description |
| --- | --- |
| `gitroot` `gr` | Navigate to the root directory of a Git repository |
| `git clone {{repo_url}}` `g clone {{repo_url}}` | Clone Git repository, navigate to created directory, and install dependencies (yarn, pnpm, npm or bun, based on the lockfile) |
| `gs` | Show the state of the working directory and staging area of a Git repository, or list directory contents outside a Git repo |
| `gaa` | Stage all changes in the working directory |
| `gcm {{message}}` | Create a commit with the specified message |
| `gd` | Show unstaged changes (working directory vs. staging area) |
| `gdc` | Show the differences (`diff`) between staged changes and the last commit |
| `gl` | Display compact and readable log |
| `gpuf` | Push with `--force-with-lease` |
| `br` | Switch branches, create a new local branch if it doesn’t exist, or delete local branches (`-d`/`-D`). Adds remote tracking when a remote branch with the same name exists. With no argument, lists recent local branches; `-r` lists remote branches; `br -` switches to the previous branch and pulls |
| `pull` | Pull remote changes using rebase while safely stashing and restoring local changes. Automatically updates submodules and reinstalls dependencies when lockfiles or package manifests change |
| `push` | Push local changes to the tracked remote branch. Intelligently maintains upstream tracking so you can push without specifying a remote or branch. Any extra arguments will be passed through to `git push`, for example `push -f` |
| `stash` | Stash all local changes (including untracked files), or run `git stash` with all the provided arguments |
| `git-pr` `git-pr {{pr_id}}` | List open GitHub pull requests, or check one out (via `gh`) |
| `git-tidy` | Delete merged branches and clean up |
| `git-find {{file}}` | Find every commit that touched a file, across all branches |

## Dotfiles & macOS maintenance

| Command | Description |
| --- | --- |
| `dotfiles` | Pull the latest dotfiles (re-run `setup.sh --skip-brew` afterwards to apply new links) |
| `brewpick` `brewpick --all` | Install packages, casks and VS Code extensions from `setup/Brewfile`, picked via fzf or all at once |
| `set-defaults` | Apply this repo's macOS defaults |
| `install-color-themes` | Install the repo's Squirrelsong themes into apps — bat cache, Obsidian vault, import hints (see [colors](../colors/README.md)) |
| `obsidian-vault install` `obsidian-vault capture` | Install the repo's Obsidian settings/templates into the vault, or bring vault changes back (see [obsidian](../obsidian/README.md)) |
| `install-iosevka-code` | Install VS Code's Iosevka Code font, or update it when the upstream zip changed (see [fonts](../fonts/README.md)) |
| `vscode-settings` | Render VS Code's `settings.json` from its template with a font preset (`--choose`, `--preset warp`, `--check`); refuses to overwrite edits VS Code made (see [vscode](../vscode/README.md#fonts-and-the-settings-template)) |
| `sync-all` | Run `obsidian-vault install`, then `install-color-themes` |
| `upup` | Run macOS, Homebrew, mise, dotfiles and other software updates |
| `flush-dns` | Flush the DNS cache |
| `shutdownmac` | Shut down macOS system |
| `restartmac` | Restart the computer |
| `showdesktop` | Show all desktop icons (useful when presenting) |
| `hidedesktop` | Hide all desktop icons (useful when presenting) |

## Other `bin/` commands

| Command | Description |
| --- | --- |
| `myip` | Show local and external IP addresses (`myip l` / `myip g` for one) |
| `palette` | Show the terminal's color palette (256 colors) and text effects |
| `serve` `serve {{port}}` | Serve the current directory over HTTP (default port `8080`) |
| `check-port {{port}}` `clear-port {{port}}` | Show / kill the process using a port |
| `optimize-image` `optimize-image {{file}}` | Convert images to WebP/AVIF and keep the smallest result |
| `ocr {{file}}` | Extract text from images with Apple’s text recognition |
| `license` | Print the MIT license |
| `cpwd` `ppp {{file}}` | Copy the current directory path / a file's full path to the clipboard |
| `copy-ssh` | Copy your SSH public key (`~/.ssh/github_personal.pub`) to the clipboard |
| `passphrase` | Generate a human-readable password |
| `httpstatus` `httpstatus {{code}}` | Look up HTTP status codes |
| `docker-clean` | Remove stopped containers, unused networks, volumes, images and build cache |
| `node-modules-size` `node-modules-clean` | Show the size of / delete all `node_modules` folders below the current directory |
| `proofread {{file}}` | Check prose for duplicate words, passive voice and weasel words |

Run `ls $DOTFILES/bin` for the full list and `help {{command}}` for each one's usage.

## GUI app shortcuts

| Command | App |
| --- | --- |
| `help gui/raycast` | Raycast |
| `help gui/1password` | 1Password |
| `help gui/dash` | Dash (Setapp, not installed by setup) |
| `help gui/ghostty` | Ghostty |
| `help gui/cmux` | cmux |
| `help gui/warp` | Warp |
| `help gui/orbstack` | OrbStack |
| `help gui/visual-studio-code` | Visual Studio Code |
| `help gui/safari` | Safari |
| `help gui/firefoxdeveloperedition` | Firefox Developer Edition (optional, not installed by setup) |
| `help gui/adobe-lightroom` | Adobe Lightroom (optional, not installed by setup) |
