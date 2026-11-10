#!/bin/bash
#
# Tests setup/packages.sh against stubbed curl, mise, gh and code in a temporary
# HOME, so nothing is installed. Run by bin/lib/check.
# shellcheck disable=SC2034 # out and applies are read inside check's eval strings

set -u

repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
script="$repo/setup/packages.sh"
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
# mise and code: point it at an empty prefix, or the real mise would install
grep -q 'HOMEBREW_PREFIX:-/opt/homebrew' "$script" || {
  echo "FAIL setup/packages.sh does not take its prefix from HOMEBREW_PREFIX; not running it" >&2
  exit 1
}

stubs="$tmp/stubs"
mkdir -p "$stubs"
printf '%s\n' '#!/bin/bash' \
  'echo "$*" >> "$logs/mise.log"' \
  'echo "pwd=$PWD cfg=${MISE_CONFIG_DIR:-} tok=${MISE_GITHUB_TOKEN:-}" >> "$logs/mise.env"' \
  'case "$*" in' \
  '  *"--manager ${MISE_STUB_NOPKG:-none}") echo "mise ERROR no packages requested for manager '"'"'$MISE_STUB_NOPKG'"'"'"; exit 1 ;;' \
  '  *"--manager ${MISE_STUB_FAIL:-none}") echo "mise ERROR install failed"; exit 1 ;;' \
  'esac' > "$stubs/mise"
printf '%s\n' '#!/bin/bash' \
  'echo "$*" >> "$logs/curl.log"' \
  'echo "mkdir -p \"\$HOME/.local/bin\" && cp \"$stubs/mise\" \"\$HOME/.local/bin/mise\""' > "$stubs/curl"
printf '%s\n' '#!/bin/bash' '[ -z "${GH_STUB_FAIL:-}" ] && [ "$*" = "auth token" ] && echo tok' > "$stubs/gh"
printf '%s\n' '#!/bin/bash' 'exit 0' > "$stubs/code"
chmod +x "$stubs"/*

# run <case> [no-mise] [no-code]: a fresh HOME, bin/ and logs; sets rc and out
run() {
  local dir="$tmp/$1"
  shift
  mkdir -p "$dir/home" "$dir/bin" "$dir/logs" "$dir/prefix"
  touch "$dir/logs/mise.log" "$dir/logs/curl.log" "$dir/logs/mise.env"
  cp "$stubs/curl" "$stubs/gh" "$dir/bin/"
  [[ " $* " == *" no-mise "* ]] || cp "$stubs/mise" "$dir/bin/"
  [[ " $* " == *" no-code "* ]] || cp "$stubs/code" "$dir/bin/"
  out=$(cd "$dir" && env -u MISE_CONFIG_DIR -u MISE_GITHUB_TOKEN \
    HOME="$dir/home" HOMEBREW_PREFIX="$dir/prefix" PATH="$dir/bin:/usr/bin:/bin" \
    logs="$dir/logs" stubs="$stubs" DOTFILES_DIR="$repo" TERM=dumb \
    bash "$script" 2>&1)
  rc=$?
  logs="$dir/logs" home="$dir/home"
}

applies="plugins link --force vscode $repo/mise-plugins/vscode
bootstrap packages apply --yes --manager brew
bootstrap packages apply --yes --manager brew-cask
bootstrap packages apply --yes --manager vscode"

run a
check "a: exits 0" "[ $rc = 0 ]"
check "a: mise found, curl not run" "[ ! -s '$logs/curl.log' ]"
check "a: link, formulae, casks, extensions in order" "[ \"\$(cat '$logs/mise.log')\" = \"\$applies\" ]"
check "a: the three applies run from HOME" "[ \"\$(grep -c '^pwd=$home ' '$logs/mise.env')\" = 3 ]"
check "a: MISE_CONFIG_DIR is the repo's on every call" "! grep -v ' cfg=$repo/tilde/.config/mise ' '$logs/mise.env'"
check "a: a free-space line per manager" "[ \"\$(grep -cE '^[0-9.]+[KMGT]i? free on /$' <<< \"\$out\")\" = 3 ]"

run b no-mise
check "b: exits 0" "[ $rc = 0 ]"
check "b: installs mise from mise.run" "grep -q 'https://mise.run' '$logs/curl.log'"
check "b: the installed mise runs the same four calls" "[ \"\$(cat '$logs/mise.log')\" = \"\$applies\" ]"

run c no-code
check "c: exits 0" "[ $rc = 0 ]"
check "c: no vscode apply without code" "! grep -q 'manager vscode' '$logs/mise.log'"
check "c: says extensions are skipped" "grep -qi 'extensions.*skipped' <<< \"\$out\""

run d
check "d: gh's token reaches mise" "! grep -v ' tok=tok$' '$logs/mise.env'"
GH_STUB_FAIL=1 run d2
check "d: without a gh token, warns about the rate limit" "grep -q 'rate limit' <<< \"\$out\""
check "d: without a gh token, still exits 0" "[ $rc = 0 ]"

MISE_STUB_FAIL=brew-cask run e
check "e: a failed cask apply exits 0" "[ $rc = 0 ]"
check "e: warns that casks failed" "grep -q 'Some casks failed' <<< \"\$out\""
check "e: extensions still apply" "grep -q 'manager vscode' '$logs/mise.log'"

MISE_STUB_NOPKG=brew run f
check "f: no package list exits 1" "[ $rc = 1 ]"
check "f: says mise read no package list" "grep -q 'mise read no package list from' <<< \"\$out\""
check "f: not reported as a failed install" "! grep -q 'Some formulae failed' <<< \"\$out\""
check "f: stops before casks" "! grep -q 'manager brew-cask' '$logs/mise.log'"

check "calls no brew" "! grep -nE '(^|[^[:alnum:]_/.-])brew[[:space:]]' '$script'"
check "is executable" "[ -x '$script' ]"

[ "$fails" -eq 0 ] || {
  echo "$fails failed" >&2
  exit 1
}
