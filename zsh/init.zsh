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

# Activate mise for full shell integration (auto-switching tool versions on cd,
# env vars, etc.). Shims for non-interactive/GUI processes are activated
# separately in tilde/.zprofile. See https://mise.jdx.dev/getting-started.html
if command_exists mise; then
  if [[ -n $CLAUDECODE ]]; then
    # Agent shells get shims only. Claude Code snapshots the shell once per
    # session and never runs the prompt hook full activation relies on, so the
    # install dirs it puts on PATH (every global node, in list order) held for
    # the whole session: node was 22 in a repo pinned to 24. A shim resolves
    # the version for the working directory on each call. Install dirs
    # inherited from a parent shell go too, or they'd still win
    path=(${path:#${MISE_DATA_DIR:-$HOME/.local/share/mise}/installs/*})
    eval "$(mise activate zsh --shims)"
  else
    eval "$(mise activate zsh)"
  fi
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
