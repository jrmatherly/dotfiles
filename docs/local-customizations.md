# Local customizations

The dotfiles can be extended to suit additional local requirements by using the following files:

## `~/.zsh.local`

If this file exists, it's sourced near the end of `~/.zshrc` (after `zsh/init.zsh`), so its content can add to or override the existing aliases, settings, PATH, etc.

An `export` here is a starting value. A setting changed with [`dotfiles-settings`](../settings/README.md) beats an export of the same variable in every new shell, and `dotfiles-settings reset <id>` hands the variable back to the export. The changes are stored in `~/.config/rotm/config.override.toml`, a folder of your own outside the clone, and `config.override.toml` in the mise config dir is a link to it. The modules you switched off are in `~/.config/rotm/modules-off.local`, linked the same way. `setup.sh` and `sysup` move a real file found in the config dir into the folder and make the link. [Settings sync](settings-sync.md) saves that folder to a private GitHub repository of your own and loads it on your next Mac.

## `~/.ssh/config.local`

If this file exists, it will be automatically included after the public SSH hosts to specify any additional SSH hosts.

## `~/.ssh/github_personal.pub`

SSH keys live in 1Password, and `tilde/.ssh/config` pins `github.com` to your personal key by pointing at this _public_ key file (1Password's ["Match key with host"](https://www.1password.dev/ssh/agent/advanced) pattern). It's machine-local and not in the repo. On a new Mac, export the public key from 1Password into this file, or copy the matching line from:

```shell
SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock ssh-add -L
```

`setup/dotfiles-extras.sh` warns if it's missing. Test with `ssh -T git@github.com`.

> [!IMPORTANT]  
> 1Password must be running and unlocked, with **Settings → Developer → Use the SSH agent** turned on, for GitHub SSH and signed commits to work. Turning on "Keep 1Password in the menu bar" and "Start at login" keeps the agent available.

## `~/.gitconfig.local`

If this file exists, it will be automatically included after the configurations from `~/.gitconfig` allowing its content to overwrite or add to the existing `git` configurations.

> [!TIP]  
> Use `~/.gitconfig.local` to store sensitive information such as the `git` user credentials for individual repositories.

`setup/dotfiles-extras.sh` writes your identity and commit signing here. Anything a tool tries to add to `~/.gitconfig` (e.g. Git Credential Manager registering itself) belongs here too, since `~/.gitconfig` is a symlink into the repo.

> [!NOTE]  
> `git config --global --get …` does **not** follow includes, so it won't show values from this file. Use `git config --get …` (or add `--includes`).
