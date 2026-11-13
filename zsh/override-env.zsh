# Values set with `mise set --override` live in mise's override file, and a
# machine-scoped setting's in config.local.toml. mise applies them at the first
# prompt only (zsh/init.zsh), so shells that never prompt read this cache of the
# [env] keys of both, and of every profile's override file
# (config.rotm-p-<name>.override.toml). The values come from mise, so only the
# active profile's reach the cache. mise runs only when one of those files, or
# miserc.local.toml, which names the active profile, is newer than the cache.
# Sourced from tilde/.zshenv, and again from tilde/.zshrc because zsh/env.zsh
# and ~/.zsh.local (the seeds) export after .zshenv.
() {
  # Lets the settings package read a seed without the override on top
  [[ -z ${DOTFILES_NO_OVERRIDE_ENV:-} ]] || return 0
  local dir=${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}
  local override=$dir/config.override.toml local=$dir/config.local.toml
  # One cache per override file, so another MISE_CONFIG_DIR never reads this one's values
  local cache=$HOME/.cache/dotfiles/override-env.${override//[^A-Za-z0-9]/_}.zsh
  local file stale=0
  local -a files
  for file in $override $local $dir/config.rotm-p-*.override.toml(N); do
    [[ ! -f $file ]] || files+=($file)
  done
  (( $#files )) || return 0
  for file in $files $dir/miserc.local.toml; do
    [[ ! -f $file || $cache -nt $file ]] || stale=1
  done
  if (( stale )); then
    # .zshenv runs before .zprofile puts mise on PATH, so try where it installs
    local mise line out in_env k
    for mise in ${commands[mise]:-} $HOME/.local/bin/mise ${HOMEBREW_PREFIX:-/opt/homebrew}/bin/mise; do
      [[ ! -x $mise ]] || break
    done
    local -a keys match mbegin mend
    for file in $files; do
      in_env=0
      for line in "${(@f)$(<$file)}"; do
        if [[ $line == \[* ]]; then
          [[ $line == '[env]'* ]] && in_env=1 || in_env=0
        elif (( in_env )) && [[ $line =~ '^[[:space:]]*"?([A-Za-z_][A-Za-z0-9_]*)"?[[:space:]]*=' ]]; then
          keys+=($match[1])
        fi
      done
    done
    # -C $HOME: an untrusted mise.toml in the current directory must not fail the run
    # Evaluated whole in a subshell, not filtered by line: a multi-line value spans lines
    if [[ -x $mise ]] && out=$("$mise" env -s zsh -C $HOME 2> /dev/null) && mkdir -p ${cache:h}; then
      (
        # A key of a profile that is not active must not come back from the environment this shell inherited
        (( ! $#keys )) || unset $keys
        eval "$out"
        for k in ${(u)keys}; do
          if (( ${(P)+k} )); then print -r -- "export $k=${(qq)${(P)k}}"; fi
        done
      ) >| $cache.$$ && command mv -f $cache.$$ $cache
    elif [[ -o interactive && -z ${_override_env_warned:-} ]]; then
      # Sourced twice per interactive shell; warn once
      typeset -g _override_env_warned=1
      print -u2 "override-env: mise could not read $override or $local; keeping the last good values"
    fi
  fi
  [[ ! -r $cache ]] || source $cache
}
