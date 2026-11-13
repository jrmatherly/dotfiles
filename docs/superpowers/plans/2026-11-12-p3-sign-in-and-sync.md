# P3: Sign In and Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** What a user changes through `rotm settings`, and what they opt out of, is saved to a private GitHub repository in their own account and loads onto their next Mac before anything is installed there.

**Architecture:** A user's choices move out of mise's checkout into one real folder, `~/.config/rotm`, and the config dir links to them. mise's own override file holds every setting mise can hold (the env settings, the macOS preferences, and the single-package and single-tool opt-outs, which the docs move there from `config.local.toml` so they travel), `modules-off.local` holds the module switches, and `tools.toml` holds the agent-tool settings the user changed, which mise cannot hold. mise's history tracks that folder through one entry written in `config.local.toml`, and a private repository is its origin. `rotm settings sync on|off|now|status` is the only new surface a user sees.

**Tech Stack:** bash 3.2 (`#!/bin/bash`), mise 2026.11.5 or newer (`mise dot`, `mise bootstrap --adopt`, `mise set --override`, `mise set --file`), Python 3.11+ standard library (the settings package), `gh`, git.

**Spec:** `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`. Read the Goal and "Decisions the owner made" in full first, then "Sync and sign-in", the last rows of "Verified facts" and the P3 brief. Decisions 2, 3, 8, 13, 14 and 15 bind every task here.

**Reviewed 2026-11-12,** before any task started, by the author against the code and by an independent reviewer on another model. Eighteen findings were raised and each was checked against the code or measured: sixteen changed a task, one was replaced by a simpler fix found while checking it (no Git credential configuration at all), and one needed only a measurement; "Measured while writing this plan" holds the measurements they needed. The probe scripts are in `docs/superpowers/specs/2026-11-11-installable-probe/p3/`.

## Global Constraints

- macOS only (decision 4). mise floor: 2026.11.5 (`setup/mise-floor.sh`). Every measurement below ran on 2026.11.5.
- The store is a private GitHub repository in the user's own account (decision 2). Nothing else is built to hold settings.
- Sync is manual (decision 8). Every `mise dot origin set` passes `--sync manual`. No `[bootstrap.services.mise-history]`, no LaunchAgent.
- Scope is every setting `rotm settings` can change, and the opt-outs (decision 13). Where mise can hold a setting, mise holds it; `tools.toml` is only for the ones it cannot (decision 14). A change made to a tool's own file by another program (for example `/jstack:setup-jstack`) is not a change made through `rotm settings` and is not saved.
- Nothing leaves the base (decisions 3 and 12). No task here removes a package, a default or an owner-pointing value.
- A development clone keeps the owner's workflow: there a macOS preference or a jstack role is still an edit to a tracked file that the owner commits. Tasks 3 and 4 change installed copies only.
- An installed copy stays fast-forwardable: no command writes a tracked file of the checkout. `mise dot track` is never called, because it writes its entry into `config.toml`. The track entry is appended to `config.local.toml` by our code.
- Restoring uses `mise bootstrap --adopt <url> --only final-hook --yes`, always with those flags. Without `--only final-hook` mise runs a full bootstrap of the base, macOS preferences included. `mise dot origin set` also takes `--yes`: its help says it asks before the first sync, and our callers capture its output, so a prompt would hang unseen.
- No Git credential configuration is written anywhere. mise passes its own helper for github.com (`mise token github --git-credential`) to every Git call it makes, and that reads the `gh` login (`[settings.github]` in `config.toml`). `gh auth setup-git` is never run: it writes `~/.gitconfig`, a tracked link on a clone.
- `~/.config/rotm` holds exactly `config.override.toml`, `modules-off.local` and `tools.toml`. That, with the secrets guard of Task 6, is this phase's exclude list: `sync on` and `sync now` stop when the folder holds any other file, because mise would save it.
- `*.local.toml` never travels (mise's rule). Anything a second Mac needs is either in `~/.config/rotm` or written again by our code on that Mac.
- The owner's Mac is a clone and `~/.config/mise` is a link into it. Never run `./setup.sh`, `sysup`, `rotm install`, `rotm update`, `rotm settings sync on` or `mise bootstrap` against the real home. Real sync against GitHub is Task 9, in the VM, when the owner schedules it (decision 15).
- Testing rule: self-checks use stubs and scratch homes, with `HOME` and every `MISE_*_DIR` pointed at the scratch folder and every mise call run from the scratch home.
- The self-checks have their own helpers (`run`, `prepare`, `check_true`, `has`, `lacks`, `stub`, `$STATE`, `$fix`; `raises` in the Python tests). Where a block here and the file disagree on a helper, the file wins and the assertion stays.
- A new self-check is one `job quiet bash <path>` line in `bin/lib/check`, and a new stdlib Python test one entry in `settings_tests` there.
- `pnpm check` runs before every commit (about 40 seconds). Edit and commit in separate Bash calls. One commit per task.
- Docs mirror behaviour: a change to setup or settings behaviour has its `README.md`, `setup/README.md`, `settings/README.md` or `docs/` edit in the same commit. A docs page is never named after a command (`help <name>` reads `docs/<name>.md` first), so the new page is `docs/settings-sync.md`.

## Measured while writing this plan

On 2026-11-12, mise 2026.11.5, scratch homes on the owner's Mac shaped like installed copies (`~/.config/mise` a link into a checkout under the data dir), a local bare repository as the origin. Status, save, sync, pull and adopt calls only. Every probe but the last two rows ran with `MISE_YES=1`. The spec's "Verified facts" holds the first five rows.

| Claim | Measured |
| --- | --- |
| mise's sync saves `config.override.toml` and `modules-off.local` where P1 and P2 put them | No. Left out as "mise internal directory", because the config dir resolves into the data dir |
| `mise dot track` keeps the checkout clean | No. It wrote its entry into `config.toml` |
| A `mode = "track"` entry written by hand in `config.local.toml` is honoured | Yes, and the checkout stayed clean |
| `config.override.toml` can be a link to a real file outside the checkout | Yes. mise read through it, and `mise set --override` and `mise unset --override` both exited 0, wrote the real file, kept the link and kept the file's other tables |
| A folder outside the checkout syncs between two installed copies | Yes, in both directions, with `mise dot sync` then `mise dot pull` |
| The override file can hold more than `[env]` | Yes. A `[bootstrap.macos.defaults."<domain>"]` key in it replaced the same key from `conf.d/20-macos.toml` in `mise bootstrap macos defaults status --json` and left that domain's other keys alone. A `"brew:<name>" = { state = "absent" }` in its `[bootstrap.packages]` made `packages status` report the package `absent`. `[settings] disable_tools = ["npm:prettier"]` in it removed that tool from `mise ls`. An `[env]` key in it beat the same key from `conf.d` |
| `mise bootstrap --adopt <origin>` only restores files | No. It then ran a full bootstrap and applied a `[dotfiles]` entry of the base. With `--only final-hook` it restored the files and applied nothing |
| An adopted home keeps the first Mac's manual mode | No. It starts in mode `sync`; `mise dot origin set <origin> --sync manual` afterwards is accepted (probe 6) |
| A track entry written as its own table, `[dotfiles."~/.config/rotm"]` with `mode = "track"`, appended after an existing `[dotfiles]` table | Honoured, and mise kept it when it wrote `[history.origin]` into the same file. So the entry can be appended without parsing the file |
| What mise says with no origin, and with no conflict | `mise dot origin` prints "no setup repository is connected" and `mise dot conflicts` prints "no sharing conflicts", both exit 0. A conflict is read from the text, never the exit code |
| Restoring onto a folder that already holds a different file | mise held it: "sync paused: 1 conflict(s) remain; no files applied or published". The local file was unchanged and `mise dot conflicts` printed the diff. The exit code of that adopt was not captured |
| A link in the config dir whose target does not exist yet | mise listed its config without error, and `mise set --override` created the target file through the link and kept the link |
| How mise authenticates its Git calls | Through the `git` command, 98 calls for one save, connect and sync, each carrying `-c credential.https://github.com.helper=!<mise> token github --git-credential`. Measured with a wrapper `git` that logged its arguments |
| `mise dot origin set <origin> --sync manual` without `MISE_YES` and with stdin closed | Connected and published, exit 0. Whether it asks on a terminal was not measured, so `--yes` is passed |
| `config.rotm-installed.toml` redeclares `"~/.claude/rules"` with `exclude = [".DS_Store", "jstack-models.md"]` and seeds that file with `mode = "copy", create_if_missing = true` | Works (`p3/6-seeded-copy-in-symlink-each.sh`, `MISE_ENV=rotm-installed`, a checkout from `git archive HEAD`). First apply: the other nine rules are links and the file is a regular copy of the tracked one. Second apply after the user edited it: the edit stays, "45 entries up to date". An install made before this change, where the path is a link: the first apply removes the link as stale and writes no copy (exit 0), `mise dotfiles status --missing` lists it and exits 1, and the second apply seeds it. Accepted without a workaround: no such install exists outside disposable VM guests (decision 15), and jstack falls back to its defaults while the file is absent |
| A helper passed in the environment beats a later one in a config file | Yes. With a github.com helper followed by an empty `helper =` and a second helper in the file, `git credential fill` used the second; with `GIT_CONFIG_COUNT`, an empty `credential.helper` and a helper in the environment, it used that one. This is the fallback if Task 9 shows mise's own helper is not enough |

Also read in the code: `uv`, which `bin/dotfiles-settings` needs, is `brew:uv` in the package lists that run after setup's GitHub login, so the restore during setup is bash and mise only. `_read_jstack` in `adapters/tool.py` returns `Source.SEED` for every role, and an installed copy's roles file is a seeded copy that later upstream changes never reach, so a diff against the shipped file cannot tell the user's change from an upstream one; `tools.toml` records a change when it is made instead.

Not measured, and settled by the task named: a real private GitHub repository, with mise's own helper as the only credential source (Task 9). Task 4's Step 1, whether `config.rotm-installed.toml` can turn one file of a `symlink-each` folder into a seeded copy, was measured before that task and is recorded in the table above.

## File Structure

| File | Responsibility |
| --- | --- |
| `bin/lib/rotm-user-layer` (new) | Owns `~/.config/rotm`: prints its path, moves the user's files into it and links them from the config dir, writes the track entry, and restores the folder from an origin. Bash and mise only, so setup can run it before `uv` exists |
| `bin/lib/rotm-modules` | Unchanged contract. Writes `modules-off.local` through a link instead of replacing the link |
| `settings/src/dotfiles_settings/sync.py` (new) | The sync commands, the record of tool settings and its replay, the secrets and folder guards |
| `settings/src/dotfiles_settings/cli.py` | The `sync` subcommand, nothing else |
| `settings/src/dotfiles_settings/adapters/env.py` | Machine-scoped settings go to `config.local.toml` |
| `settings/src/dotfiles_settings/adapters/macos_default.py` | On an installed copy, writes the user's override file instead of refusing |
| `settings/src/dotfiles_settings/adapters/tool.py` | Records a tool setting when the user sets or resets it |
| `settings/registry.toml`, `registry.py`, `model.py` | One new optional field, `scope` |
| `zsh/override-env.zsh` | Also caches the machine-scoped keys in `config.local.toml` |
| `tilde/.config/mise/config.rotm-installed.toml` | `jstack-models.md` becomes a seeded copy on an installed copy |
| `setup.sh`, `.claude/rules/setup.md` | Calls `rotm-user-layer ensure`, offers to load saved settings after the GitHub login, applies them at the end; the rule on `--adopt` is narrowed |
| `bin/lib/test-user-layer`, `bin/lib/test-sync`, `settings/tests/test_sync.py` (new) | Self-checks |
| `docs/settings-sync.md` (new), `docs/modules.md`, `docs/forking.md`, `README.md`, `settings/README.md`, `setup/README.md` | Docs |

## Review Focus

1. **Both places hold a file and they differ.** A Mac has `~/.config/rotm/config.override.toml` from a restore and a different real `config.override.toml` in the config dir. Expected: `rotm-user-layer ensure` exits 1, names both paths and changes neither. Pinned in Task 1.
2. **The named repository exists and is not a settings repository.** `rotm-settings` already holds something else. Expected: `sync on` refuses before any push and names the `--repo` flag. Pinned in Task 6.
3. **A secret, or a stray file, is in the folder.** The user once ran `mise set --override GITHUB_TOKEN=…`, or copied a file into `~/.config/rotm`. Expected: `sync on` and `sync now` stop before the first save and name it, because history keeps it forever. Pinned in Task 6.
4. **A second Mac already differs before it is connected.** It changed a setting, or its first install ran with `--without`. Expected: mise pauses, neither side is overwritten, and `sync on` and `sync now` exit 1 and print the conflicting files; setup's own restore avoids the `--without` case. Pinned in Tasks 6, 7 and 8.
5. **A restored choice that this run cannot act on.** A module arrives switched off, or a macOS preference arrives. Expected: nothing is uninstalled and no preference is written behind the user's back; the command says which of `rotm install` and `set-defaults` applies it. Pinned in Task 6.

---

### Task 1: The user's folder and its links

**Files:**
- Create: `bin/lib/rotm-user-layer`, `bin/lib/test-user-layer`
- Modify: `bin/lib/rotm-modules` (`replace`, which today renames a temp file over the path and would replace a link), `setup.sh` (before the `"$modules" sync` call near line 247), `bin/sysup` (before its `"$modules" sync` near line 236), `bin/lib/check`

**Interfaces:**
- Produces, all run by path:
  - `rotm-user-layer dir` prints `${ROTM_USER_DIR:-$HOME/.config/rotm}`.
  - `rotm-user-layer ensure` exits 0 when, for each of `config.override.toml` and `modules-off.local`, the config dir (`${MISE_CONFIG_DIR:-$HOME/.config/mise}`) holds a link to the file of the same name in that folder. A real config-dir file is moved into the folder first. The link is made even when no file exists yet (measured: mise reads past it and writes through it). It exits 1, changing nothing, when both a real config-dir file and a folder file exist and differ.
  - `rotm-user-layer track` appends the two lines `[dotfiles."<folder, tildified>"]` and `mode = "track"` to `config.local.toml` in the config dir unless that header line is already there, creating the file when missing.
  - `rotm-user-layer restore <url>` runs, from `$HOME`: `mise bootstrap --adopt <url> --only final-hook --yes`, `mise dot origin set <url> --sync manual --yes`, `track`, `ensure`, then `mise dot conflicts`. It exits 1 and prints mise's listing when that output is anything but "no sharing conflicts", and exits with mise's status when a mise call fails.

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
# 9. track with no config.local.toml: the file holds exactly the two lines; run again: unchanged
# 10. track with a config.local.toml that has a [dotfiles] table, a comment and [history.origin]: all kept byte for byte, the two lines appended once
# 11. restore against a stub mise that logs its arguments: the adopt carries `--only final-hook --yes`, the origin set carries `--sync manual --yes`,
#     no logged call is a bare `--adopt` or `dot track`, and neither ~/.gitconfig nor ~/.gitconfig.local was created
# 12. restore with the stub's `dot conflicts` printing a path: exit 1 and the path is on stderr
```

- [ ] **Step 2: Run it.** `bash bin/lib/test-user-layer`. Expected: fails, `rotm-user-layer` not found.
- [ ] **Step 3: Write `bin/lib/rotm-user-layer`** with the standard header, `set -euo pipefail`, and the four commands above. `restore` is exercised against real mise in Task 7.
- [ ] **Step 4: Make `rotm-modules` write through a link.** `replace` resolves its target first (one `readlink`, as `adapters/tool.py:edit_file` does with `resolve`) and renames the temp file onto that, so the link survives.
- [ ] **Step 5: Call `"$DOTFILES_DIR/bin/lib/rotm-user-layer" ensure || exit $?` in `setup.sh`** directly before the module sync, in both modes, skipped under `--dry-run`. Call it in `sysup` before its module sync, reported as a `fail` status line when it exits 1.
- [ ] **Step 6: Add `job quiet bash bin/lib/test-user-layer` to `bin/lib/check`**, run `pnpm check`. Expected: passes, including `test-modules`, `test-bootstrap` and `test-sysup` unchanged.
- [ ] **Step 7: Docs and commit.** `setup/README.md` gains the step, `docs/local-customizations.md` names the folder. Commit: "Keep a user's settings in a folder of their own".

### Task 2: Settings that describe one Mac stay on it

**Files:**
- Modify: `settings/src/dotfiles_settings/model.py`, `registry.py` (`OPTIONAL`), `adapters/env.py`, `settings/registry.toml`, `zsh/override-env.zsh`
- Test: `settings/tests/test_registry.py`, `settings/tests/test_env.py`, `bin/lib/test-override-env`

**Interfaces:**
- Produces: `Setting.scope: str = "user"`, the other accepted value is `"machine"`. `registry.parse` rejects anything else. Tasks 5 and 6 skip `scope == "machine"` settings.

- [ ] **Step 1: Failing tests.** In `test_registry.py`: `macos.computer_name`, `macos.local_hostname` and `hindsight.paths` load with `scope == "machine"`, every other setting with `"user"`, and a fixture entry with `scope = "everyone"` raises. In `test_env.py`, against the stub mise: writing `macos.computer_name` calls `set --file <config_dir>/config.local.toml DOTFILES_MACOS_COMPUTER_NAME=<value>` and never `--override`; reading it returns `Source.OVERRIDE` from that file; `reset` calls `unset --file <same path>`; a value left in the override file from before this change is read, and the next write removes it there with `unset --override`; `watch_paths()` includes `config.local.toml`. In `test-override-env`: a key under `[env]` in `config.local.toml` is exported by a shell that never reaches a prompt, and the cache is rebuilt when that file is newer than it.
- [ ] **Step 2: Run them.** Expected: fail on the unknown field and the missing export.
- [ ] **Step 3: Implement.** `scope` in `Setting` and in `OPTIONAL`. In `EnvAdapter`, `local_path() -> Path` is `mise.config_dir() / "config.local.toml"`, and `read`, `write` and `reset` pick the file by `s.scope`. `zsh/override-env.zsh` collects the `[env]` keys of both files and compares the cache with both.
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
- Modify: `tilde/.config/mise/config.rotm-installed.toml`, `bin/lib/test-dotfiles`, `settings/src/dotfiles_settings/adapters/tool.py` (`JSTACK_NOTE`), `settings/tests/test_tool.py`

- [ ] **Step 1: Measure first, in a scratch home.** With `40-dotfiles.toml`'s `"~/.claude/rules"` `symlink-each` entry and the `rotm-installed` environment selected, does a redeclared `"~/.claude/rules"` with `exclude = [".DS_Store", "jstack-models.md"]` plus `"~/.claude/rules/jstack-models.md" = { source = "~/dotfiles/tilde/.claude/rules/jstack-models.md", mode = "copy", create_if_missing = true }` leave every other rule a link and that one a real file, on a first apply, on a second, and when the path is already a link from an install made before this task? Record the answer in this plan's table and in the spec's "Verified facts". If mise refuses the pair, stop and report: the fallback is the owner's call.
- [ ] **Step 2: Failing assertions in `bin/lib/test-dotfiles`.** In its installed-environment section: after apply, `~/.claude/rules/jstack-models.md` is a regular file with the tracked file's content, `~/.claude/rules/verify-first.md` is a link, and an edit to the regular file survives a second apply. Its two shape checks on `config.rotm-installed.toml` (lines 40 to 49) reject the new entries as written: the first accepts a key only when it redeclares a fragment key or sits under a `{ permissions` folder, the second only `create_if_missing`, `merge` or permissions-only entries. Both gain one allowed case, a redeclared `symlink-each` entry that only adds `exclude` and a seeded copy of a file that entry excludes, and nothing wider.
- [ ] **Step 3: Add the two entries** to `config.rotm-installed.toml`, with a one-line why.
- [ ] **Step 4: Make `JSTACK_NOTE` say what happened.** `ToolAdapter.write_note` returns the "Commit it to keep the change" text only when the roles file resolves into a clone; on an installed copy it says the role is saved in the user's own copy. A `test_tool.py` case pins both.
- [ ] **Step 5: Run `bash bin/lib/test-dotfiles` and `python3 settings/tests/test_tool.py`.** `edit_file` needs no change: it refuses only a path inside the checkout, and the file no longer is one.
- [ ] **Step 6: `pnpm check`, commit:** "Seed the jstack roles file on an installed copy".

### Task 5: Carry the settings mise cannot hold

**Files:**
- Create: `settings/src/dotfiles_settings/sync.py`, `settings/tests/test_sync.py`
- Modify: `settings/src/dotfiles_settings/adapters/tool.py` (`ToolAdapter.write`, `reset`), `settings/tests/test_tool.py`, `bin/lib/check` (`settings_tests`)

**Interfaces:**
- Produces, all in `sync.py`:
  - `user_dir() -> Path`: `ROTM_USER_DIR` or `~/.config/rotm`.
  - `tools_path() -> Path`: `user_dir() / "tools.toml"`, one `[tools]` table of `"<setting id>" = "<value>"`, keys sorted.
  - `applied_path() -> Path`: `${XDG_STATE_HOME:-~/.local/state}/rotm/tools.applied.toml`, the same shape. It is what this Mac last recorded or replayed, and it never leaves the Mac.
  - `record(s: Setting, value: str) -> None` sets the id in both files. `forget(s: Setting) -> None` removes it from both. Both do nothing for `scope == "machine"`.
  - `replay(settings, adapters) -> list[str]`: for each id in `tools.toml` whose live value differs, calls that adapter's `write`; for each id in the applied file that `tools.toml` no longer has, calls that adapter's `reset`; then writes the applied file as a copy of `tools.toml` minus the ids that failed. Returns one line per change. An id the registry no longer has is skipped and named in a returned line. A write or reset that raises `SettingsError` becomes a returned line, the rest continue, and `tools.toml` itself is never rewritten by `replay`.
- Changes: after a successful write, `ToolAdapter.write` calls `sync.record(s, value)`, and `ToolAdapter.reset` calls `sync.forget(s)`. The terminal and browser UIs already write through the adapter, so they are covered.

- [ ] **Step 1: Failing test** `test_sync.py`, with fake adapters in a temp `ROTM_USER_DIR` and `XDG_STATE_HOME`:

```python
# record then record another id: tools.toml holds both, sorted; recording the same value again leaves the bytes identical
# forget: the id leaves both files; forgetting an id that was never recorded is a no-op
# a machine-scoped setting: record and forget touch neither file
# a multi-line value and a value with a double quote round-trip through tomllib
# replay: only the id whose live value differs is written; the applied file then equals tools.toml
# replay after another Mac's reset (the id is in the applied file, not in tools.toml): adapter.reset is called once and the id leaves the applied file
# replay: an unknown id yields "skipped <id>: not a setting here" and stays in tools.toml
# replay: one adapter raising SettingsError yields a line with its message, the next id is still written,
#         tools.toml is byte-identical afterwards, and the failed id is absent from the applied file so the next replay tries it again
```

- [ ] **Step 1b: Failing test in `test_tool.py`:** `ToolAdapter.write` on `claude.model` and on a jstack role leaves the id and value in `tools.toml`; `reset` removes it; a write that raises leaves the file unchanged; `hindsight.paths` never appears.
- [ ] **Step 2: Run.** Expected: `ModuleNotFoundError: dotfiles_settings.sync`.
- [ ] **Step 3: Implement** the functions and the two adapter calls. Values are written with `json.dumps`, which is valid TOML for a basic string.
- [ ] **Step 4: Add the test to `settings_tests`,** run `pnpm check`, commit: "Record and replay the tool settings mise cannot hold".

### Task 6: `rotm settings sync`

**Files:**
- Modify: `settings/src/dotfiles_settings/sync.py`, `cli.py`
- Test: `settings/tests/test_sync.py`, `settings/tests/test_cli.py`

**Interfaces:**
- Consumes: Task 1's `rotm-user-layer` (`ensure`, `track`, `restore`, run through `tool.run`), Task 5's `replay`, the module adapter's helper (`rotm-modules sync`).
- Produces: `dotfiles-settings sync on [--repo NAME]`, `sync off`, `sync now`, `sync status`, `sync apply`. In `sync.py`: `on(repo: str) -> list[str]`, `off() -> list[str]`, `now() -> list[str]`, `status() -> list[str]`, `apply() -> list[str]`, each returning the lines to print and raising `SettingsError` (exit 1) to stop. `gh` runs as `os.environ.get("DOTFILES_SETTINGS_GH", "gh")`, from `$HOME`, like `mise.run_mise`.
- Fixed values: the default repository name is `rotm-settings`. The origin URL is `https://github.com/<login>/<name>.git`, `<login>` from `gh api user --jq .login`. A repository is a settings repository when `gh api repos/<login>/<name>/contents/.mise-history/format.toml` succeeds. The secrets rule is the one `bin/claude-config` uses for `env` keys: a key of `[env]` in the user's override file matching `(TOKEN|SECRET|PASSPHRASE|API_KEY|CLIENT_KEY)$`. The folder rule: any entry of `~/.config/rotm` other than the three named files. A conflict is `mise dot conflicts` printing anything but "no sharing conflicts".

What each command does, in order. A failing step stops the command.

- `on`: `gh auth status`. When it fails and stdin is a terminal, run `gh auth login --hostname github.com --git-protocol https --web` with the terminal attached, which is the user signing in from the tool; when stdin is not a terminal, stop and name that command. Then read the repository's state before anything is written to the folder:
  - A settings repository: `rotm-user-layer restore <url>`, then `apply`. Nothing is created in the folder first: a file there before the restore would be held as a conflict with the saved one.
  - Not empty and not a settings repository: stop, "`<login>/<name>` is not a settings repository. Pass `--repo <another name>`."
  - Missing or empty: `gh repo create <name> --private` when missing, then `rotm-user-layer ensure`, the two guards, `rotm-user-layer track`, `mise dot save`, `mise dot origin set <url> --sync manual --yes`, `mise dot sync`.
- `now`: requires a connected origin (`mise dot origin` does not print "no setup repository is connected"), else stops and names `sync on`. The two guards, `mise dot save`, `mise dot sync`, `mise dot pull`, then `apply`.
- `apply`: `rotm-modules sync`, then `replay`. No network. It compares the override file and `modules-off.local` with a copy it keeps beside the applied file and ends with one line per kind that changed: for `modules-off.local` or `[bootstrap.packages]`, "Nothing was installed or removed. Run `rotm install` to install what is now on."; for `[bootstrap.macos.defaults]`, "macOS preferences changed. Run `set-defaults` to write them." Setup runs it at the end of a first install (Task 8).
- `on` and `now` finish with the conflict check; on a conflict they raise `SettingsError` with mise's listing and the two commands that decide one (`mise dot pull --take-remote <file>`, `--keep-local <file>`).
- `status`: the origin and mode from `mise dot origin`, the unsaved and pending lines of `mise dot status`, any conflicts, and "not connected" when there is no origin. Exit 0 either way.
- `off`: `mise dot origin --remove`. The folder, the links and the local history stay.

- [ ] **Step 1: Failing tests** in `test_sync.py`, with stub `mise`, `gh` and `rotm-user-layer` scripts that log their arguments and take their answers from fixture files:

```python
# on, no repo: the logged calls are, in order, gh auth status, gh api user, the repository lookup, gh repo create rotm-settings --private,
#   rotm-user-layer ensure, rotm-user-layer track, mise dot save,
#   mise dot origin set https://github.com/octo/rotm-settings.git --sync manual --yes, mise dot sync
# on, no repo: no call is `gh auth setup-git`, and no file named .gitconfig or .gitconfig.local exists in the scratch home afterwards
# on --repo mine: every URL and gh call uses "mine"
# on, settings repo exists: `rotm-user-layer restore <url>` is the first call that touches the folder, then rotm-modules sync;
#   no `gh repo create`, and no `mise dot save` before the restore
# on, foreign repo: raises SettingsError naming --repo; no mise call and no rotm-user-layer call was logged
# on, gh auth status fails, stdin not a terminal: raises SettingsError naming `gh auth login`; nothing else was called
# on, gh auth status fails, a terminal: `gh auth login --hostname github.com --git-protocol https --web` is called, then the run continues
# on and now, GITHUB_TOKEN in the override file's [env]: raises SettingsError naming the key; `mise dot save` was never called
# on and now, a file named notes.txt in the folder: raises SettingsError naming it; `mise dot save` was never called
# now, not connected: raises SettingsError naming `sync on`
# now: `mise dot save` precedes `mise dot sync`, which precedes `mise dot pull`, then rotm-modules sync and replay
# apply: rotm-modules sync then replay, and no gh call and no `mise dot` call
# apply, modules-off.local changed since the last apply: the output has the "Nothing was installed or removed" sentence; run again: it does not
# apply, a [bootstrap.macos.defaults] key changed: the output has the `set-defaults` sentence, and no `defaults write` was run
# on and now, `mise dot conflicts` lists a file: raises SettingsError containing the file and both pull commands
# off: `mise dot origin --remove` only; the folder's files still exist
# no logged mise call is ever `dot track`, and every `origin set` and `--adopt` carries --yes
```

In `test_cli.py`: `sync` with no action exits 2, `sync status` prints "not connected" and exits 0 against a stub with no origin.

- [ ] **Step 2: Run.** Expected: the new tests fail on `sync.on` not defined.
- [ ] **Step 3: Implement** `on`, `off`, `now`, `apply`, `status` and the two guards in `sync.py`, and the `sync` subparser with its `action` choices and `--repo` in `cli.py`.
- [ ] **Step 4: `rotm help` and docs.** `bin/rotm`'s header gains one example line, `rotm settings sync {{on}}`. `settings/README.md` documents the five actions. Check `help rotm` renders.
- [ ] **Step 5: `pnpm check`, commit:** "Add rotm settings sync".

### Task 7: Prove the exchange with real mise

**Files:**
- Create: `bin/lib/test-sync`
- Modify: `bin/lib/check`

This is the spec's "Done when", run by the gate: scratch homes shaped like installed copies, real mise, a local bare repository as the origin.

How the test reaches a local origin and runs offline, since `sync.py` builds a `https://github.com/…` URL and `bin/dotfiles-settings` starts `uv`: the scratch Git config (`GIT_CONFIG_GLOBAL`) holds `url.<bare repo path>.insteadOf https://github.com/octo/rotm-settings.git`; `gh` is a stub that answers `auth status`, `api user` and the lookup from the bare repository's real contents; and the CLI runs as `python3 -m dotfiles_settings` with `PYTHONPATH=settings/src` under the same Python `bin/lib/check` picks, never through `uv`.

- [ ] **Step 1: Write the test** with these assertions, each a `check_true`:

```bash
# A: `sync on` exits 0; the origin holds home/.config/rotm/config.override.toml and modules-off.local
# A: the checkout's `git status --porcelain` is empty after it
# B: a fresh installed copy, `sync on`: the files exist in B's folder, the config dir holds the two links,
#    B's miserc.local.toml ignores the module A switched off, and B's checkout is clean
# B: a file the base's config would create was not created (the restore applied nothing)
# C: a fresh installed copy with python3 and uv off PATH: `rotm-user-layer restore <url>` alone leaves the same files, links and track entry as B
# A changes a setting, `sync now`; B `sync now`: B's override file has the value
# A records a tool setting and syncs; B `sync now`: B's fake tool has the value. A resets it and syncs; B `sync now`: B's fake tool was reset
# A writes `"brew:p3-probe" = { state = "absent" }` under [bootstrap.packages] in its override file, `sync now`; after B's `sync now`,
#    B's `mise bootstrap packages status --json` reports that package absent, and B's output has the `rotm install` sentence
# a config.local.toml value written on A never appears in B's home or in the origin's history
# A and B change the same setting, both `sync now`: the second exits 1, names the file, and neither side lost its value
# D: a copy whose folder already holds a different override file: `sync on` exits 1, prints the file, and the local file is unchanged
# GITHUB_TOKEN set with `mise set --override` on A: `sync now` exits 1 and the origin's history has no line containing it
```

- [ ] **Step 2: Run it.** Expected: passes. If a step fails because mise behaves differently from the table above, stop and record what it did before changing the design.
- [ ] **Step 3: The header says** it takes the mise shims off `PATH` while `HOME` is faked, as `bin/CLAUDE.md` requires of such a self-check.
- [ ] **Step 4: Add `job quiet bash bin/lib/test-sync`,** run `pnpm check` three times (it now runs beside every other self-check), commit: "Check a two-Mac settings exchange in scratch homes".

### Task 8: Load saved settings during a first install

**Files:**
- Modify: `setup.sh` (after the `github_login` call near line 452, before the package lists, and at the end of the run), `.claude/rules/setup.md`, `bin/lib/test-bootstrap`, `setup/README.md`, `docs/installation.md`

**Interfaces:**
- Consumes: `rotm-user-layer restore` (Task 1), `dotfiles-settings sync apply` (Task 6), `gh`. `bin/dotfiles-settings` needs `uv`, which the package lists install after this point, so the restore here is the bash helper and the tool settings wait for the end of the run.

- [ ] **Step 1: Failing assertions in `test-bootstrap`,** with the stubbed `gh` and a stubbed `rotm-user-layer`:

```bash
# signed in, the settings-repository lookup for <login>/rotm-settings succeeds, no origin connected, a terminal answers yes:
#   `rotm-user-layer restore https://github.com/<login>/rotm-settings.git` ran once, then `rotm-modules sync`,
#   both before the first `mise bootstrap packages apply`; `dotfiles-settings` was not called before the packages
# the same run with --without fonts: the folder's modules-off.local did not exist when restore ran,
#   and `rotm-modules sync --without fonts` ran after it, so fonts is off on top of what was restored
# the restored override file sets DOTFILES_SKIP_CODEGRAPH=true: `mise install` ran with npm:@colbymchenry/codegraph in MISE_DISABLE_TOOLS
# the same run, at its end: `dotfiles-settings sync apply` ran once, after the bootstrap task
# no restore happened in this run: `sync apply` did not run
# the same with stdin closed, and with -y: no restore, and one line says `rotm settings sync on` loads them later
# signed in and the lookup fails (no repository, or not a settings repository): no prompt, no restore
# not signed in: no lookup
# an origin is already connected (`mise dot origin` names one): no prompt
# restore exits 1: setup warns, names `rotm settings sync status`, and carries on to the packages
# --dry-run: no prompt and no restore
```

- [ ] **Step 2: Run.** Expected: the first assertion fails.
- [ ] **Step 3: Implement** `load_saved_settings` in `setup.sh` on those rules, called right after `github_login`. A closed stdin means skip, as `.claude/rules/setup.md` requires. Four things the order forces:
  - `--without` was already written into the folder by the module sync near line 247. Before the restore that file is moved aside, and after it `"$modules" sync --without "$without"` runs again, so the restore meets no differing file and the flag still wins.
  - Without `--without`, `"$modules" sync` runs again after the restore, so a module switched off on another Mac is off before the package lists.
  - `skip_codegraph` was read from the process environment at the top of the script. After a restore it is read again from mise (`mise env --json` from `$HOME`, `/usr/bin/jq`), and the block that exports `DOTFILES_SKIP_CODEGRAPH` and `MISE_DISABLE_TOOLS` runs again when it turned true.
  - The `sync apply` call sits after the bootstrap task and `setup/dotfiles-extras.sh`, so it follows `claude-config restore` and the user's model choice is the last write. A failure there is a warning.
- [ ] **Step 4: Narrow the rule in `.claude/rules/setup.md`.** It says `setup.sh` never calls `--adopt`, because a bare adopt of a config repository clones it into `~/.config/mise`. The new sentence: the one exception is `rotm-user-layer restore`, which adopts a history origin with `--only final-hook` and applies nothing.
- [ ] **Step 5: `pnpm check`, commit:** "Offer a user's saved settings before a first install".

### Task 9: Docs, the spec and the real proof

**Files:**
- Create: `docs/settings-sync.md`
- Modify: `README.md` (the docs table), `docs/modules.md`, `docs/forking.md`, the spec, this plan (moved to `plans/completed/` at the end)

- [ ] **Step 1: Move both single-item opt-outs in `docs/modules.md`** (the `state = "absent"` package and `[settings] disable_tools`) from `config.local.toml` to `~/.config/rotm/config.override.toml`, and say that one left in `config.local.toml` still works and stays on that Mac.
- [ ] **Step 2: Write `docs/settings-sync.md`:** what is saved (the three files, by name), what never is (the machine-scoped settings, every `*.local.toml`, `~/.zsh.local`, `~/.gitconfig.local`, `~/.ssh`, and a tool's file changed by another program), the four actions a user runs, a second Mac, what `rotm install` and `set-defaults` still have to do after a sync, a conflict, and the warning from mise's docs that a private repository keeps every saved version.
- [ ] **Step 3: Update the spec.** The P3 brief gains a "Shipped" line. Task 4's measurement joins "Verified facts". "Sync and sign-in" is corrected where it says `dotfiles-settings` "tracks the user layer" with mise's own command and where it names `gh auth setup-git`.
- [ ] **Step 4: Run the `docs-auditor` agent** on the changed pages and fix what it confirms.
- [ ] **Step 5: Commit:** "Document settings sync".
- [ ] **Step 6: The real proof, when the owner schedules it.** In the UTM guest, "Run without saving changes", two sessions against a real private repository in a GitHub account the owner chooses: install, change one setting of each kind (an env setting, a module, a macOS preference, a jstack role), `rotm settings sync on`; then a fresh guest, install, accept the prompt. Compare `rotm settings list --json` between the two, run `set-defaults` on the second and compare `defaults read` for the changed preference, since `list` reports a declared value whether or not it was written. The first `sync on` also settles whether mise's own credential helper is enough against GitHub; if it is not, the fallback in the measured table goes into `sync.py` and `rotm-user-layer`. Results go under `~/vm-proof/p3/`. Decision 15 means this does not block the plan from closing on the self-checks; it does block a promotion of `stable`.
- [ ] **Step 7: Move this plan** to `docs/superpowers/plans/completed/` and update the spec's "Plans" list.
