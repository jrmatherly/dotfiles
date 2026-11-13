#!/bin/bash
# shellcheck disable=SC2010 # the listings are evidence, read by a person
#
# Measure, on the guest's mise, what the P4 plan (profiles, the mise floor, the macOS table move) rests on.
#
# - Run every probe from the shared folder:
#
# `bash "/Volumes/My Shared Files/vm-proof/p4/p4-probe.sh"`
#
# - Run it on a Mac, where it also only touches scratch homes:
#
# `/bin/bash docs/superpowers/specs/2026-11-13-p4-probe/probe.sh`
#
# ---
# Evidence for ../../plans/2026-11-13-p4-profiles.md, not part of the product.
# The guest runs the copy at ~/vm-proof/p4/p4-probe.sh. Run it under /bin/bash:
# under Homebrew's bash 5 the self-check section crashed. Needs the Command
# Line Tools (git) and mise. Everything
# runs in scratch homes under a temp dir: no install, no change to the guest's
# own config, and its last section clones this repository from GitHub to run
# its self-checks. Writes run-<time>/ next to itself, so on the shared folder
# the host sees it at ~/vm-proof/p4/. The last file written is `done`.
#
# License: MIT

set -u
here=$(cd "$(dirname "$0")" && pwd -P)
PATH="$HOME/.local/bin:$PATH"
xcode-select -p > /dev/null 2>&1 || { echo "p4-probe: Command Line Tools missing; run: xcode-select --install" >&2; exit 1; }
command -v mise > /dev/null || { echo "p4-probe: mise not found; run: curl https://mise.run | sh" >&2; exit 1; }
mise_bin=$(command -v mise); git_bin=$(command -v git)
out="$here/run-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out" || exit 1
{ sw_vers; "$mise_bin" --version; git --version; zsh --version; } > "$out/versions.txt" 2>&1
cat "$out/versions.txt"

S=$(cd "$(mktemp -d)" && pwd -P)
mkdir -p "$S/bin"
ln -s "$mise_bin" "$S/bin/mise"; ln -s "$git_bin" "$S/bin/git"
printf '[user]\n\tname = p4\n\temail = p4@example.invalid\n[init]\n\tdefaultBranch = main\n' > "$S/gitconfig"

# A scratch home shaped like an installed copy: ~/.config/mise is a link into a checkout under the data dir
new_home() {
  R="$S/$1"; H="$R/home"; D="$R/data"; K="$D/bootstrap-repo"; C="$H/.config/mise"; U="$H/.config/rotm"
  mkdir -p "$K/tilde/.config/mise/conf.d" "$H/.config" "$U" "$R/cache" "$R/state" "$R/proj"
  ln -s "$K/tilde/.config/mise" "$C"
}
m() {
  (cd "${CWD:-$H}" && env -i HOME="$H" PATH="$S/bin:/usr/bin:/bin" TERM=dumb MISE_DATA_DIR="$D" MISE_CACHE_DIR="$R/cache" \
    MISE_STATE_DIR="$R/state" XDG_CONFIG_HOME="$H/.config" MISE_YES=1 GIT_CONFIG_GLOBAL="$S/gitconfig" \
    GIT_CONFIG_NOSYSTEM=1 ${MENV:+MISE_ENV=$MENV} mise "$@" 2>&1)
}
val() { m env --dotenv | grep -E "^($1)=" | tr '\n' ' '; echo; }
show() { sed "s|$S|S|g"; }

profiles() {
  new_home profiles
  printf '[env]\nP_ALL = "base"\nP_SHARED = "base"\n\n[bootstrap.packages]\n"brew:p4-probe" = "latest"\n\n[bootstrap.macos.defaults."com.apple.dock"]\ntilesize = 48\n' > "$C/conf.d/10-base.toml"
  printf '[dotfiles]\n"~/.inst-marker" = { content = "x" }\n' > "$C/config.rotm-installed.toml"
  printf 'tilde/.config/mise/*.local.toml\ntilde/.config/mise/config.override.toml\ntilde/.config/mise/config.*.override.toml\n' > "$K/.gitignore"
  git -C "$K" init -q; GIT_CONFIG_GLOBAL="$S/gitconfig" git -C "$K" add -A; GIT_CONFIG_GLOBAL="$S/gitconfig" git -C "$K" commit -q -m base
  printf '[env]\nP_ALL = "shared-override"\nP_SHARED = "shared-override"\n' > "$U/config.override.toml"
  ln -s "$U/config.override.toml" "$C/config.override.toml"
  echo "== 1. set --override --env with no file yet: where does it land"
  printf 'env = ["rotm-installed", "rotm-p-work"]\n' > "$C/miserc.local.toml"
  m set --override --env rotm-p-work P_ALL=work-override; echo "exit $?"
  ls -la "$C/" | grep override | show
  echo "== 2. with the file pre-made in the user's folder and linked"
  rm -f "$C/config.rotm-p-work.override.toml"
  : > "$U/config.rotm-p-work.override.toml"; ln -s "$U/config.rotm-p-work.override.toml" "$C/config.rotm-p-work.override.toml"
  m set --override --env rotm-p-work P_ALL=work-override; echo "exit $?"
  readlink "$C/config.rotm-p-work.override.toml" | show; cat "$U/config.rotm-p-work.override.toml"; echo "checkout status:"; git -C "$K" status --short | show
  echo "== 3. profile override beats shared override; unset keys fall through"
  val 'P_.*'; m config ls | show
  echo "== 4. other sections in the profile override"
  printf '\n[bootstrap.packages]\n"brew:p4-probe" = { state = "absent" }\n\n[bootstrap.macos.defaults."com.apple.dock"]\ntilesize = 32\n\n[settings]\ndisable_tools = ["npm:prettier"]\n' >> "$U/config.rotm-p-work.override.toml"
  printf '\n[bootstrap.macos.defaults."com.apple.dock"]\ntilesize = 64\n' >> "$U/config.override.toml"
  m bootstrap packages status | grep p4-; m bootstrap macos defaults status | grep -i tilesize; m settings get disable_tools
  m set --override --env rotm-p-work P_KEEP=1 > /dev/null; echo "macos tables kept after set: $(grep -c 'bootstrap.macos' "$U/config.rotm-p-work.override.toml")"
  m unset --override --env rotm-p-work P_KEEP; echo "unset exit $?"; grep -c P_KEEP "$U/config.rotm-p-work.override.toml"
  echo "== 5. switch away, then back"
  printf 'env = ["rotm-installed", "rotm-p-personal"]\n' > "$C/miserc.local.toml"
  val 'P_.*'; m bootstrap macos defaults status | grep -i tilesize; m bootstrap packages status | grep p4-
  printf 'env = ["rotm-installed", "rotm-p-work"]\n' > "$C/miserc.local.toml"; val 'P_ALL'
  echo "== 6. project .miserc.toml adds an env; MISE_ENV replaces"
  printf 'env = ["staging"]\n' > "$R/proj/.miserc.toml"; : > "$R/proj/mise.toml"; CWD="$R/proj" m trust -a > /dev/null 2>&1
  CWD="$R/proj" val 'P_ALL'; MENV=staging val 'P_ALL'; MENV=staging,rotm-p-work val 'P_ALL'
  echo "== 7. mise writes the env line: -E a,b bootstrap --save-env --only final-hook"
  printf 'env = ["rotm-installed"]\nignored_config_paths = ["conf.d/60-rotm-fonts.toml"]\n' > "$C/miserc.local.toml"
  (cd "$H" && env -i HOME="$H" PATH="$S/bin:/usr/bin:/bin" TERM=dumb MISE_DATA_DIR="$D" MISE_CACHE_DIR="$R/cache" MISE_STATE_DIR="$R/state" XDG_CONFIG_HOME="$H/.config" MISE_YES=1 mise -E rotm-installed,rotm-p-work bootstrap --save-env --only final-hook 2>&1 | tail -3 | show); echo "exit $?"
  cat "$C/miserc.local.toml"; echo "marker applied (0 = nothing applied): $(ls -la "$H" | grep -c inst-marker)"
  echo "   and back to no profile: -E rotm-installed"
  (cd "$H" && env -i HOME="$H" PATH="$S/bin:/usr/bin:/bin" TERM=dumb MISE_DATA_DIR="$D" MISE_CACHE_DIR="$R/cache" MISE_STATE_DIR="$R/state" XDG_CONFIG_HOME="$H/.config" MISE_YES=1 mise -E rotm-installed bootstrap --save-env --only final-hook 2>&1 | tail -1 | show)
  cat "$C/miserc.local.toml"
  echo "   on a clone there is no rotm-installed: can the line be emptied? (--save-env with no -E)"
  (cd "$H" && env -i HOME="$H" PATH="$S/bin:/usr/bin:/bin" TERM=dumb MISE_DATA_DIR="$D" MISE_CACHE_DIR="$R/cache" MISE_STATE_DIR="$R/state" XDG_CONFIG_HOME="$H/.config" MISE_YES=1 mise bootstrap --save-env --only final-hook 2>&1 | tail -2 | show); echo "exit $?"
  cat "$C/miserc.local.toml"
  echo "== 8. sync: both override files reach the origin; a second home gets them"
  printf 'env = ["rotm-installed", "rotm-p-work"]\n' > "$C/miserc.local.toml"
  printf '[dotfiles."~/.config/rotm"]\nmode = "track"\n' > "$C/config.local.toml"
  git init -q --bare "$S/origin.git"
  m dot save | tail -1 | show; m dot origin set "$S/origin.git" --sync manual --yes | tail -1 | show; m dot sync | tail -1
  for r in $(git -C "$S/origin.git" for-each-ref --format='%(refname)'); do git -C "$S/origin.git" ls-tree -r --name-only "$r" | grep -v '^\.mise-history/'; done
  first_K=$K
  new_home second
  git clone -q "$first_K" "$K.tmp" && rm -rf "$K" && mv "$K.tmp" "$K" && ln -sfn "$K/tilde/.config/mise" "$C"
  m bootstrap --adopt "$S/origin.git" --only final-hook --yes | tail -2 | show; echo "adopt exit $?"
  ls -la "$U" | show | awk '{print $NF}' | tail -n +2 | tr '\n' ' '; echo
  echo "second checkout status:"; git -C "$K" status --short | show
  echo "== 9. env_sets"
  new_home sets
  printf '[env]\nP_ALL = "work"\n' > "$C/config.rotm-p-work.override.toml"
  printf '[env_sets]\nwork = ["rotm-installed", "rotm-p-work"]\n' > "$C/miserc.toml"; printf 'env = ["work"]\n' > "$C/miserc.local.toml"
  val 'P_ALL'
}

macos() {
  new_home macos
  echo "== 1. old spelling only"
  printf '[bootstrap.macos.defaults."com.apple.dock"]\ntilesize = 48\n' > "$C/conf.d/20-macos.toml"
  m bootstrap macos defaults status; echo "exit $?"
  echo "== 2. new spelling only"
  printf '[bootstrap.settings.macos.defaults."com.apple.dock"]\ntilesize = 48\n' > "$C/conf.d/20-macos.toml"
  m bootstrap macos defaults status; echo "exit $?"
  echo "-- json"; m bootstrap macos defaults status --json
  echo "== 3. new in the fragment, old in the override file (a setting saved before the move): who wins"
  printf '[bootstrap.macos.defaults."com.apple.dock"]\ntilesize = 64\n' > "$C/config.override.toml"
  m bootstrap macos defaults status | grep -i tilesize
  echo "== 4. new in both: override wins?"
  printf '[bootstrap.settings.macos.defaults."com.apple.dock"]\ntilesize = 64\n' > "$C/config.override.toml"
  m bootstrap macos defaults status | grep -i tilesize
  echo "== 5. old in the fragment, new in config.local.toml"
  rm "$C/config.override.toml"
  printf '[bootstrap.macos.defaults."com.apple.dock"]\ntilesize = 48\n' > "$C/conf.d/20-macos.toml"
  printf '[bootstrap.settings.macos.defaults."com.apple.dock"]\ntilesize = 20\n' > "$C/config.local.toml"
  m bootstrap macos defaults status | grep -i tilesize
  echo "== 6. the part name setup.sh skips, and the parts list"
  m bootstrap --skip macos-defaults --dry-run | tail -5 | show; echo "exit $?"
  m bootstrap --help | grep -i -A12 'skip\|only' | head -60
  echo "== 7. a hook table beside the new spelling (50-bootstrap.toml keeps [bootstrap.macos.launchd]?)"
  m bootstrap status 2>&1 | tail -15 | show
}

dotenv() {
  new_home dotenv
  cat > "$C/config.override.toml" << 'T'
[env]
D_PLAIN = "bar"
D_SPACE = "a b"
D_HASH = "a #b"
D_QUOTE = "say \"hi\""
D_SINGLE = "it's"
D_PATH = "/Users/x/My Folder"
D_EQ = "a=b"
D_EMPTY = ""
T
  echo "== raw mise env --dotenv"
  m env --dotenv | grep '^D_'
  echo "== mise env --json"
  m env --json | grep 'D_'
  echo "== mise env -s zsh"
  m env -s zsh | grep 'D_'
  echo "== unset --file on an override file"
  m unset --file "$C/config.override.toml" D_PLAIN; echo "exit $?"; grep -c D_PLAIN "$C/config.override.toml"
}

selfchecks() {
  git clone -q --depth 1 https://github.com/jrmatherly/returnofthemac.git "$S/repo" || { echo "clone failed"; return; }
  git -C "$S/repo" log --oneline -1
  echo "== what zsh/override-env.zsh exports from the dotenv probe's values"
  new_home ovr
  cp "$S/dotenv/home/.config/mise/config.override.toml" "$C/config.override.toml" 2> /dev/null
  (cd "$H" && env -i HOME="$H" PATH="$S/bin:/usr/bin:/bin" MISE_DATA_DIR="$D" MISE_CACHE_DIR="$R/cache" MISE_STATE_DIR="$R/state" XDG_CONFIG_HOME="$H/.config" \
    zsh -fc "source '$S/repo/zsh/override-env.zsh'; for k in D_PLAIN D_SPACE D_HASH D_QUOTE D_SINGLE D_PATH D_EQ D_EMPTY; do print -r -- \"\$k=[\${(P)k-UNSET}]\"; done" 2>&1)
  for t in test-override-env test-modules test-user-layer test-dotfiles test-packages test-bootstrap test-sysup test-rotm test-sync; do
    echo "== $t"
    LC_ALL=en_US.UTF-8 /bin/bash -c 'cd "$1" && exec /bin/bash "bin/lib/$2"' _ "$S/repo" "$t" > "$out/$t.log" 2>&1; echo "exit $?"; tail -4 "$out/$t.log" | show
  done
}

for p in profiles macos dotenv selfchecks; do
  echo "#### $p"
  "$p" > "$out/$p.txt" 2>&1
  echo "wrote $out/$p.txt"
done
rm -rf "$S"
date > "$out/done"
echo "p4-probe: wrote $out"
