#!/bin/bash
#
# Tests the dotfiles step of setup.sh: a copy of setup.sh runs in a temporary
# HOME beside stub step scripts, with sudo and mise stubbed. Run by bin/lib/check.

# shellcheck disable=SC2088 # "~/x" in check names is display text
set -u

repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
fails=0
log="$tmp/log"
out="$tmp/out"

check() {
  if eval "$2"; then echo "ok   $1"; else
    echo "FAIL $1"
    fails=$((fails + 1))
  fi
}

# The copy resolves the clone from its own path, so the real step scripts are
# never reached. setup.sh must read HOMEBREW_PREFIX, or a real mise in
# /opt/homebrew/bin would be run here.
grep -qF "\${HOMEBREW_PREFIX:-/opt/homebrew}/bin" "$repo/setup.sh" || {
  echo "FAIL setup.sh does not read \${HOMEBREW_PREFIX:-/opt/homebrew}; not running it" >&2
  exit 1
}
clone="$tmp/clone"
mkdir -p "$clone/setup" "$clone/bin" "$clone/tilde/.config/mise" "$tmp/stubs"
cp "$repo/setup.sh" "$clone/setup.sh"
for step in packages zsh misc dotfiles-extras; do
  printf '#!/bin/bash\necho "%s" >> "%s"\n' "$step" "$log" > "$clone/setup/$step.sh"
done
printf '#!/bin/bash\n' > "$clone/bin/nyan"
printf '#!/bin/bash\ncat > /dev/null 2>&1 < /dev/null\n' > "$tmp/stubs/sudo"
# shellcheck disable=SC2016 # expanded when the stub runs
printf '#!/bin/bash\necho "mise $* (in $PWD)" >> "%s"\nexit "${MISE_STUB_EXIT:-0}"\n' "$log" > "$tmp/mise-stub"
chmod +x "$clone"/setup/*.sh "$clone/bin/nyan" "$tmp/stubs/sudo" "$tmp/mise-stub"

# run <setup.sh args…>: a fresh HOME per case, prepared by the `prepare` function
run() {
  home="$tmp/home.$RANDOM"
  mkdir -p "$home/.local/bin" "$home/.config"
  cp "$tmp/mise-stub" "$home/.local/bin/mise"
  ln -s "$clone/tilde/.config/mise" "$home/.config/mise"
  prepare
  : > "$log"
  # To a file, not $(…): setup.sh's sudo keep-alive leaves a `sleep 60` holding a pipe open
  env -i HOME="$home" PATH="$tmp/stubs:/usr/bin:/bin:/usr/sbin:/sbin" HOMEBREW_PREFIX="$tmp/prefix" \
    MISE_STUB_EXIT="${stub_exit:-0}" bash "$clone/setup.sh" "$@" > "$out" 2>&1 < /dev/null
  rc=$?
}

prepare() { :; }
run -y
check "-y with a closed stdin exits 0" "[ $rc -eq 0 ]"
check "~/dotfiles is created as a link to the clone" "[ '$home/dotfiles' -ef '$clone' ] && [ -L '$home/dotfiles' ]"
check "mise applies from \$HOME with --yes and no --force" "grep -qxF 'mise dotfiles apply --yes (in $home)' '$log'"
check "the steps run in order, extras after the apply" "[ \"\$(sed 's/ .*//' '$log' | tr '\n' ' ')\" = 'packages zsh misc mise dotfiles-extras ' ]"

run
check "a closed stdin without -y behaves the same" "[ $rc -eq 0 ] && grep -q '^mise dotfiles apply --yes ' '$log' && grep -qx dotfiles-extras '$log'"

for kind in directory file link; do
  prepare() {
    case $kind in
      directory) mkdir "$home/dotfiles" ;;
      file) echo x > "$home/dotfiles" ;;
      link) ln -s "$tmp/stubs" "$home/dotfiles" ;;
    esac
  }
  run -y
  check "a foreign ~/dotfiles ($kind) stops setup with exit 1" "[ $rc -eq 1 ]"
  check "… names the problem ($kind)" "grep -q '~/dotfiles is not this clone' '$out'"
  check "… before any step runs ($kind)" "[ ! -s '$log' ]"
done

prepare() { rm "$home/.local/bin/mise"; }
run -y
check "without mise setup exits 1" "[ $rc -eq 1 ]"
check "… says so" "grep -q 'mise not found' '$out'"
check "… and does not run the extras" "! grep -q 'mise\|dotfiles-extras' '$log'"

prepare() { rm "$home/.config/mise" && mkdir "$home/.config/mise"; }
run -y
check "a ~/.config/mise that is not the clone's stops setup with exit 1" "[ $rc -eq 1 ] && grep -q '~/.config/mise is not this clone' '$out'"
check "… before the apply and the extras" "! grep -q 'mise\|dotfiles-extras' '$log'"

prepare() { :; }
stub_exit=1
run -y
check "a failed apply ends setup with its exit code" "[ $rc -eq 1 ]"
check "… and the extras do not run" "grep -q '^mise dotfiles apply' '$log' && ! grep -qx dotfiles-extras '$log'"
check "… and setup does not say All done" "! grep -q 'All done' '$out'"

[ "$fails" -eq 0 ] || {
  echo "$fails failed" >&2
  exit 1
}
