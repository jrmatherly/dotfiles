# tilde

Everything in this folder mirrors your home directory. `setup/symlinks.sh` links it into place, so `~/.zshrc` is a symlink to `tilde/.zshrc` and editing either edits the repo.

## How it's linked

- Each top-level file and folder becomes a symlink in `~`.
- Each item in `.config/` is linked individually into `~/.config/`, because apps also write their own state there.
- `.claude/` is linked file by file: `~/.claude/rules` stays a real folder and each tracked rule is linked into it, so machine-local rules can sit next to them. Top-level files such as `statusline-command.sh` are linked into `~/.claude/` the same way.
- `.ssh/` and `.codex/` are never linked as folders. Only `.ssh/config` and Codex's `config.toml` (plus `AGENTS.md` from `agents/`) are linked, into real `~/.ssh` and `~/.codex` folders.
- This `README.md` is not linked.

An existing file in `~` is never replaced silently: the script asks to skip, overwrite or back it up.

## What's here

| File | What it configures |
| --- | --- |
| `.zshenv` | Runs for every zsh. Exports `$DOTFILES`, the repo's location |
| `.zprofile` | Login shells, including ones started by GUI apps: Homebrew and mise shims |
| `.zshrc` | Interactive shells: loads everything in [`zsh/`](../zsh/), then `~/.zsh.local` if it exists |
| `.bash_profile` | Empty on purpose; bash isn't configured |
| `.hushlogin` | Silences the "Last login" line in new terminals |
| `.inputrc` | Readline (case-insensitive Tab completion and similar) |
| `.starship.toml` | The [Starship](https://starship.rs/) prompt |
| `.gitconfig` | Git settings and the aliases [below](#git-helpers). Identity and signing come from `~/.gitconfig.local` |
| `.gitignore` | Your global git ignore file (`core.excludesFile`). Because it sits in this folder, git also applies it to `tilde/` itself |
| `.gitmessage` | The template git shows when you write a commit message |
| `.ripgreprc`, `.ackrc`, `.curlrc` | Defaults for `rg`, `ack` and `curl` |
| `.tlrc.toml` | The `tldr` client behind `help` |
| `.config/` | Amp, bat, btop, cmux, fastfetch, gh, Ghostty, hunk and mise |
| `.claude/` | Claude Code's global rules and status line script |
| `.codex/`, `.ssh/` | Codex's `config.toml` and the SSH `config` |

Machine-local files live outside the repo: see [Local customizations](../README.md#local-customizations) in the main README.

## Git helpers

`g` is aliased to `git` in zsh, so these work as `g <alias>` or `git <alias>`. Short aliases (`s`, `d`, `l`, `cm`, `amend`, `puf`, …) are listed in [`.gitconfig`](.gitconfig); `g aliases` prints them all.

### First-aid

| Command | Description |
| --- | --- |
| `g undo` | Undo the last commit but keep its changes, ready to recommit. |
| `g unstage` | Remove files from the staging area without discarding changes. |
| `g discard` | Discard unstaged changes in the current directory and below, back to the last commit. Run it from the repo root to cover everything. |
| `g nuke` | Discard ALL local modifications, including untracked files, and restore the repository to the last commit. |

### Rebase and worktrees

| Command | Description |
| --- | --- |
| `g cont` | Stage everything and continue the rebase. |
| `g skip` | Skip the current rebase step. |
| `g abort` | Abort the rebase. |
| `g wta {{path}} {{branch}}` | Add a worktree. |
| `g wtl` | List worktrees. |
| `g wtr {{path}}` | Remove a worktree. |

### Helpers

| Command | Description |
| --- | --- |
| `g whoami` | Show the user email for the current repository. |
| `g aliases` | Print all configured aliases. |
| `g branchname` | Display the current branch name. |
| `g contribs` | List all contributors sorted by number of commits. |
| `g my` | List my own commits across all branches. |
| `g today` | Show how many lines I have changed today. |
| `g stats` | Count the lines in the files of a Git project. |
| `g last` | Show the most recent commit. |
| `g recent` | Show the branches I was working on, ordered by last change. |
| `g wtf` | Print a list of files with merge conflicts. |
| `g patch` | Sharable diff with no syntax highlighting. |
| `g publish` | Push the branch and set its upstream. |

## Git customization

### Separate Git identity for work repositories

Assuming your work repositories are inside the `~/dev/acme` folder.

1. First, create a separate Git config:

   ```shell
   git config -f ~/dev/acme/.gitconfig user.email "john.doe@acme.org"
   git config -f ~/dev/acme/.gitconfig user.name "John Doe"
   ```

1. Then, add this to `~/.gitconfig.local` (setup already created it with your identity and signing settings — append, don't replace):

   ```ini
   [includeIf "gitdir:~/dev/acme/"]
     path = ~/dev/acme/.gitconfig
   ```

   Commits there are still signed with your personal key unless the work `.gitconfig` sets its own `user.signingKey`.

### Per repository Git identity

```shell
cd ~/dev/repo
git config user.email "john.doe@acme.org"
git config user.name "John Doe"
```
