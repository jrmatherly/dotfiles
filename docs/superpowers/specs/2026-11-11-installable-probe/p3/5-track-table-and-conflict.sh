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
say "not connected: mise dot origin / conflicts"
run dot origin | sed "s|$S|<S>|g" | tail -3
run dot conflicts | tail -3
U="$HOME/.config/rotm"; mkdir -p "$U"; printf '[env]\nA = "1"\n' > "$U/config.override.toml"
say "track entry as its own sub-table, appended after an existing [dotfiles] table"
printf '[dotfiles]\n"~/.other" = { mode = "absent" }\n\n[dotfiles."~/.config/rotm"]\nmode = "track"\n' > "$MISE_CONFIG_DIR/config.local.toml"
run dot paths | sed "s|$S|<S>|g" | tail -3
origin="$S/origin.git"; g init -q --bare "$origin"
m dot save > /dev/null; run dot origin set "$origin" --sync manual | tail -1 | sed "s|$S|<S>|g"
echo "-- config.local.toml after mise wrote the origin:"; sed "s|$S|<S>|g" "$MISE_CONFIG_DIR/config.local.toml"
run dot origin | sed "s|$S|<S>|g" | tail -4
run dot conflicts | tail -2
say "restore onto a Mac whose folder already holds a different file"
install_copy b
mkdir -p "$HOME/.config/rotm"; printf '[env]\nA = "local"\n' > "$HOME/.config/rotm/config.override.toml"
run bootstrap --adopt "$origin" --only final-hook | sed "s|$S|<S>|g" | grep -v -E '^Sync mode|^Only explicitly' | tail -8
echo "local file after: $(tr '\n' ' ' < "$HOME/.config/rotm/config.override.toml")"
run dot conflicts | sed "s|$S|<S>|g" | tail -6
run dot status | sed "s|$S|<S>|g" | grep -i -E 'conflict|paused|pending' | head -4
