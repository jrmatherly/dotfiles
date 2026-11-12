#!/bin/bash
#
# Run one row of the P1 VM proof in the UTM guest and keep what it printed.
#
# - Run a row from the shared folder (rows 1 and 2 first, on the fresh guest):
#
# `bash "/Volumes/My Shared Files/vm-proof/p1/p1-evidence.sh" {{3}}`
#
# - Follow another branch than main:
#
# `P1_REF={{stable}} bash "/Volumes/My Shared Files/vm-proof/p1/p1-evidence.sh" {{3}}`
#
# ---
# The rows are the table in Task 6 of
# docs/superpowers/plans/2026-11-11-p1-install-and-update.md. Each command and
# its output goes to p1-<date>/row-<n>.txt next to this script, so on the shared
# folder the host sees them at ~/vm-proof/p1/. Commands run through `script`,
# which keeps the terminal that setup.sh's prompts and sudo need.
#
# Refuses to run outside the guest: a row installs for real, and rows 1 and 2
# delete ~/.config/mise and mise's checkout.
#
# License: MIT

set -u

here=$(cd "$(dirname "$0")" && pwd -P)
case "$here" in
  "/Volumes/My Shared Files"/*) ;;
  *)
    echo "p1-evidence: run this from the guest's shared folder, never on the host" >&2
    exit 1
    ;;
esac
row=${1:-}
ref=${P1_REF:-main}
checkout="$HOME/.local/share/mise/bootstrap-repo"
install="$HOME/.local/bin/mise -E installed bootstrap --from 'https://github.com/jrmatherly/returnofthemac.git?ref=$ref' --config-dir tilde/.config/mise --save-env --only final-hook && $checkout/setup.sh"
status="git -C $HOME/dotfiles status --porcelain --untracked-files=no"
PATH="$HOME/.local/bin:$PATH"

out="$here/p1-$(date +%Y%m%d)"
mkdir -p "$out" || exit 1
file="$out/row-$row.txt"

# run <command>: shows it, runs it on the terminal, and records the output and exit code
run() {
  printf '\n$ %s\n' "$1" | tee -a "$file"
  script -q -a "$file" /bin/bash -c "$1"
  printf '[exit %s]\n' "$?" | tee -a "$file"
}
note() { printf '%s\n' "$1" | tee -a "$file"; }
# Rows 1 and 2 set up and remove files a real install owns
fresh_only() {
  [ ! -e "$checkout" ] && [ ! -e "$HOME/dotfiles" ] && [ ! -L "$HOME/.config/mise" ] || {
    echo "p1-evidence: row $row is for the fresh guest, before any install" >&2
    exit 1
  }
}

case "$row" in
  1)
    fresh_only
    run "mkdir -p ~/.config/mise && touch ~/.config/mise/config.toml"
    run "$install"
    note "PASS when mise refused the link and setup.sh did not start."
    run "rm -rf ~/.config/mise $checkout"
    ;;
  2)
    fresh_only
    run "mkdir ~/dotfiles && echo mine > ~/.zshrc"
    run "$install"
    note "PASS when setup.sh stopped at ~/dotfiles and named it."
    run "rmdir ~/dotfiles"
    run "$install"
    run "cat ~/.zshrc"
    note "PASS when the rerun stopped at ~/.zshrc and it still holds: mine"
    run "rm ~/.zshrc"
    ;;
  3)
    run "$install"
    note "PASS when setup.sh ended with All done, or exit 2 with only the royal-tsx miss."
    ;;
  4)
    run "[ ~/.config/mise -ef $checkout/tilde/.config/mise ] && echo config-link-ok"
    run "[ ~/dotfiles -ef $checkout ] && echo dotfiles-link-ok"
    run "$HOME/dotfiles/bin/lib/rotm-mode"
    run "cat ~/.config/mise/miserc.local.toml"
    note "PASS when both links are ok, the mode is installed and env = [\"installed\"]."
    ;;
  5)
    run "cd ~ && mise bootstrap status --missing"
    run "cd ~ && mise bootstrap packages status --json | /usr/bin/jq -c 'to_entries[] | {manager: .key, missing: [.value.packages[]? | select(.state != \"installed\") | .package]}'"
    note "PASS when this matches what A6 recorded for a setup.sh run."
    ;;
  6)
    note "Run this row in a NEW terminal window."
    run "zsh -ic 'command -v rotm; rotm settings list | head -3'"
    run "git config --get core.excludesfile"
    note "PASS when rotm resolves under the checkout, the list prints and git reads our settings."
    ;;
  7 | 8 | 10)
    if [ "$row" != 7 ]; then
      note "First use the Mac as the plan's row $row says, then press Enter."
      read -r _
    fi
    run "$status"
    [ "$row" != 10 ] || run "rotm update -y"
    note "Row 7 and 10 PASS when nothing is listed. Row 8 lists the paths that need an entry."
    ;;
  9)
    note "First, on the host: commit and push row 8's entries and the one-line changes. Then press Enter."
    read -r _
    run "$status"
    note "Restore the files listed above (git -C ~/dotfiles checkout -- <file>), then press Enter."
    read -r _
    run "rotm update -y"
    run "git -C ~/dotfiles log --oneline -1"
    run "gh config get editor; git config --get alias.zz"
    run "$status"
    note "PASS when HEAD is the new commit, setup.sh ran, editor is vim, alias.zz is status and nothing is listed."
    ;;
  11)
    run "zsh -ic sysup"
    run "$status"
    note "PASS when there is no claude-config save, dotfiles says rotm update and nothing is listed."
    ;;
  12)
    run "zsh -ic dotfiles"
    note "PASS when it prints the rotm update hint and pulls nothing."
    ;;
  *)
    echo "usage: p1-evidence.sh <row 1-12>" >&2
    exit 2
    ;;
esac
echo "p1-evidence: wrote $file"
