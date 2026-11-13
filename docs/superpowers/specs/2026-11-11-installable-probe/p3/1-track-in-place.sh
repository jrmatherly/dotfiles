#!/bin/bash
# P3 research probe: mise tracking and sync under the config-dir shape, in a scratch home only.
set -u
S=$(mktemp -d "${TMPDIR:-/tmp}/p3-probe.XXXXXX") || exit 1
S=$(cd "$S" && pwd -P)
[ "${KEEP:-}" = 1 ] || trap 'rm -rf "$S"' EXIT

use() {
  export HOME="$S/$1/home" MISE_DATA_DIR="$S/$1/data" MISE_STATE_DIR="$S/$1/state" MISE_CACHE_DIR="$S/$1/cache"
  export MISE_CONFIG_DIR="$HOME/.config/mise"
  co="$MISE_DATA_DIR/bootstrap-repo"
}
penv() {
  env -i PATH="$PATH" TERM=dumb MISE_YES=1 HOME="$HOME" MISE_DATA_DIR="$MISE_DATA_DIR" \
    MISE_CONFIG_DIR="$MISE_CONFIG_DIR" MISE_STATE_DIR="$MISE_STATE_DIR" MISE_CACHE_DIR="$MISE_CACHE_DIR" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=probe GIT_AUTHOR_EMAIL=probe@example.invalid \
    GIT_COMMITTER_NAME=probe GIT_COMMITTER_EMAIL=probe@example.invalid "$@"
}
g() { penv git "$@"; }
m() {
  case "$HOME" in "$S"/*) ;; *) echo "not scratch" >&2; exit 3 ;; esac
  (cd "$HOME" && penv mise "$@" 2>&1 | grep -v -E 'WARN +(mise version|To update)')
  return "${PIPESTATUS[0]}"
}
say() { printf '\n=== %s\n' "$*"; }
run() { printf '$ mise %s\n' "$*"; m "$@"; printf '[exit %s]\n' "$?"; }

# An installed copy as P1 ships it: ~/.config/mise is a link into mise's checkout
mkdir -p "$S/a/home" && use a
upstream="$S/upstream.git"
seed="$S/seed"
mkdir -p "$seed/cfg/conf.d"
printf '# base-marker\n' > "$seed/cfg/config.toml"
printf '# fragment-marker\n' > "$seed/cfg/conf.d/10-base.toml"
printf 'cfg/config.override.toml\ncfg/config.local.toml\ncfg/miserc.local.toml\ncfg/modules-off.local\n' > "$seed/.gitignore"
g -C "$seed" init -q -b main && g -C "$seed" add -A && g -C "$seed" commit -q -m base
g clone -q --bare "$seed" "$upstream"

install_copy() {
  mkdir -p "$S/$1/home/.config" "$S/$1/data" "$S/$1/state" "$S/$1/cache"
  use "$1"
  g clone -q "$upstream" "$co"
  ln -s "$co/cfg" "$HOME/.config/mise"
}

install_copy a
printf '[env]\nP3_PROBE = "override-marker"\n' > "$MISE_CONFIG_DIR/config.override.toml"
printf '# local-marker\n' > "$MISE_CONFIG_DIR/config.local.toml"
printf '# rc-marker\n' > "$MISE_CONFIG_DIR/miserc.local.toml"
printf 'fonts\n' > "$MISE_CONFIG_DIR/modules-off.local"
printf '# zsh-marker\n' > "$HOME/.zsh.local"

say "config files mise sees (must all be under scratch)"
m config ls --json | /usr/bin/jq -r '.[].path' | sed "s|$S|<S>|"

say "track --help"
m dot track --help | sed -n '1,60p'

say "T1 track each user file"
for f in "$MISE_CONFIG_DIR/config.override.toml" "$MISE_CONFIG_DIR/modules-off.local" "$MISE_CONFIG_DIR/config.local.toml" "$MISE_CONFIG_DIR/miserc.local.toml" "$HOME/.zsh.local"; do
  run dot track "$f" | sed "s|$S|<S>|g"
done

say "T1 where the track entries were written, and is the checkout dirty?"
grep -rn -E 'track|dotfiles' "$co/cfg" "$HOME/.config" 2> /dev/null | sed "s|$S|<S>|g"
echo "-- git status of the checkout:"; g -C "$co" status --porcelain
echo "-- files in config dir:"; ls -A "$co/cfg"

say "T2 paths, save"
run dot paths | sed "s|$S|<S>|g"
run dot save | sed "s|$S|<S>|g"

say "T3 origin, sync, what reached the origin"
origin="$S/origin.git"; g init -q --bare "$origin"
run dot origin set "$origin" --sync manual | sed "s|$S|<S>|g"
run dot sync | sed "s|$S|<S>|g"
echo "-- files in origin history:"; g -C "$origin" log --all --name-only --format= | sort -u
echo "-- checkout dirty after sync?"; g -C "$co" status --porcelain

say "T4 second Mac: install first, then adopt"
install_copy b
run bootstrap --adopt "$origin" | sed "s|$S|<S>|g" | tail -25
run dot origin set "$origin" --sync manual | sed "s|$S|<S>|g" | tail -3
for f in config.override.toml modules-off.local config.local.toml miserc.local.toml; do
  printf '%s: ' "$f"; [ -e "$MISE_CONFIG_DIR/$f" ] && head -2 "$MISE_CONFIG_DIR/$f" | tr '\n' ' ' || printf 'absent'; echo
done
printf '.zsh.local: '; cat "$HOME/.zsh.local" 2> /dev/null || echo absent
echo "-- is ~/.config/mise still the link?"; ls -ld "$HOME/.config/mise" | sed "s|$S|<S>|g"
echo "-- checkout b dirty?"; g -C "$co" status --porcelain
echo "-- config dir b:"; ls -A "$MISE_CONFIG_DIR/"
