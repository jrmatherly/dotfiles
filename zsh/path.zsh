# Note: The first added entry gets referenced last

# Build on the inherited PATH: tilde/.zprofile (or a parent shell) already made
# the base, and resetting it dropped entries such as SnippetsLab's `lab`.
# typeset -U keeps the first copy, so each prepend moves its entry to the front.
typeset -U path PATH
prepend() {
  [ -d "$1" ] && PATH="$1:$PATH"
}

# CotEditor and VSCode install their CLI tools here
prepend "/usr/local/bin"

# Cursor CLI installs here
prepend "$HOME/.local/bin"

# .NET global tools (e.g. pwsh); tilde/.zprofile appends it too, for login and GUI shells
prepend "$HOME/.dotnet/tools"

# Flutter
prepend "$HOME/Projects/flutter/bin"

# Rust: cargo-installed binaries and rustup's proxies (the rustup formula is
# keg-only). Prepended before Homebrew's bin so they end up AFTER it in PATH:
# the keg also ships a rust-analyzer proxy, which only works once that rustup
# component is installed and would otherwise shadow the rust-analyzer formula.
# tilde/.zprofile appends the same two for login and GUI shells.
prepend "$HOME/.cargo/bin"
prepend "/opt/homebrew/opt/rustup/bin"

# Homebrew binaries
# > $(brew --prefix)
homebrew_path="/opt/homebrew"
prepend "$homebrew_path/bin"
prepend "$homebrew_path/sbin"

# Node/Python/etc runtime versions are managed by mise (activated in
# tilde/.zprofile for shims and zsh/init.zsh for full shell activation).
# See https://mise.jdx.dev

# LLM Router desktop CLI (ccr-app). The app writes its own PATH block into
# ~/.zshrc unless that file names this path; tilde/.zshrc carries the marker.
prepend "$HOME/.llm-router/bin"

# Custom dotfiles binaries
prepend "$DOTFILES/bin/lib"
prepend "$DOTFILES/bin"

# User binaries
prepend "$HOME/bin"

# Prevent it from being used accidentally elsewhere in the script or by other scripts
unset prepend

export PATH
