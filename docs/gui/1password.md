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

- **Option+Cmd+\\:** Quick Access (1Password's default since macOS 27 took Cmd+Shift+Space for Visual Intelligence; accepted on this Mac 2026-10-24)
- **Cmd+Shift+L:** lock 1Password
- **Cmd+Backslash:** autofill
- Change them in **Settings → General**

## Quick Access

- **Cmd+C:** copy username; **Cmd+Shift+C:** copy password
- **Option+Enter:** open in the browser; **Shift+Enter:** autofill the focused app
- **→:** show all actions for the item; **Cmd+O:** open the item in a new window; **Cmd+Shift+O:** open it in 1Password

## App

- **Cmd+/:** show all keyboard shortcuts
- **Cmd+F:** find; **Cmd+1:** all accounts; **Cmd+2…9:** switch accounts and collections; **Cmd+[ / Cmd+]:** back / forward
- **↑ / ↓:** previous / next row; **← / →:** left / right section
- **Cmd+C / Cmd+Shift+C / Option+Cmd+C:** copy primary field / password / one-time password
- **Cmd+Shift+F:** open and fill in the web browser; **Cmd+O:** open the item in a new window
- **Cmd+E:** edit; **Cmd+S:** save; **Backspace:** archive; **Cmd+Backspace:** delete
- **Cmd+R:** reveal concealed fields
- **Cmd+Shift+D:** show / hide the sidebar; **Cmd++ / Cmd+- / Cmd+0:** zoom in / out / actual size

## Sources

- https://support.1password.com/keyboard-shortcuts/
- https://www.1password.dev/ssh/get-started/
- https://www.1password.dev/ssh/agent/advanced
- https://www.1password.dev/ssh/git-commit-signing/
- https://www.1password.dev/cli/get-started/
