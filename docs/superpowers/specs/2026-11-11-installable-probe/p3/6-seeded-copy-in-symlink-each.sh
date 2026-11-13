#!/bin/bash
# P3 research probe (Task 4 Step 1): can config.rotm-installed.toml turn one file of the
# ~/.claude/rules symlink-each folder into a seeded copy? Scratch homes only.
set -u
REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel) || exit 1
S=$(mktemp -d "${TMPDIR:-/tmp}/p3-probe.XXXXXX") || exit 1
S=$(cd "$S" && pwd -P)
[ "${KEEP:-}" = 1 ] || trap 'rm -rf "$S"' EXIT
# Tracked files only, so no machine-local mise file reaches the scratch config
git -C "$REPO" archive HEAD > "$S/repo.tar"
NOMISE=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'mise/shims' | paste -sd: -)

# An installed copy: the checkout under the data dir, ~/.config/mise and ~/dotfiles link into it
mkhome() {
  H="$S/$1/home" D="$S/$1/data"
  co="$D/bootstrap-repo"
  mkdir -p "$H/.config" "$co" "$S/$1/state" "$S/$1/cache"
  tar -xf "$S/repo.tar" -C "$co"
  ln -s "$co/tilde/.config/mise" "$H/.config/mise"
  ln -s "$co" "$H/dotfiles"
}
m() {
  case "$H" in "$S"/*) ;; *) echo "not scratch" >&2; exit 3 ;; esac
  printf '$ mise %s\n' "$*"
  (cd "$H" && env -i PATH="$NOMISE" TERM=dumb MISE_YES=1 MISE_ENV=rotm-installed HOME="$H" \
    MISE_CONFIG_DIR="$H/.config/mise" MISE_DATA_DIR="$D" MISE_STATE_DIR="${D%/data}/state" \
    MISE_CACHE_DIR="${D%/data}/cache" MISE_CEILING_PATHS="$S" mise "$@" 2>&1) \
    | grep -v -E 'WARN +(mise version|To update)' | sed "s|$S|<S>|g"
  printf '[exit %s]\n' "${PIPESTATUS[0]}"
}
change() {
  cat >> "$co/tilde/.config/mise/config.rotm-installed.toml" << 'EOF'

# Probe: the roles file is the user's, every other rule stays a link
"~/.claude/rules" = { source = "~/dotfiles/tilde/.claude/rules", mode = "symlink-each", exclude = [".DS_Store", "jstack-models.md"] }
"~/.claude/rules/jstack-models.md" = { source = "~/dotfiles/tilde/.claude/rules/jstack-models.md", mode = "copy", create_if_missing = true }
EOF
}
rules() {
  echo "-- ls -l ~/.claude/rules"
  ls -l "$H/.claude/rules" | sed "s|$S|<S>|g"
  local f="$H/.claude/rules/jstack-models.md" src="$co/tilde/.claude/rules/jstack-models.md"
  if [ -L "$f" ]; then echo "jstack-models.md: LINK"
  elif [ -f "$f" ]; then
    if cmp -s "$f" "$src"; then echo "jstack-models.md: REGULAR, same as tracked"; else echo "jstack-models.md: REGULAR, differs from tracked"; fi
  else echo "jstack-models.md: MISSING"; fi
  echo "links: $(find "$H/.claude/rules" -type l | wc -l | tr -d ' '), regular: $(find "$H/.claude/rules" -type f | wc -l | tr -d ' '), tracked rules: $(ls "$co/tilde/.claude/rules" | wc -l | tr -d ' ')"
  echo "checkout dirty: $(cd "$co" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ') (no .git in the archive, so n/a)"
}
say() { printf '\n=== %s\n' "$*"; }

say "(a) fresh installed copy with the change, first apply"
mkhome ab
change
m config ls
m dotfiles status
m dotfiles apply
rules

say "(b) user edits the regular file, second apply"
echo "feature, refactoring: user-edit medium" >> "$H/.claude/rules/jstack-models.md"
m dotfiles apply
rules
grep -c 'user-edit' "$H/.claude/rules/jstack-models.md" | sed 's/^/user-edit lines: /'
m dotfiles status

say "(c) installed before the change, then the change, then apply"
mkhome c
m dotfiles apply > /dev/null
rules
change
m dotfiles status
m dotfiles apply
rules

say "(c2) a second apply after (c)"
m dotfiles status --missing
m dotfiles apply
rules
m dotfiles apply
