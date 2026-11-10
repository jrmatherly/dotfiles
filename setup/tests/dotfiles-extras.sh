#!/bin/bash
#
# Tests setup/dotfiles-extras.sh in a temporary HOME with a fixture repo and
# stubbed sudo and bat. Run by bin/lib/check.

set -u

repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
script="$repo/setup/dotfiles-extras.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

check() {
  if eval "$2"; then echo "ok   $1"; else
    echo "FAIL $1"
    fails=$((fails + 1))
  fi
}

# The script puts $HOMEBREW_PREFIX/bin before PATH, where this Mac has a real
# bat, and links into /usr/local/bin unless told otherwise. Without both knobs
# a run would rebuild the real bat cache or sudo into the real folder.
if [ -f "$script" ]; then
  for knob in 'HOMEBREW_PREFIX:-/opt/homebrew' 'DOTFILES_EXTRAS_BIN:-/usr/local/bin' 'DOTFILES_EXTRAS_APPS:-/Applications'; do
    grep -qF "$knob" "$script" || {
      echo "FAIL setup/dotfiles-extras.sh does not read \${$knob}; not running it" >&2
      exit 1
    }
  done
fi

# What the script would change on this Mac if it escaped the scratch HOME
real_ff=$("$repo/firefox/lib/get-firefox-dev-path")
watched=("$HOME/.gitconfig.local" /usr/local/bin /usr/local/bin/cot /usr/local/bin/code "$HOME/.cache/bat" "$HOME/.cache/bat/themes.bin" "$HOME/.cache/bat/syntaxes.bin" "$HOME/.cache/bat/metadata.yaml")
[ -n "$real_ff" ] && watched+=("$real_ff/user.js" "$real_ff/chrome/userContent.css" "$real_ff/chrome/userChrome.css")
fingerprint() {
  local p
  for p in "${watched[@]}"; do
    stat -f '%N %i %Fm %Fc %z %p' "$p" 2> /dev/null || echo "absent $p"
  done
}
# shellcheck disable=SC2034 # read inside the eval of check
before=$(fingerprint)

# A fixture clone: the script hard-links from it, so it sits on the temp volume
fx="$tmp/repo"
cot="$tmp/apps/CotEditor.app/Contents/SharedSupport/bin/cot"
mkdir -p "$fx/firefox/chrome" "$tmp/stubs" "$(dirname "$cot")" "$tmp/bin" "$tmp/prefix/bin" "$tmp/prefix/sbin"
ln -s "$repo/firefox/lib" "$fx/firefox/lib"
echo v1 > "$fx/firefox/user.js"
echo c1 > "$fx/firefox/chrome/userContent.css"
echo c2 > "$fx/firefox/chrome/userChrome.css"
printf '#!/bin/sh\necho cot\n' > "$cot"
chmod +x "$cot"
printf '#!/bin/sh\necho "sudo $*" >> "%s"\n' "$tmp/log" > "$tmp/stubs/sudo"
printf '#!/bin/sh\necho "bat $*" >> "%s"\n' "$tmp/log" > "$tmp/stubs/bat"
chmod +x "$tmp/stubs/sudo" "$tmp/stubs/bat"

# run <home> [VAR=value...]: closed stdin, no cot or code on PATH, an empty prefix
run() {
  local home=$1
  shift
  mkdir -p "$home"
  : > "$tmp/log"
  env -i HOME="$home" PATH="$tmp/stubs:/usr/bin:/bin" DOTFILES_DIR="$fx" HOMEBREW_PREFIX="$tmp/prefix" \
    DOTFILES_EXTRAS_APPS="$tmp/apps" DOTFILES_EXTRAS_BIN="$tmp/bin" "$@" \
    bash "$script" < /dev/null > "$tmp/out" 2>&1
}

h="$tmp/h1"
run "$h"
check "closed stdin and no knobs: exits 0" "[ $? = 0 ]"
check "closed stdin and no knobs: no identity file" "[ ! -e '$h/.gitconfig.local' ]"
check "missing public key warned about" "grep -q 'github_personal.pub not found' '$tmp/out'"
check "no Firefox profile: warned, not failed" "grep -q 'No Firefox Developer Edition profile' '$tmp/out'"
check "cot linked without sudo into a writable folder" "[ '$tmp/bin/cot' -ef '$cot' ] && ! grep -q '^sudo' '$tmp/log'"
check "VS Code missing: warned" "grep -q 'Visual Studio Code not installed' '$tmp/out'"
check "bat cache rebuilt" "grep -qx 'bat cache --build' '$tmp/log'"

run "$h" DOTFILES_GIT_NAME='A B' DOTFILES_GIT_EMAIL=a@b.c DOTFILES_GIT_SIGN_METHOD=ssh DOTFILES_GIT_SIGNINGKEY='ssh-ed25519 AAAA'
check "knobs write the identity" "grep -qx '  name = A B' '$h/.gitconfig.local' && grep -qx '  signingKey = ssh-ed25519 AAAA' '$h/.gitconfig.local'"
check "ssh signing written" "grep -qx '  format = ssh' '$h/.gitconfig.local' && grep -q 'op-ssh-sign' '$h/.gitconfig.local'"
run "$h" DOTFILES_GIT_NAME=Other DOTFILES_GIT_EMAIL=o@b.c
check "an existing identity file is kept" "grep -qx '  name = A B' '$h/.gitconfig.local'"
check "second run: cot link kept, nothing asked of sudo" "[ -L '$tmp/bin/cot' ] && ! grep -q '^sudo' '$tmp/log'"

rm "$tmp/bin/cot"
chmod 555 "$tmp/bin"
run "$h"
check "unwritable folder: sudo makes the link" "grep -q '^sudo ln -s $cot $tmp/bin/cot\$' '$tmp/log'"
chmod 755 "$tmp/bin"
echo other > "$tmp/bin/cot"
run "$h"
check "a foreign file at the link is left alone" "[ \"\$(cat '$tmp/bin/cot')\" = other ] && grep -q 'leaving it' '$tmp/out'"

h="$tmp/h2"
prof="$h/Library/Application Support/Firefox/Profiles/abc.dev-edition-default"
mkdir -p "$prof/chrome"
echo mine > "$prof/user.js"
echo c1 > "$prof/chrome/userContent.css"
run "$h"
check "Firefox files hard-linked" "[ '$prof/user.js' -ef '$fx/firefox/user.js' ] && [ '$prof/chrome/userChrome.css' -ef '$fx/firefox/chrome/userChrome.css' ]"
check "a different file is backed up first" "[ \"\$(cat '$prof/user.js.backup')\" = mine ]"
check "an identical file is relinked without a backup" "[ '$prof/chrome/userContent.css' -ef '$fx/firefox/chrome/userContent.css' ] && [ ! -e '$prof/chrome/userContent.css.backup' ]"
run "$h"
check "second run makes no new backup" "[ \"\$(find '$prof' -name '*.backup*' | wc -l)\" -eq 1 ]"
# git writes a changed file as a new inode, which breaks the hard link
rm "$fx/firefox/user.js"
echo v2 > "$fx/firefox/user.js"
run "$h"
check "a pulled change reaches the profile" "[ \"\$(cat '$prof/user.js')\" = v2 ]"
check "the first backup is kept" "[ \"\$(cat '$prof/user.js.backup')\" = mine ]"
check "the stale copy gets its own backup name" "find '$prof' -maxdepth 1 -name 'user.js.backup.*' | grep -q ."

check "the real ~/.gitconfig.local, /usr/local/bin, bat cache and Firefox profile are untouched" "[ \"\$(fingerprint)\" = \"\$before\" ]"

[ "$fails" -eq 0 ] || {
  echo "$fails failed" >&2
  exit 1
}
