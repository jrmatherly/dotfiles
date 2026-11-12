# P1: Install and Update Without a Clone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On a Mac with only mise and the Command Line Tools, one pasted line installs returnofthemac, `rotm update` brings in new commits, and neither needs a clone, a fork or an edit to our repository.

**Architecture:** mise fetches and links, our script installs. `mise bootstrap --from <url>?ref=stable --config-dir tilde/.config/mise --only final-hook` clones the repository to mise's checkout and links `~/.config/mise` into it, applying nothing. Then the checkout's own `setup.sh` runs, the script the A6 VM run already proved. A new `rotm` command wraps install, update and `dotfiles-settings`. Targets that apps rewrite get a second declaration in a mise config environment named `installed`, so an installed checkout stays clean and the owner's clone keeps its symlinks.

**Tech Stack:** bash 3.2 (`#!/bin/bash`), mise 2026.11.5 or newer, git, `/usr/bin/jq`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`. Read "Verified facts", the Distribution section and the P1 brief first.

## Global Constraints

- macOS only.
- mise floor: 2026.11.5 (`setup/mise-floor.sh`). The owner left it there on 2026-11-11. Every probe ran on 2026.11.6.
- Names: the product is `returnofthemac`, the command is `rotm`, the repository is `https://github.com/jrmatherly/returnofthemac.git`. `rotm` wraps `dotfiles-settings`. No existing command, variable or folder is renamed in this plan.
- Users follow `?ref=stable`. `stable` moves only by a fast-forward to a commit on `main` that passed the VM install, or to a later commit that differs from it in Markdown files only.
- The owner's Mac stays in clone mode. `./setup.sh` from a clone must behave exactly as before: `bin/lib/test-bootstrap` passes with no existing assertion removed or loosened, and every message a clone prints keeps its text.
- Testing rule: a real install or update runs in the UTM guest `macOS`, started with "Run without saving changes", never on the owner's Mac. Evidence goes to the shared folder, `/Volumes/My Shared Files/vm-proof` in the guest and `~/vm-proof` on the host. Self-checks with stubs and scratch homes run anywhere.
- Never run `./setup.sh`, `sysup`, `rotm install`, `rotm update` or `mise bootstrap` against the real home. Never edit `config.local.toml` or `config.override.toml`.
- The owner runs every step inside the guest. An agent session on the host cannot reach it.
- The commit hook runs `pnpm check` (about two minutes) before the command starts. Edit and commit in separate Bash calls, and retry once when the hook times out.
- Docs mirror behaviour: a change to setup behaviour has its `README.md`, `setup/README.md` or `docs/` edit in the same commit.

## Decisions this plan makes

- **Shape: config-dir.** The repository is already laid out that way (`tilde/.config/mise`), probes 9 and 11 proved the link, and `setup.sh` already expects `~/.config/mise` to be that link. The repository needs no root `mise.toml` (probe 11), so the owner's clone gets no new file to trust.
- **mise does not apply anything.** mise's own part order installs packages before dotfiles. `setup.sh` links the dotfiles first because a package that writes `~/.gitconfig` otherwise leaves a real file where a link belongs and stops the apply. `setup.sh` also carries on past one failed package. So the install line is two commands joined by `&&`: mise to fetch and link, then `setup.sh`.
- **The install line names mise by path.** mise's installer puts it in `~/.local/bin`, which a fresh Mac's `PATH` lacks (`setup.sh` says so where it sets its own `PATH`).
- **`~/dotfiles` stays.** The spec said installed mode could drop the link. It is kept: `setup.sh` makes it to whichever checkout it runs from, and lazygit's `shellFunctionsFile`, `zsh/env.zsh`, the bootstrap hooks and every `[dotfiles]` source rely on it. Dropping it belongs with the later full rename. Task 9 corrects the spec.
- **`installed` is a mise config environment.** `tilde/.config/mise/config.installed.toml` redeclares the targets apps rewrite. The install line passes `-E installed --save-env`. Probe 12 measured that the file beats `conf.d` for a file and for a linked folder, and that later runs keep the selection without `-E`.
- **Files that tools append to become thin wrappers.** A stranger's `git config --global` and any installer's `echo … >> ~/.zshrc` write through a symlink into the checkout. On an installed copy `~/.gitconfig` and `~/.zshrc` are seeded once as real files that include ours, so the user's lines stay in their file and our settings still update.
- **`stable` is created after the proof.** The VM proof runs the install line with `?ref=main`. The README section and the branch follow it.
- **The floor check stays where it is.** `setup.sh` runs `setup/mise-floor.sh` before its first mise call. A mise too old for `--from` fails on the install line's first command by itself.

## Review Focus

- A stranger who already has a real `~/.config/mise`, a `~/dotfiles`, or their own `~/.zshrc` or `~/.gitconfig`: nothing is overwritten, the run stops with the file named, and the docs give the move-aside command. Pinned in Task 6 (rows 1 and 2) and Task 7 (docs).
- `rotm update` when an app has edited a tracked file and upstream changed the same file: it stops before `setup.sh`, names the tracked files that differ and exits non-zero. Pinned in Task 3.
- `rotm update` typed in the owner's dev clone: it refuses and changes nothing. Pinned in Task 3.
- `sysup` on an installed copy: it must not run `claude-config save`, which writes `agents/` inside the checkout, and must not report the copy as up to date. Pinned in Task 4.
- `MISE_DATA_DIR` set to another folder: `rotm-mode` follows it. Pinned in Task 2.
- An installed checkout on a detached HEAD: `rotm update` exits 1 and says so. Pinned in Task 3.

---

## File Structure

- `bin/lib/rotm-mode`: prints `installed` or `clone`. The one place that knows the difference.
- `bin/rotm`: `install`, `update`, `settings`, `help`.
- `bin/lib/test-rotm`: self-check for both, run by `bin/lib/check`.
- `tilde/.config/mise/config.installed.toml`: the `installed` environment's `[dotfiles]` overrides.
- `tilde/.gitconfig.installed`, `tilde/.zshrc.installed`: the two wrapper files.
- `setup.sh`, `bin/sysup`, `bin/dotfiles`, `bin/vscode-settings`: one installed-mode branch each.
- `bin/lib/test-bootstrap`, `bin/lib/test-sysup`, `bin/lib/test-dotfiles`, `vscode/test-vscode-settings.sh`: one new block each.
- `docs/superpowers/specs/2026-11-11-installable-probe/probe.sh`, `results.txt`: probes 11 to 14.
- `docs/superpowers/specs/2026-11-11-installable-probe/p1-evidence.sh`: writes the VM proof rows to the shared folder.
- `.github/workflows/fresh-install.yml`: a matrix over the two install paths.
- `README.md`, `docs/installation.md`, `setup/README.md`, `docs/README.md`, the spec.

---

### Task 1: Measure the mise facts in the guest

**Files:**

- Modify: `docs/superpowers/specs/2026-11-11-installable-probe/results.txt`

Probes 11 to 13 are written and were run on 2026-11-11 (mise 2026.11.6, the disposable guest). Their lines are in `results.txt`:

| Probe | Answer | Meaning |
| --- | --- | --- |
| 11 | `only-final-hook=ok skip-all=untested no-root-toml=ok` | `--only final-hook` clones and links and applies nothing, with or without a root `mise.toml` |
| 12 | `file-override=file dir-override=real-dir remembered=yes` | `config.installed.toml` beats `conf.d` for a file and for a linked folder, and a later `mise dotfiles apply` with no `-E` keeps the selection |
| 13 | `update-fetch-only=updates exit=0 flags=final-hook` | The same call with `--update` fast-forwards the checkout |

Probe 14 used the install line's exact flags on a project with no root `mise.toml`, then did what `setup.sh` does next. It ran on 2026-11-11 in the same guest:

`PROBE 14 save-env-with-final-hook=yes link-after-apply=direct update=updates exit=0 folder-converted=symlink`

| Part | Meaning |
| --- | --- |
| `save-env-with-final-hook=yes` | The install line saves `env = ["installed"]` although it applies nothing |
| `link-after-apply=direct`, `update=updates` | A `mise dotfiles apply` that redeclares `~/.config/mise` through `~/dotfiles` leaves mise's link as it is, and the next `--update` works |
| `folder-converted=symlink` | An environment file that arrives in an update does not turn an existing linked folder into a real one. mise warns "is a symlink, which is never followed" and then creates the per-file entries through the link, inside the checkout |

The last line changes Task 4: `setup.sh` on an installed copy removes such a link before it applies the dotfiles. A fresh install is unaffected, because the folder is real from the first apply (probe 12).

This task is complete. All four lines are in `results.txt`.

---

### Task 2: `rotm-mode`

**Files:**

- Create: `bin/lib/rotm-mode` (mode 0755)
- Create: `bin/lib/test-rotm` (mode 0755)
- Modify: `bin/lib/check` (run `bash bin/lib/test-rotm > /dev/null` beside the other self-checks)

**Interfaces:**

- Produces: `rotm-mode [<dir>]` prints `installed` when `<dir>` (default: the repository this script sits in) is the same folder as `${MISE_DATA_DIR:-$HOME/.local/share/mise}/bootstrap-repo`, and `clone` otherwise. Always exits 0. Callers find it beside themselves (`"$(dirname "$0")/lib/rotm-mode"` from `bin/`, `"$DOTFILES_DIR/bin/lib/rotm-mode"` from `setup.sh`), never through `PATH`, so a test fixture uses its own copy.

- [ ] **Step 1: Write the failing test**

`test-rotm` follows `test-claude-config`'s shape: `set -u`, a temp folder removed on exit, a `check <name> <condition>` helper, exit 1 when any check failed. It sets `HOME="$tmp/home"` and unsets `DOTFILES` and `MISE_DATA_DIR` first.

```bash
mode="$repo/bin/lib/rotm-mode"
mkdir -p "$HOME/.local/share/mise/bootstrap-repo" "$tmp/dev" "$tmp/data/bootstrap-repo"
check "mise's checkout is installed" "[ \"\$(bash '$mode' '$HOME/.local/share/mise/bootstrap-repo')\" = installed ]"
check "another folder is a clone" "[ \"\$(bash '$mode' '$tmp/dev')\" = clone ]"
check "MISE_DATA_DIR moves the checkout" "[ \"\$(MISE_DATA_DIR='$tmp/data' bash '$mode' '$tmp/data/bootstrap-repo')\" = installed ]"
check "the default checkout is a clone under another MISE_DATA_DIR" "[ \"\$(MISE_DATA_DIR='$tmp/data' bash '$mode' '$HOME/.local/share/mise/bootstrap-repo')\" = clone ]"
ln -s "$HOME/.local/share/mise/bootstrap-repo" "$tmp/link"
check "a link to the checkout is installed" "[ \"\$(bash '$mode' '$tmp/link')\" = installed ]"
check "no checkout at all is a clone" "[ \"\$(HOME='$tmp/empty' bash '$mode' '$tmp/dev')\" = clone ]"
```

- [ ] **Step 2: Run to see it fail**

Run: `bash bin/lib/test-rotm`
Expected: six `FAIL` lines, exit 1.

- [ ] **Step 3: Write `bin/lib/rotm-mode`**

Header comment in the house form. The comparison is `[ "$dir" -ef "$checkout" ]`, which is false when either is missing.

- [ ] **Step 4: Run to see it pass, then commit**

Run: `bash bin/lib/test-rotm`
Expected: six `ok` lines, exit 0.

```bash
git add bin/lib/rotm-mode bin/lib/test-rotm bin/lib/check
git commit -m "Add rotm-mode to tell an installed copy from a dev clone"
```

---

### Task 3: The `rotm` command

**Files:**

- Create: `bin/rotm` (mode 0755)
- Modify: `bin/lib/test-rotm`
- Modify: `docs/README.md` (add `rotm` to the command index)

**Interfaces:**

- Consumes: `rotm-mode` from Task 2.
- Produces:
  - `rotm install [<setup.sh args>]`: `exec "$DOTFILES/setup.sh" "$@"`.
  - `rotm update [<setup.sh args>]`: described below.
  - `rotm settings [<args>]`: `exec "$DOTFILES/bin/dotfiles-settings" "$@"`.
  - `rotm`, `rotm help`, `rotm -h`, `rotm --help`: print the header, exit 0. Any other first word: `rotm: unknown command: <word>` on stderr, exit 2.

`rotm update`, in order:

1. `rotm-mode` prints `clone`: print `rotm: this is a development clone. Pull it yourself, then run ./setup.sh` on stderr and exit 1.
2. `branch=$(git -C "$DOTFILES" symbolic-ref -q --short HEAD)` fails: print `rotm: the installed copy is not on a branch (git -C <path> status shows where it is)` and exit 1.
3. `url=$(git -C "$DOTFILES" remote get-url origin)`. mise requires the URL to match the checkout's origin, so it is read, never hard-coded.
4. From `$HOME`: `mise bootstrap --from "$url?ref=$branch" --config-dir tilde/.config/mise --update --only final-hook`, with `--yes` added when the arguments before any `--` include `-y` or `--yes`.
5. That fails: print `rotm: mise refused or failed to update the installed copy. Tracked files that differ in it:`, then `git -C "$DOTFILES" status --short --untracked-files=no`, then `Nothing was installed.` and exit with mise's code. `setup.sh` does not run.
6. `exec "$DOTFILES/setup.sh" "$@"`. The update may have replaced `bin/rotm` itself. That is safe: git writes a new file and bash keeps reading the one it opened (the plan's reviewer ran this).

- [ ] **Step 1: Write the failing tests**

Add to `test-rotm`. The fixture is a real Git repository at `$HOME/.local/share/mise/bootstrap-repo` on branch `stable` with a bare origin in `$tmp`, a `setup.sh` stub that appends `setup $*` to `$tmp/log`, and `bin/lib/rotm-mode` and `bin/rotm` copied from the repository. `mise` and `dotfiles-settings` are stubs on `PATH`. The `mise` stub appends `cwd $PWD` and then its arguments to `$tmp/log` and exits `${STUB_MISE_RC:-0}`. The test calls `rotm() { bash "$fix/bin/rotm" "$@"; }` with `DOTFILES` unset, so it finds the fixture from its own path. `$tmp/dev` is a second fixture with the same files outside mise's checkout path.

```bash
check "install passes its arguments to setup.sh" "rotm install -y -- --upgrade && grep -qx 'setup -y -- --upgrade' '$tmp/log'"
check "settings passes through" "rotm settings list && grep -qx 'dotfiles-settings list' '$tmp/log'"
: > "$tmp/log"
check "update fetches the branch it is on" "rotm update && grep -q -- \"--from $origin?ref=stable --config-dir tilde/.config/mise --update --only final-hook\" '$tmp/log'"
check "update runs mise from HOME" "grep -qx \"cwd $HOME\" '$tmp/log'"
check "update then runs setup.sh" "[ \"\$(tail -1 '$tmp/log')\" = 'setup ' ]"
check "update without -y does not pass --yes to mise" "! grep -q -- '--yes' '$tmp/log'"
: > "$tmp/log"
check "update -y passes --yes to mise and -y to setup.sh" "rotm update -y && grep -q -- '--only final-hook --yes' '$tmp/log' && grep -qx 'setup -y' '$tmp/log'"
: > "$tmp/log"
echo edit >> "$fix/setup.sh"
check "a refused update exits with mise's code" "STUB_MISE_RC=1 rotm update > '$tmp/out' 2>&1; [ \$? -eq 1 ]"
check "a refused update does not run setup.sh" "! grep -q '^setup' '$tmp/log'"
check "a refused update names the tracked files that differ" "grep -q 'setup.sh' '$tmp/out' && ! grep -q '??' '$tmp/out'"
git -C "$fix" checkout -q -- setup.sh
git -C "$fix" checkout -q --detach
check "a detached copy stops the update" "! rotm update 2> '$tmp/err' && grep -q 'not on a branch' '$tmp/err'"
check "update in a dev clone refuses" "! bash '$tmp/dev/bin/rotm' update 2> '$tmp/err' && grep -q 'development clone' '$tmp/err'"
check "an unknown command exits 2" "rotm frobnicate 2> /dev/null; [ \$? -eq 2 ]"
check "no argument prints usage" "rotm | grep -q 'rotm update'"
```

The fixture holds one untracked file, so the `??` check means something.

- [ ] **Step 2: Run to see them fail**

Run: `bash bin/lib/test-rotm`
Expected: the fourteen new checks `FAIL`.

- [ ] **Step 3: Write `bin/rotm`**

`#!/bin/bash`, `set -euo pipefail`, the header block in `bin/CLAUDE.md`'s form with one example per subcommand, `DOTFILES` resolved as `bin/dotfiles` does. A comment beside `--only final-hook` names probes 11 and 13.

- [ ] **Step 4: Run to see them pass, check the help page**

Run: `bash bin/lib/test-rotm`
Expected: every line `ok`.

Run: `help rotm`
Expected: the tldr page with the four invocations.

- [ ] **Step 5: Commit**

```bash
git add bin/rotm bin/lib/test-rotm docs/README.md
git commit -m "Add rotm: install, update and settings in one command"
```

---

### Task 4: The scripts that must know they are installed

**Files:**

- Modify: `setup.sh` (every `rerun ./setup.sh` and the `To retry:` line)
- Modify: `bin/sysup` (the dotfiles step near line 200, the `claude-config save` branch near line 680)
- Modify: `bin/dotfiles`
- Modify: `bin/vscode-settings` (its `dir=` default)
- Modify: `bin/lib/test-bootstrap`, `bin/lib/test-sysup`, `vscode/test-vscode-settings.sh`
- Modify: `setup/README.md`, `docs/claude-config.md`

**Interfaces:**

- Consumes: `rotm-mode` from Task 2, called by path.
- Produces: nothing later tasks use.

- [ ] **Step 1: Make the fixtures able to be installed copies**

- `test-bootstrap`: copy `bin/lib/rotm-mode` into `$fix/bin/lib/`. Give the fixture a `tilde/.config/mise/config.installed.toml` declaring `"~/.config/gh"`, `"~/.config/keep"` and `"~/.config/elsewhere"` with `permissions` alone and a `tilde/.config/gh` folder, and have `prepare` for these cases make `~/.config/gh` a link to that folder in whichever copy will run, `~/.config/keep` a real folder and `~/.config/elsewhere` a link to `$tmp/other`. Add `MISE_DATA_DIR` to the `unset` line. Add `run_installed [args…]`, which does what `run` does but, after `prepare`, copies `$fix` to `$HOME/.local/share/mise/bootstrap-repo` and runs that copy's `setup.sh`.
- `test-sysup`: copy `bin/lib/rotm-mode` into the fixture beside the copied `sysup`, so `"$(dirname "$0")/lib/rotm-mode"` resolves. Add `MISE_DATA_DIR` to its `unset` line. For the installed case, export `MISE_DATA_DIR="$tmp/data"` and make `$tmp/data/bootstrap-repo` a symlink to `$DOTFILES`.

Run: `bash bin/lib/test-bootstrap && bash bin/lib/test-sysup`
Expected: exit 0. Nothing new is asserted yet.

- [ ] **Step 2: Write the failing tests**

`test-bootstrap`, after the existing clone-mode cases, with one package made to fail through the mise stub as the existing problem cases do:

```bash
run_installed -y
check_true "installed: the retry hint names rotm" grep -q 'To retry: rotm install' <<< "$out"
check_true "installed: a warning names rotm" grep -q 'then rerun rotm install' <<< "$out"
check_true "installed: ~/dotfiles links to mise's checkout" [ "$HOME/dotfiles" -ef "$HOME/.local/share/mise/bootstrap-repo" ]
check_true "installed: a link into the checkout at a real-folder key is removed" [ ! -L "$HOME/.config/gh" ]
check_true "installed: a real folder at such a key is kept" [ -d "$HOME/.config/keep" ]
check_true "installed: a link that points elsewhere is kept" [ -L "$HOME/.config/elsewhere" ]
run -y
check_true "clone: a link into the clone at such a key is kept" [ -L "$HOME/.config/gh" ]
check_true "clone: the hints still name ./setup.sh" grep -q 'then rerun ./setup.sh' <<< "$out"
```

`test-sysup`, in the installed fixture, after `rm -f "$STATE/claude-config.log"` and a run:

```bash
check_true "installed: claude-config save is not run" no_save
check_true "installed: restore --dry-run still runs" grep -qx 'restore settings --dry-run' "$STATE/claude-config.log"
check_true "installed: the Claude config line says why" has 'Claude config.*installed copy'
check_true "installed: the dotfiles step points at rotm update" has 'dotfiles.*rotm update'
check_true "installed: the copy is not called up to date" lacks 'dotfiles.*up to date'
check_true "installed: no advice to run claude-config save" lacks 'claude-config save'
```

`vscode/test-vscode-settings.sh`: with `MISE_DATA_DIR` pointing at a folder whose `bootstrap-repo` is the script's own repository copy and `VSCODE_SETTINGS_DIR` unset, a render writes `settings.json` under `$HOME/Library/Application Support/Code/User`, and nothing under the repository's `vscode/User`.

- [ ] **Step 3: Run to see them fail**

Run each of the three test files.
Expected: each stops at its first new assertion (`check_true` exits on a failure) and every older assertion before it passes.

- [ ] **Step 4: Implement**

- `setup.sh`: `self=./setup.sh`, and `self='rotm install'` when `"$DOTFILES_DIR/bin/lib/rotm-mode" "$DOTFILES_DIR"` prints `installed`. Use `$self` in the `To retry:` line and in every warning that says `rerun ./setup.sh` (seven of them today). The three messages printed before the mode is known to matter (Command Line Tools, `~/dotfiles`, `~/.config/mise`) use it too. A clone prints the same text as before.
- `bin/sysup`, dotfiles step: on an installed copy, do not call `dotfiles`. Report `status notice dotfiles "installed copy: run rotm update"`.
- `bin/sysup`, Claude config: on an installed copy, skip `claude-config save` and the action that advises it, and report `status ok "Claude config" "installed copy: not saved into it"`.
- `bin/dotfiles`: on an installed copy, print `This is an installed copy. Run: rotm update` and exit 0 without pulling.
- `setup.sh`, on an installed copy only, before `mise dotfiles apply`: for each key that `config.installed.toml` declares with `permissions` alone, when that path is a symlink whose target is inside `$DOTFILES_DIR`, remove the symlink and print `Unlinked <path>: it is a real folder on an installed copy`. Probe 14 showed mise otherwise keeps the link and writes the folder's per-file entries into the checkout. The key list is read with `sed -n 's/^"\([^"]*\)" = { permissions = .*/\1/p'`, and a leading `~/` becomes `$HOME/`. A real folder, a missing path and a link that points outside the checkout are left alone.
- `bin/vscode-settings`: when `VSCODE_SETTINGS_DIR` is unset and the copy is installed, `dir` is `$HOME/Library/Application Support/Code/User`. Task 5 makes that folder real on an installed copy.

- [ ] **Step 5: Run to see them pass**

Run: `bash bin/lib/test-bootstrap && bash bin/lib/test-sysup && bash vscode/test-vscode-settings.sh`
Expected: exit 0.

- [ ] **Step 6: Document and commit**

`setup/README.md`: one section, "Installed copies", saying what differs (the hints, `sysup` neither pulling nor saving Claude config, `dotfiles` pointing at `rotm update`, where VS Code's `settings.json` is rendered). `docs/claude-config.md`: one sentence in the `sysup` paragraph.

```bash
git add setup.sh bin/sysup bin/dotfiles bin/vscode-settings bin/lib/test-bootstrap bin/lib/test-sysup vscode/test-vscode-settings.sh setup/README.md docs/claude-config.md
git commit -m "Keep an installed copy clean, and name rotm in its hints"
```

---

### Task 5: Targets that apps and tools write to

**Files:**

- Create: `tilde/.config/mise/config.installed.toml`
- Create: `tilde/.gitconfig.installed`, `tilde/.zshrc.installed`
- Modify: `bin/lib/test-dotfiles`
- Modify: `tilde/.config/mise/conf.d/40-dotfiles.toml` (its header comment only)
- Modify: the spec (a new table, "How each entry deploys on an installed copy")

**Interfaces:**

- Produces: the `installed` environment, which the install line selects.

The rule for each entry, from probes 5 and 12:

- Read-only to apps: stays a symlink. This is the default and needs no line.
- A file a tool appends to, where our content must keep updating: a seeded wrapper that includes ours.
- A file we only seed and the app then owns: `{ source = "<same source>", mode = "copy", create_if_missing = true }`.
- A linked folder holding such a file: a real folder (`{ permissions = "…" }`) with one entry per tracked file.

- [ ] **Step 1: Write the failing tests**

Add to `test-dotfiles`:

```bash
installed="$repo/tilde/.config/mise/config.installed.toml"
base="$repo/tilde/.config/mise/conf.d/40-dotfiles.toml"
[ -f "$installed" ] || fail "config.installed.toml is missing"
# Each key redeclares a base entry, or sits inside a folder this file makes real
while IFS= read -r key; do
  grep -qF "\"$key\" = " "$base" && continue
  grep -qF "\"${key%/*}\" = { permissions" "$installed" \
    || fail "config.installed.toml declares $key, which redeclares nothing and is in no folder it makes real"
done < <(sed -n 's/^"\([^"]*\)" = .*/\1/p' "$installed")
# A symlink here would put app writes back in the checkout
if grep -E '^"' "$installed" | grep -vE 'create_if_missing = true|merge = |= \{ permissions = "[0-7]+" \}' | grep -q .; then
  fail "config.installed.toml has an entry that is neither create_if_missing, merge nor a real folder"
fi
```

`test-dotfiles` builds a scratch config dir holding only `40-dotfiles.toml` and asserts mise reads only that file. Add a second scratch config dir that also holds `config.installed.toml`, and assert that `MISE_ENV=installed` `mise dotfiles status` there lists `~/.config/gh/config.yml` and reports `~/.gitconfig` as a copy, with no parse error.

- [ ] **Step 2: Run to see it fail**

Run: `bash bin/lib/test-dotfiles`
Expected: `FAIL: config.installed.toml is missing`.

- [ ] **Step 3: Write the two wrappers**

`tilde/.gitconfig.installed`:

```ini
# Yours to edit: git config --global writes here. returnofthemac's settings
# come from the first include and update with it.
[include]
  path = ~/dotfiles/tilde/.gitconfig
[include]
  path = ~/.gitconfig.local
```

`tilde/.zshrc.installed`:

```zsh
# Yours to edit: installers append here. returnofthemac's shell setup is the
# line below and updates with it.
source "$DOTFILES/tilde/.zshrc"
```

Add `tilde/.zshrc.installed` to `.prettierignore` beside the other zsh files. `tilde/.gitconfig` already ends by including `~/.gitconfig.local`, so the second include in the wrapper is harmless and keeps the wrapper readable without the first.

- [ ] **Step 4: Write `config.installed.toml`**

A header comment says what the file is for, that `-E installed` selects it, and that the VM proof's row 7 is where new entries come from.

```toml
[dotfiles]
"~/.gitconfig" = { source = "~/dotfiles/tilde/.gitconfig.installed", mode = "copy", create_if_missing = true }
"~/.zshrc" = { source = "~/dotfiles/tilde/.zshrc.installed", mode = "copy", create_if_missing = true }

# gh rewrites config.yml and keeps hosts.yml beside it
"~/.config/gh" = { permissions = "0700" }
"~/.config/gh/config.yml" = { source = "~/dotfiles/tilde/.config/gh/config.yml", mode = "copy", create_if_missing = true }

# VS Code writes keybindings, tasks and snippets here. settings.json is
# rendered into this folder by bin/vscode-settings, not copied.
"~/Library/Application Support/Code/User" = { permissions = "0700" }
"~/Library/Application Support/Code/User/keybindings.json" = { source = "~/dotfiles/vscode/User/keybindings.json", mode = "copy", create_if_missing = true }
"~/Library/Application Support/Code/User/tasks.json" = { source = "~/dotfiles/vscode/User/tasks.json", mode = "copy", create_if_missing = true }
"~/Library/Application Support/Code/User/chatLanguageModels.json" = { source = "~/dotfiles/vscode/User/chatLanguageModels.json", mode = "copy", create_if_missing = true }
"~/Library/Application Support/Code/User/snippets/global.code-snippets" = { source = "~/dotfiles/vscode/User/snippets/global.code-snippets", mode = "copy", create_if_missing = true }
```

The snippets entry sits two levels below the real folder, so the test's parent check needs `"~/Library/Application Support/Code/User/snippets" = { permissions = "0700" }` as well. `vscode/User/.prettierrc.yaml` is not listed: VS Code never reads it from there.

- [ ] **Step 5: Record a decision for every entry**

Add to the spec, under Distribution, a table with one row per key in `40-dotfiles.toml` (38 today): the key, how it deploys on an installed copy (symlink, wrapper, seeded copy, real folder, merge), and one clause of reason. Entries not named in Step 4 are symlinks, and the reason says what makes them safe ("nothing writes it", "the app keeps its state in an ignored file beside it"). Mark each row `read` or `measured`: Task 6's row 7 turns `read` into `measured` or into a new entry.

- [ ] **Step 6: Run to see it pass, then commit**

Run: `bash bin/lib/test-dotfiles`
Expected: exit 0.

```bash
git add tilde/.config/mise/config.installed.toml tilde/.gitconfig.installed tilde/.zshrc.installed tilde/.config/mise/conf.d/40-dotfiles.toml bin/lib/test-dotfiles .prettierignore docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md
git commit -m "Declare how each dotfile deploys on an installed copy"
git push
```

---

### Task 6: The VM proof

**Files:**

- Create: `docs/superpowers/specs/2026-11-11-installable-probe/p1-evidence.sh` (mode 0755)
- Modify: `tilde/.config/mise/config.installed.toml` and the spec's table (the measured entries)
- Modify: this plan (a `#### Results` section)

**Interfaces:**

- Consumes: `rotm` (Task 3), the `installed` environment (Task 5).
- Produces: the proven commit, which Task 7 promotes.

The install line for the proof follows `main`, because `stable` does not exist yet:

```bash
~/.local/bin/mise -E installed bootstrap --from 'https://github.com/jrmatherly/returnofthemac.git?ref=main' --config-dir tilde/.config/mise --save-env --only final-hook && ~/.local/share/mise/bootstrap-repo/setup.sh
```

`p1-evidence.sh <row>` writes each row's commands and output to `p1-<time>/row-<n>.txt` beside itself, as `run-in-guest.sh` does for the probes. Copy it to `~/vm-proof/p1/`.

- [ ] **Step 1: Write `p1-evidence.sh`, lint it, copy it to the share**

One function per row below that has commands to capture, each printing the commands it runs.

- [ ] **Step 2: The owner runs the rows in a disposable guest**

Rows 1 and 2 come first, on the fresh guest after `xcode-select --install` and mise's installer.

| # | In the guest | Pass |
| --- | --- | --- |
| 1 | `mkdir -p ~/.config/mise && touch ~/.config/mise/config.toml`, then the install line | mise refuses the link and `setup.sh` does not start. Then `rm -rf ~/.config/mise ~/.local/share/mise/bootstrap-repo` |
| 2 | `mkdir ~/dotfiles && echo mine > ~/.zshrc`, then the install line | `setup.sh` stops at `~/dotfiles`, naming it. After `rmdir ~/dotfiles`, a rerun stops at `~/.zshrc` with nothing overwritten (`cat ~/.zshrc` prints `mine`). Then `rm ~/.zshrc` |
| 3 | The install line. Answer the prompts as a new owner would | `setup.sh` ends with "All done", or exit 2 with only the tolerated `royal-tsx` miss |
| 4 | `[ ~/.config/mise -ef ~/.local/share/mise/bootstrap-repo/tilde/.config/mise ]`, the same for `~/dotfiles` and the checkout, `~/dotfiles/bin/lib/rotm-mode`, `cat ~/.config/mise/miserc.local.toml` | both tests true, `installed`, `env = ["installed"]` |
| 5 | `mise bootstrap status --missing`, `mise bootstrap packages status --json` as in A6 rows 3 to 6 | the same result A6 recorded for a `setup.sh` run |
| 6 | A new terminal, then `command -v rotm`, `rotm settings list \| head -3`, `git config --get core.excludesfile` | `rotm` resolves under the checkout, the list prints, and git reads our settings through the wrapper |
| 7 | `git -C ~/dotfiles status --porcelain --untracked-files=no` | empty |
| 8 | Use the Mac: `git config --global alias.zz status`; `gh auth setup-git`; `gh config set editor vim`; `echo '# from an installer' >> ~/.zshrc`; open VS Code and change one keybinding and one setting; open and quit `btop`; open Ghostty, cmux and lazygit once. Then row 7's command again | Record every path listed. Each one becomes an entry in `config.installed.toml` and a `measured` row in the spec's table, on the host |
| 9 | On the host: commit row 8's entries, a one-line change to `tilde/.config/gh/config.yml` and a one-line change to each file row 8 listed, and push. In the guest: `git -C ~/dotfiles checkout -- .` for the files row 8 listed, then `rotm update -y` | the checkout's `HEAD` is the new commit, `setup.sh` ran, `gh config get editor` still prints `vim`, `git config --get alias.zz` still prints `status`, and row 7's command prints nothing |
| 10 | Repeat row 8's actions, then row 7's command, then `rotm update -y` again | still nothing listed, and the second update succeeds |
| 11 | `sysup` | no `claude-config save`, a `rotm update` notice for dotfiles, and row 7's command still prints nothing |
| 12 | `dotfiles` | prints the `rotm update` hint and pulls nothing |

Row 9 discards the stranger's edits to the files row 8 found because those files were still symlinks when the edits were made. That is the cost of finding them in the proof. A real user never meets it: the entries exist before their first install.

- [ ] **Step 3: Record and fix**

Add `#### Results` here: the date, the guest build, the mise version, the commit proven, one line per row. A failure in rows 1 to 7 or 9 to 12 is fixed on `main` and rerun from a fresh disposable guest. Row 8's findings are data, not failures.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-11-11-installable-probe/p1-evidence.sh tilde/.config/mise/config.installed.toml docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md docs/superpowers/plans/2026-11-11-p1-install-and-update.md
git commit -m "Record the VM proof of the installed path"
git push
```

---

### Task 7: The install docs and the `stable` branch

**Files:**

- Modify: `README.md`, `docs/installation.md`, `setup/README.md`

**Interfaces:**

- Consumes: the proven commit from Task 6.
- Produces: the published install line, quoted by Task 8:

```bash
~/.local/bin/mise -E installed bootstrap --from 'https://github.com/jrmatherly/returnofthemac.git?ref=stable' --config-dir tilde/.config/mise --save-env --only final-hook && ~/.local/share/mise/bootstrap-repo/setup.sh
```

- [ ] **Step 1: Write the install section**

`README.md` gains "Install without cloning" above the clone instructions. It states, in this order:

- the two prerequisites: `xcode-select --install`, then mise from https://mise.run;
- the install line;
- that `--from` trusts this repository's configuration for the run, with the link to review it and `--dry-run` to preview;
- what must not be in the way, each with its move-aside command: `~/.config/mise`, `~/dotfiles`, and your own `~/.zshrc`, `~/.zprofile`, `~/.zshenv`, `~/.gitconfig` and `~/.bash_profile`. Nothing is overwritten: the run stops and names the file;
- that macOS preferences are not applied (`set-defaults` does that);
- `rotm update` for later, and `rotm settings` for the settings UI;
- that the copy lives in `~/.local/share/mise/bootstrap-repo` (under `$MISE_DATA_DIR` when that is set, in which case the line's second path changes with it) and is not for editing.

`docs/installation.md` gets the same steps in its numbered form. The clone path stays documented as the way to develop or fork.

- [ ] **Step 2: Write the promotion step**

`setup/README.md` gains "Releasing to `stable`": users follow `stable`; promote with `git push origin <sha>:refs/heads/stable` after the VM install passed on `<sha>`; the push is a plain one, so GitHub refuses anything that is not a fast-forward; never force it.

- [ ] **Step 3: Gate, commit and push**

Run: `pnpm check`
Expected: exit 0.

```bash
git add README.md docs/installation.md setup/README.md
git commit -m "Document installing returnofthemac without a clone"
git push
```

- [ ] **Step 4: Create `stable`, with the owner's go-ahead**

Ask the owner first: this publishes a branch. Check that only Markdown changed since the proven commit:

Run: `git diff --stat <proven sha>..HEAD -- . ':!*.md'`
Expected: no output.

```bash
git push origin HEAD:refs/heads/stable
```

Expected: `* [new branch] HEAD -> stable`. Between Step 3 and this push the README names a branch that does not exist, so run them together.

---

### Task 8: A workflow job for the installed path

**Files:**

- Modify: `.github/workflows/fresh-install.yml`

**Interfaces:**

- Consumes: the install line (Task 7).

- [ ] **Step 1: Turn the job into a matrix**

`strategy.matrix.path: [clone, installed]` with `fail-fast: false`. The steps that differ:

- `actions/checkout` and "Move the runner's own dotfiles aside" stay for both. The checkout is unused on `installed`, and keeping it leaves the later steps identical.
- New step, `if: matrix.path == 'installed'`, "Install mise": `curl -fsSL https://mise.run | sh` and nothing else. `~/.local/bin` is not added to `GITHUB_PATH` here: the install line must work without it, as on a stranger's Mac. The existing "Remove Homebrew" step's `if command -v mise; then exit 1; fi` runs before this step.
- The `setup.sh` step becomes two steps guarded by `matrix.path`. The `installed` one runs the published install line with `?ref=${{ github.ref_name }}` in place of `?ref=stable` and `-y --skip-codegraph -- --skip user` after `setup.sh`, with the same exit-code rule.
- "Disk after setup" sets `MISE_CONFIG_DIR` to `$HOME/.config/mise` for both paths. It is the same folder through the link.
- New final steps, `if: matrix.path == 'installed'`: `test "$("$HOME/dotfiles/bin/lib/rotm-mode")" = installed`; `"$HOME/dotfiles/bin/rotm" update -y --skip-codegraph -- --skip user`, with the same exit-code rule; then `test -z "$(git -C "$HOME/dotfiles" status --porcelain --untracked-files=no)"`.

- [ ] **Step 2: Lint and commit**

Run: `actionlint .github/workflows/fresh-install.yml`
Expected: no output.

```bash
git add .github/workflows/fresh-install.yml
git commit -m "Run fresh-install for the installed path too"
git push
```

Running the workflow is the owner's call: it takes up to four hours of a hosted runner per path.

---

### Task 9: Close the phase

**Files:**

- Modify: `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`
- Modify: `CLAUDE.md`, `.claude/rules/setup.md`, `.claude/rules/symlinks.md` where a stated fact became false

- [ ] **Step 1: Update the spec**

In Distribution: the chosen shape is config-dir, the install is mise to fetch and link followed by `setup.sh`, and `~/dotfiles` is kept in installed mode (replace the sentence that says it is dropped, and the matching Risks bullet). Add probe 14 to "Verified facts". In the P1 brief, replace "Settled by P0" and "Decided" with one "Shipped" line naming this plan. In "Plans", mark this file done.

- [ ] **Step 2: Check the instruction files**

Run: `grep -n 'setup.sh\|~/dotfiles' CLAUDE.md .claude/rules/setup.md .claude/rules/symlinks.md`
Fix only a sentence that is now false. `~/dotfiles` "must be a symlink to the clone" becomes "to the clone or, on an installed copy, to mise's checkout".

- [ ] **Step 3: Move the plan and commit**

```bash
git mv docs/superpowers/plans/2026-11-11-p1-install-and-update.md docs/superpowers/plans/completed/
git add -A docs/superpowers CLAUDE.md .claude/rules
git commit -m "Complete P1: install and update without a clone"
git push
```

Then ask the owner to review before P2 is written.
