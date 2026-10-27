command_exists() {
  command -v "$@" &> /dev/null
}

source_brew_plugin() {
  # HOMEBREW_PREFIX comes from `brew shellenv` in tilde/.zprofile; `brew --prefix`
  # cost a Ruby start per call
  local plugin_path prefix=${HOMEBREW_PREFIX:-/opt/homebrew}
  for plugin_path in "$prefix/share/$1/$1.zsh" "$prefix/share/$1/${1#zsh-}.plugin.zsh"; do
    [[ -r "$plugin_path" ]] && source "$plugin_path"
  done
}

# mise: shims first, full activation at the first prompt (the order mise's
# docs give: https://mise.jdx.dev/dev-tools/shims.html). The shims go back in
# front of /opt/homebrew/bin, which zsh/path.zsh just put ahead of them (it
# has Homebrew's own node). Full activation, which puts each tool's install
# dir first and switches versions on cd, waits for a prompt: Claude Desktop
# reads PATH from an interactive login shell that never prompts and hands it
# to Claude Code, which keeps it ahead of everything in its shell snapshot,
# so activating here pinned every global node (24, 22, 26) for whole agent
# sessions. Agent shells never prompt either, so they resolve through shims
if command_exists mise; then
  eval "$(mise activate zsh --shims)"
  _dotfiles_mise_activate() {
    add-zsh-hook -d precmd _dotfiles_mise_activate
    unfunction _dotfiles_mise_activate
    eval "$(mise activate zsh)"
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _dotfiles_mise_activate
fi

# Activate Fish-like autosuggestions: https://github.com/zsh-users/zsh-autosuggestions/blob/master/INSTALL.md#homebrew
source_brew_plugin "zsh-autosuggestions"

# Enable zsh-fast-syntax-highlighting: https://github.com/zdharma-continuum/fast-syntax-highlighting#installation
source_brew_plugin "zsh-fast-syntax-highlighting"
# Only themeable once the plugin is actually installed (e.g. before the first
# `brew bundle` on a new machine it isn't)
# The plugin loads the stored theme ($FAST_WORK_DIR/current_theme.zsh) itself,
# so fast-theme reruns only when the repo's ini is newer than that file
if (( $+functions[fast-theme] )) && [[ $DOTFILES/colors/fast-syntax-highlighting.ini -nt $FAST_WORK_DIR/current_theme.zsh ]]; then
  fast-theme $DOTFILES/colors/fast-syntax-highlighting.ini --quiet
fi

# Enable fzf: https://github.com/junegunn/fzf
if command_exists fzf; then
  source $DOTFILES/zsh/fzf.zsh
fi

# Setup zoxide: https://github.com/ajeetdsouza/zoxide?tab=readme-ov-file#installation
export _ZO_DATA_DIR=$HOME
if command_exists zoxide; then
  # Agent shells keep the builtin cd (a missed path must fail, not jump to a frecency match); z and zi still work
  if [[ -n $CLAUDECODE ]]; then
    eval "$(zoxide init zsh)"
  else
    eval "$(zoxide init --cmd cd zsh)"
  fi
fi

# Starship prompt
# Not in a dumb terminal (an editor or agent shell), where starship errors on every prompt
if [[ $TERM != dumb ]] && command_exists starship; then
  export STARSHIP_CONFIG=~/.starship.toml
  eval "$(starship init zsh)"
fi
