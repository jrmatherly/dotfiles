# ~/.zprofile — runs once for login shells (including shells spawned by GUI
# apps like VSCode/Finder). Interactive-only setup belongs in .zshrc instead.

# Homebrew
eval "$(/opt/homebrew/bin/brew shellenv zsh)"

# mise: make tool shims available to non-interactive/GUI-launched processes
# (e.g. VSCode's integrated Python/Node resolution). Full shell activation
# (auto-switching on cd, env vars) happens separately in zsh/init.zsh.
# See https://mise.jdx.dev/dev-tools/shims.html
if command -v mise &> /dev/null; then
  eval "$(mise activate zsh --shims)"
fi

# Visual Studio Code CLI
export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"

# OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init.zsh 2> /dev/null || :

# .NET Core SDK tools
export PATH="$PATH:$HOME/.dotnet/tools"
