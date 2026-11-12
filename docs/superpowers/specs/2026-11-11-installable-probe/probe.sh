#!/bin/bash
#
# Measure the mise behaviours the installable-setup spec rests on, in a scratch home.
#
# - Run every probe and print one `PROBE <n> <answer>` line each:
#
# `bash probe.sh`
#
# - Run only some probes:
#
# `bash probe.sh {{1 2 3}}`
#
# - Keep the scratch folder for inspection:
#
# `PROBE_KEEP=1 bash probe.sh {{5}}`
#
# ---
# Evidence for ../2026-11-11-installable-setup-profiles-and-sync.md, not part
# of the product. Needs git, mise and /usr/bin/jq. Meant for a disposable VM.
#
# License: MIT

set -u

scratch=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-probe.XXXXXX") || exit 1
# mise prints resolved paths, and macOS temp dirs sit behind the /var symlink
scratch=$(cd "$scratch" && pwd -P)
case $scratch in
  */dotfiles-probe.*) ;;
  *)
    echo "probe: unexpected scratch folder: $scratch" >&2
    exit 1
    ;;
esac
[ "${PROBE_KEEP:-}" = 1 ] || trap 'rm -rf "$scratch"' EXIT

project=''
origin=''

# The caller's environment stays out: no MISE_ENV, tokens, shell activation or
# ~/.gitconfig with its commit signing
penv() {
  env -i PATH="$PATH" TERM=dumb MISE_YES=1 HOME="$HOME" \
    MISE_DATA_DIR="$MISE_DATA_DIR" MISE_CONFIG_DIR="$MISE_CONFIG_DIR" \
    MISE_STATE_DIR="$MISE_STATE_DIR" MISE_CACHE_DIR="$MISE_CACHE_DIR" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=probe GIT_AUTHOR_EMAIL=probe@example.invalid \
    GIT_COMMITTER_NAME=probe GIT_COMMITTER_EMAIL=probe@example.invalid \
    "$@"
}

use_home() {
  export HOME="$scratch/$1/home" MISE_DATA_DIR="$scratch/$1/data" \
    MISE_CONFIG_DIR="$scratch/$1/config" MISE_STATE_DIR="$scratch/$1/state" \
    MISE_CACHE_DIR="$scratch/$1/cache"
}

new_home() {
  rm -rf "${scratch:?}/$1"
  mkdir -p "$scratch/$1/home" "$scratch/$1/data" "$scratch/$1/config" \
    "$scratch/$1/state" "$scratch/$1/cache"
  use_home "$1"
}

g() { penv git "$@"; }

# mise reads config from every directory between / and the current one, and a
# faked HOME makes the real home just another parent: run from the repository,
# a bootstrap would apply the real config to the real machine. So every call
# runs from the scratch home, and refuses when anything points outside it.
m() {
  local dir=${HOME:-} v
  if [ "${1:-}" = -C ]; then
    dir=$2
    shift 2
  fi
  for v in "${HOME:-}" "${MISE_DATA_DIR:-}" "${MISE_CONFIG_DIR:-}" \
    "${MISE_STATE_DIR:-}" "${MISE_CACHE_DIR:-}" "$dir"; do
    case $v in
      "$scratch"/*) ;;
      *)
        echo "probe: scratch home not set" >&2
        exit 3
        ;;
    esac
  done
  (cd "$dir" && penv mise "$@")
}

self_check() {
  local out paths p
  if ! out=$(m config ls --json) || ! paths=$(/usr/bin/jq -r '.[].path' <<< "$out"); then
    echo "probe: could not list mise's config files" >&2
    exit 4
  fi
  while IFS= read -r p; do
    case $p in
      '' | "$scratch"/*) ;;
      *)
        echo "probe: mise sees config outside the scratch folder: $p" >&2
        exit 4
        ;;
    esac
  done <<< "$paths"
}

next_dir() {
  local n=1
  while [ -e "$scratch/$1.$n" ]; do n=$((n + 1)); done
  echo "$scratch/$1.$n"
}

commit_all() {
  g -C "$1" add -A && g -C "$1" commit -q -m "$2"
}

new_project() {
  local f
  project=$(next_dir project)
  mkdir -p "$project/files"
  cat > "$project/mise.toml" << 'EOF'
[dotfiles]
"~/.probe/linked" = "files/linked"
"~/.probe/copied" = { source = "files/copied", mode = "copy" }
"~/.probe/seeded" = { source = "files/seeded", mode = "copy", create_if_missing = true }
EOF
  cat > "$project/mise.extras.toml" << 'EOF'
[dotfiles]
"~/.probe/extra" = "files/extra"
EOF
  cat > "$project/mise.work.toml" << 'EOF'
[dotfiles]
"~/.probe/work" = "files/work"
EOF
  for f in linked copied seeded extra work; do echo "$f" > "$project/files/$f"; done
  g init -q -b main "$project" && commit_all "$project" fixture
}

new_origin() {
  origin=$(next_dir origin)
  g init -q --bare -b main "$origin"
}

answer() {
  local n=$1
  shift
  echo "PROBE $n $*"
}

# A failed mise command is itself an answer, so one probe never stops the rest
probe() {
  local code=0
  ("$2") || code=$?
  [ "$code" = 0 ] || answer "$1" "ERROR $code"
}

# mise's own output goes to stderr, so stdout carries only the PROBE lines
step() {
  local code=0
  "$@" >&2 || code=$?
  [ "$code" = 0 ] || echo "probe: failed ($code): $*" >&2
  return "$code"
}

boot() { step m bootstrap --from "file://$project" "$@"; }

checkout() {
  if [ -f "$MISE_DATA_DIR/bootstrap-repo/mise.toml" ]; then
    echo "$MISE_DATA_DIR/bootstrap-repo"
  else
    echo none
  fi
}

has() { [ -e "$1" ] || [ -L "$1" ]; }

quiet() { "$@" > /dev/null 2>&1; }

# pick <yes-word> <no-word> <command…>
pick() {
  local yes=$1 no=$2
  shift 2
  if "$@"; then echo "$yes"; else echo "$no"; fi
}

kind() {
  if [ -L "$1" ]; then
    echo symlink
  elif [ -f "$1" ]; then
    echo file
  else
    echo missing
  fi
}

upstream() {
  local f
  for f in "$@"; do echo "upstream $RANDOM" >> "$project/files/$f"; done
  commit_all "$project" "change $*"
}

synced() {
  pick updates refuses [ "$(g -C "$1" rev-parse HEAD)" = "$(g -C "$project" rev-parse HEAD)" ]
}

probe_1() {
  local version help flag out
  version=$(m --version | awk '{ print $1; exit }')
  [ -n "$version" ] || return 1
  help=$(m bootstrap --help 2>&1) || return $?
  out="version=$version"
  for flag in from from-dir config-dir adopt update save-env; do
    out="$out $flag=$(pick yes no grep -Eq -- "--$flag([^-a-z]|\$)" <<< "$help")"
  done
  answer 1 "$out unapply=$(pick yes no quiet m bootstrap unapply --help)"
}

probe_2() {
  local co linked
  new_home mac-a
  new_project || return 1
  boot || return $?
  co=$(checkout)
  if [ -L "$HOME/.probe/linked" ]; then
    linked=$(readlink "$HOME/.probe/linked")
    linked=${linked#"$scratch"/}
  else
    linked=$(pick not-a-symlink missing has "$HOME/.probe/linked")
  fi
  answer 2 "checkout=${co#"$scratch"/} linked=$linked copied=$(kind "$HOME/.probe/copied")"
}

probe_3() {
  local shipped=ignored file=none override=untested
  new_home mac-a
  new_project || return 1
  echo 'env = ["extras"]' > "$project/.miserc.toml"
  commit_all "$project" "ship a module list" || return 1
  boot || return $?
  if has "$HOME/.probe/extra"; then
    shipped=applied file=.miserc.toml
  else
    mkdir -p "$project/.config"
    g -C "$project" mv .miserc.toml .config/miserc.toml
    commit_all "$project" "move the module list" || return 1
    new_home mac-a
    boot || return $?
    has "$HOME/.probe/extra" && shipped=applied file=.config/miserc.toml
  fi
  # Without a shipped list that applies, an empty local list shows nothing
  if [ "$shipped" = applied ]; then
    echo 'env = []' > "$MISE_CONFIG_DIR/miserc.local.toml"
    rm -rf "$HOME/.probe"
    boot || return $?
    override=$(pick loses wins has "$HOME/.probe/extra")
  fi
  answer 3 "shipped-list=$shipped shipped-file=$file local-override=$override"
}

# cancel_with <toml value for the user's "~/.probe/linked" entry>
cancel_with() {
  printf '[dotfiles]\n"~/.probe/linked" = %s\n' "$1" > "$MISE_CONFIG_DIR/config.toml"
  rm -rf "$HOME/.probe"
  if boot; then pick ignored cancels has "$HOME/.probe/linked"; else echo error; fi
}

probe_4() {
  local off absent winner
  new_home mac-a
  new_project || return 1
  boot || return $?
  off=$(cancel_with '{ enabled = false }')
  absent=$(cancel_with '{ mode = "absent" }')
  echo user > "$MISE_CONFIG_DIR/other"
  cancel_with '"other"' > /dev/null
  case $(cat "$HOME/.probe/linked" 2> /dev/null) in
    user) winner=user ;;
    linked) winner=project ;;
    *) winner=neither ;;
  esac
  answer 4 "enabled-false=$off absent=$absent winner=$winner"
}

probe_5() {
  local co c1=0 c2=0 c3=0 r1 r2 r3 copy seeded
  new_home mac-a
  new_project || return 1
  boot || return $?
  co=$(checkout)
  [ "$co" != none ] || return 1

  echo user-edit >> "$HOME/.probe/copied"
  echo user-edit >> "$HOME/.probe/seeded"
  upstream copied seeded || return 1
  boot --update || c1=$?
  r1=$(synced "$co")
  copy=untested seeded=untested
  if [ "$r1" = updates ]; then
    copy=$(pick kept-user-edit overwritten grep -q user-edit "$HOME/.probe/copied")
    seeded=$(pick kept-user-edit overwritten grep -q user-edit "$HOME/.probe/seeded")
  fi

  echo user-edit >> "$HOME/.probe/linked"
  upstream extra || return 1
  boot --update || c2=$?
  r2=$(synced "$co")

  upstream linked || return 1
  boot --update || c3=$?
  r3=$(synced "$co")

  answer 5 "exit-codes=$c1,$c2,$c3 copy-edit=$r1 symlink-edit-other-file=$r2 symlink-edit-same-file=$r3 copy-target-after=$copy seeded-target-after=$seeded"
}

# The config dir sits under HOME here, as on a real Mac, so a tracked path
# means the same thing in both homes
sync_home() {
  use_home "$1"
  export MISE_CONFIG_DIR="$HOME/.config/mise"
}

probe_6() {
  local a b shared local_toml conflict=untested listed out
  new_home mac-a
  sync_home mac-a
  a=$MISE_CONFIG_DIR
  mkdir -p "$a"
  new_origin || return 1
  echo '# shared-marker' > "$a/config.toml"
  echo '# local-marker' > "$a/config.local.toml"
  step m dot track "$a" || return $?
  step m dot save || return $?
  step m dot origin set "$origin" --sync manual || return $?
  step m dot sync || return $?

  new_home mac-b
  sync_home mac-b
  b=$MISE_CONFIG_DIR
  step m bootstrap --adopt "$origin" || return $?
  shared=$(pick arrived missing grep -rqs '# shared-marker' "$HOME")
  local_toml=$(pick leaked stayed grep -rqs '# local-marker' "$HOME")
  g -C "$origin" log --all --name-only --format= | grep -q 'config\.local\.toml' && local_toml=leaked

  sync_home mac-a
  echo '# edit-a' >> "$a/config.toml"
  step m dot save || return $?
  step m dot sync || return $?
  sync_home mac-b
  if [ -f "$b/config.toml" ]; then
    echo '# edit-b' >> "$b/config.toml"
    step m dot save
    step m dot sync
    step m dot pull
  fi
  if out=$(m dot conflicts 2>&1); then
    listed=$(pick lists-file empty grep -q 'config\.toml' <<< "$out")
  else
    listed=error
  fi
  echo "$out" >&2
  if [ -f "$b/config.toml" ]; then
    if ! grep -q '# edit-b' "$b/config.toml"; then
      conflict=overwrote-b
    elif grep -q '# edit-a' "$b/config.toml"; then
      conflict=merged
    else
      sync_home mac-a
      step m dot sync
      step m dot pull
      conflict=$(pick paused overwrote-a grep -q '# edit-a' "$a/config.toml")
    fi
  fi
  answer 6 "shared=$shared local-toml=$local_toml conflict=$conflict conflicts-cmd=$listed"
}

probe_7() {
  local first remembered saved
  new_home mac-a
  new_project || return 1
  step m -E work bootstrap --from "file://$project" --save-env || return $?
  first=$(pick applied ignored has "$HOME/.probe/work")
  rm -rf "$HOME/.probe"
  boot || return $?
  remembered=$(pick yes no has "$HOME/.probe/work")
  saved=$(grep -rlsw work "$MISE_CONFIG_DIR" | head -1)
  saved=${saved#"$MISE_CONFIG_DIR"/}
  answer 7 "work-first-run=$first remembered=$remembered saved-in=${saved:-none}"
}

probe_8() {
  local co out ran=neither first=none extra=untested linked=untested
  new_home mac-a
  new_project || return 1
  step m -E extras bootstrap --from "file://$project" || return $?
  if ! has "$HOME/.probe/extra"; then
    echo "probe: the extras module was not applied" >&2
    return 1
  fi
  co=$(checkout)
  if [ "$co" != none ] && out=$(m -C "$co" bootstrap unapply extras 2>&1); then
    ran=checkout
  else
    echo "${out:-probe: no checkout found}" >&2
    first=$(pick untrusted other grep -qi trust <<< "${out:-}")
    if [ "$co" != none ] && step m -C "$co" -E extras bootstrap unapply extras; then ran=checkout-with-env; fi
  fi
  if [ "$ran" != neither ]; then
    extra=$(pick kept removed has "$HOME/.probe/extra")
    linked=$(pick kept removed has "$HOME/.probe/linked")
  fi
  answer 8 "extra=$extra linked=$linked ran-from=$ran first-error=$first"
}

probe_9() {
  local co real shape=error applied=untested tracked=untested updated=untested
  new_home mac-a
  new_project || return 1
  mkdir "$project/cfg"
  printf '[dotfiles]\n"~/.probe/from-cfg" = "../files/linked"\n' > "$project/cfg/config.toml"
  commit_all "$project" "add a config dir" || return 1
  rmdir "$MISE_CONFIG_DIR"
  boot --config-dir cfg && applied=$(pick applied missing has "$HOME/.probe/from-cfg")
  co=$(checkout)
  real=$(cd -P "$MISE_CONFIG_DIR" 2> /dev/null && pwd -P)
  if [ -L "$MISE_CONFIG_DIR" ]; then
    case $real in
      "$MISE_DATA_DIR"/*) shape=symlink-into-checkout ;;
      *) shape=symlink-elsewhere ;;
    esac
  elif [ -d "$MISE_CONFIG_DIR" ]; then
    shape='real-dir'
  fi
  # Never write through a link that leaves the scratch folder
  case $real in "$scratch"/*) ;; *) co=none ;; esac
  if [ "$applied" != untested ] && [ "$co" != none ]; then
    echo '# local' > "$MISE_CONFIG_DIR/config.local.toml"
    tracked=$(pick yes no grep -q 'config\.local\.toml' <<< "$(g -C "$co" status --porcelain)")
    upstream extra || return 1
    boot --config-dir cfg --update
    updated=$(synced "$co")
  fi
  answer 9 "config-dir=$shape from-cfg=$applied local-toml-in-checkout=$tracked update-with-local-toml=$updated"
}

clone_branch() { g -C "$1" symbolic-ref -q --short HEAD || echo detached; }

probe_10() {
  local clone="$scratch/clone" url applied=error b1 e1 code=0
  new_home mac-a
  new_project || return 1
  g -C "$project" branch stable || return 1
  upstream extra || return 1
  rm -rf "${scratch:?}/clone"
  # The clone's origin is spelled as the URL passed to --from, which mise compares
  g clone -q "file://$project" "$clone" || return 1
  echo dev-edit >> "$clone/files/linked"
  url="file://$project?ref=stable"
  if step m bootstrap --from "$url" --from-dir "$clone"; then
    applied=$(pick yes no has "$HOME/.probe/linked")
  fi
  b1=$(clone_branch "$clone")
  e1=$(pick kept lost grep -q dev-edit "$clone/files/linked")
  g -C "$project" checkout -q stable || return 1
  upstream copied || return 1
  g -C "$project" checkout -q main || return 1
  step m bootstrap --from "$url" --from-dir "$clone" --update || code=$?
  answer 10 "applied=$applied branch-after-install=$b1 edit-after-install=$e1 branch-after-update=$(clone_branch "$clone") edit-after-update=$(pick kept lost grep -q dev-edit "$clone/files/linked") update-exit=$code"
}

main() {
  local n
  [ $# -gt 0 ] || set -- 1 2 3 4 5 6 7 8 9 10
  new_home mac-a
  (self_check) || exit $?
  for n in "$@"; do
    case $n in
      [1-9] | 10) probe "$n" "probe_$n" ;;
      *) echo "probe: no probe $n" >&2 ;;
    esac
  done
}

main "$@"
