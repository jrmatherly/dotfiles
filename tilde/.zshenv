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

# Hindsight's extraction provider. The coding-agent daemon picks the first API
# key it finds when this is unset, and a daemon already running is adopted, not
# restarted, so the first session of the day would otherwise decide billing.
# Set here rather than in zsh/env.zsh because only interactive shells read that.
export HINDSIGHT_API_LLM_PROVIDER=claude-code
