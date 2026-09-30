# Note: The first added entry gets referenced last

if command -v getconf &> /dev/null; then
  PATH="$(getconf PATH)"
fi

# Prepend PATH by skipping duplicates
declare -U PATH
prepend() {
  [ -d "$1" ] && PATH="$1:$PATH"
}

# CotEditor and VSCode install their CLI tools here
prepend "/usr/local/bin"

# Cursor CLI installs here
prepend "$HOME/.local/bin"

# .NET global tools (e.g. pwsh) — tilde/.zprofile adds this too, but the PATH
# reset above drops it in interactive shells
prepend "$HOME/.dotnet/tools"

# Flutter
prepend "$HOME/Projects/flutter/bin"

# Homebrew binaries
# > $(brew --prefix)
homebrew_path="/opt/homebrew"
prepend "$homebrew_path/bin"
prepend "$homebrew_path/sbin"

# Node/Python/etc runtime versions are managed by mise (activated in
# tilde/.zprofile for shims and zsh/init.zsh for full shell activation).
# See https://mise.jdx.dev

# Custom dotfiles binaries
prepend "$DOTFILES/bin/lib"
prepend "$DOTFILES/bin"

# User binaries
prepend "$HOME/bin"

# Prevent it from being used accidentally elsewhere in the script or by other scripts
unset prepend

export PATH
