# P3: Sign In and Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** What a user changes through `rotm settings`, and what they opt out of, is saved to a private GitHub repository in their own account and loads onto their next Mac before anything is installed there.

**Architecture:** A user's choices move out of mise's checkout into one real folder, `~/.config/rotm`, and the config dir links to them. mise's own override file holds every setting mise can hold (the env settings, the macOS preferences, and the single-package opt-outs, which the docs move there from `config.local.toml` so they travel), `modules-off.local` holds the module switches, and `tools.toml` holds the values of the agent-tool settings, which mise cannot hold. mise's history tracks that folder through one entry written in `config.local.toml`, and a private repository is its origin. `rotm settings sync on|off|now|status` is the only new surface.

**Tech Stack:** bash 3.2 (`#!/bin/bash`), mise 2026.11.5 or newer (`mise dot`, `mise bootstrap --adopt`, `mise set --override`, `mise set --file`), Python 3.11+ standard library (the settings package), `gh`, git.

**Spec:** `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`. Read the Goal and "Decisions the owner made" in full first, then "Sync and sign-in", the last rows of "Verified facts" and the P3 brief. Decisions 2, 3, 8, 13, 14 and 15 bind every task here.

## Global Constraints

- macOS only (decision 4). mise floor: 2026.11.5 (`setup/mise-floor.sh`). Every measurement below ran on 2026.11.5.
- The store is a private GitHub repository in the user's own account (decision 2). Nothing else is built to hold settings.
- Sync is manual (decision 8). Every `mise dot origin set` passes `--sync manual`. No `[bootstrap.services.mise-history]`, no LaunchAgent.
- Scope is every setting `rotm settings` can change, and the opt-outs (decision 13). Where mise can hold a setting, mise holds it; `tools.toml` is only for the ones it cannot (decision 14).
- Nothing leaves the base (decisions 3 and 12). No task here removes a package, a default or an owner-pointing value.
- A development clone keeps the owner's workflow: there a macOS preference or a jstack role is still an edit to a tracked file that the owner commits. Tasks 3 and 4 change installed copies only.
- An installed copy stays fast-forwardable: no command writes a tracked file of the checkout. `mise dot track` is never called, because it writes its entry into `config.toml`. The track entry is written into `config.local.toml` by our code.
- Restoring uses `mise bootstrap --adopt <url> --only final-hook`, always with that flag. Without it mise runs a full bootstrap of the base, macOS preferences included.
- `*.local.toml` never travels (mise's rule). Anything a second Mac needs is either in `~/.config/rotm` or written again by our code on that Mac.
- The owner's Mac is a clone and `~/.config/mise` is a link into it. Never run `./setup.sh`, `sysup`, `rotm install`, `rotm update`, `rotm settings sync on` or `mise bootstrap` against the real home. Real sync against GitHub is Task 9, in the VM, when the owner schedules it (decision 15).
- Testing rule: self-checks use stubs and scratch homes, with `HOME` and every `MISE_*_DIR` pointed at the scratch folder and every mise call run from the scratch home.
- The self-checks have their own helpers (`run`, `prepare`, `check_true`, `has`, `lacks`, `stub`, `$STATE`, `$fix`; `raises` in the Python tests). Where a block here and the file disagree on a helper, the file wins and the assertion stays.
- A new self-check is one `job quiet bash <path>` line in `bin/lib/check`, and a new stdlib Python test one entry in `settings_tests` there.
- `pnpm check` runs before every commit (about 40 seconds). Edit and commit in separate Bash calls. One commit per task.
- Docs mirror behaviour: a change to setup or settings behaviour has its `README.md`, `setup/README.md`, `settings/README.md` or `docs/` edit in the same commit. A docs page is never named after a command (`help <name>` reads `docs/<name>.md` first), so the new page is `docs/settings-sync.md`.

## Measured while writing this plan

On 2026-11-12, mise 2026.11.5, scratch homes on the owner's Mac shaped like installed copies (`~/.config/mise` a link into a checkout under the data dir), a local bare repository as the origin. Status, save, sync, pull and adopt calls only. The spec's "Verified facts" holds the first five rows.

| Claim | Measured |
| --- | --- |
| mise's sync saves `config.override.toml` and `modules-off.local` where P1 and P2 put them | No. Left out as "mise internal directory", because the config dir resolves into the data dir |
| `mise dot track` keeps the checkout clean | No. It wrote its entry into `config.toml` |
| A `mode = "track"` entry written by hand in `config.local.toml` is honoured | Yes, and the checkout stayed clean |
| `config.override.toml` can be a link to a real file outside the checkout | Yes. mise read through it, and `mise set --override` and `mise unset --override` both exited 0, wrote the real file, kept the link and kept the file's other tables |
| A folder outside the checkout syncs between two installed copies | Yes, in both directions, with `mise dot sync` then `mise dot pull` |
| The override file can hold more than `[env]` | Yes. A `[bootstrap.macos.defaults."<domain>"]` key in it replaced the same key from `conf.d/20-macos.toml` in `mise bootstrap macos defaults status --json` and left that domain's other keys alone. A `"brew:<name>" = { state = "absent" }` in its `[bootstrap.packages]` made `packages status` report the package `absent`. An `[env]` key in it beat the same key from `conf.d` |
| `mise bootstrap --adopt <origin>` only restores files | No. It then ran a full bootstrap and applied a `[dotfiles]` entry of the base. With `--only final-hook` it restored the files and applied nothing |
| An adopted home keeps the first Mac's manual mode | No. It starts in mode `sync`; `mise dot origin set <origin> --sync manual` afterwards is accepted (probe 6) |

Not measured, and settled by the task named: `[settings] disable_tools` in the override file (not used by this plan), a real private GitHub repository (Task 9), and whether `config.rotm-installed.toml` can turn one file of a `symlink-each` folder into a seeded copy (Task 4, Step 1).

## File Structure

| File | Responsibility |
| --- | --- |
| `bin/lib/rotm-user-layer` (new) | Owns `~/.config/rotm`: prints its path, and moves the user's files into it and links them from the config dir |
| `bin/lib/rotm-modules` | Unchanged contract. Writes `modules-off.local` through a link instead of replacing the link |
| `settings/src/dotfiles_settings/sync.py` (new) | The four sync commands, the track entry, the tool-value capture and replay, the secrets guard |
| `settings/src/dotfiles_settings/cli.py` | The `sync` subcommand, nothing else |
| `settings/src/dotfiles_settings/adapters/env.py` | Machine-scoped settings go to `config.local.toml` |
| `settings/src/dotfiles_settings/adapters/macos_default.py` | On an installed copy, writes the user's override file instead of refusing |
| `settings/registry.toml`, `registry.py`, `model.py` | One new optional field, `scope` |
| `tilde/.config/mise/config.rotm-installed.toml` | `jstack-models.md` becomes a seeded copy on an installed copy |
| `setup.sh` | Calls `rotm-user-layer ensure`, and offers to load saved settings after the GitHub login |
| `bin/lib/test-user-layer`, `bin/lib/test-sync`, `settings/tests/test_sync.py` (new) | Self-checks |
| `docs/settings-sync.md` (new), `docs/forking.md`, `README.md`, `settings/README.md`, `setup/README.md` | Docs |

## Review Focus

1. **Both places hold a file and they differ.** A Mac has `~/.config/rotm/config.override.toml` from an adopt and a different real `config.override.toml` in the config dir. Expected: `rotm-user-layer ensure` exits 1, names both paths and changes neither. Pinned in Task 1.
2. **The named repository exists and is not a settings repository.** `rotm-settings` already holds something else. Expected: `sync on` refuses before any push and names the `--repo` flag. Pinned in Task 6.
3. **A secret is in the folder.** The user once ran `mise set --override GITHUB_TOKEN=…`. Expected: `sync on` and `sync now` stop before the first save and name the key, because history keeps a secret forever. Pinned in Task 6.
4. **A second Mac changed a setting before it was connected.** Expected: mise pauses, neither side is overwritten, and `sync on` and `sync now` exit 1 and print the conflicting files instead of "done". Pinned in Tasks 6 and 7.
5. **A module arrives switched off from another Mac.** Expected: `sync now` rewrites mise's ignore line and says that nothing was uninstalled and what `rotm install` will do. Pinned in Task 6.

---

### Task 1: The user's folder and its links

**Files:**
- Create: `bin/lib/rotm-user-layer`, `bin/lib/test-user-layer`
- Modify: `bin/lib/rotm-modules` (the function that replaces a config-dir file through a temp file), `setup.sh` (before the `"$modules" sync` call near line 247), `bin/sysup` (beside its `rotm-modules sync` call), `bin/lib/check`

**Interfaces:**
- Produces: `rotm-user-layer dir` prints `${ROTM_USER_DIR:-$HOME/.config/rotm}`. `rotm-user-layer ensure` exits 0 when, for each of `config.override.toml` and `modules-off.local`, the config dir (`${MISE_CONFIG_DIR:-$HOME/.config/mise}`) holds a link to the file of the same name in that folder. It exits 1, changing nothing, when both a real config-dir file and a folder file exist and differ. Callers run it by path.

- [ ] **Step 1: Write the failing test** `bin/lib/test-user-layer`, a scratch `HOME` and `MISE_CONFIG_DIR`, with these cases and assertions:

```bash
# 1. nothing anywhere: ensure creates the folder 0700 and two links; the folder holds no files
# 2. a real config.override.toml in the config dir: its bytes are now in the folder and the config-dir path is a link to it
# 3. run again: exit 0, nothing changes (compare `ls -l` and checksums before and after)
# 4. the folder has the file, the config dir has none (a restored Mac): only the link is made
# 5. both real and identical: the config-dir copy becomes the link
# 6. both real and different: exit 1, stderr names both paths, both files unchanged
# 7. `rotm-modules set fonts off` after ensure: modules-off.local in the config dir is still a link, and the folder's file lists fonts
# 8. `rotm-user-layer dir` with ROTM_USER_DIR set prints it
```

- [ ] **Step 2: Run it.** `bash bin/lib/test-user-layer`. Expected: fails, `rotm-user-layer` not found.
- [ ] **Step 3: Write `bin/lib/rotm-user-layer`** with the standard header, `set -euo pipefail`, and the two commands above. A link whose target is missing is not created for `modules-off.local` being absent: `ensure` links both names always, so a later write through the link creates the file in the folder.
- [ ] **Step 4: Make `rotm-modules` write through a link.** Its replace function resolves the path first (`readlink`, one level, as `settings/.../tool.py:edit_file` does with `resolve`) and renames the temp file onto the target, so the link survives.
- [ ] **Step 5: Call `"$DOTFILES_DIR/bin/lib/rotm-user-layer" ensure || exit $?` in `setup.sh`** directly before the module sync, in both modes, skipped under `--dry-run`. Call it in `sysup` before its module sync, reported as a `fail` status line when it exits 1.
- [ ] **Step 6: Add `job quiet bash bin/lib/test-user-layer` to `bin/lib/check`**, run `pnpm check`. Expected: passes, including `test-modules`, `test-bootstrap` and `test-sysup` unchanged.
- [ ] **Step 7: Docs and commit.** `setup/README.md` gains the step, `docs/local-customizations.md` names the folder. Commit: "Keep a user's settings in a folder of their own".

### Task 2: Settings that describe one Mac stay on it

**Files:**
- Modify: `settings/src/dotfiles_settings/model.py`, `registry.py`, `adapters/env.py`, `settings/registry.toml`
- Test: `settings/tests/test_registry.py`, `settings/tests/test_env.py`

**Interfaces:**
- Produces: `Setting.scope: str = "user"`, the other accepted value is `"machine"`. `registry.load` rejects anything else. Tasks 5 and 6 skip `scope == "machine"` settings.

- [ ] **Step 1: Failing tests.** In `test_registry.py`: `macos.computer_name`, `macos.local_hostname` and `hindsight.paths` load with `scope == "machine"`, every other setting with `"user"`, and a fixture entry with `scope = "everyone"` raises. In `test_env.py`, against the stub mise: writing `macos.computer_name` calls `set --file <config_dir>/config.local.toml DOTFILES_MACOS_COMPUTER_NAME=<value>` and never `--override`; reading it returns `Source.OVERRIDE` from that file; `reset` calls `unset --file <same path>`; a value left in the override file from before this change is read, and the next write removes it there with `unset --override`.
- [ ] **Step 2: Run both.** Expected: fail on the unknown field.
- [ ] **Step 3: Implement.** `scope` in `Setting` and in the registry's accepted keys. In `EnvAdapter`, `local_path() -> Path` is `mise.config_dir() / "config.local.toml"`, and `read`, `write` and `reset` pick the file by `s.scope`.
- [ ] **Step 4: Mark the three settings** in `settings/registry.toml` with `scope = "machine"`.
- [ ] **Step 5: Run the tests and `pnpm check`,** then commit: "Keep a Mac's own name and paths out of synced settings". `settings/README.md` documents the field in the same commit.

### Task 3: macOS preferences on an installed copy

**Files:**
- Modify: `settings/src/dotfiles_settings/adapters/macos_default.py`
- Test: `settings/tests/test_macos_default.py` (the block at "An installed copy", lines 244 to 251, is replaced)

**Interfaces:**
- Consumes: `env.override_path()`.
- Produces: no new names. `MacosDefaultAdapter.write`, `reset` and `read` change behaviour only when `fragment_path()` is inside mise's checkout.

- [ ] **Step 1: Replace the two `raises(..., "installed copy")` assertions** with: on an installed copy, `write(dock, "44")` leaves `20-macos.toml` byte-identical and puts `tilesize = 44` under `[bootstrap.macos.defaults."com.apple.dock"]` in the override file; a second key of the same domain joins that table; `[env]` already in the override file is kept; `read` then reports `Source.OVERRIDE` with the fragment's value as `seed`; `reset` removes the key from the override file and leaves the fragment alone; the clone-mode assertions above the block still pass unchanged.
- [ ] **Step 2: Run.** `python3 settings/tests/test_macos_default.py`. Expected: fails with the "installed copy" `SettingsError`.
- [ ] **Step 3: Implement.** `set_key`, `remove_key` and `declared` already edit and read a `[bootstrap.macos.defaults.<domain>]` table in any TOML text, so `write` and `reset` choose the target file (the fragment in a clone, the override file on an installed copy) and reuse them. `read` decides `OVERRIDE` from the override file first. The one-key `defaults write` and the restart stay as they are. `write_note` becomes a method that names the file that was edited.
- [ ] **Step 4: Run the test and `pnpm check`,** then commit: "Let an installed copy change a macOS preference". `settings/README.md` and `docs/installation.md` lose the sentence that says it cannot.

### Task 4: jstack roles on an installed copy

**Files:**
- Modify: `tilde/.config/mise/config.rotm-installed.toml`, `tilde/.config/mise/conf.d/40-dotfiles.toml` (comment only, if the entry needs a counterpart note), `bin/lib/test-dotfiles`

- [ ] **Step 1: Measure first, in a scratch home.** With `40-dotfiles.toml`'s `"~/.claude/rules"` `symlink-each` entry and the `rotm-installed` environment selected, does a redeclared `"~/.claude/rules"` with `exclude = [".DS_Store", "jstack-models.md"]` plus `"~/.claude/rules/jstack-models.md" = { source = "~/dotfiles/tilde/.claude/rules/jstack-models.md", mode = "copy", create_if_missing = true }` leave every other rule a link and that one a real file, on a first apply and on a second? Record the answer in this plan's table and in the spec's "Verified facts". If mise refuses the pair, stop and report: the fallback is the owner's call.
- [ ] **Step 2: Failing assertion in `bin/lib/test-dotfiles`,** in its installed-environment section: after apply, `~/.claude/rules/jstack-models.md` is a regular file with the tracked file's content, `~/.claude/rules/verify-first.md` is a link, and an edit to the regular file survives a second apply.
- [ ] **Step 3: Add the two entries** to `config.rotm-installed.toml`, with a one-line why.
- [ ] **Step 4: Run `bash bin/lib/test-dotfiles` and `python3 settings/tests/test_tool.py`.** The second needs no change: `edit_file` refuses only a path inside the checkout, and the file no longer is one.
- [ ] **Step 5: `pnpm check`, commit:** "Seed the jstack roles file on an installed copy".

### Task 5: Carry the settings mise cannot hold

**Files:**
- Create: `settings/src/dotfiles_settings/sync.py`, `settings/tests/test_sync.py`
- Modify: `bin/lib/check` (`settings_tests`)

**Interfaces:**
- Produces, all in `sync.py`:
  - `user_dir() -> Path`: `ROTM_USER_DIR` or `~/.config/rotm`.
  - `tools_path() -> Path`: `user_dir() / "tools.toml"`.
  - `capture(settings: list[Setting], adapters: dict[str, Adapter]) -> dict[str, str]`: for every setting with `kind == "tool"`, `access == "rw"` and `scope == "user"` whose `read` returns `Source.OVERRIDE`, its id and value. Writes them as one `[tools]` table, keys sorted, and returns them. With none it writes an empty table.
  - `replay(settings, adapters) -> list[str]`: for each id in `tools.toml` whose current value differs, calls that adapter's `write` and returns one line per change. An id the registry no longer has is skipped and named in a returned line. A write that raises `SettingsError` becomes a returned line and the rest continue.

- [ ] **Step 1: Failing test** `test_sync.py`, with fake adapters in a temp `ROTM_USER_DIR`:

```python
# capture: an OVERRIDE tool value is written; a SEED one, an ro one, a machine-scoped one and an env one are not
# capture twice with no change: the file's bytes are identical
# a multi-line value (hindsight-style) and a value with a double quote round-trip through tomllib
# replay: only the differing id is written; an unknown id yields "skipped <id>: not a setting here"
# replay: one adapter raising SettingsError yields a line with its message and the next id is still written
```

- [ ] **Step 2: Run.** Expected: `ModuleNotFoundError: dotfiles_settings.sync`.
- [ ] **Step 3: Implement** the four functions. Values are written with `json.dumps`, which is valid TOML for a basic string.
- [ ] **Step 4: Add the test to `settings_tests`,** run `pnpm check`, commit: "Record and replay the tool settings mise cannot hold".

### Task 6: `rotm settings sync`

**Files:**
- Modify: `settings/src/dotfiles_settings/sync.py`, `cli.py`, `mise.py` (nothing new unless a helper is shared)
- Test: `settings/tests/test_sync.py`, `settings/tests/test_cli.py`

**Interfaces:**
- Consumes: Task 1's `rotm-user-layer ensure` (run through `tool.run`), Task 5's `capture` and `replay`, `ADAPTERS["module"]`'s helper (`rotm-modules sync`).
- Produces: `dotfiles-settings sync on [--repo NAME]`, `sync off`, `sync now`, `sync status`. In `sync.py`: `on(repo: str) -> list[str]`, `off() -> list[str]`, `now() -> list[str]`, `status() -> list[str]`, each returning the lines to print, and raising `SettingsError` (exit 1) to stop. `gh` runs as `os.environ.get("DOTFILES_SETTINGS_GH", "gh")`, from `$HOME`, like `mise.run_mise`.
- Fixed values: the default repository name is `rotm-settings`. The origin URL is `https://github.com/<login>/<name>.git`, `<login>` from `gh api user --jq .login`. The track entry is exactly `"~/.config/rotm" = { mode = "track" }` under `[dotfiles]` in `config.local.toml` (with `ROTM_USER_DIR` set, its tildified path). The secrets rule is the one `bin/claude-config` uses for `env` keys: a key of `[env]` in the user's override file matching `(TOKEN|SECRET|PASSPHRASE|API_KEY|CLIENT_KEY)$`.

What each command does, in order. A failing step stops the command.

- `on`: `gh auth status`. When it fails and stdin is a terminal, run `gh auth login --hostname github.com --git-protocol https --web` with the terminal attached, which is the user signing in from the tool; when stdin is not a terminal, stop and name that command. Then `gh auth setup-git`. `rotm-user-layer ensure`. `capture`. The secrets guard. Then by the state of the repository:
  - It does not exist: `gh repo create <name> --private`, write the track entry, `mise dot save`, `mise dot origin set <url> --sync manual`, `mise dot sync`.
  - It exists and `gh api repos/<login>/<name>/contents/.mise-history/format.toml` succeeds: `mise bootstrap --adopt <url> --only final-hook`, `mise dot origin set <url> --sync manual`, write the track entry, `rotm-user-layer ensure` again (the adopt created the folder's files), `rotm-modules sync`, `replay`.
  - It exists, is not empty and has no such file: stop, "`<login>/<name>` is not a settings repository. Pass `--repo <another name>`."
  - It exists and is empty: as "does not exist", without the create.
- `now`: requires a connected origin (`mise dot origin` names one), else stops and names `sync on`. `capture`, the secrets guard, `mise dot save`, `mise dot sync`, `mise dot pull`, `rotm-modules sync`, `replay`. Ends with one line when the pull changed `modules-off.local` or `[bootstrap.packages]`: "Nothing was installed or removed. Run `rotm install` to install what is now on."
- Both `on` and `now` finish by running `mise dot conflicts`; when it lists a file they raise `SettingsError` with mise's listing and the two commands that decide one (`mise dot pull --take-remote <file>`, `--keep-local <file>`).
- `status`: the origin and mode from `mise dot origin`, the unsaved and pending lines of `mise dot status`, any conflicts, and "not connected" when there is no origin. Exit 0 either way.
- `off`: `mise dot origin --remove`. The folder, the links and the local history stay.

- [ ] **Step 1: Failing tests** in `test_sync.py`, with stub `mise` and `gh` scripts that log their arguments and take their answers from fixture files:

```python
# on, no repo: the logged calls are, in order, gh auth status, gh auth setup-git, rotm-user-layer ensure,
#   gh api user, gh repo view, gh repo create rotm-settings --private, mise dot save,
#   mise dot origin set https://github.com/octo/rotm-settings.git --sync manual, mise dot sync
# on, no repo: config.local.toml gains the [dotfiles] track entry once, keeps a [history.origin] table and a comment already in it, and a second `on` adds nothing
# on --repo mine: every URL and gh call uses "mine"
# on, settings repo exists: `mise bootstrap --adopt <url> --only final-hook` is called with exactly those flags, then origin set --sync manual; no `gh repo create`, no bare `--adopt`
# on, foreign repo: raises SettingsError naming --repo; no mise call was logged
# on, gh auth status fails, stdin not a terminal: raises SettingsError naming `gh auth login`; nothing else was called
# on, gh auth status fails, a terminal: `gh auth login --hostname github.com --git-protocol https --web` is called, then the run continues
# on and now, GITHUB_TOKEN in the override file's [env]: raises SettingsError naming the key; `mise dot save` was never called
# now, not connected: raises SettingsError naming `sync on`
# now: capture runs before `mise dot save`, and rotm-modules sync and replay after `mise dot pull`
# now, the pull changed modules-off.local: the last line is the "Nothing was installed or removed" sentence
# on and now, `mise dot conflicts` lists a file: raises SettingsError containing the file and both pull commands
# off: `mise dot origin --remove` only; the folder's files still exist
# no logged mise call is ever `dot track`
```

In `test_cli.py`: `sync` with no action exits 2, `sync status` prints "not connected" and exits 0 against a stub with no origin.

- [ ] **Step 2: Run.** Expected: the new tests fail on `sync.on` not defined.
- [ ] **Step 3: Implement** `on`, `off`, `now`, `status`, the track-entry writer (a text edit that keeps the rest of `config.local.toml`, in the style of `macos_default.set_key`) and the secrets guard in `sync.py`, and the `sync` subparser with its `action` choices and `--repo` in `cli.py`.
- [ ] **Step 4: `rotm help` and docs.** `bin/rotm`'s header gains one example line, `rotm settings sync {{on}}`. `settings/README.md` documents the four actions. Check `help rotm` renders.
- [ ] **Step 5: `pnpm check`, commit:** "Add rotm settings sync".

### Task 7: Prove the exchange with real mise

**Files:**
- Create: `bin/lib/test-sync`
- Modify: `bin/lib/check`

This is the spec's "Done when", run by the gate: two scratch homes shaped like installed copies, real mise, a local bare repository as the origin, `gh` stubbed to answer for it.

- [ ] **Step 1: Write the test** with these assertions, each a `check_true`:

```bash
# A: `dotfiles-settings sync on` exits 0; the origin holds home/.config/rotm/config.override.toml, modules-off.local and tools.toml
# A: the checkout's `git status --porcelain` is empty after it
# B: a fresh installed copy, `sync on`: the three files exist in B's folder, the config dir holds the two links,
#    B's miserc.local.toml ignores the module A switched off, and B's checkout is clean
# B: a file the base's config would create was not created (the adopt applied nothing)
# A changes a setting, `sync now`; B `sync now`: B's override file has the value
# a config.local.toml value written on A never appears in B's home or in the origin's history
# A and B change the same setting, both `sync now`: the second exits 1, names the file, and neither side lost its value
# A writes `"brew:p3-probe" = { state = "absent" }` under [bootstrap.packages] in its override file, `sync now`; after B's `sync now`,
#    B's `mise bootstrap packages status --json` reports that package absent
# GITHUB_TOKEN set with `mise set --override` on A: `sync now` exits 1 and the origin's history has no line containing it
```

- [ ] **Step 2: Run it.** Expected before Task 6 is complete: fails. Now: passes. If a step fails because mise behaves differently from the table above, stop and record what it did before changing the design.
- [ ] **Step 3: The header says** it takes the mise shims off `PATH` while `HOME` is faked, as `bin/CLAUDE.md` requires of such a self-check.
- [ ] **Step 4: Add `job quiet bash bin/lib/test-sync`,** run `pnpm check` three times (it now runs beside every other self-check), commit: "Check a two-Mac settings exchange in scratch homes".

### Task 8: Load saved settings during a first install

**Files:**
- Modify: `setup.sh` (after the `github_login` call near line 452, before the package lists), `bin/lib/test-bootstrap`, `setup/README.md`, `docs/installation.md`

**Interfaces:**
- Consumes: `dotfiles-settings sync on`, `gh`.

- [ ] **Step 1: Failing assertions in `test-bootstrap`,** with the stubbed `gh`:

```bash
# signed in, `gh repo view <login>/rotm-settings` succeeds, no origin connected, a terminal answers yes:
#   `dotfiles-settings sync on` ran once, before the first `mise bootstrap packages apply`
# the same with stdin closed, and with -y: sync on did not run, and one line says how to load them later
# signed in and the repository does not exist: no prompt, no sync call
# not signed in: no `gh repo view` call
# an origin is already connected: no prompt
# sync on exits 1: setup warns, names `rotm settings sync status`, and carries on to the packages
```

- [ ] **Step 2: Run.** Expected: the first assertion fails.
- [ ] **Step 3: Implement** `load_saved_settings` in `setup.sh` on those rules. A closed stdin means skip, as `.claude/rules/setup.md` requires. The module sync that follows the prompt in the file's order must run after it, so a module the user switched off elsewhere is off before the package lists; move the call or repeat it, whichever keeps `test-bootstrap`'s existing order assertions true.
- [ ] **Step 4: `pnpm check`, commit:** "Offer a user's saved settings before a first install".

### Task 9: Docs, the spec and the real proof

**Files:**
- Create: `docs/settings-sync.md`
- Modify: `README.md` (the docs table), `docs/forking.md`, `docs/modules.md`, the spec, this plan (moved to `plans/completed/` at the end)

- [ ] **Step 1: Move the single-package opt-out in `docs/modules.md`** from `config.local.toml` to `[bootstrap.packages]` in `~/.config/rotm/config.override.toml`, and say that one left in `config.local.toml` still works and stays on that Mac.
- [ ] **Step 1b: Write `docs/settings-sync.md`:** what is saved (the three files, by name), what never is (the machine-scoped settings, every `*.local.toml`, `~/.zsh.local`, `~/.gitconfig.local`, `~/.ssh`), the four actions, a second Mac, a conflict, and the warning from mise's docs that a private repository keeps every saved version.
- [ ] **Step 2: Update the spec.** The P3 brief gains a "Shipped" line. Task 4's measurement joins "Verified facts". "Sync and sign-in" is corrected where it says `dotfiles-settings` "tracks the user layer" with mise's own command.
- [ ] **Step 3: Run the `docs-auditor` agent** on the changed pages and fix what it confirms.
- [ ] **Step 4: Commit:** "Document settings sync".
- [ ] **Step 5: The real proof, when the owner schedules it.** In the UTM guest, "Run without saving changes", two sessions against a real private repository in a GitHub account the owner chooses: install, change one setting of each kind (an env setting, a module, a macOS preference, a jstack role), `rotm settings sync on`; then a fresh guest, install, accept the prompt, and compare `rotm settings list` between the two. Results go under `~/vm-proof/p3/`. Decision 15 means this does not block the plan from closing on the self-checks; it does block a promotion of `stable`.
- [ ] **Step 6: Move this plan** to `docs/superpowers/plans/completed/` and update the spec's "Plans" list.
