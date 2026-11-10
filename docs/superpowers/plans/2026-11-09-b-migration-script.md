# Migration Script (Part B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `migrate/legacy-to-mise` moves a Mac set up by the old bash and Brewfile method onto the mise-first method, one step per Part A phase, and is deleted on or after 2027-02-28.

**Architecture:** One standalone bash script with five steps (`env`, `macos`, `packages`, `dotfiles`, `setup`). It is the only file that knows the old layout, and it carries that knowledge as literals because Part A deletes the old scripts. It reads state through mise's JSON output and macOS's `/usr/bin/jq`, changes things only after a prompt, and moves what it replaces into a timestamped backup folder with a restore command per item. One self-check, `bin/lib/test-migrate`, runs every step against a scratch `HOME` with fake `brew`, `mise` and `claude` on `PATH`.

**Tech Stack:** bash 3.2 (`#!/bin/bash`), `/usr/bin/jq` (ships with macOS, 1.7.1 on this Mac), mise 2026.11.5 or newer, shellcheck, Prettier with `prettier-plugin-sh`.

**Spec:** `docs/superpowers/specs/2026-11-09-mise-first-setup-and-settings-ui.md` ("Two parts", D5, D11, "Verified facts", phase "B. Migration script", Risks).

## Global Constraints

- Minimum mise version: 2026.11.5. Every step refuses below it.
- Removal date: 2027-02-28. The script header states it. `bin/lib/test-conventions` fails after that date while `migrate/` exists.
- Part A never reads the old layout. No file outside `migrate/`, `bin/lib/test-migrate` and the one README section may name the old method.
- The script never sources or calls `setup.sh`, `setup/*.sh`, `setup/Brewfile` or `bin/brewpick`. They will not exist.
- The script never edits `~/.zsh.local`.
- The script never passes `--force` to `mise dot apply`.
- Every step is idempotent, prints what it will change, asks before changing, and backs up what it replaces to `~/.dotfiles-migration-backup/<timestamp>/` (`<timestamp>` is `date +%Y%m%d-%H%M%S`).
- A closed stdin answers every prompt with "no" (`.claude/rules/setup.md`).
- Repo conventions: `#!/bin/bash`, tldr-style header, inline output helpers, `set -euo pipefail`, shellcheck clean at `--severity=warning`, `pnpm check` passes.
- Commit subjects are short, imperative, sentence case, no prefix. On `main`, commit and push once `pnpm check` passes.
- Tested on this Mac only (D11). Steps that change this Mac are run by the user, never by the implementer.

## Review Focus

1. **A Mac that never used the old method.** Every step prints "nothing to migrate", exits 0 and creates no backup folder. Test in Task 1 (`never_old`), extended by each step's task.
2. **A Mac migrated half way.** A second run after an interrupted first run finishes the work and repeats nothing. A cask Homebrew uninstalled that mise did not install shows as `missing`, and the script prints the apply command for it. Tests in Tasks 4 and 6 (`half_way_*`).
3. **`~/.zsh.local` with a value holding spaces or quotes.** `export K='a b "c"'` reaches `mise set --override` as one argument with the exact value. A value the script cannot read safely is skipped with the manual command. Tests in Task 2 (`env_quoting`).
4. **A Homebrew-installed cask that is running.** The script skips it, names it and tells the user to quit the app. It never uninstalls a running app. Test in Task 4 (`cask_running`).
5. **No network.** The `packages` step refuses to uninstall any cask when `curl -fsI --max-time 5 https://formulae.brew.sh/` fails. Every other step works offline. Test in Task 4 (`no_network`).

---

## Decisions this plan makes

The spec left these open. Each was checked on this Mac on 2026-11-09 unless marked.

| # | Decision | Evidence |
| --- | --- | --- |
| P1 | A phase is present when its marker file exists in the checkout. `macos`: `tilde/.config/mise/conf.d/20-macos.toml`. `packages`: `…/30-packages.toml`. `dotfiles`: `…/40-dotfiles.toml`. `setup`: `…/50-bootstrap.toml`. `env`: `zsh/override-env.zsh` (A1), and the step also needs `settings/registry.toml` (A2). | Spec "Architecture". The A1 and A2 plans create no `10-env.toml`, so `env` cannot use a fragment. |
| P2 | The script also refuses when `~/.config/mise` is not the clone's `tilde/.config/mise` (`-ef` test). mise would report on some other config. | `setup/misc.sh` `link_config_dir`. |
| P3 | Registered env keys come from `settings/registry.toml`, read with awk. A key counts when its `[[setting]]` table has `kind = "env"` and `access` is not `"ro"`. With the file missing the `env` step refuses (exit 3). No built-in key list. | Spec "Data shape". |
| P4 | A value in `~/.zsh.local` is read as text, never by running the file. Three forms are accepted. Anything else is skipped with the manual command. A value holding `$` is skipped because mise expands `$` in `[env]` values. | `mise set --override 'SP=… $x'` warned "env var 'x' is not defined". |
| P5 | "Is this already an override?" is answered by `mise set --file ~/.config/mise/config.override.toml KEY` (exit 1 when absent). `mise set --override KEY` cannot answer it. It prints the merged value. | Scratch run: `--override ONLYBASE` printed `base` from `conf.d`. |
| P6 | The cask's self-update flag and its owner come from `mise bootstrap packages status --json` (`auto_updates`, `managed_by`). No `brew` call and no network. | Scratch config with the 33 casks: 17 `auto_updates: true`, 16 without, all `managed_by: "homebrew"`. |
| P7 | A cask moves to mise with `brew uninstall --cask <token>` then `mise bootstrap packages apply --yes brew-cask:<token>`. So reinstalling needs `brew` still installed. Without `brew` the step only lists. | mise docs: apply does nothing to a Homebrew-installed cask, upgrade and prune skip it, "use Homebrew" to remove it. |
| P8 | A removed app bundle is not copied to the backup folder (size). The backup records token and version in `casks.tsv`, and the restore command is `brew install --cask <token>`. This is the one exception to "back up what you replace", and the prompt says so. | Casks have no version pins (spec). |
| P9 | Formulae need no migration. mise reads the prefix, so a Homebrew-installed formula counts as installed, and `upgrade` installs the current bottle over it. The step reports `needs_repair` entries and the `prune --dry-run` count. It never prunes. | Scratch run: `brew:jq` `installed`, `brew:rustup` `needs_repair`. mise brew docs. |
| P10 | Homebrew's documented uninstaller is not used. It deletes `Cellar` and `Caskroom`, where mise's packages live (D5). The step moves only the Homebrew program into the backup folder. | `uninstall.sh` lines 377-378, 423 and 454, cited in Task 5. |
| P11 | `/etc/pam.d/sudo_local`, `private/setup-logs/` and `~/dotfiles` are all left in place. The new method uses each. The script only copies a `sudo_local` that differs from the declared content into the backup, because the first `mise bootstrap` rewrites it. | A6 plan, "Part B hook". |
| P12 | `migrate/legacy-to-mise` follows the `bin/` conventions (header, helpers, shebang). It is not on `PATH` and `help` does not render it. Its test lives in `bin/lib/test-migrate`, where `bin/lib/check` already globs `bin/lib/test-*`. | `bin/CLAUDE.md`, `bin/lib/check`. |

## File Structure

| File | Responsibility | Created in |
| --- | --- | --- |
| `migrate/legacy-to-mise` | The script. One function per step plus shared helpers. | Task 1, grown by Tasks 2-7 |
| `migrate/README.md` | What each step does, the removal date, how to restore. | Task 1, one section per later task |
| `bin/lib/test-migrate` | Self-check. Scratch `HOME`, stubs, one function per case. | Task 1, grown by Tasks 2-7 |
| `bin/lib/check` | Lints `migrate/legacy-to-mise`, runs `test-migrate`. | Task 1 |
| `package.json` | `format` covers `migrate/*`. | Task 1 |
| `bin/lib/test-conventions` | Removal-date check. Old-method-name check (Task 7). | Tasks 1 and 7 |
| `README.md` | Section "Migrating an existing machine". | Task 1 |

## Landing order

| Task | Lands with | Why |
| --- | --- | --- |
| 1 Skeleton | before A1 | Later tasks only add a step function. |
| 2 `env` | A2 | Needs `settings/registry.toml`. |
| 3 `macos` | A3 | |
| 4 `packages`: casks and leftovers | A4 | |
| 5 `packages`: Homebrew removal | after A4's fresh-install workflow has passed once | That run is the proof mise needs no Homebrew program. |
| 6 `dotfiles` | A5, before A5's first `mise dot apply` on this Mac | |
| 7 `setup` | A6, before A6's first `mise bootstrap` on this Mac | A6 plan, Task "changes the machine", says so. |
| 8 Removal | on or after 2027-02-28 | |

---

### Task 1: Script skeleton, self-check, removal date, docs

**Files:**

- Create: `migrate/legacy-to-mise` (mode 755)
- Create: `migrate/README.md`
- Create: `bin/lib/test-migrate` (mode 755)
- Modify: `bin/lib/check` (the `shell_scripts` array, the Prettier globs, one test line)
- Modify: `package.json` (`scripts.format`)
- Modify: `bin/lib/test-conventions` (one check and one header sentence)
- Modify: `README.md` (new section after "Updating")

**Interfaces:**

- Produces, in `migrate/legacy-to-mise`:
  - Globals: `REPO` (clone root, `cd "$(dirname "$0")/.." && pwd -P`), `DRY_RUN` (`true` or `false`), `PREFIX` (`${HOMEBREW_PREFIX:-/opt/homebrew}`), `BACKUP_DIR` (`$HOME/.dotfiles-migration-backup/$(date +%Y%m%d-%H%M%S)`, not created until first use), `MIN_MISE=2026.11.5`, `CHANGED` (count of changes made).
  - `header <text>`, `info <text>`, `warn <text>`, `success <text>`, `fail <text>` (prints and exits 1). Inline, `tput` guarded as in `setup/brew.sh`: `tput() { command tput "$@" 2> /dev/null || true; }`.
  - `ask <question>`: returns 0 only for `y` or `Y`. Under `DRY_RUN=true` it prints `would ask: <question>` and returns 1. EOF returns 1.
  - `ask_typed <phrase> <question>`: returns 0 only when the reply equals `<phrase>` exactly. Same dry-run and EOF rules.
  - `run <cmd> [args…]`: under `DRY_RUN=true` prints `would run: <cmd> <args>` and returns 0. Otherwise prints `→ <cmd> <args>`, runs it, adds 1 to `CHANGED`.
  - `backup_move <path>`: moves `<path>` to `$BACKUP_DIR/files/<path without its leading slash>`, creating `BACKUP_DIR` with mode 700. Appends `mv '<backup>' '<path>'` to `$BACKUP_DIR/RESTORE.txt`. Under `DRY_RUN=true` prints `would back up: <path>` and moves nothing. Never called on a path that resolves inside `REPO` (it calls `fail`).
  - `backup_copy <path>`: same, with `cp -p`, and the restore line is `cp -p '<backup>' '<path>'`.
  - `backup_note <file> <line>`: appends `<line>` to `$BACKUP_DIR/<file>` (mode 600). No-op under dry-run.
  - `STEPS=(env macos packages dotfiles setup)` and `phase_marker <step>`, a `case` that prints each step's marker path relative to `REPO`: `zsh/override-env.zsh`, `tilde/.config/mise/conf.d/20-macos.toml`, `tilde/.config/mise/conf.d/30-packages.toml`, `tilde/.config/mise/conf.d/40-dotfiles.toml`, `tilde/.config/mise/conf.d/50-bootstrap.toml`.
  - `phase_present <step>`: returns 0 when `$REPO/$(phase_marker <step>)` exists.
  - Each step is a function `step_<name>` returning 0 or 1. Task 1 defines all five as `info "nothing to migrate yet"`.
- Produces, in `bin/lib/test-migrate`:
  - `tmp`, `HOME=$tmp/home`, `STATE=$tmp/state`, `REPO_COPY=$tmp/repo` (holds a copy of `migrate/` plus fixture `tilde/.config/mise/conf.d/` and `settings/`), `HOMEBREW_PREFIX=$tmp/prefix`, `PATH=$tmp/bin:/usr/bin:/bin`.
  - `stub <name> <body>` as in `bin/lib/test-upup`.
  - `phase <step>`: creates that step's marker file in `REPO_COPY` (the same five paths as `phase_marker`).
  - `snapshot`: prints `find "$HOME" "$HOMEBREW_PREFIX" "$STATE" -exec ls -ld {} +` with every regular file's `cksum`, sorted, excluding `$STATE/*.log`.
  - `mutations`: prints the lines of `$STATE/mise.log`, `$STATE/brew.log` and `$STATE/claude.log` that are not read-only calls. Read-only means matching `status`, `--version`, `--dry-run`, `set --file`, `info --json`, `mcp get`.
  - `check <description> <command…>` and `check_out <description> <ERE>` (greps `$out`), exiting 1 with `test-migrate: <description>`.

**Usage and exit codes (exact):**

```text
migrate/legacy-to-mise [--step <env|macos|packages|dotfiles|setup>] [--dry-run] [-h|--help]
0  done, or nothing to migrate
1  a step failed
2  unknown option or step name
3  refused: mise older than 2026.11.5, ~/.config/mise is not this clone's, or the named step's marker file is absent
```

With no `--step`, the script runs every step whose phase is present, in `STEPS` order, and prints `skipped <name>: its phase is not in this checkout` for the rest. That is exit 0. With `--step <name>` and the phase absent it prints `refusing <name>: <marker path> is not in this checkout` and exits 3. The last line of every run is `Changed <n> thing(s).` followed, when `BACKUP_DIR` exists, by `Backup: <dir>` and `Restore commands: <dir>/RESTORE.txt`.

**Header (exact copy, one sentence per line as tlrc requires):**

```bash
#!/bin/bash
#
# Move a Mac set up by the old bash and Brewfile method onto the mise-first setup.
#
# - Show what every step would change, changing nothing:
#
# `migrate/legacy-to-mise --dry-run`
#
# - Run one step (env, macos, packages, dotfiles or setup):
#
# `migrate/legacy-to-mise --step {{step}}`
#
# - Run every step whose phase is in this checkout:
#
# `migrate/legacy-to-mise`
#
# ---
# Temporary: delete migrate/ on or after 2027-02-28 (bin/lib/test-conventions fails after that date).
# The only file that knows the old layout, so it never sources or calls the old scripts.
# Every change asks first, and what it replaces goes to ~/.dotfiles-migration-backup/<timestamp>/.
#
# License: MIT
```

- [ ] **Step 1: Write the failing test `bin/lib/test-migrate`**

Header in the style of `bin/lib/test-rea-mcp` ("Self-check for migrate/legacy-to-mise against a scratch HOME and stubbed brew, mise and claude."). The fake `mise` for this task:

```bash
stub mise 'echo "mise $*" >> "$STATE/mise.log"
case "$*" in
  --version) echo "${FAKE_MISE_VERSION:-2026.11.5} macos-arm64 (2026-11-08)" ;;
esac'
stub brew 'echo "brew $*" >> "$STATE/brew.log"'
stub claude 'echo "claude $*" >> "$STATE/claude.log"'
```

Cases, each a function called at the bottom:

```bash
refuses_absent_phase() {
  for s in env macos packages dotfiles setup; do
    out=$("$script" --step "$s" 2>&1) && fail "$s ran with its phase absent" || rc=$?
    [ "$rc" = 3 ] || fail "$s: exit $rc, want 3"
    check_out "$s names the marker" "refusing $s: [a-z./0-9-]+ is not in this checkout"
  done
}
refuses_old_mise() {
  phase macos
  out=$(FAKE_MISE_VERSION=2026.11.4 "$script" --step macos 2>&1) && fail "ran on old mise" || rc=$?
  [ "$rc" = 3 ] || fail "old mise: exit $rc, want 3"
  check_out "names the floor" 'mise 2026\.11\.5 or newer'
  out=$(FAKE_MISE_VERSION=2026.12.0 "$script" --step macos 2>&1) || fail "refused 2026.12.0: $out"
}
refuses_foreign_mise_config() {
  rm "$HOME/.config/mise" && mkdir "$HOME/.config/mise"
  out=$("$script" --step macos 2>&1) && fail "ran with a foreign ~/.config/mise" || rc=$?
  [ "$rc" = 3 ] || fail "foreign config: exit $rc, want 3"
  rmdir "$HOME/.config/mise" && ln -s "$REPO_COPY/tilde/.config/mise" "$HOME/.config/mise"
}
usage_errors() {
  "$script" --step nope > /dev/null 2>&1 && fail "accepted --step nope" || [ $? = 2 ] || fail "--step nope: want exit 2"
  "$script" --frob > /dev/null 2>&1 && fail "accepted --frob" || [ $? = 2 ] || fail "--frob: want exit 2"
  "$script" --help | grep -q '2027-02-28' || fail "--help does not state the removal date"
}
never_old() {
  for s in env macos packages dotfiles setup; do phase "$s"; done
  before=$(snapshot)
  out=$("$script" < /dev/null 2>&1) || fail "never-old Mac: exit $?: $out"
  [ "$(snapshot)" = "$before" ] || fail "never-old Mac: something changed"
  [ ! -e "$HOME/.dotfiles-migration-backup" ] || fail "never-old Mac: a backup folder was made"
  [ -z "$(mutations)" ] || fail "never-old Mac: mutating calls: $(mutations)"
  check_out "ends with the count" '^Changed 0 thing\(s\)\.$'
}
helpers_back_up_before_replacing() {
  # MIGRATE_SELFTEST runs: backup_move "$1"; echo replaced > "$1"
  echo original > "$HOME/victim"
  MIGRATE_SELFTEST="$HOME/victim" "$script" > /dev/null 2>&1 || fail "selftest hook failed"
  bak=$(echo "$HOME"/.dotfiles-migration-backup/*/files"$HOME"/victim)
  [ "$(cat "$bak")" = original ] || fail "backup does not hold the original"
  grep -qF "mv '$bak' '$HOME/victim'" "$HOME"/.dotfiles-migration-backup/*/RESTORE.txt || fail "no restore command"
  MIGRATE_SELFTEST="$REPO_COPY/migrate/legacy-to-mise" "$script" > /dev/null 2>&1 && fail "backed up a file inside the clone" || true
  rm -rf "$HOME/.dotfiles-migration-backup" "$HOME/victim"
}
```

`MIGRATE_SELFTEST` is a test-only hook in the script: when set, it runs `backup_move "$MIGRATE_SELFTEST"`, writes `replaced` to that path and exits. It is the only way to exercise the helper before a step uses it. Task 6 replaces this case with a real one and deletes the hook.

`never_old` runs last in this task because it creates every marker file.

- [ ] **Step 2: Run the test to see it fail**

Run: `bash bin/lib/test-migrate`
Expected: FAIL, `migrate/legacy-to-mise: No such file or directory`.

- [ ] **Step 3: Write `migrate/legacy-to-mise` to the Interfaces block**

The version test is `[ "$(printf '%s\n' "$MIN_MISE" "$have" | sort -V | head -1)" = "$MIN_MISE" ]`, where `have` is the first field of `mise --version`. `sort -V` exists in macOS `sort` (checked: orders `2026.6.6 2026.11.5 2026.11.10`). `mise` missing from `PATH` is the same refusal (exit 3). `--help` prints the header with the `awk` line from `setup.sh:54`, copied into the script. Then `chmod +x migrate/legacy-to-mise bin/lib/test-migrate`.

- [ ] **Step 4: Run the test to see it pass**

Run: `bash bin/lib/test-migrate`
Expected: `test-migrate: ok`

- [ ] **Step 5: Wire into `bin/lib/check` and `package.json`**

In `bin/lib/check`: add `migrate/legacy-to-mise` to `shell_scripts`. Add `"migrate/*"` after `"bin/*"` in the Prettier call. Add, after the `test-rea-mcp` line:

```bash
# migrate/legacy-to-mise against a scratch HOME with brew, mise and claude stubbed (temporary: see migrate/README.md)
bash bin/lib/test-migrate > /dev/null
```

In `package.json`, add `\"migrate/*\"` after `\"bin/*\"` in `scripts.format`.

- [ ] **Step 6: Add the removal-date check to `bin/lib/test-conventions`**

After the `curlrc` check:

```bash
# migrate/ is temporary (spec Part B). CONVENTIONS_TODAY lets the check be tried before the date
if [ -e migrate ]; then
  grep -q '2027-02-28' migrate/legacy-to-mise || fail "migrate/legacy-to-mise must state its removal date, 2027-02-28"
  [ "${CONVENTIONS_TODAY:-$(date +%Y%m%d)}" -le 20270228 ] \
    || fail "migrate/ is past its removal date (2027-02-28): delete migrate/, bin/lib/test-migrate, their lines in bin/lib/check and package.json, this check and README.md's 'Migrating an existing machine'"
fi
```

Add to the header's description sentence: "that migrate/ is gone after 2027-02-28,".

- [ ] **Step 7: Prove the date check fires**

Run: `CONVENTIONS_TODAY=20270301 bash bin/lib/test-conventions; echo "exit $?"`
Expected: `FAIL: migrate/ is past its removal date (2027-02-28): …` and `exit 1`.
Run: `CONVENTIONS_TODAY=20270228 bash bin/lib/test-conventions | tail -1`
Expected: `conventions: all checks passed`

- [ ] **Step 8: Write `migrate/README.md` and the `README.md` section**

`migrate/README.md` holds: one paragraph on who needs it (a Mac set up from this repo before the mise-first setup), the removal date and the check that enforces it, the usage block and exit codes above, a "Steps" heading with one `###` per step (Task 1 writes "Lands with phase A<n>." under each, and later tasks replace that line), and "Restoring": every replaced item is under `~/.dotfiles-migration-backup/<timestamp>/files/` at its original path, `RESTORE.txt` in that folder lists one command per item, and the folder is deleted by hand once the Mac works.

`README.md`, new `##` section after "Updating", exact text:

````markdown
## Migrating an existing machine

A Mac set up from this repo before the mise-first setup moves across with a separate script. It is temporary: `migrate/` is deleted on or after 2027-02-28, and `pnpm check` fails after that date while it exists.

```shell
migrate/legacy-to-mise --dry-run # show what each step would change
migrate/legacy-to-mise           # run every step this checkout supports
```

It runs five steps (`env`, `macos`, `packages`, `dotfiles`, `setup`), asks before each change, and moves anything it replaces to `~/.dotfiles-migration-backup/<timestamp>/`, where `RESTORE.txt` lists the command that puts each item back. A new Mac never needs it. Details per step: [migrate/README.md](migrate/README.md).
````

- [ ] **Step 9: Gate and commit**

Run: `pnpm check`
Expected: exit 0.

```bash
git add migrate bin/lib/test-migrate bin/lib/check bin/lib/test-conventions package.json README.md
git commit -m "Add the migration script skeleton and its removal date check"
git push
```

---

### Task 2: Step `env` (lands with A2)

**Files:**

- Modify: `migrate/legacy-to-mise` (`step_env`)
- Modify: `bin/lib/test-migrate`
- Modify: `migrate/README.md` (the `env` section)

**Interfaces:**

- Consumes: `ask`, `run`, `backup_copy`, `phase_present`, `REPO` from Task 1. `settings/registry.toml` from A2, in the shape the spec's "Data shape" gives.
- Produces:
  - `registered_env_keys`: prints one key per line. For each `[[setting]]` table in `$REPO/settings/registry.toml`, the `key` value when `kind = "env"` and `access` is not `"ro"`. POSIX awk only (macOS awk is the 2020 BWK version).
  - `zsh_local_value <KEY>`: prints the value of the last `export KEY=…` line in `~/.zsh.local` and returns 0. Returns 1 when no such line exists. Returns 2 when the last such line is not in an accepted form.
  - `step_env`.

**Accepted value forms** (after `export KEY=`, to end of line, allowing trailing spaces and a `# comment`):

| Form | Rule | Value |
| --- | --- | --- |
| `'…'` | no `'` inside | the text between the quotes |
| `"…"` | none of `"`, `$`, `` ` ``, `\` inside | the text between the quotes |
| bare | only `[A-Za-z0-9_./:@%+,=~-]`, not starting with `~` | the word |

A value holding `$` is rejected in every form (P4).

**Behaviour of `step_env`, in order:**

1. `settings/registry.toml` missing: print `refusing env: settings/registry.toml is not in this checkout (phase A2)` and exit 3.
2. `~/.zsh.local` missing or holding no export of a registered key: `nothing to migrate`, return 0.
3. For each registered key with an export, read the current override with `mise set --file "$HOME/.config/mise/config.override.toml" KEY` (exit 1 means none):
   - equal: print `KEY: already an override`.
   - form not accepted: print `KEY: cannot read its value safely. Set it yourself: mise set --override KEY=<value>`.
   - none: `ask "Make KEY=<value> from ~/.zsh.local an override?"`.
   - different: print both values, `ask "Replace the override for KEY?"`.
4. Before the first write of the run, `backup_copy` the override file when it exists.
5. Write with `(cd "$HOME" && run mise set --override "KEY=VALUE")`. One argument, quoted.
6. Print `KEY: retired, no longer read. Delete its line from ~/.zsh.local yourself.` for each export of `DOTFILES_MACOS_YES`, `DOTFILES_MACOS_NO` or a name starting `HOMEBREW_`, when the phase that retired it is present (`phase_present macos` for the first two, `phase_present packages` for `HOMEBREW_*`).
7. When at least one override was written or already existed, print this exact text:

```text
~/.zsh.local was not edited. Its export lines stay as seeds.
An override beats the seed: while KEY has an override, editing ~/.zsh.local does not change KEY.
Undo one with: mise unset --override KEY
```

- [ ] **Step 1: Write the failing tests**

The fake `mise` gains:

```bash
"set --file "*)  # set --file <file> KEY  → prints $STATE/override/KEY, exit 1 when absent
  key=${*##* }; [ -f "$STATE/override/$key" ] && cat "$STATE/override/$key" || exit 1 ;;
"set --override "*)  # set --override KEY=VALUE  (one argument)
  [ $# = 3 ] || { echo "set --override got $# args" >&2; exit 9; }
  kv=$3; mkdir -p "$STATE/override"; printf '%s\n' "${kv#*=}" > "$STATE/override/${kv%%=*}" ;;
```

Fixture `$REPO_COPY/settings/registry.toml`: four `[[setting]]` tables. `DOTFILES_TRIM_CA_ROOTS` (`kind = "env"`, `access = "rw"`), `DOTFILES_MAC_PASSWORD_OP` (`env`, `rw`), `DOTNET_CLI_TELEMETRY_OPTOUT` (`env`, `ro`), and one with `kind = "tool"` and `key = "NOT_ENV"`.

```bash
env_refuses_without_registry() {
  phase env; mv "$REPO_COPY/settings/registry.toml" "$tmp/reg"
  "$script" --step env > /dev/null 2>&1 && fail "env ran without the registry" || [ $? = 3 ] || fail "env without registry: want exit 3"
  mv "$tmp/reg" "$REPO_COPY/settings/registry.toml"
}
env_quoting() {
  cat > "$HOME/.zsh.local" << 'EOF'
export DOTFILES_MAC_PASSWORD_OP='op://Private/Mac login/pass "q"'  # note
export DOTFILES_TRIM_CA_ROOTS=1
export DOTNET_CLI_TELEMETRY_OPTOUT=0
export NOT_ENV=x
export UNREGISTERED="y"
EOF
  zsh_local_before=$(cksum < "$HOME/.zsh.local")
  out=$(yes | "$script" --step env 2>&1) || fail "env: exit $?: $out"
  [ "$(cat "$STATE/override/DOTFILES_MAC_PASSWORD_OP")" = 'op://Private/Mac login/pass "q"' ] || fail "value with spaces and quotes was changed"
  [ "$(cat "$STATE/override/DOTFILES_TRIM_CA_ROOTS")" = 1 ] || fail "bare value not written"
  [ ! -e "$STATE/override/DOTNET_CLI_TELEMETRY_OPTOUT" ] || fail "wrote a read-only setting"
  [ ! -e "$STATE/override/NOT_ENV" ] && [ ! -e "$STATE/override/UNREGISTERED" ] || fail "wrote an unregistered key"
  [ "$(cksum < "$HOME/.zsh.local")" = "$zsh_local_before" ] || fail "~/.zsh.local was edited"
  check_out "explains seed and override" 'An override beats the seed'
}
env_second_run_changes_nothing() {
  before=$(snapshot); : > "$STATE/mise.log"
  out=$(yes | "$script" --step env 2>&1) || fail "env rerun: exit $?"
  [ "$(snapshot)" = "$before" ] || fail "env rerun changed something"
  [ -z "$(mutations)" ] || fail "env rerun made mutating calls: $(mutations)"
  check_out "says already" 'DOTFILES_TRIM_CA_ROOTS: already an override'
}
env_unsafe_values_are_skipped() {
  rm -rf "$STATE/override"
  printf '%s\n' 'export DOTFILES_MAC_PASSWORD_OP="$(op read x)"' "export DOTFILES_TRIM_CA_ROOTS='a\$b'" > "$HOME/.zsh.local"
  out=$(yes | "$script" --step env 2>&1) || fail "env unsafe: exit $?"
  [ ! -e "$STATE/override" ] || fail "wrote a value it could not read safely"
  check_out "gives the manual command" 'mise set --override DOTFILES_MAC_PASSWORD_OP=<value>'
}
env_dry_run_and_closed_stdin_change_nothing() {
  printf '%s\n' 'export DOTFILES_TRIM_CA_ROOTS=1' > "$HOME/.zsh.local"
  for how in "--dry-run" ""; do
    before=$(snapshot); : > "$STATE/mise.log"
    out=$("$script" --step env $how < /dev/null 2>&1) || fail "env $how: exit $?"
    [ "$(snapshot)" = "$before" ] && [ -z "$(mutations)" ] || fail "env $how with closed stdin changed something"
  done
}
env_backs_up_override_before_replacing() {
  mkdir -p "$STATE/override"; echo 0 > "$STATE/override/DOTFILES_TRIM_CA_ROOTS"
  echo '[env]' > "$REPO_COPY/tilde/.config/mise/config.override.toml"
  out=$(yes | "$script" --step env 2>&1) || fail "env replace: exit $?"
  ls "$HOME"/.dotfiles-migration-backup/*/files"$HOME"/.config/mise/config.override.toml > /dev/null 2>&1 || fail "override file not backed up before the write"
  rm -rf "$HOME/.dotfiles-migration-backup" "$HOME/.zsh.local" "$STATE/override"
}
```

`never_old` stays last and now covers `env` with no `~/.zsh.local`.

- [ ] **Step 2: Run to see them fail**

Run: `bash bin/lib/test-migrate`
Expected: FAIL at `env ran without the registry`.

- [ ] **Step 3: Implement `registered_env_keys`, `zsh_local_value` and `step_env`**

- [ ] **Step 4: Run to see them pass**

Run: `bash bin/lib/test-migrate`
Expected: `test-migrate: ok`

- [ ] **Step 5: Check the real registry parses**

Run: `bash -c 'source <(sed -n "/^registered_env_keys()/,/^}/p" migrate/legacy-to-mise); REPO=$PWD registered_env_keys' | sort`
Expected: the `key` of every `rw` env setting A2 registered, `DOTFILES_TRIM_CA_ROOTS` and `DOTFILES_MAC_PASSWORD_OP` among them, and no telemetry opt-out.

- [ ] **Step 6: Dry-run on this Mac**

Run: `migrate/legacy-to-mise --step env --dry-run`
Expected: two `would ask:` lines, for `DOTFILES_MAC_PASSWORD_OP` and `DOTFILES_TRIM_CA_ROOTS` (the two exports in this Mac's `~/.zsh.local`), and `Changed 0 thing(s).`

- [ ] **Step 7: Document, gate, commit**

Replace the `env` line in `migrate/README.md` with the behaviour list above in prose, including the three accepted forms and the seed-and-override text.

Run: `pnpm check`

```bash
git add migrate bin/lib/test-migrate
git commit -m "Add the env step to the migration script"
git push
```

---

### Task 3: Step `macos` (lands with A3)

**Files:**

- Modify: `migrate/legacy-to-mise` (`step_macos`)
- Modify: `bin/lib/test-migrate`
- Modify: `migrate/README.md`

**Interfaces:**

- Consumes: `mise bootstrap macos defaults status --json`. Shape, checked on mise 2026.11.5: `{"macos_defaults":{"available":true,"entries":[{"domain":"…","key":"…","value":<json>,"current":"…","state":"set"|"differs"|"unset"}]}}`.
- Produces: `step_macos`. It changes nothing and always returns 0 when the status command succeeds.

**Output (exact):** one line `macOS defaults: <a> set, <b> differ, <c> unset.`, then one line per `differs` or `unset` entry as `<domain> <key>: wants <value>, has <current or "nothing">`, then one line per leftover that is present as `<domain> <key>: set by the old script, no longer declared. Remove it: defaults delete <domain> <key>`, then this text:

```text
Nothing was changed. The old script already wrote these preferences.
To write the declared values, run: set-defaults
mise never deletes a preference. One the old script set that the config no longer declares stays
until you run its defaults delete command.
```

**Leftovers** (from the A3 plan, "What Part B's `macos` step needs"): `com.apple.dock autohide-delay`, `com.apple.dock autohide-time-modifier`, `com.apple.LaunchServices LSQuarantine`, `com.apple.frameworks.diskimages skip-verify`, `com.apple.frameworks.diskimages skip-verify-locked`, `com.apple.frameworks.diskimages skip-verify-remote`. One is present when `defaults read <domain> <key>` exits 0. The list is a literal array in the script.

- [ ] **Step 1: Write the failing test**

The fake `mise` gains: `"bootstrap macos defaults status --json") cat "$STATE/defaults.json" ;;`. A `defaults` stub exits 0 for `read com.apple.dock autohide-delay` and 1 for every other `read`, and logs any other verb to `$STATE/defaults.log`.

```bash
macos_reports_only() {
  phase macos
  cat > "$STATE/defaults.json" << 'EOF'
{"macos_defaults":{"available":true,"entries":[
 {"domain":"com.apple.dock","key":"autohide","value":true,"current":"true","state":"set"},
 {"domain":"com.apple.dock","key":"tilesize","value":48,"current":"64","state":"differs"},
 {"domain":"NSGlobalDomain","key":"KeyRepeat","value":2,"current":"","state":"unset"}]}}
EOF
  before=$(snapshot)
  for how in "" "--dry-run"; do
    out=$(yes | "$script" --step macos $how 2>&1) || fail "macos $how: exit $?"
    check_out "counts" '^macOS defaults: 1 set, 1 differ, 1 unset\.$'
    check_out "lists the differing one" '^com\.apple\.dock tilesize: wants 48, has 64$'
    check_out "lists the unset one" '^NSGlobalDomain KeyRepeat: wants 2, has nothing$'
    check_out "names the leftover that is present" '^com\.apple\.dock autohide-delay: set by the old script.*defaults delete com\.apple\.dock autohide-delay$'
    ! grep -q 'LSQuarantine' <<< "$out" || fail "listed a leftover that is not set"
    check_out "states the no-delete rule" 'mise never deletes a preference'
  done
  [ "$(snapshot)" = "$before" ] && [ -z "$(mutations)" ] && [ ! -s "$STATE/defaults.log" ] || fail "macos changed something"
}
```

- [ ] **Step 2: Run to see it fail.** `bash bin/lib/test-migrate`. Expected: FAIL `counts`.
- [ ] **Step 3: Implement `step_macos`** with one `jq` call for the counts and one for the lines.
- [ ] **Step 4: Run to see it pass.** Expected: `test-migrate: ok`.
- [ ] **Step 5: Run on this Mac** (read-only): `migrate/legacy-to-mise --step macos`. Expected: the counts line, whose three numbers add up to the entry count of `mise bootstrap macos defaults status --json | jq '.macos_defaults.entries | length'`, and `Changed 0 thing(s).`
- [ ] **Step 6: Document, gate, commit**

`migrate/README.md`, `macos` section: report only, the leftovers list, the four-line text above.

```bash
pnpm check
git add migrate bin/lib/test-migrate
git commit -m "Add the macOS defaults report to the migration script"
git push
```

---

### Task 4: Step `packages`, casks and leftovers (lands with A4)

**Files:**

- Modify: `migrate/legacy-to-mise` (`step_packages` and helpers)
- Modify: `bin/lib/test-migrate`
- Modify: `migrate/README.md`

**Interfaces:**

- Consumes: `mise bootstrap packages status --json`. Shape, checked: `{"brew":{"packages":[{"package","state","installed_version"}]},"brew-cask":{"packages":[{"package","state","installed_version","auto_updates"?,"managed_by"?}]}}`. `state` is `installed`, `missing` or `needs_repair`. `managed_by` is `homebrew`, `mise` or `unknown`. `auto_updates` is present only when true.
- Consumes, only while `brew` is on `PATH`: `brew info --json=v2 --cask <token>`, for `.casks[0].artifacts[] | .app? // empty | .[] | strings` (the app bundle names, checked: `ghostty` gives `Ghostty.app`, a font cask gives none) and `.pkg?` (checked: present for `dotnet-sdk`).
- Produces:
  - `packages_status`: prints the status JSON once per run (cached in a variable).
  - `homebrew_casks`: prints `token<TAB>version<TAB>self-updates(true|false)` for each cask with `managed_by == "homebrew"`.
  - `cask_apps <token>`: prints the app bundle names, empty without `brew`.
  - `app_running <App.app>`: `pgrep -f "${MIGRATE_APPDIR:-/Applications}/$1/Contents/MacOS/" > /dev/null`.
  - `reinstall_cask <token>`: the sequence below. Returns 1 when the check after it fails.
  - `clean_staging_leftovers`.
  - `step_packages`. Task 5 adds a call at its end.

**What `step_packages` prints and does, in order:**

1. **Formulae.** `Formulae: nothing to migrate. mise reads /opt/homebrew, so a formula Homebrew installed counts as installed, and "mise bootstrap packages upgrade" replaces it with the current bottle.` Then one line per `brew` package with `state == "needs_repair"`: `<name>: needs repair (mise bootstrap packages apply restores the link, nothing is reinstalled)`. Then `Not declared in the config: <n> formulae ("mise bootstrap packages prune --dry-run" lists them; this script never prunes)`, where `<n>` is `mise bootstrap packages prune --manager brew --dry-run | grep -c '^remove brew:'`.
2. **Half-way casks.** For each cask with `state == "missing"`: `<token>: declared but not installed. Install it: mise bootstrap packages apply brew-cask:<token>`. No prompt.
3. **Self-updating Homebrew casks.** One line: `Left alone (they update themselves): <tokens>`.
4. **Homebrew casks that do not self-update.** A table of token, version and kind (`app`, `pkg`, or `other`). Then this text, exact:

```text
Nothing upgrades these any more: mise leaves a cask Homebrew installed alone.
Reinstalling one through mise runs, for each cask you pick:
  brew uninstall --cask <token>
  mise bootstrap packages apply --yes brew-cask:<token>
and then checks that mise reports it installed and managed by mise.
The app bundle is replaced, not copied to the backup folder. macOS can drop the privacy
permissions (Accessibility, Full Disk Access, Screen Recording and the like) of a replaced app,
so check System Settings > Privacy & Security afterwards. Way back: brew install --cask <token>.
```

5. Without `brew` on `PATH`: `brew is not installed, so these cannot be moved by this script. To move one by hand, delete the app and /opt/homebrew/Caskroom/<token>, then run the apply command.` Return.
6. Network probe once: `curl -fsI --max-time 5 https://formulae.brew.sh/ > /dev/null`. On failure: `No network: not reinstalling anything.` Skip to 8.
7. For each cask in the table: when any of its apps is running, print `<token>: <App.app> is running. Quit it and run this step again.` and skip it. Otherwise `ask "Reinstall <token> <version> through mise?"`. On yes, `reinstall_cask`.
8. `clean_staging_leftovers`.

**`reinstall_cask <token>`:**

1. `backup_note casks.tsv "<token><TAB><version>"` and append `brew install --cask <token>` to `RESTORE.txt`.
2. `run brew uninstall --cask "<token>"`. On failure, stop the step with exit 1. Nothing was replaced.
3. `run mise bootstrap packages apply --yes "brew-cask:<token>"`.
4. Read the status again. Pass when the cask has `state == "installed"` and `managed_by == "mise"`, and each app `cask_apps` named before the uninstall exists under `${MIGRATE_APPDIR:-/Applications}`. On failure print `<token> is not installed. Put it back with: brew install --cask <token>` and stop the step with exit 1. The remaining casks are not touched.

**`clean_staging_leftovers`:** for each directory `d` directly under `$PREFIX/Cellar` where `ls -A "$d"` prints exactly `.mise-staging.lock`: list it, `ask "Remove <n> empty Cellar folder(s) that hold only mise's staging lock?"`, then `backup_move "$d"` for each. The spec's "Verified facts" records how one arises (`brew uninstall` of a formula mise installed).

- [ ] **Step 1: Write the failing tests**

The fake `mise` and `brew` gain:

```bash
# mise
"bootstrap packages status --json") cat "$STATE/status.json" ;;
"bootstrap packages prune --manager brew --dry-run") printf 'remove brew:abseil@1\nremove brew:ack@3\n' ;;
"bootstrap packages apply --yes brew-cask:"*)
  [ ! -e "$STATE/apply-fails" ] || exit 1
  t=${*##*brew-cask:}
  jq --arg t "$t" '(."brew-cask".packages[] | select(.package == $t)) |= (.state = "installed" | .managed_by = "mise")' "$STATE/status.json" > "$STATE/s" && mv "$STATE/s" "$STATE/status.json"
  for a in $(cat "$STATE/apps/$t" 2> /dev/null); do mkdir -p "$MIGRATE_APPDIR/$a"; done ;;
# brew
"info --json=v2 --cask "*) cat "$STATE/cask-info/${*##* }.json" ;;
"uninstall --cask "*)
  t=${*##* }
  jq --arg t "$t" '(."brew-cask".packages[] | select(.package == $t)) |= (.state = "missing" | del(.managed_by))' "$STATE/status.json" > "$STATE/s" && mv "$STATE/s" "$STATE/status.json" ;;
```

The script reads the applications folder from `${MIGRATE_APPDIR:-/Applications}`, and the test exports `MIGRATE_APPDIR="$tmp/apps"`. `curl` and `pgrep` are stubs too: `curl` exits 1 when `$STATE/offline` exists, `pgrep` exits 0 when its last argument contains a name listed in `$STATE/running`.

Fixture `status.json`: formulae `jq` (`installed`) and `rustup` (`needs_repair`). Casks `ghostty` (`homebrew`, `auto_updates: true`), `font-hack-nerd-font` (`homebrew`), `utm` (`homebrew`, app `UTM.app`), `freelens` (`homebrew`, app `Freelens.app`), `raycast` (`mise`).

```bash
packages_lists_and_reinstalls_only_the_picked() {
  phase packages
  # answers in table order: font-hack-nerd-font n, utm y, freelens n, then the leftovers prompt n
  out=$(printf 'n\ny\nn\nn\n' | "$script" --step packages 2>&1) || fail "packages: exit $?: $out"
  check_out "formulae need nothing" '^Formulae: nothing to migrate'
  check_out "repair is reported" '^rustup: needs repair'
  check_out "prune count" 'Not declared in the config: 2 formulae'
  check_out "self-updating casks are left" 'Left alone \(they update themselves\): ghostty'
  check_out "privacy warning" 'macOS can drop the privacy'
  ! grep -q 'raycast' <<< "$out" || fail "listed a cask mise already manages"
  [ "$(grep -c '^brew uninstall' "$STATE/brew.log")" = 1 ] && grep -qx 'brew uninstall --cask utm' "$STATE/brew.log" || fail "uninstalled something other than the one pick"
  grep -qx 'mise bootstrap packages apply --yes brew-cask:utm' "$STATE/mise.log" || fail "did not apply the pick through mise"
  grep -q '^utm' "$HOME"/.dotfiles-migration-backup/*/casks.tsv || fail "pick not recorded before the uninstall"
  grep -qx 'brew install --cask utm' "$HOME"/.dotfiles-migration-backup/*/RESTORE.txt || fail "no way back recorded"
}
packages_second_run_changes_nothing() {
  before=$(snapshot); : > "$STATE/mise.log"; : > "$STATE/brew.log"
  out=$(printf 'n\nn\nn\n' | "$script" --step packages 2>&1) || fail "packages rerun: exit $?"
  [ "$(snapshot)" = "$before" ] && [ -z "$(mutations)" ] || fail "packages rerun changed something"
  ! grep -q 'Reinstall utm' <<< "$out" || fail "offered utm again after mise took it over"
}
cask_running() {
  echo Freelens.app > "$STATE/running"; : > "$STATE/brew.log"
  out=$(yes | "$script" --step packages 2>&1) || true
  check_out "names the running app" '^freelens: Freelens\.app is running\. Quit it'
  ! grep -q 'uninstall --cask freelens' "$STATE/brew.log" || fail "uninstalled a running app"
  rm "$STATE/running"
}
no_network() {
  touch "$STATE/offline"; : > "$STATE/brew.log"
  out=$(yes | "$script" --step packages 2>&1) || fail "offline: exit $?"
  check_out "says so" '^No network: not reinstalling anything\.$'
  ! grep -q uninstall "$STATE/brew.log" || fail "uninstalled a cask while offline"
  rm "$STATE/offline"
}
half_way_cask() {
  touch "$STATE/apply-fails"
  out=$(printf 'n\ny\n' | "$script" --step packages 2>&1) && fail "a failed apply must exit 1" || [ $? = 1 ] || fail "failed apply: want exit 1"
  check_out "way back" 'Put it back with: brew install --cask freelens'
  rm "$STATE/apply-fails"
  out=$("$script" --step packages < /dev/null 2>&1) || fail "rerun after a failed apply: exit $?"
  check_out "the missing cask gets its command" '^freelens: declared but not installed\. Install it: mise bootstrap packages apply brew-cask:freelens$'
}
packages_dry_run_changes_nothing() {
  before=$(snapshot); : > "$STATE/mise.log"; : > "$STATE/brew.log"
  out=$(yes | "$script" --step packages --dry-run 2>&1) || fail "packages --dry-run: exit $?"
  [ "$(snapshot)" = "$before" ] && [ -z "$(mutations)" ] || fail "packages --dry-run changed something"
}
packages_without_brew_only_lists() {
  mv "$tmp/bin/brew" "$tmp/brew.off"
  out=$(yes | "$script" --step packages 2>&1) || fail "no brew: exit $?"
  check_out "explains" '^brew is not installed, so these cannot be moved by this script'
  mv "$tmp/brew.off" "$tmp/bin/brew"
}
staging_leftovers() {
  mkdir -p "$HOMEBREW_PREFIX/Cellar/hello" "$HOMEBREW_PREFIX/Cellar/jq/1.8.2"
  touch "$HOMEBREW_PREFIX/Cellar/hello/.mise-staging.lock" "$HOMEBREW_PREFIX/Cellar/jq/.mise-staging.lock"
  # every cask prompt answered n, the leftovers prompt answered y
  out=$({ printf 'n\n%.0s' 1 2 3; echo y; } | "$script" --step packages 2>&1) || fail "leftovers: exit $?"
  [ ! -e "$HOMEBREW_PREFIX/Cellar/hello" ] || fail "leftover not removed"
  [ -d "$HOMEBREW_PREFIX/Cellar/jq/1.8.2" ] || fail "removed a Cellar folder that holds a keg"
  ls -d "$HOME"/.dotfiles-migration-backup/*/files"$HOMEBREW_PREFIX"/Cellar/hello > /dev/null || fail "leftover not backed up"
}
```

Count the prompts in each case against the fixture when writing them: the cask prompts come in status order, and a cask mise took over in an earlier case is no longer asked.

- [ ] **Step 2: Run to see them fail.** `bash bin/lib/test-migrate`. Expected: FAIL `formulae need nothing`.
- [ ] **Step 3: Implement** `packages_status`, `homebrew_casks`, `cask_apps`, `app_running`, `reinstall_cask`, `clean_staging_leftovers`, `step_packages`.
- [ ] **Step 4: Run to see them pass.** Expected: `test-migrate: ok`.
- [ ] **Step 5: Dry-run on this Mac**

Run: `migrate/legacy-to-mise --step packages --dry-run`
Expected: `Left alone` names 17 casks. The table holds 16: the 7 `font-*-nerd-font` casks, `jrmatherly/tap/claude-multipass-app`, `codex`, `azure-cli`, `dotnet-sdk`, `freelens`, `coderabbit`, `1password-cli`, `git-credential-manager`, `utm`. 16 `would ask:` lines. `Changed 0 thing(s).`

- [ ] **Step 5a: Try adoption on one font cask first (needs the user's go-ahead)**

  Reinstalling replaces the app bundle, which can drop its macOS privacy permissions. mise's docs say `adopt = true` (set in A4's `[bootstrap.brew]`) takes over an existing artifact whose contents match the download, and that adoption applies only to a cask mise does not see as installed. That suggests a gentler path: hide Homebrew's record and let mise adopt the files in place. This is not tested. Settle it on a cask where a failure costs nothing.

  1. Record the font file's inode: `stat -f %i ~/Library/Fonts/TinosNerdFont-Regular.ttf`.
  2. Move Homebrew's record aside, leaving the font files: `mv /opt/homebrew/Caskroom/font-tinos-nerd-font "$backup/Caskroom-font-tinos-nerd-font"`.
  3. From `$HOME`: `mise bootstrap packages apply --dry-run brew-cask:font-tinos-nerd-font`, read what it plans, then the same without `--dry-run`.
  4. Check: the status JSON reports `managed_by: mise` for the cask, and the inode from 1 is unchanged.

  If both hold, `reinstall_cask` uses this sequence (move the Caskroom record to the backup, apply, check) in place of `brew uninstall --cask`, the privacy warning is dropped from the prompt, and the tests and README are changed to match before Step 6. If the inode changed or mise refused, restore with `mv "$backup/Caskroom-font-tinos-nerd-font" /opt/homebrew/Caskroom/font-tinos-nerd-font`, keep the uninstall-then-apply sequence, and record the result in `migrate/README.md`.

- [ ] **Step 6: Hand the first real run to the user**

The reinstall path has never run on a real machine (it changes the machine). Ask the user to run `migrate/legacy-to-mise --step packages`, answer `y` for `font-tinos-nerd-font` only, and confirm afterwards:

Run: `mise bootstrap packages status --json | jq -r '."brew-cask".packages[] | select(.package == "font-tinos-nerd-font") | .managed_by'`
Expected: `mise`

If it prints `homebrew` or the apply fails, stop. P7 is wrong and this task needs a new design before any app cask is touched.

- [ ] **Step 7: Document, gate, commit**

`migrate/README.md`, `packages` section: the eight points above, P8's exception, and that pkg casks (`dotnet-sdk`, `git-credential-manager`) ask for the password twice, once from each tool.

```bash
pnpm check
git add migrate bin/lib/test-migrate
git commit -m "Add the packages step to the migration script"
git push
```

---

### Task 5: Step `packages`, removing the Homebrew program (lands after A4's fresh-install workflow passes)

**Files:**

- Modify: `migrate/legacy-to-mise` (`offer_homebrew_removal`, called last in `step_packages`)
- Modify: `bin/lib/test-migrate`
- Modify: `migrate/README.md`

**Why not Homebrew's own uninstaller.** The documented procedure is `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"` (https://github.com/Homebrew/install#uninstall-homebrew, https://docs.brew.sh/FAQ#how-do-i-uninstall-homebrew). Read on 2026-11-09, it asks "This will remove your installed packages!" and then deletes `$HOMEBREW_PREFIX/Cellar` and `$HOMEBREW_PREFIX/Caskroom` (its lines 377-378 and 454), every broken symlink under the prefix (line 460), and `/etc/paths.d/homebrew`. Under D5 mise installs into that same `Cellar` and `Caskroom`. Running it would delete every package the new method manages. So this step removes only the Homebrew program, by moving it into the backup folder, and leaves the prefix in place.

**Interfaces:**

- Consumes: `packages_status`, `homebrew_casks`, `ask_typed`, `backup_move`, `PREFIX`.
- Produces: `offer_homebrew_removal`. Returns 0 when it did nothing or succeeded, 1 when it had to restore.

**What it moves** (to `$BACKUP_DIR/files$PREFIX/…`, each with its `mv` line in `RESTORE.txt`):

- every top-level name `git -C "$PREFIX" ls-tree --name-only HEAD` prints, except `bin`. Checked on this Mac: `Library` (which holds `Homebrew` and `Taps`), `completions`, `docs`, `manpages`, `package`, the repository's dot-files and its top-level Markdown and licence files.
- `$PREFIX/bin/brew` (the only tracked file under `bin`).
- `$PREFIX/.git`.
- the links `uninstall.sh` calls `homebrew_prefix_markers`, when present: `etc/bash_completion.d/brew`, `share/doc/homebrew`, `share/man/man1/brew.1`, `share/zsh/site-functions/_brew`, `share/fish/vendor_completions.d/brew.fish`.
- `~/Library/Caches/Homebrew` and `~/Library/Logs/Homebrew`.

**What it leaves, and says it leaves:** `Cellar`, `Caskroom`, `opt`, `bin`, `sbin`, `etc`, `include`, `lib`, `share`, `Frameworks` and `var/homebrew` (the linked-keg records mise reads), because mise's packages live there. `/etc/paths.d/homebrew`, because `/opt/homebrew/bin` must stay on `PATH`. Taps go with `Library`. mise keeps its own tap list in `[bootstrap.brew.taps]`.

**Preconditions, checked in this order. A failed one prints its reason and returns 0 without asking:**

1. Under `DRY_RUN=true` the function prints the result of preconditions 2-6 and the list it would move, then returns.
2. `$PREFIX/bin/brew` exists and `$PREFIX/.git` is a directory. Otherwise `Homebrew is not installed here in the layout this script knows.`
3. `mise bootstrap packages status --missing` exits 0. Otherwise `Packages differ from the config. Fix that first: mise bootstrap packages status`.
4. No cask has `managed_by == "unknown"`.
5. `command -v mise` does not resolve through `$PREFIX/Library`. (It never should. The check is one `case`.)
6. `df -P "$PREFIX" "$HOME" | awk 'NR > 1 { print $1 }' | sort -u | wc -l` is 1, so each move is a rename. Otherwise `The backup folder is on another volume.`

**The prompt.** It lists every remaining `managed_by == "homebrew"` cask with this text, then asks with `ask_typed "remove homebrew"`:

```text
Homebrew's own uninstaller is not used: it deletes Cellar and Caskroom, where mise's packages live.
This moves only the Homebrew program (brew, Library with its taps, the Git checkout) into the backup folder.
These casks stay installed and stay recorded as Homebrew's. They update themselves, or nothing updates them.
Without brew, removing one later means deleting the app and its Caskroom folder by hand:
  <tokens>
Lines in your own files that call "brew shellenv" or set HOMEBREW_ variables (not edited):
  <file>:<line number> for each match in ~/.zsh.local, ~/.zprofile, ~/.zshrc, ~/.bash_profile, ~/.profile that is a real file, not a link into this clone
Type "remove homebrew" to continue. Anything else leaves Homebrew installed.
```

**After the moves:** run `hash -r`, then `mise bootstrap packages status --missing`. Exit 0: print `Homebrew program moved to <dir>. Put it back with the mv lines in RESTORE.txt.` Non-zero: run the recorded `mv` lines for this function in reverse, print `mise reported drift without Homebrew, so it was put back.` and return 1.

- [ ] **Step 1: Write the failing tests**

The test builds a fake prefix: `git init -q "$HOMEBREW_PREFIX"`, tracked `bin/brew`, `Library/Homebrew/x`, `Library/Taps/a/b/x`, `README.md`, committed with the flags `bin/lib/test-upup` uses. Untracked `Cellar/jq/1.8.2/bin/jq`, `Caskroom/ghostty/1.4.0/x`, `var/homebrew/linked/jq`, `bin/jq`. `git` and `df` are the real ones (`PATH` keeps `/usr/bin`). The fake `mise` answers `bootstrap packages status --missing` with exit 1 when `$STATE/drift` exists, and with exit 1 when `$STATE/drift-without-brew` exists and `$HOMEBREW_PREFIX/bin/brew` does not.

```bash
homebrew_removal_is_off_by_default() {
  before=$(snapshot)
  out=$(yes | "$script" --step packages 2>&1) || fail "exit $?"   # "y" is not the typed phrase
  [ -x "$HOMEBREW_PREFIX/bin/brew" ] && [ -d "$HOMEBREW_PREFIX/Library" ] || fail "y removed Homebrew"
  out=$("$script" --step packages < /dev/null 2>&1) || fail "exit $?"
  [ -x "$HOMEBREW_PREFIX/bin/brew" ] || fail "closed stdin removed Homebrew"
  check_out "explains why the uninstaller is not used" "uninstaller is not used: it deletes Cellar and Caskroom"
}
homebrew_removal_refuses_on_drift() {
  touch "$STATE/drift"
  out=$({ printf 'n\n%.0s' 1 2; echo "remove homebrew"; } | "$script" --step packages 2>&1) || fail "exit $?"
  check_out "reason" '^Packages differ from the config'
  [ -x "$HOMEBREW_PREFIX/bin/brew" ] || fail "removed Homebrew despite drift"
  rm "$STATE/drift"
}
homebrew_removal_moves_only_the_program() {
  out=$({ printf 'n\n%.0s' 1 2; echo "remove homebrew"; } | "$script" --step packages 2>&1) || fail "exit $?: $out"
  for gone in bin/brew Library .git README.md; do [ ! -e "$HOMEBREW_PREFIX/$gone" ] || fail "$gone still there"; done
  for kept in Cellar/jq/1.8.2/bin/jq Caskroom/ghostty/1.4.0/x var/homebrew/linked/jq bin/jq; do [ -e "$HOMEBREW_PREFIX/$kept" ] || fail "$kept was removed"; done
  bak=$(echo "$HOME"/.dotfiles-migration-backup/*/files"$HOMEBREW_PREFIX")
  [ -x "$bak/bin/brew" ] && [ -e "$bak/Library/Taps/a/b/x" ] && [ -d "$bak/.git" ] || fail "program not in the backup"
  # the restore file puts it back
  sh "${bak%/files*}/RESTORE.txt"
  [ -x "$HOMEBREW_PREFIX/bin/brew" ] && [ -d "$HOMEBREW_PREFIX/.git" ] || fail "RESTORE.txt did not restore Homebrew"
}
homebrew_removal_restores_itself_when_mise_drifts() {
  touch "$STATE/drift-without-brew"
  out=$({ printf 'n\n%.0s' 1 2; echo "remove homebrew"; } | "$script" --step packages 2>&1) && fail "want exit 1" || [ $? = 1 ] || fail "want exit 1"
  [ -x "$HOMEBREW_PREFIX/bin/brew" ] && [ -d "$HOMEBREW_PREFIX/Library" ] || fail "did not put Homebrew back"
  check_out "says so" 'so it was put back'
  rm "$STATE/drift-without-brew"
}
```

Set the `n` count in each `printf` to the number of cask prompts the fixture produces at that point. `RESTORE.txt` must be runnable with `sh` for the third case, so every line the script writes into it is a complete command (Task 1's `backup_move`, `backup_copy`, and the `brew install --cask` lines).

- [ ] **Step 2: Run to see them fail.** Expected: FAIL `explains why the uninstaller is not used`.
- [ ] **Step 3: Implement `offer_homebrew_removal`** and call it last in `step_packages`.
- [ ] **Step 4: Run to see them pass.** Expected: `test-migrate: ok`.
- [ ] **Step 5: Dry-run on this Mac**

Run: `migrate/legacy-to-mise --step packages --dry-run | sed -n '/Homebrew program/,$p'`
Expected: preconditions 2-6 with their results, the would-move list (27 top-level names from `git ls-tree`, `bin` excluded, `bin/brew`, `.git`, the completion links, the two cache folders), and `Changed 0 thing(s).`

- [ ] **Step 6: Leave the real run to the user, and say what is unproven**

Tell the user: moving the program is reversible with `sh ~/.dotfiles-migration-backup/<timestamp>/RESTORE.txt`, and the proof that mise works with no Homebrew program is A4's `fresh-install` workflow, which must have passed. Do not run it for them.

- [ ] **Step 7: Document, gate, commit**

`migrate/README.md`, under `packages`: a subsection "Removing Homebrew" with the "why not the uninstaller" paragraph and its two links, the moved and left lists, the preconditions, the typed phrase, and the restore command.

```bash
pnpm check
git add migrate bin/lib/test-migrate
git commit -m "Offer to move the Homebrew program aside in the migration script"
git push
```

---

### Task 6: Step `dotfiles` (lands with A5, before A5's first apply on this Mac)

**Files:**

- Modify: `migrate/legacy-to-mise` (`step_dotfiles`, remove the `MIGRATE_SELFTEST` hook)
- Modify: `bin/lib/test-migrate` (remove `helpers_back_up_before_replacing`)
- Modify: `migrate/README.md`

**Interfaces:**

- Consumes: `mise dot status --json`. Shape, checked in a scratch config: `{"files":[{"target":"~/.one","source":"…","mode":"symlink"|"symlink-each"|"copy","state":"applied"|"missing"|"differs"|"source_missing","reason":"…"}],…}`. A `symlink-each` entry is one row whose `reason` names only its first problem, with the path prefixed. A5 declares one such entry, `"~/.claude/rules"`, and 37 single-file entries, so the status alone cannot list every conflict.
- Consumes: `mise dot apply --dry-run`. Checked: with a real file in the way it exits 1 and prints `mise ERROR files: refusing to overwrite existing files (use --force):` on stderr, followed by one line per conflict, two spaces then `~/path`. That list is complete across `symlink` and `symlink-each` entries. With no conflict it exits 0 and prints one `ln -sf` line per entry, not per file.
- Consumes: `mise dot apply --yes`, `mise dot status --missing` (exit 1 on any entry not in its desired state).
- Checked behaviour the step relies on: one conflict makes the whole `mise dot apply` fail, and nothing else in that run is applied. A link that points elsewhere is repointed without `--force` and without a copy, and neither the status nor the dry run lists it under a `symlink-each` entry.
- From the A5 plan's "Part B hook" (measured there, not here): mise turns a whole-directory `~/.claude/rules` link into a real folder of links by itself. An old link to the clone's physical path already reads `applied`. `~/.codex/config.toml` as a symlink reads `applied` and stays a link. An entry in `tilde/.config/mise/config.local.toml` replaces the `conf.d` entry with the same key.
- Produces: `dot_conflicts` (prints the absolute path of each conflict from the dry run), `dot_foreign_links` (prints `target<TAB>old path`), `step_dotfiles`. `step_dotfiles` returns the exit status of the final `mise dot status --missing`.

**`dot_foreign_links`:** for each status entry with mode `symlink`, the target when it is a symlink and not `-ef` its `source`. For each entry with mode `symlink-each`, the same test for every file `find "$source" -type f` prints, mapped onto the target folder. A link whose `readlink` starts with `$REPO/` or `$HOME/dotfiles/` is an old-style link, not a foreign one. It is counted and not listed.

**Behaviour, in order:**

1. **The older whole-directory links.**
   - `~/.claude/rules` is a symlink and `-ef "$REPO/tilde/.claude/rules"`: print `~/.claude/rules is one link into the clone. mise replaces it with a real folder of links.` Nothing to do.
   - `~/.ssh` is a symlink and `-ef "$REPO/tilde/.ssh"`: print the commands below and return 1. The script does not move key files, and `--force` there would replace the tracked file with a link to itself.

     ```text
     ~/.ssh is one link into the clone. Fix it by hand, then run this step again:
       rm ~/.ssh && mkdir -m 700 ~/.ssh
       mv <clone>/tilde/.ssh/<every file except config> ~/.ssh/
     ```

2. **Mole's per-Mac whitelist.** The old script linked `~/.config/mole/<name>` to `mole/<name>.local` when that file existed. A5 declares the shared `mole/<name>`, so a plain apply would repoint the link. For each of `whitelist` and `whitelist_optimize` with `$REPO/mole/<name>.local` present, the entry `"~/.config/mole/<name>" = { source = "~/dotfiles/mole/<name>.local", mode = "symlink" }` must be in `$REPO/tilde/.config/mise/config.local.toml` under `[dotfiles]`. When the file already holds that key: nothing. When the file is missing or has no `[dotfiles]` line: `ask "Keep this Mac's Mole <name> list by adding it to config.local.toml?"`, `backup_copy` the file when it exists, append the table header once and the entry. When the file has a `[dotfiles]` table without the key: print the line to add by hand and return 1 before any apply. On no, print `~/.config/mole/<name> will point at the shared list.`
3. **Codex.** `~/.codex/config.toml` is a symlink: `ask "Replace the ~/.codex/config.toml link with a private copy?"`, `backup_note links.tsv`, append the `ln -sfn` line to `RESTORE.txt`, `rm` the link. The apply then seeds the copy. A regular file is never touched.
4. **Find conflicts and foreign links.** Run `dot_conflicts`. For each, when the path resolved with `cd -P` on its parent lies inside `REPO`, print `<target>: resolves into the clone, not touched` and return 1 after the listing. That is a whole-directory link this script does not know. Run `dot_foreign_links`.
5. **Print** `<n> old-style link(s): already in place or repointed by mise, nothing is lost.` Then the conflicts as `<target>: a real file or folder is in the way` and the foreign links as `<target>: a link to <path> will be repointed`.
6. **Ask once.** With at least one conflict or foreign link: `Back up the <n> item(s) above and let mise link them?` With none of those but `mise dot status --missing` failing (the half-migrated case): `Run mise dot apply to link what is missing?` With neither, go to 8. On no, print `Left as they are. Finish with: mise dot apply` and go to 8.
7. `backup_move` each conflict. For each foreign link, `backup_note links.tsv "<target><TAB><old path>"` and append `ln -sfn '<old path>' '<target>'` to `RESTORE.txt`. Then `run mise dot apply --yes`. Never `--force`. Under `--dry-run` nothing is moved and the dry run from point 4 is the report.
8. **Old links nothing declares** (report only). List symlinks whose `readlink` starts with `$REPO/` or `$HOME/dotfiles/` and whose path is not a `target` in the status, found by `find` with `-type l` at `-maxdepth 1` in `~`, `~/.claude/rules`, `~/.claude/skills`, `~/.codex`, `~/.gnupg`, `~/.ssh`, `~/.config/mole`, and at `-maxdepth 1` in `~/.config`, plus the three paths `~/Library/Application Support/Code/User`, `…/lazydocker/config.yml`, `…/rtk/config.toml`. Print each with `(dangling)` when its target is gone. These are the places the old `symlinks.sh` linked into.
9. **Firefox** (report only). The old script made hard links, and A5's `setup/dotfiles-extras.sh` remakes them. Find the profile as the old helper did: the first directory under `~/Library/Application Support/Firefox/Profiles` matching `*dev-edition*`. For `user.js`, `chrome/userContent.css`, `chrome/userChrome.css`: print `hard link ok` when the profile file `-ef` the clone's `firefox/` file, else `not linked to the clone (the bootstrap task links it)`. No profile: one line saying so.
10. Run `mise dot status --missing` and return its status. On 0 print `All dotfiles are in their declared state.`

- [ ] **Step 1: Write the failing tests**

The fake `mise` reads `$STATE/dot-targets`, one `target<TAB>source` per line. `"dot status --json")` prints `$STATE/dot.json`. `"dot status --missing")` exits 0 only when every target is a link `-ef` its source. `"dot apply --dry-run")` prints the real error text on stderr (`mise ERROR files: refusing to overwrite existing files (use --force):` then two spaces and the `~/` path per target that exists and is not a link) and exits 1, or exits 0 with none. `"dot apply --yes")` fails the same way, and otherwise runs `ln -sfn` for each target. `dot.json` holds one `symlink` row per target and one `symlink-each` row `"~/.claude/rules"` whose `source` is `$REPO_COPY/tilde/.claude/rules`.

```bash
dotfiles_backs_up_then_applies() {
  phase dotfiles
  echo mine > "$HOME/.zshrc"                                   # a real file in the way
  ln -s /etc/hosts "$HOME/.gitconfig"                          # a foreign link
  ln -s "$REPO_COPY/tilde/.old" "$HOME/.old"                   # an old link nothing declares, dangling
  ln -s "$HOME/dotfiles/tilde/.starship.toml" "$HOME/.starship.toml"   # an old-style link
  # dot-targets and $REPO_COPY/tilde hold .zshrc, .gitconfig, .starship.toml and .zshenv, each its own `symlink` row
  out=$(echo y | "$script" --step dotfiles 2>&1) || fail "dotfiles: exit $?: $out"
  bak=$(echo "$HOME"/.dotfiles-migration-backup/*)
  [ "$(cat "$bak/files$HOME/.zshrc")" = mine ] || fail "real file not backed up before apply"
  grep -qF "ln -sfn '/etc/hosts' '$HOME/.gitconfig'" "$bak/RESTORE.txt" || fail "foreign link not recorded"
  ! grep -q -- '--force' "$STATE/mise.log" || fail "passed --force"
  awk '/dot apply --yes/ { exit !seen } /dot apply --dry-run/ { seen = 1 }' "$STATE/mise.log" || fail "applied before the dry run listed the conflicts"
  check_out "old-style count" '^1 old-style link\(s\)'
  check_out "undeclared old link" '\.old .*\(dangling\)'
  check_out "ends clean" '^All dotfiles are in their declared state\.$'
}
dotfiles_second_run_changes_nothing() {
  before=$(snapshot); : > "$STATE/mise.log"
  out=$(echo y | "$script" --step dotfiles 2>&1) || fail "dotfiles rerun: exit $?"
  [ "$(snapshot)" = "$before" ] && [ -z "$(mutations)" ] || fail "dotfiles rerun changed something"
}
dotfiles_declined_or_dry_run_changes_nothing() {
  echo mine > "$HOME/.zprofile"   # dot-targets gains ~/.zprofile
  for how in "--dry-run" ""; do
    before=$(snapshot); : > "$STATE/mise.log"
    out=$("$script" --step dotfiles $how < /dev/null 2>&1) || true
    [ "$(snapshot)" = "$before" ] && [ -z "$(mutations)" ] || fail "dotfiles $how changed something"
  done
}
dotfiles_never_moves_a_repo_file() {
  ln -s "$REPO_COPY/tilde/.claude/skills" "$HOME/.claude/skills"   # a whole-directory link the script does not know
  # dot-targets gains ~/.claude/skills/x, so the dry run lists it as a conflict
  out=$(echo y | "$script" --step dotfiles 2>&1) && fail "want exit 1" || [ $? = 1 ] || fail "want exit 1"
  [ -e "$REPO_COPY/tilde/.claude/skills/x" ] || fail "moved a tracked file out of the clone"
  check_out "says why" 'resolves into the clone, not touched'
}
dotfiles_leaves_the_whole_rules_link_to_mise() {
  ln -s "$REPO_COPY/tilde/.claude/rules" "$HOME/.claude/rules"
  out=$("$script" --step dotfiles < /dev/null 2>&1) || true
  check_out "says mise handles it" 'mise replaces it with a real folder of links'
  [ -e "$REPO_COPY/tilde/.claude/rules/a.md" ] || fail "removed the clone's rules"
  rm "$HOME/.claude/rules"
}
dotfiles_keeps_the_local_mole_list() {
  echo x > "$REPO_COPY/mole/whitelist.local"; local_toml="$REPO_COPY/tilde/.config/mise/config.local.toml"
  out=$(echo y | "$script" --step dotfiles 2>&1) || true
  grep -qF '"~/.config/mole/whitelist" = { source = "~/dotfiles/mole/whitelist.local", mode = "symlink" }' "$local_toml" || fail "local Mole entry not written"
  [ "$(grep -c '^\[dotfiles\]' "$local_toml")" = 1 ] || fail "wrote a second [dotfiles] table"
  before=$(cksum < "$local_toml"); out=$(echo y | "$script" --step dotfiles 2>&1) || true
  [ "$(cksum < "$local_toml")" = "$before" ] || fail "wrote the Mole entry twice"
  printf '[dotfiles]\n"~/.x" = { source = "~/x", mode = "symlink" }\n' > "$local_toml"; : > "$STATE/mise.log"
  out=$(echo y | "$script" --step dotfiles 2>&1) && fail "want exit 1 with a [dotfiles] table it cannot edit" || true
  ! grep -q 'dot apply --yes' "$STATE/mise.log" || fail "applied before the Mole entry was in place"
  rm "$local_toml" "$REPO_COPY/mole/whitelist.local"
}
dotfiles_replaces_a_codex_config_link() {
  mkdir -p "$HOME/.codex"; ln -s "$REPO_COPY/tilde/.codex/config.toml" "$HOME/.codex/config.toml"
  out=$(echo y | "$script" --step dotfiles 2>&1) || true
  [ ! -L "$HOME/.codex/config.toml" ] || fail "codex config is still a link"
  grep -qF "'$HOME/.codex/config.toml'" "$HOME"/.dotfiles-migration-backup/*/RESTORE.txt || fail "codex link not recorded"
  echo mine > "$HOME/.codex/config.toml"; out=$(echo y | "$script" --step dotfiles 2>&1) || true
  [ "$(cat "$HOME/.codex/config.toml")" = mine ] || fail "touched a regular codex config"
}
half_way_dotfiles() {
  # the conflict was backed up by an earlier run but apply never ran: ~/.zprofile is absent
  out=$("$script" --step dotfiles < /dev/null 2>&1) || true
  check_out "closed stdin: tells the user what is left" '^Left as they are\. Finish with: mise dot apply$'
  out=$(echo y | "$script" --step dotfiles 2>&1) || fail "half-way rerun: exit $?"
  grep -qx 'mise dot apply --yes' "$STATE/mise.log" || fail "did not finish the apply on the rerun"
}
firefox_hard_links_are_reported() {
  p="$HOME/Library/Application Support/Firefox/Profiles/abc.dev-edition-default"; mkdir -p "$p/chrome"
  ln "$REPO_COPY/firefox/user.js" "$p/user.js"; echo other > "$p/chrome/userChrome.css"
  out=$("$script" --step dotfiles < /dev/null 2>&1) || true
  check_out "linked one" 'user\.js: hard link ok'
  check_out "unlinked one" 'userChrome\.css: not linked to the clone'
}
```

- [ ] **Step 2: Run to see them fail.** Expected: FAIL `real file not backed up before apply`.
- [ ] **Step 3: Implement `step_dotfiles`. Delete the `MIGRATE_SELFTEST` hook and its test case.**
- [ ] **Step 4: Run to see them pass.** Expected: `test-migrate: ok`.
- [ ] **Step 5: Dry-run on this Mac**

Run: `migrate/legacy-to-mise --step dotfiles --dry-run`
Expected: no conflict lines (A5's author measured 37 of its 38 entries `applied` on this Mac and one `differs`, the Mole link), one `would ask:` line for Mole's `whitelist` (this Mac has `mole/whitelist.local`), three `hard link ok` lines, and `Changed 0 thing(s).` Any conflict line here is a difference between A5's entries and the old script. Report it to the A5 owner before A5's first apply.

- [ ] **Step 6: Document, gate, commit**

`migrate/README.md`, `dotfiles` section: the ten points, and "never `--force`: mise's `--force` replaces a file with no copy".

```bash
pnpm check
git add migrate bin/lib/test-migrate
git commit -m "Add the dotfiles step to the migration script"
git push
```

---

### Task 7: Step `setup`, and the old-method-name check (lands with A6, before A6's first bootstrap on this Mac)

**Files:**

- Modify: `migrate/legacy-to-mise` (`step_setup`)
- Modify: `bin/lib/test-migrate`
- Modify: `bin/lib/test-conventions`
- Modify: `migrate/README.md`

**Interfaces:**

- Consumes: `backup_copy`, `backup_move`, `backup_note`, `ask`, `run`. `claude mcp get mise`, whose output holds a line `  Command: <path>` (checked on this Mac: `/opt/homebrew/bin/mise`).
- Produces: `step_setup`. Returns 0.

**What only the old method left, and the decision for each:**

| Item | Decision | Why |
| --- | --- | --- |
| `/etc/pam.d/sudo_local` whose content is not exactly `auth       sufficient     pam_tid.so` | Show `diff`, `backup_copy` it, print that the first `mise bootstrap` rewrites it and that `sudo cp <backup> /etc/pam.d/sudo_local` restores it. Nothing is removed. Path overridable as `${MIGRATE_SUDO_LOCAL:-/etc/pam.d/sudo_local}` for the test. | The old `setup.sh` wrote the file only when missing, so a hand-edited one survived. A6 declares it in `[bootstrap.files]`. |
| `/etc/pam.d/sudo_local` with exactly that content | Print `sudo_local: as declared, kept`. | The new method owns it. |
| `${MISE_DATA_DIR:-$HOME/.local/share/mise}/installs/rust` | `ask "Forget mise's old rust install so its shims stop shadowing rustup?"`, `backup_move` it, `run mise reshim`. | Moved here from `setup/misc.sh:189-199` by A6 (inventory M16). |
| `~/.cargo/bin/rustup` that differs (`cmp -s`) from `$PREFIX/opt/rustup/bin/rustup` | Print the old script's hint: `rm -rf ~/.cargo/bin ~/.rustup && /opt/homebrew/opt/rustup/bin/rustup default stable`. Report only. | A6 inventory M17. The toolchain is the owner's call. |
| The `mise` MCP server registered with a command other than `$(command -v mise)` | `ask "Re-register the mise MCP server with <new path>?"`, `backup_note mcp.txt "<old command>"`, append `claude mcp remove mise -s user && claude mcp add --scope user mise -- '<old command>' mcp` to `RESTORE.txt`, then `run claude mcp remove mise -s user` and `run claude mcp add --scope user mise -- "$(command -v mise)" mcp`. Skipped when `claude` is not on `PATH` or the server is not registered. | A4 installs mise with its own installer, so Homebrew's path goes stale. The new `misc.sh` only warns. |
| `private/setup-logs/` | Print `setup logs: kept (the new setup.sh still writes them)`. | A6 keeps the log path. |
| `~/dotfiles` | Print `~/dotfiles: kept (lazygit's config cannot expand variables)`. | A6's `setup.sh` still makes it. |
| `/etc/shells` entry and the login shell | Not mentioned. | Unchanged by the new method. |

- [ ] **Step 1: Write the failing tests**

The fake `claude` answers `mcp get mise` from `$STATE/mcp-command` (`mise:` then `  Command: <content>`), exits 1 when the file is absent, and on `mcp add --scope user mise -- <path> mcp` writes `<path>` to that file. The fake `mise` gains `reshim) : ;;`.

```bash
setup_backs_up_a_hand_edited_sudo_local() {
  phase setup
  export MIGRATE_SUDO_LOCAL="$tmp/sudo_local"
  printf 'auth sufficient pam_tid.so\nauth sufficient pam_reattach.so\n' > "$MIGRATE_SUDO_LOCAL"
  out=$("$script" --step setup < /dev/null 2>&1) || fail "setup: exit $?: $out"
  cmp -s "$(echo "$HOME"/.dotfiles-migration-backup/*/files"$MIGRATE_SUDO_LOCAL")" "$MIGRATE_SUDO_LOCAL" || fail "sudo_local not copied to the backup"
  [ -f "$MIGRATE_SUDO_LOCAL" ] || fail "sudo_local was removed"
  check_out "restore command" 'sudo cp .* /etc/pam.d/sudo_local'
  echo 'auth       sufficient     pam_tid.so' > "$MIGRATE_SUDO_LOCAL"
  out=$("$script" --step setup < /dev/null 2>&1); check_out "declared content is kept" '^sudo_local: as declared, kept$'
}
setup_forgets_the_old_rust_install() {
  export MISE_DATA_DIR="$tmp/mise-data"; mkdir -p "$MISE_DATA_DIR/installs/rust/1.90"
  out=$(echo y | "$script" --step setup 2>&1) || fail "setup rust: exit $?"
  [ ! -e "$MISE_DATA_DIR/installs/rust" ] || fail "rust install still there"
  ls -d "$HOME"/.dotfiles-migration-backup/*/files"$MISE_DATA_DIR"/installs/rust/1.90 > /dev/null || fail "rust install not backed up"
  grep -qx 'mise reshim' "$STATE/mise.log" || fail "no reshim"
}
setup_reregisters_the_mcp_server() {
  echo /opt/homebrew/bin/mise > "$STATE/mcp-command"
  out=$(echo y | "$script" --step setup 2>&1) || fail "setup mcp: exit $?"
  [ "$(cat "$STATE/mcp-command")" = "$tmp/bin/mise" ] || fail "mise MCP server not re-registered with the mise on PATH"
  grep -qF "mise -- '/opt/homebrew/bin/mise' mcp" "$HOME"/.dotfiles-migration-backup/*/RESTORE.txt || fail "old registration not recorded"
}
setup_second_run_and_dry_run_change_nothing() {
  for how in "" "--dry-run"; do
    before=$(snapshot); : > "$STATE/mise.log"; : > "$STATE/claude.log"
    out=$(yes | "$script" --step setup $how 2>&1) || fail "setup $how rerun: exit $?"
    [ "$(snapshot)" = "$before" ] && [ -z "$(mutations)" ] || fail "setup $how rerun changed something"
  done
  check_out "kept items" '^~/dotfiles: kept'
}
```

- [ ] **Step 2: Run to see them fail.** Expected: FAIL `sudo_local not copied to the backup`.
- [ ] **Step 3: Implement `step_setup`.**
- [ ] **Step 4: Run to see them pass.** Expected: `test-migrate: ok`.
- [ ] **Step 5: Dry-run on this Mac**

Run: `migrate/legacy-to-mise --step setup --dry-run`
Expected: `sudo_local: as declared, kept` (this Mac's file is the one line). No rust line (`~/.local/share/mise/installs/rust` does not exist here). One `would ask: Re-register the mise MCP server` line if A4 moved mise off `/opt/homebrew/bin/mise`, none otherwise. The two `kept` lines. `Changed 0 thing(s).`

- [ ] **Step 6: Add the old-method-name check to `bin/lib/test-conventions`**

Part A's phases delete these names from every doc and script. This check keeps them deleted. After the removal-date check:

```bash
# Only the migration script may name what Part A deleted (spec: Part A carries no knowledge of the old method)
old=$(git grep -lE 'Brewfile|brewpick|setup/(brew|symlinks|macos)\.sh' -- . ':!migrate' ':!bin/lib/test-migrate' ':!bin/lib/test-conventions' ':!docs/superpowers' || true)
[ -z "$old" ] || fail "the old setup method is named outside migrate/: $old"
```

Run: `bash bin/lib/test-conventions | tail -1`
Expected: `conventions: all checks passed`. A failure names the files a Part A phase missed. Fix those docs in this commit (D12), not the check. On 2026-11-09, before Part A, `git grep -lE 'Brewfile|brewpick' -- . ':!migrate' ':!docs/superpowers' | wc -l` printed 41, so the check must not land before A6.

Add to the header's description sentence: "that only migrate/ names the old setup method,".

- [ ] **Step 7: Document, gate, commit**

`migrate/README.md`, `setup` section: the decision table above as prose.

```bash
pnpm check
git add migrate bin/lib/test-migrate bin/lib/test-conventions
git commit -m "Add the setup step to the migration script"
git push
```

- [ ] **Step 8: Hand the real runs to the user**

With every phase landed, ask the user to run `migrate/legacy-to-mise --dry-run`, read it, then run `migrate/legacy-to-mise`. The implementer does not run it without `--dry-run`. Afterwards:

Run: `mise bootstrap status --missing; echo "exit $?"`
Expected: `exit 0`
Run: `migrate/legacy-to-mise --dry-run | tail -1`
Expected: `Changed 0 thing(s).`

---

### Task 8: Removal (on or after 2027-02-28)

**Files:**

- Delete: `migrate/` (the script and its README)
- Delete: `bin/lib/test-migrate`
- Modify: `bin/lib/check` (remove `migrate/legacy-to-mise` from `shell_scripts`, `"migrate/*"` from the Prettier globs, and the `test-migrate` line with its comment)
- Modify: `package.json` (remove `\"migrate/*\"` from `scripts.format`)
- Modify: `bin/lib/test-conventions` (remove the removal-date check and its header words; in the old-method-name check drop the `':!migrate'` and `':!bin/lib/test-migrate'` exclusions)
- Modify: `README.md` (remove the section "Migrating an existing machine")
- Modify: `docs/superpowers/specs/2026-11-09-mise-first-setup-and-settings-ui.md` only by `git mv` to `specs/completed/` when every other plan built on it is completed

**Interfaces:** none. Nothing outside these files refers to `migrate/` (the name check in Task 7 guarantees it).

- [ ] **Step 1: Confirm no machine still needs it.** Ask the user whether every Mac set up the old way has been migrated. `~/.dotfiles-migration-backup/` on a Mac is the sign it ran there. Stop if any has not.
- [ ] **Step 2: Delete and edit** the files above.
- [ ] **Step 3: Verify nothing refers to it**

Run: `git grep -nE 'migrate/|test-migrate|legacy-to-mise|dotfiles-migration-backup|CONVENTIONS_TODAY' -- . ':!docs/superpowers'`
Expected: no output.

- [ ] **Step 4: Gate and commit**

Run: `pnpm check`
Expected: exit 0.

```bash
git add -A migrate bin/lib/test-migrate bin/lib/check bin/lib/test-conventions package.json README.md
git commit -m "Remove the migration script"
git push
```

- [ ] **Step 5: Close the plan.** `git mv docs/superpowers/plans/2026-11-09-b-migration-script.md docs/superpowers/plans/completed/`, commit and push. Tell the user that `~/.dotfiles-migration-backup/` on each Mac can be deleted by hand.

---

## Not verified, and the command that settles each

| Claim | Why it is unverified | Command |
| --- | --- | --- |
| After `brew uninstall --cask X`, `mise bootstrap packages apply --yes brew-cask:X` installs it and status reports `managed_by: "mise"` | It changes the machine | Task 4 Step 6, on `font-tinos-nerd-font` |
| mise upgrades a formula Homebrew installed | No formula was outdated on 2026-11-09 | When `brew outdated --formula` lists one: `mise bootstrap packages upgrade --manager brew --dry-run` names it |
| mise's brew backend works with `Library/` and `.git` moved out of `/opt/homebrew` | It changes the machine | A4's `fresh-install` workflow passing, then Task 5's own post-check, which restores on failure |
| An entry in `config.local.toml` replaces the `conf.d` entry with the same key, and mise converts a whole-directory `~/.claude/rules` link itself | Measured by the A5 plan's author, not here | Task 6 Step 5, then `mise dot status --verbose` after the user's real run shows `~/.config/mole/whitelist` as `applied` |
| A4 and A5 create `30-packages.toml` and `40-dotfiles.toml` | Their plans were not written when this one was. A1, A3 and A6 were checked | `ls tilde/.config/mise/conf.d/` after each phase lands |
| `settings/registry.toml` writes `kind`, `key` and `access` one per line as `name = "value"` | A2 is not built | Task 2 Step 5 |
| `mise bootstrap packages apply --dry-run` and `mise dot apply --dry-run` touch no network | Not measured | Run each with Wi-Fi off |
