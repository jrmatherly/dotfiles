# Values set with `mise set --override` live in mise's override file. mise
# applies them at the first prompt only (zsh/init.zsh), so shells that never
# prompt read this cache of them. mise runs only when the override file is newer
# than the cache. Sourced from tilde/.zshenv, and again from tilde/.zshrc because
# zsh/env.zsh and ~/.zsh.local (the seeds) export after .zshenv.
# shortcut: `mise env --dotenv` prints values raw, so a multi-line value keeps
# its first line only; switch to --json if a setting ever needs one.
() {
  # Lets the settings package read a seed without the override on top
  [[ -z ${DOTFILES_NO_OVERRIDE_ENV:-} ]] || return 0
  local override=${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}/config.override.toml
  # One cache per override file, so another MISE_CONFIG_DIR never reads this one's values
  local cache=$HOME/.cache/dotfiles/override-env.${override//[^A-Za-z0-9]/_}.zsh
  [[ -f $override ]] || return 0
  if [[ ! $cache -nt $override ]]; then
    # .zshenv runs before .zprofile puts mise on PATH, so try where it installs
    local mise line out in_env=0
    for mise in ${commands[mise]:-} $HOME/.local/bin/mise ${HOMEBREW_PREFIX:-/opt/homebrew}/bin/mise; do
      [[ ! -x $mise ]] || break
    done
    local -a keys match mbegin mend
    for line in "${(@f)$(<$override)}"; do
      if [[ $line == \[* ]]; then
        [[ $line == '[env]'* ]] && in_env=1 || in_env=0
      elif (( in_env )) && [[ $line =~ '^[[:space:]]*"?([A-Za-z_][A-Za-z0-9_]*)"?[[:space:]]*=' ]]; then
        keys+=($match[1])
      fi
    done
    # -C $HOME: an untrusted mise.toml in the current directory must not fail the run
    if [[ -x $mise ]] && out=$("$mise" env --dotenv -C $HOME 2> /dev/null) && mkdir -p ${cache:h}; then
      for line in "${(@f)out}"; do
        if (( ${keys[(Ie)${line%%=*}]} )); then print -r -- "export ${line%%=*}=${(qq)${line#*=}}"; fi
      done >| $cache.$$ && command mv -f $cache.$$ $cache
    elif [[ -o interactive && -z ${_override_env_warned:-} ]]; then
      # Sourced twice per interactive shell; warn once
      typeset -g _override_env_warned=1
      print -u2 "override-env: mise could not read $override; keeping the last good values"
    fi
  fi
  [[ ! -r $cache ]] || source $cache
}
