# Where this repo lives. `~/.zshenv` is a symlink into the repo's `tilde/`
# folder, so resolve this file's own path (%x), follow the symlink (:A) and go
# up two levels — no hardcoded `~/dotfiles` needed. Set here (rather than in
# .zshrc) so non-interactive shells and scripts see it too.
export DOTFILES="${${(%):-%x}:A:h:h}"

typeset -U fpath

# Terminal integrations (i.e. cmux) can run before .zshrc.
# Avoid stale Homebrew Cellar zsh function paths so early autoloads like add-zsh-hook and is-at-least work as intended.
if [[ -d /opt/homebrew/opt/zsh/share/zsh/functions ]]; then
  fpath=(/opt/homebrew/opt/zsh/share/zsh/functions ${fpath:#/opt/homebrew/Cellar/zsh/*/share/zsh/functions})
fi
