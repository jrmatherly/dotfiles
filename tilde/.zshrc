# Resolve the repo location if ~/.zshenv didn't already (see tilde/.zshenv)
export DOTFILES="${DOTFILES:-${${(%):-%x}:A:h:h}}"

# Load configs
source $DOTFILES/zsh/path.zsh
source $DOTFILES/zsh/env.zsh
source $DOTFILES/zsh/options.zsh
source $DOTFILES/zsh/aliases.zsh
source $DOTFILES/zsh/completion.zsh
source $DOTFILES/zsh/key-bindings.zsh

# Load plugins
source $DOTFILES/zsh/plugins/zsh-shift-select.plugin.zsh

# Set the window title nicely no matter where you are
DISABLE_AUTO_TITLE="true"
_set_terminal_title() {
  local title="$(basename "$PWD")"
  if [[ -n $SSH_CONNECTION ]]; then
    title="$title \xE2\x80\x94 $HOSTNAME"
  fi
  print -Pn "\e]2;$title\a"
}
# Call the function before displaying the prompt
precmd_functions+=(_set_terminal_title)

# pnpm — before init.zsh so `mise activate` puts its tools ahead of pnpm's
# global bin (`mise doctor`: "mise tool paths are not first in PATH")
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

source $DOTFILES/zsh/init.zsh

# Allow local (private) overrides if present (PATH additions, work-specific aliases, etc.)
[ -f ~/.zsh.local ] && source ~/.zsh.local

# Add GPG key
export GPG_TTY=$(tty)
