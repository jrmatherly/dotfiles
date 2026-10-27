# Setup Robustness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `setup.sh` finish the whole run on a flaky network or a headless terminal, never lose a user's file to a repeated backup, and hold sudo only around the steps that need it.

**Architecture:** Each fix lands in the setup script that owns the step, following the file's existing tolerance pattern (`brew.sh:38-44`: report and carry on, never abort before `symlinks.sh`). Pure functions in `setup/symlinks.sh` and `firefox/lib/get-firefox-dev-path` get a `setup/tests/*.sh` test in the `codex-config.sh` style (functions extracted with `sed -nE`, run under a scratch `HOME`), and `bin/lib/check` runs them. Conventions that a lint can hold (guarded `tput`) go to `bin/lib/test-conventions`. Everything else is verified by the `/validate-setup` cycle at the end, which is how this repo verifies setup changes.

**Tech Stack:** bash 3.2 (`/bin/bash`), shellcheck, the `setup/tests` harness pattern, `/validate-setup`.

**Spec:** `docs/superpowers/specs/2026-10-27-repo-audit-assessment.md`, section B (B1 to B14) and A11.

## Global Constraints

- Setup scripts keep `set -euo pipefail`; a step that may fail for environmental reasons ends in `|| warning "… — re-run: <command>"` so the run continues. A closed stdin means skip, never abort or overwrite (`.claude/rules/setup.md`).
- `brew.sh` runs first; every later script guards Homebrew tools with `command_exists`.
- Every behavior change edits `setup/README.md`'s section for that script in the same commit (`README.md` too when a flag changes); the commit-gate hook reminds you when a setup file changes without a README.
- Fresh-install paths (no Homebrew, no node_modules) cannot be verified on this machine; say so in the commit when a change touches them.
- Each task is one commit; `pnpm check` must pass before it. Commit subjects are short, imperative, sentence case; each ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` (omitted below).
- No em-dash characters in new prose or comments.

## Review Focus

1. A second run after a partial first run: every backup, link and guard must be idempotent (Task 1's test runs the backup twice; Tasks 5 and 6 re-check `-L` targets).
2. A run with `TERM` unset (SSH without a terminal, a CI-like shell): no script may abort on `tput` (Task 3's lint).
3. A run where `mise install` fails for one tool: `symlinks.sh` must still run and the summary must name the re-run command (Task 2; verified by the log in Task 11).
4. A cancelled Xcode CLT dialog: the run must not hang (Task 4's bounded wait).
5. The sudo credential during `curl | bash` and npm installs: the keep-alive must be stopped before `misc.sh` and restarted before `symlinks.sh` (Task 9; verified by the log's "Sudo released"/"Sudo reactivated" lines in Task 11).

---

### Task 1: Backups never overwrite an earlier backup (B1)

**Files:**
- Modify: `setup/symlinks.sh:156-159` (`handle_existing_file`, the backup branch)
- Create: `setup/tests/symlinks-backup.sh`
- Modify: `bin/lib/check` (run the new test next to `setup/tests/codex-config.sh`)
- Modify: `setup/README.md` (the `symlinks` section's prompt description)

**Interfaces:**
- Produces: `backup_path <dst>` in `setup/symlinks.sh`, printing `<dst>.backup` when free, else `<dst>.backup.<YYYYmmdd-HHMMSS>`, and `<dst>.backup.<stamp>.<n>` if that exists too. `handle_existing_file` moves to `$(backup_path "$dst")`.

- [x] **Step 1: Write the failing test**

`setup/tests/symlinks-backup.sh` extracts `indent tildify info user success skipped fail warn backup_path handle_existing_file symlink_file` with the `sed -nE` idiom from `setup/tests/codex-config.sh:10`, sets `HOME=$(mktemp -d)`, and checks:

```bash
echo first > "$HOME/f"; echo second > "$HOME/f"
printf b | symlink_file "$src" "$HOME/f" > /dev/null 2>&1   # first backup
echo third > "$HOME/f"
printf b | symlink_file "$src" "$HOME/f" > /dev/null 2>&1   # second backup
check "first backup kept" "[ \"\$(cat '$HOME/f.backup')\" = second ]"
check "second backup has its own name" "ls '$HOME'/f.backup.* | grep -q ."
mkdir "$HOME/d"; mkdir "$HOME/d.backup"
printf b | symlink_file "$srcdir" "$HOME/d" > /dev/null 2>&1
check "directory backup not nested" "[ ! -e '$HOME/d.backup/d' ]"
```

End with `exit $fails` like `codex-config.sh`.

- [x] **Step 2: Run it and watch it fail**

Run: `bash setup/tests/symlinks-backup.sh`
Expected: `FAIL first backup kept` (the file now holds `third`) and `FAIL directory backup not nested`.

- [x] **Step 3: Add `backup_path` and use it**

Place `backup_path()` above `handle_existing_file`; replace `mv "$dst" "${dst}.backup"` and the success line with the computed path.

- [x] **Step 4: Run the test and the gate**

Run: `bash setup/tests/symlinks-backup.sh && pnpm check`
Expected: all `ok`, gate exit 0 (after adding `bash setup/tests/symlinks-backup.sh > /dev/null` to `bin/lib/check`).

- [x] **Step 5: Commit**

```bash
git add setup/symlinks.sh setup/tests/symlinks-backup.sh bin/lib/check setup/README.md CLAUDE.md
git commit -m "Never overwrite an earlier backup when linking"
```

### Task 2: One failed install no longer aborts setup (B2, B3)

**Files:**
- Modify: `setup/misc.sh:131,134` (`mise install`), `:436,438` (`dotnet tool`), `:491` (`pnpm install`)
- Modify: `setup/brew.sh:28` (`brew update`)
- Modify: `setup/README.md` (`brew` and `misc` sections: what is tolerated and the re-run command)

- [x] **Step 1: Add `|| warning` to each bare step**

`mise install | indent || warning "mise install had failures — re-run: mise install"` (both branches; keep `mise reshim` after the `--skip-codegraph` branch), `brew update || warn "brew update failed — re-run: brew update"` (add a `warn` helper to `brew.sh` if it has none; `title` is the only helper there today), `dotnet tool update/install … | indent || warning "PowerShell install failed — re-run: dotnet tool install --global PowerShell"`, `pnpm install --dir "$DOTFILES_DIR" | indent || warning "pnpm install failed — re-run: pnpm install"`.

- [x] **Step 2: Prove the shape with a stub**

Run: `tmp=$(mktemp -d); printf '#!/bin/bash\nexit 1\n' > $tmp/mise; chmod +x $tmp/mise; PATH=$tmp:$PATH bash -c 'set -euo pipefail; warning(){ echo "WARN: $1"; }; indent(){ cat; }; mise install | indent || warning "mise install had failures"; echo continued'`
Expected: `WARN: mise install had failures` then `continued`.

- [x] **Step 3: Run the gate and commit**

Run: `pnpm check`

```bash
git add setup/misc.sh setup/brew.sh setup/README.md
git commit -m "Carry on when mise, brew update, dotnet or pnpm fail"
```

### Task 3: Guarded `tput` in every setup script (B4)

**Files:**
- Modify: `setup/brew.sh:8-9`, `setup/zsh.sh:16-22`, `setup/misc.sh:13-15`
- Modify: `bin/lib/test-conventions`

- [ ] **Step 1: Add the failing lint**

```bash
for file in setup/brew.sh setup/zsh.sh setup/misc.sh; do
  grep -nE '\$\(tput [a-z0-9 ]+\)' "$file" | grep -v '|| true' && fail "unguarded tput: $file"
done
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash bin/lib/test-conventions`
Expected: `FAIL: unguarded tput: setup/brew.sh`.

- [ ] **Step 3: Guard every call**

Use `dash.sh:25`'s form, `$(tput bold 2> /dev/null || true)`, for each assignment, and `tput setaf 1 2> /dev/null || true` for the bare calls inside `zsh.sh`'s `warning()`.

- [ ] **Step 4: Prove it**

Run: `env -u TERM bash -c 'set -euo pipefail; b=$(tput bold 2> /dev/null || true); echo survived'` and `bash bin/lib/test-conventions`
Expected: `survived`; the lint passes.

- [ ] **Step 5: Commit**

```bash
git add setup/brew.sh setup/zsh.sh setup/misc.sh bin/lib/test-conventions
git commit -m "Guard tput in the setup scripts"
```

### Task 4: Xcode CLT install that cannot hang (B5)

**Files:**
- Modify: `setup/misc.sh:42-49`
- Modify: `setup/README.md` (`misc` section, the CLT bullet)

- [ ] **Step 1: Rewrite the block**

When `xcode-select -p` fails: if `[ ! -t 0 ]`, print `Xcode Command Line Tools missing; run: xcode-select --install` through `indent` and skip. Else run `xcode-select --install > /dev/null 2>&1 || true`, then wait at most 30 minutes (`for i in $(seq 1 360); do xcode-select -p && break; sleep 5; done`), and if still missing, `warning "Xcode Command Line Tools not installed — later steps may fail; run: xcode-select --install"` and continue.

- [ ] **Step 2: Prove the headless branch**

Run: `bash -c 'if [ ! -t 0 ]; then echo headless-skip; fi' < /dev/null`
Expected: `headless-skip`. (The install dialog itself cannot be exercised on this machine; CLT is installed.)

- [ ] **Step 3: Run the gate and commit**

Run: `pnpm check`

```bash
git add setup/misc.sh setup/README.md
git commit -m "Bound the Xcode CLT wait and skip it headless"
```

### Task 5: Missing npm skips only the npm steps (B7)

**Files:**
- Modify: `setup/misc.sh:461-491`
- Modify: `setup/README.md` (`misc` section, order note)

- [ ] **Step 1: Replace `exit 0` with an `if command_exists npm; then … fi` around the npm config and the pnpm install**, so the Claude restore and catalog at `:503-511` run either way. Keep the comment that the restore must come after the npm settings.

- [ ] **Step 2: Run the gate and commit**

Run: `pnpm check`

```bash
git add setup/misc.sh setup/README.md
git commit -m "Restore Claude Code config even without npm"
```

### Task 6: `ln -sfn` only replaces our own links (B8)

**Files:**
- Modify: `setup/misc.sh:93-94,116-117`

- [ ] **Step 1: Add the failing test to `setup/tests/symlinks-backup.sh`** (same harness): a helper `link_config_dir <name>` extracted from `misc.sh` that, given `$HOME/.config/<name>` as a symlink to `$tmp/elsewhere`, leaves it untouched and warns; given none, creates the link; given a link into `$DOTFILES_DIR`, relinks.

- [ ] **Step 2: Extract the duplicated block into `link_config_dir()`** in `misc.sh` (used for `gh` and `mise`) with that rule, warning text: `~/.config/<name> links elsewhere — leaving it; symlinks.sh will ask`.

- [ ] **Step 3: Run the test and the gate, then commit**

Run: `bash setup/tests/symlinks-backup.sh && pnpm check`

```bash
git add setup/misc.sh setup/tests/symlinks-backup.sh
git commit -m "Only relink config dirs that already point at the repo"
```

### Task 7: Firefox files go through the prompt, and the profiles.ini fallback works (B9, B11)

**Files:**
- Modify: `setup/symlinks.sh:398-399`
- Modify: `firefox/lib/get-firefox-dev-path:20-26`
- Create: `setup/tests/firefox-dev-path.sh`
- Modify: `bin/lib/check`, `firefox/README.md` (if it describes the hard links)

- [ ] **Step 1: Write the failing test**

`setup/tests/firefox-dev-path.sh`: under `HOME=$(mktemp -d)`, create `$HOME/Library/Application Support/Firefox/profiles.ini` with a `[Profile0]` block `Name=dev-edition-default`, `IsRelative=1`, `Path=Profiles/abc.dev-edition-default`, and the directory `…/Firefox/Profiles/abc.dev-edition-default`; also a second case with `IsRelative=0` and an absolute `Path`.

```bash
check "relative Path resolves" "[ \"\$(firefox/lib/get-firefox-dev-path)\" = \"$HOME/Library/Application Support/Firefox/Profiles/abc.dev-edition-default\" ]"
```

(Name the profile dir without `dev-edition` in the first `find` branch's pattern, e.g. `abc.custom`, so the fallback is what resolves it.)

- [ ] **Step 2: Run it and watch it fail**

Run: `bash setup/tests/firefox-dev-path.sh`
Expected: `FAIL relative Path resolves` (today's result is `…/Profiles/Profiles/abc.custom`).

- [ ] **Step 3: Fix the join**

Read `IsRelative` next to `Path`; relative paths join `$firefox_app_support_dir/$profile_path`, absolute ones are used as is.

- [ ] **Step 4: Route the two CSS files through `symlink_file … true`** at `symlinks.sh:398-399`, like `user.js` at `:396`.

- [ ] **Step 5: Run the test and the gate, then commit**

Run: `bash setup/tests/firefox-dev-path.sh && pnpm check`

```bash
git add setup/symlinks.sh firefox/lib/get-firefox-dev-path setup/tests/firefox-dev-path.sh bin/lib/check firefox/README.md CLAUDE.md
git commit -m "Prompt before replacing Firefox CSS and fix the profiles.ini fallback"
```

### Task 8: `symlinks.sh` sees Homebrew, and children skip the redundant sudo prompt (B10, B13)

**Files:**
- Modify: `setup/symlinks.sh:5` (add the guarded `brew shellenv` eval from `misc.sh:9-11`)
- Modify: `setup.sh:150-166`, `setup/zsh.sh:38-40`, `setup/misc.sh:36-39`

- [ ] **Step 1: Export `DOTFILES_SUDO_KEPT=1` in `setup.sh` after `sudo -v`**, and in `zsh.sh` and `misc.sh` wrap the `warning "Activate sudo"` and `sudo echo` in `if [ -z "${DOTFILES_SUDO_KEPT:-}" ]`.

- [ ] **Step 2: Prove the skip**

Run: `DOTFILES_SUDO_KEPT=1 bash -c '[ -z "${DOTFILES_SUDO_KEPT:-}" ] && echo would-prompt || echo skipped'`
Expected: `skipped`.

- [ ] **Step 3: Run the gate and commit**

Run: `pnpm check`

```bash
git add setup/symlinks.sh setup.sh setup/zsh.sh setup/misc.sh setup/README.md
git commit -m "Put Homebrew on symlinks.sh's PATH and prompt for sudo once"
```

### Task 9: Hold sudo only around the steps that use it (A11)

**Files:**
- Modify: `setup.sh:148-166,175-195`
- Modify: `setup/README.md` (`setup.sh` section: when sudo is held)

The steps that call `sudo`: Touch ID (`setup.sh:145`), `brew.sh` (cask installers), `zsh.sh:47` (`/etc/shells`), `symlinks.sh:95,345` (`/usr/local/bin`), `macos.sh` (its own keep-alive). `misc.sh` needs none once Task 8 lands, and it is the script that runs `curl | bash` and the npm, uv and dotnet installs.

- [ ] **Step 1: Turn the keep-alive into `sudo_keepalive_start` and `sudo_keepalive_stop` functions** in `setup.sh` (start sets `SUDO_KEEPALIVE_PID` and the trap; stop kills it and prints `Sudo released` through `info`). Call stop before `misc.sh` and start again (printing `Sudo reactivated`) before `symlinks.sh`.

- [ ] **Step 2: Prove the pair**

Run: `bash -c 'f(){ while true; do sleep 60; done & P=$!; }; f; kill -0 $P && echo running; kill $P; sleep 0.1; kill -0 $P 2>/dev/null || echo stopped'`
Expected: `running` then `stopped`.

- [ ] **Step 3: Run the gate and commit**

Run: `pnpm check`

```bash
git add setup.sh setup/README.md README.md
git commit -m "Release sudo before the installers that do not need it"
```

### Task 10: Settle the sandboxed and stale macOS defaults (B6, B12)

**Files:**
- Modify: `setup/macos.sh:108,239,497-504,528,542-548` (only the lines the checks below prove dead)
- Modify: `setup/README.md` (`macos` section) and `README.md`'s macOS paragraph

These are checks the owner runs; each decides one block.

- [ ] **Step 1: TextEdit.** Run the three `defaults write com.apple.TextEdit …` lines, quit and reopen TextEdit, `File > New`. Plain text with no ruler means honoured (keep); a rich-text document means dead (delete the block and the `TextEdit plain text` line in `setup/README.md`).
- [ ] **Step 2: Preview.** `defaults write com.apple.Preview ApplePersistenceIgnoreState YES`, open two PDFs, quit, reopen one. Only that one open means honoured.
- [ ] **Step 3: QuickTime.** Write the key, open a video. Auto-play means honoured.
- [ ] **Step 4: helpviewer (`:108`).** Open any app's Help window; a floating window that stays above others means honoured.
- [ ] **Step 5: Quick Look text selection (`:239`).** Quick Look a text file, try to select text. No selection means dead; delete the line.
- [ ] **Step 6: Messages (`:542-548`).** Type `"hi"` in Messages; straight quotes mean honoured, curly means dead; delete the dead keys.
- [ ] **Step 7: Commit** the deletions and README edits: `git commit -m "Drop macOS defaults the sandboxed apps ignore"`.

### Task 11: Validate the whole program on this Mac (B14 included)

- [ ] **Step 1: `/validate-setup before`** (runs `pnpm check`, snapshots).
- [ ] **Step 2: Run `./setup.sh --skip-brew` in your own terminal**, answering `b` once to a prompt you can afford to back up twice (then re-run for the second backup) so Task 1 is exercised live.
- [ ] **Step 3: `/validate-setup after`.** In the log, confirm `Sudo released` precedes the Claude Code and npm steps and `Sudo reactivated` precedes the symlinks step, no `/!\` line names an abort, and `npm config get min-release-age` prints `7` afterwards (B14; if it does not, the rewriter is something else, `ls -l ~/.npmrc` for the mtime and `grep -rl npmrc ~/Library/LaunchAgents` would be the next check).
- [ ] **Step 4:** Fix anything the diff or log shows, one commit per fix, then push.

---

## Self-review notes

- Spec coverage: B1 Task 1, B2 and B3 Task 2, B4 Task 3, B5 Task 4, B6 and B12 Task 10, B7 Task 5, B8 Task 6, B9 and B11 Task 7, B10 and B13 Task 8, B14 Task 11, A11 Task 9.
- Tasks 2, 4, 5, 8 and 9 have no unit test because the scripts they change are not sourceable without side effects; Task 11 is their verification, with the log lines named.
- Review Focus items map to Tasks 1 and 6, 3, 2 and 11, 4, 9 and 11.
