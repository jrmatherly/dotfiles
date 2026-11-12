# P2: Modules and Opt-outs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A person can decline any group of what returnofthemac installs, before the first install or after it, and can skip one single package, without editing a tracked file.

**Architecture:** Each group is a mise module: a `conf.d/60-rotm-<name>.toml` fragment, which mise always loads. A module is off when `ignored_config_paths` in `miserc.local.toml` names its file. One helper, `bin/lib/rotm-modules`, owns that line. It stores what the user turned off in `modules-off.local` and derives the line from it, so a Mac with no state loads every module and a module added later is on for everyone. `setup.sh`, `sysup` and `dotfiles-settings` all go through the helper. One package is skipped with mise's own `state = "absent"` in the machine-local `config.local.toml`.

**Design change, 2026-11-12, decided by the owner after Tasks 1 to 3 shipped:** the plan first selected modules with the `env` list (`config.rotm-<name>.toml`, on only when named). That fails off: a Mac with no list, or a shell with `MISE_ENV` set, loses every module. The ignore list fails on. Task 3b is the rework of the two shipped commits (`dfb3070`, `6d14c35`). Tasks 2 and 3 below describe the target, not what those commits hold.

**Tech Stack:** bash 3.2 (`#!/bin/bash`), mise 2026.11.5 or newer, Python 3.11+ with `tomllib` (the settings package and the self-checks), GitHub Actions, Renovate.

**Spec:** `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`. Read "Opt-outs", "Verified facts" and the P2 brief first. The owner split the brief on 2026-11-12: this plan is modules and opt-outs, and the owner's layer (the 13 values in `docs/forking.md`) is brief P2b, its own later plan.

## Global Constraints

- macOS only.
- mise floor: 2026.11.5 (`setup/mise-floor.sh`). Every measurement below ran on 2026.11.5.
- All modules are on by default. Nothing is forced: every group outside the base has a switch (decision 3).
- Turning a module off stops declaring it. It never removes a formula, a cask or a VS Code extension: the reply names `mise bootstrap packages prune --dry-run`, which lists what no config declares and is not limited to one module. mise tools are different: `sysup` already runs `mise prune --yes`, which deletes tool versions no config selects (`bin/sysup`, the "mise prune" step), so an off module's tools go at the next `sysup`. The docs and the reply say both.
- No tracked file is written by any switch. The state lives in `modules-off.local` and `miserc.local.toml` in the mise config dir, both git-ignored, so an installed copy stays fast-forwardable.
- The owner's Mac is a clone and `~/.config/mise` is a link into it, so an edit to a tracked mise config file is live on this Mac the moment it is saved. A Mac with nothing switched off loads every module, so Task 4 must leave what mise declares here unchanged. Task 4 Step 6 checks that, and nothing is written to the real home to make it so.
- `./setup.sh` from a clone with every module on must install exactly what it installs today: `bin/lib/test-bootstrap` passes with no existing assertion removed or loosened.
- Testing rule: a real install or update runs in the UTM guest `macOS`, started with "Run without saving changes", never on the owner's Mac. Self-checks with stubs and scratch homes run anywhere.
- Never run `./setup.sh`, `sysup`, `rotm install`, `rotm update` or `mise bootstrap` against the real home. Never edit `config.local.toml` or `config.override.toml`. One step touches the real home, with the owner's go-ahead: the read-only status calls in Task 4, before and after the move.
- Until Task 3b lands, the `sync` that `6d14c35` shipped writes `env = ["rotm-..."]` on every `setup.sh` and `sysup` run. That line is harmless while no `config.rotm-*.toml` exists, and Task 3b's `sync` removes its `rotm-` entries. Land Task 3b before Task 4.
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

Measured again on 2026-11-12 after Task 3, the same way (scratch home, mise 2026.11.5, `ls --json`, `packages status`, `config ls`, `doctor`), for the design change:

| Claim | Measured |
| --- | --- |
| With module files as `config.rotm-<name>.toml` and no `env` list, a Mac keeps its modules | No. Only the base loaded: the module's package and tool were both gone. This is a clone after a plain `git pull` |
| With the list saved, `MISE_ENV=development` or `mise -E production` in a shell keeps the modules | No. Each left only the base |
| A `conf.d` fragment with `[bootstrap.packages]`, a tap and `[tools]` loads with no state, and under `MISE_ENV` | Yes to both |
| `ignored_config_paths` in `miserc.local.toml` switches one fragment off | Yes: its package and its tool left `status` and `ls`, the other fragments stayed, and `mise doctor` listed the file under `ignored_config_files` |
| Which path form matches | A path relative to the miserc's own dir (`conf.d/60-rotm-security.toml`) matched through the `~/.config/mise` link, with `MISE_CONFIG_DIR` set to the real path, and from a project dir. An absolute path matched only the form mise itself used: the real path did not match through the link. A brace glob (`conf.d/60-rotm-{security,cloud}.toml`) matched both files |
| The same key under `[settings]` in `config.local.toml` works | No. It is read before config files load, as the docs say |
| `env = ["installed"]` and `ignored_config_paths` in one `miserc.local.toml` | Both honoured |
| A listed path whose file does not exist | Ignored, no warning |
| `state = "absent"` in `config.local.toml` still cancels a package a `conf.d` module declares | Yes |
| `mise -E <env> bootstrap --save-env` keeps an `ignored_config_paths` line already in `miserc.local.toml` | Yes. It rewrote only the `env` line: the ignore list, a comment and an unknown key all stayed. So running the install line again keeps what is switched off. It replaces the `env` list, it does not add to it |
| `MISE_IGNORED_CONFIG_PATHS` in a shell adds to the saved list | No. It replaced it: the saved module loaded again and only the variable's file was ignored. So `sync` warns when the variable is set |
| `ignored_config_paths = []` | Read without complaint, every fragment loaded |
| The same tool in `config.toml` and in a `conf.d` fragment | `config.toml` won. No module repeats a base key (Task 4 asserts it) |

Measured while building Task 3b, the same way, with fresh state dirs:

| Claim | Measured |
| --- | --- |
| `mise bootstrap` and `mise dotfiles status` run with a module file ignored | No, on a Mac with no trust record. Both exit 1 with "cannot read history configuration: ~/.config/mise/conf.d/60-rotm-fonts.toml" and "not trusted". The same with the config dir real or a link, with `MISE_TRUSTED_CONFIG_PATHS` set to it, and after a bootstrap that ran before the file was ignored. `bootstrap packages status`, `packages apply --dry-run`, `bootstrap status` and `bootstrap --only packages --dry-run` are not affected |
| What makes them pass | `mise trust <a module file>`, by the link path or the real one. The record it writes is for the home dir as a config root, not for the file: one record covered two ignored files, survived an edit to the file, and worked when written before the file was ignored. `mise trust` of the config dir or the repo root did not help. Nor did `trusted_config_paths` in `config.toml`, `config.local.toml`, a `conf.d` fragment, `miserc.toml` or `miserc.local.toml`. `MISE_TRUSTED_CONFIG_PATHS=$HOME` passes but trusts every project under home. `mise trust --ignore` refuses global config. The owner's Mac already has the home record, which is why the earlier `--save-env` row passed |
| What the home record lets through | A `~/mise.toml` loads without a prompt. A project config under home is still refused as untrusted |
| Which commands fail without it | `mise dotfiles status` and `apply`, and `mise bootstrap` when the dotfiles part or the final hook runs. On a terminal mise fails too, with no prompt. `ls`, `env`, `exec`, `hook-env`, `install --dry-run`, `prune --dry-run`, `tasks ls` and every `bootstrap packages` command pass. So `setup.sh`, `rotm update` and the install line are exposed, and shells and `sysup` are not |
| An ignored path whose file does not exist, and an empty list | Both pass |
| Fixed in a newer mise | No. `crates/mise-system/src/history/config.rs` is byte-identical at v2026.11.5, v2026.11.7 and `main` on 2026-11-12. Its `config_files()` lists every global config with no ignore filter, and `is_trusted_with` in `src/config/config_file/mod.rs` returns false for an ignored path before the global-config shortcut. No upstream issue was found |

**Decided by the owner, 2026-11-12:** `rotm-modules sync` runs `mise trust` on one off module's file when mise is on `PATH`, and `setup.sh` calls `sync` a second time after mise is installed. `test-modules` asserts `mise dotfiles status` passes with a module off, and pins the failure on a state dir with no record, so a fixed mise fails the check and the workaround is deleted. Still open: `rotm update` runs `mise bootstrap` before `sync`, so a Mac whose mise state dir was wiped fails that one run; `docs/installation.md`'s `MISE_CONFIG_DIR` preview is not measured with a module off; `fresh-install.yml` has no `--without` row.

Read from mise's docs that day, not measured: `ignored_config_paths` is an early-init setting, set in a `miserc.toml` file or `MISE_IGNORED_CONFIG_PATHS`, and `mise settings` refuses it. Commands that act on every tracked config honour only the variable and "the global and system `miserc.toml` files". From mise 2027.8.10 a `conf.d` filename may carry an environment segment (`env_conf_d`), so fragment names keep to one dot.

Not measured, and settled later in this plan:

- `state = "absent"` on a `vscode:` key (a plugin manager): Task 1.
- What `packages apply --manager <m>` exits with when a package declared absent is installed. `mise bootstrap packages apply --help` says that case "fails for it only when you pass `--manager` or name the package", and `setup.sh` passes `--manager`. Task 1 measures it for `vscode` with the fake `code`; a real cask needs a real install, which is VM row 5.
- That `mise prune` treats an off module's tools as unused, which also needs it to honour `miserc.local.toml`'s `ignored_config_paths` (see the docs note above). Read from `bin/sysup` and `mise prune --help`, not run: it needs installed tools. VM row 4 shows it.
- A real install with a module ignored: only `status`, `ls` and `doctor` were run. VM rows 1 and 2.

## Decisions this plan makes

- **Modules add, they do not subtract.** A module's packages move out of `conf.d/30-packages.toml` into its own file. The other shape, everything in the base plus an "off" file that declares each package absent, would keep two lists in step and make mise warn on every apply about installed packages declared absent.
- **The stored truth is the off list.** `modules-off.local` holds one module name per line. The `ignored_config_paths` line is derived from it. Nothing stores an on list, so a module that arrives in an update is on for every existing user.
- **A module is an always-loaded fragment, switched off with `ignored_config_paths`.** The file is `conf.d/60-rotm-<name>.toml` and the line holds `conf.d/60-rotm-<name>.toml`, relative to the miserc's dir, because only that form matched however mise reached the config dir (measured above). The `env` list was the first design and was dropped: it fails off, `MISE_ENV` replaces it, and a saved `env` name also selects `mise.<name>.toml` in every project. P1's `installed` environment still has that last exposure and is not renamed here: it is in the install line and in every installed copy's saved list. It is an open point for the owner. Modules never touch the `env` line, so P4's profiles own it alone.
- **The module names live in one place, `rotm-modules list`.** The settings registry has one row per module and a self-check keeps the two equal.
- **A module may have no packages.** `claude` and `agents` are mostly steps of `setup/misc.sh`. `is-on` is the same question for every module.
- **Dotfile entries stay in the base.** A link to the config of an app that is not installed is harmless, and moving entries would need a second `installed` variant of each.
- **The base keeps what the base runs.** A formula or tool stays in the base when `setup.sh`, `setup/*.sh`, `bin/rotm`, `bin/dotfiles-settings`, `bin/sysup`, `bin/vscode-settings`, a file under `zsh/`, `tilde/.zshrc`, `tilde/.zprofile`, `tilde/.zshenv` or `tilde/.gitconfig` uses it without a `command -v` or `command_exists` guard, or when a self-check says mise needs it. Known today: `uv` (runs `dotfiles-settings`), `ruby` (mise reads the `claude-multipass-app` tap cask with it), `jq`, `minijinja-cli`, and `git-lfs` (`tilde/.gitconfig` sets `filter.lfs.required = true`). These five move into the "Dotfiles framework requirements" section.
- **Declining before the first install is a `setup.sh` flag**, `--without <modules>`, because the install line is the only thing a stranger has typed by then.
- **One package is skipped with mise's own syntax**, documented, with no new command. The spec's "deny list" and "hook for user overrides" are not built: the measurement removed the need.
- **`mise bootstrap unapply` is not offered.** Per mise's docs it removes files, services and dotfile entries, and reports packages with guidance only. The modules hold packages and tools, so it would do nothing.

## Modules

`rotm-modules list` prints these twelve names in this order. The file for `<name>` is `tilde/.config/mise/conf.d/60-rotm-<name>.toml`, after `50-bootstrap.toml`.

| Module | What moves into it | Leans on |
| --- | --- | --- |
| `fonts` | The seven `font-*` casks. Gates the Iosevka step in `misc.sh` and `sysup` | |
| `apps` | The "GUI apps" section's casks. Gates `sysup`'s "Raycast" step. The language-server tools `config.toml` installs for Terax (`npm:typescript-language-server` through `npm:@vue/language-server`) and `npm:typescript`, which `misc.sh` links for them. Gates that link step | |
| `vscode` | Every `vscode:` key. The `visual-studio-code` cask stays in the base | |
| `claude` | The `bun` tool. Gates the Claude Code installer, `claude-config restore` and `claude-catalog` in `misc.sh`, and `sysup`'s "Claude Code", "agent skills", "plugins", "Claude config" and "catalog" steps | |
| `agents` | `brew:rtk`, `brew-cask:coderabbit`, `npm:@colbymchenry/codegraph`, `npm:rea-agents`. Gates the CodeGraph wiring, every `register_mcp` call, Serena, Scrapling, Hindsight, REA, SnippetsLab, the remote docs servers and `rtk init` | `claude` for the registrations. Hindsight's daemon needs `cargo`, from `rustup` in `devops`. REA also wants `ghidra` (`security`) and Hopper (`apps`), and already checks for them |
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
- `miserc.local.toml` already holds `env = ["installed"]`, or a profile name later, or the user's own `ignored_config_paths` entries: `sync` rewrites only the `ignored_config_paths` line, keeps every entry of it that is not `conf.d/60-rotm-*.toml` first and in order, and leaves every other line alone. Pinned in Task 2.
- Nothing is switched off: `sync` writes no file and no line, so a clone that never ran it and one that did read the same. Pinned in Task 2.
- A name in `modules-off.local` that is not a module (a typo, or a module removed upstream): `sync` ignores it and says so once, and never fails a setup run. Pinned in Task 2.
- A package is declared `absent` in `config.local.toml`: `setup.sh` ends without listing it as a problem, and `sysup` does not put it in a notice on every run. Pinned in Tasks 5 and 6.
- Every module off: `setup.sh` ends "All done", and a new shell, `git`, a clone of a repository that uses LFS, `rotm settings list` and `help` work. No self-check can prove this. Pinned in Task 8 (row 2).
- `MISE_ENV` is set in the shell: the modules still load, and an off module stays off. Pinned in Task 2's mise block.
- `MISE_IGNORED_CONFIG_PATHS` is set in the shell: mise uses it in place of the saved list, so an off module loads there. `sync` prints one warning naming the variable. Pinned in Task 2.
- A typo after `--without`: the run stops before the sudo prompt and before mise is installed. Pinned in Task 3.

---

## File Structure

- `bin/lib/rotm-modules`: the module names, the off list, and the `ignored_config_paths` line. The one place that knows them.
- `bin/lib/test-modules`: self-check for the helper and for the split, run by `bin/lib/check`.
- `tilde/.config/mise/conf.d/60-rotm-<module>.toml`: twelve files, one per row of the table.
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

- [x] **Step 5: Commit**

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
  - `rotm-modules sync [--without <a,b>]`: `--without` first adds those names to `modules-off.local` (exit 2 before writing anything when one is unknown). Then it sets the `ignored_config_paths` line of `miserc.local.toml` to the off modules' files. Prints `modules: off = [a, b]` when it changed the file and nothing when it did not. With nothing off and no such line it writes nothing. Exit 0.
- Every argument and every line of output uses short names (`fonts`). Only the `ignored_config_paths` line carries `conf.d/60-rotm-fonts.toml`.
- The config dir is `${MISE_CONFIG_DIR:-$HOME/.config/mise}`. Both files are written through it, so on a clone and on an installed copy they land in the checkout, git-ignored. The helper creates the dir's files, never the dir: a missing dir is exit 1 with its path.

- [x] **Step 1: Write the failing tests**

`bin/lib/test-modules`, with the header shape of `bin/lib/test-rotm`. `cfg` is one temp dir, `MISE_CONFIG_DIR` points at it, and the cases run in this order on that one dir. `reset` empties it. `MISE_ENV` and `MISE_IGNORED_CONFIG_PATHS` are unset. The file `dfb3070` shipped tests the first design; Task 3b rewrites it to this.

```bash
m=bin/lib/rotm-modules
[ "$("$m" list | tr '\n' ' ')" = "fonts apps vscode claude agents cloud kubernetes devops security network languages media " ] || fail "list"
line() { grep '^ignored_config_paths' "$cfg/miserc.local.toml"; }

# Nothing off: no file, no line, no output. This is every Mac that never ran sync
[ -z "$("$m" sync)" ] || fail "sync with nothing off printed something"
[ -z "$(ls -A "$cfg")" ] || fail "sync with nothing off wrote something"

# Off, and back on
"$m" set security off > "$tmp/out"
[ "$(cat "$cfg/miserc.local.toml")" = 'ignored_config_paths = ["conf.d/60-rotm-security.toml"]' ] || fail "set off on an empty dir"
grep -qx 'modules: off = \[security\]' "$tmp/out" || fail "set off did not say what is off"
[ -z "$("$m" sync)" ] || fail "a second sync printed something"
[ "$("$m" off)" = security ] || fail "off does not list it"
"$m" is-on fonts || fail "is-on fonts"
if "$m" is-on security; then fail "is-on security"; fi
"$m" set security on > /dev/null
[ "$(line)" = 'ignored_config_paths = []' ] || fail "set on left the module ignored"
[ -z "$("$m" off)" ] || fail "set on left the module in the off list"
rc=0; "$m" set security maybe 2> /dev/null || rc=$?; [ "$rc" = 2 ] || fail "set with a third word exited $rc"

# Only our entries of the one line change: env, other keys and the user's own ignores stay; a stale module entry goes
reset
printf 'env = ["installed"]\nignored_config_paths = ["/opt/mine.toml", "conf.d/60-rotm-gone.toml"]\nfoo = 1\n' > "$cfg/miserc.local.toml"
"$m" sync --without fonts,cloud > /dev/null
grep -qxF 'env = ["installed"]' "$cfg/miserc.local.toml" || fail "sync touched the env line"
# The first design's sync wrote rotm- entries into env: they go, the rest stays
sed -i '' 's/^env = .*/env = ["installed", "rotm-fonts", "rotm-media"]/' "$cfg/miserc.local.toml"
"$m" sync > /dev/null
grep -qxF 'env = ["installed"]' "$cfg/miserc.local.toml" || fail "sync left the first design's env entries"
grep -qx 'foo = 1' "$cfg/miserc.local.toml" || fail "sync dropped another key"
[ "$(line)" = 'ignored_config_paths = ["/opt/mine.toml", "conf.d/60-rotm-fonts.toml", "conf.d/60-rotm-cloud.toml"]' ] || fail "the user's entry was not kept first, or a stale one stayed"
[ "$("$m" off | tr '\n' ' ')" = "fonts cloud " ] || fail "--without"

# Unknown names
rc=0; "$m" is-on nope 2> /dev/null || rc=$?; [ "$rc" = 2 ] || fail "is-on with an unknown name exited $rc"
rc=0; "$m" sync --without media,nope 2> "$tmp/err" || rc=$?
[ "$rc" = 2 ] && grep -q nope "$tmp/err" && [ "$("$m" off | tr '\n' ' ')" = "fonts cloud " ] || fail "--without with an unknown name wrote something"
rc=0; "$m" sync --without 2> /dev/null || rc=$?; [ "$rc" = 2 ] || fail "--without with no names exited $rc"
echo typo >> "$cfg/modules-off.local"
"$m" sync 2> "$tmp/err" || fail "a stray name in modules-off.local failed sync"
grep -q 'typo' "$tmp/err" || fail "a stray name was not reported"

# A list on several lines, the variable that replaces the saved list, and no config dir
reset
printf 'ignored_config_paths = [\n  "/opt/mine.toml",\n]\n' > "$cfg/miserc.local.toml"
rc=0; "$m" set fonts off 2> "$tmp/err" || rc=$?; [ "$rc" = 1 ] && grep -q 'one line' "$tmp/err" || fail "a multi-line list was rewritten"
reset
MISE_IGNORED_CONFIG_PATHS=/x "$m" set fonts off 2> "$tmp/err" > /dev/null || fail "set with MISE_IGNORED_CONFIG_PATHS set"
grep -q 'MISE_IGNORED_CONFIG_PATHS' "$tmp/err" || fail "no warning that the variable replaces the saved list"
rc=0; MISE_CONFIG_DIR="$tmp/missing" "$m" set fonts off 2> /dev/null || rc=$?; [ "$rc" = 1 ] || fail "set created a config dir"
```

One more block, with a real `mise` on `PATH` and skipped with a message when it is missing, as `test-packages` does. `smise` runs mise from a scratch home with `MISE_CONFIG_DIR`, `MISE_DATA_DIR`, `MISE_STATE_DIR` and `MISE_CACHE_DIR` in `$tmp`, `MISE_CEILING_PATHS="$tmp"` and `MISE_SYSTEM_BREW_PREFIX` at an empty dir. The config dir holds a `conf.d/30-packages.toml` with `"brew:jq"` and a `conf.d/60-rotm-fonts.toml` with one font cask. Assert `smise bootstrap packages status --json` lists the cask with no state at all, lists it under `MISE_ENV=dev`, does not list it after `set fonts off` (also under `MISE_ENV=dev`, and with `MISE_CONFIG_DIR` unset and `~/.config/mise` a link to the dir), and lists it again after `set fonts on`.

- [x] **Step 2: Run to see it fail**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-modules`
Expected: FAIL at "list", because `bin/lib/rotm-modules` does not exist.

- [x] **Step 3: Write `bin/lib/rotm-modules`**

Header in the `bin/` shape, saying that it is called by path, that the off list is the stored truth, and why the paths are relative. `set -euo pipefail`. The names are one bash array. The `ignored_config_paths` line is rewritten in place when a line starting `ignored_config_paths = [` and ending `]` exists, appended when no line starts with that key and a module is off, and refused (exit 1, "the ignored_config_paths list in miserc.local.toml is not on one line") otherwise. Write through a temp file in the same dir and `mv`, so a failed run leaves the old file.

- [x] **Step 4: Run to see it pass, check the gate**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-modules && bash -n bin/lib/rotm-modules && shellcheck --severity=warning bin/lib/rotm-modules bin/lib/test-modules`
Expected: `ok`, then no output.

- [x] **Step 5: Commit**

```bash
git add bin/lib/rotm-modules bin/lib/test-modules bin/lib/check .gitignore
git commit -m "Add rotm-modules, which keeps mise's env list from what is switched off"
```

---

### Task 3: Every entry point syncs

**Files:**

- Modify: `setup.sh` (the `--without` flag, one `sync` call), `bin/sysup` (one `sync` call)
- Modify: `bin/lib/test-bootstrap`, `bin/lib/test-sysup`
- Modify: `setup/README.md`, `docs/installation.md`

**Interfaces:**

- Consumes: `rotm-modules is-on <name>` and `sync [--without <a,b>]` (Task 2).
- Produces: `./setup.sh --without <a,b>`, also reachable as `rotm install --without <a,b>` and `rotm update --without <a,b>`, since `rotm` passes its arguments to `setup.sh`. No Mac needs this task to have run before Task 4: with nothing off, `sync` writes nothing.

- [x] **Step 1: Make the fixture forget the list between runs**

`test-bootstrap`'s `run()` deletes `$tmp/home`, but `~/.config/mise` is a link into `$fix/tilde/.config/mise`, so the two state files would survive from one case to the next. Add to `run()`, beside its `rm -rf`: `rm -f "$fix/tilde/.config/mise/miserc.local.toml" "$fix/tilde/.config/mise/modules-off.local"`. Copy `bin/lib/rotm-modules` into the fixture where it copies `bin/lib/rotm-mode`.

- [x] **Step 2: Write the failing tests**

In `bin/lib/test-bootstrap`, after the existing cases. `in_order` reads the mise log, so the order is taken from the screen. The file `6d14c35` shipped asserts the first design; Task 3b rewrites it to this.

```bash
line_of() { grep -nF -- "$1" <<< "$out" | head -1 | cut -d: -f1; }
rc_file() { echo "$HOME/.config/mise/miserc.local.toml"; }

prepare() { :; }
run -y
check_true "setup with every module on writes no module state" [ ! -e "$(rc_file)" ]

run -y --without fonts,security
check_true "--without is stored" [ "$(tr '\n' ' ' < "$HOME/.config/mise/modules-off.local")" = "fonts security " ]
check_true "and mise is told to skip those files" grep -qxF 'ignored_config_paths = ["conf.d/60-rotm-fonts.toml", "conf.d/60-rotm-security.toml"]' "$(rc_file)"
check_true "the list is written before the dotfiles are applied" [ "$(line_of 'modules: off = ')" -lt "$(line_of 'Linking the dotfiles')" ]

run -y --without nope
check_true "an unknown module stops setup" [ "$rc" -eq 2 ]
check_true "and names it" has 'nope'
check_true "before any mise call" log_empty
check_true "and before the password prompt" [ ! -s "$STATE/sudo.log" ]
check_true "and before the warning" lacks 'WARNING'

run -y --without fonts -- --dry-run
check_true "a dry run writes no module state" [ ! -e "$(rc_file)" ]
check_true "and says so" has 'dry run: the module list is not written'
```

In `bin/lib/test-sysup`: the fixture's `$HOME/.config/mise` must exist (`mkdir -p` it where the fixture builds `$HOME`). After the first `run`: `check_true "sysup with nothing off writes no module state" [ ! -e "$HOME/.config/mise/miserc.local.toml" ]`. One more case with `cloud` in `$HOME/.config/mise/modules-off.local` and no miserc: after `run`, `check_true "sysup syncs the module list" grep -q '60-rotm-cloud' "$HOME/.config/mise/miserc.local.toml"`.

- [x] **Step 3: Run to see them fail**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-bootstrap; LC_ALL=en_US.UTF-8 bin/lib/test-sysup`
Expected: FAIL "setup with every module on writes no module state", and the `sysup` case.

- [x] **Step 4: Implement**

`setup.sh`:

- Parse `--without <list>` and `--without=<list>` with the other flags and add it to the usage header. Still inside flag parsing, check each name with `"$DOTFILES_DIR/bin/lib/rotm-modules" is-on <name>`: status 2 prints the helper's message and exits 2. This is before the warning banner, the sudo prompt and the mise install.
- Call `"$DOTFILES_DIR/bin/lib/rotm-modules" sync ${without:+--without "$without"}` right after the block that links `~/.config/mise` into the repo, which is before `setup/mise-floor.sh` and every mise call, so no mise call of the run loads a module that was just declined. Exit with the helper's status when it is not 0.
- In a dry run, skip the call and print "dry run: the module list is not written".

`bin/sysup`: one `"$(dirname "$0")/lib/rotm-modules" sync` call, by path as it calls `rotm-mode`, placed after the `dotfiles` step so a module that arrived in that pull is in the list for the same run. A non-zero status is `status fail modules "<the helper's last line>"` and the run goes on.

`rotm update --without nope` still fetches before `setup.sh` rejects the name. That is accepted: the fetch changes nothing the user chose.

- [x] **Step 5: Run to see them pass**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-bootstrap && LC_ALL=en_US.UTF-8 bin/lib/test-sysup`
Expected: `ok` twice.

- [x] **Step 6: Document and commit**

`setup/README.md`: the flag, and the step in the order list. `docs/installation.md`: one paragraph under the install line, "To leave groups out from the start, add `--without <names>` after `setup.sh`", pointing at `docs/modules.md` (written in Task 7).

```bash
git add setup.sh bin/sysup bin/lib/test-bootstrap bin/lib/test-sysup setup/README.md docs/installation.md
git commit -m "Sync the module list from setup and sysup, and take --without"
```

- **Step 7 is removed** by the design change: a Mac with nothing switched off needs no list.

---

### Task 3b: Rework the helper and its callers for the ignore list

**Files:**

- Modify: `bin/lib/rotm-modules`, `bin/lib/test-modules`, `bin/lib/test-bootstrap`, `bin/lib/test-sysup`
- Modify: `setup.sh` (one comment), `bin/sysup` (one comment), `bin/lib/check` (the comment beside `test-modules` names "mise's env line"), `setup/README.md`, `docs/installation.md`, `.gitignore` (comment only, if it names the `env` line)

**Interfaces:**

- Produces: the Task 2 and Task 3 interfaces as written above. `list`, `off`, `is-on`, `set` and `--without` keep their arguments and exit statuses, so `setup.sh` and `sysup` change only in comments.

- [x] **Step 1: Pin the two measurements this design rests on**

Both were measured by hand on 2026-11-12 (the second table above) and no self-check holds them yet. In the scratch `smise` block of `test-modules`, with `fonts` off in `miserc.local.toml` and a second fragment: `MISE_IGNORED_CONFIG_PATHS` naming the second makes the first load again (the variable replaces the list), and `smise -E installed bootstrap --save-env --only final-hook --yes` leaves the `ignored_config_paths` line as it was. A mise release that changes either then fails the check.

- [x] **Step 2: Rewrite the failing tests**

`test-modules` to the block in Task 2 Step 1, `test-bootstrap` and `test-sysup` to the block in Task 3 Step 2.

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-modules; LC_ALL=en_US.UTF-8 bin/lib/test-bootstrap; LC_ALL=en_US.UTF-8 bin/lib/test-sysup`
Expected: each FAILs on its first rewritten assertion.

- [x] **Step 3: Rework `sync`**

One line changes owner: `ignored_config_paths`, not `env`. The `rotm-` env prefix goes, and the warning names `MISE_IGNORED_CONFIG_PATHS`, not `MISE_ENV`. `sync` also drops any `"rotm-..."` entry from an `env` line, because a `setup.sh` or `sysup` run between `6d14c35` and this task wrote twelve of them. It removes the line when nothing else is in it.

- [x] **Step 4: Run to see them pass, fix the docs, commit**

Run: the three self-checks, then `shellcheck --severity=warning bin/lib/rotm-modules bin/lib/test-modules`.
Expected: `ok` three times, then no output.

`setup/README.md` and `docs/installation.md`: the step writes "the list of modules mise skips", and writes nothing when none is off.

```bash
git add bin/lib setup.sh bin/sysup setup/README.md docs/installation.md .gitignore docs/superpowers
git commit -m "Switch modules off with ignored_config_paths, so a Mac with no state loads them all"
```

---

### Task 4: Split the package list and the tools into modules

**Files:**

- Create: the twelve `tilde/.config/mise/conf.d/60-rotm-<module>.toml`
- Modify: `tilde/.config/mise/conf.d/30-packages.toml`, `tilde/.config/mise/config.toml`
- Modify: `bin/lib/test-packages`, `bin/lib/test-modules`
- Modify: `.github/workflows/check.yml`, `renovate.json`, and `.github/workflows/fresh-install.yml` (comments only, where they name the file)

**Interfaces:**

- Consumes: `rotm-modules list` (Task 2), reworked by Task 3b.
- Produces: the file layout in "Modules". Each module file starts with a comment naming the module, what turning it off leaves installed, and `rotm settings set modules.<name> off`.

- [x] **Step 1: Record what this Mac reports today**

Ask the owner first: these read this Mac's real state and change nothing.

Confirm first that `~/.config/mise/miserc.local.toml` holds no `ignored_config_paths` line and `modules-off.local` does not exist, so every module will load.

Run: `cd ~ && mise bootstrap packages status --json | jq -S '[to_entries[] | .key as $m | .value.packages[] | "\($m):\(.package)"] | sort' > /tmp/p2-before-packages.json; mise ls --global --json | jq -S keys > /tmp/p2-before-tools.json; jq length /tmp/p2-before-packages.json /tmp/p2-before-tools.json`
Expected: two files of sorted keys, and their two counts. Put the tool count in the Step 2 assertion. These are what is declared, not what is missing: a key dropped from every file would not show as missing. `mise ls --global` counts a tool a `conf.d` fragment declares (measured 2026-11-12 in a scratch home).

- [x] **Step 2: Rewrite the `test-packages` assertions to read every file**

The Python block loads `conf.d/30-packages.toml`, `config.toml` and each `conf.d/60-rotm-<name>.toml` for `name` in `rotm-modules list`, and asserts:

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
# files on disk and names in the helper agree, and a name has one dot (mise 2027.8.10 reads a second segment as an environment)
on_disk = {p.name for p in (config_dir / "conf.d").glob("60-rotm-*")}
assert on_disk == {f"60-rotm-{n}.toml" for n in modules}, on_disk
assert all(p.name.count(".") == 1 for p in (config_dir / "conf.d").iterdir()), "a conf.d name with two dots"
```

The completion-hook block reads `flux2` and `talosctl` from `conf.d/60-rotm-kubernetes.toml`.

- [x] **Step 3: Run to see it fail**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-packages`
Expected: FAIL "conf.d/30-packages.toml", at the first missing `60-rotm-*.toml`.

- [x] **Step 4: Move the entries**

`~/.config/mise` is this clone, so a half-moved state is live on this Mac while it exists, and this session's own MCP shims resolve against it. Write the fourteen files (the two that shrink and the twelve new) into a scratch dir with a throwaway script, run the Step 2 Python block against that dir (it takes the config dir as its argument), then copy them into place in one `cp`.

Follow the "Modules" table. Move lines, do not retype them: each entry keeps its comment and its order within its section. Section header comments go with their section. Every one of the twelve files exists, however short.

Before moving a formula or tool out of the base, apply the rule in "Decisions" to the files it lists. One that is used unguarded stays in the base, in the framework section, and is added to the base assertion in Step 2 in the same commit.

- [x] **Step 5: Add the "one module off" case to `test-modules`**

Not a copy of the whole tracked config dir: `config.toml` carries a `credential_command` that would run this Mac's real `gh`, the tools would be resolved from the network on every commit, and `test-modules` runs in the commit gate. Build the dir as `check.yml`'s dry run does: `conf.d/30-packages.toml` and every `conf.d/60-rotm-*.toml`, each with its `[tools]` table dropped. Status only, so nothing is fetched:

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

`30-packages.toml` says mise needs Ruby 3+ to read the `claude-multipass-app` tap cask, and `smise` has only macOS's 2.6 on `PATH`. If status fails for that reason, add the Ruby that `brew:ruby` installs to `smise`'s `PATH` and skip the block with a message when there is none, as the block skips without mise.

The spec's "Done when" for P2 is a dry run, which downloads formula metadata. It runs in CI, not in the commit gate: Step 7 adds it to `check.yml`.

- [x] **Step 6: Run to see both pass, and compare this Mac**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-packages && LC_ALL=en_US.UTF-8 bin/lib/test-modules`
Expected: `ok` twice.

Run: `cd ~ && mise bootstrap packages status --json | jq -S '[to_entries[] | .key as $m | .value.packages[] | "\($m):\(.package)"] | sort' | diff /tmp/p2-before-packages.json - && mise ls --global --json | jq -S keys | diff /tmp/p2-before-tools.json -`
Expected: no output. A difference means an entry was lost, doubled or renamed in the move. This is the proof that the move changed nothing on a Mac with no module state.

- [x] **Step 7: CI and Renovate see the module files**

`check.yml`, "Package list dry run": copy `conf.d/30-packages.toml` and every `conf.d/60-rotm-*.toml` into `$d/config/conf.d`. No list is written: they load as they are. Add a second dry run with one module off (`rotm-modules set security off` against `$d/config`), which fails when its output names `nmap`, `hydra` or `ghidra`: this is the spec's "Done when". The tools are still left out, for the reason the comment gives, so each copy drops its `[tools]` table: `awk '/^\[tools\]/{skip=1; next} /^\[/{skip=0} !skip'`. Say so in the comment.

`renovate.json`: three rules match the mise manager, and tools they cover move into module files. Read Renovate's mise manager page for its default file patterns. If `conf.d/*.toml` under `tilde/.config/mise/` is not among them, add a `mise` block with `managerFilePatterns` (or the key that page names) covering `tilde/.config/mise/config.toml` and `tilde/.config/mise/conf.d/60-rotm-*.toml`.

Run: `actionlint .github/workflows/check.yml && npx --yes --package renovate -- renovate-config-validator renovate.json`
Expected: no output from `actionlint`, and "Config validated successfully". If `npx` is denied here, validate the JSON with `jq . renovate.json > /dev/null` and say the Renovate check was not run.

- [x] **Step 8: Commit**

```bash
git add tilde/.config/mise bin/lib/test-packages bin/lib/test-modules .github/workflows renovate.json
git commit -m "Split the packages and tools into twelve modules"
```

**As built, 2026-11-12:** the snapshot was 365 packages and 27 tools, and Step 6's diff was empty. No formula or tool beyond the five known ones had to stay in the base: a scan of the files in "Decisions" found every other use behind `command_exists`, or in an alias. Step 5's block also drops the taps and their six packages from its copies, so it declares 170, not 176: with them mise clones each tap and needs Ruby 3+, which the commit gate should not depend on. `check.yml`'s dry run covers them, and its two runs were rehearsed locally in a scratch dir (613 lines with every module on, 593 and no `nmap`, `hydra` or `ghidra` with `security` off). Renovate's mise manager does not read `conf.d`, so `renovate.json` adds `tilde/.config/mise/conf.d/60-rotm-*.toml`. Comments that named both files were split between the modules and reworded; every entry line moved byte for byte.

---

### Task 5: Gates in `misc.sh`, and an absent package is not a problem

**Files:**

- Modify: `setup/misc.sh`, `setup.sh` (`packages_for`), `setup/dotfiles-extras.sh` (SSH signing without 1Password)
- Modify: `bin/lib/test-bootstrap`

**Interfaces:**

- Consumes: `rotm-modules is-on <name>` (Task 2).
- Produces: in `misc.sh`, `module_on <name>`, true when the module is on, and for an off module one line per gated step: `skipped: the <name> module is off`.

- [x] **Step 1: Make `misc.sh` runnable under stubs**

No self-check runs `setup/misc.sh` today: `test-bootstrap` only greps it. It also puts `/opt/homebrew/bin` first on `PATH` and names `/opt/homebrew/opt/rustup` and `/opt/homebrew/opt/ghidra` directly, so under a test it would run this Mac's real `uv`, `rtk`, `gh` and `claude`. Change those three places to `${HOMEBREW_PREFIX:-/opt/homebrew}`, as `setup.sh` does. In `test-bootstrap`, add the guard it already has for `setup.sh`:

```bash
! grep -q '/opt/homebrew' <(grep -v 'HOMEBREW_PREFIX:-/opt/homebrew' "$repo/setup/misc.sh" | grep -v '^ *#') \
  || fail "setup/misc.sh names /opt/homebrew without HOMEBREW_PREFIX; not running it"
```

- [x] **Step 2: Build the harness, every module on**

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

- [x] **Step 3: Write the failing tests**

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

- [x] **Step 4: Run to see them fail**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-bootstrap`
Expected: FAIL "modules off: no install-iosevka-code".

- [x] **Step 5: Implement**

`setup/dotfiles-extras.sh` writes `gpg.ssh.program = /Applications/1Password.app/Contents/MacOS/op-ssh-sign` with `commit.gpgSign` and `tag.gpgSign` when the user picks SSH signing, and the `1password` cask is in `apps`. With `apps` off and no 1Password, every commit and tag would then fail. When the method is `ssh` and that program is not executable, warn and write the identity with no signing lines, as the `none` choice does. Add the file to this task's commit and one case to the self-check that covers it (find it with `grep -l dotfiles-extras bin/lib/test-*`; a grep assertion in `test-bootstrap` if none runs it). The other answer, keeping the cask in the base, would force 1Password on everyone, against decision 3. It is the owner's to overrule.

`misc.sh`: `module_on() { "$DOTFILES_DIR/bin/lib/rotm-modules" is-on "$1"; }`, and wrap the steps the "Modules" table names for `fonts`, `apps`, `claude` and `agents`. The existing `command_exists` guards stay inside the gate. Steps for other modules need no gate: each already checks for its tool (`rustup`, `dotnet`, `aspire`, `supabase`).

`setup.sh` `packages_for`: when the manager's apply fails, nothing for that manager is in state `missing` afterwards, and at least one of its packages is in state `unexpectedly_installed`, it is not a problem. The decision reads states from `status --json`, not mise's wording. Any other failure stays a problem. mise 2026.11.7 added a `skipped` state for a key no manager can install; every key here carries a manager, so it is not handled, and a package in it stays a problem.

- [x] **Step 6: Run to see them pass, then commit**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-bootstrap`
Expected: `ok`.

```bash
git add setup/misc.sh setup/dotfiles-extras.sh setup.sh bin/lib/test-bootstrap
git commit -m "Skip the Claude, agent, app and font steps of a module that is off"
```

**As built, 2026-11-12:** the harness keeps its stubs in `$tmp/mbin`, not `$tmp/bin`, because a logging `curl` or `jq` there would break the `setup.sh` cases. The `agents` steps share one flag set once, so the module prints one `skipped` line, not one per step. The code was written before the tests were seen to fail, so two mutations stood in for Step 4: `module_on` always true failed "modules off: no install-iosevka-code", and the `unexpectedly_installed` branch disabled failed "an installed package declared absent is not a problem". The signing guard also clears the key and skips the key prompt. `setup/tests/dotfiles-extras.sh` runs the script (the plan's `grep -l dotfiles-extras bin/lib/test-*` missed it, and CI caught it: its SSH case failed on a runner with no 1Password). The helper path now follows `DOTFILES_EXTRAS_APPS`, and that self-check covers both cases.

---

### Task 6: `sysup` honours the modules

**Files:**

- Modify: `bin/sysup`, `bin/lib/test-sysup`, `bin/lib/test-packages` (the `upgrade` measurement)
- Modify: `.claude/rules/sysup.md` where a stated fact became false

**Interfaces:**

- Consumes: `rotm-modules is-on <name>` and `off` (Task 2), called as `"$(dirname "$0")/lib/rotm-modules"`.

- [x] **Step 1: Write the failing tests**

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

- [x] **Step 2: Run to see them fail**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-sysup`
Expected: FAIL "Iosevka is left out".

- [x] **Step 3: Implement**

- Each named step reports `status ok "<step>" "the <name> module is off"` and does nothing else when its module is off: `Iosevka` on `fonts`; `Claude Code`, `agent skills`, `plugins`, `Claude config`, `catalog` on `claude`; `REA skill`, `Hindsight memory`, `SnippetsLab skill`, `mise MCP`, `Scrapling` on `agents`; `Raycast` on `apps`, since that step opens the app with no check that it is installed. `agent skills` goes with `claude` because `claude-config restore` in `misc.sh`, which installs those skills, is gated on `claude`.
- "packages status": a package in state `absent` or `unexpectedly_installed` is not `not_installed`.
- "packages": `sysup` runs `mise bootstrap packages upgrade --yes`, and what that exits with when an installed package is declared absent is not measured. Measure it first in `test-packages`' `cfg3` block, as Task 1 measured `apply`, and pin it. If it fails, the step reads the states as `setup.sh`'s `packages_for` does, so the run does not report "upgrade failed" every time.
- "packages prune": when its notice fires and `rotm-modules off` prints anything, the notice ends "(modules off: a, b)", so the count is explained.

- [x] **Step 4: Run to see them pass, then commit**

Run: `LC_ALL=en_US.UTF-8 bin/lib/test-sysup`
Expected: `ok`.

```bash
git add bin/sysup bin/lib/test-sysup bin/lib/test-packages .claude/rules/sysup.md
git commit -m "Leave an off module's steps out of sysup"
```

**As built, 2026-11-12:** `mise bootstrap packages upgrade --yes` exits 0 with an installed extension declared absent (mise 2026.11.5, the fake `code`, `test-packages` pins it), so the "packages" step reads no states. That is measured for `vscode` only, whose plugin upgrades nothing: a real cask is VM row 5. `module_off <module> <step>…` in `sysup` asks first and gives each step its line, so a step that is also conditional (`rea`, the Hindsight config, the SnippetsLab app, `scrapling`) prints the off line whether or not its tool is there. The Claude and agents steps still sit inside `command -v claude`, so a Mac with no `claude` prints none of them, as before. The tests were seen to fail before the code ("Iosevka is left out"), and two mutations failed the other two: the old state filter failed "a package declared absent is not a notice", and the notice without its suffix failed "the prune notice names them". No fact in `.claude/rules/sysup.md` became false, so it is unchanged; `docs/updating.md` gained the paragraph. Found, and fixed in the commit after Task 7: the macOS step reused the name `installed` for the labels it installed, so on an installed copy with a macOS update listed the later `[ "$installed" = true ]` tests were false and `claude-config save` ran.

---

### Task 7: The switches in `dotfiles-settings`, and the docs

**Files:**

- Create: `settings/src/dotfiles_settings/adapters/module.py`, `settings/tests/test_module.py`, `docs/modules.md`
- Modify: `bin/dotfiles-settings` (`export DOTFILES`), `settings/src/dotfiles_settings/adapters/__init__.py`, `settings/src/dotfiles_settings/registry.py` (`KINDS`), `settings/registry.toml`, `settings/src/dotfiles_settings/adapters/package.py` (the two read-only messages), `settings/README.md`
- Modify: `bin/lib/test-modules`, `bin/vscode-settings` (its font warning names `30-packages.toml`), `README.md`, `docs/README.md`, `docs/forking.md`, `setup/README.md`, `CLAUDE.md`, `bin/CLAUDE.md`, `.claude/rules/*.md`, `.claude/agents/docs-auditor.md` and `.claude/skills/add-tool/SKILL.md` where they name `30-packages.toml` as the one package file

**Interfaces:**

- Consumes: `rotm-modules list`, `off`, `set <name> on|off` (Task 2).
- Produces: twelve settings `modules.<name>`, `kind = "module"`, `key = "<name>"`, `type = "bool"`, `true_value = "on"`, `default = "on"`, `access = "rw"`, `section = "Modules"`. `ModuleAdapter` with `read`, `write`, `reset` and `write_note` in the shape of the other adapters. It runs `$DOTFILES/bin/lib/rotm-modules` the way `adapters/tool.py`'s `run` runs a `bin/` script, and raises `SettingsError("DOTFILES is not set")` when the variable is missing. `bin/dotfiles-settings` must export `DOTFILES` (Step 3 adds it).

- [x] **Step 1: Write the failing tests**

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

- [x] **Step 2: Run to see them fail**

Run: `cd settings && uv run --locked pytest tests/test_module.py -q`
Expected: FAIL, `adapters/module.py` does not exist.

- [x] **Step 3: Implement**

The adapter, the `KINDS` and `ADAPTERS` entries, and the twelve registry rows. Each row's `help` says in one sentence what the module holds, from the "Modules" table, and names the module it leans on where the table gives one. `package.py`'s two messages name the module files as well as `30-packages.toml`. Its `summarize` counts every state but `installed` as drift, and its `apply` passes `--manager`: a package in state `absent` or `unexpectedly_installed` is neither drift nor a failed apply, by the rule `setup.sh` uses (Task 5), with a test for each in the package adapter's tests. `bin/dotfiles-settings` assigns `DOTFILES` without exporting it, so the Python side sees it only when the caller's shell exported it: add `export DOTFILES`. The registry's `packages.formulae` and `packages.tools` help texts name `30-packages.toml` and `config.toml` as the only files; they name the module files too.

- [x] **Step 4: Run to see them pass**

Run: `cd settings && uv run --locked pytest -q && cd .. && LC_ALL=en_US.UTF-8 bin/lib/test-modules`
Expected: all pass, then `ok`.

- [x] **Step 5: Write `docs/modules.md` and fix the docs that changed**

`docs/modules.md` (not named after a command, so `help modules` reads it): the table of modules in a reader's words, with the "leans on" column; all on by default; `rotm settings set modules.<name> off` and `on`; `--without` on the install line; what off does, in three plain sentences (nothing more is installed for it; formulae, casks and extensions stay until `mise bootstrap packages prune`, which is not limited to one module, so read its dry run first; its mise tools are removed by the next `sysup`); that `sysup` will keep mentioning the undeclared packages; skipping one thing:

```toml
# ~/.config/mise/config.local.toml
[bootstrap.packages]
"brew-cask:warp" = { state = "absent" }

[settings]
disable_tools = ["npm:serverless"]
```

and that an absent package already installed is left in place. One line for people who work on the repo: `pnpm check` and the commit hook need `pnpm` (`languages`), `shellcheck` and `actionlint` (`devops`) and `rtk` (`agents`). For `vscode:` keys, say what Task 1 measured.

`README.md`: one line and a link. `docs/forking.md`: the `30-packages.toml` row now says a fork trims modules or turns them off. `docs/README.md`: the page in the index. The instruction files: only sentences that became false, chiefly "formulae, casks and VS Code extensions (`30-packages.toml`)" and where a new package goes. The `add-tool` skill gains the question "which module". `.claude/rules/ci.md` lists `config.toml` in its `paths:` and not the module files: add `tilde/.config/mise/conf.d/60-rotm-*.toml`, and correct its sentence about the dry run.

- [x] **Step 6: Gate and commit**

Run: `pnpm check`
Expected: exit 0.

```bash
git add settings docs README.md setup/README.md CLAUDE.md bin/CLAUDE.md bin/vscode-settings bin/dotfiles-settings .claude bin/lib/test-modules
git commit -m "Add a switch per module to the settings, and document opting out"
```

**As built, 2026-11-12:** the settings tests are plain scripts, not pytest (the project has no pytest), so `test_module.py` asserts at module level, prints `ok`, and is listed in `settings_tests` in `bin/lib/check`; Steps 2 and 4 ran it as `python3 settings/tests/test_module.py`. It failed before the adapter existed (`KeyError: 'module'`), and `test-modules`' registry assertion failed before the rows did. A failed `rotm-modules off` makes a row unset rather than an error, as the plugin stack row does, so one bad call does not stop `list`; a failed `set` is a `SettingsError` with the helper's message. The adapter also watches `modules-off.local`. `package.py`'s apply succeeds when mise stops only at an installed package declared absent, by `setup.sh`'s rule, and `summarize` counts neither absent state. The plan's line for people who work on the repo was partly false: no module or base file declares `shellcheck` (CI installs it), and `bin/lib/check` and `test-conventions` skip `actionlint` and `rtk` when they are missing, so `docs/modules.md` says that. The docs that named `30-packages.toml` for a package that moved (the 1Password, Raycast, Warp and OrbStack pages, `docs/privacy.md`, `docs/mole.md`, the fonts, VS Code and Syntax Highlight READMEs, the tips page, `.claude/rules/vscode.md`, `bin/CLAUDE.md`'s `cwebp`) now name its module; `.claude/agents/docs-auditor.md` already lists `conf.d/*.toml` and is unchanged, as is `ci.md`'s dry-run sentence, which Task 4 made true. Set and reset were run through `bin/dotfiles-settings` against a scratch `MISE_CONFIG_DIR`, and the terminal UI was mounted with the real rows (twelve switches, all on). Not run: a switch on a real home, and that `rotm update` installs a module switched back on (VM row 3).

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
| 1 | The install line with `--without security,cloud,kubernetes,vscode` after `setup.sh` | "All done" or only tolerated problems. `mise bootstrap packages status --json` lists no `nmap`, no `awscli`, no `helm` and no `vscode:` key. `modules-off.local` holds the four names, `miserc.local.toml` holds `env = ["installed"]` and four `ignored_config_paths` entries, and `mise doctor` lists the four files. `MISE_ENV=dev mise ls` still lists `bun` (a module's tool survives `MISE_ENV`) |
| 2 | A fresh guest. The install line with all twelve names after `--without` | `setup.sh` exits 0 or 2 with only tolerated problems. A new terminal opens a prompt with no error. `git status` and a `git commit` in a scratch repo (answer the signing question with SSH, to show the guard from Task 5), `git clone` of a public repository that uses LFS, `rotm settings list` and `help rotm` all work. This is the proof that the base stands alone |
| 3 | On the row 1 guest: `rotm settings set modules.security on`, then `rotm update -y` | `nmap` is installed. The copy has no changed tracked file |
| 4 | Then `rotm settings set modules.kubernetes on`, `rotm update -y`, `rotm settings set modules.kubernetes off`, then `sysup` | `helm` is still installed. `sysup` reports "all installed" for packages, a prune notice ending "(modules off: ...)", and its "mise prune" step lists `flux2` or `talosctl` as removed. Record which tools went |
| 5 | With `apps` on and Warp installed, add `"brew-cask:warp" = { state = "absent" }` to `~/.config/mise/config.local.toml`, then `rotm update -y`, then `sysup` | Warp is still in `/Applications`. Neither run lists it as a problem or a notice. Record the exit status and text of `mise bootstrap packages apply --yes --manager brew-cask` |
| 6 | A fresh guest. The plain install line | The same package and tool counts as P1's row 3 and row 5: nothing missing for `brew`, `brew-cask`, `vscode`, and `mise ls --missing` is empty. `miserc.local.toml` holds no `ignored_config_paths` line |

- [ ] **Step 3: Record and fix**

Add `#### Results` here: the date, the guest build, the mise version, the commit proven, one line per row. A failure is fixed on `main` and its row rerun from a fresh guest. A package that row 2 shows the base needs moves into the base, with its line in the Task 4 assertion. If row 4 shows `mise prune` leaves an off module's tools alone, which is what happens if it does not honour `miserc.local.toml`, correct the Global Constraint, the adapter's note and `docs/modules.md`.

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

In "Opt-outs": the bullets were rewritten for the ignore list on 2026-11-12; check them against what shipped, and replace the one that offers `unapply`. In the P2 brief, replace "Settled" with one "Shipped" line naming this plan. In "Plans", mark this file done. In the P4 brief's "Known", note that modules never touch the `env` line of `miserc.local.toml`, so a profile owns it alone, beside `installed`. Move the rows Task 8 measured into "Verified facts".

- [ ] **Step 2: Promote and move**

Ask the owner before moving `stable`: Task 8 proved the install on `main`.

```bash
git mv docs/superpowers/plans/2026-11-12-p2-modules-and-opt-outs.md docs/superpowers/plans/completed/
git add -A docs/superpowers CLAUDE.md .claude/rules
git commit -m "Complete P2: modules and opt-outs"
git push
```

Then ask the owner to review before the owner's-layer plan is written.
