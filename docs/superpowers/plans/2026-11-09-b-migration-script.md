# Migration Script (Part B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `migrate/legacy-to-mise` moves a Mac set up by the old bash and Brewfile method onto the mise-first method, one step per Part A phase, and is deleted on or after 2027-02-28.

**Architecture:** One standalone bash script with five steps (`env`, `macos`, `packages`, `dotfiles`, `setup`). It is the only file that knows the old layout, and it carries that knowledge as literals because Part A deletes the old scripts. It reads state through mise's JSON output and macOS's `/usr/bin/jq`, changes things only after a prompt, and moves what it replaces into a timestamped backup folder with a restore command per item. One self-check, `bin/lib/test-migrate`, runs every step against a scratch `HOME` with fake `brew`, `mise` and `claude` on `PATH`.

**Tech Stack:** bash 3.2 (`#!/bin/bash`), `/usr/bin/jq` (ships with macOS, 1.7.1 on this Mac), mise 2026.11.5 or newer, shellcheck, Prettier with `prettier-plugin-sh`.

**Spec:** `docs/superpowers/specs/2026-11-09-mise-first-setup-and-settings-ui.md` ("Two parts", D5, D11, "Verified facts", phase "B. Migration script", Risks, and "Decisions" items 2, 5, 6, 7 and 12: the Time Machine and firewall switches are on by default, so Task 3 warns a Mac that would change at its next `set-defaults`; Homebrew is removed only after every Homebrew-managed app is reinstalled or adopted, which P16, P17 and Tasks 4 and 5 enforce; the Codex config is a `merge = "missing"` edit, which Task 6 prepares for; every `ask` permission rule lands in A7, so this plan adds none; the gate for removing Homebrew is the VM run recorded in plan A6's Task 6, which Task 5 Step 6 checks).

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
- Every commit names its files. No `git add -A`, no `git add .`, no bare directory. The working tree holds an unrelated uncommitted change to `agents/claude-settings.json` that must never enter one of this plan's commits.
- Tested on this Mac only (D11). Steps that change this Mac are run by the user, never by the implementer. Each such step says so in its title. The implementer runs the script only with `--dry-run`, or against the scratch `HOME` of `bin/lib/test-migrate`.
- No `ask` permission rule is added by this plan (spec decision 7). A7's Task 8, the last task of the last phase, adds the five rules for this script (P15). Until it lands, the owner's go-ahead in chat is the only guard on a run without `--dry-run`.
- The script exports `HOMEBREW_NO_ANALYTICS=1` before its first `brew` call. A4 deletes the `HOMEBREW_*` exports from `zsh/env.zsh`, and without one `brew analytics state` reports analytics enabled (measured). Every `brew` command this plan or the script tells the user to type carries the same prefix.
- The script calls mise through one resolved path, `MISE`, never by a fresh `PATH` lookup. The `packages` step replaces the mise binary while it runs (Task 4).
- A phase gate is `pnpm check` plus `bin/lib/test-migrate`. `mise bootstrap status --missing` and `mise bootstrap packages status --missing` are informational: apps rewrite preferences and a missing package is normal mid-migration, so no step requires either to exit 0.
- Line numbers are from commit `9af6244`. An earlier phase may have moved them, so find the quoted text with `grep -n` before editing.

## Review Focus

1. **A Mac that never used the old method.** Every step prints "nothing to migrate", exits 0 and creates no backup folder. Test in Task 1 (`never_old`), extended by each step's task.
2. **A Mac migrated half way.** A second run after an interrupted first run finishes the work and repeats nothing. A cask Homebrew uninstalled that mise did not install shows as `missing`, and the script prints the apply command for it. Tests in Tasks 4 and 6 (`half_way_*`).
3. **`~/.zsh.local` with a value holding spaces or quotes.** `export K='a b "c"'` reaches `mise set --override` as one argument with the exact value. A value the script cannot read safely is skipped with the manual command. Tests in Task 2 (`env_quoting`).
4. **A Homebrew-installed cask that is running.** The script skips it, names it and tells the user to quit the app. It never uninstalls a running app. Test in Task 4 (`cask_running`).
5. **No network.** The `packages` step refuses to move mise or uninstall any cask when `curl -fsI --max-time 5 https://formulae.brew.sh/` fails. Every other step works offline. Test in Task 4 (`no_network`).
6. **mise replaced while the script runs.** The `packages` step uninstalls the mise binary it was started with, and every shim on this Mac is a link to that binary. The shims are repointed before the uninstall, the script never calls the old path afterwards, and a failed installer leaves Homebrew's mise in place. Tests in Task 4 (`mise_move_*`, `half_way_mise_shims`).
7. **Homebrew removed while it still owns something** (spec decision 5). While any cask is still `managed_by: "homebrew"`, or a formula installed on request or a `Caskroom` cask is neither declared in mise's package config nor listed in the drop file, Task 5 names each one and never shows the typed prompt. Typing the phrase anyway changes nothing. Task 4 offers every Homebrew-managed cask, the self-updating ones too (P17), so a cask still listed is one the owner declined, and Task 4 says so when they decline it. Tests in Task 4 (`packages_lists_and_reinstalls_only_the_picked`) and Task 5 (`homebrew_removal_refuses_while_homebrew_owns_packages`).

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
| P13 | mise itself moves first. The `packages` step installs mise with its own installer to `~/.local/bin/mise`, reshims with the new binary, and only then runs `brew uninstall mise`. Nothing else in the step runs until this is done or declined. | Measured on this Mac: `/opt/homebrew/opt/mise/lib/.disable-self-update` exists, so `mise self-update` refuses. All 149 files in `~/.local/share/mise/shims` are links to `/opt/homebrew/bin/mise`. A prune dry-run lists `remove brew:mise@2026.11.5`. `brew uses --installed mise` prints nothing. Scratch run, mise 2026.11.5: `mise reshim` run by a copy of the binary repoints every shim to that copy, whether the old target still exists or not. `mise ls` does not repoint. |
| P14 | A package this Mac has that no config declares is offered a line in the gitignored `tilde/.config/mise/config.local.toml`. The script asks only about formulae Homebrew recorded as installed on request and casks in `Caskroom` that the status does not list. It never asks about `mise` or the seven formulae A4 moved to `[tools]`. | Scratch run: a `[bootstrap.packages]` table in `config.local.toml` merges with the one in `conf.d`, and `"brew:jrmatherly/ai-kb/aikb"` and `"brew-cask:signal"` there read `installed`. `INSTALL_RECEIPT.json` has `installed_on_request: true` for `aikb` and `ai-kb-lite` and `false` for the old `openssl@3` keg. A4's P16: mise finds a tap at its default GitHub URL with no taps entry. |
| P15 | `.claude/settings.json` asks before every way an agent can start `migrate/legacy-to-mise`, `--dry-run` included. The five rules and their check are added by A7's Task 8, not here (spec decision 7: every `ask` rule lands in the last phase, so none prompts during the build). This plan's Task 8 removes them with the script. | The repo's rule for `sysup` and `set-defaults` (`bin/lib/test-conventions`): a command that changes the machine asks. |
| P8 | A removed app bundle is not copied to the backup folder (size). The backup records token and version in `casks.tsv`, and the restore command is `HOMEBREW_NO_ANALYTICS=1 brew install --cask <token>`. This is the one exception to "back up what you replace", and the prompt says so. | Casks have no version pins (spec). |
| P9 | Formulae need no migration. mise reads the prefix, so a Homebrew-installed formula counts as installed, and `upgrade` installs the current bottle over it. The step reports `needs_repair` entries and the `prune --dry-run` count. It never prunes. | Scratch run: `brew:jq` `installed`, `brew:rustup` `needs_repair`. mise brew docs. |
| P10 | Homebrew's documented uninstaller is not used. It deletes `Cellar` and `Caskroom`, where mise's packages live (D5). The step moves only the Homebrew program into the backup folder. | `uninstall.sh` lines 377-378, 423 and 454, cited in Task 5. |
| P11 | `/etc/pam.d/sudo_local`, `private/setup-logs/` and `~/dotfiles` are all left in place. The new method uses each. The script only copies a `sudo_local` that differs from the declared content into the backup, because the first `mise bootstrap` rewrites it. | A6 plan, "Part B hook". |
| P16 | Homebrew is removed only when nothing it installed is left outside mise's package state (spec decision 5). Task 5 checks it itself, from a fresh `status --json` and Homebrew's own receipts, and refuses with one line per package. It blocks on: a cask with `managed_by: "homebrew"` (declared or not); a `Caskroom` folder whose token no status cask names; a `Cellar` formula whose receipt says `installed_on_request: true` and whose name no status formula names. Matching is by the last `/` part, as in `undeclared_casks`. Not counted: `mise` (precondition 3 covers it), the seven `MOVED_TO_TOOLS` (transferred to `[tools]` by A4), and dependencies (mise installs a declared formula's dependencies itself, and an orphan is what prune is for). The owner drops a package on purpose with one line, `brew:<name>` or `brew-cask:<token>`, in `~/.dotfiles-migration-backup/dropped.txt`, which the script reads and never writes. A drop does not excuse a cask still declared and `managed_by: "homebrew"`. The prune dry-run is not used for this check. | Measured on this Mac on 2026-11-09, before A4: with no package declared, `status --json` printed `{}` and `prune --manager brew --dry-run` listed only `openssl@3`, while 153 kegs have a receipt with `installed_on_request: true` (equal to `brew list --formula --installed-on-request`) and `Caskroom` holds 36 folders. mise keeps formulae its 108 tracked configs declare, so the prune list misses most of them. A4 plan, "Measured on this Mac": `managed_by` is on casks only. |
| P17 | Task 4 offers every cask with `managed_by: "homebrew"`, the self-updating ones as well as the rest. A self-updating app gains no upgrades from the move, but under spec decision 5 Homebrew stays until it is moved, so leaving them out would make P16's check unclearable. The owner may decline any. A declined one stays Homebrew's, and Task 5 names it and refuses. | `brew info --json=v2 --installed --cask` on 2026-11-09: 36 casks, 3 undeclared (`gcloud-cli`, `signal`, `t3-code`, all self-updating). Of the 33 declared, 17 have `auto_updates: true` and one app each: `1password`, `cmux`, `comet`, `coteditor`, `ghostty`, `hopper-disassembler`, `iterm2`, `nimble-commander`, `obsidian`, `orbstack`, `raycast`, `royal-tsx`, `syntax-highlight`, `terax`, `visual-studio-code`, `vorssaint`, `warp`. mise source at tag `v2026.11.5`, `crates/mise-system-packages/src/brew/cask/mod.rs`: `validate_adoptable_apps` runs only `if adopt && !cask.auto_updates`, and `install_app_for` gets `verify_adopt: !cask.auto_updates`, whose doc comment reads "Skipped for self-updating apps, whose on-disk bundle legitimately differs from the declared artifact". So adoption of a self-updating app compares nothing. Not run (Task 4 Step 5a). |
| P12 | `migrate/legacy-to-mise` follows the `bin/` conventions (header, helpers, shebang). It is not on `PATH` and `help` does not render it. Its test lives in `bin/lib/test-migrate`, where `bin/lib/check` already globs `bin/lib/test-*`. | `bin/CLAUDE.md`, `bin/lib/check`. |

## File Structure

| File | Responsibility | Created in |
| --- | --- | --- |
| `migrate/legacy-to-mise` | The script. One function per step plus shared helpers. | Task 1, grown by Tasks 2-7 |
| `migrate/README.md` | What each step does, the removal date, how to restore. | Task 1, one section per later task |
| `bin/lib/test-migrate` | Self-check. Scratch `HOME`, stubs, one function per case. | Task 1, grown by Tasks 2-7 |
| `bin/lib/check` | Lints `migrate/legacy-to-mise`, runs `test-migrate`. | Task 1 |
| `package.json` | `format` covers `migrate/*`. | Task 1 |
| `bin/lib/test-conventions` | Removal-date check. Old-method-name check (Task 7). The permission-rule check for the script is A7's (Task 8 there). | Tasks 1 and 7 |
| `.claude/settings.json` | Five `ask` rules for the script (P15). | A7 Task 8, removed in this plan's Task 8 |
| `README.md` | Section "Migrating an existing machine". | Task 1 |

## Landing order

| Task | Lands with | Why |
| --- | --- | --- |
| 1 Skeleton | before A1 | Later tasks only add a step function. |
| 2 `env` | A2 | Needs `settings/registry.toml`. |
| 3 `macos` | A3 | |
| 4 `packages`: mise itself, undeclared packages, casks and leftovers | A4 | A4's `sysup` sends the user here to move mise off Homebrew. |
| 5 `packages`: Homebrew removal | after A6, once the VM run of A6's Task 6 is recorded with no blocking row failing (spec decision 12 c) and the `fresh-install` workflow has passed once (spec decision 5). The step itself also refuses until nothing Homebrew installed is left outside mise's package state (P16). | The VM run is the full proof that a Mac needs no Homebrew program, and the gate. The workflow is the hosted-runner layer under it. P16 is spec decision 5: every Homebrew-managed app is reinstalled, adopted, declared or dropped first. |
| 6 `dotfiles` | A5, before A5's first `mise dot apply` on this Mac | |
| 7 `setup` | A6, before A6's first `mise bootstrap` on this Mac. Its old-method-name check (Step 6) lands after A6's last commit. | A6 plan, Task "changes the machine", says so. The check fails until A6 has removed the last old name. |
| 8 Removal | on or after 2027-02-28 | |

The script's five `ask` rules come with A7's Task 8, the last task of Part A (P15). Tasks 1 to 4, 6 and 7 land before it, so until then the owner's go-ahead in chat guards a real run. Task 5 may land after it and adds no rule. Task 8 removes the rules A7 added.

---

### Task 1: Script skeleton, self-check, removal date, docs

**Files:**

- Create: `migrate/legacy-to-mise` (mode 755)
- Create: `migrate/README.md`
- Create: `bin/lib/test-migrate` (mode 755)
- Modify: `bin/lib/check` (the `shell_scripts` array, the Prettier globs, one test line)
- Modify: `package.json` (`scripts.format`)
- Modify: `bin/lib/test-conventions` (the removal-date check and one header sentence)
- Modify: `README.md` (new section after "Updating")

**Interfaces:**

- Produces, in `migrate/legacy-to-mise`:
  - Globals: `REPO` (clone root, `cd "$(dirname "$0")/.." && pwd -P`), `DRY_RUN` (`true` or `false`), `PREFIX` (`${HOMEBREW_PREFIX:-/opt/homebrew}`), `BACKUP_DIR` (`$HOME/.dotfiles-migration-backup/$(date +%Y%m%d-%H%M%S)`, not created until first use), `MIN_MISE=2026.11.5`, `CHANGED` (count of changes made), `MISE` (the absolute path `command -v mise` prints, read once at start).
  - `mise() { "$MISE" "$@"; }`. Every `mise` call in the script, `run mise …` included, goes through it, so one action never mixes two binaries. Only Task 4's `move_mise` assigns `MISE` again.
  - `export HOMEBREW_NO_ANALYTICS=1`, straight after `set -euo pipefail`, with the comment `# A4 removed the HOMEBREW_* exports from the shell, and brew reports analytics as enabled without one`.
  - `header <text>`, `info <text>`, `warn <text>`, `success <text>`, `fail <text>` (prints and exits 1). Inline, `tput` guarded as in `setup/brew.sh`: `tput() { command tput "$@" 2> /dev/null || true; }`.
  - `ask <question>`: returns 0 only for `y` or `Y`. Under `DRY_RUN=true` it prints `would ask: <question>` and returns 1. EOF returns 1.
  - `ask_typed <phrase> <question>`: returns 0 only when the reply equals `<phrase>` exactly. Same dry-run and EOF rules.
  - `run <cmd> [args…]`: under `DRY_RUN=true` prints `would run: <cmd> <args>` and returns 0. Otherwise prints `→ <cmd> <args>`, runs it, adds 1 to `CHANGED`.
  - `backup_move <path>`: moves `<path>` to `$BACKUP_DIR/files/<path without its leading slash>`, creating `BACKUP_DIR` with mode 700. Appends `mv '<backup>' '<path>'` to `$BACKUP_DIR/RESTORE.txt`. Under `DRY_RUN=true` prints `would back up: <path>` and moves nothing. Never called on a path that resolves inside `REPO` (it calls `fail`).
  - `backup_copy <path>`: same, with `cp -p`, and the restore line is `cp -p '<backup>' '<path>'`. It copies, so the clone rule does not apply: Tasks 2, 4 and 6 copy the clone's gitignored `config.override.toml` and `config.local.toml`.
  - `backup_note <file> <line>`: appends `<line>` to `$BACKUP_DIR/<file>` (mode 600). No-op under dry-run.
  - `STEPS=(env macos packages dotfiles setup)` and `phase_marker <step>`, a `case` that prints each step's marker path relative to `REPO`: `zsh/override-env.zsh`, `tilde/.config/mise/conf.d/20-macos.toml`, `tilde/.config/mise/conf.d/30-packages.toml`, `tilde/.config/mise/conf.d/40-dotfiles.toml`, `tilde/.config/mise/conf.d/50-bootstrap.toml`.
  - `phase_present <step>`: returns 0 when `$REPO/$(phase_marker <step>)` exists.
  - Each step is a function `step_<name>` returning 0 or 1. Task 1 defines all five as `info "nothing to migrate yet"`.
- Produces, in `bin/lib/test-migrate`:
  - `tmp` (`tmp=$(cd "$(mktemp -d)" && pwd -P)`: physical, because the script resolves `REPO` with `pwd -P` and macOS's temp folder sits behind the `/var` link), `HOME=$tmp/home`, `STATE=$tmp/state`, `REPO_COPY=$tmp/repo` (holds a copy of `migrate/` plus fixture `tilde/.config/mise/conf.d/` and `settings/`), `HOMEBREW_PREFIX=$tmp/prefix`, `PATH=$tmp/bin:/usr/bin:/bin`.
  - `set -eu`, without `pipefail`. The cases feed prompts with `yes | "$script" …`, and `yes` is killed by SIGPIPE (status 141) when the script exits. Under `pipefail` that turns every such case whose script exits 0 into a failure (measured: `bash -c 'set -euo pipefail; out=$(yes | head -1) || echo rc=$?'` prints `rc=141`). Without it the pipeline's status is the script's.
  - `stub <name> <body>` as in `bin/lib/test-sysup`.
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
stub brew 'echo "brew $*" >> "$STATE/brew.log"
[ "${HOMEBREW_NO_ANALYTICS:-}" = 1 ] || { echo "brew ran without HOMEBREW_NO_ANALYTICS=1" >&2; exit 97; }'
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
  # the cases before this one leave their backup folders and their logged calls behind
  rm -rf "$HOME/.dotfiles-migration-backup"; : > "$STATE/mise.log"; : > "$STATE/brew.log"; : > "$STATE/claude.log"
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

`never_old` runs last in this task because it creates every marker file. It clears the backup folder and the three logs first: from Task 2 on, the cases before it write overrides, move packages and leave backups, and its own assertions are about this one run.

- [ ] **Step 2: Run the test to see it fail**

Run: `bash bin/lib/test-migrate`
Expected: FAIL, `migrate/legacy-to-mise: No such file or directory`.

- [ ] **Step 3: Write `migrate/legacy-to-mise` to the Interfaces block**

The version test is `[ "$(printf '%s\n' "$MIN_MISE" "$have" | sort -V | head -1)" = "$MIN_MISE" ]`, where `have` is the first field of `mise --version`. `sort -V` exists in macOS `sort` (checked: orders `2026.6.6 2026.11.5 2026.11.10`). `mise` missing from `PATH` is the same refusal (exit 3). The test never exports `HOMEBREW_NO_ANALYTICS`, so the fake `brew` fails any call the script makes without its own export. `--help` prints the header with the `awk` line from `setup.sh:54`, copied into the script. Then `chmod +x migrate/legacy-to-mise bin/lib/test-migrate`.

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

No permission rule here (P15). A7's Task 8 adds the five `ask` rules for the script and their check (spec decision 7).

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
git add migrate/legacy-to-mise migrate/README.md bin/lib/test-migrate bin/lib/check bin/lib/test-conventions package.json README.md
git ls-files -s migrate/legacy-to-mise bin/lib/test-migrate   # both lines start 100755
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
2. `~/.zsh.local` missing or holding no export of a registered key or of a retired name (point 6): `nothing to migrate`, return 0.
3. For each registered key with an export, read the current override with `mise set --file "$HOME/.config/mise/config.override.toml" KEY` (exit 1 means none):
   - equal: print `KEY: already an override`.
   - form not accepted: print `KEY: cannot read its value safely. Set it yourself: mise set --override KEY=<value>`.
   - none: `ask "Make KEY=<value> from ~/.zsh.local an override?"`.
   - different: print both values, `ask "Replace the override for KEY?"`.
4. Before the first write of the run, `backup_copy` the override file when it exists.
5. Write with `(cd "$HOME" && run mise set --override "KEY=VALUE")`. One argument, quoted.
6. Print `KEY: retired, no longer read. Delete its line from ~/.zsh.local yourself.` for each export of `DOTFILES_MACOS_YES`, `DOTFILES_MACOS_NO` or a name starting `HOMEBREW_`, when the phase that retired it is present (`phase_present macos` for the first two, `phase_present packages` for `HOMEBREW_*`). With `phase_present macos`, an export of `COMPUTERNAME` or `LOCALHOSTNAME`, the old script's prompt variables, gets `KEY: retired, no longer read. Set it with: dotfiles-settings set macos.computer_name <name>` (`macos.local_hostname <host>` for the second), as the A3 plan asks in "What Part B's `macos` step needs". These two are not registered keys, so nothing is copied.
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
env_names_retired_knobs() {
  phase macos
  printf '%s\n' 'export DOTFILES_MACOS_NO=1' "export COMPUTERNAME='Old Mac'" > "$HOME/.zsh.local"
  out=$("$script" --step env < /dev/null 2>&1) || fail "env retired names: exit $?"
  check_out "names a dead knob" '^DOTFILES_MACOS_NO: retired, no longer read'
  check_out "points the old prompt variable at its setting" '^COMPUTERNAME: retired, no longer read\. Set it with: dotfiles-settings set macos\.computer_name'
  [ ! -e "$STATE/override" ] || fail "wrote an override for a retired name"
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
git add migrate/legacy-to-mise migrate/README.md bin/lib/test-migrate
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

- Consumes: `mise bootstrap macos defaults status --json`. Shape, from the A3 plan's measurement on mise 2026.11.5: `{"macos_defaults":{"available":true,"entries":[{"domain":"…","host":"…","path":null|["…"],"key":"…","value":<json>,"current":"…","state":"set"|"differs"|"unset"}]}}`. `path` names a value inside a dictionary preference. A3 declares `com.apple.finder DesktopViewSettings` twice, once with `path` `["IconViewSettings","arrangeBy"]` and once with `["IconViewSettings","iconSize"]`, and the same pair for two more keys, so `domain` and `key` alone do not name an entry.
- Produces: `step_macos`. It changes nothing and always returns 0 when the status command succeeds.

**Output (exact):** one line `macOS defaults: <a> set, <b> differ, <c> unset.`, then one line per `differs` or `unset` entry as `<domain> <key><path>: wants <value>, has <current or "nothing">`, where `<path>` is empty for a null `path` and otherwise a space and the path joined with dots (`com.apple.finder DesktopViewSettings IconViewSettings.arrangeBy: wants grid, has name`). Then one line per leftover that is present and not declared as `<domain> <key>: set by the old script, not declared now. To keep it, declare it in config.local.toml (the comment at the top of conf.d/20-macos.toml shows the table). To drop it: defaults delete <domain> <key>`, then the switch warnings below when they apply, then this text:

```text
Nothing was changed. The old script already wrote these preferences.
To write the declared values, run: set-defaults
mise never deletes a preference. One the old script set that no config declares stays as it is.
Declare it in config.local.toml to keep it on purpose, or run its defaults delete command.
```

**Leftovers** (from the A3 plan, "What Part B's `macos` step needs"): `com.apple.dock autohide-delay`, `com.apple.dock autohide-time-modifier`, `com.apple.LaunchServices LSQuarantine`, `com.apple.frameworks.diskimages skip-verify`, `com.apple.frameworks.diskimages skip-verify-locked`, `com.apple.frameworks.diskimages skip-verify-remote`. The list is a literal array in the script. The old script set these only when the user opted in, and A3 documents them as `config.local.toml` opt-ins. So one is listed only when `defaults read <domain> <key>` exits 0 and no status entry has that `domain` and `key`. An entry the status lists is declared on purpose and is never called a leftover.

**Switches that are on by default** (spec decision 2, and the last item of the A3 plan's "What Part B's `macos` step needs"). The old script turned Time Machine backups off and the firewall on only after a "yes" to a prompt that defaulted to No. A3's `setup/macos-extras.sh` does both unless the setting is switched off, so a Mac migrated with its backups on loses them at its next `set-defaults`. The step reads the Mac's state without sudo, as the extras script does, and changes nothing:

- A switch counts as left at its default when its variable is not set in the script's environment (`[ -z "${VAR+x}" ]`) and `mise set --file "$HOME/.config/mise/config.override.toml" VAR` exits 1 (P5). An empty value is a switch the owner turned off, and gets no warning.
- Time Machine, `DOTFILES_MACOS_DISABLE_TIME_MACHINE`. Backups count as on when `defaults read /Library/Preferences/com.apple.TimeMachine AutoBackup 2> /dev/null` prints something other than `0`, or `tmutil destinationinfo 2> /dev/null` prints anything without the words `No destinations configured` (measured on this Mac on 2026-11-09: `0`, and `tmutil: No destinations configured.` with exit 0). A read that fails prints nothing and is not a warning: on a Mac that never set Time Machine up, `tmutil disable` loses nothing. Then print, exact:

  ```text
  Time Machine backups are on here. set-defaults now turns them off unless told not to (the old script asked first).
  To keep your backups, run this before set-defaults: dotfiles-settings set macos.disable_time_machine off
  ```

- The firewall, `DOTFILES_MACOS_FIREWALL`. With `fw=$(command -v socketfilterfw || echo /usr/libexec/ApplicationFirewall/socketfilterfw)`, when `"$fw" --getglobalstate` does not contain `State = 1`, print `The firewall is off here. set-defaults now turns it on with stealth mode and asks for your password. To leave it off: dotfiles-settings set macos.firewall off`.

Not measured: what `tmutil destinationinfo` prints with a destination configured (this Mac has none). The check that settles it is that command on a Mac with a backup disk. A wrong reading there costs a warning that should not print, or one that is missing while `AutoBackup` still reads `1`.

- [ ] **Step 1: Write the failing test**

The fake `mise` gains: `"bootstrap macos defaults status --json") cat "$STATE/defaults.json" ;;`. A `defaults` stub exits 0 for `read com.apple.dock autohide-delay` and `read com.apple.dock autohide-time-modifier`, prints `1` for `read /Library/Preferences/com.apple.TimeMachine AutoBackup` while `$STATE/tm-on` exists, exits 1 for every other `read`, and logs any other verb to `$STATE/defaults.log`. A `tmutil` stub prints `tmutil: No destinations configured.`, and a `socketfilterfw` stub prints `Firewall is disabled. (State = 0)` while `$STATE/fw-off` exists and `Firewall is enabled. (State = 1)` otherwise. Both stay on `PATH` for every later case, `never_old` included, so no case reads the real Mac. The file `unset`s `DOTFILES_MACOS_DISABLE_TIME_MACHINE` and `DOTFILES_MACOS_FIREWALL` at its top, because A1's override cache may export them into the shell that runs `pnpm check`.

```bash
macos_reports_only() {
  phase macos
  cat > "$STATE/defaults.json" << 'EOF'
{"macos_defaults":{"available":true,"entries":[
 {"domain":"com.apple.dock","host":"any","path":null,"key":"autohide","value":true,"current":"true","state":"set"},
 {"domain":"com.apple.dock","host":"any","path":null,"key":"autohide-time-modifier","value":0.5,"current":"0.5","state":"set"},
 {"domain":"com.apple.dock","host":"any","path":null,"key":"tilesize","value":48,"current":"64","state":"differs"},
 {"domain":"com.apple.finder","host":"any","path":["IconViewSettings","arrangeBy"],"key":"DesktopViewSettings","value":"grid","current":"name","state":"differs"},
 {"domain":"com.apple.finder","host":"any","path":["IconViewSettings","iconSize"],"key":"DesktopViewSettings","value":48.0,"current":"48","state":"set"},
 {"domain":"NSGlobalDomain","host":"any","path":null,"key":"KeyRepeat","value":2,"current":"","state":"unset"}]}}
EOF
  before=$(snapshot)
  for how in "" "--dry-run"; do
    out=$(yes | "$script" --step macos $how 2>&1) || fail "macos $how: exit $?"
    check_out "counts" '^macOS defaults: 3 set, 2 differ, 1 unset\.$'
    check_out "lists the differing one" '^com\.apple\.dock tilesize: wants 48, has 64$'
    check_out "names the dictionary path" '^com\.apple\.finder DesktopViewSettings IconViewSettings\.arrangeBy: wants grid, has name$'
    check_out "lists the unset one" '^NSGlobalDomain KeyRepeat: wants 2, has nothing$'
    check_out "names the leftover that is present" '^com\.apple\.dock autohide-delay: set by the old script.*config\.local\.toml.*defaults delete com\.apple\.dock autohide-delay$'
    ! grep -q 'LSQuarantine' <<< "$out" || fail "listed a leftover that is not set"
    ! grep -q '^com\.apple\.dock autohide-time-modifier: set by the old script' <<< "$out" || fail "called a declared preference a leftover"
    check_out "states the no-delete rule" 'mise never deletes a preference'
  done
  [ "$(snapshot)" = "$before" ] && [ -z "$(mutations)" ] && [ ! -s "$STATE/defaults.log" ] || fail "macos changed something"
  ! grep -qE 'Time Machine backups are on|The firewall is off' <<< "$out" || fail "warned on a Mac that already matches the defaults"
}
macos_warns_before_set_defaults_turns_backups_off() {
  touch "$STATE/tm-on" "$STATE/fw-off"
  out=$("$script" --step macos < /dev/null 2>&1) || fail "macos warnings: exit $?"
  check_out "Time Machine warning" '^Time Machine backups are on here\. set-defaults now turns them off'
  check_out "gives the command that keeps them" 'dotfiles-settings set macos\.disable_time_machine off$'
  check_out "firewall note" '^The firewall is off here\..*dotfiles-settings set macos\.firewall off$'
  # a switch the owner already turned off (an empty override) is not warned about
  mkdir -p "$STATE/override"; : > "$STATE/override/DOTFILES_MACOS_DISABLE_TIME_MACHINE"
  out=$("$script" --step macos < /dev/null 2>&1) || fail "macos warnings, switched off: exit $?"
  ! grep -q 'Time Machine backups are on' <<< "$out" || fail "warned although the switch is off"
  check_out "the firewall switch is still at its default" '^The firewall is off here'
  # so is one exported into the environment
  out=$(DOTFILES_MACOS_FIREWALL= "$script" --step macos < /dev/null 2>&1) || fail "macos warnings, exported: exit $?"
  ! grep -q 'The firewall is off' <<< "$out" || fail "warned although the variable is set"
  [ ! -s "$STATE/defaults.log" ] || fail "the warnings changed a preference"
  rm -rf "$STATE/tm-on" "$STATE/fw-off" "$STATE/override"
}
```

The fake `mise` answers `set --file <file> KEY` with no output and exit 0 for an empty `$STATE/override/KEY` (Task 2's stub: `cat` of an existing file), which is how an override of `""` reads.

- [ ] **Step 2: Run to see it fail.** `bash bin/lib/test-migrate`. Expected: FAIL `counts`.
- [ ] **Step 3: Implement `step_macos`** with one `jq` call for the counts and one for the lines.
- [ ] **Step 4: Run to see it pass.** Expected: `test-migrate: ok`.
- [ ] **Step 5: Run on this Mac** (read-only): `migrate/legacy-to-mise --step macos`. Expected: the counts line, whose three numbers add up to the entry count of `mise bootstrap macos defaults status --json | jq '.macos_defaults.entries | length'`, and `Changed 0 thing(s).`
- [ ] **Step 6: Document, gate, commit**

`migrate/README.md`, `macos` section: report only, the leftovers list with the rule that a declared one is not a leftover, the two switch warnings with when each prints and that the Time Machine one must be acted on before `set-defaults`, the four-line text above.

```bash
pnpm check
git add migrate/legacy-to-mise migrate/README.md bin/lib/test-migrate
git commit -m "Add the macOS defaults report to the migration script"
git push
```

---

### Task 4: Step `packages`: mise itself, undeclared packages, casks and leftovers (lands with A4)

**Files:**

- Modify: `migrate/legacy-to-mise` (`step_packages` and helpers)
- Modify: `bin/lib/test-migrate`
- Modify: `migrate/README.md`

**Interfaces:**

- Consumes: `mise bootstrap packages status --json`. Shape, checked: `{"brew":{"packages":[{"package","state","installed_version"}]},"brew-cask":{"packages":[{"package","state","installed_version","auto_updates"?,"managed_by"?}]}}`. `state` is `installed`, `missing` or `needs_repair`. `managed_by` is `homebrew`, `mise` or `unknown`. `auto_updates` is present only when true.
- Consumes: `mise bootstrap packages prune --manager brew --dry-run`, whose lines are `remove brew:<name>@<version>`. The name is the text between `brew:` and the last `@` (`openssl@3@3.5.9` is `openssl@3`).
- Consumes: `$PREFIX/Cellar/<name>/<version>/INSTALL_RECEIPT.json` and `$PREFIX/Caskroom/<token>/.metadata/INSTALL_RECEIPT.json`, Homebrew's own records, for `.installed_on_request` and `.source.tap`. Read with `/usr/bin/jq`. A missing receipt counts as not on request.
- Consumes: mise's documented installer, `curl -fsSL https://mise.run | sh`. Read on 2026-11-09: it installs to `${MISE_INSTALL_PATH:-$HOME/.local/bin/mise}`, checks the download against checksums embedded in the script, edits no shell file, and prints its "add this to your shell" hint unless `MISE_INSTALL_HELP=0`.
- Consumes: `claude mcp get mise`, whose output holds a line `  Command: <path>` (checked on this Mac: `/opt/homebrew/bin/mise`).
- Consumes, only while `brew` is on `PATH`: `brew info --json=v2 --cask <token>`, for `.casks[0].artifacts[] | .app? // empty | .[] | strings` (the app bundle names, checked: `ghostty` gives `Ghostty.app`, a font cask gives none) and `.pkg?` (checked: present for `dotnet-sdk`).
- Produces:
  - `packages_status`: prints the status JSON once per run (cached in a variable).
  - `online`: runs `curl -fsI --max-time 5 https://formulae.brew.sh/ > /dev/null` once per run and returns the cached result.
  - `move_mise`: the sequence below. Returns 0 when it moved mise, had nothing to move or was declined, 1 when a check failed.
  - `reregister_mise_mcp`: skipped when `claude` is not on `PATH`, when `claude mcp get mise` fails, or when its `Command:` equals `$MISE`. Otherwise `ask "Re-register the mise MCP server with $MISE?"`, `backup_note mcp.txt "<old command>"`, append `claude mcp remove mise -s user && claude mcp add --scope user mise -- '<old command>' mcp` to `RESTORE.txt`, then `run claude mcp remove mise -s user` and `run claude mcp add --scope user mise -- "$MISE" mcp`. Task 7 calls it again.
  - `MOVED_TO_TOOLS=(azd azure-functions-core-tools@4 flux hunk kubelogin lazydocker talosctl)`: the seven formulae A4 moved to `[tools]`, as the prune dry-run names them. A literal, because the Brewfile that listed them is gone.
  - `undeclared_formulae`: prints `name<TAB>version<TAB>kind` for each prune line. `kind` is `mise` for the name `mise`, `tools` for a name in `MOVED_TO_TOOLS`, `request` when the receipt has `installed_on_request == true`, else `dependency`.
  - `undeclared_casks`: prints each directory name under `$PREFIX/Caskroom` that is not the last `/`-separated part of any cask `package` in the status.
  - `local_toml_add <table> <key> <value>`: adds `"<key>" = <value>` under `[<table>]` in `$REPO/tilde/.config/mise/config.local.toml`. A file that already holds `"<key>" =` is left alone. Before the first write of the run it calls `backup_copy` on the file when it exists. With no line equal to `[<table>]` it appends a blank line, the header and the entry. With one, it inserts the entry on the line after the header (one `awk` pass to a temp file, then `mv`), because TOML does not allow the same table twice. Each write adds 1 to `CHANGED`.
  - `homebrew_casks`: prints `token<TAB>version<TAB>self-updates(true|false)` for each cask with `managed_by == "homebrew"`.
  - `cask_apps <token>`: prints the app bundle names, empty without `brew`.
  - `app_running <App.app>`: `pgrep -f "${MIGRATE_APPDIR:-/Applications}/$1/Contents/MacOS/" > /dev/null`.
  - `reinstall_cask <token>`: the sequence below. Returns 1 when the check after it fails.
  - `clean_staging_leftovers`.
  - `step_packages`. Task 5 adds a call at its end.

**What `step_packages` prints and does, in order:**

1. **mise itself.** `move_mise`. When it returns 1 the step stops with exit 1. Nothing below uninstalls anything before this point has run.
2. **Formulae.** `Formulae: nothing to migrate. mise reads /opt/homebrew, so a formula Homebrew installed counts as installed, and "mise bootstrap packages upgrade" replaces it with the current bottle.` Then one line per `brew` package with `state == "needs_repair"`: `<name>: needs repair (mise bootstrap packages apply restores the link, nothing is reinstalled)`.
3. **Packages no config declares.** `Not declared in the config: <n> formulae ("mise bootstrap packages prune --dry-run" lists them; this script never prunes)`, where `<n>` is the number of lines `undeclared_formulae` prints. That function filters the dry-run with `grep '^remove brew:' || true`: `grep` exits 1 on zero matches, which would end the script under `set -euo pipefail`. Then one line per formula, `  <name> <version>: <reason>`, the reason by kind: `Homebrew's mise, moved at the start of this step` (`mise`), `moved to mise tools, this keg is no longer used` (`tools`), `installed by hand` (`request`), `a dependency nothing declared needs` (`dependency`). With `<n>` above 0, this text, exact:

   ```text
   Any "mise bootstrap packages prune" removes every formula listed above.
   mise keeps a formula that any config it has tracked still declares (<t> tracked, in <dir>),
   so this list can be shorter than what is really undeclared.
   ```

   `<dir>` is `${MISE_STATE_DIR:-$HOME/.local/state/mise}/tracked-configs` and `<t>` the number of entries in it (0 when it is absent; 106 on this Mac). Then, for each `request` formula: `ask "Keep <name> by declaring it in config.local.toml?"`. On yes, `local_toml_add bootstrap.packages "brew:<tap>/<name>" '"latest"'` when the receipt's `.source.tap` is set and is not `homebrew/core`, else `"brew:<name>"`. On no, `<name>: left undeclared. A prune removes it.` Then, when `undeclared_casks` prints any: `Casks Homebrew installed that no config declares: <tokens>` and `mise never upgrades or removes these. Once declared, one that does not update itself can be moved to mise by this step. To remove one instead, while brew exists: HOMEBREW_NO_ANALYTICS=1 brew uninstall --cask <token>`, and for each `ask "Declare <token> in config.local.toml?"` with `local_toml_add bootstrap.packages "brew-cask:<token>" '"latest"'` (tap-qualified by the same rule against `homebrew/cask`). After any write: `Declared <n> package(s) in tilde/.config/mise/config.local.toml (gitignored, this Mac only). Run this step again to see them in the lists below.` The status is read once per run, so a package declared here joins the lists on the next run.
4. **Half-way casks.** For each cask with `state == "missing"`: `<token>: declared but not installed. Install it: mise bootstrap packages apply brew-cask:<token>`. No prompt.
5. **Homebrew casks that do not self-update.** The line `Homebrew casks that do not update themselves:`, then a table of token, version and kind (`app`, `pkg`, or `other`).
6. **Self-updating Homebrew casks** (P17). The line `Homebrew casks that update themselves:`, then the same table for each cask with `self-updates` true. Then this text, exact:

```text
Nothing upgrades the first list any more: mise leaves a cask Homebrew installed alone.
The second list updates itself, so moving it gains no upgrades. It is offered because
Homebrew is removed only once no cask is still Homebrew's (the removal at the end of this step).
Reinstalling one through mise runs, for each cask you pick:
  brew uninstall --cask <token>
  mise bootstrap packages apply --yes brew-cask:<token>
and then checks that mise reports it installed and managed by mise.
The app bundle is replaced, not copied to the backup folder. macOS can drop the privacy
permissions (Accessibility, Full Disk Access, Screen Recording and the like) of a replaced app,
so check System Settings > Privacy & Security afterwards.
A cask you decline stays Homebrew's, and Homebrew stays installed while one does.
Way back: HOMEBREW_NO_ANALYTICS=1 brew install --cask <token>.
```

7. Without `brew` on `PATH`: `brew is not installed, so these cannot be moved by this script. To move one by hand, delete the app and /opt/homebrew/Caskroom/<token>, then run the apply command.` Return.
8. `online` fails: `No network: not reinstalling anything.` Skip to 10.
9. For each cask in the first table, then each in the second: when any of its apps is running, print `<token>: <App.app> is running. Quit it and run this step again.` and skip it. Otherwise `ask "Reinstall <token> <version> through mise?"`. On yes, `reinstall_cask`. On no, print `<token>: stays Homebrew's, so Homebrew cannot be removed yet.`
10. `clean_staging_leftovers`.

**`move_mise`:** `new` is `$HOME/.local/bin/mise` and `shims` is `${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims`. Every `find` below runs only when `shims` is a directory, and counts as printing nothing otherwise.

1. `$MISE` is not under `$PREFIX/`: mise is already outside Homebrew. When `find "$shims" -type l ! -exec test -e {} \; -print` lists any link (an earlier run stopped between the uninstall and the reshim), print the count and `ask "Rebuild the mise shims with $MISE?"`, then `run mise reshim`. Otherwise print `mise: $MISE, not Homebrew's. Nothing to move.` Return 0.
2. Print this text, exact, with `<n>` the number of links in `shims`:

   ```text
   mise is Homebrew's (<path>). The new setup installs mise with mise's own installer, and
   Homebrew's copy refuses "mise self-update", so nothing upgrades it any more.
   Moving it runs:
     curl -fsSL https://mise.run | sh     installs ~/.local/bin/mise and checks its checksum
     ~/.local/bin/mise reshim             points the <n> shims at the new binary
     brew uninstall mise
   and checks that every shim still resolves. Way back: HOMEBREW_NO_ANALYTICS=1 brew install mise
   ```

3. Without `brew` on `PATH`: `brew is not installed, so its mise cannot be uninstalled by this script.` Return 0. `online` fails: `No network: not moving mise.` Return 0.
4. `ask "Move mise from Homebrew to ~/.local/bin/mise?"`. On no: `mise stays Homebrew's. sysup reports it until this step moves it.` Return 0.
5. When `$new` is not executable or its version is below `MIN_MISE`: `run env MISE_INSTALL_PATH="$new" MISE_INSTALL_HELP=0 sh -c 'curl -fsSL https://mise.run | sh' || true`. The pipeline's exit status proves nothing either way (a failed `curl` hands `sh` an empty script), so point 6 decides.
6. `"$new" --version` meets `MIN_MISE` (the Task 1 test). Otherwise `The new mise did not install. Homebrew's mise is untouched.` Return 1.
7. `backup_note mise.tsv "<old path><TAB><old version>"` and append `HOMEBREW_NO_ANALYTICS=1 brew install mise && $PREFIX/bin/mise reshim` to `RESTORE.txt`.
8. `old=$MISE`, `MISE=$new`, `hash -r`. From here every call in the script uses the new binary. `run mise reshim`. When `find "$shims" -type l -lname "$old"` still prints a link: set `MISE=$old`, print `The shims still point at Homebrew's mise. Nothing was uninstalled.` Return 1.
9. `run brew uninstall mise`. On failure: `brew could not uninstall mise. Both are installed and the shims use the new one. Run this step again.` Return 1. A rerun finds `$new` in place, skips the installer and finishes.
10. `run mise reshim` again, then check: the `find` from point 1 prints nothing, and when `$shims/node` exists `"$shims/node" --version` exits 0. Otherwise print `A mise shim does not resolve. Put Homebrew's mise back with: HOMEBREW_NO_ANALYTICS=1 brew install mise && $PREFIX/bin/mise reshim` and return 1.
11. `reregister_mise_mcp`.
12. Print `mise now runs from ~/.local/bin/mise. Open a new terminal: this one still remembers the old path.` When `command -v mise` is not `$new`, also `warn "~/.local/bin is not on PATH in this shell. The new shell startup files put it there."`

The reshim comes before the uninstall on purpose. Agent and GUI shells reach node, python and jq only through the shims, and a shim is a link to the mise binary, so uninstalling first would leave every one of them dangling until the reshim. Reshimming first means there is no such moment (P13). The second reshim costs nothing and covers a shim something recreated in between.

**`reinstall_cask <token>`:**

1. `backup_note casks.tsv "<token><TAB><version>"` and append `HOMEBREW_NO_ANALYTICS=1 brew install --cask <token>` to `RESTORE.txt`.
2. `run brew uninstall --cask "<token>"`. On failure, stop the step with exit 1. Nothing was replaced.
3. `run mise bootstrap packages apply --yes "brew-cask:<token>"`.
4. Read the status again. Pass when the cask has `state == "installed"` and `managed_by == "mise"`, and each app `cask_apps` named before the uninstall exists under `${MIGRATE_APPDIR:-/Applications}`. On failure print `<token> is not installed. Put it back with: HOMEBREW_NO_ANALYTICS=1 brew install --cask <token>` and stop the step with exit 1. The remaining casks are not touched.

**`clean_staging_leftovers`:** for each directory `d` directly under `$PREFIX/Cellar` where `ls -A "$d"` prints exactly `.mise-staging.lock`: list it, `ask "Remove <n> empty Cellar folder(s) that hold only mise's staging lock?"`, then `backup_move "$d"` for each. The spec's "Verified facts" records how one arises (`brew uninstall` of a formula mise installed).

- [ ] **Step 1: Write the failing tests**

The fake `mise` and `brew` gain:

```bash
# mise
"bootstrap packages status --json") cat "$STATE/status.json" ;;
"bootstrap packages prune --manager brew --dry-run") [ -e "$STATE/prune-empty" ] || printf 'remove brew:abseil@1\nremove brew:ack@3\n' ;;
reshim)  # as the real one: every shim becomes a link to the binary that ran
  for s in "${MISE_DATA_DIR:-$HOME/.local/share/mise}"/shims/*; do if [ -L "$s" ]; then ln -sfn "$0" "$s"; fi; done ;;
"bootstrap packages apply --yes brew-cask:"*)
  [ ! -e "$STATE/apply-fails" ] || exit 1
  t=${*##*brew-cask:}
  jq --arg t "$t" '(."brew-cask".packages[] | select(.package == $t)) |= (.state = "installed" | .managed_by = "mise")' "$STATE/status.json" > "$STATE/s" && mv "$STATE/s" "$STATE/status.json"
  for a in $(cat "$STATE/apps/$t" 2> /dev/null); do mkdir -p "$MIGRATE_APPDIR/$a"; done ;;
# brew
"info --json=v2 --cask "*) cat "$STATE/cask-info/${*##* }.json" ;;
"uninstall mise")  # fails while a shim still links to this mise, so the test pins reshim-before-uninstall
  if find "$HOME/.local/share/mise/shims" -type l -lname "$HOMEBREW_PREFIX/bin/mise" | grep -q .; then echo "shims still use this mise" >&2; exit 1; fi
  rm "$HOMEBREW_PREFIX/bin/mise" ;;
"uninstall --cask "*)
  t=${*##* }
  jq --arg t "$t" '(."brew-cask".packages[] | select(.package == $t)) |= (.state = "missing" | del(.managed_by))' "$STATE/status.json" > "$STATE/s" && mv "$STATE/s" "$STATE/status.json" ;;
```

The script reads the applications folder from `${MIGRATE_APPDIR:-/Applications}`, and the test exports `MIGRATE_APPDIR="$tmp/apps"`. `curl` and `pgrep` are stubs too: `curl` exits 1 when `$STATE/offline` exists, `pgrep` exits 0 when its last argument contains a name listed in `$STATE/running`. For a URL holding `mise.run` the `curl` stub prints a one-line installer, `mkdir -p "$(dirname "$MISE_INSTALL_PATH")" && cp <the fake mise> "$MISE_INSTALL_PATH"`, or `exit 1` when `$STATE/installer-fails` exists.

The fake `claude` answers `mcp get mise` from `$STATE/mcp-command` (`mise:` then `  Command: <content>`), exits 1 when the file is absent, and on `mcp add --scope user mise -- <path> mcp` writes `<path>` to that file.

The mise cases run first, with `PATH="$HOMEBREW_PREFIX/bin:$HOME/.local/bin:$PATH"` (`brewpath` below) and a copy of the fake `mise` at `$HOMEBREW_PREFIX/bin/mise`. That is this Mac's layout: Homebrew's mise first on `PATH`, the new one behind it. Every other case keeps the plain `PATH`, where mise is `$tmp/bin/mise`, outside the prefix, so `move_mise` has nothing to do and asks nothing.

Fixture `status.json`: formulae `jq` (`installed`) and `rustup` (`needs_repair`). Casks `ghostty` (`homebrew`, `auto_updates: true`, app `Ghostty.app`), `font-hack-nerd-font` (`homebrew`), `utm` (`homebrew`, app `UTM.app`), `freelens` (`homebrew`, app `Freelens.app`), `raycast` (`mise`).

```bash
shims="$HOME/.local/share/mise/shims"
brewpath="$HOMEBREW_PREFIX/bin:$HOME/.local/bin:$PATH"
homebrew_mise() {  # this Mac before the move
  phase packages
  mkdir -p "$HOMEBREW_PREFIX/bin" "$shims"; cp "$tmp/bin/mise" "$HOMEBREW_PREFIX/bin/mise"
  ln -sfn "$HOMEBREW_PREFIX/bin/mise" "$shims/node"
  echo "$HOMEBREW_PREFIX/bin/mise" > "$STATE/mcp-command"
}
mise_move_declined_or_dry_run_changes_nothing() {
  homebrew_mise
  for how in "--dry-run" ""; do
    before=$(snapshot); : > "$STATE/mise.log"; : > "$STATE/brew.log"
    out=$(PATH="$brewpath" "$script" --step packages $how < /dev/null 2>&1) || fail "mise move $how: exit $?: $out"
    [ "$(snapshot)" = "$before" ] && [ -z "$(mutations)" ] || fail "mise move $how with closed stdin changed something"
    check_out "explains the move" "^mise is Homebrew's"
  done
  check_out "closed stdin leaves it" "^mise stays Homebrew's"
}
mise_move_stops_when_the_installer_fails() {
  touch "$STATE/installer-fails"; : > "$STATE/brew.log"
  out=$({ echo y; yes n; } | PATH="$brewpath" "$script" --step packages 2>&1) && fail "a failed installer must exit 1" || [ $? = 1 ] || fail "failed installer: want exit 1"
  check_out "says what is untouched" "Homebrew's mise is untouched"
  [ -x "$HOMEBREW_PREFIX/bin/mise" ] && ! grep -q 'uninstall mise' "$STATE/brew.log" || fail "uninstalled mise without a working replacement"
  [ "$(readlink "$shims/node")" = "$HOMEBREW_PREFIX/bin/mise" ] || fail "repointed the shims without a working replacement"
  rm "$STATE/installer-fails"; rm -rf "$HOME/.dotfiles-migration-backup"
}
mise_moves_off_homebrew() {
  # answers: move mise y, re-register the MCP server y, everything after n
  out=$({ printf 'y\ny\n'; yes n; } | PATH="$brewpath" "$script" --step packages 2>&1) || fail "mise move: exit $?: $out"
  [ -x "$HOME/.local/bin/mise" ] || fail "the installer did not put mise at ~/.local/bin/mise"
  [ ! -e "$HOMEBREW_PREFIX/bin/mise" ] || fail "Homebrew's mise is still installed"
  [ "$(readlink "$shims/node")" = "$HOME/.local/bin/mise" ] || fail "shim not repointed: $(readlink "$shims/node")"
  [ "$(cat "$STATE/mcp-command")" = "$HOME/.local/bin/mise" ] || fail "mise MCP server still names Homebrew's path"
  grep -qF 'HOMEBREW_NO_ANALYTICS=1 brew install mise' "$HOME"/.dotfiles-migration-backup/*/RESTORE.txt || fail "no way back recorded"
  check_out "tells the user to open a new terminal" 'Open a new terminal'
}
mise_move_second_run_changes_nothing() {
  before=$(snapshot); : > "$STATE/mise.log"; : > "$STATE/brew.log"; : > "$STATE/claude.log"
  out=$(yes n | PATH="$brewpath" "$script" --step packages 2>&1) || fail "mise move rerun: exit $?"
  [ "$(snapshot)" = "$before" ] && [ -z "$(mutations)" ] || fail "mise move rerun changed something"
  check_out "reports and skips" "not Homebrew's\. Nothing to move\.$"
}
half_way_mise_shims() {
  # an earlier run uninstalled Homebrew's mise and stopped before the second reshim
  ln -sfn "$HOMEBREW_PREFIX/bin/mise" "$shims/node"
  out=$({ echo y; yes n; } | PATH="$brewpath" "$script" --step packages 2>&1) || fail "dangling shims: exit $?"
  [ "$(readlink "$shims/node")" = "$HOME/.local/bin/mise" ] || fail "dangling shim not rebuilt"
  rm -rf "$HOME/.local" "$HOME/.dotfiles-migration-backup" "$STATE/mcp-command"
}
undeclared_packages_are_offered() {
  local_toml="$REPO_COPY/tilde/.config/mise/config.local.toml"
  mkdir -p "$HOMEBREW_PREFIX/Cellar/ack/3" "$HOMEBREW_PREFIX/Cellar/abseil/1" "$HOMEBREW_PREFIX/Caskroom/signal/8/.metadata"
  echo '{"installed_on_request":true,"source":{"tap":"me/tap"}}' > "$HOMEBREW_PREFIX/Cellar/ack/3/INSTALL_RECEIPT.json"
  echo '{"installed_on_request":false,"source":{"tap":"homebrew/core"}}' > "$HOMEBREW_PREFIX/Cellar/abseil/1/INSTALL_RECEIPT.json"
  printf '[bootstrap.packages]\n"brew:other" = "latest"\n' > "$local_toml"
  before=$(cksum < "$local_toml")
  out=$("$script" --step packages < /dev/null 2>&1) || fail "undeclared, closed stdin: exit $?"
  check_out "says what a no means" '^ack: left undeclared\. A prune removes it\.$'
  [ "$(cksum < "$local_toml")" = "$before" ] || fail "closed stdin declared a package"
  # answers: keep ack y, declare signal y, everything after n
  out=$({ printf 'y\ny\n'; yes n; } | "$script" --step packages 2>&1) || fail "undeclared: exit $?: $out"
  check_out "names the dependency without asking" '^  abseil 1: a dependency nothing declared needs$'
  ! grep -q 'Keep abseil' <<< "$out" || fail "asked about a dependency"
  check_out "prune caveat" 'mise keeps a formula that any config it has tracked still declares \(0 tracked'
  grep -qxF '"brew:me/tap/ack" = "latest"' "$local_toml" || fail "tap formula not declared with its tap"
  grep -qxF '"brew-cask:signal" = "latest"' "$local_toml" || fail "cask not declared"
  grep -qxF '"brew:other" = "latest"' "$local_toml" || fail "lost an entry that was already there"
  [ "$(grep -c '^\[bootstrap\.packages\]' "$local_toml")" = 1 ] || fail "wrote a second [bootstrap.packages] table"
  ls "$HOME"/.dotfiles-migration-backup/*/files"$local_toml" > /dev/null 2>&1 || fail "config.local.toml not backed up before the write"
  before=$(cksum < "$local_toml"); out=$({ printf 'y\ny\n'; yes n; } | "$script" --step packages 2>&1) || fail "undeclared rerun: exit $?"
  [ "$(cksum < "$local_toml")" = "$before" ] || fail "declared a package twice"
  rm -rf "$local_toml" "$HOMEBREW_PREFIX/Cellar" "$HOMEBREW_PREFIX/Caskroom" "$HOME/.dotfiles-migration-backup"
}
no_prune_candidates() {
  touch "$STATE/prune-empty"
  out=$("$script" --step packages < /dev/null 2>&1) || fail "no prune candidates: exit $?: $out"
  check_out "zero is a count, not a failure" 'Not declared in the config: 0 formulae'
  rm "$STATE/prune-empty"
}
packages_lists_and_reinstalls_only_the_picked() {
  phase packages
  # answers in table order: font-hack-nerd-font n, utm y, freelens n, then the self-updating table: ghostty n
  out=$(printf 'n\ny\nn\nn\n' | "$script" --step packages 2>&1) || fail "packages: exit $?: $out"
  check_out "formulae need nothing" '^Formulae: nothing to migrate'
  check_out "repair is reported" '^rustup: needs repair'
  check_out "prune count" 'Not declared in the config: 2 formulae'
  check_out "self-updating casks are offered too" '^Homebrew casks that update themselves:'
  ! grep -q '^Left alone' <<< "$out" || fail "left the self-updating casks out (spec decision 5)"
  check_out "a declined cask blocks the removal" "^ghostty: stays Homebrew's, so Homebrew cannot be removed yet\.$"
  check_out "privacy warning" 'macOS can drop the privacy'
  ! grep -q 'raycast' <<< "$out" || fail "listed a cask mise already manages"
  [ "$(grep -c '^brew uninstall' "$STATE/brew.log")" = 1 ] && grep -qx 'brew uninstall --cask utm' "$STATE/brew.log" || fail "uninstalled something other than the one pick"
  grep -qx 'mise bootstrap packages apply --yes brew-cask:utm' "$STATE/mise.log" || fail "did not apply the pick through mise"
  grep -q '^utm' "$HOME"/.dotfiles-migration-backup/*/casks.tsv || fail "pick not recorded before the uninstall"
  grep -qx 'HOMEBREW_NO_ANALYTICS=1 brew install --cask utm' "$HOME"/.dotfiles-migration-backup/*/RESTORE.txt || fail "no way back recorded"
}
packages_second_run_changes_nothing() {
  before=$(snapshot); : > "$STATE/mise.log"; : > "$STATE/brew.log"
  out=$(printf 'n\nn\nn\n' | "$script" --step packages 2>&1) || fail "packages rerun: exit $?"
  [ "$(snapshot)" = "$before" ] && [ -z "$(mutations)" ] || fail "packages rerun changed something"
  ! grep -q 'Reinstall utm' <<< "$out" || fail "offered utm again after mise took it over"
}
cask_running() {
  printf 'Freelens.app\nGhostty.app\n' > "$STATE/running"; : > "$STATE/brew.log"
  out=$(yes | "$script" --step packages 2>&1) || true   # yes moves font-hack-nerd-font, the one cask not running
  check_out "names the running app" '^freelens: Freelens\.app is running\. Quit it'
  check_out "names a running self-updating app" '^ghostty: Ghostty\.app is running\. Quit it'
  ! grep -qE 'uninstall --cask (freelens|ghostty)' "$STATE/brew.log" || fail "uninstalled a running app"
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
  # freelens is the first cask still Homebrew's (utm and font-hack-nerd-font are mise's by now), and the failed apply stops the step
  out=$(printf 'y\n' | "$script" --step packages 2>&1) && fail "a failed apply must exit 1" || [ $? = 1 ] || fail "failed apply: want exit 1"
  check_out "way back" 'Put it back with: HOMEBREW_NO_ANALYTICS=1 brew install --cask freelens'
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
  # offline, so no cask is asked about and the only prompt is the leftovers one
  touch "$STATE/offline"
  out=$(yes | "$script" --step packages 2>&1) || fail "leftovers: exit $?"
  rm "$STATE/offline"
  [ ! -e "$HOMEBREW_PREFIX/Cellar/hello" ] || fail "leftover not removed"
  [ -d "$HOMEBREW_PREFIX/Cellar/jq/1.8.2" ] || fail "removed a Cellar folder that holds a keg"
  ls -d "$HOME"/.dotfiles-migration-backup/*/files"$HOMEBREW_PREFIX"/Cellar/hello > /dev/null || fail "leftover not backed up"
}
```

Count the prompts in each case against the fixture when writing them: the cask prompts come in status order, the casks that do not self-update first and then the self-updating ones (only `ghostty` in the fixture), and a cask mise took over in an earlier case is no longer asked. `cask_running` keeps `ghostty` running, so it leaves Task 4 still Homebrew's, which Task 5's refusal case needs. `staging_leftovers` runs offline so that no cask prompt comes before the leftovers one. The undeclared-package prompts come before the cask prompts, and outside `undeclared_packages_are_offered` there are none, because the fake prefix holds no receipt and no `Caskroom` folder. `never_old` keeps the plain `PATH`, so it also proves `move_mise` does nothing for a mise outside Homebrew.

- [ ] **Step 2: Run to see them fail.** `bash bin/lib/test-migrate`. Expected: FAIL `explains the move`.
- [ ] **Step 3: Implement** `packages_status`, `online`, `move_mise`, `reregister_mise_mcp`, `undeclared_formulae`, `undeclared_casks`, `local_toml_add`, `homebrew_casks`, `cask_apps`, `app_running`, `reinstall_cask`, `clean_staging_leftovers`, `step_packages`.
- [ ] **Step 4: Run to see them pass.** Expected: `test-migrate: ok`.
- [ ] **Step 5: Dry-run on this Mac**

Run: `migrate/legacy-to-mise --step packages --dry-run`
Expected, in order:

- The `mise is Homebrew's (/opt/homebrew/bin/mise)` text with 149 shims, and `would ask: Move mise from Homebrew to ~/.local/bin/mise?`.
- The undeclared formulae. A4 measured 11 with a clean state folder: `mise`, the seven in `MOVED_TO_TOOLS`, `openssl@3` as a dependency, and `aikb` and `ai-kb-lite` as installed by hand. This Mac has 106 tracked configs, so fewer may show. That is the caveat the step prints. `would ask: Keep aikb …` and `would ask: Keep ai-kb-lite …` when they are listed.
- `Casks Homebrew installed that no config declares: gcloud-cli signal t3-code` and three `would ask: Declare …` lines.
- The first table holds 16: the 7 `font-*-nerd-font` casks, `jrmatherly/tap/claude-multipass-app`, `codex`, `azure-cli`, `dotnet-sdk`, `freelens`, `coderabbit`, `1password-cli`, `git-credential-manager`, `utm`. The second holds the 17 P17 lists. 33 `would ask: Reinstall …` lines, fewer for any app that is running (this session's terminal app among them), which get the `is running` line instead. No `Left alone` line.
- `Changed 0 thing(s).`

- [ ] **Step 5a: Try adoption on one app cask (changes this Mac: the user runs it, after an explicit go-ahead)**

  Reinstalling replaces the app bundle, which can drop its macOS privacy permissions. `adopt = true` (set in A4's `[bootstrap.brew]`) offers a gentler path: hide Homebrew's record and let mise take over the bundle in place. This is not tested. What mise's source says, read at tag `v2026.11.5` in `crates/mise-system-packages/src/brew/cask/mod.rs`:

  - Adoption applies only when mise does not see the cask as installed (`adopt = adopt_requested && installed_version.is_none()`).
  - It exists only for app bundles. The check and the takeover both run over `artifacts.apps`.
  - For a cask that does not update itself, the bundle on disk must be identical to the download. Otherwise mise stops with `cannot adopt '<path>': existing artifact is not identical to the declared artifact`. `validate_adoptable_apps` runs after the download and before mise takes its locks or touches the `Caskroom` or the app.
  - For a cask that updates itself, nothing is compared (`verify_adopt: !cask.auto_updates`, P17). mise records the bundle as its own without replacing it, so this is the path that keeps the privacy permissions of the 17 self-updating apps, most of which hold some (1Password, Raycast, the terminals, OrbStack).
  - A font is never adopted. `link_font` renames the existing file aside, copies the new one and deletes the old. So a font cask cannot show whether adoption works, and its inode always changes. A font has no privacy permission to lose, so that is harmless.

  So the trial runs on an app cask from the Step 5 table that does not update itself: `freelens` (`/Applications/Freelens.app`), or `utm` (`/Applications/UTM.app`). The implementer does not run it. Give the user these commands for the chosen cask:

  1. Quit the app. Bring the installed bundle up to the current download, or the identity check fails for the wrong reason: `HOMEBREW_NO_ANALYTICS=1 brew upgrade --cask freelens`.
  2. Record the bundle's inode: `stat -f %i /Applications/Freelens.app`.
  3. Move Homebrew's record aside, leaving the app: `backup=~/.dotfiles-migration-backup/adopt-trial && mkdir -p "$backup" && mv /opt/homebrew/Caskroom/freelens "$backup/Caskroom-freelens"`.
  4. From `$HOME`: `mise bootstrap packages apply --dry-run brew-cask:freelens`, read what it plans, then the same without `--dry-run`.
  5. Read the result. It is one of two:
     - **Adopted.** The apply exits 0, the inode from 2 is unchanged, and `mise bootstrap packages status --json | /usr/bin/jq -r '."brew-cask".packages[] | select(.package == "freelens") | .managed_by'` prints `mise`.
     - **Refused.** The apply prints the `cannot adopt … not identical` line, and the inode from 2 is unchanged. Nothing was changed.

     An inode that changed means mise replaced the bundle. Then adoption does not do what this step hoped. Record that as a third result.
  6. Repeat 2 to 5 on one self-updating app cask from the second table, with the app quit and `coteditor`, `CotEditor.app` and `Caskroom-coteditor` in place of the freelens names: `coteditor` holds no privacy permission worth keeping. Skip 1: a self-updating cask is not compared, so its bundle need not match the download. The source predicts **Adopted**. A refusal or a changed inode here contradicts the source reading in P17, and is recorded as such.

  Put the record back after a refusal: `mv "$backup/Caskroom-freelens" /opt/homebrew/Caskroom/freelens`. First check `ls /opt/homebrew/Caskroom/freelens`. When that folder exists, mise made a new record, and a plain `mv` would nest the backup inside it. Move the new record aside first: `mv /opt/homebrew/Caskroom/freelens "$backup/Caskroom-freelens.mise"`.

  Each trial decides its own table. If the cask was adopted, `reinstall_cask` uses this sequence for the casks of kind `app` in that table (move the `Caskroom` record to the backup with `backup_move`, apply, check) in place of `brew uninstall --cask`, the privacy warning is dropped from the prompt for them, and the tests and README are changed to match before Step 6. Font casks may take the same record-aside path, with no privacy risk either way. If mise refused, keep the uninstall-then-apply sequence for that table and record the result in `migrate/README.md`. A refusal on a bundle Homebrew has just upgraded means identical content cannot be relied on.

- [ ] **Step 6: Hand the first real run to the user (changes this Mac: the user runs it, after an explicit go-ahead)**

Neither the mise move nor the reinstall path has run on a real machine. Ask the user to run `migrate/legacy-to-mise --step packages`, answer `y` to moving mise and to re-registering the MCP server, `n` to every package and cask question except `font-tinos-nerd-font`, and then, in a new terminal:

Run: `command -v mise; readlink ~/.local/share/mise/shims/node; node --version; ls /opt/homebrew/opt/mise; claude mcp get mise | grep Command`
Expected: `mise` resolves to `~/.local/bin/mise`. The shim link reads the same path. `node --version` prints a version. `ls` reports no such folder (it held `lib/.disable-self-update`). The MCP command is `~/.local/bin/mise` written in full.

If a shim does not resolve, the way back is in `RESTORE.txt`: `HOMEBREW_NO_ANALYTICS=1 brew install mise && /opt/homebrew/bin/mise reshim`. Stop and fix `move_mise` before anything else.

Run: `mise bootstrap packages status --json | /usr/bin/jq -r '."brew-cask".packages[] | select(.package == "font-tinos-nerd-font") | .managed_by'`
Expected: `mise`

If it prints `homebrew` or the apply fails, stop. P7 is wrong and this task needs a new design before any app cask is touched.

- [ ] **Step 7: Document, gate, commit**

`migrate/README.md`, `packages` section: the ten points above, why the self-updating casks are offered too (P17) and that a declined one keeps Homebrew installed, the `move_mise` sequence with why the reshim comes first, what declaring a package in `config.local.toml` does and that the file is this Mac's own, the tracked-config caveat, P8's exception, and that pkg casks (`dotnet-sdk`, `git-credential-manager`) ask for the password twice, once from each tool.

```bash
pnpm check
git add migrate/legacy-to-mise migrate/README.md bin/lib/test-migrate
git commit -m "Add the packages step to the migration script"
git push
```

---

### Task 5: Step `packages`, removing the Homebrew program (lands after A6's VM run is recorded and the fresh-install workflow has passed)

**Files:**

- Modify: `migrate/legacy-to-mise` (`offer_homebrew_removal`, called last in `step_packages`)
- Modify: `bin/lib/test-migrate`
- Modify: `migrate/README.md`

**Why not Homebrew's own uninstaller.** The documented procedure is `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"` (https://github.com/Homebrew/install#uninstall-homebrew, https://docs.brew.sh/FAQ#how-do-i-uninstall-homebrew). Read on 2026-11-09, it asks "This will remove your installed packages!" and then deletes `$HOMEBREW_PREFIX/Cellar` and `$HOMEBREW_PREFIX/Caskroom` (its lines 377-378 and 454), every broken symlink under the prefix (line 460), and `/etc/paths.d/homebrew`. Under D5 mise installs into that same `Cellar` and `Caskroom`. Running it would delete every package the new method manages. So this step removes only the Homebrew program, by moving it into the backup folder, and leaves the prefix in place.

**Interfaces:**

- Consumes: `packages_status`, `homebrew_casks`, `ask_typed`, `backup_move`, `PREFIX`, `MISE`, `MOVED_TO_TOOLS` (Task 4).
- Produces: `packages_fingerprint`: runs `mise bootstrap packages status --json` afresh (not the cached copy) and prints one sorted line per formula and cask, `<manager> <package> <state> <managed_by or "-">`. Returns the status call's exit code.
- Produces: `DROPPED="$HOME/.dotfiles-migration-backup/dropped.txt"`, the owner's drop file (P16). The script reads it and never writes it. One `brew:<name>` or `brew-cask:<token>` per line, tap-qualified or not. Blank lines and lines starting `#` are ignored. A missing file drops nothing.
- Produces: `homebrew_leftovers`: runs `mise bootstrap packages status --json` afresh and prints one line per package that blocks removal (P16), sorted, in these exact forms:
  - `  brew-cask:<token>: still Homebrew's. Move it: HOMEBREW_NO_ANALYTICS=1 brew uninstall --cask <token> && mise bootstrap packages apply --yes brew-cask:<token>`, for each status cask with `managed_by == "homebrew"`. `<token>` is the status `package` as written.
  - `  brew-cask:<token>: installed by Homebrew, declared nowhere`, for each folder under `$PREFIX/Caskroom` that no status cask names (last `/` part) and the drop file does not list.
  - `  brew:<name>: installed by hand, declared nowhere`, for each folder under `$PREFIX/Cellar` where any `<version>/INSTALL_RECEIPT.json` has `.installed_on_request == true`, whose name is not `mise`, not in `MOVED_TO_TOOLS`, named by no status formula (last `/` part) and not in the drop file.
  
  Returns 0 when it printed nothing, 1 when it printed a line, 2 when the status call failed or `.brew.available` or `."brew-cask".available` is `false` (mise cannot then say who manages a package). Both lists come from Homebrew's own records, not from the prune dry-run (P16 says why). A `Cellar` folder holding only `.mise-staging.lock` has no receipt, so it is never listed.
- Produces: `offer_homebrew_removal`. Returns 0 when it did nothing or succeeded, 1 when it had to restore.

**What it moves** (to `$BACKUP_DIR/files$PREFIX/…`, each with its `mv` line in `RESTORE.txt`):

- every top-level name `git -C "$PREFIX" ls-tree --name-only HEAD` prints, except `bin`. Checked on this Mac: `Library` (which holds `Homebrew` and `Taps`), `completions`, `docs`, `manpages`, `package`, the repository's dot-files and its top-level Markdown and licence files.
- `$PREFIX/bin/brew` (the only tracked file under `bin`).
- `$PREFIX/.git`.
- the links `uninstall.sh` calls `homebrew_prefix_markers`, when present: `etc/bash_completion.d/brew`, `share/doc/homebrew`, `share/man/man1/brew.1`, `share/zsh/site-functions/_brew`, `share/fish/vendor_completions.d/brew.fish`.
- `~/Library/Caches/Homebrew` and `~/Library/Logs/Homebrew`.

**What it leaves, and says it leaves:** `Cellar`, `Caskroom`, `opt`, `bin`, `sbin`, `etc`, `include`, `lib`, `share`, `Frameworks` and `var/homebrew` (the linked-keg records mise reads), because mise's packages live there. `/etc/paths.d/homebrew`, because `/opt/homebrew/bin` must stay on `PATH`. Taps go with `Library`. mise keeps its own tap list in `[bootstrap.brew.taps]`.

**Preconditions, checked in this order. A failed one prints its reason and returns 0 without asking:**

1. Under `DRY_RUN=true` the function prints the result of preconditions 2-7 (for 5, every line `homebrew_leftovers` prints) and the list it would move, then returns.
2. `$PREFIX/bin/brew` exists and `$PREFIX/.git` is a directory. Otherwise `Homebrew is not installed here in the layout this script knows.`
3. `$MISE` is not under `$PREFIX/`. Otherwise `mise is still Homebrew's. Move it first: answer yes at the start of this step.` Without the Homebrew program nothing can uninstall that keg cleanly, and `$PREFIX/bin/mise` is the binary every shim links to.
4. `packages_fingerprint` exits 0, and its output is kept as `before`. Otherwise `mise cannot read the package status. Fix that first: mise bootstrap packages status`. The call needs a Ruby 3 on `PATH` to read tap definitions. macOS ships 2.6, and A4 declares `brew:ruby` for this, so a failure here usually means that formula is missing. `--missing` is not used: a declared package that is not installed is normal half way through and does not make removing Homebrew unsafe.
5. **Nothing Homebrew installed is left outside mise's package state** (P16, spec decision 5). `homebrew_leftovers` returns 0. On 2 the reason is precondition 4's. On 1 the step prints this text, exact, with its lines in between, and returns 0 without asking:

   ```text
   Homebrew stays installed: it still owns these packages.
   <the lines homebrew_leftovers printed>
   Declare one: run this step again and answer yes to "Keep" or "Declare", or add it to conf.d/30-packages.toml.
   Remove one while brew exists: HOMEBREW_NO_ANALYTICS=1 brew uninstall [--cask] <name>
   Drop one on purpose (it stays installed, and nothing updates or removes it once brew is gone):
     mkdir -p ~/.dotfiles-migration-backup && echo 'brew-cask:<token>' >> ~/.dotfiles-migration-backup/dropped.txt
   ```

   This is the step's own check, not advice. No later precondition, prompt or typed phrase runs while one line is printed.
6. No cask has `managed_by == "unknown"`.
7. `df -P "$PREFIX" "$HOME" | awk 'NR > 1 { print $1 }' | sort -u | wc -l` is 1, so each move is a rename. Otherwise `The backup folder is on another volume.`

**The prompt.** It prints this text, then asks with `ask_typed "remove homebrew"`. By precondition 5 no cask is Homebrew's any more, so the only packages left recorded as Homebrew's are the drop file's:

```text
Homebrew's own uninstaller is not used: it deletes Cellar and Caskroom, where mise's packages live.
This moves only the Homebrew program (brew, Library with its taps, the Git checkout) into the backup folder.
Every formula and cask Homebrew installed is now declared in mise's config or dropped by you.
Dropped in ~/.dotfiles-migration-backup/dropped.txt (they stay installed; without brew, removing one means deleting it by hand):
  <each line of the drop file whose package is still in Cellar or Caskroom, or "none">
"ca-roots trim" (the opt-in DOTFILES_TRIM_CA_ROOTS step in sysup) runs a script inside Library and stops working.
Lines in your own files that call "brew shellenv" or set HOMEBREW_ variables (not edited):
  <file>:<line number> for each match in ~/.zsh.local, ~/.zprofile, ~/.zshrc, ~/.bash_profile, ~/.profile that is a real file, not a link into this clone
Type "remove homebrew" to continue. Anything else leaves Homebrew installed.
```

**After the moves:** run `hash -r`, then `packages_fingerprint` again. Exit 0 and output equal to `before` (so the same packages are installed, each with the same `managed_by`): print `Homebrew program moved to <dir>. Put it back with the mv lines in RESTORE.txt.` A non-zero exit or any differing line: run the recorded `mv` lines for this function in reverse, print `mise reads the packages differently without Homebrew, so it was put back.` and the differing lines, and return 1.

- [ ] **Step 1: Write the failing tests**

The test builds a fake prefix: `git init -q "$HOMEBREW_PREFIX"`, tracked `bin/brew`, `Library/Homebrew/x`, `Library/Taps/a/b/x`, `README.md`, committed with the flags `bin/lib/test-sysup` uses. Untracked `Cellar/jq/1.8.2/bin/jq`, `Caskroom/ghostty/1.4.0/x`, `var/homebrew/linked/jq`, `bin/jq`. `git` and `df` are the real ones (`PATH` keeps `/usr/bin`). The tracked `bin/brew` is a copy of the `brew` stub. The fake `mise` touches `$STATE/status-read` on each `bootstrap packages status --json`, and exits 1 instead when that file already exists and `$STATE/status-fails-later` does too. So a case can fail the fresh read `packages_fingerprint` makes while the step's first, cached read succeeds. When `$STATE/differs-without-brew` exists and `$HOMEBREW_PREFIX/bin/brew` does not, it prints the status with every `managed_by` of `mise` changed to `unknown`.

At this point Task 4's cases have left `ghostty` as `managed_by: "homebrew"` in `status.json` (declined in `packages_lists_and_reinstalls_only_the_picked`, running in `cask_running`), `utm` and `font-hack-nerd-font` as mise's, and `freelens` `missing`. The fake prefix's `Caskroom/ghostty` matches the status. The refusal case runs first and ends by handing every cask to mise, so the cases after it start from a Mac where Homebrew owns nothing. Every case feeds `yes 'remove homebrew'`: each `ask` reads a line that is not `y` and declines, and the typed prompt, when reached, gets its phrase. So no case depends on how many prompts come first.

```bash
homebrew_owns_nothing() {  # every cask reinstalled or adopted through mise
  jq '."brew-cask".packages |= map(.state = "installed" | .managed_by = "mise")' "$STATE/status.json" > "$STATE/s" && mv "$STATE/s" "$STATE/status.json"
}
homebrew_removal_refuses_while_homebrew_owns_packages() {
  mkdir -p "$HOMEBREW_PREFIX/Cellar/ack/3" "$HOMEBREW_PREFIX/Cellar/abseil/1" "$HOMEBREW_PREFIX/Caskroom/signal/8"
  echo '{"installed_on_request":true,"source":{"tap":"homebrew/core"}}' > "$HOMEBREW_PREFIX/Cellar/ack/3/INSTALL_RECEIPT.json"
  echo '{"installed_on_request":false,"source":{"tap":"homebrew/core"}}' > "$HOMEBREW_PREFIX/Cellar/abseil/1/INSTALL_RECEIPT.json"
  out=$(yes 'remove homebrew' | "$script" --step packages 2>&1) || fail "exit $?: $out"
  check_out "names a cask Homebrew still manages" "^  brew-cask:ghostty: still Homebrew's\. Move it: HOMEBREW_NO_ANALYTICS=1 brew uninstall --cask ghostty && mise bootstrap packages apply --yes brew-cask:ghostty$"
  check_out "names an undeclared cask" '^  brew-cask:signal: installed by Homebrew, declared nowhere$'
  check_out "names a formula installed by hand" '^  brew:ack: installed by hand, declared nowhere$'
  ! grep -q 'brew:abseil' <<< "$out" || fail "blocked on a dependency"
  ! grep -q 'brew:jq' <<< "$out" || fail "blocked on a keg with no receipt"
  ! grep -q 'Type "remove homebrew"' <<< "$out" || fail "offered the typed phrase while Homebrew still owns packages"
  [ -x "$HOMEBREW_PREFIX/bin/brew" ] && [ -d "$HOMEBREW_PREFIX/Library" ] && [ -d "$HOMEBREW_PREFIX/.git" ] || fail "removed Homebrew while it still owns packages"
  # a drop excuses an undeclared package, never a cask Homebrew still manages
  mkdir -p "$HOME/.dotfiles-migration-backup"
  printf '# dropped by hand\nbrew:ack\nbrew-cask:signal\nbrew-cask:ghostty\n' > "$HOME/.dotfiles-migration-backup/dropped.txt"
  out=$(yes 'remove homebrew' | "$script" --step packages 2>&1) || fail "exit $?: $out"
  ! grep -qE '^  brew:ack|^  brew-cask:signal' <<< "$out" || fail "listed a dropped package"
  check_out "a drop does not excuse a cask still Homebrew's" "^  brew-cask:ghostty: still Homebrew's"
  [ -x "$HOMEBREW_PREFIX/bin/brew" ] || fail "removed Homebrew while a cask is still Homebrew's"
  homebrew_owns_nothing
  out=$("$script" --step packages --dry-run 2>&1) || fail "dry run: exit $?"
  ! grep -qE '^  brew(-cask)?:' <<< "$out" || fail "still blocks once every cask is mise's and the rest are dropped: $out"
  rm -rf "$HOMEBREW_PREFIX/Cellar/ack" "$HOMEBREW_PREFIX/Cellar/abseil" "$HOMEBREW_PREFIX/Caskroom/signal" "$HOME/.dotfiles-migration-backup"
}
homebrew_removal_is_off_by_default() {
  before=$(snapshot)
  out=$(yes | "$script" --step packages 2>&1) || fail "exit $?"   # "y" is not the typed phrase
  [ -x "$HOMEBREW_PREFIX/bin/brew" ] && [ -d "$HOMEBREW_PREFIX/Library" ] || fail "y removed Homebrew"
  out=$("$script" --step packages < /dev/null 2>&1) || fail "exit $?"
  [ -x "$HOMEBREW_PREFIX/bin/brew" ] || fail "closed stdin removed Homebrew"
  check_out "explains why the uninstaller is not used" "uninstaller is not used: it deletes Cellar and Caskroom"
}
homebrew_removal_refuses_when_status_fails() {
  touch "$STATE/status-fails-later"; rm -f "$STATE/status-read"
  out=$(yes 'remove homebrew' | "$script" --step packages 2>&1) || fail "exit $?"
  check_out "reason" '^mise cannot read the package status'
  [ -x "$HOMEBREW_PREFIX/bin/brew" ] || fail "removed Homebrew although mise could not read the status"
  rm "$STATE/status-fails-later"
}
homebrew_removal_refuses_while_mise_is_homebrews() {
  cp "$tmp/bin/mise" "$HOMEBREW_PREFIX/bin/mise"
  out=$(yes n | PATH="$HOMEBREW_PREFIX/bin:$PATH" "$script" --step packages 2>&1) || fail "exit $?"   # n declines the mise move too
  check_out "reason" "^mise is still Homebrew's\. Move it first"
  [ -x "$HOMEBREW_PREFIX/bin/brew" ] || fail "removed Homebrew from under its own mise"
  rm "$HOMEBREW_PREFIX/bin/mise"
}
homebrew_removal_moves_only_the_program() {
  out=$(yes 'remove homebrew' | "$script" --step packages 2>&1) || fail "exit $?: $out"
  for gone in bin/brew Library .git README.md; do [ ! -e "$HOMEBREW_PREFIX/$gone" ] || fail "$gone still there"; done
  for kept in Cellar/jq/1.8.2/bin/jq Caskroom/ghostty/1.4.0/x var/homebrew/linked/jq bin/jq; do [ -e "$HOMEBREW_PREFIX/$kept" ] || fail "$kept was removed"; done
  bak=$(echo "$HOME"/.dotfiles-migration-backup/*/files"$HOMEBREW_PREFIX")
  [ -x "$bak/bin/brew" ] && [ -e "$bak/Library/Taps/a/b/x" ] && [ -d "$bak/.git" ] || fail "program not in the backup"
  # the restore file puts it back
  sh "${bak%/files*}/RESTORE.txt"
  [ -x "$HOMEBREW_PREFIX/bin/brew" ] && [ -d "$HOMEBREW_PREFIX/.git" ] || fail "RESTORE.txt did not restore Homebrew"
}
homebrew_removal_restores_itself_when_mise_reads_differently() {
  touch "$STATE/differs-without-brew"
  out=$(yes 'remove homebrew' | "$script" --step packages 2>&1) && fail "want exit 1" || [ $? = 1 ] || fail "want exit 1"
  [ -x "$HOMEBREW_PREFIX/bin/brew" ] && [ -d "$HOMEBREW_PREFIX/Library" ] || fail "did not put Homebrew back"
  check_out "says so" 'so it was put back'
  rm "$STATE/differs-without-brew"
}
```

`RESTORE.txt` must be runnable with `sh` for `homebrew_removal_moves_only_the_program`, so every line the script writes into it is a complete command (Task 1's `backup_move`, `backup_copy`, and the `brew install --cask` lines).

- [ ] **Step 2: Run to see them fail.** Expected: FAIL `names a cask Homebrew still manages`. The refusal case runs first, so the decision 5 check is proven failing before any code for it exists.
- [ ] **Step 3: Implement `offer_homebrew_removal`** and call it last in `step_packages`.
- [ ] **Step 4: Run to see them pass.** Expected: `test-migrate: ok`.
- [ ] **Step 5: Dry-run on this Mac**

Run: `migrate/legacy-to-mise --step packages --dry-run | sed -n '/Homebrew program/,$p'`
Expected: preconditions 2-7 with their results, the would-move list (27 top-level names from `git ls-tree`, `bin` excluded, `bin/brew`, `.git`, the completion links, the two cache folders), and `Changed 0 thing(s).` Until the owner has moved every cask, precondition 5 lists packages (gate 3 of Step 6 counts them). Task 4's step offers all 33 declared casks (P17), so each one the owner declined there, or skipped because it was running, shows with its `brew uninstall … && mise bootstrap packages apply …` line until Task 4 is run again or it is moved by hand. Cross-check the formula lines against Homebrew's own list, run from `$HOME`: `comm -23 <(HOMEBREW_NO_ANALYTICS=1 brew list --formula --installed-on-request | sort) <(mise bootstrap packages status --json | /usr/bin/jq -r '(.brew.packages // [])[].package | split("/") | last' | sort)`. Before A4 it printed all 153 names (measured 2026-11-09, `status --json` was `{}`). Every name it prints is a `brew:` line in the refusal, except `mise`, the seven `MOVED_TO_TOOLS` and the drop file's.

- [ ] **Step 6: Leave the real run to the user, and say what is unproven (changes this Mac: the user runs it, after an explicit go-ahead)**

Before offering it, check the four gates, in order, and stop at the first that fails:

1. The VM run is recorded (spec decision 12 c, the gate). Run: `grep -n -A 20 '^#### Results' docs/superpowers/plans/completed/2026-11-09-a6-bootstrap-entry-point.md docs/superpowers/plans/2026-11-09-a6-bootstrap-entry-point.md 2> /dev/null`. Expected: the results section A6's Task 6 Step 7 writes, with rows 2 to 8, 10 and 13 (the rows that plan calls blocking) each marked pass, or failed with the fixed rerun that passed. A6 moves its plan to `completed/` in the commit that records them. No section, or a blocking row still failing, stops here: a hosted runner is not a clean Mac, so the workflow alone is not the proof.
2. The `fresh-install` workflow has passed once (spec decision 5). Run: `gh run list --workflow fresh-install.yml --status success --limit 1`. Expected: one row. After A6 the job runs `./setup.sh`, and a run from before that change counts too.
3. Precondition 5 holds. Run: `migrate/legacy-to-mise --step packages --dry-run | grep -cE '^  brew(-cask)?:'`. Expected: `0`. The pattern matches only the lines `homebrew_leftovers` prints, not the `  brew uninstall …` lines of the step's own explanations. Any line is a package still Homebrew's: hand the list to the owner (move, declare, uninstall or drop each), not to the removal.
4. The owner says go in chat, after reading the dry run.

Then tell the user: the run asks for the typed phrase, moving the program is reversible with `sh ~/.dotfiles-migration-backup/<timestamp>/RESTORE.txt`, and a package in the drop file stays installed with nothing to update or remove it. Do not run it for them.

- [ ] **Step 7: Document, gate, commit**

`migrate/README.md`, under `packages`: a subsection "Removing Homebrew" with the "why not the uninstaller" paragraph and its two links, the moved and left lists, the preconditions, the decision 5 rule (what blocks removal, what does not, and the drop file's format and location), that `ca-roots trim` stops working, the typed phrase, and the restore command.

```bash
pnpm check
git add migrate/legacy-to-mise migrate/README.md bin/lib/test-migrate
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

- Consumes: `mise dot status --json`. Shape, checked in a scratch config: `{"files":[{"target":"~/.one","source":"…","mode":"symlink"|"symlink-each"|"copy","state":"applied"|"missing"|"differs"|"source_missing","reason":"…"}],…}`. A `symlink-each` entry is one row whose `reason` names only its first problem, with the path prefixed. A5 declares one such entry, `"~/.claude/rules"`, and 37 single-file entries, so the status alone cannot list every conflict. The Codex config is not in `files`: A5 declares it as an edit, `"~/.codex/config.toml/defaults" = { source = …, merge = "missing", permissions = "0600" }`, and the JSON lists it under `edits` as `{"path":"~/.codex/config.toml","edit":"merge:defaults","origin":{…},"state":"differs"}`, with no `reason` (A5's E9, and re-measured on mise 2026.11.5 for this plan). `dot_foreign_links` reads `files` only, so the Codex config is point 3's alone.
- Consumes: `mise dot apply --dry-run`. Checked: with a real file in the way it exits 1 and prints `mise ERROR files: refusing to overwrite existing files (use --force):` on stderr, followed by one line per conflict, two spaces then `~/path`. That list is complete across `symlink` and `symlink-each` entries. With no conflict it exits 0 and prints one `ln -sf` line per entry, not per file. The Codex edit can make it exit 1 with a different header, measured on mise 2026.11.5 in a scratch `HOME` with A5's edit entry: `mise ERROR edits: cannot apply these entries, fix them manually:`, then `  "~/.codex/config.toml" (merge:defaults): failed to parse the TOML target: …` for invalid TOML, or `…: target is a symlink; replace it with a copy of the real file before merging …` for a link that does not point at the source. A link that points at the source passes the dry run (`edit ~/.codex/config.toml (merge:defaults)`, exit 0). So `dot_conflicts` takes only the two-space lines that follow the `files: refusing to overwrite` header, up to the next line that does not start with two spaces, and never reads an `edits:` line as a conflict.
- Consumes: `mise dot apply --yes`, `mise dot status --missing` (exit 1 on any entry not in its desired state, the Codex edit included: measured exit 1 with `differs (failed to parse the TOML target: …)`, `differs (symlink to the merge source; apply replaces it with a copy)` and `differs (target is a symlink; …)`).
- Checked behaviour the step relies on: one conflict makes the whole `mise dot apply` fail, and nothing else in that run is applied. A link that points elsewhere is repointed without `--force` and without a copy, and neither the status nor the dry run lists it under a `symlink-each` entry.
- From the A5 plan's "Part B hook" (measured there, not here): mise turns a whole-directory `~/.claude/rules` link into a real folder of links by itself. An old link to the clone's physical path already reads `applied`.
- The Codex config, from A5's E9 and E18 (mise 2026.11.5) and its "Part B hook" item 4. A missing `~/.codex/config.toml` is created as a regular file at mode 600 (re-measured here: `mise edits: applied ~/.codex/config.toml (merge:defaults)`, then `600 Regular File`). A symlink there that points at the source through the clone reads `differs`, and apply replaces it with a regular file at mode **644**: `permissions` applies only when mise creates the file, and the link counts as an existing one. A symlink anywhere else stops the apply with exit 1 and leaves the linked file alone. A target that is not valid TOML makes apply exit 1 with `failed to parse the TOML target` and leaves the file byte-identical. A regular file that parses keeps its own mode and values, and gains only the keys it lacks. Measured here for point 7's sequence on a link elsewhere (link to a file holding `model = "x"` and an `[mcp_servers.t]` table, `rm`, `cp`, `chmod 600`, apply): exit 0, a regular file at 600 holding `model = "x"`, the table and the added `sandbox_mode`, and the linked file unchanged. So the link goes before the apply, and the step ends with the file at mode 600 either way.
- Verified twice: a `[dotfiles]` entry in `tilde/.config/mise/config.local.toml` replaces the `conf.d` entry with the same key. The A5 plan measured it (its E12, pinned by `test-dotfiles`), and the review re-measured it on 2026-11-09 in a fresh scratch folder.
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
3. **Codex.** `codex=$HOME/.codex/config.toml`. Nothing is changed here. Points 6 and 7 act on what this finds.
   - A symlink whose `readlink` starts with `$REPO/` or `$HOME/dotfiles/`: it joins the point 5 list as `~/.codex/config.toml: a link into the clone. Removed before the apply, which then creates the file at mode 600.` Without that, the apply would leave a regular file at 644.
   - Any other symlink: it joins the list as `~/.codex/config.toml: a link to <path>. Replaced before the apply by a copy of that file at mode 600, which mise then gives only the keys it lacks.` mise's own error for this case says to do exactly that ("replace it with a copy of the real file before merging").
   - A regular file: never touched. When point 4's dry run (run before this check is made) printed `failed to parse the TOML target` for it, print `~/.codex/config.toml is not valid TOML, so mise cannot add the keys it lacks. Fix it by hand and run this step again. It was not changed.` and return 1 after the listing, before any prompt or apply.
4. **Find conflicts and foreign links.** Run `dot_conflicts`, keeping the dry run's stderr for point 3. For each conflict, when the path resolved with `cd -P` on its parent lies inside `REPO`, print `<target>: resolves into the clone, not touched` and return 1 after the listing. That is a whole-directory link this script does not know. Run `dot_foreign_links`.
5. **Print** `<n> old-style link(s): already in place or repointed by mise, nothing is lost.` Then the conflicts as `<target>: a real file or folder is in the way`, the foreign links as `<target>: a link to <path> will be repointed`, and point 3's Codex line.
6. **Ask once.** With at least one conflict, foreign link or Codex link: `Back up the <n> item(s) above and let mise link them?` With none of those but `mise dot status --missing` failing (the half-migrated case): `Run mise dot apply to link what is missing?` With neither, go to 8. On no, print `Left as they are. Finish with: mise dot apply` and go to 8. A declined Codex link stays a link, because nothing is applied.
7. `backup_move` each conflict. For each foreign link, `backup_note links.tsv "<target><TAB><old path>"` and append `ln -sfn '<old path>' '<target>'` to `RESTORE.txt`. For a Codex link, the same `backup_note` and `RESTORE.txt` line, then `run rm "$codex"`, and for a link that does not point into the clone also `run cp "<old path>" "$codex"` and `run chmod 600 "$codex"`. The file it pointed to stays where it is. Then `run mise dot apply --yes`. Never `--force`. Under `--dry-run` nothing is moved and the dry run from point 4 is the report.
8. **Old links nothing declares** (report only). List symlinks whose `readlink` starts with `$REPO/` or `$HOME/dotfiles/` and whose path is not a `target` in the status, found by `find` with `-type l` at `-maxdepth 1` in `~`, `~/.claude/rules`, `~/.claude/skills`, `~/.codex`, `~/.gnupg`, `~/.ssh`, `~/.config/mole`, and at `-maxdepth 1` in `~/.config`, plus the three paths `~/Library/Application Support/Code/User`, `…/lazydocker/config.yml`, `…/rtk/config.toml`. Print each with `(dangling)` when its target is gone. These are the places the old `symlinks.sh` linked into.
9. **Firefox** (report only). The old script made hard links, and A5's `setup/dotfiles-extras.sh` remakes them. Find the profile as the old helper did: the first directory under `~/Library/Application Support/Firefox/Profiles` matching `*dev-edition*`. For `user.js`, `chrome/userContent.css`, `chrome/userChrome.css`: print `hard link ok` when the profile file `-ef` the clone's `firefox/` file, else `not linked to the clone (the bootstrap task links it)`. No profile: one line saying so.
10. Run `mise dot status --missing` and return its status. On 0 print `All dotfiles are in their declared state.`

- [ ] **Step 1: Write the failing tests**

The fake `mise` reads `$STATE/dot-targets`, one `target<TAB>source` per line. `"dot status --json")` prints `$STATE/dot.json`. `"dot status --missing")` exits 0 only when every target is a link `-ef` its source. `"dot apply --dry-run")` prints the real error text on stderr (`mise ERROR files: refusing to overwrite existing files (use --force):` then two spaces and the `~/` path per target that exists and is not a link) and exits 1, or exits 0 with none. `"dot apply --yes")` fails the same way, and otherwise runs `ln -sfn` for each target. `dot.json` holds one `symlink` row per target, one `symlink-each` row `"~/.claude/rules"` whose `source` is `$REPO_COPY/tilde/.claude/rules`, and an `edits` array with the Codex row. The fixture gains `$REPO_COPY/tilde/.codex/config.toml` holding `model = "o3"` and `sandbox_mode = "workspace-write"`.

The fake models the Codex edit as A5's E9 and E18 measured it, after the file conflicts (a file conflict stops the real apply before the edit), with `codex=$HOME/.codex/config.toml` and `src=$REPO_COPY/tilde/.codex/config.toml`:

| `$codex` | `dot apply --dry-run` | `dot apply --yes` | `dot status --missing` |
| --- | --- | --- | --- |
| absent | exit 0 | copies `$src` there, `chmod 600` | exit 1 |
| a link `-ef "$src"` | exit 0 | replaces it with a copy of `$src` at mode 644, as the real one does, so a script that skips the removal ends at 644 and fails the test | exit 1 |
| any other link | stderr `mise ERROR edits: cannot apply these entries, fix them manually:` and `  "~/.codex/config.toml" (merge:defaults): target is a symlink; replace it with a copy of the real file before merging`, exit 1 | the same | exit 1 |
| a regular file whose first line is exactly `model = `, with nothing after the space (the fixture's invalid TOML; `model = "x"` is valid) | the same header and `  "~/.codex/config.toml" (merge:defaults): failed to parse the TOML target: …`, exit 1 | the same, file untouched | exit 1 |
| any other regular file | exit 0 | leaves it as it is (the real merge would add missing keys) | no effect |

```bash
dotfiles_backs_up_then_applies() {
  phase dotfiles
  rm -rf "$HOME/.dotfiles-migration-backup"                    # the packages cases left theirs, and $bak below must be one folder
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
  codex="$HOME/.codex/config.toml"; src="$REPO_COPY/tilde/.codex/config.toml"
  # only the Codex edit is in play: the earlier cases' targets (the ~/.claude/skills conflict among them) would stop each run first
  cp "$STATE/dot-targets" "$tmp/dot-targets.saved"; : > "$STATE/dot-targets"
  mkdir -p "$HOME/.codex"; ln -s "$src" "$codex"                    # an old symlinks.sh link into the clone
  before=$(snapshot); : > "$STATE/mise.log"
  out=$("$script" --step dotfiles < /dev/null 2>&1) || true         # declined: the apply never runs, so the exit is the status check's 1
  [ -L "$codex" ] && [ "$(snapshot)" = "$before" ] && [ -z "$(mutations)" ] || fail "a declined run touched the codex link"
  out=$(yes | "$script" --step dotfiles 2>&1) || fail "codex link into the clone: exit $?: $out"
  [ -f "$codex" ] && [ ! -L "$codex" ] || fail "codex config is still a link"
  [ "$(stat -f %Lp "$codex")" = 600 ] || fail "codex config is not 0600: the link was not removed before the apply"
  grep -qF "ln -sfn '$src' '$codex'" "$HOME"/.dotfiles-migration-backup/*/RESTORE.txt || fail "codex link not recorded"
  printf 'model = "x"\n\n[mcp_servers.t]\ncommand = "t"\n' > "$tmp/elsewhere.toml"
  rm "$codex"; ln -s "$tmp/elsewhere.toml" "$codex"                 # a link somewhere else
  out=$(yes | "$script" --step dotfiles 2>&1) || fail "codex link elsewhere: exit $?: $out"
  [ -f "$codex" ] && [ ! -L "$codex" ] && cmp -s "$codex" "$tmp/elsewhere.toml" || fail "a link elsewhere was not replaced by a copy of its file"
  [ "$(stat -f %Lp "$codex")" = 600 ] || fail "the copy is not 0600"
  [ -f "$tmp/elsewhere.toml" ] || fail "removed the file the link pointed to"
  rm "$codex"; printf 'model = "mine"\n' > "$codex"; chmod 644 "$codex"   # valid TOML, the Mac's own
  out=$(yes | "$script" --step dotfiles 2>&1) || fail "regular codex config: exit $?: $out"
  [ "$(cat "$codex")" = 'model = "mine"' ] && [ "$(stat -f %Lp "$codex")" = 644 ] || fail "touched a regular codex config"
  printf 'model = \n' > "$codex"; cp "$codex" "$tmp/codex.bad"; : > "$STATE/mise.log"   # invalid TOML
  out=$(yes | "$script" --step dotfiles 2>&1) && fail "want exit 1 over an invalid codex config" || [ $? = 1 ] || fail "invalid codex config: want exit 1"
  check_out "names the invalid file" '^~/\.codex/config\.toml is not valid TOML'
  cmp -s "$codex" "$tmp/codex.bad" || fail "an invalid codex config was rewritten"
  ! grep -q 'dot apply --yes' "$STATE/mise.log" || fail "applied over an invalid codex config"
  printf 'model = "mine"\n' > "$codex"; mv "$tmp/dot-targets.saved" "$STATE/dot-targets"
}
half_way_dotfiles() {
  # the conflict was backed up by an earlier run but apply never ran: ~/.zprofile is absent.
  # The earlier cases left ~/.zprofile as a real file and the ~/.claude/skills link with its
  # target, which stops every run at "resolves into the clone" before the prompt, so both go first
  rm -f "$HOME/.zprofile" "$HOME/.claude/skills"
  grep -v '/\.claude/skills/x' "$STATE/dot-targets" > "$STATE/t" && mv "$STATE/t" "$STATE/dot-targets"
  : > "$STATE/mise.log"
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
Expected: no conflict lines (A5's author measured 37 of its 38 entries `applied` on this Mac and one `differs`, the Mole link), one `would ask:` line for Mole's `whitelist` (this Mac has `mole/whitelist.local`), no Codex line (this Mac's `~/.codex/config.toml` is a regular file at mode 600, checked 2026-11-09 with `ls -l` and `stat -f %Lp`), three `hard link ok` lines, and `Changed 0 thing(s).` Any conflict line here is a difference between A5's entries and the old script. Report it to the A5 owner before A5's first apply.

- [ ] **Step 6: Document, gate, commit**

`migrate/README.md`, `dotfiles` section: the ten points, why a Codex link goes before the apply (mise would leave a link into the clone as a regular file at 644, and stops at any other link) and that an invalid Codex config is the owner's to fix, and "never `--force`: mise's `--force` replaces a file with no copy".

```bash
pnpm check
git add migrate/legacy-to-mise migrate/README.md bin/lib/test-migrate
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

- Consumes: `backup_copy`, `backup_move`, `backup_note`, `ask`, `run`, and `reregister_mise_mcp` from Task 4.
- Produces: `step_setup`. Returns 0.

**What only the old method left, and the decision for each:**

| Item | Decision | Why |
| --- | --- | --- |
| `/etc/pam.d/sudo_local` whose content is not exactly `auth       sufficient     pam_tid.so` | Show `diff`, `backup_copy` it, print that the first `mise bootstrap` rewrites it and that `sudo cp <backup> /etc/pam.d/sudo_local` restores it. Nothing is removed. Path overridable as `${MIGRATE_SUDO_LOCAL:-/etc/pam.d/sudo_local}` for the test. | The old `setup.sh` wrote the file only when missing, so a hand-edited one survived. A6 declares it in `[bootstrap.files]`. |
| `/etc/pam.d/sudo_local` with exactly that content | Print `sudo_local: as declared, kept`. | The new method owns it. |
| `${MISE_DATA_DIR:-$HOME/.local/share/mise}/installs/rust` | `ask "Forget mise's old rust install so its shims stop shadowing rustup?"`, `backup_move` it, `run mise reshim`. | Moved here from `setup/misc.sh:189-199` by A6 (inventory M16). |
| `~/.cargo/bin/rustup` that differs (`cmp -s`) from `$PREFIX/opt/rustup/bin/rustup` | Print the old script's hint: `rm -rf ~/.cargo/bin ~/.rustup && /opt/homebrew/opt/rustup/bin/rustup default stable`. Report only. | A6 inventory M17. The toolchain is the owner's call. |
| The `mise` MCP server registered with a command other than `$MISE` | `reregister_mise_mcp` (Task 4, which runs it straight after moving mise). Here it catches a Mac where mise moved some other way. | A4 installs mise with its own installer, so Homebrew's path goes stale. The new `misc.sh` only warns. |
| `private/setup-logs/` | Print `setup logs: kept (the new setup.sh still writes them)`. | A6 keeps the log path. |
| `~/dotfiles` | Print `~/dotfiles: kept (every [dotfiles] source in the mise config resolves through it)`. | After A5 each `[dotfiles]` source is written as `~/dotfiles/…`, so the link is required, not a convenience. A6's `setup.sh` still makes it. |
| `/etc/shells` entry and the login shell | Not mentioned. | Unchanged by the new method. |

- [ ] **Step 1: Write the failing tests**

The fake `claude` and the fake `mise reshim` are the ones Task 4 added.

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
Expected: `sudo_local: as declared, kept` (this Mac's file is the one line). No rust line (`~/.local/share/mise/installs/rust` does not exist here). No `Re-register the mise MCP server` line once Task 4's step has moved mise and re-registered the server, one while the server still names another path. The two `kept` lines. `Changed 0 thing(s).`

- [ ] **Step 6: Add the old-method-name check to `bin/lib/test-conventions`**

Part A's phases delete these names from every doc and script. This check keeps them deleted. It lands after A6's last commit, as its own commit if Steps 1-5 landed earlier: A6 regenerates the last files that name the old method (`setup/bootstrap-runtime.archify.json` and its `.svg`). After the removal-date check:

```bash
# Only the migration script may name what Part A deleted (spec: Part A carries no knowledge of the old method)
old=$(git grep -lE 'Brewfile|brewpick|setup/(brew|symlinks|macos)\.sh' -- . ':!migrate' ':!bin/lib/test-migrate' ':!bin/lib/test-conventions' ':!docs/superpowers' || true)
[ -z "$old" ] || fail "the old setup method is named outside migrate/: $old"
```

Run: `bash bin/lib/test-conventions | tail -1`
Expected: `conventions: all checks passed`. A failure names the files a Part A phase missed. Fix those docs in this commit (D12), not the check. The four exclusions are the only ones: `migrate/` and `bin/lib/test-migrate` hold the old layout by design, `bin/lib/test-conventions` holds this pattern, and `docs/superpowers` holds the plans and the spec. Nothing under `.claude/` is excluded. A4 rewrites `.claude/hooks/test-auditor-readonly.sh:40` (`allow 'grep -n Brewfile README.md'` becomes `grep -n mise`) for this check, since no doc pass would touch a test fixture. If that line still names the Brewfile here, make A4's edit. On 2026-11-09, before Part A, the check's own `git grep` listed 53 files, so it must not land before A6.

Add to the header's description sentence: "that only migrate/ names the old setup method,".

- [ ] **Step 7: Document, gate, commit**

`migrate/README.md`, `setup` section: the decision table above as prose.

```bash
pnpm check
git add migrate/legacy-to-mise migrate/README.md bin/lib/test-migrate bin/lib/test-conventions
git commit -m "Add the setup step to the migration script"
git push
```

- [ ] **Step 8: Hand the real runs to the user (changes this Mac: the user runs it, after an explicit go-ahead)**

With every phase landed, ask the user to run `migrate/legacy-to-mise --dry-run`, read it, then run `migrate/legacy-to-mise`. The implementer does not run it without `--dry-run`. Afterwards:

Run: `mise bootstrap status --missing; echo "exit $?"`
Expected: informational, not a gate. `exit 1` with only macOS preferences listed is an app rewriting its own settings. Any dotfile or package it lists is this script's to explain: run the matching step again.
Run: `migrate/legacy-to-mise --dry-run | tail -1`
Expected: `Changed 0 thing(s).`

---

### Task 8: Removal (on or after 2027-02-28)

**Files:**

- Delete: `migrate/` (the script and its README)
- Delete: `bin/lib/test-migrate`
- Modify: `bin/lib/check` (remove `migrate/legacy-to-mise` from `shell_scripts`, `"migrate/*"` from the Prettier globs, and the `test-migrate` line with its comment)
- Modify: `package.json` (remove `\"migrate/*\"` from `scripts.format`)
- Modify: `bin/lib/test-conventions` (remove the removal-date check and its header words, and the `if [ -e migrate ]` permission-rule check A7's Task 8 added; in the old-method-name check drop the `':!migrate'` and `':!bin/lib/test-migrate'` exclusions)
- Modify: `.claude/settings.json` (remove the five `legacy-to-mise` rules A7's Task 8 added to `permissions.ask`)
- Modify: `README.md` (remove the section "Migrating an existing machine")
- Modify: `bin/sysup`, `bin/lib/test-sysup` (remove A4's two notices that end `run: migrate/legacy-to-mise --step packages`, for a Homebrew mise and for Homebrew casks, and their assertions. Find them with `grep -n legacy-to-mise bin/sysup bin/lib/test-sysup`)
- Modify: `docs/superpowers/specs/2026-11-09-mise-first-setup-and-settings-ui.md` only by `git mv` to `specs/completed/` when every other plan built on it is completed

**Interfaces:** none. Step 3 proves nothing outside these files refers to `migrate/`.

- [ ] **Step 1: Confirm no machine still needs it.** Ask the user whether every Mac set up the old way has been migrated. `~/.dotfiles-migration-backup/` on a Mac is the sign it ran there. Stop if any has not.
- [ ] **Step 2: Delete and edit** the files above.
- [ ] **Step 3: Verify nothing refers to it**

Run: `git grep -nE 'migrate/|test-migrate|legacy-to-mise|dotfiles-migration-backup|CONVENTIONS_TODAY' -- . ':!docs/superpowers'`
Expected: no output.

- [ ] **Step 4: Gate and commit**

Run: `pnpm check`
Expected: exit 0.

```bash
git rm -q migrate/legacy-to-mise migrate/README.md bin/lib/test-migrate
git add bin/lib/check bin/lib/test-conventions bin/sysup bin/lib/test-sysup package.json README.md .claude/settings.json
git commit -m "Remove the migration script"
git push
```

- [ ] **Step 5: Close the plan.** `git mv docs/superpowers/plans/2026-11-09-b-migration-script.md docs/superpowers/plans/completed/`, commit and push. Tell the user that `~/.dotfiles-migration-backup/` on each Mac can be deleted by hand.

---

## Not verified, and the command that settles each

| Claim | Why it is unverified | Command |
| --- | --- | --- |
| After `brew uninstall --cask X`, `mise bootstrap packages apply --yes brew-cask:X` installs it and status reports `managed_by: "mise"` | It changes the machine | Task 4 Step 6, on `font-tinos-nerd-font` |
| The installer, `reshim` and `brew uninstall mise` leave this Mac with working shims. `brew uninstall mise` touches nothing under `~/.local/share/mise` | It changes the machine. The reshim behaviour itself was measured in a scratch folder (P13) | Task 4 Step 6, the first command |
| mise adopts an app bundle in place once Homebrew's `Caskroom` record is moved aside | It changes the machine. Read in the source, not run | Task 4 Step 5a, on `freelens` or `utm` |
| A package declared in `config.local.toml` survives `mise bootstrap packages prune` | Only `status` was measured in a scratch folder (P14). Prune was not run | After Task 4 Step 6: `mise bootstrap packages prune --manager brew --dry-run` no longer lists a formula the user chose to keep |
| mise upgrades a formula Homebrew installed | No formula was outdated on 2026-11-09 | When `brew outdated --formula` lists one: `mise bootstrap packages upgrade --manager brew --dry-run` names it |
| mise's brew backend works with `Library/` and `.git` moved out of `/opt/homebrew` | It changes the machine | The VM run in A6's Task 6 (its formulae and casks rows, on a Mac that never had Homebrew) and the `fresh-install` workflow, then Task 5's own post-check, which restores on failure |
| P16's check finds every package Homebrew still owns: status `package` names match `Caskroom` and `Cellar` folder names by their last `/` part, and a tap cask's status name is tap-qualified | Measured only with nothing declared (`status --json` printed `{}`). The shape with casks declared is A4's measurement, and Task 4 already relies on the same last-part match | After A4 lands: `migrate/legacy-to-mise --step packages --dry-run` lists no `brew-cask:` line for a cask `ls /opt/homebrew/Caskroom` shows and the status reports `managed_by: "mise"`, and the Step 5 `comm` cross-check agrees with the `brew:` lines |
| Precondition 5 can be cleared on this Mac | Task 4 offers all 33 declared casks (P17), but each one the owner declines, or that is running when the step runs, stays `managed_by: "homebrew"` and blocks the removal. No cask has been moved yet | Task 5 Step 6 gate 3 prints `0` |
| mise adopts a self-updating app in place, with no identity check, once Homebrew's `Caskroom` record is moved aside | Read in the source (P17), not run | Task 4 Step 5a, item 6, on `coteditor` |
| A self-updating cask reinstalled with `brew uninstall --cask` then a mise apply reads `managed_by: "mise"` | Only a cask that does not update itself is in Task 4 Step 6 | After Step 5a, the first self-updating cask the owner moves: the Step 6 `jq` line with its token prints `mise` |
| mise converts a whole-directory `~/.claude/rules` link itself | Measured by the A5 plan's author, not here | `ls -ld ~/.claude/rules` after the user's real run shows a folder, not a link |
| A4 and A5 create `30-packages.toml` and `40-dotfiles.toml` | Not built yet. Both plans now name these files | `ls tilde/.config/mise/conf.d/` after each phase lands |
| `settings/registry.toml` writes `kind`, `key` and `access` one per line as `name = "value"` | A2 is not built | Task 2 Step 5 |
| `mise bootstrap packages apply --dry-run` and `mise dot apply --dry-run` touch no network | Not measured | Run each with Wi-Fi off |
