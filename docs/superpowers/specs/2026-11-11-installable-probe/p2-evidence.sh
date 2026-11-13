#!/bin/bash
#
# Run one row of the P2 VM proof in the UTM guest and keep what it printed.
#
# - Run a row from the shared folder (rows 1, 2 and 6 each on a fresh guest):
#
# `bash "/Volumes/My Shared Files/vm-proof/p2/p2-evidence.sh" {{1}}`
#
# - Follow another branch than main:
#
# `P2_REF={{stable}} bash "/Volumes/My Shared Files/vm-proof/p2/p2-evidence.sh" {{1}}`
#
# ---
# The rows are the table in Task 8 of
# docs/superpowers/plans/completed/2026-11-12-p2-modules-and-opt-outs.md. Each command and
# its output goes to p2-<date>/row-<n>.txt next to this script, so on the shared
# folder the host sees them at ~/vm-proof/p2/. Commands run through `script`,
# which keeps the terminal that setup.sh's prompts and sudo need.
#
# Rows 1, 3, 4 and 5 are one guest, in that order. Rows 2 and 6 each need a
# fresh one ("Run without saving changes"), with mise installed and nothing else.
#
# Refuses to run outside the guest: every row installs for real.
#
# License: MIT

set -u

here=$(cd "$(dirname "$0")" && pwd -P)
case "$here" in
  "/Volumes/My Shared Files"/*) ;;
  *)
    echo "p2-evidence: run this from the guest's shared folder, never on the host" >&2
    exit 1
    ;;
esac
row=${1:-}
ref=${P2_REF:-main}
checkout="$HOME/.local/share/mise/bootstrap-repo"
fetch="$HOME/.local/bin/mise -E installed bootstrap --from 'https://github.com/jrmatherly/returnofthemac.git?ref=$ref' --config-dir tilde/.config/mise --save-env --only final-hook"
all=fonts,apps,vscode,claude,agents,cloud,kubernetes,devops,security,network,languages,media
cfg="$HOME/.config/mise"
status="git -C $HOME/dotfiles status --porcelain --untracked-files=no"
# One line per manager: how many are installed, and what is not
packages="cd ~ && mise bootstrap packages status --json | /usr/bin/jq -c 'to_entries[] | {manager: .key, installed: [.value.packages[]? | select(.state == \"installed\")] | length, other: [.value.packages[]? | select(.state != \"installed\") | \"\\(.package) \\(.state)\"]}'"
# declared <package>…: which of them mise's config declares, by any manager
declared() {
  local names
  names=$(printf '"%s",' "$@")
  echo "cd ~ && mise bootstrap packages status --json | /usr/bin/jq -c '[.[].packages[]? | select(.package | IN(${names%,})) | \"\\(.package) \\(.state)\"]'"
}
# A terminal opened before the install has no /opt/homebrew/bin, where the formulae land
PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

out="$here/p2-$(date +%Y%m%d)"
mkdir -p "$out" || exit 1
file="$out/row-$row.txt"

# run <command>: shows it, runs it on the terminal, and records the output and exit code
run() {
  printf '\n$ %s\n' "$1" | tee -a "$file"
  script -q -a "$file" /bin/bash -c "$1"
  printf '[exit %s]\n' "$?" | tee -a "$file"
}
note() { printf '%s\n' "$1" | tee -a "$file"; }
fresh_only() {
  [ ! -e "$checkout" ] && [ ! -e "$HOME/dotfiles" ] && [ ! -L "$cfg" ] || {
    echo "p2-evidence: row $row is for a fresh guest, before any install" >&2
    exit 1
  }
}
installed_only() {
  [ -e "$checkout" ] || {
    echo "p2-evidence: row $row runs on the row 1 guest, after its install" >&2
    exit 1
  }
}
# What the Results section records for every row
stamp() {
  run "sw_vers -productVersion; sw_vers -buildVersion; mise --version"
  [ ! -e "$checkout" ] || run "git --no-pager -C $checkout log --oneline -1"
}

case "$row" in
  1)
    fresh_only
    stamp
    run "$fetch && $checkout/setup.sh --without security,cloud,kubernetes,vscode"
    note "PASS when setup.sh ended with All done, or exit 2 with only tolerated problems."
    run "git --no-pager -C $checkout log --oneline -1"
    run "$(declared nmap awscli helm)"
    run "cd ~ && mise bootstrap packages status --json | /usr/bin/jq -c 'keys'"
    note "PASS when the first list is empty and the managers have no vscode."
    run "cat $cfg/modules-off.local; cat $cfg/miserc.local.toml"
    note "PASS when the off list holds the four names, env = [\"installed\"] and ignored_config_paths has four entries."
    run "cd ~ && mise doctor 2>&1 | grep -A6 ignored_config_files"
    note "PASS when mise doctor lists the four module files."
    run "cd ~ && MISE_ENV=dev mise ls bun"
    note "PASS when bun is listed: a module's tool survives MISE_ENV."
    ;;
  2)
    fresh_only
    stamp
    note "At the commit-signing question, answer SSH: with apps off there is no 1Password, and the guard must leave signing out."
    run "$fetch && $checkout/setup.sh --without $all"
    note "PASS when setup.sh exits 0, or 2 with only tolerated problems."
    run "git --no-pager -C $checkout log --oneline -1"
    run "cat $cfg/modules-off.local"
    run "zsh -ic 'echo prompt-ok' 2>&1"
    note "PASS when the only output is prompt-ok: a new shell starts with no error."
    run "rm -rf ~/p2-scratch && git init -q ~/p2-scratch && cd ~/p2-scratch && git status --short && git commit --allow-empty -m probe && git log --oneline -1"
    run "git config --get commit.gpgsign; git config --get gpg.ssh.program"
    note "PASS when the commit was made, and no signing program that does not exist is set."
    # filter.lfs.required is true in the tracked gitconfig, so a clone with an LFS file fails without git-lfs
    run "cd ~/p2-scratch && git lfs track '*.bin' && head -c 2048 /dev/urandom > blob.bin && git add -A && git commit -qm lfs && rm -rf ~/p2-clone && git clone -q ~/p2-scratch ~/p2-clone && cmp blob.bin ~/p2-clone/blob.bin && echo lfs-ok"
    if [ -n "${P2_LFS_REPO:-}" ]; then
      run "rm -rf ~/p2-lfs && git clone --depth 1 '$P2_LFS_REPO' ~/p2-lfs && git -C ~/p2-lfs lfs ls-files | head -3"
    else
      note "Not run: a clone of a public LFS repository. Set P2_LFS_REPO to its URL to add it."
    fi
    run "zsh -ic 'rotm settings list | head -5; rotm settings list --section modules'"
    run "zsh -ic 'help rotm | head -5'"
    note "PASS when lfs-ok printed, the settings list shows twelve modules off and help renders. This is the proof that the base stands alone."
    ;;
  3)
    installed_only
    stamp
    run "zsh -ic 'rotm settings set modules.security on'"
    run "cat $cfg/modules-off.local; grep ignored_config_paths $cfg/miserc.local.toml"
    run "zsh -ic 'rotm update -y'"
    run "command -v nmap; $(declared nmap)"
    run "$status"
    note "PASS when nmap is installed and no tracked file is listed."
    ;;
  4)
    installed_only
    stamp
    run "zsh -ic 'rotm settings set modules.kubernetes on && rotm update -y'"
    run "command -v helm; cd ~ && mise ls flux2 talosctl"
    run "zsh -ic 'rotm settings set modules.kubernetes off'"
    run "zsh -ic sysup"
    run "command -v helm; cd ~ && mise ls flux2 talosctl"
    run "$status"
    note "PASS when helm is still installed, and sysup said: packages status all installed, a packages prune notice ending (modules off: …), and a mise prune line that removed flux2 or talosctl."
    note "Record which tools mise prune removed. If it removed none, mise prune does not honour ignored_config_paths, and the plan's Global Constraint, the adapter's note and docs/modules.md are wrong."
    ;;
  5)
    installed_only
    stamp
    run "ls -d /Applications/Warp.app; zsh -ic 'rotm settings get modules.apps'"
    if grep -q '^\[bootstrap\.packages\]' "$cfg/config.local.toml" 2> /dev/null; then
      note "config.local.toml already has a [bootstrap.packages] table: add \"brew-cask:warp\" = { state = \"absent\" } to it by hand, then press Enter."
      read -r _
    else
      run "printf '\\n[bootstrap.packages]\\n\"brew-cask:warp\" = { state = \"absent\" }\\n' >> $cfg/config.local.toml"
    fi
    run "cat $cfg/config.local.toml; $(declared warp)"
    run "cd ~ && mise bootstrap packages apply --yes --manager brew-cask"
    note "Record that exit status and text: it is the measurement for a real cask."
    run "zsh -ic 'rotm update -y'"
    run "zsh -ic sysup"
    run "ls -d /Applications/Warp.app; $status"
    note "PASS when Warp is still in /Applications, and neither run lists it as a problem or a notice."
    ;;
  6)
    fresh_only
    stamp
    run "$fetch && $checkout/setup.sh"
    note "PASS when setup.sh ended with All done, or exit 2 with only tolerated problems."
    run "git --no-pager -C $checkout log --oneline -1"
    run "$packages"
    run "cd ~ && mise ls --missing"
    run "cat $cfg/miserc.local.toml; ls $cfg/modules-off.local"
    note "PASS when the counts match P1's rows 3 and 5, nothing is missing, and miserc.local.toml has no ignored_config_paths line."
    ;;
  *)
    echo "usage: p2-evidence.sh <row 1-6>" >&2
    exit 2
    ;;
esac
echo "p2-evidence: wrote $file"
