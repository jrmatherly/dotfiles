# P2: Modules and Opt-outs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A person can decline any group of what returnofthemac installs, before the first install or after it, and can skip one single package, without editing a tracked file.

**Architecture:** Each group is a mise module: a `config.rotm-<name>.toml` beside `config.toml`, loaded only when the `env` list in `miserc.local.toml` names `rotm-<name>`. One helper, `bin/lib/rotm-modules`, owns that list. It stores what the user turned off and derives the list as "every module minus those", so a module added later is on for everyone. `setup.sh`, `sysup` and `dotfiles-settings` all go through the helper. One package is skipped with mise's own `state = "absent"` in the machine-local `config.local.toml`.

**Tech Stack:** bash 3.2 (`#!/bin/bash`), mise 2026.11.5 or newer, Python 3.11+ with `tomllib` (the settings package and the self-checks), GitHub Actions, Renovate.

**Spec:** `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`. Read "Opt-outs", "Verified facts" and the P2 brief first. The owner split the brief on 2026-11-12: this plan is modules and opt-outs, and the owner's layer (the 13 values in `docs/forking.md`) is brief P2b, its own later plan.

## Global Constraints

- macOS only.
- mise floor: 2026.11.5 (`setup/mise-floor.sh`). Every measurement below ran on 2026.11.5.
- All modules are on by default. Nothing is forced: every group outside the base has a switch (decision 3).
- Turning a module off stops declaring it. It never removes a formula, a cask or a VS Code extension: the reply names `mise bootstrap packages prune --dry-run`, which lists what no config declares and is not limited to one module. mise tools are different: `sysup` already runs `mise prune --yes`, which deletes tool versions no config selects (`bin/sysup`, the "mise prune" step), so an off module's tools go at the next `sysup`. The docs and the reply say both.
- No tracked file is written by any switch. The state lives in `modules-off.local` and `miserc.local.toml` in the mise config dir, both git-ignored, so an installed copy stays fast-forwardable.
- The owner's Mac is a clone and `~/.config/mise` is a link into it, so an edit to a tracked mise config file is live on this Mac the moment it is saved. Task 3 runs the helper on this Mac before Task 4 moves anything. Do not reorder them.
- `./setup.sh` from a clone with every module on must install exactly what it installs today: `bin/lib/test-bootstrap` passes with no existing assertion removed or loosened.
- Testing rule: a real install or update runs in the UTM guest `macOS`, started with "Run without saving changes", never on the owner's Mac. Self-checks with stubs and scratch homes run anywhere.
- Never run `./setup.sh`, `sysup`, `rotm install`, `rotm update` or `mise bootstrap` against the real home. Never edit `config.local.toml` or `config.override.toml`. Two steps touch the real home, each with the owner's go-ahead: `rotm-modules sync` in Task 3 (it writes `miserc.local.toml`) and the two read-only status calls in Task 4.
- The self-checks have their own helpers (`run`, `prepare`, `check_true`, `has`, `lacks`, `log_has`, `stub`, `$STATE`, `$fix`). The test code here uses them. Where a block here and the file disagree on a helper, the file wins and the assertion stays.
- The commit hook runs `pnpm check` (about two minutes) before the command starts. Edit and commit in separate Bash calls, and retry once when the hook times out.
- Docs mirror behaviour: a change to setup behaviour has its `README.md`, `setup/README.md` or `docs/` edit in the same commit.

## Measured while writing this plan

On 2026-11-12, mise 2026.11.5, in a scratch home and config dir with every `MISE_*_DIR` pointed at it, using `mise bootstrap packages status --json`, `mise config ls`, `mise ls --json`, `mise env --json` and one `packages apply --dry-run`. Nothing was installed. The spec's "Verified facts" holds the same rows.

| Claim | Measured |
| --- | --- |
| A `config.<name>.toml` in the config dir adds its `[bootstrap.packages]` only when `env` in `miserc.local.toml` names it | Yes. Without the list only `conf.d` loaded; with `env = ["fonts"]` the module's cask joined the base's formulae |
| An `env` entry with no `config.<name>.toml` is an error | No. `env = ["installed", "fonts", "apps"]` with no `config.installed.toml` loaded the other two and reported nothing |
| `MISE_ENV` adds to the saved list | No. `MISE_ENV=apps` replaced it, as the docs say `-E` does |
| A `[bootstrap.brew.taps]` entry in a module merges with the base's taps | Yes. A dry run resolved a module's tap formula through the module's tap |
| `[tools]` in a module load only when the module is named | Yes |
| A more local file can cancel one base package | Yes, with `{ state = "absent" }` only. In `config.local.toml` or in a module, status reported the key as `absent`. `false`, `{ enabled = false }` and `{ version = "latest", enabled = false }` are parse errors. `""` and `"absent"` are read as versions. Measured for a `brew:` key that was not installed |
| One tool can be switched off from `config.local.toml` | Yes: `[settings] disable_tools = ["npm:prettier"]` |
| A name in the saved `env` list reaches a project's files | Yes. With `env = ["security"]`, a project's `mise.security.toml` was loaded in that project. With `env = ["rotm-security"]` and `config.rotm-security.toml`, the module loaded and the project's file did not |
| A project's own `.miserc.toml` with an `env` list displaces the saved one | No. The module still loaded inside that project |

Not measured, and settled later in this plan:

- `state = "absent"` on a `vscode:` key (a plugin manager): Task 1.
- What `packages apply --manager <m>` exits with when a package declared absent is installed. `mise bootstrap packages apply --help` says that case "fails for it only when you pass `--manager` or name the package", and `setup.sh` passes `--manager`. Task 1 measures it for `vscode` with the fake `code`; a real cask needs a real install, which is VM row 5.
- That `mise prune` treats an off module's tools as unused. Read from `bin/sysup` and `mise prune --help`, not run: it needs installed tools. VM row 4 shows it.

## Decisions this plan makes

- **Modules add, they do not subtract.** A module's packages move out of `conf.d/30-packages.toml` into its own file. The other shape, everything in the base plus an "off" file that declares each package absent, would keep two lists in step and make mise warn on every apply about installed packages declared absent.
- **The stored truth is the off list.** `modules-off.local` holds one module name per line. `env` is derived from it. Storing the on list would turn a module that arrives in an update off for every existing user.
- **Module names are prefixed where mise sees them.** A person types `fonts`. The `env` entry is `rotm-fonts` and the file is `config.rotm-fonts.toml`, because a saved `env` name also selects `mise.<name>.toml` in every project on the Mac (measured above), and `cloud`, `apps` or `security` are names a project could use. P1's `installed` environment has the same exposure and is not renamed here: it is in the install line and in every installed copy's saved list. It is an open point for the owner.
- **The module names live in one place, `rotm-modules list`.** The settings registry has one row per module and a self-check keeps the two equal.
- **A module may have no packages.** `claude` and `agents` are mostly steps of `setup/misc.sh`. `is-on` is the same question for every module.
- **Dotfile entries stay in the base.** A link to the config of an app that is not installed is harmless, and moving entries would need a second `installed` variant of each.
- **The base keeps what the base runs.** A formula or tool stays in the base when `setup.sh`, `setup/*.sh`, `bin/rotm`, `bin/dotfiles-settings`, `bin/sysup`, `bin/vscode-settings`, a file under `zsh/`, `tilde/.zshrc`, `tilde/.zprofile`, `tilde/.zshenv` or `tilde/.gitconfig` uses it without a `command -v` or `command_exists` guard, or when a self-check says mise needs it. Known today: `uv` (runs `dotfiles-settings`), `ruby` (mise reads the `claude-multipass-app` tap cask with it), `jq`, `minijinja-cli`, and `git-lfs` (`tilde/.gitconfig` sets `filter.lfs.required = true`). These five move into the "Dotfiles framework requirements" section.
- **Declining before the first install is a `setup.sh` flag**, `--without <modules>`, because the install line is the only thing a stranger has typed by then.
- **One package is skipped with mise's own syntax**, documented, with no new command. The spec's "deny list" and "hook for user overrides" are not built: the measurement removed the need.
- **`mise bootstrap unapply` is not offered.** Per mise's docs it removes files, services and dotfile entries, and reports packages with guidance only. The modules hold packages and tools, so it would do nothing.

## Modules

`rotm-modules list` prints these twelve names in this order. The file for `<name>` is `tilde/.config/mise/config.rotm-<name>.toml`.

| Module | What moves into it | Leans on |
| --- | --- | --- |
| `fonts` | The seven `font-*` casks. Gates the Iosevka step in `misc.sh` and `sysup` | |
| `apps` | The "GUI apps" section's casks. Gates `sysup`'s "Raycast" step. The language-server tools `config.toml` installs for Terax (`npm:typescript-language-server` through `npm:@vue/language-server`) and `npm:typescript`, which `misc.sh` links for them. Gates that link step | |
| `vscode` | Every `vscode:` key. The `visual-studio-code` cask stays in the base | |
| `claude` | The `bun` tool. Gates the Claude Code installer, `claude-config restore` and `claude-catalog` in `misc.sh`, and `sysup`'s "Claude Code", "agent skills", "plugins", "Claude config" and "catalog" steps | |
| `agents` | `brew:rtk`, `brew-cask:coderabbit`, `npm:@colbymchenry/codegraph`, `npm:rea-agents`. Gates the CodeGraph wiring, every `register_mcp` call, Serena, Scrapling, Hindsight, REA, SnippetsLab, the remote docs servers and `rtk init` | `claude` for the registrations. REA also wants `ghidra` (`security`) and Hopper (`apps`), and already checks for them |
| `cloud` | The "Cloud / Azure / AWS" section, and the tools `azd`, `azure-functions-core-tools`, `github:microsoft/aspire`, `npm:serverless` | |
| `kubernetes` | The "Kubernetes / containers / infra" section with its two taps, and the tools `flux2`, `talosctl`, `github:home-operations/flate`, `mirrord`, `lazydocker`, `aqua:Azure/kubelogin` | |
| `devops` | The "DevOps / CI / linting" section without `rtk`, `coderabbit`, `ruby` and `uv`, and the tool `github:getsentry/toolkit` | |
| `security` | The "Security / pentesting" section | |
| `network` | The "Networking / system utilities" section | |
| `languages` | The "Languages / runtimes / build tools" section, and the tool `npm:@antfu/ni` | |
| `media` | The "File / text / image processing" section without `jq`, `minijinja-cli` and `git-lfs`, with the `bramstein/webfonttools` tap | |

The base keeps: the "Dotfiles framework requirements" section plus the five formulae above, the `jrmatherly/tap` tap, `[bootstrap.brew]`, and the tools `node`, `python` and `hunk`. Every comment moves with its entry. A step that leans on another module's tool keeps its own `command_exists` check, so an off module makes it skip, not fail.

## Review Focus

- A person turns a module off after installing it: the next `setup.sh` and `sysup` must not report that module's packages as missing, and must not reinstall them. Pinned in Task 4 (status) and Task 8 (row 4).
- A module arrives in an update: it is on for a user who has other modules off, and their off list is unchanged. Pinned in Task 2.
- `miserc.local.toml` already holds `env = ["installed"]`, or a profile name later: `sync` keeps every entry that does not start `rotm-`, in its order, before the modules. Pinned in Task 2.
- A name in `modules-off.local` that is not a module (a typo, or a module removed upstream): `sync` ignores it and says so once, and never fails a setup run. Pinned in Task 2.
- A package is declared `absent` in `config.local.toml`: `setup.sh` ends without listing it as a problem, and `sysup` does not put it in a notice on every run. Pinned in Tasks 5 and 6.
- Every module off: `setup.sh` ends "All done", and a new shell, `git`, a clone of a repository that uses LFS, `rotm settings list` and `help` work. No self-check can prove this. Pinned in Task 8 (row 2).
- `MISE_ENV` is set in the shell: mise ignores the saved list. `sync` prints one warning naming the variable. Pinned in Task 2.
- A typo after `--without`: the run stops before the sudo prompt and before mise is installed. Pinned in Task 3.

---

## File Structure

- `bin/lib/rotm-modules`: the module names, the off list, and the `env` line. The one place that knows them.
- `bin/lib/test-modules`: self-check for the helper and for the split, run by `bin/lib/check`.
- `tilde/.config/mise/config.rotm-<module>.toml`: twelve files, one per row of the table.
- `tilde/.config/mise/conf.d/30-packages.toml`, `tilde/.config/mise/config.toml`: lose what moved.
- `setup.sh`: `--without`, and one `sync` call. `setup/misc.sh`: gates, and the Homebrew prefix from `HOMEBREW_PREFIX`. `bin/sysup`: one `sync` call, gates, two status fixes.
- `settings/registry.toml`, `settings/src/dotfiles_settings/adapters/module.py`, `settings/tests/test_module.py`: the switches.
- `bin/lib/test-packages`, `bin/lib/test-bootstrap`, `bin/lib/test-sysup`: updated and extended.
- `.github/workflows/check.yml`: the package dry run covers the modules. `renovate.json`: the module files are mise files.
- `.gitignore`: `tilde/.config/mise/modules-off.local`.
- `docs/modules.md` (new), `README.md`, `docs/installation.md`, `setup/README.md`, `docs/README.md`, `docs/forking.md`, the spec, `CLAUDE.md` and the rules that name `30-packages.toml`.

---

### Task 1: Measure `state = "absent"` on a plugin manager

**Files:**

- Modify: `bin/lib/test-packages` (one block, after the existing `cfg2` block)
- Modify: `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`

**Interfaces:**

- Produces: two facts for Task 5 and the docs. Whether a `vscode:` key honours `state = "absent"`, and the exit status of `packages apply --yes --manager vscode` when an installed extension is declared absent.

- [x] **Step 1: Add the block to `test-packages`**

A third config dir `cfg3` whose `conf.d/30-packages.toml` declares `vscode:ms-python.python` and `vscode:eamodio.gitlens`, and whose `config.local.toml` holds:

```toml
[bootstrap.packages]
"vscode:ms-python.python" = { state = "absent" }
"vscode:eamodio.gitlens" = { state = "absent" }
```

The fake `code` already reports `ms-python.python` as installed and `eamodio.gitlens` as not.

```bash
mkdir -p "$v/cfg3/conf.d"
cfg=cfg3 vmise bootstrap packages status --json 2> /dev/null > "$v/absent.json" || fail "vscode: status with absent keys"
# Python: both keys report state "absent", neither "missing"
: > "$log"
rc=0
out=$(cfg=cfg3 vmise bootstrap packages apply --yes --manager vscode 2>&1) || rc=$?
! grep -q -- '--install-extension' "$log" || fail "vscode: an absent extension was installed"
! grep -q -- '--uninstall-extension' "$log" || fail "vscode: an absent extension was removed"
echo "absent+installed: rc=$rc: $out" >&2
```

- [x] **Step 2: Run it and read the last line**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-packages`
Expected: exit 0, and one `absent+installed: rc=<n>` line on stderr. If the status assertion fails because the plugin manager ignores `state`, stop and tell the owner: a single extension then cannot be skipped this way, and the docs in Task 7 say so for `vscode:` keys.

- [x] **Step 3: Pin what was seen**

Replace the `echo` with an assertion of the status seen, so a mise release that changes it fails the check.

- [x] **Step 4: Record in the spec**

In "Verified facts", add the two rows this task measured, each ending "(P2 Task 1, mise <version>)". Delete the matching row from "Still not verified".

- [ ] **Step 5: Commit**

```bash
git add bin/lib/test-packages docs/superpowers
git commit -m "Measure how an extension is declared absent"
```

---

### Task 2: `rotm-modules`

**Files:**

- Create: `bin/lib/rotm-modules`
- Create: `bin/lib/test-modules`
- Modify: `bin/lib/check` (run `test-modules` beside `test-rotm`)
- Modify: `.gitignore` (add `tilde/.config/mise/modules-off.local` under the mise block, with its reason)

**Interfaces:**

- Produces, all called by path as `rotm-mode` is, never through `PATH`:
  - `rotm-modules list`: the twelve short names, one per line, in the table's order. Exit 0.
  - `rotm-modules off`: the names in `modules-off.local` that are modules, one per line, in `list` order. Exit 0 with no output when the file is missing.
  - `rotm-modules is-on <name>`: exit 0 when on, 1 when off, 2 with a message on stderr for a name `list` does not print.
  - `rotm-modules set <name> on|off`: rewrites `modules-off.local`, then runs `sync`. Exit 2 for an unknown name or a third word other than `on` or `off`.
  - `rotm-modules sync [--without <a,b>]`: `--without` first adds those names to `modules-off.local` (exit 2 before writing anything when one is unknown). Then it sets the `env` line of `miserc.local.toml`. Prints `modules: env = [...]` when it changed the file and nothing when it did not. Exit 0.
- Every argument and every line of output uses short names (`fonts`). Only the `env` line carries `rotm-fonts`.
- The config dir is `${MISE_CONFIG_DIR:-$HOME/.config/mise}`. Both files are written through it, so on a clone and on an installed copy they land in the checkout, git-ignored. The helper creates the dir's files, never the dir: a missing dir is exit 1 with its path.

- [ ] **Step 1: Write the failing tests**

`bin/lib/test-modules`, with the header shape of `bin/lib/test-rotm`. `cfg` is one temp dir, `MISE_CONFIG_DIR` points at it, `MISE_ENV` is unset, and the cases run in this order on that one dir. `reset` empties it.

```bash
m=bin/lib/rotm-modules
[ "$("$m" list | tr '\n' ' ')" = "fonts apps vscode claude agents cloud kubernetes devops security network languages media " ] || fail "list"
all='"rotm-fonts", "rotm-apps", "rotm-vscode", "rotm-claude", "rotm-agents", "rotm-cloud", "rotm-kubernetes", "rotm-devops", "rotm-security", "rotm-network", "rotm-languages", "rotm-media"'

# First run on a Mac with no list: every module, in order
"$m" sync > "$tmp/out"
[ "$(cat "$cfg/miserc.local.toml")" = "env = [$all]" ] || fail "sync on an empty dir"
grep -q '^modules: env = \[' "$tmp/out" || fail "sync did not say what it wrote"
[ -z "$("$m" sync)" ] || fail "a second sync printed something"

# Entries that are not ours stay first, in their order; other keys stay; a stale rotm- entry goes
reset
printf 'env = ["installed", "rotm-gone", "work"]\nfoo = 1\n' > "$cfg/miserc.local.toml"
"$m" sync > /dev/null
grep -qxF "env = [\"installed\", \"work\", $all]" "$cfg/miserc.local.toml" || fail "entries that are not modules were not kept first"
grep -qx 'foo = 1' "$cfg/miserc.local.toml" || fail "sync dropped another key"

# Off, and back on
"$m" set security off > /dev/null
! grep -q 'rotm-security' "$cfg/miserc.local.toml" || fail "an off module is still in env"
[ "$("$m" off)" = security ] || fail "off does not list it"
"$m" is-on fonts || fail "is-on fonts"
if "$m" is-on security; then fail "is-on security"; fi
"$m" set security on > /dev/null
grep -q 'rotm-security' "$cfg/miserc.local.toml" && [ -z "$("$m" off)" ] || fail "set on"

# --without; a module that is not in the off list is on, which is how one that arrives later behaves
"$m" sync --without fonts,cloud > /dev/null
[ "$("$m" off | tr '\n' ' ')" = "fonts cloud " ] || fail "--without"
grep -q 'rotm-media' "$cfg/miserc.local.toml" || fail "a module not in the off list is off"

# Unknown names
rc=0; "$m" is-on nope 2> /dev/null || rc=$?; [ "$rc" = 2 ] || fail "is-on with an unknown name exited $rc"
rc=0; "$m" sync --without media,nope 2> "$tmp/err" || rc=$?
[ "$rc" = 2 ] && grep -q nope "$tmp/err" && [ "$("$m" off | tr '\n' ' ')" = "fonts cloud " ] || fail "--without with an unknown name wrote something"
echo typo >> "$cfg/modules-off.local"
"$m" sync 2> "$tmp/err" || fail "a stray name in modules-off.local failed sync"
grep -q 'typo' "$tmp/err" || fail "a stray name was not reported"

# A list mise cannot have written, MISE_ENV, and no config dir
reset
printf 'env = [\n  "installed",\n]\n' > "$cfg/miserc.local.toml"
rc=0; "$m" sync 2> "$tmp/err" || rc=$?; [ "$rc" = 1 ] && grep -q 'one line' "$tmp/err" || fail "a multi-line env list was rewritten"
reset
MISE_ENV=work "$m" sync 2> "$tmp/err" > /dev/null || fail "sync with MISE_ENV set"
grep -q 'MISE_ENV' "$tmp/err" || fail "no warning that MISE_ENV replaces the saved list"
rc=0; MISE_CONFIG_DIR="$tmp/missing" "$m" sync 2> /dev/null || rc=$?; [ "$rc" = 1 ] || fail "sync created a config dir"
```

One more block, with a real `mise` on `PATH` and skipped with a message when it is missing, as `test-packages` does. `smise` runs mise from a scratch home with `MISE_CONFIG_DIR`, `MISE_DATA_DIR`, `MISE_STATE_DIR` and `MISE_CACHE_DIR` in `$tmp`, `MISE_CEILING_PATHS="$tmp"` and `MISE_SYSTEM_BREW_PREFIX` at an empty dir. The config dir holds a `conf.d/30-packages.toml` with `"brew:jq"` and a `config.rotm-fonts.toml` with one font cask. Assert `smise bootstrap packages status --json` lists the cask after `sync` and not after `set fonts off`.

- [ ] **Step 2: Run to see it fail**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-modules`
Expected: FAIL at "list", because `bin/lib/rotm-modules` does not exist.

- [ ] **Step 3: Write `bin/lib/rotm-modules`**

Header in the `bin/` shape, saying that it is called by path, that the off list is the stored truth, and why the `env` entries carry the prefix. `set -euo pipefail`. The names are one bash array. The `env` line is rewritten in place when a line starting `env = [` and ending `]` exists, appended when no line starts with `env`, and refused (exit 1, "the env list in miserc.local.toml is not on one line") otherwise. Write through a temp file in the same dir and `mv`, so a failed run leaves the old file.

- [ ] **Step 4: Run to see it pass, check the gate**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-modules && bash -n bin/lib/rotm-modules && shellcheck --severity=warning bin/lib/rotm-modules bin/lib/test-modules`
Expected: `ok`, then no output.

- [ ] **Step 5: Commit**

```bash
git add bin/lib/rotm-modules bin/lib/test-modules bin/lib/check .gitignore
git commit -m "Add rotm-modules, which keeps mise's env list from what is switched off"
```

---

### Task 3: Every entry point syncs, and this Mac gets its list

**Files:**

- Modify: `setup.sh` (the `--without` flag, one `sync` call), `bin/sysup` (one `sync` call)
- Modify: `bin/lib/test-bootstrap`, `bin/lib/test-sysup`
- Modify: `setup/README.md`, `docs/installation.md`

**Interfaces:**

- Consumes: `rotm-modules is-on <name>` and `sync [--without <a,b>]` (Task 2).
- Produces: `./setup.sh --without <a,b>`, also reachable as `rotm install --without <a,b>` and `rotm update --without <a,b>`, since `rotm` passes its arguments to `setup.sh`. After this task every Mac that ran `setup.sh` or `sysup` has an `env` list naming all twelve modules, which is what makes Task 4 safe.

- [ ] **Step 1: Make the fixture forget the list between runs**

`test-bootstrap`'s `run()` deletes `$tmp/home`, but `~/.config/mise` is a link into `$fix/tilde/.config/mise`, so the two state files would survive from one case to the next. Add to `run()`, beside its `rm -rf`: `rm -f "$fix/tilde/.config/mise/miserc.local.toml" "$fix/tilde/.config/mise/modules-off.local"`. Copy `bin/lib/rotm-modules` into the fixture where it copies `bin/lib/rotm-mode`.

- [ ] **Step 2: Write the failing tests**

In `bin/lib/test-bootstrap`, after the existing cases. `in_order` reads the mise log, so the order is taken from the screen:

```bash
line_of() { grep -nF -- "$1" <<< "$out" | head -1 | cut -d: -f1; }

prepare() { :; }
run -y
check_true "setup writes the module list" grep -q 'rotm-media' "$HOME/.config/mise/miserc.local.toml"
check_true "the list is written before the dotfiles are applied" [ "$(line_of 'modules: env = ')" -lt "$(line_of 'Linking the dotfiles')" ]

run -y --without fonts,security
check_true "--without is stored" [ "$(tr '\n' ' ' < "$HOME/.config/mise/modules-off.local")" = "fonts security " ]

run -y --without nope
check_true "an unknown module stops setup" [ "$rc" -eq 2 ]
check_true "and names it" has 'nope'
check_true "before any mise call" log_empty
check_true "and before the password prompt" [ ! -s "$STATE/sudo.log" ]

run -y -- --dry-run
check_true "a dry run writes no module list" [ ! -e "$HOME/.config/mise/miserc.local.toml" ]
check_true "and says so" has 'dry run: the module list is not written'
```

In `bin/lib/test-sysup`: the fixture's `$HOME/.config/mise` must exist (`mkdir -p` it where the fixture builds `$HOME`), and after `run`: `check_true "sysup syncs the module list" grep -q 'rotm-media' "$HOME/.config/mise/miserc.local.toml"`.

- [ ] **Step 3: Run to see them fail**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-bootstrap; LC_ALL=en_US.UTF-8 bin/lib/test-sysup`
Expected: FAIL "setup writes the module list", and the `sysup` case.

- [ ] **Step 4: Implement**

`setup.sh`:

- Parse `--without <list>` and `--without=<list>` with the other flags and add it to the usage header. Still inside flag parsing, check each name with `"$DOTFILES_DIR/bin/lib/rotm-modules" is-on <name>`: status 2 prints the helper's message and exits 2. This is before the warning banner, the sudo prompt and the mise install.
- Call `"$DOTFILES_DIR/bin/lib/rotm-modules" sync ${without:+--without "$without"}` right after the block that links `~/.config/mise` into the repo, which is before `setup/mise-floor.sh` and every mise call. Exit with the helper's status when it is not 0.
- In a dry run, skip the call and print "dry run: the module list is not written".

`bin/sysup`: one `"$(dirname "$0")/lib/rotm-modules" sync` call, by path as it calls `rotm-mode`, placed after the `dotfiles` step so a module that arrived in that pull is in the list for the same run. A non-zero status is `status fail modules "<the helper's last line>"` and the run goes on.

`rotm update --without nope` still fetches before `setup.sh` rejects the name. That is accepted: the fetch changes nothing the user chose.

- [ ] **Step 5: Run to see them pass**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-bootstrap && LC_ALL=en_US.UTF-8 bin/lib/test-sysup`
Expected: `ok` twice.

- [ ] **Step 6: Document and commit**

`setup/README.md`: the flag, and the step in the order list. `docs/installation.md`: one paragraph under the install line, "To leave groups out from the start, add `--without <names>` after `setup.sh`", pointing at `docs/modules.md` (written in Task 7).

```bash
git add setup.sh bin/sysup bin/lib/test-bootstrap bin/lib/test-sysup setup/README.md docs/installation.md
git commit -m "Sync the module list from setup and sysup, and take --without"
```

- [ ] **Step 7: Give this Mac its list, with the owner's go-ahead**

Ask the owner first: this writes `miserc.local.toml` through `~/.config/mise`, the one real-home write in the plan. Then:

Run: `bin/lib/rotm-modules sync && cat ~/.config/mise/miserc.local.toml && git status --short`
Expected: `modules: env = [...]` with twelve `rotm-` names, the same line in the file, and no change in `git status`. Then `cd ~ && mise config ls` lists the same files as before and no error. No `config.rotm-*.toml` exists yet, so mise's view of this Mac is unchanged.

---

### Task 4: Split the package list and the tools into modules

**Files:**

- Create: the twelve `tilde/.config/mise/config.rotm-<module>.toml`
- Modify: `tilde/.config/mise/conf.d/30-packages.toml`, `tilde/.config/mise/config.toml`
- Modify: `bin/lib/test-packages`, `bin/lib/test-modules`
- Modify: `.github/workflows/check.yml`, `renovate.json`, and `.github/workflows/fresh-install.yml` (comments only, where they name the file)

**Interfaces:**

- Consumes: `rotm-modules list` (Task 2). Task 3 Step 7 has run on this Mac.
- Produces: the file layout in "Modules". Each module file starts with a comment naming the module, what turning it off leaves installed, and `rotm settings set modules.<name> off`.

- [ ] **Step 1: Record what this Mac reports today**

Ask the owner first: these read this Mac's real state and change nothing.

Run: `cd ~ && mise bootstrap packages status --missing > /tmp/p2-before-packages.txt 2>&1; mise ls --missing > /tmp/p2-before-tools.txt 2>&1; mise ls --global --json | jq 'keys | length'`
Expected: two files, and the number of global tools. Put that number in the Step 2 assertion.

- [ ] **Step 2: Rewrite the `test-packages` assertions to read every file**

The Python block loads `conf.d/30-packages.toml`, `config.toml` and each `config.rotm-<name>.toml` for `name` in `rotm-modules list`, and asserts:

```python
# the union is what the two files held before: nothing lost, nothing added
assert (count("brew"), count("brew-cask"), count("vscode")) == (143, 33, 184)
assert len(all_tools) == TOOLS_BEFORE                        # the number from Step 1
assert not dupes, f"declared in two files: {dupes}"          # packages and tools alike
assert all(v == "latest" for v in every_package.values())
assert set(all_taps) == used and len(all_taps) <= 5
# a tap sits in the file whose packages use it
for f in files: assert set(f.taps) == {tap_of(k) for k in f.packages if is_tap_key(k)}, f.name
# the base keeps what the base runs
for k in ("brew:uv", "brew:ruby", "brew:jq", "brew:minijinja-cli", "brew:git-lfs", "brew:git", "brew:zsh", "brew-cask:visual-studio-code"):
    assert k in base.packages, k
assert set(base.tools) == {"node", "python", "hunk"}
assert not any(k.startswith("vscode:") for f in files if f.name != "vscode" for k in f.packages)
assert all(k.startswith("brew-cask:font-") for k in fonts.packages) and len(fonts.packages) == 7
# files on disk and names in the helper agree; installed is the one environment that is not a module
on_disk = {p.name for p in config_dir.glob("config.*.toml")} - {"config.local.toml", "config.override.toml"}
assert on_disk == {f"config.rotm-{n}.toml" for n in modules} | {"config.installed.toml"}, on_disk
```

The completion-hook block reads `flux2` and `talosctl` from `config.rotm-kubernetes.toml`.

- [ ] **Step 3: Run to see it fail**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-packages`
Expected: FAIL "conf.d/30-packages.toml", on the files-on-disk assertion.

- [ ] **Step 4: Move the entries**

Follow the "Modules" table. Move lines, do not retype them: each entry keeps its comment and its order within its section. Section header comments go with their section. Every one of the twelve files exists, however short.

Before moving a formula or tool out of the base, apply the rule in "Decisions" to the files it lists. One that is used unguarded stays in the base, in the framework section, and is added to the base assertion in Step 2 in the same commit.

- [ ] **Step 5: Add the "one module off" case to `test-modules`**

With `smise` from Task 2 and a config dir that is a copy of the tracked files of `tilde/.config/mise`:

```bash
"$m" sync > /dev/null
all=$(smise bootstrap packages status --json | jq '[.brew.packages[], ."brew-cask".packages[]] | length')
[ "$all" = 176 ] || fail "every module on declares $all formulae and casks, not 176"
"$m" set security off > /dev/null
smise bootstrap packages status --json > "$tmp/s.json"
smise bootstrap packages apply --dry-run --manager brew > "$tmp/dry.txt" 2>&1 || fail "the dry run failed with security off"
for p in nmap hydra ghidra; do
  ! jq -e --arg p "$p" '.brew.packages[] | select(.package == $p)' "$tmp/s.json" > /dev/null || fail "security is off and $p is still declared"
  ! grep -qw "$p" "$tmp/dry.txt" || fail "security is off and the dry run would install $p"
done
jq -e '.brew.packages[] | select(.package == "git")' "$tmp/s.json" > /dev/null || fail "the base lost git"
```

The dry run downloads formula metadata, as `check.yml`'s does. This is the spec's "Done when" for P2.

- [ ] **Step 6: Run to see both pass, and compare this Mac**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-packages && LC_ALL=en_US.UTF-8 bin/lib/test-modules`
Expected: `ok` twice.

Run: `cd ~ && mise bootstrap packages status --missing 2>&1 | diff /tmp/p2-before-packages.txt - && mise ls --missing 2>&1 | diff /tmp/p2-before-tools.txt -`
Expected: no output. A difference means an entry was lost or doubled in the move.

- [ ] **Step 7: CI and Renovate see the module files**

`check.yml`, "Package list dry run": copy `conf.d/30-packages.toml` and every `config.rotm-*.toml` into `$d/config`, and write the list with `MISE_CONFIG_DIR=$d/config bin/lib/rotm-modules sync`. The tools are still left out, for the reason the comment gives, so each copy drops its `[tools]` table: `awk '/^\[tools\]/{skip=1; next} /^\[/{skip=0} !skip'`. Say so in the comment.

`renovate.json`: three rules match the mise manager, and tools they cover move into module files. Read Renovate's mise manager page for its default file patterns. If `config.rotm-*.toml` under `tilde/.config/mise/` is not among them, add a `mise` block with `managerFilePatterns` (or the key that page names) covering `tilde/.config/mise/config.toml` and `tilde/.config/mise/config.rotm-*.toml`.

Run: `actionlint .github/workflows/check.yml && npx --yes --package renovate -- renovate-config-validator renovate.json`
Expected: no output from `actionlint`, and "Config validated successfully". If `npx` is denied here, validate the JSON with `jq . renovate.json > /dev/null` and say the Renovate check was not run.

- [ ] **Step 8: Commit**

```bash
git add tilde/.config/mise bin/lib/test-packages bin/lib/test-modules .github/workflows renovate.json
git commit -m "Split the packages and tools into twelve modules"
```

---

### Task 5: Gates in `misc.sh`, and an absent package is not a problem

**Files:**

- Modify: `setup/misc.sh`, `setup.sh` (`packages_for`)
- Modify: `bin/lib/test-bootstrap`

**Interfaces:**

- Consumes: `rotm-modules is-on <name>` (Task 2).
- Produces: in `misc.sh`, `module_on <name>`, true when the module is on, and for an off module one line per gated step: `skipped: the <name> module is off`.

- [ ] **Step 1: Make `misc.sh` runnable under stubs**

No self-check runs `setup/misc.sh` today: `test-bootstrap` only greps it. It also puts `/opt/homebrew/bin` first on `PATH` and names `/opt/homebrew/opt/rustup` and `/opt/homebrew/opt/ghidra` directly, so under a test it would run this Mac's real `uv`, `rtk`, `gh` and `claude`. Change those three places to `${HOMEBREW_PREFIX:-/opt/homebrew}`, as `setup.sh` does. In `test-bootstrap`, add the guard it already has for `setup.sh`:

```bash
! grep -q '/opt/homebrew' <(grep -v 'HOMEBREW_PREFIX:-/opt/homebrew' "$repo/setup/misc.sh" | grep -v '^ *#') \
  || fail "setup/misc.sh names /opt/homebrew without HOMEBREW_PREFIX; not running it"
```

- [ ] **Step 2: Build the harness, every module on**

A folder `$tmp/mfix` holds copies of `setup/misc.sh` and `bin/lib/rotm-modules` at their repo paths, and one-line stubs at `bin/install-iosevka-code`, `bin/claude-config`, `bin/claude-catalog`, `bin/hindsight-memory` and `bin/install-snippetslab-skill` that append their name and arguments to `$STATE/misc.log`. `stub` adds `curl`, `uv`, `uvx`, `npx`, `jq`, `rtk` and `mise` to `$tmp/bin`, each logging the same way. The `claude` stub goes in `$tmp/bin` and at `$HOME/.local/bin/claude`, logs, and exits 1 when its first two arguments are `mcp get`: `misc.sh` registers a server only when `mcp get` fails.

```bash
misc() {
  rc=0
  out=$(cd "$HOME" && HOMEBREW_PREFIX="$tmp/nobrew" PATH="$tmp/bin:/usr/bin:/bin" DOTFILES_YES=1 "$tmp/mfix/setup/misc.sh" 2>&1 < /dev/null) || rc=$?
}
ran() { grep -qF -- "$1" "$STATE/misc.log"; }
fresh() { rm -rf "$HOME" "$STATE"; mkdir -p "$HOME/.config/mise" "$HOME/.local/bin" "$STATE"; : > "$STATE/misc.log"; }

fresh; misc
check_true "all on: misc.sh exits 0" [ "$rc" -eq 0 ]
check_true "all on: the font step runs" ran install-iosevka-code
check_true "all on: Claude's config is restored" ran 'claude-config restore'
check_true "all on: the catalog is built" ran claude-catalog
check_true "all on: an MCP server is registered" ran 'mcp add'
check_true "all on: a uv tool is installed" ran 'tool install'
check_true "all on: rtk is wired" ran 'init -g'
```

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-bootstrap`
Expected: `ok`. These cases must pass before Step 3, or the off cases prove nothing. If a step does not fire, fix the stubs, not `misc.sh`.

- [ ] **Step 3: Write the failing tests**

```bash
fresh
printf 'claude\nagents\nfonts\napps\n' > "$HOME/.config/mise/modules-off.local"
misc
check_true "modules off: misc.sh still exits 0" [ "$rc" -eq 0 ]
for call in install-iosevka-code 'claude-config restore' claude-catalog 'mcp add' 'tool install' hindsight-memory 'init -g'; do
  check_true "modules off: no $call" eval '! ran "$call"'
done
check_true "a gated step says why it was skipped" has 'skipped: the claude module is off'
check_true "and so does the font step" has 'skipped: the fonts module is off'
check_true "no TypeScript warning with apps off" lacks 'npm:typescript is not installed'

# The Claude Code installer: no claude anywhere, the module off, and curl is not run
fresh; rm -f "$tmp/bin/claude"
printf 'claude\n' > "$HOME/.config/mise/modules-off.local"
misc
check_true "claude off: the installer is not fetched" eval '! ran "claude.ai/install.sh"'
```

And for `packages_for`, two cases in the existing style. `prepare` makes the stub `mise` exit 1 for `packages apply --yes --manager brew-cask`, with a status that reports every `brew-cask` package `installed` except one in state `unexpectedly_installed`, which is what Task 1 measured for an installed package declared absent:

```bash
run -y
check_true "an installed package declared absent is not a problem" lacks 'Setup finished with'
check_true "and setup exits 0" [ "$rc" -eq 0 ]
```

The second case is the same with one more package in state `missing`: `has 'Setup finished with 1 problem'`.

- [ ] **Step 4: Run to see them fail**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-bootstrap`
Expected: FAIL "modules off: no install-iosevka-code".

- [ ] **Step 5: Implement**

`misc.sh`: `module_on() { "$DOTFILES_DIR/bin/lib/rotm-modules" is-on "$1"; }`, and wrap the steps the "Modules" table names for `fonts`, `apps`, `claude` and `agents`. The existing `command_exists` guards stay inside the gate. Steps for other modules need no gate: each already checks for its tool (`rustup`, `dotnet`, `aspire`, `supabase`).

`setup.sh` `packages_for`: when the manager's apply fails, nothing for that manager is in state `missing` afterwards, and at least one of its packages is in state `unexpectedly_installed`, it is not a problem. The decision reads states from `status --json`, not mise's wording. Any other failure stays a problem.

- [ ] **Step 6: Run to see them pass, then commit**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-bootstrap`
Expected: `ok`.

```bash
git add setup/misc.sh setup.sh bin/lib/test-bootstrap
git commit -m "Skip the Claude, agent, app and font steps of a module that is off"
```

---

### Task 6: `sysup` honours the modules

**Files:**

- Modify: `bin/sysup`, `bin/lib/test-sysup`
- Modify: `.claude/rules/sysup.md` where a stated fact became false

**Interfaces:**

- Consumes: `rotm-modules is-on <name>` and `off` (Task 2), called as `"$(dirname "$0")/lib/rotm-modules"`.

- [ ] **Step 1: Write the failing tests**

In `bin/lib/test-sysup`, a case with `claude`, `agents`, `fonts` and `apps` in `$HOME/.config/mise/modules-off.local`:

```bash
run
for pair in 'Iosevka:fonts' 'Claude Code:claude' 'agent skills:claude' 'plugins:claude' 'Claude config:claude' 'catalog:claude' 'REA skill:agents' 'Hindsight memory:agents' 'SnippetsLab skill:agents' 'mise MCP:agents' 'Scrapling:agents' 'Raycast:apps'; do
  check_true "${pair%%:*} is left out" has "^✔ ${pair%%:*} +the ${pair##*:} module is off\$"
done
check_true "no Claude config is saved" no_save
check_true "the prune notice names the modules that are off" has 'packages prune .*modules off: fonts, apps, claude, agents'
```

A case where the stub's package status holds one package in state `unexpectedly_installed`, one in state `absent` and the rest `installed`: `check_true "an absent package is not a notice" has '^✔ packages status +all installed$'`.

- [ ] **Step 2: Run to see them fail**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-sysup`
Expected: FAIL "Iosevka is left out".

- [ ] **Step 3: Implement**

- Each named step reports `status ok "<step>" "the <name> module is off"` and does nothing else when its module is off: `Iosevka` on `fonts`; `Claude Code`, `agent skills`, `plugins`, `Claude config`, `catalog` on `claude`; `REA skill`, `Hindsight memory`, `SnippetsLab skill`, `mise MCP`, `Scrapling` on `agents`; `Raycast` on `apps`, since that step opens the app with no check that it is installed. `agent skills` goes with `claude` because `claude-config restore` in `misc.sh`, which installs those skills, is gated on `claude`.
- "packages status": a package in state `absent` or `unexpectedly_installed` is not `not_installed`.
- "packages prune": when its notice fires and `rotm-modules off` prints anything, the notice ends "(modules off: a, b)", so the count is explained.

- [ ] **Step 4: Run to see them pass, then commit**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-sysup`
Expected: `ok`.

```bash
git add bin/sysup bin/lib/test-sysup .claude/rules/sysup.md
git commit -m "Leave an off module's steps out of sysup"
```

---

### Task 7: The switches in `dotfiles-settings`, and the docs

**Files:**

- Create: `settings/src/dotfiles_settings/adapters/module.py`, `settings/tests/test_module.py`, `docs/modules.md`
- Modify: `settings/src/dotfiles_settings/adapters/__init__.py`, `settings/src/dotfiles_settings/registry.py` (`KINDS`), `settings/registry.toml`, `settings/src/dotfiles_settings/adapters/package.py` (the two read-only messages), `settings/README.md`
- Modify: `bin/lib/test-modules`, `bin/vscode-settings` (its font warning names `30-packages.toml`), `README.md`, `docs/README.md`, `docs/forking.md`, `setup/README.md`, `CLAUDE.md`, `bin/CLAUDE.md`, `.claude/rules/*.md`, `.claude/agents/docs-auditor.md` and `.claude/skills/add-tool/SKILL.md` where they name `30-packages.toml` as the one package file

**Interfaces:**

- Consumes: `rotm-modules list`, `off`, `set <name> on|off` (Task 2).
- Produces: twelve settings `modules.<name>`, `kind = "module"`, `key = "<name>"`, `type = "bool"`, `true_value = "on"`, `default = "on"`, `access = "rw"`, `section = "Modules"`. `ModuleAdapter` with `read`, `write`, `reset` and `write_note` in the shape of the other adapters. It runs `$DOTFILES/bin/lib/rotm-modules` the way `adapters/tool.py`'s `run` runs a `bin/` script, and raises `SettingsError("DOTFILES is not set")` when the variable is missing. `bin/dotfiles-settings` exports `DOTFILES`.

- [ ] **Step 1: Write the failing tests**

`settings/tests/test_module.py`. A fixture sets `DOTFILES` to a temp dir holding a stub `bin/lib/rotm-modules` that keeps its off list in a temp file and appends each call's arguments to a log:

```python
def test_read_on_by_default(adapter, setting):                  # Value.value == "on", Source.SEED, no drift
def test_write_off_calls_the_helper(adapter, setting, calls):   # calls[-1] == ["set", "security", "off"]; read() then gives "", Source.OVERRIDE
def test_write_rejects_other_values(adapter, setting):          # InvalidValue for "maybe"
def test_reset_turns_it_on(adapter, setting, calls):            # calls[-1] == ["set", "security", "on"]
def test_note_names_what_stays_and_what_goes(adapter, setting):
    # adapter.write_note(setting) holds "no package is uninstalled",
    # "mise bootstrap packages prune --dry-run" and "sysup removes its mise tools"
def test_helper_failure_is_a_settings_error(adapter, setting):  # the stub exits 2 -> SettingsError carrying its stderr
def test_no_dotfiles_is_a_settings_error(adapter, setting, monkeypatch):  # DOTFILES unset
def test_allowed_on_an_installed_copy(adapter, setting):        # no refuse_installed: the state files are git-ignored
```

In `bin/lib/test-modules`: the `key`s of the registry's `kind = "module"` rows equal `rotm-modules list`, in order.

- [ ] **Step 2: Run to see them fail**

Run: `cd settings && uv run --locked pytest tests/test_module.py -q`
Expected: FAIL, `adapters/module.py` does not exist.

- [ ] **Step 3: Implement**

The adapter, the `KINDS` and `ADAPTERS` entries, and the twelve registry rows. Each row's `help` says in one sentence what the module holds, from the "Modules" table, and names the module it leans on where the table gives one. `package.py`'s two messages name the module files as well as `30-packages.toml`.

- [ ] **Step 4: Run to see them pass**

Run: `cd settings && uv run --locked pytest -q && cd .. && LC_ALL=en_US.UTF-8 bin/lib/test-modules`
Expected: all pass, then `ok`.

- [ ] **Step 5: Write `docs/modules.md` and fix the docs that changed**

`docs/modules.md` (not named after a command, so `help modules` reads it): the table of modules in a reader's words, with the "leans on" column; all on by default; `rotm settings set modules.<name> off` and `on`; `--without` on the install line; what off does, in three plain sentences (nothing more is installed for it; formulae, casks and extensions stay until `mise bootstrap packages prune`, which is not limited to one module, so read its dry run first; its mise tools are removed by the next `sysup`); that `sysup` will keep mentioning the undeclared packages; skipping one thing:

```toml
# ~/.config/mise/config.local.toml
[bootstrap.packages]
"brew-cask:warp" = { state = "absent" }

[settings]
disable_tools = ["npm:serverless"]
```

and that an absent package already installed is left in place. For `vscode:` keys, say what Task 1 measured.

`README.md`: one line and a link. `docs/forking.md`: the `30-packages.toml` row now says a fork trims modules or turns them off. `docs/README.md`: the page in the index. The instruction files: only sentences that became false, chiefly "formulae, casks and VS Code extensions (`30-packages.toml`)" and where a new package goes. The `add-tool` skill gains the question "which module".

- [ ] **Step 6: Gate and commit**

Run: `pnpm check`
Expected: exit 0.

```bash
git add settings docs README.md setup/README.md CLAUDE.md bin/CLAUDE.md bin/vscode-settings .claude bin/lib/test-modules
git commit -m "Add a switch per module to the settings, and document opting out"
```

---

### Task 8: The VM proof

**Files:**

- Create: `docs/superpowers/specs/2026-11-11-installable-probe/p2-evidence.sh` (the shape of `p1-evidence.sh`, which refuses to run on the host)
- Modify: this plan (`#### Results`)

**Interfaces:**

- Consumes: everything above, pushed to `main`. The install line follows `?ref=main`, as P1's proof did.

- [ ] **Step 1: Write `p2-evidence.sh`, lint it, copy it to the share**

One function per row, each writing `row-<n>.txt` to the shared folder.

- [ ] **Step 2: The owner runs the rows in a disposable guest**

| # | Do | Pass when |
| --- | --- | --- |
| 1 | The install line with `--without security,cloud,kubernetes,vscode` after `setup.sh` | "All done" or only tolerated problems. `mise bootstrap packages status --json` lists no `nmap`, no `awscli`, no `helm` and no `vscode:` key. `modules-off.local` holds the four names |
| 2 | A fresh guest. The install line with all twelve names after `--without` | `setup.sh` exits 0 or 2 with only tolerated problems. A new terminal opens a prompt with no error. `git status` in a scratch repo, `git clone` of a public repository that uses LFS, `rotm settings list` and `help rotm` all work. This is the proof that the base stands alone |
| 3 | On the row 1 guest: `rotm settings set modules.security on`, then `rotm update -y` | `nmap` is installed. The copy has no changed tracked file |
| 4 | Then `rotm settings set modules.kubernetes on`, `rotm update -y`, `rotm settings set modules.kubernetes off`, then `sysup` | `helm` is still installed. `sysup` reports "all installed" for packages, a prune notice ending "(modules off: ...)", and its "mise prune" step lists `flux2` or `talosctl` as removed. Record which tools went |
| 5 | With `apps` on and Warp installed, add `"brew-cask:warp" = { state = "absent" }` to `~/.config/mise/config.local.toml`, then `rotm update -y`, then `sysup` | Warp is still in `/Applications`. Neither run lists it as a problem or a notice. Record the exit status and text of `mise bootstrap packages apply --yes --manager brew-cask` |
| 6 | A fresh guest. The plain install line | The same package and tool counts as P1's row 3 and row 5: nothing missing for `brew`, `brew-cask`, `vscode`, and `mise ls --missing` is empty |

- [ ] **Step 3: Record and fix**

Add `#### Results` here: the date, the guest build, the mise version, the commit proven, one line per row. A failure is fixed on `main` and its row rerun from a fresh guest. A package that row 2 shows the base needs moves into the base, with its line in the Task 4 assertion. If row 4 shows `mise prune` leaves an off module's tools alone, correct the Global Constraint, the adapter's note and `docs/modules.md`.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers
git commit -m "Record the VM proof of modules and opt-outs"
```

---

### Task 9: Close the phase

**Files:**

- Modify: the spec, `CLAUDE.md`, `.claude/rules/setup.md`

- [ ] **Step 1: Update the spec**

In "Opt-outs": the install passes no module list, since the list is derived by `rotm-modules`; replace the bullet that says the install command passes it with `-E`, and the one that offers `unapply`. In the P2 brief, replace "Settled" with one "Shipped" line naming this plan. In "Plans", mark this file done. In the P4 brief's "Known", note that the `env` list is written by `rotm-modules sync`, which keeps entries that do not start `rotm-` first, so a profile is such an entry. Move the rows Task 8 measured into "Verified facts".

- [ ] **Step 2: Promote and move**

Ask the owner before moving `stable`: Task 8 proved the install on `main`.

```bash
git mv docs/superpowers/plans/2026-11-12-p2-modules-and-opt-outs.md docs/superpowers/plans/completed/
git add -A docs/superpowers CLAUDE.md .claude/rules
git commit -m "Complete P2: modules and opt-outs"
git push
```

Then ask the owner to review before the owner's-layer plan is written.
