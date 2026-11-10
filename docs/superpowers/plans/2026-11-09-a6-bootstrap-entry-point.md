# A6 Bootstrap Entry Point Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new Mac goes from `git clone` to a finished setup with `./setup.sh`, which installs mise, links the repo's mise config, installs the packages and runs `mise bootstrap`. It never applies macOS preferences. Those stay with `set-defaults`.

**Architecture:** `setup.sh` shrinks to a wrapper. It checks the Command Line Tools, links `~/dotfiles` and `~/.config/mise` into the clone, installs mise when missing, holds sudo, applies the packages one manager at a time (a failed package warns and the run goes on, and with `-- --upgrade` each manager is upgraded right after its apply), runs `mise bootstrap --skip macos-defaults,packages` from `$HOME`, and then runs `setup/dotfiles-extras.sh`. `conf.d/50-bootstrap.toml` declares Touch ID for sudo, the login shell, a `pre-packages` hook for a bare `mise bootstrap`, a `pre-tools` hook that drops sudo, and one `[tasks.bootstrap]` that runs `setup/misc.sh`. `setup/misc.sh` keeps every step no declarative section covers. `sysup` gains a prune report.

**Tech Stack:** bash 3.2 (`/bin/bash`), mise 2026.11.5, TOML, the repo's stub-based self-checks.

**Spec:** `docs/superpowers/specs/2026-11-09-mise-first-setup-and-settings-ui.md`, phase "A6. Bootstrap entry point". Read it first.

## Global Constraints

- Minimum mise version: 2026.11.5. Setup fails with a clear message below it.
- The new method is Homebrew-free. Setup, `sysup` and shell startup never call `brew`.
- Part A never reads the old layout and carries no compatibility code for it.
- Every task and hook is safe to repeat. A bootstrap run is not a transaction. Hooks and the `bootstrap` task run every time.
- A closed stdin means "skip", never abort or overwrite.
- Bash scripts start with `#!/bin/bash` and a header comment, define their output helpers inline, and pass `pnpm check`.
- Commit subjects are short, imperative, sentence case, with no conventional-commit prefix.
- Every phase updates the docs that describe what it changed, in the same commit (D12).
- Never run `./setup.sh`, `mise bootstrap` without `--dry-run`, or `sysup` yourself. Tasks 5 and 6 are the only places the real thing runs (this Mac, then a VM), and the user runs both. Until A7 adds the `ask` rule `Bash(mise bootstrap*)` (spec decision 7), nothing in `.claude/settings.json` stops an agent from running `mise bootstrap`. This rule and the owner's go-ahead in chat are the guard.
- Tests that isolate mise set `HOME` and `MISE_CONFIG_DIR` only. Never set `MISE_GLOBAL_CONFIG_FILE`.
- Line numbers in this plan are from commit `9af6244`. An earlier phase may have moved them, so find each quoted sentence with `grep -n` before editing it.
- A commit names its paths. No `git add -A`, no `git add .`, no bare directory. The working tree holds an unrelated change to `agents/claude-settings.json` that must stay out of every commit.
- The phase is done when `pnpm check` and `bin/lib/test-bootstrap` pass and Task 6's VM results are recorded in this plan. `mise bootstrap status --missing` is informational. `setup.sh` never applies macOS preferences, and apps rewrite their own, so that command can list `macos-defaults` entries and exit 1 on a healthy Mac.

## Review Focus

1. A Mac that already has its own `~/.config/mise` (a real directory, or a link elsewhere). Expected: `setup.sh` stops before it installs or changes anything and prints the `mv` command. Pinned by `test-bootstrap` case c.
2. `mise bootstrap` started inside the clone. Measured: the repo's `.nvmrc` (`lts/*`) adds `node@26` to the tools part. Expected: `setup.sh` always runs mise from `$HOME`. Pinned by `test-bootstrap` case a (`pwd=`).
3. A mise older than 2026.11.5 already on PATH. Expected: A1's message naming the floor and the found version, and no bootstrap. Pinned by case e.
4. A run without a terminal (CI, an agent shell). Expected: no `sudo -v` prompt, no Enter prompt, no `script` log, and the run still reaches `mise bootstrap`. Pinned by case a (`sudo.log` has no `-v`).
5. Packages on the Mac that no config declares. Expected: `sysup` names the count and the review command, and removes nothing. Pinned by the `only_dry_runs` assertion in Task 3.
6. A rerun of `./setup.sh` on a configured Mac. Expected: no macOS preference is written and no app is quit. Pinned by case a (`--skip macos-defaults,packages`) and case b3 (`--only` is refused).
7. One cask fails to install on a new Mac. Expected: a warning, and the run still links the dotfiles, sets the login shell and installs the tools. Pinned by case f2.
8. `mise dotfiles apply` started from the settings UI. Expected: no sudo prompt, because `setup/dotfiles-extras.sh` is not a hook. Pinned by the static check that `50-bootstrap.toml` has no `post-dotfiles` line.
9. `./setup.sh -- --upgrade` (spec decision 11). Expected: each package manager is applied, then upgraded, a failed upgrade only warns, and mise's own `--upgrade` still reaches the tools part. A plain rerun never upgrades a package, and `-- --skip packages --upgrade` upgrades tools only. Pinned by cases a (no `packages upgrade` line), b2, b4 (`--dry-run` reaches each upgrade), b6 and f3.

---

## Decisions

**Entry point: a thin `setup.sh`, not `--from` or `--adopt`.** Measured in a scratch `HOME` with mise 2026.11.5:

- `mise bootstrap --adopt <url> --dry-run` prints `Would run: git clone <url> ~/.config/mise`. It clones the whole repository into the config directory. A subdirectory cannot be the config directory. Ruled out.
- `mise bootstrap --from <origin> --from-dir <clone> --config-dir tilde/.config/mise --dry-run` accepts a checkout made by hand and lists every part. It has two faults here. It loads the checkout root as a project, so `.nvmrc` added `node@26.13.0 ⇢ would install` to the tools part. It fails without an `origin` remote (`exists but is not a git checkout with an origin remote`) and when the origin differs from the URL passed. Ruled out.
- A hand-made link `~/.config/mise -> <clone>/tilde/.config/mise` followed by `mise bootstrap --dry-run` from `$HOME` listed the same parts and no stray `node`. Chosen.
- `MISE_CONFIG_DIR=<clone>/tilde/.config/mise mise bootstrap --dry-run` previews a bare Mac without creating the link, and wrote nothing into the config directory. The self-check and the docs use it.

**One TOML task, one script.** `[tasks.bootstrap]` has a single `run` line that starts `setup/misc.sh`. A `run` array stops at the first failing entry, and `misc.sh` is built to warn and carry on, so the steps stay inside one script. The file keeps its name. About 45 comments and docs point at `setup/misc.sh`, and each stays true.

**Repo root in TOML is `${DOTFILES:-$HOME/dotfiles}`.** Measured: `{{ config_root }}` in a global `conf.d` fragment renders as `$HOME`, and `MISE_PROJECT_ROOT` in the task is `$HOME` too. A3's `post-defaults` hook already uses this form. `setup.sh` exports `DOTFILES` and creates `~/dotfiles` before mise runs, so both spellings resolve.

**No `[bootstrap.mise_shell_activate]`.** mise skips files that `[dotfiles]` covers, and `~/.zprofile` and `~/.zshrc` are links into the repo. The repo's own lines stay because they do what mise's block cannot. `zsh/init.zsh` puts shims first and delays full activation to the first prompt, so agent shells and Claude Desktop never pin a global node.

**Setup never applies macOS preferences.** A plain `mise bootstrap` includes the `macos-defaults` part, and A3's `pre-defaults` and `post-defaults` hooks quit System Settings, run the extras script and restart Finder, the Dock and other apps. Today `setup.sh` touches no preference, and rerunning it is the normal way to apply changes. So `setup.sh` always passes `--skip macos-defaults`. Measured in a scratch `HOME`: `mise bootstrap --dry-run --skip macos-defaults,packages` prints no defaults block, no packages block and none of the four hooks around them, and exits 0. `--only` cannot be combined with `--skip` (measured: `the argument '--only' cannot be used with '--skip'`). So `setup.sh` merges a user's `--skip` list into its own single `--skip` argument and refuses `--only` with a message that names the direct command. Refusing is the conservative choice: no flag of `setup.sh` can then reach the preferences.

**`setup.sh` applies the packages itself, before `mise bootstrap`.** mise stops at the first part that fails, and no flag makes it continue (`mise bootstrap --help` lists none). One failed cask would then skip the dotfiles, the login shell, the tools and the task, where the old `brew.sh` warned and went on. So `setup.sh` keeps what A4's `setup/packages.sh` did: `mise bootstrap packages apply --yes --manager brew`, then `brew-cask`, then `vscode` when `code` is on PATH, each followed by `|| warning`. Then it runs `mise bootstrap` with `packages` added to the skip list. Measured: the part names compose (`--skip macos-defaults,packages`), and `mise bootstrap packages apply --dry-run --yes --manager brew` runs on its own and prints no hook block, so `setup.sh` links the vscode plugin itself first. The `pre-packages` hook stays for a bare `mise bootstrap`, which does run the `packages` part and does stop on a failure. With `code` missing, `setup.sh` skips the vscode manager and says so. Under a bare `mise bootstrap` the manager reports `available: false` and every extension `skipped`, exit 0 (measured by the reviewer of A4). Either way the extensions install on the next run.

**`-- --upgrade` upgrades packages too (spec decision 11), and only then.** mise's `--upgrade` upgrades packages only in the `packages` part ("runs the equivalent of `mise bootstrap packages upgrade` after installing", `mise bootstrap --help`), and `setup.sh` skips that part. So when `--upgrade` is among the arguments after `--`, `setup.sh` runs `mise bootstrap packages upgrade --yes --manager <m>` right after each manager's apply, with its own `|| warning`, and still passes `--upgrade` to `mise bootstrap` for the tools part. `packages apply` has no upgrade flag (`mise bootstrap packages apply --help` lists `--manager`, `--dry-run`, `--yes`, `--update`), so a run without `--upgrade` stays install-only. Measured in a scratch `HOME` with temp `MISE_CONFIG_DIR`, `MISE_DATA_DIR`, `MISE_STATE_DIR`, `MISE_CACHE_DIR` and an empty `MISE_SYSTEM_BREW_PREFIX`, a config of `brew:jq` and `brew-cask:firefox`: `packages upgrade --dry-run --yes --manager brew` (and `brew-cask`) on packages not yet installed prints `mise WARN  brew: 1 package(s) not installed — run mise bootstrap packages apply first` and exits 0, so apply comes first and a package the apply failed on does not fail the upgrade. `--manager vscode` with no plugin linked exits 1 with `no packages requested for manager 'vscode'`, which is why the vscode upgrade runs under the same `code` guard and after the same plugin link as its apply. `mise bootstrap --dry-run --upgrade --only packages` printed the install lines, then `mise bootstrap: upgrading packages`, exit 0: the per-manager form does what the part does, with the warning instead of a stop. `--dry-run` reaches each upgrade call. A user `--skip packages` skips the upgrades with the applies, so `-- --skip packages --upgrade` upgrades tools only. Neither form updates mise itself, macOS or the agent tooling: that stays `sysup`, the command that upgrades everything.

**GitHub token for tap resolution.** `setup.sh` exports `MISE_GITHUB_TOKEN` from `gh auth token` when the variable is unset and `gh` is signed in. Otherwise it prints one warning. The export comes before the package step, so it covers the upgrade calls too. A run over the five remaining taps uses about 20 of the 60 anonymous API calls an hour (measured in A4), so one run works without a token and several runs within an hour can hit the limit. An `--upgrade` run refreshes metadata again ("Refreshes package manager metadata, then upgrades", `packages upgrade --help`), so it uses more calls than an install-only run. How many is unmeasured: the scratch run above had nothing installed, so the upgrade skipped every package. Task 6 settles it on a VM (item 12 of its checklist).

**`setup/dotfiles-extras.sh` is not a hook.** mise runs `post-dotfiles` on every `mise dotfiles apply` too, including one started from the settings UI, where a sudo prompt cannot be answered. `setup.sh` runs the script after `mise bootstrap` returns 0, and not when the run is a `--dry-run` or skips `dotfiles`. The git identity prompt therefore runs from `setup.sh` in the user's terminal. Without a terminal the script takes its non-interactive path.

**Sudo.** `setup.sh` keeps `sudo -v` and the keep-alive loop, as one span. Every step that needs root (packages, files, the login shell) runs before `tools`. The `pre-tools` hook runs `sudo -k`, and `misc.sh` starts with `sudo -k` for runs that skip `tools`. That replaces the release and re-ask around `misc.sh`. `DOTFILES_SUDO_KEPT` goes. Without a terminal `setup.sh` skips `sudo -v`, and mise elevates per step. `setup/dotfiles-extras.sh` runs after the credential is dropped. It asks for sudo itself, in the terminal, and only when a `/usr/local/bin` link is missing (A5). That one prompt on a new Mac is acceptable. `setup.sh` runs `sudo -k` after it.

**Setup log stays.** `private/setup-logs/<timestamp>.log` through `script`, unchanged. mise keeps no run log, and `/validate-setup after` greps this one.

**Telemetry exports stay in `setup.sh`.** The `tools` part installs `npm:@colbymchenry/codegraph` and the package step installs casks such as `dotnet-sdk` and `azd`. Both run before the `bootstrap` task, so exports in `setup/misc.sh` would come too late. In `setup.sh` they reach mise and every child. `bin/lib/test-conventions`, `.claude/rules/telemetry-sync.md` and `docs/privacy.md:24` keep reading `setup.sh` and do not change.

**Flags.**

| Flag | After A6 |
| --- | --- |
| `-y`, `--yes` | Skips the Enter prompt and passes `--yes` to `mise bootstrap`. |
| `--skip-codegraph` | Exports `DOTFILES_SKIP_CODEGRAPH=true` and `MISE_DISABLE_TOOLS=npm:@colbymchenry/codegraph`. Measured: with the variable set, the tools part and `mise bootstrap status --missing` both leave the tool out. |
| `--dash` | Runs `setup/dash.sh` after a successful bootstrap. |
| `-h`, `--help` | Unchanged. |
| `--skip-brew` | Removed. It exits 1 and names the replacement, `./setup.sh -- --skip packages`. |
| `-- <args>` | New. Everything after `--` goes to `mise bootstrap`, with three exceptions. `--skip <parts>` (or `--skip=<parts>`, repeatable) is merged into the one `--skip macos-defaults,<parts>,packages`. When `<parts>` names `packages`, `setup.sh` skips its own package step too. `--only` exits 1. `--upgrade` stays in the mise arguments (tools) and also adds a `packages upgrade` after each manager's apply. `--dry-run` is also passed to the package step, upgrades included, and the plugin link and `setup/dotfiles-extras.sh` are left out. The two links and the mise install still happen. |

**`sysup` reports prune, it never prunes.** `mise bootstrap packages prune` removes every linked formula no config declares, including ones installed by hand. `sysup` runs it with `--dry-run` and prints a notice with the command.

## Inventory

Every action of the four scripts, 60 in all. "Task" means `setup/misc.sh` run by `[tasks.bootstrap]`.

**`setup.sh` (17)**

| # | Action (lines) | Goes to |
| --- | --- | --- |
| S1 | Resolve the clone, `cd` (19-22) | `setup.sh`. It also exports `DOTFILES` and runs mise from `$HOME`. |
| S2 | Ten telemetry exports (24-37) | `setup.sh`, unchanged. They must cover the package step and the `tools` part. |
| S3 | Flag parsing (39-63) | `setup.sh`, per the flag table. |
| S4 | `DOTFILES_SKIP_CODEGRAPH` default (42) | `setup.sh`, plus `MISE_DISABLE_TOOLS`. |
| S5 | Run log through `script` (65-76) | `setup.sh`, unchanged. |
| S6 | Colors, `title`, `warning` (78-97) | `setup.sh`, unchanged. |
| S7 | ASCII banner, warning, Enter prompt (99-126) | Banner art deleted. The warning and the prompt stay, reworded for A5 (a conflict stops the run). |
| S8 | `~/dotfiles` link (128-141) | `setup.sh`. It must exist before mise runs, because `[dotfiles]` sources, hooks and the task resolve the repo through it. A wrong `~/dotfiles` now stops the run instead of warning. |
| S9 | Touch ID `sudo_local` (143-147) | `[bootstrap.files]`. |
| S10 | `sudo -v`, keep-alive, `DOTFILES_SUDO_KEPT` (149-180) | `setup.sh` keeps `sudo -v` and the loop. `DOTFILES_SUDO_KEPT` deleted. |
| S11 | Release sudo around `misc.sh` (198) | `pre-tools` hook and the first line of `misc.sh`. |
| S12 | `brew.sh` (182-189), which A4 replaced with `setup/packages.sh` | `setup.sh`. The script, its test `setup/tests/packages.sh` and the `bin/lib/check` line that runs the test are deleted. Its mise installer, `MISE_GITHUB_TOKEN` export, `mise plugins link` and per-manager apply with a warning move into `setup.sh`. |
| S13 | `zsh.sh` (191-194) | `[bootstrap.user]`. |
| S14 | `misc.sh` (196-201) | `[tasks.bootstrap]`. |
| S15 | Re-ask sudo, `symlinks.sh` (203-212), which A5 replaced with `mise dotfiles apply --yes` and `setup/dotfiles-extras.sh` | The `dotfiles` part. `setup.sh` runs `setup/dotfiles-extras.sh` after `mise bootstrap` returns 0. The re-ask is deleted, and the script asks for sudo itself when a `/usr/local/bin` link is missing. |
| S16 | `dash.sh` with `--dash` (214-219) | `setup.sh`, after bootstrap. |
| S17 | "All done", `nyan` (221-224) | `setup.sh`. |

**`setup/zsh.sh` (6), file deleted**

| # | Action (lines) | Goes to |
| --- | --- | --- |
| Z1 | `brew shellenv` (11-14) | Deleted. |
| Z2 | Guarded `tput`, helpers (16-30) | Deleted. |
| Z3 | Exit when the shell is already zsh (32-38) | `[bootstrap.user]`. mise reports `already set`. |
| Z4 | Own sudo prompt (40-45) | Deleted. mise elevates. |
| Z5 | Append to `/etc/shells` (47-53) | `[bootstrap.user]`. |
| Z6 | `chsh -s` (55-59) | `[bootstrap.user]`. |

**`setup/dash.sh` (1)**

| # | Action | Goes to |
| --- | --- | --- |
| D1 | Interactive Dash docset entries, whole file | Unchanged. It is optional and interactive, so it stays out of the task. |

**`setup/misc.sh` (36)**

| # | Action (lines) | Goes to |
| --- | --- | --- |
| M1 | Resolve the clone, `cd` (5-6) | Task. Falls back to `$DOTFILES`. |
| M2 | `brew shellenv` (8-11) | Replaced by `export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"`, unless A4 already left that line. |
| M3 | Guarded `tput`, `indent`, `info`, `warning`, `command_exists` (13-36) | Task. |
| M4 | `link_config_dir` (38-55) | Deleted. `setup.sh` links mise. A5's `[dotfiles]` links `gh` before the task runs. |
| M5 | Own sudo prompt (57-62) | Deleted. Replaced by `sudo -k`. |
| M6 | Command Line Tools install and 30 minute wait (64-80) | `setup.sh` precheck. It exits 1 with `xcode-select --install`. The wait is deleted, since the clone itself needed git. |
| M7 | `chmod +x` on `bin/` (82-88) | Task. |
| M8 | Iosevka Code font (90-95) | Task. |
| M9 | Render VS Code settings (97-111) | Task. |
| M10 | Offer `gh auth login` (113-133) | Task, without the `link_config_dir gh` call. |
| M11 | Link `~/.config/mise` (140-143) | `setup.sh`. |
| M12 | `mise install`, CodeGraph skip, reshim (144-153) | `tools` part. Only the reshim stays in the task (Task 1 Step 6). |
| M13 | Link the global TypeScript (154-165) | Task. |
| M14 | Put mise shims on PATH (166-172) | Task. |
| M15 | `rustup default stable` (177-188) | Task. |
| M16 | Forget a leftover mise rust install (189-199) | Part B, `setup` step. It is old-layout cleanup. |
| M17 | Warn about a foreign `~/.cargo/bin/rustup` (200-202) | Part B, `setup` step. |
| M18 | Claude Code native installer (205-214) | Task. |
| M19 | CodeGraph `install` and `telemetry off` (216-233) | Task. |
| M20 | `register_mcp` helper (235-272) | Task. |
| M21 | mise MCP server (274-280) | Task. |
| M22 | Serena install and registration (282-295) | Task. |
| M23 | Scrapling install, browser, registration (297-325) | Task. |
| M24 | Hindsight `init` (327-339) | Task. |
| M25 | REA skill (353-362) | Task. |
| M26 | REA MCP server (363-367) | Task, as A4 left it. |
| M27 | SnippetsLab skill, Claude Code and Codex servers (369-399) | Task. |
| M28 | Three remote docs MCP servers (401-424) | Task. |
| M29 | `rtk init` hook (426-436) | Task. |
| M30 | `supabase telemetry disable` (438-444) | Task. |
| M31 | PowerShell .NET tool (446-460) | Task. |
| M32 | `aspire certs trust` (462-477) | Task. |
| M33 | npm config, five settings (481-498) | Task. |
| M34 | `pnpm install` (503-510) | Task. |
| M35 | `claude-config restore` (522-525) | Task, still after M33. |
| M36 | `claude-catalog` (526-529) | Task, last. |

Totals for the 60 rows:

| Destination | Count | Rows |
| --- | --- | --- |
| Declarative section | 6 | S9 (`[bootstrap.files]`), S13, Z3, Z5, Z6 (`[bootstrap.user]`), M12 (`tools` part) |
| Hook | 1 | S11 |
| Task (`setup/misc.sh`) | 30 | S14, M1 to M3, M7 to M10, M13 to M15, M18 to M36 |
| `setup.sh` | 15 | S1 to S8, S10, S12, S15 to S17, M6, M11 |
| Unchanged script | 1 | D1 |
| Part B | 2 | M16, M17 |
| Deleted | 5 | Z1, Z2, Z4, M4, M5 |

## Interfaces from A1 to A5

- A1: `setup/mise-floor.sh` is the version check, called from `setup/misc.sh`. Task 1 moves the call to `setup.sh`. CI has `mise` 2026.11.5 and `uv` on PATH (`jdx/mise-action` with `install: false`), with no `~/.config/mise` link, so part two of `test-bootstrap` runs there.
- A3: `tilde/.config/mise/conf.d/20-macos.toml` declares `[bootstrap.hooks]` `pre-defaults` and `post-defaults`. Measured: hooks from two fragments combine, and both hooks run only when the `macos-defaults` part runs. A3 adds the `test-conventions` check that tracked `setup/*.sh` files are executable. A6 relies on it and does not add it. A3 adds no `ask` rule (spec decision 7): `Bash(mise bootstrap*)` lands in A7 Task 8, after this phase, so A6 neither adds nor checks for it.
- A4: `conf.d/30-packages.toml` declares `brew:zsh`. `setup/packages.sh` installs mise with `curl -fsSL https://mise.run | sh`, exports `MISE_GITHUB_TOKEN` from `gh auth token` or warns, links the vscode plugin and applies packages one manager at a time (the vscode manager only when `code` exists, a warning per failed manager, exit 0), behind the `--skip-brew` flag. `setup/tests/packages.sh` tests it and `bin/lib/check` runs that test. A6 moves those behaviours into `setup.sh` and deletes the script, the test and the check line. `setup/misc.sh` already has `export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"` in place of `brew shellenv`, so inventory row M2 is done. `sysup` already has `mise self-update`, `packages` (status JSON compared before and after) and `packages status` steps, and exports `GITHUB_TOKEN` from `gh auth token`. A4 adds no hooks. `.github/workflows/fresh-install.yml` is manual (`workflow_dispatch`) and has no inputs (A4 P8, spec decision 12). Its one job deletes the runner's Homebrew, asserts no `mise` is on PATH, runs `bash setup/packages.sh` as the path a new Mac takes, and then checks with `packages status --json` that every formula, cask and extension is installed. Decision 12 adds to A4's job the `df -h /` and bottle-cache readings at the start and after each package manager, and the `xcode-27` image with `macos-26` as the fallback. Because A4 is being revised for that decision, Task 2 Step 5 reads the committed workflow file rather than this summary. `.claude/rules/ci.md` describes the job with `setup/packages.sh` in it.
- A5: `conf.d/40-dotfiles.toml` links `tilde/` with sources written `~/dotfiles/...`, so `~/dotfiles` must exist before the `dotfiles` part. A real directory at `~/.config/mise` makes `mise dot apply` refuse. A5 defines no task and no hook. It creates `setup/dotfiles-extras.sh` (git identity prompt, the two `sudo ln -s` links into `/usr/local/bin`, Firefox hard links, `bat cache --build`), safe to repeat, which the old `setup.sh` calls after `mise dotfiles apply --yes`. Measured here: when two fragments both define `[tasks.bootstrap]`, the later file wins silently, so `test-bootstrap` asserts there is exactly one.

## File Structure

| File | Change |
| --- | --- |
| `tilde/.config/mise/conf.d/50-bootstrap.toml` | Create. |
| `setup.sh` | Rewrite as the wrapper. |
| `setup/misc.sh` | Trim to the task (inventory M rows). |
| `setup/zsh.sh`, `setup/packages.sh`, `setup/tests/packages.sh` | Delete. |
| `bin/lib/test-bootstrap` | Create. Stub-driven check of `setup.sh` and a dry-run parse of the real config. |
| `bin/lib/check`, `bin/lib/test-conventions` | Wire the new check, drop the lines that run the two deleted tests, repoint the `tput` loop. |
| `setup/tests/symlinks-backup.sh` | Delete. A5 left only its `link_config_dir` half, and `link_config_dir` goes (M4). |
| `bin/sysup`, `bin/lib/test-sysup` | A `packages prune` report step. |
| `.claude/skills/validate-setup/SKILL.md`, `snapshot.sh`, `.claude/rules/setup.md` | Rewrite for the new order. |
| Docs listed in Task 2 | Replace stale sentences. |
| `setup/bootstrap-runtime.archify.json`, `setup/bootstrap-runtime.svg` | Regenerate. |

---

### Task 1: Bootstrap config, task script and entry point

**Files:**
- Create: `tilde/.config/mise/conf.d/50-bootstrap.toml`, `bin/lib/test-bootstrap`
- Modify: `setup.sh`, `setup/misc.sh`, `bin/lib/check`, `bin/lib/test-conventions:90-94`
- Delete: `setup/zsh.sh`, `setup/packages.sh`, `setup/tests/packages.sh`, `setup/tests/symlinks-backup.sh`

**Interfaces:**
- Consumes: the A1 to A5 interfaces above.
- Produces: `./setup.sh [-y|--yes] [--skip-codegraph] [--dash] [-h|--help] [-- <mise bootstrap args>]`. It runs `mise bootstrap --skip macos-defaults[,<user parts>],packages`, never `--only`. With `--upgrade` after `--`, it also runs `mise bootstrap packages upgrade --yes --manager <m>` after each manager's apply. The environment mise and the task see: `DOTFILES`, `DOTFILES_SKIP_CODEGRAPH`, `MISE_DISABLE_TOOLS`, `MISE_GITHUB_TOKEN` when `gh` is signed in, and the ten telemetry opt-outs. Task 2 documents these. Task 5 runs them.

- [ ] **Step 1: Write `bin/lib/test-bootstrap`**

Header in the `bin/lib/test-sysup` style. Part one never touches the machine. `HOME`, `STATE`, a stub `bin` and a fixture clone `$fix` live under `mktemp -d`, and `PATH` is `"$tmp/bin:/usr/bin:/bin"`. The fixture holds copies of the real `setup.sh` and `setup/mise-floor.sh`, an empty `tilde/.config/mise/`, and three executable stubs: `setup/dotfiles-extras.sh` (appends `ran` to `$STATE/extras.log`), `setup/dash.sh` and `bin/nyan` (both `exit 0`). A fixture is needed because `setup.sh` finds its helper scripts next to itself, and the real extras script must not run in a test. Stubs on PATH:

```bash
stub mise 'case $1 in
  --version) echo "${STUB_MISE_VERSION:-2026.11.5} macos-arm64 (2026-11-08)" ;;
  *) echo "pwd=$(pwd -P) args=$* disable=${MISE_DISABLE_TOOLS:-} dotfiles=${DOTFILES:-} skip=${DOTFILES_SKIP_CODEGRAPH:-} token=${MISE_GITHUB_TOKEN:-} telemetry=${CODEGRAPH_TELEMETRY:-}" >> "$STATE/mise.log"
    case "$*" in
      "bootstrap packages upgrade "*) [ ! -e "$STATE/upgrade-fails" ] ;;
      *"--manager brew-cask"*) [ ! -e "$STATE/casks-fail" ] ;;
      "bootstrap packages "* | plugins*) ;;
      bootstrap*) [ ! -e "$STATE/bootstrap-fails" ] ;;
    esac ;;
esac'
stub sudo 'echo "$*" >> "$STATE/sudo.log"'
stub xcode-select '[ ! -e "$STATE/no-clt" ]'
stub curl 'echo "$*" >> "$STATE/curl.log"; echo "mkdir -p \"\$HOME/.local/bin\" && cp \"$STATE/mise-stub\" \"\$HOME/.local/bin/mise\""'
```

Case i adds a `gh` stub (`auth token` prints `tok`). Cases b2 and f2 add a `code` stub (`exit 0`). No other case has them. Each case starts from an empty `HOME` and `STATE`, runs `"$fix/setup.sh" <args> < /dev/null` and asserts with `check_true`, as `test-sysup` does. "The bootstrap line" is the one `mise.log` line whose `args=` starts with `bootstrap --` or is exactly `bootstrap`.

| Case | Setup | Assertions |
| --- | --- | --- |
| a | empty `HOME` | exit 0. `~/.config/mise` and `~/dotfiles` are links whose `-ef` targets are `$fix/tilde/.config/mise` and `$fix`. `mise.log` has, in order, `args=plugins link --force vscode <fix>/mise-plugins/vscode`, `args=bootstrap packages apply --yes --manager brew`, `args=bootstrap packages apply --yes --manager brew-cask`, then the bootstrap line `pwd=<HOME> args=bootstrap --skip macos-defaults,packages disable= dotfiles=<fix> skip= token= telemetry=0`. Every line has `pwd=<HOME>`. No line has `packages upgrade`. No line has `--manager vscode`, and the output says extensions are skipped until VS Code is installed. The output has the rate-limit warning. `extras.log` has one line. `sudo.log` has no `-v` line. |
| b | `-y --skip-codegraph -- --skip packages` | `args=bootstrap --yes --skip macos-defaults,packages disable=npm:@colbymchenry/codegraph` and `skip=true`. `mise.log` has no `packages apply` and no `plugins link` line. |
| b2 | `-- --skip tools --skip=files --upgrade`, `code` stub | The bootstrap line has `args=bootstrap --skip macos-defaults,tools,files,packages --upgrade`. `mise.log` has, in order, `args=bootstrap packages apply --yes --manager brew`, `args=bootstrap packages upgrade --yes --manager brew`, the same pair for `brew-cask`, then the same pair for `vscode`, all before the bootstrap line. |
| b3 | `-- --only tools` | exit 1. Output matches `--only` and `mise bootstrap --only`. `mise.log` gained no line. |
| b4 | `-- --dry-run --upgrade` | The two `packages apply` lines and the two `packages upgrade` lines end in `--dry-run`. The bootstrap line has `--skip macos-defaults,packages --dry-run --upgrade`. No `plugins link` line. `extras.log` is empty. |
| b5 | `-- --skip dotfiles` | exit 0. The bootstrap line has `--skip macos-defaults,dotfiles,packages`. `extras.log` is empty. |
| b6 | `-- --skip packages --upgrade` | exit 0. `mise.log` has no `packages apply`, no `packages upgrade` and no `plugins link` line. The bootstrap line has `--skip macos-defaults,packages --upgrade`. |
| c | `mkdir -p ~/.config/mise` with a file in it | exit 1. Output matches `is not a link to`. `mise.log` gained no line. |
| c2 | `~/dotfiles` is a link to another directory | exit 1. Output matches `~/dotfiles is not a link to`. `mise.log` gained no line. |
| d | no `mise` stub on PATH, `mise-stub` in `STATE` | exit 0. `curl.log` has `https://mise.run`. `mise.log` has the bootstrap line. |
| e | `STUB_MISE_VERSION=2026.10.1` | exit 1. Output matches `mise 2026\.11\.5 or newer is required, found 2026\.10\.1`. `mise.log` gained no line. |
| f | `touch $STATE/bootstrap-fails` | exit is non-zero. Output matches `rerun \./setup\.sh`. `extras.log` is empty. |
| f2 | `touch $STATE/casks-fail`, `code` stub | exit 0. Output has the casks warning. `mise.log` has the `--manager vscode` line and the bootstrap line after the failed one. `extras.log` has one line. |
| f3 | `-- --upgrade`, `touch $STATE/upgrade-fails` | exit 0. Output has `failed to upgrade`. `mise.log` has the `--manager brew-cask` apply after the failed brew upgrade, and the bootstrap line with `--upgrade`. `extras.log` has one line. |
| g | `--skip-brew` | exit 1. Output matches `-- --skip packages`. `--help` output lacks `skip-brew`. |
| h | `touch $STATE/no-clt` | exit 1. Output matches `xcode-select --install`. |
| i | `gh` stub | Every `mise.log` line has `token=tok`. The output has no rate-limit warning. A second run with `MISE_GITHUB_TOKEN=mine` in the environment has `token=mine`. |

Part two uses the real mise and is skipped with a stderr note when `command -v mise` finds nothing. It runs from a scratch `HOME` with `MISE_CONFIG_DIR="$repo/tilde/.config/mise"` and `DOTFILES="$repo"`:

```bash
out=$(mise bootstrap --dry-run --only files,user,task 2>&1) || fail "config does not load: $out"
grep -q 'mise bootstrap: system files' <<< "$out" || fail "no files part"
grep -q 'mise bootstrap: login shell' <<< "$out" || fail "no user part"
grep -qF 'mise bootstrap: running `bootstrap` task' <<< "$out" || fail "no bootstrap task"
grep -qF '/setup/misc.sh' <<< "$out" || fail "task does not run setup/misc.sh"
! grep -q 'unknown field' <<< "$out" || fail "mise warns about an unknown key"
mise bootstrap files status | grep '/etc/pam.d/sudo_local' | grep -q 'owner root group wheel' || fail "sudo_local not declared with its owner"
mise bootstrap user status | grep -q '^/opt/homebrew/bin/zsh' || fail "login shell not declared"
out=$(mise bootstrap --dry-run --skip macos-defaults,packages 2>&1) || fail "the skip list setup.sh passes does not parse: $out"
! grep -qE 'pre-defaults|post-defaults|pre-packages|system defaults|system packages' <<< "$out" || fail "a skipped part or its hook still runs"
```

Static checks close the file: exactly one `[tasks.bootstrap]` across `conf.d/*.toml`. `50-bootstrap.toml` has the lines `pre-tools = "sudo -k"` and `pre-packages = …`, and no `post-dotfiles` line (`setup/dotfiles-extras.sh` must not be a hook). In `setup/misc.sh`, `grep -nE '(^|[^a-z_])sudo ' | grep -v 'sudo -k'` is empty, and so are greps for `link_config_dir`, `mise install`, `brew shellenv` and `DOTFILES_SUDO_KEPT`. `setup.sh` has at least one `^export [A-Z_]*TELEMETRY` line, and `setup/misc.sh` has none.

- [ ] **Step 2: Run it to see it fail**

Run: `bash bin/lib/test-bootstrap`
Expected: `FAIL` on case a (the current `setup.sh` calls scripts the stubs do not cover) or on the missing `50-bootstrap.toml`.

- [ ] **Step 3: Create `tilde/.config/mise/conf.d/50-bootstrap.toml`** with exactly this content

```toml
# What `mise bootstrap` does beyond env, macOS defaults, packages and dotfiles
# (conf.d/10 to 40). setup.sh links this directory to ~/.config/mise, installs
# mise, applies the packages itself and runs
# `mise bootstrap --skip macos-defaults,packages` from $HOME.
# https://mise.jdx.dev/bootstrap.html

# Touch ID for sudo. /etc/pam.d/sudo includes sudo_local, and macOS updates
# leave the file alone. mise writes it through sudo, and only when the content,
# the mode or the owner differs. Owner and group are declared because mise
# does not check them when unset, and this file decides who may use sudo.
[bootstrap.files."/etc/pam.d/sudo_local"]
content = "auth       sufficient     pam_tid.so\n"
mode = "0644"
owner = "root"
group = "wheel"

# zsh from conf.d/30-packages.toml as the login shell. mise adds it to
# /etc/shells and runs chsh when the account's shell differs.
[bootstrap.user]
login_shell = "/opt/homebrew/bin/zsh"

# No [bootstrap.mise_shell_activate]: ~/.zprofile and ~/.zshrc are links into
# this repo, which mise skips, and zsh/init.zsh delays full activation to the
# first prompt on purpose.

[bootstrap.hooks]
# The VS Code extension manager is a plugin kept in this repo. Linking is safe
# to repeat (--force replaces the link). setup.sh skips the packages part and
# links the plugin itself, so this hook is for a bare `mise bootstrap`.
pre-packages = 'mise plugins link --force vscode "${DOTFILES:-$HOME/dotfiles}/mise-plugins/vscode"'
# No post-dotfiles hook: mise runs it on every `mise dotfiles apply` too, and
# setup/dotfiles-extras.sh may ask for sudo. setup.sh runs that script.
# Every part that needs root runs before `tools`. Drop the cached credential
# here, so npm install scripts and the task's installers cannot use sudo
# without asking.
pre-tools = "sudo -k"

# The steps no section above covers. It runs on every bootstrap, so each step
# in the script checks state first and warns instead of failing.
# {{ config_root }} is $HOME in a global fragment, hence the shell expansion.
[tasks.bootstrap]
description = "Finish setup: fonts, agent tooling, MCP servers, npm defaults"
raw = true
run = '"${DOTFILES:-$HOME/dotfiles}/setup/misc.sh"'
```

- [ ] **Step 4: Rewrite `setup.sh`**

Keep the header style and update the usage line to the Produces signature. Order of the body, with the lines that are decisions:

1. `set -euo pipefail`, then `DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd -P)"` and `export DOTFILES_DIR DOTFILES="$DOTFILES_DIR"`. Then the ten telemetry `export` lines with their comment, unchanged (lines 24-37).
2. Flags per the flag table. `--skip-brew` prints `--skip-brew is gone: use ./setup.sh -- --skip packages` to stderr and exits 1. Arguments after `--` are sorted into three places. `--skip <parts>` and `--skip=<parts>` append to `user_skip` (comma-joined). `--only` and `--only=*` print `--only cannot be combined with the --skip macos-defaults that setup always passes. Run it yourself: cd ~ && mise bootstrap --only <parts>` to stderr and exit 1. `--dry-run` and `-n` set `dry_run=true` and stay in `mise_args`. `--upgrade` sets `upgrade=true` and stays in `mise_args`, where it upgrades the tools part. Everything else collects in `mise_args`. Then:

   ```bash
   # macOS preferences are never part of setup (set-defaults owns them), and
   # --only cannot be combined with --skip, so there is one merged list.
   skip="macos-defaults${user_skip:+,$user_skip}"
   run_packages=true run_extras=true
   case ",$user_skip," in *,packages,*) run_packages=false ;; *) skip="$skip,packages" ;; esac
   case ",$user_skip," in *,dotfiles,*) run_extras=false ;; esac
   [ "$dry_run" = false ] || run_extras=false
   ```

3. The `script` re-exec block, unchanged (lines 65-76).
4. Colors, `title`, `warning`, unchanged, with one line added above the color block: `tput() { command tput "$@" 2> /dev/null || true; }`. The block calls `tput` six times and already runs only when `tput setaf 1` works, so `TERM` unset is safe today. The wrapper puts `setup.sh` under the same `test-conventions` check as the other scripts (Step 7).
5. `xcode-select -p > /dev/null 2>&1` or exit 1 with `Command Line Tools missing; run: xcode-select --install, then rerun ./setup.sh`.
6. The warning text and the Enter prompt. No banner art.
7. `link_into_repo <link> <target>`: creates the link when nothing is there, returns 0 when `<link> -ef <target>`, returns 1 otherwise. For `~/dotfiles` a failure exits 1 with `~/dotfiles is not a link to $DOTFILES_DIR. Move it aside and rerun ./setup.sh`, because every `[dotfiles]` source and every hook goes through that path (A5 added this guard, keep it). For `~/.config/mise` a failure exits 1 with `~/.config/mise is not a link to $DOTFILES_DIR/tilde/.config/mise. Move it aside (mv ~/.config/mise ~/.config/mise.backup) and rerun ./setup.sh`. Run `mkdir -p "$HOME/.config"` first.
8. mise. `export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"` first (A4's line, so a `code` or `gh` installed earlier in the same run is found). When `command -v mise` then finds nothing, run `curl -fsSL https://mise.run | sh`.
9. Version floor: `bash "$DOTFILES_DIR/setup/mise-floor.sh" || exit 1`. A1 created that script. It holds the floor (`floor=2026.11.5`), reads `mise --version` from PATH and prints `mise 2026.11.5 or newer is required, found <version>. Upgrade mise, then run setup again.` Do not write a second check. Remove A1's call from `setup/misc.sh`, since mise is already running when the task starts.
10. With `--skip-codegraph`: `export DOTFILES_SKIP_CODEGRAPH=true MISE_DISABLE_TOOLS="${MISE_DISABLE_TOOLS:+$MISE_DISABLE_TOOLS,}npm:@colbymchenry/codegraph"`.
11. When `[ -t 0 ]`: `sudo -v`, then `sudo_keepalive_start` (lines 152-160, unchanged). The `EXIT` trap runs `sudo_keepalive_stop` (lines 164-170, unchanged).
12. GitHub token. When `MISE_GITHUB_TOKEN` is unset and `gh auth token` succeeds, export `MISE_GITHUB_TOKEN` from it. When it is unset and `gh` is missing or signed out, print one `warning`: `No GitHub token: tap formulae use the anonymous API limit (60 calls an hour). If packages fail to resolve, run gh auth login and rerun ./setup.sh`.
13. `cd "$HOME"`. Every mise call below runs from here.
14. Packages, when `run_packages` is true. This is what `setup/packages.sh` did, plus the upgrade of spec decision 11. One helper, `packages_for <manager> <noun>`, does one manager. It runs `mise bootstrap packages apply --yes --manager "$1" ${dry_run_flag} || warning "Some $2 failed to install. See above, then rerun ./setup.sh"`. Then, when `upgrade` is true, `mise bootstrap packages upgrade --yes --manager "$1" ${dry_run_flag} || warning "Some $2 failed to upgrade. See above, then rerun ./setup.sh -- --upgrade"`. A failed package never stops the run. `dry_run_flag` is `--dry-run` or empty.
    - Unless `dry_run`: `mise plugins link --force vscode "$DOTFILES_DIR/mise-plugins/vscode"`.
    - `packages_for brew formulae`, then `packages_for brew-cask casks`. Formulae first: the cask step needs the `brew:ruby` the formula step installs (A4 P12).
    - When `command -v code` succeeds, `packages_for vscode extensions`. Otherwise print `VS Code is not installed yet: extensions are skipped. Rerun ./setup.sh once it is.`
15. `mise bootstrap ${yes:+--yes} --skip "$skip" ${mise_args[@]+"${mise_args[@]}"}`. On failure print `mise bootstrap stopped. Earlier steps stay applied. Fix what it reported, then rerun ./setup.sh` and exit with mise's status.
16. `sudo_keepalive_stop`. Then, when `run_extras` is true, `"$DOTFILES_DIR/setup/dotfiles-extras.sh"`, followed by `sudo -k 2> /dev/null || true`. The script asks for sudo itself, in the terminal, when a `/usr/local/bin` link is missing. A failure of the script fails the run with its status.
17. `--dash`, the closing line and `"$DOTFILES_DIR/bin/nyan"`.

- [ ] **Step 5: Trim `setup/misc.sh`** to the inventory's "Task" rows

- Add a header comment that says the script is the `bootstrap` task of `conf.d/50-bootstrap.toml`, runs on every `mise bootstrap`, and must never call sudo.
- After `set -euo pipefail`: `sudo -k 2> /dev/null || true`. No telemetry exports here. The task inherits them from `setup.sh`, and a bare `mise bootstrap` from a shell gets them from `zsh/env.zsh`.
- `DOTFILES_DIR="${DOTFILES_DIR:-${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd -P)}}"`.
- Apply rows M2, M4, M5, M6, M10, M11, M12, M16, M17 as the inventory says.

- [ ] **Step 6: Keep `--skip-codegraph` from dropping an installed shim**

Where M12 was, leave only this. The comment carries the reason from `misc.sh:144-147`.

```bash
# setup.sh --skip-codegraph sets MISE_DISABLE_TOOLS for the tools part. A
# reshim while it is set deletes an installed CodeGraph's shim, so reshim
# once more without it.
if [ "${DOTFILES_SKIP_CODEGRAPH:-false}" = true ] && command_exists mise; then
  env -u MISE_DISABLE_TOOLS mise reshim
fi
```

- [ ] **Step 7: Delete the replaced scripts and their tests, and repoint the convention checks**

Before deleting `setup/packages.sh`, read it against Step 4 items 8, 12 and 14. Those items carry its mise installer, token export, plugin link, per-manager apply with a warning, and the `code` guard. If A4 built anything else into it, move that to `setup.sh` too and add a `test-bootstrap` case for it.

```bash
git rm setup/zsh.sh setup/packages.sh setup/tests/packages.sh setup/tests/symlinks-backup.sh
```

In `bin/lib/check`, delete the two lines that run `setup/tests/packages.sh` and `setup/tests/symlinks-backup.sh`, each with its comment line. `grep -n 'setup/tests/' bin/lib/check` must then list only tests that exist.

In `bin/lib/test-conventions`, the `tput` loop (line 92 at `9af6244`, where it names `setup/brew.sh setup/zsh.sh setup/misc.sh`) names `setup.sh setup/misc.sh`. Then run `grep -l tput setup/*.sh`. `setup/dash.sh` guards each call inline (`|| true`) and stays out. Any other file it prints (`mise-floor.sh`, `macos-extras.sh` and `dotfiles-extras.sh` come from A1, A3 and A5) joins the loop, and gets the wrapper line if it lacks one. The telemetry check (line 34) and its header line (10) keep reading `setup.sh` and do not change.

This phase adds no `ask` rule and asserts none (spec decision 7). `Bash(mise bootstrap*)` lands in A7 Task 8, and its assertion with it. Do not check for it here: until A7 lands the rule is absent on purpose, and the owner's go-ahead in chat guards `mise bootstrap` (Global Constraints).

Run: `ls -l setup/*.sh | grep -v '^-rwxr-xr-x'`
Expected: no output. `setup.sh` runs `setup/dotfiles-extras.sh` directly, and mise runs `setup/misc.sh` directly, so both need mode 755 (A3's `test-conventions` check enforces it).

- [ ] **Step 8: Wire the check**

In `bin/lib/check`, after the `test-sysup` line:

```bash
# setup.sh in a fixture clone against stubbed mise, sudo, gh and curl, then a dry-run of the tracked bootstrap config in a scratch HOME
bash bin/lib/test-bootstrap > /dev/null
```

- [ ] **Step 9: Run the checks**

Run: `bash bin/lib/test-bootstrap && bash bin/lib/test-conventions`
Expected: every `ok:` line, then `conventions: all checks passed`.

Run: `cd ~ && MISE_CONFIG_DIR="$DOTFILES/tilde/.config/mise" mise bootstrap --dry-run --skip macos-defaults,packages`
Expected: exit 0, the headings `system files`, `login shell`, `pre-tools hooks` with `sh -o errexit -c 'sudo -k'`, `tools`, and the `bootstrap` task line. No `pre-defaults`, `post-defaults`, `pre-packages` or `post-dotfiles` block, and no `system defaults` or `system packages` heading. On this Mac the files and login shell lines say `already converged` and `already set to /opt/homebrew/bin/zsh`.

Task 1 is verified on its own by the two runs above. It is not committed on its own: the docs would still describe `--skip-brew`, `setup/zsh.sh` and the old order, and D12 puts a behaviour change and its docs in one commit. Task 2 ends with that commit.

### Task 2: Docs and agent instructions for the new entry point

**Files:**
- Modify: `.github/workflows/fresh-install.yml`, `.claude/rules/ci.md`, `README.md`, `setup/README.md`, `CLAUDE.md`, `.claude/rules/setup.md`, `.claude/skills/validate-setup/SKILL.md`, `.claude/skills/validate-setup/snapshot.sh`, `.claude/agents/docs-auditor.md`, `docs/README.md`, `docs/rea.md`, `bin/dotfiles`, `bin/sysup:210`, `.claude/skills/add-tool/SKILL.md`

**Interfaces:**
- Consumes: Task 1's signature and environment.
- Produces: nothing later tasks call.

Facts every edit must state where it applies: mise is installed first, by `setup.sh`, into `~/.local/bin`. `setup.sh` applies the packages, then wraps `mise bootstrap`. A failed package warns and the run goes on. A failed part of `mise bootstrap` stops it, earlier steps stay applied, and the fix is to rerun `./setup.sh`. Hooks and the `bootstrap` task run on every bootstrap. Setup never applies macOS preferences: `setup.sh` passes `--skip macos-defaults`, and `set-defaults` is the only way they are applied. A bare `mise bootstrap` does apply them, so the docs give `./setup.sh` as the rerun command, never a bare `mise bootstrap`.

- [ ] **Step 1: Replace the stale sentences**

| File:line | Stale text | Replace with |
| --- | --- | --- |
| `README.md:14` | "…from the Brewfile; `setup/zsh.sh` makes it your login shell" | mise makes it the login shell (`[bootstrap.user]`). |
| `README.md:53` | "`setup/misc.sh` offers `gh auth login` later" | Still true. Keep. |
| `README.md:61` | "install 1Password (`brew install --cask 1password`)", which A4 turned into "`mise bootstrap packages apply brew-cask:1password`, after `setup/packages.sh` has installed mise, or download it" | Download it. mise is not installed before `./setup.sh` runs, and `setup/packages.sh` is gone. Keep A5's "`setup/dotfiles-extras.sh` asks how to sign commits". |
| `README.md:67-80` | The "Manually" section and "`setup.sh` also does a few things the manual path skips…". A4 and A5 edited lines 73, 76 and 80 inside it (`./setup/packages.sh`, `mise dotfiles apply`, the sudo sentence). | Delete the section, those edits included. Replace with a short "Preview" section: `cd ~ && MISE_CONFIG_DIR=~/dev/dotfiles/tilde/.config/mise mise bootstrap --dry-run --skip macos-defaults`. Say that `./setup.sh` is the rerun, and that a bare `mise bootstrap` also applies the macOS preferences and restarts Finder and the Dock. |
| `README.md:93` | "This will install all required dotfiles in your home directory as symlinks." | Add the order: Command Line Tools check, the two links, mise, the packages, `mise bootstrap`, then `setup/dotfiles-extras.sh`. Add the rerun sentence, that a failed package only warns, and that macOS preferences are not applied (`set-defaults` does that). |
| `README.md:100` | "`--skip-brew` \| Skip `brew update` and the Brewfile install…" | Remove the row. Add a `-- <args>` row with `./setup.sh -- --skip packages` as the example. Say `--skip` lists are merged with `macos-defaults`, `--only` is refused (run `mise bootstrap --only <parts>` from `~` instead), and `-- --upgrade` upgrades packages and tools. |
| `README.md:105` | "If `/etc/pam.d/sudo_local` doesn't exist yet, it's created to enable Touch ID" | mise declares the file (content, mode, `root:wheel`) and rewrites it when any of them differs. |
| `README.md`, the paragraph on `gh` near line 53 | "`setup/misc.sh` offers `gh auth login` later" | Keep, and add what is true about the token: `setup.sh` passes `MISE_GITHUB_TOKEN` to mise when `gh` is signed in and warns when it is not. One run fits the anonymous limit (about 20 of 60 API calls an hour). Several runs within an hour can hit it. Do not write that `gh` must be signed in first. |
| `README.md:242` | `"$DOTFILES/setup.sh" --skip-brew # drop --skip-brew to also install new Brewfile entries` | `"$DOTFILES/setup.sh"`, with `-- --skip packages` to leave packages alone. |
| `README.md:245` | "`setup.sh` installs what's missing but doesn't upgrade… the dependencies `brew bundle` upgrades on its own…" | Drop the `brew bundle` clause. Add the two ways to upgrade and how they differ. `./setup.sh -- --upgrade` upgrades what the mise config declares: the packages, one manager at a time with a warning on failure, and the tools. `sysup` upgrades everything: macOS updates, mise itself, the packages, the tools and the agent tooling, and it reports packages no config declares. Take the `sysup` list from its `step` lines (`grep -n '^ *step ' bin/sysup`), not from this row. |
| `setup/README.md:9` | "`../setup.sh` runs these in order: **brew → zsh → misc → symlinks**…" | The order: packages (applied by `setup.sh`, one manager at a time, a failure warns), then mise's parts from `mise bootstrap --help` without the two that are skipped: files, dotfiles, login shell, tools, the `bootstrap` task. Then `setup/dotfiles-extras.sh`. The new flag list, with the `--skip` merge, the refused `--only`, and `-- --upgrade` (packages after each apply, then tools; `sysup` for everything, macOS and mise included). |
| `setup/README.md:11` | "After its `sudo -v` it exports `DOTFILES_SUDO_KEPT=1`… Sudo is held only around the steps that use it…", as A5 left it | One span of sudo. The `pre-tools` hook and `misc.sh` drop it. `setup/dotfiles-extras.sh` runs after that and asks itself when a `/usr/local/bin` link is missing (keep A5's sentence). The `~/.config/mise` link and its failure message. |
| `setup/README.md:15` | A3's sentence that macOS preferences are not part of the run | Still true. Add how: `setup.sh` passes `--skip macos-defaults`, which also drops the two hooks around that part. |
| `setup/README.md`, the "## packages" section A4 wrote | What `setup/packages.sh` does | Same facts with `setup.sh` as the subject: the mise installer, the token or the warning, the plugin link, one apply per manager with a warning on failure, extensions skipped until `code` exists, and with `-- --upgrade` a `packages upgrade` after each apply, also warning on failure. Add that a bare `mise bootstrap` runs the `packages` part without that tolerance and stops at the first failure. |
| `setup/README.md:35-37` | The `## zsh` section | Three sentences on `[bootstrap.user]`. |
| `setup/README.md:41` | "Run on its own, it asks for sudo first; under `setup.sh` (`DOTFILES_SUDO_KEPT=1`) it skips that prompt." | It is the `bootstrap` task, runs on every bootstrap, never uses sudo, and warns instead of failing. |
| `setup/README.md:43` | "Installs the Xcode Command Line Tools if missing… It waits at most 30 minutes…" | `setup.sh` checks for them and stops with the command. |
| `setup/README.md:47` | "The script links that config into `~/.config/mise` and runs `mise install` before touching npm. It links `~/.config/mise` (and `~/.config/gh`…)…" | `setup.sh` links it. The `tools` part installs. Keep the version list. |
| `setup/README.md:60` | "Rust lived in mise before 2026-10-24…" to the end of the bullet | Delete. Part B owns it. |
| `setup/README.md:62` | "Pass `--skip-codegraph` to `setup.sh` (or set `DOTFILES_SKIP_CODEGRAPH=true`) to skip CodeGraph's mise install and this step" | Say the flag also sets `MISE_DISABLE_TOOLS`, and that a bare `mise bootstrap` needs both variables. |
| `CLAUDE.md:27` | "`./setup.sh --skip-brew`: re-apply the dotfiles… drop `--skip-brew` to also install the Brewfile." | The whole bullet becomes: "- `./setup.sh`: links the mise config, installs mise and the packages, then runs `mise bootstrap` (never macOS preferences, which are `set-defaults`). It's interactive. Flags: `-y`, `--skip-codegraph`, `--dash`, `-h`, `-- <mise args>`. From a terminal it logs each run to `private/setup-logs/<timestamp>.log` (via `script`), which `/validate-setup after` reads." |
| `CLAUDE.md:39` | "setup.sh orchestrator → setup/{brew,zsh,misc,symlinks}.sh (+ dash.sh with --dash)", as A4 and A5 left it | "setup.sh wrapper → packages, mise bootstrap (conf.d/*.toml, task setup/misc.sh), dotfiles-extras.sh", with the column spacing of the lines around it. Line 40 names no script this plan deletes. Confirm and leave it. |
| `CLAUDE.md:52` | "**Setup order**: `brew.sh` must run first…a sudo keep-alive loop, and telemetry opt-out exports." | The whole bullet becomes: "- **Setup order**: mise is installed first and its part order is fixed. `setup.sh` installs packages itself first, so one failed package doesn't stop the run. What each step does is in `setup/README.md`; the constraints are in `.claude/rules/setup.md`." |
| `CLAUDE.md:87` | "telemetry opt-outs live in both `setup.sh` and `zsh/env.zsh`" | Still true. Keep. |
| `CLAUDE.md:89` | "Re-running `setup.sh` is the normal way to apply changes." | Keep, and append "A run is not a transaction: rerun after a failure." |
| `docs/README.md:152`, `bin/dotfiles:4`, `bin/sysup:210`, `docs/rea.md:48`, `.claude/skills/add-tool/SKILL.md:24` | "`setup.sh --skip-brew`" | "`setup.sh`". |
| `.claude/agents/docs-auditor.md:15` | "`tilde/.config/mise/config.toml`" in the repo-claims list | Add `tilde/.config/mise/conf.d/*.toml`. Add `mise bootstrap` to the forbidden list on line 16. |

`.claude/rules/telemetry-sync.md` and `docs/privacy.md:24` say `setup.sh` exports the opt-outs for the install run. That stays true. Do not edit them.

`.claude/skills/docs-audit/SKILL.md` and `.serena/memories/core.md` are in the spec's table. At `9af6244` neither names a script this plan deletes (`grep -n 'setup'` finds the README list in the first and "`setup.sh`, `setup/*.sh`" in the second). A4 edits `docs-audit` for the Brewfile, so run `grep -nE 'packages\.sh|zsh\.sh|skip-brew|Brewfile|brew\.sh' .claude/skills/docs-audit/SKILL.md .serena/memories/core.md` after Step 1. Expected: no output. Fix any hit in this commit.

**`CLAUDE.md` size.** The file is 10,829 bytes at `9af6244` and `test-conventions` caps it at 12,000. The four edits above replace 1,024 bytes with 1,018, a net change of -6 bytes against the `9af6244` text. A1 to A5 edit some of the same lines first, so measure instead of trusting that figure: run `wc -c CLAUDE.md` before and after this step and record both in the commit body. `CLAUDE.md` is Prettier-ignored. Edit it by hand.

- [ ] **Step 2: Replace `.claude/rules/setup.md` below its front matter**

```markdown
# Setup

- A closed stdin (non-interactive run) must mean "skip", never abort or overwrite.
- mise comes first. `setup.sh` links `~/dotfiles` and `~/.config/mise` into the clone, installs mise with its own installer when missing, checks the version floor and runs every mise command from `$HOME`. Started inside the clone, mise reads `.nvmrc` and adds a node to the tools part.
- Not `--from` or `--adopt`: `--adopt` clones a whole repo into `~/.config/mise`, and `--from` loads the checkout root as a project and needs a matching `origin` (measured on 2026.11.5).
- Setup never applies macOS preferences. `setup.sh` always passes `--skip macos-defaults`, which also drops the `pre-defaults` and `post-defaults` hooks. `--only` cannot be combined with `--skip`, so a user's `--skip` list is merged into that one argument and `--only` is refused. A bare `mise bootstrap` does apply them.
- `setup.sh` applies the packages itself, one manager at a time, and only warns on a failure, because mise stops at the first failed part. It then skips the `packages` part, so mise's `--upgrade` alone would upgrade only the tools: with `-- --upgrade`, `setup.sh` runs `mise bootstrap packages upgrade` after each manager's apply. A run without it never upgrades a package. `sysup` is the command that upgrades everything, macOS and mise included. The telemetry opt-outs are exported in `setup.sh` so they cover the package and tool installs.
- The order after that is mise's: files, dotfiles, login shell, tools, then the `bootstrap` task. Everything that needs root runs before `tools`. The `pre-tools` hook and the first line of `setup/misc.sh` run `sudo -k`, so nothing in `misc.sh` may call sudo (`test-bootstrap` asserts it).
- `setup/dotfiles-extras.sh` is never a hook. mise runs `post-dotfiles` on every `mise dotfiles apply`, including one from the settings UI, where a sudo prompt cannot be answered. `setup.sh` runs the script after `mise bootstrap` succeeds.
- A run is not a transaction: a failed part leaves the earlier ones applied, and the fix is to rerun `./setup.sh`. Hooks and the task run on every bootstrap, so each `misc.sh` step checks state first and warns instead of failing.
- Hooks run in mise's environment without `[tools]`; the task has them. In a global fragment `{{ config_root }}` is `$HOME`, so hooks and the task find the repo as `${DOTFILES:-$HOME/dotfiles}`.
- Only one fragment may define `[tasks.bootstrap]`: a second definition replaces the first without a warning.
- Order constraints in `misc.sh`: `claude-config restore` and the catalog run last so `npx skills` runs with the npm settings (`min-release-age`, `allow-git none`). After the tools part it links `<mise data dir>/node_modules/typescript` to the global `npm:typescript` (`sysup` relinks it). `chmod +x` skips `*.md` so `bin/CLAUDE.md` stays non-executable.
- `aspire certs trust` has no y/N prompt and macOS may ask for the password, so it is skipped when already trusted and only a hint when non-interactive.
- `--skip-codegraph` must leave an existing CodeGraph install untouched, including its mise shim: `setup.sh` sets `MISE_DISABLE_TOOLS` for the run and `misc.sh` reshims once without it.
- Every behavior change updates `setup/README.md` (and `README.md` for flags) in the same commit.
- A fresh install can't be verified on this machine. The `fresh-install` workflow runs `./setup.sh` on a hosted runner, which is not a clean Mac (Xcode is preinstalled, no first-launch prompts). The full proof is a run in a disposable macOS VM, checklist in the A6 plan's Task 6 (in `docs/superpowers/plans/completed/` once done). Say which of the two a change needs when it touches that path.
- Validate with `/validate-setup before`, then `./setup.sh` in a terminal (it is interactive), then `/validate-setup after`.
- `setup/bootstrap-runtime.svg` (embedded in `setup/README.md`) is generated by Archify from `setup/bootstrap-runtime.archify.json` (source line refs pinned to a commit). When step order, sudo use or download sources change, update the JSON, re-run `archify finalize` and re-export the SVG. Archify's per-run `.archify/` folder is gitignored; commit only the exported image.
```

Add `'tilde/.config/mise/conf.d/50-bootstrap.toml'` to its `paths:`.

- [ ] **Step 3: Replace `.claude/skills/validate-setup/SKILL.md`**

Keep the front matter keys. In `allowed-tools` add `Bash(mise bootstrap status*)` and `Bash(mise bootstrap --dry-run*)`. Change the description to "Snapshot the machine state `mise bootstrap` manages before and after `./setup.sh`, and diff the two, to verify a setup change." Body:

```markdown
Phase: $ARGUMENTS

- **before**: run `pnpm check` (stop and report if it fails), then `mkdir -p private/setup-snapshots` and `.claude/skills/validate-setup/snapshot.sh > private/setup-snapshots/before.txt`. Run `mise bootstrap --dry-run --skip macos-defaults` from `~` and say what it would change. Tell the user to run `./setup.sh` (add `--skip-codegraph` if CodeGraph is irrelevant, `-- --skip packages` to leave packages alone) **in their own terminal**, since it prompts, and then invoke `/validate-setup after`. They don't need to paste the output: setup.sh records each run to `private/setup-logs/<timestamp>.log`.
- **after**:
  1. Run `.claude/skills/validate-setup/snapshot.sh > private/setup-snapshots/after.txt`, then `diff -u private/setup-snapshots/before.txt private/setup-snapshots/after.txt`. Explain every changed line: expected from the change under test, or a regression. No diff means setup was a no-op. Say whether that was expected.
  2. Run `mise bootstrap status --missing` and name each entry that isn't converged. It is informational, and exit 1 is not a failure by itself: setup never applies macOS preferences and apps rewrite their own, so `macos-defaults` entries are expected there (`set-defaults` applies them). An entry of any other part is a part that failed, fixed by rerunning `./setup.sh`.
  3. Read the newest log (`ls -t private/setup-logs/*.log`, first entry) and `grep -inE 'error|warn|deprecat|fail|not found'` it. Explain each hit (expected, harmless upstream noise, or a problem), and confirm the step under test printed what it should.
- Anything else: explain the two phases and stop.

Never run `./setup.sh` or `mise bootstrap` without `--dry-run` yourself.
```

In `snapshot.sh` add one section before the login shell section:

```bash
echo "## mise bootstrap status"
mise bootstrap status 2>&1
```

- [ ] **Step 4: No ask rule for `mise bootstrap` in this phase**

Nothing to add to `.claude/settings.json`. Spec decision 7 puts every `ask` rule the plans add, `Bash(mise bootstrap*)` included, in A7 Task 8, which also adds the `test-conventions` assertion. The validate-setup skill's own `allowed-tools` (Step 3) are not permission rules in `.claude/settings.json` and stay in this phase.

- [ ] **Step 5: Point the fresh-install workflow at the entry point**

A4's one job runs `bash setup/packages.sh`, and Task 1 deleted that script, so the job must change in this commit. Read the committed file first (`git show HEAD:.github/workflows/fresh-install.yml`) and edit that, not the A4 plan's description: A4 is being revised for spec decision 12. Keep one job, the runner choice A4 made (the `xcode-27` image first, `macos-26` as the fallback, and the line that says which one ran), `on: workflow_dispatch` with no inputs, the Homebrew removal, and the "no `mise` on PATH" assertion. Then:

1. Replace the `bash setup/packages.sh` step with `./setup.sh -y --skip-codegraph`, run from `$GITHUB_WORKSPACE`. Its exit status is the test. The runner has no terminal, so `setup.sh` skips `sudo -v`, the Enter prompt and the `script` log, and mise elevates with the runner's passwordless sudo. The runner has the Command Line Tools, so the precheck passes: the path without them is Task 6's.
2. Directly before it, a step `ls -la ~` for the log. Unverified: whether the runner image's home already holds files that `conf.d/40-dotfiles.toml` links (a `~/.zshrc` or `~/.bashrc`, say). A5 makes such a conflict stop the `dotfiles` part, so `setup.sh` would exit non-zero there. If the first run stops on one, add a step before `setup.sh` that moves each file the error names into `$RUNNER_TEMP/home-backup`, with the comment `# The runner is not a new Mac: its image ships these files`. Do not pass `-- --force-dotfiles`: the command under test stays the one a new Mac runs.
3. Disk readings. Keep A4's reading at the start (`df -h /` and the size of mise's bottle cache, at the path A4's step reads). A4's readings after each package manager cannot stay where they are: `setup.sh` applies the three managers inside one step. Replace them with one step after `setup.sh`, `if: always()`, that prints `df -h /`, the bottle-cache size, and `du -sh` of where each manager and the tools part write: `/opt/homebrew/Cellar` (formulae), `/opt/homebrew/Caskroom` and `/Applications` (casks), `~/.vscode/extensions` (extensions), `~/.local/share/mise/installs` (tools), each with `2> /dev/null || true`. What is lost: free space between managers, so the peak (one manager's downloads on top of the previous manager's installs) is not read, and a run that fills the disk is located by the failing line of the `setup.sh` log instead of by a reading. The per-manager footprint is kept, from the `du` lines.
4. Delete A4's `mise install --yes` step. The `tools` part of `mise bootstrap` installed the tools inside `setup.sh`. Keep A4's `GITHUB_PATH` step and its `MISE_CONFIG_DIR` line (harmless now that `setup.sh` links `~/.config/mise`), and the formula, cask and extension status checks with their `if: always()`.
5. A last step, `if: always()`, prints `MISE_DISABLE_TOOLS=npm:@colbymchenry/codegraph mise bootstrap status --missing || true` for the log. It is informational: the run never applies macOS preferences, so those entries are listed.

If the job does not fit on the runner, spec decision 12 splits it into one job per manager. The entry point cannot be split that way. In that case the per-manager jobs run `mise bootstrap packages apply --yes --manager <m>` after the mise installer, as A4 would, `.claude/rules/ci.md` says the workflow no longer runs `./setup.sh`, and Task 6's VM run is then the only test of the entry point. Report it to the owner when it happens. Do not shrink the package list to make it fit.

In `.claude/rules/ci.md`, replace A4's "runs `setup/packages.sh` (which installs mise and applies `conf.d/30-packages.toml`), installs the global tools" with "runs `./setup.sh -y --skip-codegraph` (mise's installer, the packages, then `mise bootstrap` without macOS preferences)". Add one sentence: a hosted runner is not a clean Mac, and the full proof is the VM checklist in the A6 plan's Task 6. `pnpm check` lints the workflow with actionlint.

- [ ] **Step 6: Prove nothing stale is left**

Run: `grep -rnE -e '--skip-brew|DOTFILES_SUDO_KEPT|setup/zsh\.sh|setup/(tests/)?packages\.sh|symlinks-backup|brew → zsh|link_config_dir' --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=superpowers --exclude-dir=.archify . | grep -v 'bin/lib/test-bootstrap' | grep -v 'bootstrap-runtime'`
Expected: hits in `setup.sh` only, the `--skip-brew)` case and its "is gone" message. Any other hit is a stale sentence an earlier phase wrote. Fix it in this commit and add its path to the `git add` in Step 7.

Run: `pnpm check`
Expected: exit 0. It runs `test-conventions`, which fails when `CLAUDE.md` is over 12,000 bytes.

Run: `wc -c CLAUDE.md`
Expected: under 12000. If it is over, delete text that restates code from `CLAUDE.md` until it fits. Do not raise the cap.

- [ ] **Step 7: Commit Tasks 1 and 2 together**

Task 1 Step 7 already staged the four deletions with `git rm`. Name every other path. Add a `setup/*.sh` file here only if Task 1 Step 7 gave it the `tput` wrapper.

```bash
chmod 755 bin/lib/test-bootstrap
git add setup.sh setup/misc.sh setup/README.md tilde/.config/mise/conf.d/50-bootstrap.toml \
  bin/lib/test-bootstrap bin/lib/check bin/lib/test-conventions bin/dotfiles bin/sysup \
  .claude/rules/setup.md .claude/skills/validate-setup/SKILL.md .claude/skills/validate-setup/snapshot.sh \
  .claude/skills/add-tool/SKILL.md .claude/agents/docs-auditor.md \
  .github/workflows/fresh-install.yml .claude/rules/ci.md README.md CLAUDE.md docs/README.md docs/rea.md
git status --short
```

Expected: every line of `git status --short` that starts with a letter in the first column is a path this plan names. `agents/claude-settings.json` shows ` M` (unstaged), never `M `. Then:

```bash
git commit -m "Make setup.sh a wrapper around mise bootstrap"
```

### Task 3: Prune report in `sysup`

A4 already upgrades packages in `sysup` through `mise bootstrap packages upgrade` and compares `packages status --json` before and after. What is left for A6 is the prune report.

**Files:**
- Modify: `bin/sysup` (after A4's `packages status` step), `bin/lib/test-sysup`, `.claude/rules/sysup.md`, `README.md` (the Updating list)

**Interfaces:**
- Consumes: `mise bootstrap packages prune --dry-run` prints one `remove <manager>:<name>@<version>` line per package and exits 0 (measured). With `-m brew-cask` it also prints `mise WARN  brew-cask:<name>: skipped: Homebrew owns this cask` lines, which are not removals (measured).
- Produces: one `sysup` step, `packages prune`.

- [ ] **Step 1: Write the failing assertions in `bin/lib/test-sysup`**

Extend A4's `mise` stub: `bootstrap packages prune --dry-run` prints `remove brew:old@1.0` and `remove brew:older@0.9` when `$STATE/undeclared` exists, prints nothing otherwise, and exits 1 when `$STATE/prune-report-fails` exists. Record every `bootstrap packages prune` call's arguments in `$STATE/prune-args.log`.

```bash
check_true "up to date: nothing undeclared" has '^✔ packages prune +nothing undeclared$'
check_true "undeclared: a notice with the command" has '^● packages prune +2 packages no config declares; review: mise bootstrap packages prune --dry-run$'
only_dry_runs() { ! grep -v -- --dry-run "$STATE/prune-args.log" | grep -q .; }
check_true "undeclared: sysup never prunes" only_dry_runs
check_true "prune report fails: fail line names the command" has '^✖ packages prune +run: mise bootstrap packages prune --dry-run$'
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash bin/lib/test-sysup`
Expected: `FAIL: up to date: nothing undeclared`.

- [ ] **Step 3: Implement `step "packages prune"` in `bin/sysup`**

`capture mise bootstrap packages prune --dry-run`, then the same with `-m brew-cask`, and count the `^remove ` lines of both. Zero is `ok`, more is one `notice`, a non-zero exit is `fail`. The step never runs prune without `--dry-run`.

- [ ] **Step 4: Run the test**

Run: `bash bin/lib/test-sysup`
Expected: every line starts with `ok:`.

- [ ] **Step 5: Docs**

`.claude/rules/sysup.md`: add to A4's packages bullet that prune is reported and never run, because it removes every formula no config declares. `README.md`, Updating list: one bullet for the report and the command that removes.

- [ ] **Step 6: Commit**

```bash
pnpm check
git add bin/sysup bin/lib/test-sysup .claude/rules/sysup.md README.md
git commit -m "Report undeclared packages in sysup"
```

### Task 4: Regenerate the setup diagram

**Files:**
- Modify: `setup/bootstrap-runtime.archify.json`, `setup/bootstrap-runtime.svg`

**Interfaces:**
- Consumes: the commit from Task 2 (line references pin to it).
- Produces: the image `setup/README.md:5` embeds.

- [ ] **Step 1: Edit the JSON**

Set `meta.repository.revision` to `git rev-parse HEAD`. Remove the `brew`, `symlinks` and `homebrew` nodes and their edges. Add a `mise` node (`mise bootstrap`, sublabel `files · dotfiles · shell · tools · task`, source `tilde/.config/mise/conf.d/50-bootstrap.toml`) between `setup` and `misc`. The package step (`mise bootstrap packages apply`, one manager at a time) and `setup/dotfiles-extras.sh` are steps of the `setup` node, with `setup.sh` as their source. Repoint every `sources` entry to lines that exist now. The `system` node's sources become the `[bootstrap.files]` and `[bootstrap.user]` tables. Rewrite the cards: the primary path is `setup.sh → packages → mise bootstrap → setup/misc.sh → setup/dotfiles-extras.sh`, the trust card says sudo is held until the `pre-tools` hook and that macOS preferences are never applied, and the sysup card says `mise bootstrap packages upgrade`.

- [ ] **Step 2: Validate and finalize**

Run: `node ~/.claude/skills/archify/bin/archify.mjs validate architecture setup/bootstrap-runtime.archify.json --repo-root . --quality showcase --json`
Expected: `"ok": true`.

Run: `node ~/.claude/skills/archify/bin/archify.mjs finalize architecture setup/bootstrap-runtime.archify.json .archify/architecture-dotfiles-runtime-$(date +%Y%m%d-%H%M%S)/dotfiles-runtime.html --repo-root . --quality showcase --json`
Expected: exit 0. Set `meta.output` to that path first.

- [ ] **Step 3: Export the SVG**

Open the HTML, use the viewer's SVG export, and save the file as `setup/bootstrap-runtime.svg`. The CLI has no export command.

- [ ] **Step 4: Commit**

```bash
pnpm check
git add setup/bootstrap-runtime.archify.json setup/bootstrap-runtime.svg
git commit -m "Update the setup diagram for the mise bootstrap entry point"
```

### Task 5: Run it on this Mac (needs the user's explicit go-ahead, and the user runs it)

This task changes the machine. Stop and ask the user for an explicit go-ahead before Step 2. The agent never runs `./setup.sh` itself. The Part B `setup` step for this phase must have landed first.

- [ ] **Step 1: Preview.** Run `/validate-setup before`. Read its `mise bootstrap --dry-run --skip macos-defaults` output with the user.
- [ ] **Step 2: The user runs `./setup.sh` in their own terminal, after giving the go-ahead.**
- [ ] **Step 3: Check.** Run `/validate-setup after`, then:

| Command | Expected |
| --- | --- |
| `mise bootstrap status --missing` | Informational, no exit status required. Every entry it lists belongs to `macos-defaults` (setup does not apply those, and apps rewrite their own). An entry of another part is a failure to explain. |
| `defaults read com.apple.dock autohide` before and after the run (or any one key from `20-macos.toml`) | The same value both times. No app was quit and Finder and the Dock kept their process IDs (`pgrep -x Dock` before and after). |
| `sudo -n true; echo $?`, in the terminal that ran `setup.sh` | `1` (the credential was dropped) |
| `dscl . -read ~ UserShell` | `UserShell: /opt/homebrew/bin/zsh` |
| `cat /etc/pam.d/sudo_local` | `auth       sufficient     pam_tid.so` |
| `command -v codegraph` | still resolves |

- [ ] **Step 4: Second run changes nothing (the user runs it).** Copy `after.txt` to `before.txt`, have the user run `./setup.sh -y` again, take a new `after.txt`. `diff -u` is empty outside `macos-defaults` lines of the `mise bootstrap status` section, which apps can change on their own. The new log has no line that reports an install, a link or a write outside the task's own "already" lines.
- [ ] **Step 5: Hand on to Task 6.** This Mac is set up already, so Steps 3 and 4 prove a rerun, not a new Mac. The plan stays open until Task 6 has run.

### Task 6: Prove a new Mac in a disposable macOS 27 VM (the owner runs it, after a go-ahead in chat)

Spec decision 12 (c). A hosted runner is not a clean Mac: Xcode and other tools are preinstalled, and nobody sees a first-launch prompt. This run is the full proof of the entry point, and the gate plan B's Homebrew-removal task cites. It is a checklist with evidence to capture, not a script. The owner runs every step. An agent never creates, starts or deletes the VM and never runs anything in it unasked. It may read the evidence the owner copies out and write the results section. Run it after Tasks 1 to 5 are pushed, because the VM clones the public repo from GitHub.

**Measured on this Mac (2026-11-09).** Host macOS 27.2.1 (`sw_vers`). UTM 5.0.8 (`defaults read /Applications/UTM.app/Contents/Info.plist CFBundleShortVersionString`), `utmctl` on PATH. 140 GiB free on `/` (`df -h /`). The full install measured about 32 GB on this Mac (spec decision 12).

**From UTM's docs, read 2026-11-09.** `docs.getutm.app/guest-support/macos/`: a macOS guest is made with the wizard's "Virtualize", then "macOS 12+", on Apple Silicon. UTM downloads the latest compatible IPSW, or takes one you supply. Snapshots and disposable mode need macOS 27 on the Apple Virtualization backend, and a shared folder uses VirtioFS (`mount_virtiofs share <mount point>` in the guest, macOS 13 or newer on both sides). `docs.getutm.app/advanced/disposable/`: disposable mode is "Run without saving changes" in the VM's action menu, and the window title then shows "Disposable Mode". For a macOS guest, EFI and auxiliary storage changes are discarded too, and nothing can be suspended or snapshotted while it runs. The page does not say whether macOS 27 is needed on the host or the guest. Both are 27 here.

**Unverified, each with the check that settles it.**

- That UTM offers a macOS 27 IPSW. Check: the build the wizard names before the download, and `sw_vers` in the guest.
- That "Run without saving changes" is offered for this macOS guest on UTM 5.0.8. Check: the action menu of the stopped base VM. When it is missing, use a clone: `utmctl clone <base> --name a6-proof` (read `utmctl help clone` first), run the clone, and `utmctl delete a6-proof` afterwards, which asks no confirmation.
- Apple ID, iCloud and App Store sign-in inside a guest. UTM's docs do not cover them. Setup needs none: no `mas` entry is declared (`grep -c '^mas ' setup/Brewfile` printed 0 at HEAD; after A4 run `grep -c '"mas:' tilde/.config/mise/conf.d/*.toml`). So skip sign-in in Setup Assistant and record only whether it let you skip.
- Touch ID. A guest has no sensor. `sudo_local` makes `pam_tid.so` `sufficient`, so sudo should fall back to the password. Checklist item 8 records what happens.
- Whether the disk image is allocated sparsely. Check: `du -sh` of the VM's `.utm` bundle on the host right after creating it.

- [ ] **Step 1: Get the owner's go-ahead in chat.** Name the disk space (up to the image size below), the time (expect one to two hours) and that nothing on the host changes except UTM's VM folder and one shared folder.

- [ ] **Step 2: Make the base VM (once, kept).** UTM, Create a New Virtual Machine, Virtualize, macOS 12+, let UTM download the IPSW. 4 cores, 8 GB of memory, a 100 GB disk (about 32 GB of packages plus macOS, inside the 140 GiB free). In Setup Assistant: a local admin account, no Apple ID, no migration. Do not install the Command Line Tools, Xcode or Homebrew. In the guest Terminal record `sw_vers` and `xcode-select -p; echo $?` (expected: a non-zero exit, no developer directory). In the VM's settings, share one empty host folder, for example `~/vm-proof`. Shut down. This base is the clean Mac, so it never runs setup outside disposable mode.

- [ ] **Step 3: Start it disposable.** Action menu, "Run without saving changes". Confirm the title says "Disposable Mode". Everything below is lost at shutdown, so evidence goes to the shared folder: `mkdir -p ~/share && mount_virtiofs share ~/share`. Then `df -h / > ~/share/df-before.txt` and `curl -s https://api.github.com/rate_limit > ~/share/rate-before.json`.

- [ ] **Step 4: Setup without the Command Line Tools stops.** `curl -fsSL https://github.com/jrmatherly/dotfiles/archive/refs/heads/main.tar.gz | tar -xz -C ~ && ~/dotfiles-main/setup.sh; echo "exit $?"`. Expected: `Command Line Tools missing; run: xcode-select --install, then rerun ./setup.sh` and `exit 1`, before any link or download. Then `rm -rf ~/dotfiles-main`.

- [ ] **Step 5: The README's path.** `xcode-select --install` and accept the dialog. Then `mkdir -p ~/dev && git clone https://github.com/jrmatherly/dotfiles.git ~/dev/dotfiles && cd ~/dev/dotfiles && time ./setup.sh`. Answer the prompts as a new owner would: Enter, the sudo password, the git identity prompt. Write down every dialog that appears, and what it asked.

- [ ] **Step 6: Capture the evidence.** Copy `private/setup-logs/*.log` to `~/share/`. Then record each row, with its output saved to `~/share/`:

| # | Item | Evidence | Pass |
| --- | --- | --- | --- |
| 1 | No Command Line Tools | Step 4 output | exit 1 with the `xcode-select --install` message |
| 2 | mise installer path | `command -v mise; mise --version`, the log's mise.run lines | `~/.local/bin/mise`, 2026.11.5 or newer |
| 3 | Formulae | `mise bootstrap packages status --json \| jq '[.brew.packages[] \| select(.state != "installed")]'` | `[]` |
| 4 | Casks, the two pkg installers included | the same for `."brew-cask"`, then `git credential-manager --version`, `dotnet --info \| head -3`, `pkgutil --pkgs \| grep -E 'gitcredentialmanager\|microsoft\.dotnet'` | `[]`, both commands answer, both receipt families listed (`com.microsoft.gitcredentialmanager` and `com.microsoft.dotnet.*` on this Mac) |
| 5 | Extensions | `mise bootstrap packages status --json \| jq '.vscode.available, [.vscode.packages[] \| select(.state != "installed")]'` | `true` and `[]`. Record whether they installed in this run or were skipped because `code` came later |
| 6 | Dotfiles links | `ls -l ~/dotfiles ~/.config/mise ~/.zshrc`, `mise bootstrap status --missing` | the links point into `~/dev/dotfiles`, and no `dotfiles` entry is missing |
| 7 | Login shell | `dscl . -read ~ UserShell`, then a new Terminal window | `/opt/homebrew/bin/zsh`, and the window opens with no error |
| 8 | Touch ID file, sudo | `cat /etc/pam.d/sudo_local`, then `sudo -k; sudo true; echo $?` | the one `pam_tid.so` line. Record whether sudo asked for the password and exited 0 |
| 9 | First-launch prompts | the dialogs from Step 5. `for a in /Applications/*.app; do xattr -p com.apple.quarantine "$a" > /dev/null 2>&1 && echo "$a"; done`. Open Ghostty, VS Code, 1Password and OrbStack once and note each prompt | every prompt named. The quarantine list says which apps show Gatekeeper's first-launch dialog |
| 10 | Ruby for source formulae | `grep -inE 'ruby\|from source\|requires Ruby' <log>`, `command -v ruby`, `ruby --version` | Record whether any formula built from source and whether the cask step needed the declared `brew:ruby` (A4 P12). A `requires Ruby 3` error fails the item |
| 11 | Disk used | `df -h /` against `df-before.txt`; `du -sh /opt/homebrew ~/.local/share/mise ~/Library/Caches/mise /Applications`; on the host, `du -sh` of the `.utm` bundle | Record the numbers. They are the figure the runner's 14 GB is compared with |
| 12 | GitHub API calls without a token | `curl -s https://api.github.com/rate_limit` against `rate-before.json`, then again after `./setup.sh -y -- --upgrade` | Record both differences. Shared NAT means the host's own anonymous calls count too, so keep the host quiet meanwhile. This settles the upgrade-calls question in Decisions |
| 13 | A second run changes nothing | `./setup.sh -y` again, the new log | no install, link or write lines outside the task's "already" lines |
| 14 | Warnings | `grep -inE 'error\|warn\|deprecat\|fail\|not found' <each log>` | each hit explained: expected, upstream noise, or a problem |
| 15 | macOS preferences untouched | `defaults read com.apple.dock autohide` before Step 5 and after Step 6 | the same output both times |

Shut the VM down when the evidence is copied. Disposable mode discards the guest's changes. Check the base still starts clean (`xcode-select -p` fails) before using it again.

- [ ] **Step 7: Record the results and close the phase.** Add a `#### Results` heading under this task: the date, host, guest build and UTM version, one line per row (pass or fail, and the evidence line), each failure with the commit that fixed it and the rerun that passed. A failure in rows 2 to 8, 10 or 13 blocks the gate until a fixed rerun passes. Row 9, 11, 12 and 14 findings are recorded, and become plan or doc changes where they need one. Plan B's Homebrew removal (B Task 5) cites this section as its gate. Then:

```bash
git mv docs/superpowers/plans/2026-11-09-a6-bootstrap-entry-point.md docs/superpowers/plans/completed/
git add docs/superpowers/plans/completed/2026-11-09-a6-bootstrap-entry-point.md
git status --short
git commit -m "Complete the A6 bootstrap entry point plan"
```

Expected before the commit: only the rename is staged, and ` M agents/claude-settings.json` stays unstaged. Push.

## Part B hook: what the `setup` step needs

Only the old method left these on disk. A6 carries no code for them.

- `/etc/pam.d/sudo_local` with other content. The old `setup.sh` created the file only when it was missing, so a hand-edited one survived. mise now rewrites it. B shows the diff, backs the file up and asks, before the first bootstrap.
- A leftover mise rust install (`~/.local/share/mise/installs/rust`) and a foreign `~/.cargo/bin/rustup`. The removal and the warning move out of `setup/misc.sh` (inventory M16, M17) into B.
- The `mise` MCP server registered with Homebrew's path. `register_mcp` in `misc.sh` only warns when the command differs from `$(command -v mise)`. B re-registers it: `claude mcp remove mise -s user`, then `claude mcp add --scope user mise -- "$(command -v mise)" mcp`.
- The log path did not move. `private/setup-logs/` stays, so B has nothing to remove there, and the spec's "old logs path" item can go.
- The `~/.config/mise` and `~/dotfiles` links the old method made are the ones the new `setup.sh` expects. Nothing to do.
