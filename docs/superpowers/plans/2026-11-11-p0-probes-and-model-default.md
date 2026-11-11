# P0: Probes and the Model Default Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure the nine mise behaviours the installable-setup design rests on, in a scratch home, and stop `claude-config save` from replacing the tracked `opus` model with one Mac's choice.

**Architecture:** One committed harness script builds a throwaway home, a small fixture bootstrap project in a local Git repository and a bare repository that stands in for the user's private GitHub repository. Every probe gets a fresh copy of each, so no probe sees what another left behind. Each probe is a function in that script that runs real mise commands against the fixtures and prints one `PROBE <n> <answer>` line. The answers are copied into the spec, which then decides P1 to P4.

**Tech Stack:** bash 3.2 (`#!/bin/bash`), mise 2026.11.5 or newer, git, `/usr/bin/jq`.

**Spec:** `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`. Read "Not verified, and the check that settles each" first: each probe here answers one row of that table.

## Global Constraints

- macOS only.
- mise floor: 2026.11.5 (`setup/mise-floor.sh`). The probes report the version they ran on.
- No probe touches the real home. Every mise and git call in the harness runs through `env -i` with only these set: `PATH`, `TERM=dumb`, `MISE_YES=1`, `HOME`, `MISE_DATA_DIR`, `MISE_CONFIG_DIR`, `MISE_STATE_DIR` and `MISE_CACHE_DIR` (all under the scratch folder), `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, and `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, `GIT_COMMITTER_EMAIL` set to `probe` and `probe@example.invalid`. That keeps out the caller's `MISE_ENV`, tokens and shell activation, and the real `~/.gitconfig` with its commit signing.
- The fixture project declares only `[dotfiles]` entries and files. It declares no packages, no tools, no macOS defaults, no login shell, no task and no `[bootstrap.services]`, so a real `mise bootstrap` inside the scratch home installs nothing and registers no LaunchAgent. mise's history watcher is a LaunchAgent only when a config declares `[bootstrap.services.mise-history]` (https://mise.jdx.dev/dotfiles/history.html); the harness never declares it and never runs `mise dot watch`.
- No network. The project and the origin are local Git repositories. `--from` is documented as taking a Git URL, so the harness passes `file://$project`. `--adopt` and `mise dot origin set` are documented as taking local paths.
- The harness does not pre-trust the fixture (`MISE_TRUSTED_CONFIG_PATHS` stays unset), because whether a later command in the checkout needs trust is one of the things a stranger would hit.
- Where it runs: the harness is safe on the owner's Mac by the isolation above, and the macOS VM is the preferred place when it is available, because there a mistake in that isolation costs nothing. In the VM it needs only git and mise at the floor or newer; copy `probe.sh` in, run it, and copy `results.txt` back. Task 1 runs on the owner's Mac either way: it is a script and its self-check.
- Never run `./setup.sh`, `sysup`, or `mise bootstrap` against the real home. Never edit `config.local.toml` or `config.override.toml`.
- In Claude Code, every `mise bootstrap` command asks first, dry runs too. The owner approves each, or runs the harness from their own terminal.
- The tracked Claude Code default model is `opus` (spec, decision 5).
- The commit hook runs `pnpm check` on the tree as it is before the command starts. Edit and commit in separate Bash calls.

## Review Focus

- A Mac whose live `settings.json` has no `model` at all: `save` must still write the tracked `opus`, not drop the key. Pinned in Task 1.
- A first `save` on a Mac with no tracked settings file yet: there is no tracked model to keep, so the Mac's model is written. Pinned in Task 1.
- A harness run interrupted halfway: the next run must start from an empty scratch folder, not reuse a half-built one. Pinned in Task 2.
- A probe whose mise command fails: it must print `PROBE <n> ERROR <exit code>` and the harness must go on to the next probe, because a missing feature is itself an answer. Pinned in Task 2.
- A harness started with the scratch variables unset: it must refuse to run a mise command. Pinned in Task 2.

---

## File Structure

- `bin/claude-config`: `save_settings` keeps the tracked `model`.
- `bin/lib/test-claude-config`: three new cases.
- `docs/claude-config.md`, `settings/registry.toml`: say that `save` does not record the model.
- `docs/superpowers/specs/2026-11-11-installable-probe/probe.sh`: the harness and the nine probes. It lives beside the spec, like `specs/completed/2026-10-09-mods-probe/`, because it is evidence for the spec and not part of the product.
- `docs/superpowers/specs/2026-11-11-installable-probe/results.txt`: the `PROBE` lines from the run, committed.
- `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`: its "Not verified" table becomes "Verified facts".

---

### Task 1: `claude-config save` keeps the tracked model

**Files:**

- Modify: `bin/claude-config` (`save_settings`, near line 214)
- Modify: `bin/lib/test-claude-config` (after the "cert store kept" check)
- Modify: `docs/claude-config.md` (the `agents/claude-settings.json` row of "The three tracked files")
- Modify: `settings/registry.toml` (the help text of the setting whose `key` starts `claude:`)

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

Read the tracked file's `model` before the `jq` call (empty when the file is missing or has none) and pass it with `--arg model`. After `$settings_filter`, add `| if $model != "" then .model = $model else . end`. Add one comment line above it: the tracked model is the standard for every Mac, so one Mac's choice never replaces it.

- [ ] **Step 4: Run to see them pass**

Run: `bash bin/lib/test-claude-config`
Expected: every line starts `ok`, under each bash it lists.

- [ ] **Step 5: Check this Mac**

Run: `claude-config save settings && git diff agents/claude-settings.json`
Expected: no `model` line in the diff. This Mac's live model is `fable` and the tracked one is `opus`. Any other line in the diff is a real difference between this Mac and the repo: show it to the owner and revert it with `git checkout agents/claude-settings.json` unless they want it saved.

- [ ] **Step 6: Document, gate, commit**

In `docs/claude-config.md` add to the `agents/claude-settings.json` row: "`model` is not recorded: `save` keeps the tracked value, so change the standard by editing the file." In `settings/registry.toml`, the Claude Code default model help text says "`claude-config save` copies a change into the repo." Replace that sentence with "`claude-config save` never changes the tracked model."

Run: `pnpm check`
Expected: exit 0.

```bash
git add bin/claude-config bin/lib/test-claude-config docs/claude-config.md settings/registry.toml
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
  - `new_home <name>`: creates `$scratch/<name>` with `home`, `data`, `config`, `state` and `cache` under it, and exports `HOME`, `MISE_DATA_DIR`, `MISE_CONFIG_DIR`, `MISE_STATE_DIR`, `MISE_CACHE_DIR` to them. Probe 6 calls it twice, as `mac-a` and `mac-b`.
  - `new_project`: builds the fixture project below as a fresh Git repository with one commit on `main` and sets `project` to its path. Each call makes a new one (`$scratch/project.1`, `.2`, …).
  - `new_origin`: makes a fresh bare repository and sets `origin` to its path.
  - `g <args…>`: runs `git` under the environment in Global Constraints.
  - `m <args…>`: runs `mise` under the environment in Global Constraints, and exits 3 with "probe: scratch home not set" when `HOME` does not start with `$scratch`.
  - `answer <n> <text…>`: prints `PROBE <n> <text>`.
  - `probe <n> <function>`: runs the function in a subshell. When it exits non-zero, prints `PROBE <n> ERROR <code>` and returns 0.
  - `main`: runs `probe 1 probe_1` to `probe 9 probe_9` in order, or only the numbers given as arguments.

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

and the five files under `files/`, each holding its own name. Write `probe_1` to `probe_9` as functions that only call `answer <n> not-written`.

- [ ] **Step 2: Check the three harness guards**

Run: `bash docs/superpowers/specs/2026-11-11-installable-probe/probe.sh`
Expected: nine lines, `PROBE 1 not-written` to `PROBE 9 not-written`, and exit 0.

Run: `PROBE_KEEP=1 bash docs/superpowers/specs/2026-11-11-installable-probe/probe.sh 1; ls "$TMPDIR" | grep -c dotfiles-probe`
Expected: the kept folder exists. Run it again without `PROBE_KEEP`: it builds a new folder and does not reuse the kept one.

Temporarily make `probe_2` run `false`, and `probe_3` call `HOME=/tmp m --version`.
Expected: `PROBE 2 ERROR 1`, then `PROBE 3 ERROR 3` with "probe: scratch home not set" on stderr, then probes 4 to 9 still print. Restore both.

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

Run `m --version`, then `m bootstrap --help` and `m bootstrap unapply --help`. Answer: `version=<first word of --version> from=<yes|no> adopt=<yes|no> update=<yes|no> unapply=<yes|no>`, each from whether the help text names the flag or the subcommand exits 0.

- [ ] **Step 2: `probe_2`, relative sources**

Install. Answer: `checkout=<path that now holds mise.toml under $MISE_DATA_DIR, or none> linked=<readlink of ~/.probe/linked, or missing> copied=<file|symlink|missing>`. The spec's question: does `linked` point inside the checkout without any `~/dotfiles` link.

- [ ] **Step 3: `probe_3`, a shipped module list and a local override**

Add `.miserc.toml` with `env = ["extras"]` to this probe's project and commit (the dot-prefixed name is the one mise's environments page gives for a project). Install. Record whether `~/.probe/extra` exists. Then write `env = []` to `$MISE_CONFIG_DIR/miserc.local.toml`, remove `~/.probe`, run the same command, and record again. Answer: `shipped-list=<applied|ignored> local-override=<wins|loses|not-read>`.

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

After a first install, write a user config `$MISE_CONFIG_DIR/config.toml` that tries to cancel the project's `~/.probe/linked` entry, one form per attempt: `"~/.probe/linked" = { enabled = false }` (the form mise's dotfiles reference documents), then `"~/.probe/linked" = { mode = "absent" }`. For each, remove `~/.probe`, rerun, and record whether the file comes back. Answer: `enabled-false=<cancels|ignored|error> absent=<cancels|ignored|error> winner=<user|project>`. `winner` is which config's value applies when both declare the same key with different sources. This uses a dotfile key because the fixture has no packages. The package form is measured in P2 with a dry run against the real package list.

- [ ] **Step 2: `probe_5`, updates with a dirty checkout**

After a first install, make three changes in turn, each followed by a new upstream commit in `$project` and `m bootstrap --from "file://$project" --update`:

1. Append a line to the installed `~/.probe/copied` and to `~/.probe/seeded`. Upstream changes `files/copied` and `files/seeded`.
2. Append a line through the symlink `~/.probe/linked`. Upstream changes `files/extra`, a different file.
3. Leave change 2 in place. Upstream changes `files/linked`, the same file.

Answer: `copy-edit=<updates|refuses> symlink-edit-other-file=<updates|refuses> symlink-edit-same-file=<updates|refuses> copy-target-after=<kept-user-edit|overwritten> seeded-target-after=<kept-user-edit|overwritten>`.

- [ ] **Step 3: Run and commit**

Run: `bash docs/superpowers/specs/2026-11-11-installable-probe/probe.sh 4 5`
Expected: two `PROBE` lines, none `not-written`.

```bash
git add docs/superpowers/specs/2026-11-11-installable-probe/probe.sh
git commit -m "Probe the user layer and updates over a dirty checkout"
```

---

### Task 5: Probes 6 to 9, sync, profiles, removal and the config-dir shape

**Files:**

- Modify: `docs/superpowers/specs/2026-11-11-installable-probe/probe.sh`

**Interfaces:**

- Consumes: `new_home`, `new_project`, `new_origin`, `project`, `origin`, `g`, `m`, `answer`.

- [ ] **Step 1: `probe_6`, sync between two homes**

`new_home mac-a` and `new_origin`. Create `$MISE_CONFIG_DIR/config.toml` and `$MISE_CONFIG_DIR/config.local.toml`, each with one comment line. Run `m dot track "$MISE_CONFIG_DIR"`, `m dot save`, `m dot origin set "$origin" --sync manual`, `m dot sync`. Then `new_home mac-b` and `m bootstrap --adopt "$origin"`. Record which of the two files arrived. Then edit `config.toml` differently in both homes, save and sync in `mac-a`, then save, sync and pull in `mac-b`. Answer: `shared=<arrived|missing> local-toml=<stayed|leaked> conflict=<paused|overwrote-b|overwrote-a> conflicts-cmd=<lists-file|empty|error>`, the last from `m dot conflicts`.

- [ ] **Step 2: `probe_7`, a saved profile**

`new_home mac-a` and `new_project`. Run `m -E work bootstrap --from "file://$project" --save-env`, then remove `~/.probe` and run `m bootstrap --from "file://$project"` with no `-E`. Answer: `work-first-run=<applied|ignored> remembered=<yes|no> saved-in=<file under $MISE_CONFIG_DIR that now names work, or none>`.

- [ ] **Step 3: `probe_8`, removing a module**

`new_home mac-a` and `new_project`. Run `m -E extras bootstrap --from "file://$project"`, confirm `~/.probe/extra` exists, then run `m bootstrap unapply extras` from the checkout directory. Answer: `extra=<removed|kept> linked=<kept|removed> ran-from=<checkout|untrusted|error>`. `untrusted` is for a failure whose message names trust.

- [ ] **Step 4: `probe_9`, the config-dir shape**

`new_home mac-a` and `new_project`. Add a folder `cfg/` to this probe's project holding `config.toml` with one `[dotfiles]` entry, `"~/.probe/from-cfg" = "../files/linked"`, and commit. Remove the empty `$MISE_CONFIG_DIR` folder, then run `m bootstrap --from "file://$project" --config-dir cfg`. Record what `$MISE_CONFIG_DIR` is now. Write `$MISE_CONFIG_DIR/config.local.toml` with one comment line, make an upstream commit that changes `files/extra`, and run the same command with `--update`. Answer: `config-dir=<symlink-into-checkout|real-dir|error> from-cfg=<applied|missing> local-toml-in-checkout=<yes|no> update-with-local-toml=<updates|refuses>`. `local-toml-in-checkout` is whether `git status --porcelain` in the checkout lists the file.

- [ ] **Step 5: Run and commit**

Run: `bash docs/superpowers/specs/2026-11-11-installable-probe/probe.sh 6 7 8 9`
Expected: four `PROBE` lines, none `not-written`.

```bash
git add docs/superpowers/specs/2026-11-11-installable-probe/probe.sh
git commit -m "Probe sync, saved profiles, module removal and the config-dir shape"
```

---

### Task 6: Record the results and decide

**Files:**

- Create: `docs/superpowers/specs/2026-11-11-installable-probe/results.txt`
- Modify: `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`

**Interfaces:**

- Consumes: the nine `PROBE` lines.

- [ ] **Step 1: Run everything once and keep the output**

Run: `bash docs/superpowers/specs/2026-11-11-installable-probe/probe.sh > docs/superpowers/specs/2026-11-11-installable-probe/results.txt 2>&1; cat docs/superpowers/specs/2026-11-11-installable-probe/results.txt`
Expected: nine `PROBE` lines. The first names the mise version.

- [ ] **Step 2: Rewrite the spec's table**

Rename "Not verified, and the check that settles each" to "Verified facts" and replace each row's Check cell with the measured answer and the date. A row whose probe printed `ERROR` stays in a short "Still not verified" table with what would settle it.

- [ ] **Step 3: Apply the decision rules to the Design section**

| Result | Change to the spec |
| --- | --- |
| Probe 1: a flag or subcommand is `no` | Global Constraints in every later plan raise the mise floor to the first version that has it (`setup/mise-floor.sh`, with `bin/lib/test-override-env` and the `check.yml` version), or the design drops what needs it |
| Probe 2: `linked` points inside the checkout | Distribution drops the `~/dotfiles` link for installed mode |
| Probe 2: it does not | Distribution keeps a `~/dotfiles` link to the checkout, made by the install command |
| Probe 3: `local-override=wins` | Opt-outs use `miserc.local.toml` as written |
| Probe 3: anything else | Opt-outs use `-E` with `--save-env` (probe 7), or the fallback deny list |
| Probe 4: a form cancels | Opt-outs name that form for single items |
| Probe 4: none cancels | Opt-outs use the deny list for single items, and say so |
| Probe 5: any `refuses` | Distribution lists which entries must deploy as `copy`, and P1 gets a task that finds every app-written target |
| Probe 5: `copy-target-after=overwritten` and `seeded-target-after=kept-user-edit` | Distribution keeps its rule: app-written files are `create_if_missing` or `merge` entries, never plain copies |
| Probe 5: `seeded-target-after=overwritten` | Distribution drops `create_if_missing` and P1 tests `merge` edits and `track` for those files |
| Probe 6: `local-toml=leaked` or `conflict=overwrote-*` | Sync gets an explicit exclude step and stays manual-only |
| Probe 7: `remembered=no` | Profiles store the choice themselves and pass `-E` on every run |
| Probe 8: `ran-from=untrusted` | Distribution says which commands need `mise trust` on the checkout, and P1 decides whether the install command trusts it |
| Probe 9: `config-dir=symlink-into-checkout` and `update-with-local-toml=updates` | Distribution may choose the config-dir shape. The spec states what that costs the user layer |
| Probe 9: anything else | Distribution chooses the project shape |
| Probe 8: `extra=kept` | Opt-outs say turning a module off stops future installs and removes nothing |

- [ ] **Step 4: Commit and stop for review**

```bash
git add docs/superpowers/specs/2026-11-11-installable-probe/results.txt docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md
git commit -m "Record the probe results in the installable-setup spec"
git push
```

Then ask the owner to review the spec and answer its three open points. P1 and P2 are written only after that.
