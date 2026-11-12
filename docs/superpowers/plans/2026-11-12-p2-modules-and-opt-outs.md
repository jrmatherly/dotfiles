# P2: Modules and Opt-outs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A person can decline any group of what returnofthemac installs, before the first install or after it, and can skip one single package, without editing a tracked file.

**Architecture:** Each group is a mise module: a `config.<name>.toml` beside `config.toml`, loaded only when the `env` list in `miserc.local.toml` names it. One helper, `bin/lib/rotm-modules`, owns that list. It stores what the user turned off and derives the list as "every module minus those", so a module added later is on for everyone. `setup.sh`, `sysup` and `dotfiles-settings` all go through the helper. One package is skipped with mise's own `state = "absent"` in the machine-local `config.local.toml`.

**Tech Stack:** bash 3.2 (`#!/bin/bash`), mise 2026.11.5 or newer, Python 3.11+ with `tomllib` (the settings package and the self-checks), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`. Read "Opt-outs", "Verified facts" and the P2 brief first. The owner split the brief on 2026-11-12: this plan is modules and opt-outs, and the owner's layer (the 13 values in `docs/forking.md`) is its own later plan.

## Global Constraints

- macOS only.
- mise floor: 2026.11.5 (`setup/mise-floor.sh`). Every measurement below ran on 2026.11.5.
- All modules are on by default. Nothing is forced: every group outside the base has a switch (decision 3).
- Turning a module off never uninstalls. It stops declaring. The reply names the two commands that remove (`mise bootstrap unapply <module>` and `mise bootstrap packages prune --dry-run`), and `prune` is not limited to one module.
- No tracked file is written by any switch. The state lives in `modules-off.local` and `miserc.local.toml` in the mise config dir, both git-ignored, so an installed copy stays fast-forwardable.
- The owner's Mac is a clone and `~/.config/mise` is a link into it, so an edit to a tracked mise config file is live on this Mac the moment it is saved. Task 3 runs the helper on this Mac before Task 4 moves anything. Do not reorder them.
- `./setup.sh` from a clone with every module on must install exactly what it installs today: `bin/lib/test-bootstrap` passes with no existing assertion removed or loosened.
- Testing rule: a real install or update runs in the UTM guest `macOS`, started with "Run without saving changes", never on the owner's Mac. Self-checks with stubs and scratch homes run anywhere.
- Never run `./setup.sh`, `sysup`, `rotm install`, `rotm update` or `mise bootstrap` against the real home. Never edit `config.local.toml` or `config.override.toml`. Two steps touch the real home, each with the owner's go-ahead: `rotm-modules sync` in Task 3 (it writes `miserc.local.toml`) and the two read-only status calls in Task 4.
- The self-checks have their own helpers (`run`, `prepare`, `check_true`, `has`, `log_has`, `stub`, `$STATE`). The test code in this plan uses them where it can. Where a block here and the file disagree on a helper's name, the file wins and the assertion stays.
- The commit hook runs `pnpm check` (about two minutes) before the command starts. Edit and commit in separate Bash calls, and retry once when the hook times out.
- Docs mirror behaviour: a change to setup behaviour has its `README.md`, `setup/README.md` or `docs/` edit in the same commit.

## Measured while writing this plan

On 2026-11-12, mise 2026.11.5, in a scratch home and config dir with every `MISE_*_DIR` pointed at it, using `mise bootstrap packages status --json`, `mise config ls`, `mise ls --json` and one `packages apply --dry-run`. Nothing was installed. The spec's "Verified facts" holds the same rows.

| Claim | Measured |
| --- | --- |
| A `config.<name>.toml` in the config dir adds its `[bootstrap.packages]` only when `env` in `miserc.local.toml` names it | Yes. Without the list only `conf.d` loaded; with `env = ["fonts"]` the module's cask joined the base's formulae |
| An `env` entry with no `config.<name>.toml` is an error | No. `env = ["installed", "fonts", "apps"]` with no `config.installed.toml` loaded the other two and reported nothing |
| `MISE_ENV` adds to the saved list | No. `MISE_ENV=apps` replaced it, as the docs say `-E` does |
| A `[bootstrap.brew.taps]` entry in a module merges with the base's taps | Yes. A dry run resolved a module's tap formula through the module's tap |
| `[tools]` in a module load only when the module is named | Yes |
| A more local file can cancel one base package | Yes, with `{ state = "absent" }` only. In `config.local.toml` or in a module, status reported the key as `absent`. `false`, `{ enabled = false }` and `{ version = "latest", enabled = false }` are parse errors. `""` and `"absent"` are read as versions |
| One tool can be switched off from `config.local.toml` | Yes: `[settings] disable_tools = ["npm:prettier"]` |
| mise accepts a key it does not know in `miserc.local.toml` | Yes, but this plan does not rely on it |

Not measured, and settled by Task 1: `state = "absent"` on a `vscode:` key (a plugin manager), and what `packages apply --manager <m>` exits with when a package declared absent is installed. `mise bootstrap packages apply --help` says that case "fails for it only when you pass `--manager` or name the package", and `setup.sh` passes `--manager`.

## Decisions this plan makes

- **Modules add, they do not subtract.** A module's packages move out of `conf.d/30-packages.toml` into its own file. The other shape, everything in the base plus an "off" file that declares each package absent, would keep two lists in step and make mise warn on every apply about installed packages declared absent.
- **The stored truth is the off list.** `modules-off.local` holds one module name per line. `env` is derived from it. Storing the on list would turn a module that arrives in an update off for every existing user.
- **The module names live in one place, `rotm-modules list`.** The settings registry has one row per module and a self-check keeps the two equal.
- **A module may have no file.** `claude` and `agents` are mostly steps of `setup/misc.sh`, not mise declarations. mise tolerates an `env` name with no file, so `is-on` is the same question for every module.
- **Dotfile entries stay in the base.** A link to the config of an app that is not installed is harmless, and moving entries would need a second `installed` variant of each.
- **The base keeps what the base runs.** A formula or tool stays in the base when `setup.sh`, `setup/*.sh`, `bin/rotm`, `bin/dotfiles-settings`, `bin/sysup` or `bin/vscode-settings` calls it without a `command -v` guard, or when a self-check says mise needs it. Known today: `uv` (runs `dotfiles-settings`), `ruby` (mise reads the `claude-multipass-app` tap cask with it), `jq` and `minijinja-cli`. These four move into the "Dotfiles framework requirements" section.
- **Declining before the first install is a `setup.sh` flag**, `--without <modules>`, because the install line is the only thing a stranger has typed by then.
- **One package is skipped with mise's own syntax**, documented, with no new command. The spec's "deny list" and "hook for user overrides" are not built: the measurement removed the need.

## Modules

`rotm-modules list` prints these twelve names in this order.

| Module | File | What moves into it |
| --- | --- | --- |
| `fonts` | `config.fonts.toml` | The seven `font-*` casks. Gates the Iosevka step in `misc.sh` and `sysup` |
| `apps` | `config.apps.toml` | The "GUI apps" section's casks, and the language-server tools `config.toml` installs for Terax (`npm:typescript-language-server` through `npm:@vue/language-server`) |
| `vscode` | `config.vscode.toml` | Every `vscode:` key. The `visual-studio-code` cask stays in the base |
| `claude` | `config.claude.toml` | The `bun` tool. Gates the Claude Code installer, `claude-config restore` and `claude-catalog` |
| `agents` | `config.agents.toml` | `brew:rtk`, `brew-cask:coderabbit`, `npm:@colbymchenry/codegraph`, `npm:rea-agents`. Gates the CodeGraph wiring, every `register_mcp` call, Serena, Scrapling, Hindsight, REA, SnippetsLab, the remote docs servers and `rtk init` |
| `cloud` | `config.cloud.toml` | The "Cloud / Azure / AWS" section, and the tools `azd`, `azure-functions-core-tools`, `github:microsoft/aspire`, `npm:serverless` |
| `kubernetes` | `config.kubernetes.toml` | The "Kubernetes / containers / infra" section with its two taps, and the tools `flux2`, `talosctl`, `github:home-operations/flate`, `mirrord`, `lazydocker` |
| `devops` | `config.devops.toml` | The "DevOps / CI / linting" section without `rtk`, `coderabbit`, `ruby` and `uv`, and the tool `github:getsentry/toolkit` |
| `security` | `config.security.toml` | The "Security / pentesting" section |
| `network` | `config.network.toml` | The "Networking / system utilities" section |
| `languages` | `config.languages.toml` | The "Languages / runtimes / build tools" section, and the tools `npm:typescript`, `npm:@antfu/ni` |
| `media` | `config.media.toml` | The "File / text / image processing" section without `jq` and `minijinja-cli`, with the `bramstein/webfonttools` tap |

The base keeps: the "Dotfiles framework requirements" section plus the four formulae above, the `jrmatherly/tap` tap, `[bootstrap.brew]`, and the tools `node`, `python` and `hunk`. Every comment moves with its entry.

## Review Focus

- A person turns a module off after installing it: the next `setup.sh` and `sysup` must not report that module's packages as missing, and must not reinstall them. Pinned in Task 4 (status) and Task 6 (sysup).
- A module arrives in an update: it is on for a user who has other modules off, and their off list is unchanged. Pinned in Task 2.
- `miserc.local.toml` already holds `env = ["installed"]`, or a profile name later: `sync` keeps every entry that is not a module name, in its order, before the modules. Pinned in Task 2.
- A name in `modules-off.local` that is not a module (a typo, or a module removed upstream): `sync` ignores it and says so once, and never fails a setup run. Pinned in Task 2.
- A package is installed and then declared `absent` in `config.local.toml`: `setup.sh` ends without listing it as a problem. Pinned in Task 5.
- Every module off: `setup.sh` ends "All done", and a new shell, `git`, `rotm settings list` and `help` work. No self-check can prove this. Pinned in Task 8 (VM row 2).
- `MISE_ENV` is set in the shell: mise ignores the saved list. `sync` prints one warning naming the variable. Pinned in Task 2.

---

## File Structure

- `bin/lib/rotm-modules`: the module names, the off list, and the `env` line. The one place that knows them.
- `bin/lib/test-modules`: self-check for the helper and for the split, run by `bin/lib/check`.
- `tilde/.config/mise/config.<module>.toml`: twelve files, one per row of the table (the `claude` and `agents` files are short).
- `tilde/.config/mise/conf.d/30-packages.toml`, `tilde/.config/mise/config.toml`: lose what moved.
- `setup.sh`: `--without`, and one `sync` call. `setup/misc.sh`, `bin/sysup`: gates.
- `settings/registry.toml`, `settings/src/dotfiles_settings/adapters/module.py`, `settings/tests/test_module.py`: the switches.
- `bin/lib/test-packages`, `bin/lib/test-bootstrap`, `bin/lib/test-sysup`: updated and extended.
- `.github/workflows/check.yml`: the package dry run covers the modules.
- `.gitignore`: `tilde/.config/mise/modules-off.local`.
- `docs/modules.md` (new), `README.md`, `docs/installation.md`, `setup/README.md`, `docs/README.md`, `docs/forking.md`, the spec, `CLAUDE.md` and the rules that name `30-packages.toml`.

---

### Task 1: Measure the two open mise facts, and record all of them

**Files:**

- Modify: `bin/lib/test-packages` (two cases, in the existing fake-`code` block)
- Modify: `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`

**Interfaces:**

- Produces: `ABSENT_INSTALLED_RC`, the exit status of `mise bootstrap packages apply --yes --manager vscode` when an installed extension is declared absent. Task 5 handles exactly that status.

- [ ] **Step 1: Add the two cases to `test-packages`**

After the existing `cfg2` block, with a third config dir `cfg3` whose `conf.d/30-packages.toml` declares `vscode:ms-python.python` and `vscode:eamodio.gitlens`, and whose `config.local.toml` holds:

```toml
[bootstrap.packages]
"vscode:ms-python.python" = { state = "absent" }
"vscode:eamodio.gitlens" = { state = "absent" }
```

The fake `code` reports `ms-python.python` as installed and `eamodio.gitlens` as not.

```bash
cfg=cfg3 vmise bootstrap packages status --json 2> /dev/null > "$v/absent.json" || fail "vscode: status with absent keys"
# both keys report state "absent", neither "missing"
: > "$log"
rc=0
out=$(cfg=cfg3 vmise bootstrap packages apply --yes --manager vscode 2>&1) || rc=$?
! grep -q -- '--install-extension' "$log" || fail "vscode: an absent extension was installed"
! grep -q -- '--uninstall-extension' "$log" || fail "vscode: an absent extension was removed"
echo "absent+installed: rc=$rc: $out" >&2
```

- [ ] **Step 2: Run it and read the last line**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-packages`
Expected: exit 0, and one `absent+installed: rc=<n>` line on stderr. `<n>` is `ABSENT_INSTALLED_RC`. If the status assertion fails because a plugin manager ignores `state`, stop and tell the owner: single-extension skips then need another route, and Task 5 changes.

- [ ] **Step 3: Pin what was seen**

Replace the `echo` with an assertion of the status seen and of the text mise printed for the installed extension, so a mise release that changes either fails the check.

- [ ] **Step 4: Record in the spec**

In "Verified facts", add the two rows this task measured, each ending "(P2 Task 1, mise <version>)". The rows measured while the plan was written are already there.

- [ ] **Step 5: Commit**

```bash
git add bin/lib/test-packages docs/superpowers
git commit -m "Measure how one package is declared absent, and record the module probes"
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
  - `rotm-modules list`: the twelve names, one per line, in the table's order. Exit 0.
  - `rotm-modules off`: the names in `modules-off.local` that are modules, one per line, in `list` order. Exit 0 with no output when the file is missing.
  - `rotm-modules is-on <name>`: exit 0 when on, 1 when off, 2 with a message on stderr for a name `list` does not print.
  - `rotm-modules set <name> on|off`: rewrites `modules-off.local`, then runs `sync`. Exit 2 for an unknown name or a third word other than `on` or `off`.
  - `rotm-modules sync [--without <a,b>]`: `--without` first adds those names to `modules-off.local` (exit 2 before writing anything when one is unknown). Then it sets the `env` line of `miserc.local.toml`. Prints `modules: env = [...]` when it changed the file and nothing when it did not. Exit 0.
- The config dir is `${MISE_CONFIG_DIR:-$HOME/.config/mise}`. Both files are written through it, so on a clone and on an installed copy they land in the checkout, git-ignored.

- [ ] **Step 1: Write the failing tests**

`bin/lib/test-modules`, with the header shape of `bin/lib/test-rotm`. Every case runs the helper with `MISE_CONFIG_DIR` set to a fresh temp dir and `MISE_ENV` unset.

```bash
m=bin/lib/rotm-modules
[ "$("$m" list | tr '\n' ' ')" = "fonts apps vscode claude agents cloud kubernetes devops security network languages media " ] || fail "list"

# First run on a Mac with no list: every module, in order
"$m" sync > "$tmp/out"
[ "$(cat "$cfg/miserc.local.toml")" = 'env = ["fonts", "apps", "vscode", "claude", "agents", "cloud", "kubernetes", "devops", "security", "network", "languages", "media"]' ] || fail "sync on an empty dir"
grep -q '^modules: env = \[' "$tmp/out" || fail "sync did not say what it wrote"
[ -z "$("$m" sync)" ] || fail "a second sync printed something"

# Entries that are not modules stay first, in their order; other keys stay
printf 'env = ["installed", "work"]\nfoo = 1\n' > "$cfg/miserc.local.toml"
"$m" sync > /dev/null
grep -qx 'env = \["installed", "work", "fonts", .*"media"\]' "$cfg/miserc.local.toml" || fail "non-module entries were not kept first"
grep -qx 'foo = 1' "$cfg/miserc.local.toml" || fail "sync dropped another key"

# Off, and back on
"$m" set security off > /dev/null
! grep -q '"security"' "$cfg/miserc.local.toml" || fail "an off module is still in env"
[ "$("$m" off)" = security ] || fail "off does not list it"
"$m" is-on fonts || fail "is-on fonts"
if "$m" is-on security; then fail "is-on security"; fi
"$m" set security on > /dev/null
grep -q '"security"' "$cfg/miserc.local.toml" && [ -z "$("$m" off)" ] || fail "set on"

# --without, and a module that arrives later stays on
"$m" sync --without fonts,cloud > /dev/null
[ "$("$m" off | tr '\n' ' ')" = "fonts cloud " ] || fail "--without"
grep -q '"media"' "$cfg/miserc.local.toml" || fail "a module not in the off list is off"

# Unknown names
rc=0; "$m" is-on nope 2> /dev/null || rc=$?; [ "$rc" = 2 ] || fail "is-on with an unknown name exited $rc"
rc=0; "$m" sync --without fonts,nope 2> "$tmp/err" || rc=$?; [ "$rc" = 2 ] && grep -q nope "$tmp/err" || fail "--without with an unknown name"
echo typo >> "$cfg/modules-off.local"
"$m" sync 2> "$tmp/err" || fail "a stray name in modules-off.local failed sync"
grep -q 'typo' "$tmp/err" || fail "a stray name was not reported"

# A list mise cannot have written, and MISE_ENV
printf 'env = [\n  "installed",\n]\n' > "$cfg/miserc.local.toml"
rc=0; "$m" sync 2> "$tmp/err" || rc=$?; [ "$rc" = 1 ] && grep -q 'one line' "$tmp/err" || fail "a multi-line env list was rewritten"
rm "$cfg/miserc.local.toml"
MISE_ENV=work "$m" sync 2> "$tmp/err" > /dev/null || fail "sync with MISE_ENV set"
grep -q 'MISE_ENV' "$tmp/err" || fail "no warning that MISE_ENV replaces the saved list"
```

One more block: with a real `mise` on `PATH`, a scratch config dir holding a `conf.d` with `"brew:jq"`, a `config.fonts.toml` with one font cask, and the helper's `sync` then `set fonts off`, assert `mise bootstrap packages status --json` lists the cask after the first and not after the second. Skip it with a message when `mise` is missing, as `test-packages` does.

- [ ] **Step 2: Run to see it fail**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-modules`
Expected: FAIL at "list", because `bin/lib/rotm-modules` does not exist.

- [ ] **Step 3: Write `bin/lib/rotm-modules`**

Header in the `bin/` shape, saying that it is called by path and that the off list is the stored truth. `set -euo pipefail`. The names are one bash array. The `env` line is rewritten in place when a line starting `env = [` and ending `]` exists, appended when no line starts with `env`, and refused (exit 1, "the env list in miserc.local.toml is not on one line") otherwise. Write through a temp file in the same dir and `mv`, so a failed run leaves the old file.

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

- Consumes: `rotm-modules sync [--without <a,b>]` (Task 2).
- Produces: `./setup.sh --without <a,b>`, also reachable as `rotm install --without <a,b>` and `rotm update --without <a,b>`, since `rotm` passes its arguments to `setup.sh`. After this task every Mac that ran `setup.sh` or `sysup` has an `env` list naming all twelve modules, which is what makes Task 4 safe.

- [ ] **Step 1: Write the failing tests**

In `bin/lib/test-bootstrap`, after the existing cases. The fixture `$fix` gains a copy of `bin/lib/rotm-modules`, since `setup.sh` calls it by path.

```bash
prepare() { :; }
run -y
check_true "setup writes the module list" grep -q '"media"' "$HOME/.config/mise/miserc.local.toml"
check_true "the list is written before the dotfiles are applied" in_order 'modules: env = ' 'Linking the dotfiles'

run -y --without fonts,security
check_true "--without is stored" [ "$(tr '\n' ' ' < "$HOME/.config/mise/modules-off.local")" = "fonts security " ]

run -y --without nope
check_true "an unknown module stops setup" [ "$rc" -eq 2 ]
check_true "and it stops before any mise call" log_empty

run -y -- --dry-run
check_true "a dry run writes no module list" [ ! -e "$HOME/.config/mise/miserc.local.toml" ]
check_true "and says so" has 'dry run: the module list is not written'
```

`in_order` takes the two patterns it is given today; if it reads the mise log and not the screen, assert the order with the screen text instead. In `bin/lib/test-sysup`, after `run`: `check_true "sysup syncs the module list" grep -q '"media"' "$HOME/.config/mise/miserc.local.toml"`.

- [ ] **Step 2: Run to see them fail**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-bootstrap; LC_ALL=en_US.UTF-8 bin/lib/test-sysup`
Expected: FAIL "setup writes the module list", and the `sysup` case.

- [ ] **Step 3: Implement**

`setup.sh`: parse `--without <list>` and `--without=<list>` with the other flags, add it to the usage header, and call `"$DOTFILES_DIR/bin/lib/rotm-modules" sync ${without:+--without "$without"}` right after `~/.config/mise` is linked and before the dotfiles apply. Exit with the helper's status when it is not 0. In a dry run, skip the call and print "dry run: the module list is not written". `bin/sysup`: one `sync` call after its `cd "$HOME"` and before its first mise call, failing the run only on a non-zero status.

- [ ] **Step 4: Run to see them pass**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-bootstrap && LC_ALL=en_US.UTF-8 bin/lib/test-sysup`
Expected: `ok` twice.

- [ ] **Step 5: Document and commit**

`setup/README.md`: the flag, and the step in the order list. `docs/installation.md`: one paragraph under the install line, "To leave groups out from the start, add `--without <names>` after `setup.sh`", pointing at `docs/modules.md` (written in Task 7).

```bash
git add setup.sh bin/sysup bin/lib/test-bootstrap bin/lib/test-sysup setup/README.md docs/installation.md
git commit -m "Sync the module list from setup and sysup, and take --without"
```

- [ ] **Step 6: Give this Mac its list, with the owner's go-ahead**

Ask the owner first: this writes `miserc.local.toml` through `~/.config/mise`, the one real-home write in the plan. Then:

Run: `bin/lib/rotm-modules sync && cat ~/.config/mise/miserc.local.toml && git status --short`
Expected: `modules: env = [...]` with twelve names, the same line in the file, and no change in `git status`. Then `cd ~ && mise config ls` lists no error. No `config.<module>.toml` exists yet, so mise's view of this Mac is unchanged.

---

### Task 4: Split the package list and the tools into modules

**Files:**

- Create: the twelve `tilde/.config/mise/config.<module>.toml`
- Modify: `tilde/.config/mise/conf.d/30-packages.toml`, `tilde/.config/mise/config.toml`
- Modify: `bin/lib/test-packages`, `bin/lib/test-modules`
- Modify: `.github/workflows/check.yml`, `.github/workflows/fresh-install.yml` (comments only, where they name the file)

**Interfaces:**

- Consumes: `rotm-modules list` (Task 2). Task 3 Step 6 has run on this Mac.
- Produces: the file layout in "Modules". Each module file starts with a comment naming the module, what turning it off leaves installed, and `rotm settings set modules.<name> off`.

- [ ] **Step 1: Rewrite the `test-packages` assertions to read every file**

The Python block loads `conf.d/30-packages.toml` and each `config.<name>.toml` for `name` in `rotm-modules list`, and asserts:

```python
# the union is what one file held before: nothing lost, nothing added
assert (count("brew"), count("brew-cask"), count("vscode")) == (143, 33, 184)
assert not dupes, f"declared in two files: {dupes}"          # packages and tools alike
assert all(v == "latest" for v in every_package.values())
assert set(all_taps) == used and len(all_taps) <= 5
# a tap sits in the file whose packages use it
for f in files: assert set(f.taps) == {tap_of(k) for k in f.packages if is_tap_key(k)}, f.name
# the base keeps what the base runs
for k in ("brew:uv", "brew:ruby", "brew:jq", "brew:minijinja-cli", "brew:git", "brew:zsh", "brew-cask:visual-studio-code"):
    assert k in base.packages, k
assert set(base.tools) == {"node", "python", "hunk"}
assert not any(k.startswith("vscode:") for f in files if f.name != "vscode" for k in f.packages)
assert all(k.startswith("brew-cask:font-") for k in fonts.packages) and len(fonts.packages) == 7
# files on disk and names in the helper agree; installed is the one non-module environment
assert {p.name for p in config_dir.glob("config.*.toml")} - LOCAL == {f"config.{n}.toml" for n in modules} | {"config.installed.toml"}
```

`LOCAL` is `config.local.toml` and `config.override.toml`. The tool count before the move is asserted the same way: record `len(tools)` from today's `config.toml` in the test first, then assert the union equals it. The completion-hook block reads `flux2` and `talosctl` from `config.kubernetes.toml`.

- [ ] **Step 2: Run to see it fail**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-packages`
Expected: FAIL "conf.d/30-packages.toml", on the files-on-disk assertion.

- [ ] **Step 3: Move the entries**

Follow the "Modules" table. Move lines, do not retype them: each entry keeps its comment and its order within its section. Section header comments go with their section. A file that would hold only comments still exists (`config.claude.toml` holds `bun`).

Before moving a formula out of the base, apply the rule in "Decisions": search `setup.sh`, `setup/*.sh`, `bin/rotm`, `bin/dotfiles-settings`, `bin/sysup` and `bin/vscode-settings` for its binary. One called without a `command -v` or `command_exists` guard stays in the base, in the framework section, and is added to the base assertion in Step 1 in the same commit.

- [ ] **Step 4: Add the "one module off" case to `test-modules`**

With real `mise`, a scratch config dir that is a copy of `tilde/.config/mise` (the tracked files only), `MISE_SYSTEM_BREW_PREFIX` pointed at an empty dir as `check.yml` does:

```bash
"$m" sync > /dev/null
all=$(smise bootstrap packages status --json | jq '[.brew.packages[], ."brew-cask".packages[]] | length')
[ "$all" = 176 ] || fail "every module on declares $all formulae and casks, not 176"
"$m" set security off > /dev/null
smise bootstrap packages status --json > "$tmp/s.json"
for p in nmap hydra ghidra; do
  ! jq -e --arg p "$p" '.brew.packages[] | select(.package == $p)' "$tmp/s.json" > /dev/null || fail "security is off and $p is still declared"
done
jq -e '.brew.packages[] | select(.package == "git")' "$tmp/s.json" > /dev/null || fail "the base lost git"
```

- [ ] **Step 5: Run to see both pass, and look at this Mac**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-packages && LC_ALL=en_US.UTF-8 bin/lib/test-modules`
Expected: `ok` twice.

Ask the owner first: these read this Mac's real state and change nothing.

Run: `cd ~ && mise bootstrap packages status --missing; mise ls --missing`
Expected: the same output as before this task (run both before Step 3 and keep the output to compare). A package or tool that is newly missing or newly undeclared means an entry was lost in the move.

- [ ] **Step 6: Make the CI dry run cover the modules**

`check.yml`, "Package list dry run": copy `conf.d/30-packages.toml` and every `config.<module>.toml` into `$d/config`, write the `env` list with `MISE_CONFIG_DIR=$d/config bin/lib/rotm-modules sync`, and keep the rest. The comment says why the tools are not resolved there (the whole `config.toml` would install its pythons first), which stays true since module files hold tools too: strip the `[tools]` tables from the copies with the same Python the self-checks use, and say so in the comment.

Run: `actionlint .github/workflows/check.yml`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add tilde/.config/mise bin/lib/test-packages bin/lib/test-modules .github/workflows
git commit -m "Split the packages and tools into twelve modules"
```

---

### Task 5: Gates in `misc.sh`, and one absent package is not a problem

**Files:**

- Modify: `setup/misc.sh`, `setup.sh` (`packages_for`)
- Modify: `bin/lib/test-bootstrap`

**Interfaces:**

- Consumes: `rotm-modules is-on <name>` (Task 2), `ABSENT_INSTALLED_RC` and mise's message for it (Task 1).
- Produces: in `misc.sh`, `module_on <name>`, true when the module is on, and for an off module one line per gated step: `skipped: the <name> module is off`.

- [ ] **Step 1: Write the failing tests**

No self-check runs `setup/misc.sh` today: `test-bootstrap` only greps it. So this step builds the harness first, and its every-module-on case must pass before the off case is written, or the off case proves nothing.

In `bin/lib/test-bootstrap`, a new block. A folder `$tmp/mfix` holds copies of `setup/misc.sh` and `bin/lib/rotm-modules` at their repo paths, and one-line stubs at `bin/install-iosevka-code`, `bin/claude-config`, `bin/claude-catalog`, `bin/hindsight-memory` and `bin/install-snippetslab-skill` that append their name and arguments to `$STATE/misc.log`. `stub` adds `curl`, `uv`, `uvx`, `npx`, `claude`, `rtk` and `mise` to `$tmp/bin`, each logging the same way (`claude` also goes at `$HOME/.local/bin/claude`, where `misc.sh` looks). `misc` runs it:

```bash
misc() {
  rc=0
  out=$(cd "$HOME" && PATH="$tmp/bin:/usr/bin:/bin" DOTFILES_YES=1 "$tmp/mfix/setup/misc.sh" 2>&1 < /dev/null) || rc=$?
}
ran() { grep -qF -- "$1" "$STATE/misc.log"; }

misc
check_true "all on: the font step runs" ran install-iosevka-code
check_true "all on: Claude's config is restored" ran 'claude-config restore'
check_true "all on: an MCP server is registered" ran 'claude mcp add'
check_true "all on: a uv tool is installed" ran 'uv tool install'
check_true "all on: rtk is wired" ran 'rtk init'

printf 'claude\nagents\nfonts\n' > "$HOME/.config/mise/modules-off.local"
: > "$STATE/misc.log"
misc
check_true "modules off: misc.sh still exits 0" [ "$rc" -eq 0 ]
for call in install-iosevka-code 'claude-config restore' claude-catalog 'claude mcp add' 'uv tool install' hindsight-memory 'rtk init' 'claude.ai/install.sh'; do
  check_true "modules off: no $call" eval '! ran "$call"'
done
check_true "a gated step says why it was skipped" has 'skipped: the claude module is off'
check_true "and so does the font step" has 'skipped: the fonts module is off'
```

For the Claude Code installer case, remove the `claude` stubs first so `misc.sh` would reach `curl`, and assert `curl` was not run.

And for `packages_for`, a case in the existing style: `prepare` makes the stub `mise` exit `ABSENT_INSTALLED_RC` and print mise's absent-and-installed text for `packages apply --yes --manager brew-cask`, with its status reporting nothing missing. Then `check_true "an installed package declared absent is not a problem" lacks 'Setup finished with'` and `[ "$rc" -eq 0 ]`.

- [ ] **Step 2: Run to see them fail**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-bootstrap`
Expected: the all-on cases pass, and FAIL "modules off: no install-iosevka-code".

- [ ] **Step 3: Implement**

`misc.sh`: `module_on() { "$DOTFILES_DIR/bin/lib/rotm-modules" is-on "$1"; }`, and wrap the steps the "Modules" table names for `fonts`, `claude` and `agents`. The existing `command_exists` guards stay inside the gate. Steps for other modules need no gate: each already checks for its tool (`rustup`, `dotnet`, `aspire`, `supabase`). `setup.sh` `packages_for`: when the manager's apply fails, nothing is missing afterwards, and the output carries only mise's absent-and-installed text, it is not a problem. Any other failure stays one.

- [ ] **Step 4: Run to see them pass, then commit**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-bootstrap`
Expected: `ok`.

```bash
git add setup/misc.sh setup.sh bin/lib/test-bootstrap
git commit -m "Skip the Claude, agent and font steps of a module that is off"
```

---

### Task 6: `sysup` honours the modules

**Files:**

- Modify: `bin/sysup`, `bin/lib/test-sysup`
- Modify: `.claude/rules/sysup.md` where a stated fact became false

**Interfaces:**

- Consumes: `rotm-modules is-on <name>` (Task 2).

- [ ] **Step 1: Write the failing test**

In `bin/lib/test-sysup`, a case with `claude`, `agents` and `fonts` in `$HOME/.config/mise/modules-off.local`:

```bash
run
for pair in 'Iosevka:fonts' 'Claude Code:claude' 'plugins:claude' 'Claude config:claude' 'catalog:claude' 'agent skills:agents' 'REA skill:agents' 'Hindsight memory:agents' 'SnippetsLab skill:agents' 'mise MCP:agents' 'Scrapling:agents'; do
  check_true "${pair%%:*} is left out" has "^✔ ${pair%%:*} +the ${pair##*:} module is off\$"
done
check_true "no Claude config is saved" no_save
check_true "packages of an off module are not reported missing" has '^✔ packages status +all installed$'
```

- [ ] **Step 2: Run to see it fail**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-sysup`
Expected: FAIL "Iosevka is left out".

- [ ] **Step 3: Implement**

Each of those steps reports `status ok "<step>" "the <name> module is off"` and does nothing else when its module is off: `Iosevka` on `fonts`; `Claude Code`, `plugins`, `Claude config`, `catalog` on `claude`; `agent skills`, `REA skill`, `Hindsight memory`, `SnippetsLab skill`, `mise MCP`, `Scrapling` on `agents`.

- [ ] **Step 4: Run to see it pass, then commit**

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
- Modify: `bin/lib/test-modules`, `README.md`, `docs/README.md`, `docs/forking.md`, `setup/README.md`, `CLAUDE.md`, `.claude/rules/*.md` and `.claude/skills/add-tool/SKILL.md` where they name `30-packages.toml` as the one package file

**Interfaces:**

- Consumes: `rotm-modules list`, `off`, `set <name> on|off` (Task 2).
- Produces: twelve settings `modules.<name>`, `kind = "module"`, `key = "<name>"`, `type = "bool"`, `true_value = "on"`, `default = "on"`, `access = "rw"`, `section = "Modules"`. `ModuleAdapter` with `read`, `write`, `reset` in the shape of the other adapters. It runs the helper at `<repo>/bin/lib/rotm-modules`, resolved from the package's own path as `mise.config_dir()` callers do, and `DOTFILES_SETTINGS_MODULES` overrides the path for tests.

- [ ] **Step 1: Write the failing tests**

`settings/tests/test_module.py`, with a stub helper script on `DOTFILES_SETTINGS_MODULES` that keeps its off list in a temp file:

```python
def test_read_on_by_default(adapter, setting):       # Value.value == "on", Source.SEED, no drift
def test_write_off_calls_the_helper(adapter, setting, calls):   # calls == [["set", "security", "off"]]; read() then gives "", Source.OVERRIDE
def test_write_rejects_other_values(adapter, setting):          # InvalidValue for "maybe"
def test_reset_turns_it_on(adapter, setting, calls):            # calls[-1] == ["set", "security", "on"]
def test_off_reply_names_what_stays(adapter, setting):
    # adapter.write_note(setting) holds "nothing is uninstalled",
    # "mise bootstrap unapply security" and "mise bootstrap packages prune --dry-run"
def test_helper_failure_is_a_settings_error(adapter, setting):  # helper exits 2 -> SettingsError carrying its stderr
def test_allowed_on_an_installed_copy(adapter, setting):        # no refuse_installed: the state files are git-ignored
```

The note comes through the package's existing hook: `ModuleAdapter.write_note(s) -> str`, which `model.note_for` calls, as `ToolAdapter` does. In `bin/lib/test-modules`: the `key`s of the registry's `kind = "module"` rows equal `rotm-modules list`, in order.

- [ ] **Step 2: Run to see them fail**

Run: `cd settings && uv run --locked pytest tests/test_module.py -q`
Expected: FAIL, `adapters/module.py` does not exist.

- [ ] **Step 3: Implement**

The adapter, the `KINDS` and `ADAPTERS` entries, and the twelve registry rows. Each row's `help` says in one sentence what the module holds, from the "Modules" table, and ends "Turning it off uninstalls nothing." `package.py`'s two messages name the module files as well as `30-packages.toml`.

- [ ] **Step 4: Run to see them pass**

Run: `cd settings && uv run --locked pytest -q && cd .. && LC_ALL=en_US.UTF-8 bin/lib/test-modules`
Expected: all pass, then `ok`.

- [ ] **Step 5: Write `docs/modules.md` and fix the docs that changed**

`docs/modules.md` (not named after a command, so `help modules` reads it): the table of modules in a reader's words; all on by default; `rotm settings set modules.<name> off` and `on`; `--without` on the install line; what off does and does not do, with the two removal commands and the warning that `prune` is not limited to one module; skipping one package:

```toml
# ~/.config/mise/config.local.toml
[bootstrap.packages]
"brew-cask:warp" = { state = "absent" }

[settings]
disable_tools = ["npm:serverless"]
```

and that an absent package already installed is left in place. `README.md`: one line and a link. `docs/forking.md`: the `30-packages.toml` row now says a fork trims modules or turns them off. `docs/README.md`: the page in the index. `CLAUDE.md`, the rules and the `add-tool` skill: only sentences that became false, chiefly "formulae, casks and VS Code extensions (`30-packages.toml`)" and where a new package goes.

- [ ] **Step 6: Gate and commit**

Run: `pnpm check`
Expected: exit 0.

```bash
git add settings docs README.md setup/README.md CLAUDE.md .claude bin/lib/test-modules
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
| 2 | A fresh guest. The install line with all twelve names after `--without` | `setup.sh` exits 0 or 2 with only tolerated problems. A new terminal opens a prompt with no error. `git status` in a scratch repo, `rotm settings list` and `help rotm` all work. This is the proof that the base stands alone |
| 3 | On the row 1 guest: `rotm settings set modules.security on`, then `rotm update -y` | `nmap` is installed. The copy has no changed tracked file |
| 4 | Then `rotm settings set modules.apps off`, then `rotm update -y` | No app is removed. `setup.sh` reports no missing cask from the "GUI apps" list. `sysup` reports "all installed" for packages |
| 5 | Then add `"brew-cask:warp" = { state = "absent" }` to `~/.config/mise/config.local.toml` with `apps` on again, then `rotm update -y` | Warp is not installed, and is not listed as a problem |
| 6 | A fresh guest. The plain install line | The same package and tool counts as P1's row 3 and row 5: nothing missing for `brew`, `brew-cask`, `vscode`, and `mise ls --missing` is empty |

- [ ] **Step 3: Record and fix**

Add `#### Results` here: the date, the guest build, the mise version, the commit proven, one line per row. A failure is fixed on `main` and its row rerun from a fresh guest. A package that row 2 shows the base needs moves into the base, with its line in the Task 4 assertion.

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

In "Opt-outs": the install passes no module list, since the list is derived by `rotm-modules`, and replace the bullet that says the install command passes it with `-E`. In the P2 brief, replace "Settled by P0" with one "Shipped" line naming this plan. In "Plans", mark this file done. In the P4 brief's "Known", note that the `env` list is written by `rotm-modules sync`, which keeps non-module entries first, so a profile is such an entry.

- [ ] **Step 2: Promote and move**

Ask the owner before moving `stable`: Task 8 proved the install on `main`.

```bash
git mv docs/superpowers/plans/2026-11-12-p2-modules-and-opt-outs.md docs/superpowers/plans/completed/
git add -A docs/superpowers CLAUDE.md .claude/rules
git commit -m "Complete P2: modules and opt-outs"
git push
```

Then ask the owner to review before the owner's-layer plan is written.
