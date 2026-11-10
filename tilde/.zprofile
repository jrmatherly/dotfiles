# ~/.zprofile — runs once for login shells (including shells spawned by GUI
# apps like VSCode/Finder). Interactive-only setup belongs in .zshrc instead.

# /opt/homebrew is where mise puts formulae and casks (conf.d/30-packages.toml)
# and ~/.local/bin is where mise itself lives. These are the lines `brew
# shellenv` used to print; nothing here runs a command.
export HOMEBREW_PREFIX=/opt/homebrew
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
fpath=(/opt/homebrew/share/zsh/site-functions $fpath)
export FPATH
export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"

# mise: make tool shims available to non-interactive/GUI-launched processes
# (e.g. VSCode's integrated Python/Node resolution). Full shell activation
# (auto-switching on cd, env vars) happens separately in zsh/init.zsh.
# See https://mise.jdx.dev/dev-tools/shims.html
if command -v mise &> /dev/null; then
  eval "$(mise activate zsh --shims)"
fi

# Visual Studio Code CLI
export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"

# SnippetsLab's `lab` CLI (Mac App Store app; see setup/misc.sh)
[ -d /Applications/SnippetsLab.app/Contents/Helpers ] && export PATH="$PATH:/Applications/SnippetsLab.app/Contents/Helpers"

# OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init.zsh 2> /dev/null || :

# .NET Core SDK tools
export PATH="$PATH:$HOME/.dotnet/tools"

# Rust: rustup's proxies and cargo-installed binaries, after Homebrew's bin (why: zsh/path.zsh)
export PATH="$PATH:/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin"
