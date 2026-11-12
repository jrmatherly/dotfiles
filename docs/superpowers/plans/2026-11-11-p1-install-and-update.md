# P1: Install and Update Without a Clone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On a Mac with only mise and the Command Line Tools, one pasted line installs returnofthemac, `rotm update` brings in new commits, and neither needs a clone, a fork or an edit to our repository.

**Architecture:** mise fetches and links, our script installs. `mise bootstrap --from <url>?ref=stable --config-dir tilde/.config/mise` clones the repository to mise's checkout and links `~/.config/mise` into it, applying nothing. Then the checkout's own `setup.sh` runs, the script the A6 VM run already proved. A new `rotm` command wraps install, update and `dotfiles-settings`. Targets that apps rewrite get a second declaration in a mise config environment named `installed`, so an installed checkout stays clean and the owner's clone keeps its symlinks.

**Tech Stack:** bash 3.2 (`#!/bin/bash`), mise 2026.11.5 or newer, git, `/usr/bin/jq`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`. Read "Verified facts", the Distribution section and the P1 brief first.

## Global Constraints

- macOS only.
- mise floor: 2026.11.5 (`setup/mise-floor.sh`). The owner left it there on 2026-11-11. The P0 probes ran on 2026.11.6.
- Names: the product is `returnofthemac`, the command is `rotm`, the repository is `https://github.com/jrmatherly/returnofthemac.git`. `rotm` wraps `dotfiles-settings`. No existing command, variable or folder is renamed in this plan.
- Users follow `?ref=stable`. `stable` moves only by a fast-forward to a commit on `main` that passed the VM install.
- The owner's Mac stays in clone mode. `./setup.sh` from a clone must behave exactly as before: `bin/lib/test-bootstrap` passes with no assertion removed or loosened.
- Testing rule: a real install or update runs in the UTM guest `macOS`, started with "Run without saving changes", never on the owner's Mac. Evidence goes to the shared folder, `/Volumes/My Shared Files/vm-proof` in the guest and `~/vm-proof` on the host. Self-checks with stubs and scratch homes run anywhere.
- Never run `./setup.sh`, `sysup`, `rotm install`, `rotm update` or `mise bootstrap` against the real home. Never edit `config.local.toml` or `config.override.toml`.
- The owner runs every step inside the guest. An agent session on the host cannot reach it.
- The commit hook runs `pnpm check` (about two minutes) before the command starts. Edit and commit in separate Bash calls, and retry once when the hook times out.
- Docs mirror behaviour: a change to setup behaviour has its `README.md`, `setup/README.md` or `docs/` edit in the same commit.

## Decisions this plan makes

- **Shape: config-dir.** The repository is already laid out that way (`tilde/.config/mise`), probe 9 proved the link and the update, and `setup.sh` already expects `~/.config/mise` to be that link.
- **mise does not apply anything.** mise's own part order installs packages before dotfiles. `setup.sh` links the dotfiles first because a package that writes `~/.gitconfig` otherwise leaves a real file where a link belongs and stops the apply. `setup.sh` also carries on past one failed package. So the install line is two commands joined by `&&`: mise to fetch and link, then `setup.sh`.
- **`~/dotfiles` stays.** The spec said installed mode could drop the link. It is kept: `setup.sh` makes it to whichever checkout it runs from, and lazygit's `shellFunctionsFile`, `zsh/env.zsh`, the bootstrap hooks and every `[dotfiles]` source rely on it. Dropping it belongs with the later full rename. Task 9 corrects the spec.
- **The floor check stays where it is.** `setup.sh` runs `setup/mise-floor.sh` before its first mise call. A mise too old for `--from` fails on the install line's first command by itself.
- **`installed` is a mise config environment.** `tilde/.config/mise/config.installed.toml` redeclares the targets apps rewrite. The install line passes `-E installed --save-env`. Task 1 measures whether that file beats `conf.d/40-dotfiles.toml`.

## Review Focus

- A stranger who already has a real `~/.config/mise`: mise refuses the link, the `&&` stops the line before `setup.sh`, and the docs say to move the folder aside. Pinned in Task 6 (docs) and Task 7 (row 1).
- `rotm update` when an app has edited a tracked file and upstream changed the same file: it stops before `setup.sh`, names the files and exits non-zero. Pinned in Task 3.
- `rotm update` typed in the owner's dev clone: it refuses and changes nothing. Pinned in Task 3.
- `sysup` on an installed copy: it must not run `claude-config save`, which writes `agents/` inside the checkout. Pinned in Task 4.
- `MISE_DATA_DIR` set to another folder: `rotm-mode` follows it. Pinned in Task 2.
- An installed checkout on a detached HEAD: `rotm update` exits 1 and says so. Pinned in Task 3.

---

## File Structure

- `bin/lib/rotm-mode`: prints `installed` or `clone`. The one place that knows the difference.
- `bin/rotm`: `install`, `update`, `settings`, `help`.
- `bin/lib/test-rotm`: self-check for both, run by `bin/lib/check`.
- `tilde/.config/mise/config.installed.toml`: the `installed` environment's `[dotfiles]` overrides.
- `setup.sh`, `bin/sysup`, `bin/dotfiles`: one installed-mode branch each.
- `bin/lib/test-bootstrap`, `bin/lib/test-sysup`, `bin/lib/test-dotfiles`: one new block each.
- `docs/superpowers/specs/2026-11-11-installable-probe/probe.sh`, `results.txt`: probes 11 to 13.
- `docs/superpowers/specs/2026-11-11-installable-probe/p1-evidence.sh`: writes the VM proof rows to the shared folder.
- `.github/workflows/fresh-install.yml`: a matrix over the two install paths.
- `README.md`, `docs/installation.md`, `setup/README.md`, `docs/README.md`, the spec.

---

### Task 1: Measure three mise facts in the guest

**Files:**

- Modify: `docs/superpowers/specs/2026-11-11-installable-probe/probe.sh`
- Modify: `docs/superpowers/specs/2026-11-11-installable-probe/results.txt`

**Interfaces:**

- Consumes: `new_home`, `new_project`, `project`, `commit_all`, `g`, `m`, `step`, `boot`, `checkout`, `has`, `kind`, `pick`, `upstream`, `synced`, `answer` from `probe.sh`.
- Produces: three `PROBE` lines that Tasks 3, 5 and 6 read.

`main` accepts numbers up to 13: change `[1-9] | 10)` to `[1-9] | 1[0-3])` and the default list to 1 through 13. On the host these functions get only `bash -n` and `shellcheck`.

- [ ] **Step 1: `probe_11`, fetch and link without applying, and without a root `mise.toml`**

`new_home mac-a` and `new_project`. Add `cfg/config.toml` with `[dotfiles]` and `"~/.probe/from-cfg" = "../files/linked"`, commit, `rmdir "$MISE_CONFIG_DIR"`. Run `m bootstrap --from "file://$project" --config-dir cfg --only final-hook`. Record its exit code, whether `$MISE_CONFIG_DIR` is a symlink, and whether `~/.probe/from-cfg` or `~/.probe/linked` exists. Then start again from `new_home mac-a` with a second project that has `cfg/` and no root `mise.toml` (`g -C "$project" rm -q mise.toml mise.extras.toml mise.work.toml`, commit) and repeat. Answer: `only-final-hook=<ok|error> linked=<yes|no> applied=<nothing|something> no-root-toml=<ok|error>`.

- [ ] **Step 2: `probe_12`, an environment file overriding `conf.d`**

`new_home mac-a` and `new_project`. In the project add:

```toml
# cfg/conf.d/40.toml
[dotfiles]
"~/.probe/app" = { source = "../../files/linked", mode = "symlink" }
"~/.probe/dir" = { source = "../../files", mode = "symlink" }
```

```toml
# cfg/config.installed.toml
[dotfiles]
"~/.probe/app" = { source = "../files/linked", mode = "copy", create_if_missing = true }
"~/.probe/dir" = { permissions = "0755" }
"~/.probe/dir/one" = { source = "../files/copied", mode = "symlink" }
```

Commit, `rmdir "$MISE_CONFIG_DIR"`, run `m -E installed bootstrap --from "file://$project" --config-dir cfg --save-env`. Record `kind ~/.probe/app` and whether `~/.probe/dir` is a symlink or a real directory. Then `rm -rf ~/.probe`, run `m dotfiles apply --yes` with no `-E`, and record `kind ~/.probe/app` again. Answer: `file-override=<file|symlink|missing> dir-override=<real-dir|symlink|error> remembered=<yes|no>`. `remembered` is `yes` when the second apply made a regular file.

- [ ] **Step 3: `probe_13`, an update that fetches without applying**

Continue from the state of probe 11's first project (rebuild it the same way). After the first run, `upstream extra`, then run the same command with `--update` added. Answer: `update-only-final-hook=<updates|refuses> exit=<code>`, from `synced "$(checkout)"`.

- [ ] **Step 4: Lint, copy to the share, run in the guest**

Run: `bash -n docs/superpowers/specs/2026-11-11-installable-probe/probe.sh && shellcheck docs/superpowers/specs/2026-11-11-installable-probe/probe.sh`
Expected: no output.

Run: `cp docs/superpowers/specs/2026-11-11-installable-probe/probe.sh ~/vm-proof/p0/probe.sh`

The owner runs in the guest (Command Line Tools and mise installed first, as in P0): `bash "/Volumes/My Shared Files/vm-proof/p0/run-in-guest.sh" 11 12 13`
Expected: three `PROBE` lines in the newest `~/vm-proof/p0/run-*` folder. Append them to `results.txt`.

- [ ] **Step 5: Apply the decision rules, then commit**

| Result | What later tasks do |
| --- | --- |
| Probe 11 `only-final-hook=ok`, `linked=yes`, `applied=nothing` | `FETCH_ONLY` in Task 3 is `--only final-hook` |
| Probe 11 anything else | `FETCH_ONLY` is `--skip accounts,plugins,packages,files,services,firewall,compose,repos,dotfiles,mise-shell-activate,macos-defaults,macos-launchd-agents,user,tools,task,final-hook`. Rerun probes 11 and 13 with that before Task 3 |
| Probe 11 `no-root-toml=error` | Task 6 adds a root `mise.toml` holding one comment line, and its docs tell a dev-clone owner to run `mise trust` once |
| Probe 12 `file-override=file` and `remembered=yes` | Task 5 goes ahead as written |
| Probe 12 `file-override=symlink` or `remembered=no` | Stop and ask the owner. The fallback changes the base entries for every Mac and puts the symlink forms in the owner's own `config.local.toml`, which only the owner edits |
| Probe 12 `dir-override=real-dir` | Task 5 may turn a linked folder into per-file entries |
| Probe 12 `dir-override` anything else | Task 5 leaves folder links alone and reports any app-written file inside one to the owner |
| Probe 13 `refuses` | `rotm update` in Task 3 runs `git -C <checkout> pull --ff-only` itself in place of the mise call |

```bash
git add docs/superpowers/specs/2026-11-11-installable-probe/probe.sh docs/superpowers/specs/2026-11-11-installable-probe/results.txt
git commit -m "Probe a fetch-only bootstrap and an environment override"
```

---

### Task 2: `rotm-mode`

**Files:**

- Create: `bin/lib/rotm-mode` (mode 0755)
- Create: `bin/lib/test-rotm` (mode 0755)
- Modify: `bin/lib/check` (run `bash bin/lib/test-rotm > /dev/null` beside the other self-checks)

**Interfaces:**

- Produces: `rotm-mode [<dir>]` prints `installed` when `<dir>` (default: the repository this script sits in, honouring `$DOTFILES`) resolves with `pwd -P` to the same folder as `${MISE_DATA_DIR:-$HOME/.local/share/mise}/bootstrap-repo`, and `clone` otherwise. Always exits 0.

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

Header comment in the house form. The comparison is `[ "$dir" -ef "$checkout" ]` after both exist, so a missing checkout is `clone`.

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

- Consumes: `rotm-mode` from Task 2. `FETCH_ONLY` from Task 1's decision table.
- Produces:
  - `rotm install [<setup.sh args>]`: `exec "$DOTFILES/setup.sh" "$@"`.
  - `rotm update [<setup.sh args>]`: described below.
  - `rotm settings [<args>]`: `exec "$DOTFILES/bin/dotfiles-settings" "$@"`.
  - `rotm`, `rotm help`, `rotm -h`, `rotm --help`: print the header, exit 0. Any other first word: `rotm: unknown command: <word>` on stderr, exit 2.

`rotm update`, in order:

1. `rotm-mode` prints `clone`: print `rotm: this is a development clone. Pull it yourself, then run ./setup.sh` on stderr and exit 1.
2. `branch=$(git -C "$DOTFILES" symbolic-ref -q --short HEAD)` fails: print `rotm: the installed copy is not on a branch (git -C <path> status shows where it is)` and exit 1.
3. `url=$(git -C "$DOTFILES" remote get-url origin)`. mise requires the URL to match the checkout's origin, so it is read, never hard-coded.
4. From `$HOME`: `mise bootstrap --from "$url?ref=$branch" --config-dir tilde/.config/mise --update $FETCH_ONLY`.
5. That fails: print `rotm: the update did not apply. Files changed in the installed copy:`, then `git -C "$DOTFILES" status --short`, then `Nothing was installed.` and exit with mise's code. `setup.sh` does not run.
6. `exec "$DOTFILES/setup.sh" "$@"`.

- [ ] **Step 1: Write the failing tests**

Add to `test-rotm`. The fixture is a real Git repository at `$HOME/.local/share/mise/bootstrap-repo` on branch `stable` with a bare origin in `$tmp`, a `setup.sh` stub that appends `setup $*` to `$tmp/log`, and a `bin/lib/rotm-mode` copied from the repository. `mise` and `dotfiles-settings` are stubs on `PATH` that append their arguments to `$tmp/log`; the `mise` stub exits `${STUB_MISE_RC:-0}`. `rotm` is copied into the fixture's `bin/`, and the test calls it through `rotm() { bash "$fix/bin/rotm" "$@"; }` with `DOTFILES` unset, so it finds the fixture from its own path.

```bash
check "install passes its arguments to setup.sh" "rotm install -y -- --upgrade && grep -qx 'setup -y -- --upgrade' '$tmp/log'"
check "settings passes through" "rotm settings list && grep -qx 'dotfiles-settings list' '$tmp/log'"
check "update fetches the branch it is on" "rotm update && grep -q -- \"--from $origin?ref=stable --config-dir tilde/.config/mise --update\" '$tmp/log'"
check "update runs mise from HOME" "grep -qx \"cwd $HOME\" '$tmp/log'"
check "update then runs setup.sh" "[ \"\$(tail -1 '$tmp/log')\" = 'setup ' ]"
: > "$tmp/log"
check "a refused update exits with mise's code" "STUB_MISE_RC=1 rotm update > '$tmp/out' 2>&1; [ \$? -eq 1 ]"
check "a refused update does not run setup.sh" "! grep -q '^setup' '$tmp/log'"
check "a refused update names the changed files" "grep -q 'Files changed in the installed copy' '$tmp/out'"
git -C "$fix" checkout -q --detach
check "a detached copy stops the update" "! rotm update 2> '$tmp/err' && grep -q 'not on a branch' '$tmp/err'"
check "update in a dev clone refuses" "! DOTFILES='$tmp/dev' bash '$tmp/dev/bin/rotm' update 2> '$tmp/err' && grep -q 'development clone' '$tmp/err'"
check "an unknown command exits 2" "rotm frobnicate 2> /dev/null; [ \$? -eq 2 ]"
check "no argument prints usage" "rotm | grep -q 'rotm update'"
```

The `mise` stub prints `cwd $PWD` to the log before its arguments. `$tmp/dev` is a second fixture with the same files outside mise's checkout path.

- [ ] **Step 2: Run to see them fail**

Run: `bash bin/lib/test-rotm`
Expected: the twelve new checks `FAIL`.

- [ ] **Step 3: Write `bin/rotm`**

`#!/bin/bash`, `set -euo pipefail`, the header block in `bin/CLAUDE.md`'s form with one example per subcommand, `DOTFILES` resolved as `bin/dotfiles` does. `FETCH_ONLY` is one variable at the top with a comment giving the probe that chose it.

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

### Task 4: The three scripts that must know they are installed

**Files:**

- Modify: `setup.sh` (the two "rerun ./setup.sh" hints in the final summary)
- Modify: `bin/sysup` (the `claude-config save` branch near line 680)
- Modify: `bin/dotfiles`
- Modify: `bin/lib/test-bootstrap`, `bin/lib/test-sysup`
- Modify: `setup/README.md`, `docs/claude-config.md`

**Interfaces:**

- Consumes: `rotm-mode` from Task 2.
- Produces: nothing later tasks use.

- [ ] **Step 1: Write the failing tests**

In `test-bootstrap`, after the existing clone-mode cases, run the fixture's `setup.sh` once more from a copy placed at `$HOME/.local/share/mise/bootstrap-repo` with one package made to fail through the mise stub, and assert:

```bash
check_true "installed: the retry hint names rotm" grep -q 'To retry: rotm install' "$tmp/out"
check_true "installed: ~/dotfiles links to mise's checkout" [ "$HOME/dotfiles" -ef "$HOME/.local/share/mise/bootstrap-repo" ]
```

In `test-sysup`, in a fixture whose `DOTFILES` is `$HOME/.local/share/mise/bootstrap-repo`:

```bash
check_true "installed: claude-config save is not run" lacks_line 'claude-config save'
check_true "installed: restore --dry-run still runs" has_line 'claude-config restore settings --dry-run'
check_true "installed: the status line says why" has 'Claude config.*installed copy'
```

Use the helpers those files already define for reading the stub log and the output; add `lacks_line` beside `has_line` when it is missing.

- [ ] **Step 2: Run to see them fail**

Run: `bash bin/lib/test-bootstrap; bash bin/lib/test-sysup`
Expected: the five new assertions fail and every older one passes.

- [ ] **Step 3: Implement**

- `setup.sh`: `self=./setup.sh`, and `self='rotm install'` when `"$DOTFILES_DIR/bin/lib/rotm-mode" "$DOTFILES_DIR"` prints `installed`. Use `$self` in the summary's retry line. The earlier `rerun ./setup.sh` warnings keep their text.
- `bin/sysup`: when `rotm-mode` prints `installed`, skip `claude-config save` and report `status skip "Claude config" "installed copy: your plugins and settings are not saved into it"`. Use the status kind that file already uses for a skipped step.
- `bin/dotfiles`: when installed, print `This is an installed copy. Run: rotm update` and exit 0 without pulling.

- [ ] **Step 4: Run to see them pass**

Run: `bash bin/lib/test-bootstrap && bash bin/lib/test-sysup`
Expected: exit 0.

- [ ] **Step 5: Document and commit**

`setup/README.md`: one paragraph, "Installed copies", saying what differs (the retry hint, `sysup` not saving Claude config, `dotfiles` pointing at `rotm update`). `docs/claude-config.md`: one sentence in the `sysup` paragraph.

```bash
git add setup.sh bin/sysup bin/dotfiles bin/lib/test-bootstrap bin/lib/test-sysup setup/README.md docs/claude-config.md
git commit -m "Keep an installed copy clean: no Claude config save, and rotm in the hints"
```

---

### Task 5: Targets that apps rewrite

**Files:**

- Create: `tilde/.config/mise/config.installed.toml`
- Modify: `bin/lib/test-dotfiles`
- Modify: `tilde/.config/mise/conf.d/40-dotfiles.toml` (its header comment only)

**Interfaces:**

- Consumes: probe 12's answers from Task 1.
- Produces: the `installed` environment, which Task 6's install line selects.

The rule for each entry, from probe 5: a file we only seed becomes `{ source = "<same source>", mode = "copy", create_if_missing = true }`. A file where we own some keys becomes a `merge` entry, as `~/.codex/config.toml/defaults` already is. A linked folder holding such a file becomes a real folder with one entry per tracked file, when probe 12 allows it.

- [ ] **Step 1: Write the failing test**

Add to `test-dotfiles`:

```bash
# An override of nothing is a typo, and a symlink here would put app writes back in the checkout
installed="$repo/tilde/.config/mise/config.installed.toml"
[ -f "$installed" ] || fail "config.installed.toml is missing"
while IFS= read -r key; do
  grep -qF "\"$key\"" "$repo/tilde/.config/mise/conf.d/40-dotfiles.toml" \
    || case $key in */*/*) ;; *) fail "config.installed.toml overrides $key, which 40-dotfiles.toml does not declare" ;; esac
done < <(sed -n 's/^"\([^"]*\)" = .*/\1/p' "$installed")
if grep -E '^"' "$installed" | grep -vE 'create_if_missing = true|merge = |permissions = ' | grep -q .; then
  fail "config.installed.toml has an entry that is neither create_if_missing, merge nor a folder"
fi
```

The `*/*/*` case lets a per-file entry under a converted folder through.

- [ ] **Step 2: Run to see it fail**

Run: `bash bin/lib/test-dotfiles`
Expected: `FAIL: config.installed.toml is missing`.

- [ ] **Step 3: Write `config.installed.toml` with the starting list**

A header comment says what the file is for, that `-E installed` selects it, and that Task 7's measurement is the source of the list. Start with the entry already known to be app-written: `"~/.config/gh"` holds `config.yml`, which `gh config set` rewrites (the root `CLAUDE.md` calls it app-written). When probe 12 gave `dir-override=real-dir`:

```toml
[dotfiles]
"~/.config/gh" = { permissions = "0700" }
"~/.config/gh/config.yml" = { source = "~/dotfiles/tilde/.config/gh/config.yml", mode = "copy", create_if_missing = true }
```

Otherwise leave `[dotfiles]` empty with a comment naming `gh` as reported to the owner. Task 7 adds the rest.

- [ ] **Step 4: Run to see it pass, then check mise reads it**

Run: `bash bin/lib/test-dotfiles`
Expected: exit 0.

Run, from a scratch home as `test-dotfiles` builds one: `mise -E installed dotfiles status`
Expected: no parse error, and `~/.config/gh/config.yml` listed.

- [ ] **Step 5: Commit**

```bash
git add tilde/.config/mise/config.installed.toml tilde/.config/mise/conf.d/40-dotfiles.toml bin/lib/test-dotfiles
git commit -m "Declare app-written targets as seeded copies for installed copies"
```

---

### Task 6: The install line, its docs and the `stable` branch

**Files:**

- Modify: `README.md`, `docs/installation.md`, `setup/README.md`
- Create: root `mise.toml`, only when probe 11 gave `no-root-toml=error`

**Interfaces:**

- Consumes: `FETCH_ONLY` (Task 1), the `installed` environment (Task 5).
- Produces: the install line, quoted exactly by Tasks 7 and 8:

```bash
mise -E installed bootstrap --from 'https://github.com/jrmatherly/returnofthemac.git?ref=stable' --config-dir tilde/.config/mise --save-env --only final-hook && ~/.local/share/mise/bootstrap-repo/setup.sh
```

with `--only final-hook` replaced by Task 1's `FETCH_ONLY` when that differs.

- [ ] **Step 1: Write the install section**

`README.md` gains "Install without cloning" above the clone instructions. It states, in this order: the two prerequisites (`xcode-select --install`, then mise from https://mise.run); the install line; that `--from` trusts this repository's configuration for the run, with the review link and `--dry-run`; that `~/.config/mise` must be missing or empty, with `mv ~/.config/mise ~/.config/mise.backup` for a Mac that has one; that macOS preferences are not applied (`set-defaults` does that); `rotm update` for later; and that the copy lives in `~/.local/share/mise/bootstrap-repo` and is not for editing. `docs/installation.md` gets the same steps in its numbered form. The clone path stays documented as the way to develop or fork.

- [ ] **Step 2: Write the promotion step**

`setup/README.md` gains "Releasing to `stable`": users follow `stable`; promote with `git push origin <sha>:refs/heads/stable` after the VM install passed on `<sha>`; the push is a plain one, so GitHub refuses anything that is not a fast-forward; never force it.

- [ ] **Step 3: Gate and commit**

Run: `pnpm check`
Expected: exit 0.

```bash
git add README.md docs/installation.md setup/README.md
git commit -m "Document installing returnofthemac without a clone"
git push
```

- [ ] **Step 4: Create `stable`, with the owner's go-ahead**

Ask the owner first: this publishes a branch. Then:

```bash
git push origin HEAD:refs/heads/stable
```

Expected: `* [new branch] HEAD -> stable`. Nobody follows it until the README on `main` names it, which is this same commit.

---

### Task 7: The VM proof

**Files:**

- Create: `docs/superpowers/specs/2026-11-11-installable-probe/p1-evidence.sh` (mode 0755)
- Modify: `tilde/.config/mise/config.installed.toml` (the measured entries)
- Modify: this plan (a `#### Results` section)

**Interfaces:**

- Consumes: the install line (Task 6), `rotm` (Task 3).

`p1-evidence.sh <row>` writes each row's commands and output to `p1-<time>/row-<n>.txt` beside itself, as `run-in-guest.sh` does for the probes. Copy it to `~/vm-proof/p1/`.

- [ ] **Step 1: Write `p1-evidence.sh`, lint it, copy it to the share**

One function per row below, each printing the commands it runs.

- [ ] **Step 2: The owner runs the rows in a disposable guest**

| # | In the guest | Pass |
| --- | --- | --- |
| 1 | `mkdir -p ~/.config/mise && touch ~/.config/mise/config.toml`, then the install line | mise refuses the link, `setup.sh` does not start. Then `rm -rf ~/.config/mise` |
| 2 | `xcode-select --install`, mise's installer, the install line. Answer the prompts as a new owner would | `setup.sh` ends with "All done" or exit 2 with only the tolerated `royal-tsx` miss |
| 3 | `readlink ~/.config/mise ~/dotfiles`, `rotm-mode`, `cat ~/.config/mise/miserc.local.toml` | both links point into `~/.local/share/mise/bootstrap-repo`, `installed`, `env = ["installed"]` |
| 4 | `mise bootstrap status --missing`, `mise bootstrap packages status --json` as in A6 rows 3 to 6 | the same result A6 recorded for a `setup.sh` run |
| 5 | A new terminal, then `command -v rotm`, `rotm settings list \| head -3` | `rotm` resolves under the checkout and the list prints |
| 6 | `git -C ~/dotfiles status --porcelain` | empty |
| 7 | Use the apps: `gh config set editor vim`; open VS Code and change one keybinding and one setting; open and quit `btop`; open Ghostty, cmux and lazygit once. Then row 6's command again | Record every path listed. Each one becomes an entry in `config.installed.toml` on the host |
| 8 | On the host: commit the row 7 entries and a one-line change to `tilde/.config/gh/config.yml`, push, promote to `stable`. In the guest: `rotm update -y` | the checkout's `HEAD` is the new commit, `setup.sh` ran, and `gh config get editor` still prints `vim` |
| 9 | `sysup` | no `claude-config save`, and row 6's command still prints nothing for `agents/` |
| 10 | `dotfiles` | prints the `rotm update` hint and pulls nothing |

- [ ] **Step 3: Record and fix**

Add `#### Results` here: the date, the guest build, the mise version, one line per row. A failure in rows 1 to 6, 8 or 9 is fixed on `main`, promoted, and rerun from a fresh disposable guest. Row 7's findings are data, not failures.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-11-11-installable-probe/p1-evidence.sh tilde/.config/mise/config.installed.toml docs/superpowers/plans/2026-11-11-p1-install-and-update.md
git commit -m "Record the VM proof of the installed path"
git push
```

---

### Task 8: A workflow job for the installed path

**Files:**

- Modify: `.github/workflows/fresh-install.yml`

**Interfaces:**

- Consumes: the install line (Task 6).

- [ ] **Step 1: Turn the job into a matrix**

`strategy.matrix.path: [clone, installed]` with `fail-fast: false`. The steps that differ:

- `actions/checkout` and "Move the runner's own dotfiles aside" stay for both. The checkout is unused on `installed`, and keeping it leaves the later steps identical.
- New step, `if: matrix.path == 'installed'`, "Install mise": `curl -fsSL https://mise.run | sh` and `echo "$HOME/.local/bin" >> "$GITHUB_PATH"`. The existing "Remove Homebrew" step's `if command -v mise; then exit 1; fi` runs before it.
- The `setup.sh` step becomes two steps guarded by `matrix.path`. The `installed` one runs the install line with `?ref=${{ github.ref_name }}` in place of `?ref=stable` and `-y --skip-codegraph -- --skip user` after `setup.sh`, with the same exit-code rule.
- "Disk after setup" sets `MISE_CONFIG_DIR` to `$HOME/.config/mise` for both paths. It is the same folder through the link.
- New final step, `if: matrix.path == 'installed'`: `test "$("$HOME/dotfiles/bin/lib/rotm-mode")" = installed` and `test -z "$(git -C "$HOME/dotfiles" status --porcelain)"`.

- [ ] **Step 2: Lint and commit**

Run: `actionlint .github/workflows/fresh-install.yml`
Expected: no output.

```bash
git add .github/workflows/fresh-install.yml
git commit -m "Run fresh-install for the installed path too"
git push
```

Running the workflow is the owner's call: it takes up to four hours of a hosted runner.

---

### Task 9: Close the phase

**Files:**

- Modify: `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`
- Modify: `CLAUDE.md`, `setup/README.md` where a stated fact became false

- [ ] **Step 1: Update the spec**

In Distribution: the chosen shape is config-dir, the install is mise to fetch and link followed by `setup.sh`, and `~/dotfiles` is kept in installed mode (replace the sentence that says it is dropped, and the matching Risks bullet). Add probes 11 to 13 to "Verified facts". In the P1 brief, replace "Waiting on" and "Decided" with one "Shipped" line naming this plan. In "Plans", add this file.

- [ ] **Step 2: Check the instruction files**

Run: `grep -n 'setup.sh\|~/dotfiles' CLAUDE.md .claude/rules/setup.md .claude/rules/symlinks.md`
Fix only a sentence that is now false. `~/dotfiles` "must be a symlink to the clone" becomes "to the clone or, on an installed copy, to mise's checkout".

- [ ] **Step 3: Move the plan and commit**

```bash
git mv docs/superpowers/plans/2026-11-11-p1-install-and-update.md docs/superpowers/plans/completed/
git add -A docs/superpowers CLAUDE.md .claude/rules setup/README.md
git commit -m "Complete P1: install and update without a clone"
git push
```

Then ask the owner to review before P2 is written.
