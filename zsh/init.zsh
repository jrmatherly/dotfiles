command_exists() {
  command -v "$@" &> /dev/null
}

source_brew_plugin() {
  command_exists brew || return 1
  local plugin_path
  for plugin_path in "$(brew --prefix)/share/$1/$1.zsh" "$(brew --prefix)/share/$1/${1#zsh-}.plugin.zsh"; do
    [[ -r "$plugin_path" ]] && source "$plugin_path"
  done
}

# Activate mise for full shell integration (auto-switching tool versions on cd,
# env vars, etc.). Shims for non-interactive/GUI processes are activated
# separately in tilde/.zprofile. See https://mise.jdx.dev/getting-started.html
if command_exists mise; then
  eval "$(mise activate zsh)"
fi

# Activate Fish-like autosuggestions: https://github.com/zsh-users/zsh-autosuggestions/blob/master/INSTALL.md#homebrew
source_brew_plugin "zsh-autosuggestions"

# Enable zsh-fast-syntax-highlighting: https://github.com/zdharma-continuum/fast-syntax-highlighting#installation
source_brew_plugin "zsh-fast-syntax-highlighting"
# Only themeable once the plugin is actually installed (e.g. before the first
# `brew bundle` on a new machine it isn't)
if (( $+functions[fast-theme] )); then
  fast-theme $DOTFILES/colors/fast-syntax-highlighting.ini --quiet
fi

# Enable fzf: https://github.com/junegunn/fzf
if command_exists fzf; then
  source $DOTFILES/zsh/fzf.zsh
fi

# Setup zoxide: https://github.com/ajeetdsouza/zoxide?tab=readme-ov-file#installation
export _ZO_DATA_DIR=$HOME
if command_exists zoxide; then
  eval "$(zoxide init --cmd cd zsh)"
fi

# Starship prompt
if command_exists starship; then
  export STARSHIP_CONFIG=~/.starship.toml
  eval "$(starship init zsh)"
fi
