# P0: Probes and the Model Default Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure the ten mise behaviours the installable-setup design rests on, in a scratch home inside the VM, and stop `claude-config save` from replacing the tracked `opus` model with one Mac's choice.

**Architecture:** One committed harness script builds a throwaway home, a small fixture bootstrap project in a local Git repository and a bare repository that stands in for the user's private GitHub repository. Every probe gets a fresh copy of each, so no probe sees what another left behind. Each probe is a function in that script that runs real mise commands against the fixtures and prints one `PROBE <n> <answer>` line. The answers are copied into the spec, which then decides P1 to P4.

**Tech Stack:** bash 3.2 (`#!/bin/bash`), mise 2026.11.5 or newer, git, `/usr/bin/jq`.

**Spec:** `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`. Read "Not verified, and the check that settles each" first: each probe here answers one row of that table.

## Global Constraints

- macOS only.
- mise floor: 2026.11.5 (`setup/mise-floor.sh`). The probes report the version they ran on.
- No probe touches the real home. Every mise and git call in the harness runs through `env -i` with only these set: `PATH`, `TERM=dumb`, `MISE_YES=1`, `HOME`, `MISE_DATA_DIR`, `MISE_CONFIG_DIR`, `MISE_STATE_DIR` and `MISE_CACHE_DIR` (all under the scratch folder), `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, and `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, `GIT_COMMITTER_EMAIL` set to `probe` and `probe@example.invalid`. That keeps out the caller's `MISE_ENV`, tokens and shell activation, and the real `~/.gitconfig` with its commit signing.
- Every mise call runs with the scratch home as its working directory. mise reads config from every directory between the filesystem root and the current one, and with `HOME` faked the real home is just another parent. Measured on 2026-11-11: from the repository, `mise config ls` under the environment above listed this Mac's real `~/.config/mise/conf.d/*.toml` (packages, macOS defaults, the sudo file); from the scratch home it listed nothing. `MISE_CEILING_PATHS` set to the scratch folder did not stop it. A `mise bootstrap` started from the repository would have applied the real config to the real machine.
- The fixture project declares only `[dotfiles]` entries and files. It declares no packages, no tools, no macOS defaults, no login shell, no task and no `[bootstrap.services]`, so a real `mise bootstrap` inside the scratch home installs nothing and registers no LaunchAgent. mise's history watcher is a LaunchAgent only when a config declares `[bootstrap.services.mise-history]` (https://mise.jdx.dev/dotfiles/history.html); the harness never declares it and never runs `mise dot watch`.
- No network. The project and the origin are local Git repositories. `--from` is documented as taking a Git URL, so the harness passes `file://$project`. `--adopt` and `mise dot origin set` are documented as taking local paths.
- The harness does not pre-trust the fixture (`MISE_TRUSTED_CONFIG_PATHS` stays unset), because whether a later command in the checkout needs trust is one of the things a stranger would hit.
- Where it runs (owner's decision, 2026-11-11): the probes run in the UTM guest `macOS`, started with "Run without saving changes". The harness is written and its guards are checked on the owner's Mac (Task 2, which runs no `mise bootstrap` beyond the stub probes), then `probe.sh` is copied to the guest through the shared folder, run there, and `results.txt` is copied back to the host. The guest needs git and mise at the floor or newer for that run: `xcode-select --install`, then mise's installer (`curl -fsSL https://mise.run | sh`), both inside the disposable run. The isolation rules above still apply in the guest, so the same script is safe in either place. Task 1 runs on the owner's Mac: it is a script and its self-check.
- The owner runs the steps inside the guest. An agent session on the host cannot reach it.
- So in Tasks 3 to 5, every "Run: bash …/probe.sh <numbers>" step is run in the guest, not on the host: copy the current `probe.sh` in, run those numbers, and bring the `PROBE` lines back. Expect more than one round trip per task. A probe that prints `ERROR` because of a mistake in the harness is fixed on the host and rerun in the guest; one that prints `ERROR` because mise lacks the feature is a result. On the host, Tasks 3 to 5 may run only `bash -n` and `shellcheck` on the script.
- Never run `./setup.sh`, `sysup`, or `mise bootstrap` against the real home. Never edit `config.local.toml` or `config.override.toml`.
- The Claude Code ask rule is `Bash(mise bootstrap*)`. It does not match `bash …/probe.sh`, so one approval of the harness covers every bootstrap inside it. The harness's own guards are therefore the only check: Task 2's `config ls` self-check must pass before any probe that runs `mise bootstrap` is written or run.
- mise checks for a newer release when it starts, so "no network" means no network the probes depend on.
- The tracked Claude Code default model is `opus` (spec, decision 5).
- The commit hook runs `pnpm check` on the tree as it is before the command starts. Edit and commit in separate Bash calls.

## Review Focus

- A Mac whose live `settings.json` has no `model` at all: `save` must still write the tracked `opus`, not drop the key. Pinned in Task 1.
- A first `save` on a Mac with no tracked settings file yet: there is no tracked model to keep, so the Mac's model is written. Pinned in Task 1.
- A harness run interrupted halfway: the next run must start from an empty scratch folder, not reuse a half-built one. Pinned in Task 2.
- A probe whose mise command fails: it must print `PROBE <n> ERROR <exit code>` and the harness must go on to the next probe, because a missing feature is itself an answer. Pinned in Task 2.
- A harness started with any scratch variable unset, or from a directory outside the scratch folder: it must refuse to run a mise command. Pinned in Task 2.
- A harness run from inside the repository: mise must load nothing from the real home. Pinned in Task 2.

---

## File Structure

- `bin/claude-config`: `save_settings` keeps the tracked `model`.
- `bin/lib/test-claude-config`: four new checks.
- `docs/claude-config.md`, `settings/registry.toml`, `agents/README.md`, `.claude/rules/claude-config.md`: say that `save` does not record the model.
- `docs/superpowers/specs/2026-11-11-installable-probe/probe.sh`: the harness and the ten probes. It lives beside the spec, like `specs/completed/2026-10-09-mods-probe/`, because it is evidence for the spec and not part of the product.
- `docs/superpowers/specs/2026-11-11-installable-probe/results.txt`: the `PROBE` lines from the run, committed.
- `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`: its "Not verified" table becomes "Verified facts".

---

### Task 1: `claude-config save` keeps the tracked model

**Files:**

- Modify: `bin/claude-config` (`save_settings`, near line 214)
- Modify: `bin/lib/test-claude-config` (after the "cert store kept" check)
- Modify: `docs/claude-config.md` (the `agents/claude-settings.json` row of "The three tracked files")
- Modify: `settings/registry.toml` (the help text of the setting whose `key` starts `claude:`)
- Modify: `agents/README.md` (the bullet that starts "After installing or removing plugins or skills")
- Modify: `.claude/rules/claude-config.md` (the sentence that ends "changes only through `claude-config save`.")

**Interfaces:**

- Consumes: `settings_base` (`$CLAUDE_CONFIG_SAVE_DIR/claude-settings.json`), `settings` (`$CLAUDE_CONFIG_DIR/settings.json`), the test's `check` and `cc` helpers.
- Produces: nothing later tasks use.

- [ ] **Step 1: Write the failing tests**

Add after the "cert store kept" check. `base` is the tracked file. The block puts both files back as it found them, because the checks after it compare against them.

```bash
base="$CLAUDE_CONFIG_SAVE_DIR/claude-settings.json"
cp "$base" "$tmp/base.keep"
cp "$CLAUDE_CONFIG_DIR/settings.json" "$tmp/live.keep"
printf '{"model":"opus","theme":"dark"}' > "$base"
printf '{"model":"fable","theme":"light"}' > "$CLAUDE_CONFIG_DIR/settings.json"
cc save settings > /dev/null 2>&1
check "save keeps the tracked model" "[ \"\$(jq -r .model '$base')\" = opus ]"
check "save still records other settings" "[ \"\$(jq -r .theme '$base')\" = light ]"
printf '{"theme":"light"}' > "$CLAUDE_CONFIG_DIR/settings.json"
cc save settings > /dev/null 2>&1
check "save keeps the tracked model when the Mac has none" "[ \"\$(jq -r .model '$base')\" = opus ]"
rm "$base"
printf '{"model":"fable"}' > "$CLAUDE_CONFIG_DIR/settings.json"
cc save settings > /dev/null 2>&1
check "first save records the Mac's model" "[ \"\$(jq -r .model '$base')\" = fable ]"
cp "$tmp/base.keep" "$base"
cp "$tmp/live.keep" "$CLAUDE_CONFIG_DIR/settings.json"
```

- [ ] **Step 2: Run to see them fail**

Run: `bash bin/lib/test-claude-config`
Expected: `FAIL save keeps the tracked model` and `FAIL save keeps the tracked model when the Mac has none`. The other two pass already.

- [ ] **Step 3: Implement in `save_settings`**

Read the tracked file's `model` before the `jq` call and pass it with `--arg model`. The script runs under `set -euo pipefail` and the tracked file is missing on a first save, so the read is exactly `model=$(jq -r '.model // empty' "$settings_base" 2> /dev/null || true)`. After `$settings_filter`, add `| if $model != "" then .model = $model else . end`. Add one comment line above it: the tracked model is the standard for every Mac, so one Mac's choice never replaces it.

- [ ] **Step 4: Run to see them pass**

Run: `bash bin/lib/test-claude-config`
Expected: every line starts `ok`, under each bash it lists.

- [ ] **Step 5: Check this Mac**

Run: `claude-config save settings && git diff agents/claude-settings.json`
Expected: no `model` line in the diff. This Mac's live model is `fable` and the tracked one is `opus`. Any other line in the diff is a real difference between this Mac and the repo: show it to the owner and revert it with `git checkout agents/claude-settings.json` unless they want it saved.

- [ ] **Step 6: Document, gate, commit**

In `docs/claude-config.md` add to the `agents/claude-settings.json` row: "`model` is not recorded: `save` keeps the tracked value, so change the standard by editing the file." In `settings/registry.toml`, the Claude Code default model help text holds the sentence `claude-config save copies a change into the repo.` (no backticks in the file). Replace it with `claude-config save never changes the tracked model.` In `agents/README.md`, the bullet says a default model changed in `dotfiles-settings` is marked as drift "until `save` records it or Reset puts the tracked value back": change it to say `save` never records the model, so the drift lasts until Reset or an edit to `agents/claude-settings.json`. In `.claude/rules/claude-config.md`, replace "changes only through `claude-config save`" with "changes only by editing that file: `claude-config save` keeps the tracked model".

Run: `pnpm check`
Expected: exit 0.

```bash
git add bin/claude-config bin/lib/test-claude-config docs/claude-config.md settings/registry.toml agents/README.md .claude/rules/claude-config.md
git commit -m "Keep the tracked Claude Code model when claude-config saves"
git push
```

---

### Task 2: The probe harness

**Files:**

- Create: `docs/superpowers/specs/2026-11-11-installable-probe/probe.sh` (mode 0755)

**Interfaces:**

- Produces, for Tasks 3 to 6:
  - `scratch`: `$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-probe.XXXXXX")`, removed on exit unless `PROBE_KEEP=1`.
  - `new_home <name>`: removes `$scratch/<name>` if it exists, creates it with `home`, `data`, `config`, `state` and `cache` under it, and calls `use_home <name>`.
  - `use_home <name>`: exports `HOME`, `MISE_DATA_DIR`, `MISE_CONFIG_DIR`, `MISE_STATE_DIR`, `MISE_CACHE_DIR` to that folder's five paths, creating nothing. Probe 6 uses it to go back and forth between `mac-a` and `mac-b`.
  - `new_project`: builds the fixture project below as a fresh Git repository (`git init -b main`) with one commit and sets `project` to its path. Each call makes a new one (`$scratch/project.1`, `.2`, …).
  - `new_origin`: makes a fresh bare repository (`git init --bare -b main`) and sets `origin` to its path.
  - `g <args…>`: runs `git` under the environment in Global Constraints.
  - `m <args…>`: runs `mise` under the environment in Global Constraints with `$HOME` as its working directory (`m -C <dir> <args…>` for a command that must run in the checkout, where `<dir>` is under `$scratch`). It exits 3 with "probe: scratch home not set" when any of the five variables is empty or does not start with `$scratch`, or when the working directory it would use is not under `$scratch`.
  - `self_check`: runs `m config ls` and exits 4 with "probe: mise sees config outside the scratch folder" when any line of its output names a path that does not start with `$scratch`. `main` calls it after the first `new_home` and before any probe.
  - `answer <n> <text…>`: prints `PROBE <n> <text>`.
  - `probe <n> <function>`: runs the function in a subshell without `set -e`. When it exits non-zero, prints `PROBE <n> ERROR <code>` and returns 0. Several probes run commands that are expected to fail (an update that refuses, a pull that conflicts), so a probe function captures each exit code it cares about and returns non-zero only when it could not produce its answer.
  - `main`: runs `probe 1 probe_1` to `probe 10 probe_10` in order, or only the numbers given as arguments.

- [ ] **Step 1: Write the harness with the fixture project**

`new_project` commits these on `main`:

```toml
# mise.toml
[dotfiles]
"~/.probe/linked" = "files/linked"
"~/.probe/copied" = { source = "files/copied", mode = "copy" }
"~/.probe/seeded" = { source = "files/seeded", mode = "copy", create_if_missing = true }
```

```toml
# mise.extras.toml (a module)
[dotfiles]
"~/.probe/extra" = "files/extra"
```

```toml
# mise.work.toml (a profile)
[dotfiles]
"~/.probe/work" = "files/work"
```

and the five files under `files/`, each holding its own name. Write `probe_1` to `probe_10` as functions that only call `answer <n> not-written`.

- [ ] **Step 2: Check the three harness guards**

Run: `bash docs/superpowers/specs/2026-11-11-installable-probe/probe.sh`
Expected: ten lines, `PROBE 1 not-written` to `PROBE 10 not-written`, and exit 0.

Run: `PROBE_KEEP=1 bash docs/superpowers/specs/2026-11-11-installable-probe/probe.sh 1; ls "$TMPDIR" | grep -c dotfiles-probe`
Expected: the kept folder exists. Run it again without `PROBE_KEEP`: it builds a new folder and does not reuse the kept one. Remove the kept folder afterwards.

Run, from the repository root: `bash docs/superpowers/specs/2026-11-11-installable-probe/probe.sh 1`
Expected: exit 0 and no "outside the scratch folder" message. Then temporarily make `m` skip its change of directory and run it again from the repository root.
Expected: exit 4 with "probe: mise sees config outside the scratch folder", and no `PROBE` line. Restore it. This is the check that the measured hole in Global Constraints is closed, so do not write Task 3 until it behaves this way.

Temporarily make `probe_2` run `false`, and `probe_3` call `HOME=/tmp m --version`.
Expected: `PROBE 2 ERROR 1`, then `PROBE 3 ERROR 3` with "probe: scratch home not set" on stderr, then probes 4 to 10 still print. Restore both.

- [ ] **Step 3: Commit**

Run: `bash -n docs/superpowers/specs/2026-11-11-installable-probe/probe.sh && shellcheck --severity=warning docs/superpowers/specs/2026-11-11-installable-probe/probe.sh`
Expected: no output.

```bash
git add docs/superpowers/specs/2026-11-11-installable-probe/probe.sh
git commit -m "Add the probe harness for the installable-setup spec"
```

---

### Task 3: Probes 1 to 3, install from a repository

**Files:**

- Modify: `docs/superpowers/specs/2026-11-11-installable-probe/probe.sh`

**Interfaces:**

- Consumes: `new_home`, `new_project`, `project`, `g`, `m`, `answer` from Task 2.

Each probe starts with `new_home mac-a` and `new_project`, and installs with `m bootstrap --from "file://$project"`. Each step replaces one `not-written` function. The answer text is what the spec needs, so keep the wording given.

- [ ] **Step 1: `probe_1`, the commands exist**

Run `m --version`, then `m bootstrap --help` and `m bootstrap unapply --help`. Answer: `version=<first word of --version> from=<yes|no> from-dir=<yes|no> config-dir=<yes|no> adopt=<yes|no> update=<yes|no> save-env=<yes|no> unapply=<yes|no>`, each from whether the help text names the flag or the subcommand exits 0.

- [ ] **Step 2: `probe_2`, relative sources**

Install. Answer: `checkout=<path that now holds mise.toml under $MISE_DATA_DIR, or none> linked=<readlink of ~/.probe/linked, or missing> copied=<file|symlink|missing>`. The spec's question: does `linked` point inside the checkout without any `~/dotfiles` link.

- [ ] **Step 3: `probe_3`, a shipped module list and a local override**

Add `.miserc.toml` with `env = ["extras"]` to this probe's project and commit (the dot-prefixed name is the one mise's environments page gives for a project). Install. Record whether `~/.probe/extra` exists. When it does not, move the file to `.config/miserc.toml` in the project (the other project location mise's configuration page lists), commit, start again from `new_home mac-a`, and record which name worked. Then write `env = []` to `$MISE_CONFIG_DIR/miserc.local.toml`, remove `~/.probe`, run the same command, and record again. Answer: `shipped-list=<applied|ignored> shipped-file=<.miserc.toml|.config/miserc.toml|none> local-override=<wins|loses|not-read>`. mise's configuration page ranks a project's miserc files above the global `miserc.local.toml`, so `loses` is a possible designed result, not a harness fault.

- [ ] **Step 4: Run and commit**

Run: `bash docs/superpowers/specs/2026-11-11-installable-probe/probe.sh 1 2 3`
Expected: three `PROBE` lines, none `not-written`. An `ERROR` line is a valid result: keep it.

```bash
git add docs/superpowers/specs/2026-11-11-installable-probe/probe.sh
git commit -m "Probe installing from a repository, relative sources and modules"
```

---

### Task 4: Probes 4 and 5, the user layer and updates

**Files:**

- Modify: `docs/superpowers/specs/2026-11-11-installable-probe/probe.sh`

**Interfaces:**

- Consumes: `new_home`, `new_project`, `project`, `g`, `m`, `answer`. Each probe starts with `new_home mac-a` and `new_project`.

- [ ] **Step 1: `probe_4`, cancelling one key from the user layer**

After a first install, write a user config `$MISE_CONFIG_DIR/config.toml` that tries to cancel the project's `~/.probe/linked` entry, one form per attempt: `"~/.probe/linked" = { enabled = false }` (the form mise's dotfiles reference documents), then `"~/.probe/linked" = { mode = "absent" }`. Then a third: `"~/.probe/linked" = "other"`, with a file `other` beside that user config holding the word `user`. For each, remove `~/.probe`, rerun, and record whether the file comes back; for the third, record which content the target has. Answer: `enabled-false=<cancels|ignored|error> absent=<cancels|ignored|error> winner=<user|project>`. `winner` comes from the third attempt. This uses a dotfile key because the fixture has no packages. The package form is measured in P2 with a dry run against the real package list.

- [ ] **Step 2: `probe_5`, updates with a dirty checkout**

After a first install, make three changes in turn, each followed by a new upstream commit in `$project` and `m bootstrap --from "file://$project" --update`:

1. Append a line to the installed `~/.probe/copied` and to `~/.probe/seeded`. Upstream changes `files/copied` and `files/seeded`.
2. Append a line through the symlink `~/.probe/linked`. Upstream changes `files/extra`, a different file.
3. Leave change 2 in place. Upstream changes `files/linked`, the same file.

For each change, `updates` means the checkout's `HEAD` equals `$project`'s `HEAD` after the command, whatever its exit code, and `refuses` means it does not. Also record the three exit codes. Answer: `exit-codes=<a,b,c> copy-edit=<updates|refuses> symlink-edit-other-file=<updates|refuses> symlink-edit-same-file=<updates|refuses> copy-target-after=<kept-user-edit|overwritten> seeded-target-after=<kept-user-edit|overwritten>`.

- [ ] **Step 3: Run and commit**

Run: `bash docs/superpowers/specs/2026-11-11-installable-probe/probe.sh 4 5`
Expected: two `PROBE` lines, none `not-written`.

```bash
git add docs/superpowers/specs/2026-11-11-installable-probe/probe.sh
git commit -m "Probe the user layer and updates over a dirty checkout"
```

---

### Task 5: Probes 6 to 10, sync, profiles, removal, the config-dir shape and a dev clone

**Files:**

- Modify: `docs/superpowers/specs/2026-11-11-installable-probe/probe.sh`

**Interfaces:**

- Consumes: `new_home`, `new_project`, `new_origin`, `project`, `origin`, `g`, `m`, `answer`.

- [ ] **Step 1: `probe_6`, sync between two homes**

`new_home mac-a` and `new_origin`. In this probe only, `MISE_CONFIG_DIR` is `$HOME/.config/mise` in both homes (the harness's `sync_home`), as on a real Mac: with the config dir beside the home, a tracked path would be mac-a's absolute path and mean nothing in mac-b. Create `$MISE_CONFIG_DIR/config.toml` with the comment `# shared-marker` and `$MISE_CONFIG_DIR/config.local.toml` with the comment `# local-marker`. Run `m dot track "$MISE_CONFIG_DIR"`, `m dot save`, `m dot origin set "$origin" --sync manual`, `m dot sync`. Then `new_home mac-b` and `m bootstrap --adopt "$origin"`. Record whether `# shared-marker` and `# local-marker` are anywhere under mac-b's `$MISE_CONFIG_DIR`. The markers matter: `mise dot origin set` writes its connection into `config.local.toml`, so that file exists on both sides either way. Then edit `config.toml` differently in both homes (`use_home` to switch), save and sync in `mac-a`, then save, sync and pull in `mac-b`. Answer: `shared=<arrived|missing> local-toml=<stayed|leaked> conflict=<paused|overwrote-b|overwrote-a> conflicts-cmd=<lists-file|empty|error>`, the last from `m dot conflicts`.

- [ ] **Step 2: `probe_7`, a saved profile**

`new_home mac-a` and `new_project`. Run `m -E work bootstrap --from "file://$project" --save-env`, then remove `~/.probe` and run `m bootstrap --from "file://$project"` with no `-E`. Answer: `work-first-run=<applied|ignored> remembered=<yes|no> saved-in=<file under $MISE_CONFIG_DIR that now names work, or none>`.

- [ ] **Step 3: `probe_8`, removing a module**

`new_home mac-a` and `new_project`. Run `m -E extras bootstrap --from "file://$project"`, confirm `~/.probe/extra` exists, then run `m -C <checkout> bootstrap unapply extras`. When that fails, record its output and try `m -C <checkout> -E extras bootstrap unapply extras` (`bootstrap unapply` has no `--from` on 2026.11.5, read from `mise usage`). Answer: `extra=<removed|kept|untested> linked=<kept|removed|untested> ran-from=<checkout|checkout-with-env|neither> first-error=<none|untrusted|other>`. `untested` is for a run where neither command worked. `untrusted` is for a failure whose message names trust.

- [ ] **Step 4: `probe_9`, the config-dir shape**

`new_home mac-a` and `new_project`. Add a folder `cfg/` to this probe's project holding `config.toml` with one `[dotfiles]` entry, `"~/.probe/from-cfg" = "../files/linked"`, and commit. Remove the empty `$MISE_CONFIG_DIR` folder, then run `m bootstrap --from "file://$project" --config-dir cfg`. Record what `$MISE_CONFIG_DIR` is now. Write `$MISE_CONFIG_DIR/config.local.toml` with one comment line, make an upstream commit that changes `files/extra`, and run the same command with `--update`. Answer: `config-dir=<symlink-into-checkout|real-dir|error> from-cfg=<applied|missing> local-toml-in-checkout=<yes|no> update-with-local-toml=<updates|refuses>`. `local-toml-in-checkout` is whether `git status --porcelain` in the checkout lists the file.

- [ ] **Step 5: `probe_10`, a dev clone as the checkout**

`new_home mac-a` and `new_project`. Make a second branch `stable` in the project at its first commit, then add one more commit on `main`. Clone the project to `$scratch/clone` with `g clone`, so the clone is on `main` with `origin` set to the project. In the clone, append a line to `files/linked` and leave it uncommitted. Run `m bootstrap --from "file://$project?ref=stable" --from-dir "$scratch/clone"`, record the clone's branch and whether the edit is still there, then add an upstream commit on `stable` and run the same command with `--update`. Answer: `applied=<yes|no|error> branch-after-install=<main|stable|detached> edit-after-install=<kept|lost> branch-after-update=<main|stable|detached> edit-after-update=<kept|lost> update-exit=<code>`. This is the owner's Mac in miniature: a working clone on `main` with local edits, asked to follow `stable`.

- [ ] **Step 6: Run and commit**

Run: `bash docs/superpowers/specs/2026-11-11-installable-probe/probe.sh 6 7 8 9 10`
Expected: five `PROBE` lines, none `not-written`.

```bash
git add docs/superpowers/specs/2026-11-11-installable-probe/probe.sh
git commit -m "Probe sync, saved profiles, module removal, the config-dir shape and a dev clone"
```

---

### Task 6: Record the results and decide

**Files:**

- Create: `docs/superpowers/specs/2026-11-11-installable-probe/results.txt`
- Modify: `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`

**Interfaces:**

- Consumes: the ten `PROBE` lines.

- [ ] **Step 1: Run everything once and keep the output**

In the guest, from the folder `probe.sh` was copied to, run: `bash probe.sh 2> probe.err | grep '^PROBE ' > results.txt; cat results.txt`. Copy `results.txt` (and `probe.err` if any line says `ERROR`) to the shared folder, then on the host save it as `docs/superpowers/specs/2026-11-11-installable-probe/results.txt`.
Expected: exactly ten lines, each starting `PROBE`. The first names the mise version. Only the answer lines are committed: mise's own output holds temp paths that differ on every run.

- [ ] **Step 2: Rewrite the spec's table**

Rename "Not verified, and the check that settles each" to "Verified facts" and replace each row's Check cell with the measured answer and the date. A row whose probe printed `ERROR` stays in a short "Still not verified" table with what would settle it. The spec's row about cancelling one package or tool key stays there too, pointing at P2's first task: probe 4 measures a dotfile key only.

- [ ] **Step 3: Apply the decision rules to the Design section**

| Result | Change to the spec |
| --- | --- |
| Probe 1: a flag or subcommand is `no` | Global Constraints in every later plan raise the mise floor to the first version that has it (`setup/mise-floor.sh`, with `bin/lib/test-override-env` and the `check.yml` version), or the design drops what needs it |
| Probe 2: `linked` points inside the checkout | Distribution drops the `~/dotfiles` link for installed mode |
| Probe 2: it does not | Distribution keeps a `~/dotfiles` link to the checkout, made by the install command |
| Probe 3: `shipped-list=ignored` under both file names | Opt-outs cannot ship a default list. The install command passes the full module list with `-E` and `--save-env`, if probe 7 says that is remembered |
| Probe 3: `local-override=wins` | Opt-outs use `miserc.local.toml` as written |
| Probe 3: `local-override=loses` or `not-read` | A user cannot turn a module off from their own config dir. Opt-outs need the install to write the list (probe 7's `remembered=yes`), and without that the fallback deny list. `--save-env` is not a fallback by itself: it writes the same `miserc.local.toml` that just lost |
| Probe 4: a form cancels | Opt-outs name that form for single dotfile entries. Packages and tools stay unverified until P2 |
| Probe 4: none cancels | Opt-outs use the deny list for single items, and say so |
| Probe 4: `winner=project` | The user layer cannot override our dotfile entries. Target says so, and P2 gives the base a hook for user overrides |
| Probe 5: every case `updates` and `copy-target-after=kept-user-edit` | No change beyond recording it |
| Probe 5: any `refuses` | Distribution lists which entries must deploy as `copy`, and P1 gets a task that finds every app-written target |
| Probe 5: `copy-target-after=overwritten` and `seeded-target-after=kept-user-edit` | Distribution keeps its rule: app-written files are `create_if_missing` or `merge` entries, never plain copies |
| Probe 5: `seeded-target-after=overwritten` | Distribution drops `create_if_missing` and P1 tests `merge` edits and `track` for those files |
| Probe 6: `local-toml=leaked` or `conflict=overwrote-*` | Sync gets an explicit exclude step and stays manual-only |
| Probe 6: `shared=missing` or `conflicts-cmd=error` | Sync is not designable from this probe. P3's first task repeats it in the VM against a real private repository before anything else |
| Probe 7: `remembered=no` | Profiles store the choice themselves and pass `-E` on every run |
| Probe 8: `first-error=untrusted` | Distribution says which commands need `mise trust` on the checkout, and P1 decides whether the install command trusts it |
| Probe 9: `config-dir=symlink-into-checkout` and `update-with-local-toml=updates` | Distribution may choose the config-dir shape. The spec states what that costs the user layer |
| Probe 9: anything else | Distribution chooses the project shape |
| Probe 10: both branches stay `main` and both edits are `kept` | Decision 7 stands: the owner's Mac can use `--from-dir` on the dev clone once the VM proof passes |
| Probe 10: a branch moves, an edit is `lost`, or `applied` is not `yes` | Decision 7 changes: the owner's Mac keeps `setup.sh` from the clone, and the spec says installed mode is proven in the VM only. Tell the owner before anything else |
| Probe 8: `linked=removed` | Opt-outs must not offer removal: unapply takes more than the module |
| Probe 8: `ran-from=checkout-with-env` or `neither` | Opt-outs record the command that works, or that there is none |
| Probe 8: `extra=kept` | Opt-outs say turning a module off stops future installs and removes nothing |

- [ ] **Step 4: Commit and stop for review**

```bash
git add docs/superpowers/specs/2026-11-11-installable-probe/results.txt docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md
git commit -m "Record the probe results in the installable-setup spec"
git push
```

Then ask the owner to review the updated spec. P1 and P2 are written only after that. A probe that printed `ERROR` blocks the plan that waits on it (the spec's phase briefs name which) until it is rerun or the owner accepts the gap in writing in the spec.
