# tilde

Everything in this folder mirrors your home directory. `mise dotfiles apply` links it into place, from the entries in [`.config/mise/conf.d/40-dotfiles.toml`](.config/mise/conf.d/40-dotfiles.toml), so `~/.zshrc` is a symlink to `tilde/.zshrc` and editing either edits the repo.

## How it's linked

- Each top-level file has its own entry and becomes a symlink in `~`. A new file needs an entry, and `pnpm check` fails without it.
- Each folder in `.config/` has its own entry too and is linked individually into `~/.config/`, because apps also write their own state there.
- `.claude/` is linked file by file: `~/.claude/rules` stays a real folder and each tracked rule is linked into it, so machine-local rules can sit next to them. mise walks that folder, so a new rule needs no entry. Each tracked skill in `.claude/skills/` has its own entry and is linked into `~/.claude/skills/`, beside the ones the `skills` CLI installs. `statusline-command.sh` has one too.
- `.ssh/` and `.codex/` are never linked as folders. Only `.ssh/config` and `AGENTS.md` (from `agents/`) are linked, into real `~/.ssh` and `~/.codex` folders. Codex's `config.toml` is created when missing, and later applies add only the keys it lacks (see `setup/README.md`). SSH identity policy: `Host *` sets only the 1Password `IdentityAgent`, not `IdentitiesOnly`, so ssh offers the agent's keys to any host, and only `github.com` is pinned to one key (`IdentitiesOnly yes` plus `IdentityFile ~/.ssh/github_personal.pub` in `.ssh/config`). Setting `IdentitiesOnly yes` under `Host *` would need an `IdentityFile` for every host you use (in `~/.ssh/config.local`), or ssh would offer no key at all.
- This `README.md` is not linked.

A real file or folder where a link belongs stops the run: `mise dotfiles apply` names every such path and writes nothing. Move it aside, or adopt it with `mise dotfiles add <path>` (your file then replaces the tracked one, so check `git diff`), and run again. There is no prompt. `mise dotfiles apply --force` replaces the file with no backup. A link that points somewhere else is repointed without asking.

## What's here

| File | What it configures |
| --- | --- |
| `.zshenv` | Runs for every zsh. Exports `$DOTFILES`, the repo's location, then the values set with `mise set --override` |
| `.zprofile` | Login shells, including ones started by GUI apps: the `/opt/homebrew` prefix, `~/.local/bin` and mise shims |
| `.zshrc` | Interactive shells: loads everything in [`zsh/`](../zsh/), then `~/.zsh.local` if it exists, then the `mise set --override` values again so they win |
| `.bash_profile` | Empty on purpose; bash isn't configured |
| `.hushlogin` | Silences the "Last login" line in new terminals |
| `.inputrc` | Readline (case-insensitive Tab completion and similar) |
| `.starship.toml` | The [Starship](https://starship.rs/) prompt |
| `.gitconfig` | Git settings and the aliases [below](#git-helpers). Identity and signing come from `~/.gitconfig.local` |
| `.gitignore` | Your global git ignore file (`core.excludesFile`). Because it sits in this folder, git also applies it to `tilde/` itself |
| `.gitmessage` | The template git shows when you write a commit message |
| `.ripgreprc`, `.ackrc`, `.curlrc` | Defaults for `rg`, `ack` and `curl` |
| `.tlrc.toml` | The `tldr` client behind `help` |
| `.bunfig.toml` | Bun install defaults (exact versions, 7-day release age) |
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
