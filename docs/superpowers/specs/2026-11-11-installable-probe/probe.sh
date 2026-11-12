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
  local paths p
  if ! paths=$(m config ls --json | /usr/bin/jq -r '.[].path'); then
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

probe_1() { answer 1 not-written; }
probe_2() { answer 2 not-written; }
probe_3() { answer 3 not-written; }
probe_4() { answer 4 not-written; }
probe_5() { answer 5 not-written; }
probe_6() { answer 6 not-written; }
probe_7() { answer 7 not-written; }
probe_8() { answer 8 not-written; }
probe_9() { answer 9 not-written; }
probe_10() { answer 10 not-written; }

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
