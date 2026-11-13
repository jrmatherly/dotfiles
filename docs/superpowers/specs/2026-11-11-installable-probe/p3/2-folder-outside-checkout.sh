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
U="$HOME/.config/rotm"; mkdir -p "$U"
printf '[env]\nP3_PROBE = "override-marker"\n' > "$U/config.override.toml"
printf 'fonts\n' > "$U/modules-off.local"
ln -s "$U/config.override.toml" "$MISE_CONFIG_DIR/config.override.toml"
ln -s "$U/modules-off.local" "$MISE_CONFIG_DIR/modules-off.local"
say "A: does mise read an override file that is a link to a file outside the checkout?"
m config ls --json | /usr/bin/jq -r '.[].path' | sed "s|$S|<S>|"
printf 'P3_PROBE=%s\n' "$(m env --json | /usr/bin/jq -r '.P3_PROBE // "unset"')"
say "B: does mise set --override write through the link?"
run set --override P3_SECOND=two
ls -l "$MISE_CONFIG_DIR/config.override.toml" | sed "s|$S|<S>|g"; cat "$U/config.override.toml"
say "C: track entries written by hand in config.local.toml"
printf '[dotfiles]\n"~/.config/rotm" = { mode = "track" }\n' > "$MISE_CONFIG_DIR/config.local.toml"
run dot paths | sed "s|$S|<S>|g"
run dot save | sed "s|$S|<S>|g"
echo "-- checkout dirty?"; g -C "$co" status --porcelain
origin="$S/origin.git"; g init -q --bare "$origin"
run dot origin set "$origin" --sync manual | sed "s|$S|<S>|g" | tail -4
echo "-- origin files:"; g -C "$origin" log --all --name-only --format= | sort -u
echo "-- config.local.toml now:"; sed "s|$S|<S>|g" "$MISE_CONFIG_DIR/config.local.toml"
say "D: second Mac, installed copy first, then adopt"
install_copy b
run bootstrap --adopt "$origin" | sed "s|$S|<S>|g" | grep -v -E 'omitted|^mise bootstrap|all tools' | tail -8
echo "-- user dir on b:"; ls -A "$HOME/.config/rotm" 2>/dev/null; cat "$HOME/.config/rotm/config.override.toml" 2>/dev/null
echo "-- checkout b dirty?"; g -C "$co" status --porcelain
echo "-- b config.local.toml:"; sed "s|$S|<S>|g" "$MISE_CONFIG_DIR/config.local.toml" 2>/dev/null
say "E: b edits, syncs; a pulls"
printf 'P3_FROM_B = "b"\n' >> "$HOME/.config/rotm/config.override.toml"
run dot origin set "$origin" --sync manual | tail -1
run dot save | tail -2; run dot sync | tail -2
use a
run dot sync | tail -2; run dot pull | sed "s|$S|<S>|g" | tail -4
grep -c P3_FROM_B "$U/config.override.toml"; ls -l "$MISE_CONFIG_DIR/config.override.toml" | sed "s|$S|<S>|g"
