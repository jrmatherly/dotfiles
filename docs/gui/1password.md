# 1Password

> Password manager, SSH agent for all hosts, and Git commit signer.

Installed by `setup/Brewfile` (`cask "1password"`, `cask "1password-cli"`).

## Settings this repo depends on

- **Settings → Developer → Use the SSH Agent:** serves the SSH keys stored in 1Password
- **Settings → General → Keep 1Password in the menu bar** and **Start at login:** keep the agent available after the main window is closed
- **Settings → Developer → Integrate with 1Password CLI:** lets `op` unlock via the app (check with `op vault list`)

1Password must be running and unlocked for GitHub SSH and commit signing — you'll get a Touch ID prompt to authorize the key.

## How the repo uses it

- `tilde/.ssh/config` sets `IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"` for all hosts
- `github.com` is pinned with `IdentitiesOnly yes` and `IdentityFile ~/.ssh/github_personal.pub` — a machine-local _public_ key file (1Password's "Match key with host" pattern, avoids "Too many authentication failures"). Download the public key from 1Password, or copy the line from `SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock ssh-add -L` (plain `ssh-add -L` asks the macOS agent, not 1Password)
- `setup/symlinks.sh` creates `~/.gitconfig.local` if it's missing; answer **s** (or set `DOTFILES_GIT_SIGN_METHOD=ssh`) to sign commits and tags with SSH via `/Applications/1Password.app/Contents/MacOS/op-ssh-sign`
- For GitHub's "Verified" badge, the public key must also be added on GitHub with key type **Signing key**

## Global shortcuts

- **Cmd+Shift+Space:** Quick Access
- **Cmd+Shift+L:** lock 1Password
- **Cmd+Backslash:** autofill
- Change them in **Settings → General**

## Quick Access

- **Cmd+C:** copy username; **Cmd+Shift+C:** copy password; **Option+Cmd+C:** copy one-time password
- **Option+Enter:** open the website and fill; **Shift+Enter:** fill in the focused app
- **→:** show all actions for the item; **Cmd+Shift+O:** open the item in the app

## App

- **Cmd+/:** show all keyboard shortcuts
- **Cmd+F:** search items; **Esc:** clear search
- **Cmd+C / Cmd+Shift+C / Option+Cmd+C:** copy username / password / one-time password
- **Cmd+Shift+F:** open the website and fill credentials
- **Cmd+N:** new item; **Cmd+E:** edit; **Cmd+S:** save
- **Cmd+R:** reveal / conceal secure fields (hold **Option** to reveal all temporarily)

## Sources

- https://support.1password.com/keyboard-shortcuts/
- https://www.1password.dev/ssh/get-started/
- https://www.1password.dev/ssh/agent/advanced
- https://www.1password.dev/ssh/git-commit-signing/
- https://www.1password.dev/cli/get-started/
