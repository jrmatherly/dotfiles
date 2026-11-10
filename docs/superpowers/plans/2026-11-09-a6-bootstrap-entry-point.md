# A6 Bootstrap Entry Point Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new Mac goes from `git clone` to a finished setup with `./setup.sh`, which installs mise, links the repo's mise config and runs `mise bootstrap`.

**Architecture:** `setup.sh` shrinks to a wrapper. It checks the Command Line Tools, links `~/dotfiles` and `~/.config/mise` into the clone, installs mise when missing, holds sudo, and runs `mise bootstrap` from `$HOME`. `conf.d/50-bootstrap.toml` declares Touch ID for sudo, the login shell, one `pre-tools` hook that drops sudo, and one `[tasks.bootstrap]` that runs `setup/misc.sh`. `setup/misc.sh` keeps every step no declarative section covers. `upup` gains a prune report.

**Tech Stack:** bash 3.2 (`/bin/bash`), mise 2026.11.5, TOML, the repo's stub-based self-checks.

**Spec:** `docs/superpowers/specs/2026-11-09-mise-first-setup-and-settings-ui.md`, phase "A6. Bootstrap entry point". Read it first.

## Global Constraints

- Minimum mise version: 2026.11.5. Setup fails with a clear message below it.
- The new method is Homebrew-free. Setup, `upup` and shell startup never call `brew`.
- Part A never reads the old layout and carries no compatibility code for it.
- Every task and hook is safe to repeat. A bootstrap run is not a transaction. Hooks and the `bootstrap` task run every time.
- A closed stdin means "skip", never abort or overwrite.
- Bash scripts start with `#!/bin/bash` and a header comment, define their output helpers inline, and pass `pnpm check`.
- Commit subjects are short, imperative, sentence case, with no conventional-commit prefix.
- Every phase updates the docs that describe what it changed, in the same commit (D12).
- Never run `./setup.sh`, `mise bootstrap` without `--dry-run`, or `upup` yourself. Task 5 is the only place the real thing runs, and the user runs it.
- Tests that isolate mise set `HOME` and `MISE_CONFIG_DIR` only. Never set `MISE_GLOBAL_CONFIG_FILE`.
- Line numbers in this plan are from commit `9af6244`, before A1 to A5. Find each quoted sentence with `grep -n` before editing it.

## Review Focus

1. A Mac that already has its own `~/.config/mise` (a real directory, or a link elsewhere). Expected: `setup.sh` stops before it installs or changes anything and prints the `mv` command. Pinned by `test-bootstrap` case c.
2. `mise bootstrap` started inside the clone. Measured: the repo's `.nvmrc` (`lts/*`) adds `node@26` to the tools part. Expected: `setup.sh` always runs mise from `$HOME`. Pinned by `test-bootstrap` case a (`pwd=`).
3. A mise older than 2026.11.5 already on PATH. Expected: A1's message naming the floor and the found version, and no bootstrap. Pinned by case e.
4. A run without a terminal (CI, an agent shell). Expected: no `sudo -v` prompt, no Enter prompt, no `script` log, and the run still reaches `mise bootstrap`. Pinned by case a (`sudo.log` has no `-v`).
5. Packages on the Mac that no config declares. Expected: `upup` names the count and the review command, and removes nothing. Pinned by the `only_dry_runs` assertion in Task 3.

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

**A prompt inside a hook (not verified).** `setup/dotfiles-extras.sh` asks for the git identity when `~/.gitconfig.local` is missing, and it runs from the `post-dotfiles` hook. mise runs a hook as `sh -o errexit -c '<cmd>'`, and no hook was run for real, so whether the prompt reaches the terminal is unknown. This Mac has `~/.gitconfig.local`, so the real run in Task 5 cannot show it. The fresh-install workflow has no terminal either, and there the script must take its non-interactive path (the `DOTFILES_GIT_*` values, or skip with a warning) and exit 0. If a real first install shows the prompt does not appear, move the identity block out of `dotfiles-extras.sh` into `setup.sh`, before `mise bootstrap`, where a terminal is certain. Until a fresh Mac has run it, the README says to set `DOTFILES_GIT_NAME` and `DOTFILES_GIT_EMAIL` before the first run.

**Sudo.** `setup.sh` keeps `sudo -v` and the keep-alive loop, as one span. mise's order puts every part that needs root (packages, files, A5's `post-dotfiles` extras, the `post-defaults` extras, the login shell) before `tools`. The `pre-tools` hook runs `sudo -k`, and `misc.sh` starts with `sudo -k` for runs that skip `tools`. That replaces the release and re-ask around `misc.sh`. `DOTFILES_SUDO_KEPT` goes. Without a terminal `setup.sh` skips `sudo -v`, and mise elevates per step.

**Setup log stays.** `private/setup-logs/<timestamp>.log` through `script`, unchanged. mise keeps no run log, and `/validate-setup after` greps this one.

**Telemetry exports move to the top of `setup/misc.sh`.** That is where the tools they silence run. The `export NAME=value` form is unchanged, so `test-conventions` changes one file name.

**Flags.**

| Flag | After A6 |
| --- | --- |
| `-y`, `--yes` | Skips the Enter prompt and passes `--yes` to `mise bootstrap`. |
| `--skip-codegraph` | Exports `DOTFILES_SKIP_CODEGRAPH=true` and `MISE_DISABLE_TOOLS=npm:@colbymchenry/codegraph`. Measured: with the variable set, the tools part and `mise bootstrap status --missing` both leave the tool out. |
| `--dash` | Runs `setup/dash.sh` after a successful bootstrap. |
| `-h`, `--help` | Unchanged. |
| `--skip-brew` | Removed. It exits 1 and names the replacement, `./setup.sh -- --skip packages`. |
| `-- <args>` | New. Everything after `--` goes to `mise bootstrap` (`--skip`, `--only`, `--dry-run`, `--upgrade`). |

**`upup` reports prune, it never prunes.** `mise bootstrap packages prune` removes every linked formula no config declares, including ones installed by hand. `upup` runs it with `--dry-run` and prints a notice with the command.

## Inventory

Every action of the four scripts, 60 in all. "Task" means `setup/misc.sh` run by `[tasks.bootstrap]`.

**`setup.sh` (17)**

| # | Action (lines) | Goes to |
| --- | --- | --- |
| S1 | Resolve the clone, `cd` (19-22) | `setup.sh`. It also exports `DOTFILES` and runs mise from `$HOME`. |
| S2 | Ten telemetry exports (24-37) | Task, top of `misc.sh`. |
| S3 | Flag parsing (39-63) | `setup.sh`, per the flag table. |
| S4 | `DOTFILES_SKIP_CODEGRAPH` default (42) | `setup.sh`, plus `MISE_DISABLE_TOOLS`. |
| S5 | Run log through `script` (65-76) | `setup.sh`, unchanged. |
| S6 | Colors, `title`, `warning` (78-97) | `setup.sh`, unchanged. |
| S7 | ASCII banner, warning, Enter prompt (99-126) | Banner art deleted. The warning and the prompt stay, reworded for A5 (a conflict stops the run). |
| S8 | `~/dotfiles` link (128-141) | `setup.sh`. It must exist before mise runs, because `[dotfiles]` sources, hooks and the task resolve the repo through it. A wrong `~/dotfiles` now stops the run instead of warning. |
| S9 | Touch ID `sudo_local` (143-147) | `[bootstrap.files]`. |
| S10 | `sudo -v`, keep-alive, `DOTFILES_SUDO_KEPT` (149-180) | `setup.sh` keeps `sudo -v` and the loop. `DOTFILES_SUDO_KEPT` deleted. |
| S11 | Release sudo around `misc.sh` (198) | `pre-tools` hook and the first line of `misc.sh`. |
| S12 | `brew.sh` (182-189), which A4 replaced with `setup/packages.sh` | `setup/packages.sh` deleted. Its mise installer moves to `setup.sh`, its `mise plugins link` to the `pre-packages` hook, its package apply to the `packages` part. |
| S13 | `zsh.sh` (191-194) | `[bootstrap.user]`. |
| S14 | `misc.sh` (196-201) | `[tasks.bootstrap]`. |
| S15 | Re-ask sudo, `symlinks.sh` (203-212), which A5 replaced with `mise dotfiles apply --yes` and `setup/dotfiles-extras.sh` | The `dotfiles` part, then a `post-dotfiles` hook that runs `setup/dotfiles-extras.sh` while sudo is still held. The re-ask is deleted. |
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
| Hook | 2 | S11, S15 |
| Task (`setup/misc.sh`) | 31 | S2, S14, M1 to M3, M7 to M10, M13 to M15, M18 to M36 |
| `setup.sh` | 12 | S1, S3 to S8, S10, S16, S17, M6, M11 |
| Unchanged script | 1 | D1 |
| Part B | 2 | M16, M17 |
| Deleted | 6 | S12, Z1, Z2, Z4, M4, M5 |

## Interfaces from A1 to A5

- A1: `setup/mise-floor.sh` is the version check, called from `setup/misc.sh`. Task 1 moves the call to `setup.sh`. CI has `mise` 2026.11.5 and `uv` on PATH (`jdx/mise-action` with `install: false`), with no `~/.config/mise` link, so part two of `test-bootstrap` runs there.
- A3: `tilde/.config/mise/conf.d/20-macos.toml` declares `[bootstrap.hooks]` `pre-defaults` and `post-defaults`. Measured: hooks from two fragments combine.
- A4: `conf.d/30-packages.toml` declares `brew:zsh`. `setup/packages.sh` installs mise with `curl -fsSL https://mise.run | sh`, links the vscode plugin and applies packages, behind the `--skip-brew` flag. A6 deletes that script. `setup/misc.sh` already has `export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"` in place of `brew shellenv`, so inventory row M2 is done. `upup` already has `mise self-update`, `packages` (status JSON compared before and after) and `packages status` steps, and exports `GITHUB_TOKEN` from `gh auth token`. A4 adds no hooks. `fresh-install.yml` applies packages piecewise with a `casks` input.
- A5: `conf.d/40-dotfiles.toml` links `tilde/` with sources written `~/dotfiles/...`, so `~/dotfiles` must exist before the `dotfiles` part. A real directory at `~/.config/mise` makes `mise dot apply` refuse. A5 defines no task and no hook. It creates `setup/dotfiles-extras.sh` (git identity prompt, the two `sudo ln -s` links into `/usr/local/bin`, Firefox hard links, `bat cache --build`), safe to repeat, which the old `setup.sh` calls after `mise dotfiles apply --yes`. Measured here: when two fragments both define `[tasks.bootstrap]`, the later file wins silently, so `test-bootstrap` asserts there is exactly one.

## File Structure

| File | Change |
| --- | --- |
| `tilde/.config/mise/conf.d/50-bootstrap.toml` | Create. |
| `setup.sh` | Rewrite as the wrapper. |
| `setup/misc.sh` | Trim to the task (inventory M rows). |
| `setup/zsh.sh`, `setup/packages.sh` | Delete. |
| `bin/lib/test-bootstrap` | Create. Stub-driven check of `setup.sh` and a dry-run parse of the real config. |
| `bin/lib/check`, `bin/lib/test-conventions` | Wire the new check, move the telemetry and `tput` checks. |
| `setup/tests/symlinks-backup.sh` | Drop the `link_config_dir` section (lines 42 on), or the file if A5 left nothing else. |
| `bin/upup`, `bin/lib/test-upup` | A `packages prune` report step. |
| `.claude/skills/validate-setup/SKILL.md`, `snapshot.sh`, `.claude/rules/setup.md`, `.claude/settings.json` | Rewrite for the new order. |
| Docs listed in Task 2 | Replace stale sentences. |
| `setup/bootstrap-runtime.archify.json`, `setup/bootstrap-runtime.svg` | Regenerate. |

---

### Task 1: Bootstrap config, task script and entry point

**Files:**
- Create: `tilde/.config/mise/conf.d/50-bootstrap.toml`, `bin/lib/test-bootstrap`
- Modify: `setup.sh`, `setup/misc.sh`, `bin/lib/check`, `bin/lib/test-conventions:10,34,90-94`, `setup/tests/symlinks-backup.sh`
- Delete: `setup/zsh.sh`

**Interfaces:**
- Consumes: the A1 to A5 interfaces above.
- Produces: `./setup.sh [-y|--yes] [--skip-codegraph] [--dash] [-h|--help] [-- <mise bootstrap args>]`. The environment the task sees: `DOTFILES`, `DOTFILES_SKIP_CODEGRAPH`, `MISE_DISABLE_TOOLS`. Task 2 documents these. Task 5 runs them.

- [ ] **Step 1: Write `bin/lib/test-bootstrap`**

Header in the `bin/lib/test-upup` style. Part one never touches the machine. `HOME`, `STATE` and a stub `bin` live under `mktemp -d`, and `PATH` is `"$tmp/bin:/usr/bin:/bin"`. Stubs:

```bash
stub mise 'case $1 in
  --version) echo "${STUB_MISE_VERSION:-2026.11.5} macos-arm64 (2026-11-08)" ;;
  bootstrap) echo "pwd=$(pwd -P) args=$* disable=${MISE_DISABLE_TOOLS:-} dotfiles=${DOTFILES:-} skip=${DOTFILES_SKIP_CODEGRAPH:-}" >> "$STATE/mise.log"
    [ ! -e "$STATE/bootstrap-fails" ] ;;
esac'
stub sudo 'echo "$*" >> "$STATE/sudo.log"'
stub xcode-select '[ ! -e "$STATE/no-clt" ]'
stub curl 'echo "$*" >> "$STATE/curl.log"; echo "mkdir -p \"\$HOME/.local/bin\" && cp \"$STATE/mise-stub\" \"\$HOME/.local/bin/mise\""'
```

Each case runs `"$repo/setup.sh" <args> < /dev/null` and asserts with `check_true`, as `test-upup` does:

| Case | Setup | Assertions |
| --- | --- | --- |
| a | empty `HOME` | exit 0. `~/.config/mise` and `~/dotfiles` are links whose `-ef` targets are `$repo/tilde/.config/mise` and `$repo`. `mise.log` has `pwd=<HOME> args=bootstrap disable= dotfiles=<repo>`. `sudo.log` has no `-v` line. |
| b | `-y --skip-codegraph -- --skip packages` | `args=bootstrap --yes --skip packages disable=npm:@colbymchenry/codegraph` and `skip=true`. |
| c | `mkdir -p ~/.config/mise` with a file in it | exit 1. Output matches `is not a link to`. `mise.log` gained no line. |
| c2 | `~/dotfiles` is a link to another directory | exit 1. Output matches `~/dotfiles is not a link to`. `mise.log` gained no line. |
| d | no `mise` stub on PATH, `mise-stub` in `STATE` | exit 0. `curl.log` has `https://mise.run`. `mise.log` gained a line. |
| e | `STUB_MISE_VERSION=2026.10.1` | exit 1. Output matches `mise 2026\.11\.5 or newer is required, found 2026\.10\.1`. No bootstrap line. |
| f | `touch $STATE/bootstrap-fails` | exit is non-zero. Output matches `rerun \./setup\.sh`. |
| g | `--skip-brew` | exit 1. Output matches `-- --skip packages`. `--help` output lacks `skip-brew`. |
| h | `touch $STATE/no-clt` | exit 1. Output matches `xcode-select --install`. |

Part two uses the real mise and is skipped with a stderr note when `command -v mise` finds nothing. It runs from a scratch `HOME` with `MISE_CONFIG_DIR="$repo/tilde/.config/mise"` and `DOTFILES="$repo"`:

```bash
out=$(mise bootstrap --dry-run --only files,user,task 2>&1) || fail "config does not load: $out"
grep -q 'mise bootstrap: system files' <<< "$out" || fail "no files part"
grep -q 'mise bootstrap: login shell' <<< "$out" || fail "no user part"
grep -qF 'mise bootstrap: running `bootstrap` task' <<< "$out" || fail "no bootstrap task"
grep -qF '/setup/misc.sh' <<< "$out" || fail "task does not run setup/misc.sh"
! grep -q 'unknown field' <<< "$out" || fail "mise warns about an unknown key"
mise bootstrap files status | grep -q '/etc/pam.d/sudo_local' || fail "sudo_local not declared"
mise bootstrap user status | grep -q '^/opt/homebrew/bin/zsh' || fail "login shell not declared"
```

Static checks close the file: exactly one `[tasks.bootstrap]` across `conf.d/*.toml`. `50-bootstrap.toml` has the line `pre-tools = "sudo -k"`. In `setup/misc.sh`, `grep -nE '(^|[^a-z_])sudo ' | grep -v 'sudo -k'` is empty, and so are greps for `link_config_dir`, `mise install`, `brew shellenv` and `DOTFILES_SUDO_KEPT`.

- [ ] **Step 2: Run it to see it fail**

Run: `bash bin/lib/test-bootstrap`
Expected: `FAIL` on case a (the current `setup.sh` calls scripts the stubs do not cover) or on the missing `50-bootstrap.toml`.

- [ ] **Step 3: Create `tilde/.config/mise/conf.d/50-bootstrap.toml`** with exactly this content

```toml
# What `mise bootstrap` does beyond env, macOS defaults, packages and dotfiles
# (conf.d/10 to 40). setup.sh links this directory to ~/.config/mise, installs
# mise and runs `mise bootstrap` from $HOME. https://mise.jdx.dev/bootstrap.html

# Touch ID for sudo. /etc/pam.d/sudo includes sudo_local, and macOS updates
# leave the file alone. mise writes it through sudo, and only when the content
# or the mode differs.
[bootstrap.files."/etc/pam.d/sudo_local"]
content = "auth       sufficient     pam_tid.so\n"
mode = "0644"

# zsh from conf.d/30-packages.toml as the login shell. mise adds it to
# /etc/shells and runs chsh when the account's shell differs.
[bootstrap.user]
login_shell = "/opt/homebrew/bin/zsh"

# No [bootstrap.mise_shell_activate]: ~/.zprofile and ~/.zshrc are links into
# this repo, which mise skips, and zsh/init.zsh delays full activation to the
# first prompt on purpose.

[bootstrap.hooks]
# The VS Code extension manager is a plugin kept in this repo. Linking is safe
# to repeat (--force replaces the link), and extensions install in the plugin
# packages part, long after this.
pre-packages = 'mise plugins link --force vscode "${DOTFILES:-$HOME/dotfiles}/mise-plugins/vscode"'
# What [dotfiles] cannot declare: the git identity prompt, the two
# /usr/local/bin links (sudo), Firefox hard links, bat's cache. It runs here
# and not in the task because it may need sudo. It also runs on `mise dot apply`.
post-dotfiles = '"${DOTFILES:-$HOME/dotfiles}/setup/dotfiles-extras.sh"'
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

1. `set -euo pipefail`, then `DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd -P)"` and `export DOTFILES_DIR DOTFILES="$DOTFILES_DIR"`.
2. Flags per the flag table. Arguments after `--` collect in `mise_args`. `--skip-brew` prints `--skip-brew is gone: use ./setup.sh -- --skip packages` to stderr and exits 1.
3. The `script` re-exec block, unchanged (lines 65-76).
4. Colors, `title`, `warning`, unchanged.
5. `xcode-select -p > /dev/null 2>&1` or exit 1 with `Command Line Tools missing; run: xcode-select --install, then rerun ./setup.sh`.
6. The warning text and the Enter prompt. No banner art.
7. `link_into_repo <link> <target>`: creates the link when nothing is there, returns 0 when `<link> -ef <target>`, returns 1 otherwise. For `~/dotfiles` a failure exits 1 with `~/dotfiles is not a link to $DOTFILES_DIR. Move it aside and rerun ./setup.sh`, because every `[dotfiles]` source and every hook goes through that path (A5 added this guard, keep it). For `~/.config/mise` a failure exits 1 with `~/.config/mise is not a link to $DOTFILES_DIR/tilde/.config/mise. Move it aside (mv ~/.config/mise ~/.config/mise.backup) and rerun ./setup.sh`. Run `mkdir -p "$HOME/.config"` first.
8. mise. When `command -v mise` finds nothing and `~/.local/bin/mise` is absent, run `curl -fsSL https://mise.run | sh`. Then `export PATH="$HOME/.local/bin:$PATH"`.
9. Version floor: `bash "$DOTFILES_DIR/setup/mise-floor.sh" || exit 1`. A1 created that script. It holds the floor (`floor=2026.11.5`), reads `mise --version` from PATH and prints `mise 2026.11.5 or newer is required, found <version>. Upgrade mise, then run setup again.` Do not write a second check. Remove A1's call from `setup/misc.sh`, since mise is already running when the task starts.
10. With `--skip-codegraph`: `export DOTFILES_SKIP_CODEGRAPH=true MISE_DISABLE_TOOLS="${MISE_DISABLE_TOOLS:+$MISE_DISABLE_TOOLS,}npm:@colbymchenry/codegraph"`.
11. When `[ -t 0 ]`: `sudo -v`, then `sudo_keepalive_start` (lines 152-160, unchanged). The `EXIT` trap runs `sudo_keepalive_stop` (lines 164-170, unchanged).
12. `cd "$HOME"`, then `mise bootstrap ${yes:+--yes} ${mise_args[@]+"${mise_args[@]}"}`. On failure print `mise bootstrap stopped. Earlier steps stay applied. Fix what it reported, then rerun ./setup.sh` and exit with mise's status.
13. `--dash`, the closing line and `"$DOTFILES_DIR/bin/nyan"`.

- [ ] **Step 5: Trim `setup/misc.sh`** to the inventory's "Task" rows

- Add a header comment that says the script is the `bootstrap` task of `conf.d/50-bootstrap.toml`, runs on every `mise bootstrap`, and must never call sudo.
- After `set -euo pipefail`: the ten `export` lines from `setup.sh:28-37` with their comment, then `sudo -k 2> /dev/null || true`.
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

- [ ] **Step 7: Delete `setup/zsh.sh` and `setup/packages.sh`, and move the convention checks**

Before deleting `setup/packages.sh`, read it. Anything beyond the mise installer, the plugin link and the package apply (for example a `GITHUB_TOKEN` export for tap resolution) moves to `setup.sh` ahead of `mise bootstrap`. Add to the static checks of `test-bootstrap` that `50-bootstrap.toml` has the `pre-packages` and `post-dotfiles` lines.

In `bin/lib/test-conventions`: line 34 reads the exports from `setup/misc.sh` instead of `setup.sh`. Line 10 of the header says `setup/misc.sh exports a subset of zsh/env.zsh's`. The `tput` loop at 92 covers `setup/misc.sh` only. Add `'Bash(mise bootstrap*)'` to a `rules .claude/settings.json ask present` line. In `setup/tests/symlinks-backup.sh` remove the `link_config_dir` block.

- [ ] **Step 8: Wire the check**

In `bin/lib/check`, after the `test-upup` line:

```bash
# setup.sh against stubbed mise, sudo and curl, then a dry-run of the tracked bootstrap config in a scratch HOME
bash bin/lib/test-bootstrap > /dev/null
```

- [ ] **Step 9: Run the checks**

Run: `bash bin/lib/test-bootstrap && bash bin/lib/test-conventions`
Expected: every `ok:` line, then `conventions: all checks passed`.

Run: `cd ~ && MISE_CONFIG_DIR="$DOTFILES/tilde/.config/mise" mise bootstrap --dry-run`
Expected: exit 0, the headings `system files`, `login shell`, `pre-tools hooks` with `sh -o errexit -c 'sudo -k'`, `tools`, and the `bootstrap` task line. On this Mac the files and login shell lines say `already converged` and `already set to /opt/homebrew/bin/zsh`.

No commit yet. Task 2 lands in the same commit (D12).

### Task 2: Docs and agent instructions for the new entry point

**Files:**
- Modify: `.github/workflows/fresh-install.yml`, `README.md`, `setup/README.md`, `CLAUDE.md`, `.claude/rules/setup.md`, `.claude/rules/telemetry-sync.md`, `.claude/skills/validate-setup/SKILL.md`, `.claude/skills/validate-setup/snapshot.sh`, `.claude/agents/docs-auditor.md`, `.claude/settings.json`, `docs/privacy.md`, `docs/README.md`, `docs/rea.md`, `bin/dotfiles`, `bin/upup:210`, `.claude/skills/add-tool/SKILL.md`

**Interfaces:**
- Consumes: Task 1's signature and environment.
- Produces: nothing later tasks call.

Facts every edit must state where it applies: mise is installed first, by `setup.sh`, into `~/.local/bin`. `setup.sh` wraps `mise bootstrap`. A run is not a transaction, so rerun `./setup.sh` after a failure. Hooks and the `bootstrap` task run on every bootstrap.

- [ ] **Step 1: Replace the stale sentences**

| File:line | Stale text | Replace with |
| --- | --- | --- |
| `README.md:14` | "…from the Brewfile; `setup/zsh.sh` makes it your login shell" | mise makes it the login shell (`[bootstrap.user]`). |
| `README.md:53` | "`setup/misc.sh` offers `gh auth login` later" | Still true. Keep. |
| `README.md:67-80` | The "Manually" section and "`setup.sh` also does a few things the manual path skips…" | Delete the section. Replace with a short "Preview" section: `cd ~ && MISE_CONFIG_DIR=~/dev/dotfiles/tilde/.config/mise mise bootstrap --dry-run`, and `mise bootstrap` as the rerun once the link exists. |
| `README.md:93` | "This will install all required dotfiles in your home directory as symlinks." | Add the order: Command Line Tools check, the two links, mise, then `mise bootstrap`. Add the rerun sentence. |
| `README.md:100` | "`--skip-brew` \| Skip `brew update` and the Brewfile install…" | Remove the row. Add a `-- <args>` row with `./setup.sh -- --skip packages` as the example. |
| `README.md:105` | "If `/etc/pam.d/sudo_local` doesn't exist yet, it's created to enable Touch ID" | mise declares the file and rewrites it when its content differs. |
| `README.md:242` | `"$DOTFILES/setup.sh" --skip-brew # drop --skip-brew to also install new Brewfile entries` | `"$DOTFILES/setup.sh"`, with `-- --skip packages` to leave packages alone. |
| `README.md:245` | "`setup.sh` installs what's missing but doesn't upgrade… the dependencies `brew bundle` upgrades on its own…" | Drop the `brew bundle` clause. Add that `./setup.sh -- --upgrade` upgrades packages and tools. |
| `setup/README.md:9` | "`../setup.sh` runs these in order: **brew → zsh → misc → symlinks**…" | mise's order, from `mise bootstrap --help`: packages, files, dotfiles, macOS defaults, login shell, tools, the `bootstrap` task. The new flag list. |
| `setup/README.md:11` | "After its `sudo -v` it exports `DOTFILES_SUDO_KEPT=1`… Sudo is held only around the steps that use it…" | One span of sudo. The `pre-tools` hook and `misc.sh` drop it. The `~/.config/mise` link and its failure message. |
| `setup/README.md:35-37` | The `## zsh` section | Three sentences on `[bootstrap.user]`. |
| `setup/README.md:41` | "Run on its own, it asks for sudo first; under `setup.sh` (`DOTFILES_SUDO_KEPT=1`) it skips that prompt." | It is the `bootstrap` task, runs on every bootstrap, never uses sudo, and warns instead of failing. |
| `setup/README.md:43` | "Installs the Xcode Command Line Tools if missing… It waits at most 30 minutes…" | `setup.sh` checks for them and stops with the command. |
| `setup/README.md:47` | "The script links that config into `~/.config/mise` and runs `mise install` before touching npm. It links `~/.config/mise` (and `~/.config/gh`…)…" | `setup.sh` links it. The `tools` part installs. Keep the version list. |
| `setup/README.md:60` | "Rust lived in mise before 2026-10-24…" to the end of the bullet | Delete. Part B owns it. |
| `setup/README.md:62` | "Pass `--skip-codegraph` to `setup.sh` (or set `DOTFILES_SKIP_CODEGRAPH=true`) to skip CodeGraph's mise install and this step" | Say the flag also sets `MISE_DISABLE_TOOLS`, and that a bare `mise bootstrap` needs both variables. |
| `CLAUDE.md:27` | "`./setup.sh --skip-brew`: re-apply the dotfiles… drop `--skip-brew` to also install the Brewfile." | `./setup.sh`: links the mise config, installs mise, runs `mise bootstrap`. Flags `-y`, `--skip-codegraph`, `--dash`, `-h`, `-- <mise args>`. Keep the log sentence. |
| `CLAUDE.md:39-40` | "setup.sh orchestrator → setup/{brew,zsh,misc,symlinks}.sh (+ dash.sh with --dash)" and the `setup/` line | `setup.sh` wrapper → `mise bootstrap` → `conf.d/*.toml`, task `setup/misc.sh`. |
| `CLAUDE.md:52` | "**Setup order**: `brew.sh` must run first…a sudo keep-alive loop, and telemetry opt-out exports." | mise is installed first and its part order is fixed. Constraints are in `.claude/rules/setup.md`. |
| `CLAUDE.md:87` | "telemetry opt-outs live in both `setup.sh` and `zsh/env.zsh`" | `setup/misc.sh` and `zsh/env.zsh`. |
| `CLAUDE.md:89` | "Re-running `setup.sh` is the normal way to apply changes." | Keep, and add "a run is not a transaction". |
| `.claude/rules/telemetry-sync.md:10` | "`setup.sh` exports a subset… fails the gate when a `setup.sh` export is missing… When the change touches `setup.sh`'s list" | `setup/misc.sh` in all three places. In its `paths:`, `setup.sh` becomes `setup/misc.sh`. |
| `docs/privacy.md:24` | "`setup.sh` exports the Microsoft ones…for the install run" | `setup/misc.sh`, the bootstrap task. |
| `docs/README.md:152`, `bin/dotfiles:4`, `bin/upup:210`, `docs/rea.md:48`, `.claude/skills/add-tool/SKILL.md:24` | "`setup.sh --skip-brew`" | "`setup.sh`". |
| `.claude/agents/docs-auditor.md:15` | "`tilde/.config/mise/config.toml`" in the repo-claims list | Add `tilde/.config/mise/conf.d/*.toml`. Add `mise bootstrap` to the forbidden list on line 16. |

`.claude/skills/docs-audit/SKILL.md` and `.serena/memories/core.md` are in the spec's table. No sentence in either becomes false. Confirm with `grep -n 'setup' <file>` and leave them.

- [ ] **Step 2: Replace `.claude/rules/setup.md` below its front matter**

```markdown
# Setup

- A closed stdin (non-interactive run) must mean "skip", never abort or overwrite.
- mise comes first. `setup.sh` links `~/dotfiles` and `~/.config/mise` into the clone, installs mise with its own installer when missing, checks the version floor and runs `mise bootstrap` from `$HOME`. Started inside the clone, mise reads `.nvmrc` and adds a node to the tools part.
- Not `--from` or `--adopt`: `--adopt` clones a whole repo into `~/.config/mise`, and `--from` loads the checkout root as a project and needs a matching `origin` (measured on 2026.11.5).
- The part order is mise's: packages, files, dotfiles, macOS defaults, login shell, tools, then the `bootstrap` task. Everything that needs root runs before `tools`. The `pre-tools` hook and the first line of `setup/misc.sh` run `sudo -k`, so nothing in `misc.sh` may call sudo (`test-bootstrap` asserts it).
- A run is not a transaction: a failed part leaves the earlier ones applied, and the fix is to rerun. Hooks and the task run on every bootstrap, so each `misc.sh` step checks state first and warns instead of failing.
- Hooks run in mise's environment without `[tools]`; the task has them. In a global fragment `{{ config_root }}` is `$HOME`, so hooks and the task find the repo as `${DOTFILES:-$HOME/dotfiles}`.
- Only one fragment may define `[tasks.bootstrap]`: a second definition replaces the first without a warning.
- Order constraints in `misc.sh`: `claude-config restore` and the catalog run last so `npx skills` runs with the npm settings (`min-release-age`, `allow-git none`). After the tools part it links `<mise data dir>/node_modules/typescript` to the global `npm:typescript` (`upup` relinks it). `chmod +x` skips `*.md` so `bin/CLAUDE.md` stays non-executable.
- `aspire certs trust` has no y/N prompt and macOS may ask for the password, so it is skipped when already trusted and only a hint when non-interactive.
- `--skip-codegraph` must leave an existing CodeGraph install untouched, including its mise shim: `setup.sh` sets `MISE_DISABLE_TOOLS` for the run and `misc.sh` reshims once without it.
- Every behavior change updates `setup/README.md` (and `README.md` for flags) in the same commit.
- A fresh install can't be verified on this machine. The `fresh-install` workflow is the test; say so when a change touches that path.
- Validate with `/validate-setup before`, then `./setup.sh` in a terminal (it is interactive), then `/validate-setup after`.
- `setup/bootstrap-runtime.svg` (embedded in `setup/README.md`) is generated by Archify from `setup/bootstrap-runtime.archify.json` (source line refs pinned to a commit). When step order, sudo use or download sources change, update the JSON, re-run `archify finalize` and re-export the SVG. Archify's per-run `.archify/` folder is gitignored; commit only the exported image.
```

Add `'tilde/.config/mise/conf.d/50-bootstrap.toml'` to its `paths:`.

- [ ] **Step 3: Replace `.claude/skills/validate-setup/SKILL.md`**

Keep the front matter keys. In `allowed-tools` add `Bash(mise bootstrap status*)` and `Bash(mise bootstrap --dry-run*)`. Change the description to "Snapshot the machine state `mise bootstrap` manages before and after `./setup.sh`, and diff the two, to verify a setup change." Body:

```markdown
Phase: $ARGUMENTS

- **before**: run `pnpm check` (stop and report if it fails), then `mkdir -p private/setup-snapshots` and `.claude/skills/validate-setup/snapshot.sh > private/setup-snapshots/before.txt`. Run `mise bootstrap --dry-run` and say what it would change. Tell the user to run `./setup.sh` (add `--skip-codegraph` if CodeGraph is irrelevant, `-- --skip packages` to leave packages alone) **in their own terminal**, since it prompts, and then invoke `/validate-setup after`. They don't need to paste the output: setup.sh records each run to `private/setup-logs/<timestamp>.log`.
- **after**:
  1. Run `.claude/skills/validate-setup/snapshot.sh > private/setup-snapshots/after.txt`, then `diff -u private/setup-snapshots/before.txt private/setup-snapshots/after.txt`. Explain every changed line: expected from the change under test, or a regression. No diff means setup was a no-op. Say whether that was expected.
  2. Run `mise bootstrap status --missing`. Exit 1 means a part still differs from the config: name each entry that isn't converged. A run is not a transaction, so a part that failed is fixed by rerunning `./setup.sh`.
  3. Read the newest log (`ls -t private/setup-logs/*.log`, first entry) and `grep -inE 'error|warn|deprecat|fail|not found'` it. Explain each hit (expected, harmless upstream noise, or a problem), and confirm the step under test printed what it should.
- Anything else: explain the two phases and stop.

Never run `./setup.sh` or `mise bootstrap` without `--dry-run` yourself.
```

In `snapshot.sh` add one section before the login shell section:

```bash
echo "## mise bootstrap status"
mise bootstrap status 2>&1
```

- [ ] **Step 4: Ask before `mise bootstrap`**

In `.claude/settings.json`, add `"Bash(mise bootstrap*)"` to `permissions.ask` if A3 to A5 did not. Task 1 Step 7 already asserts it.

- [ ] **Step 5: Point the fresh-install workflow at the entry point**

In `.github/workflows/fresh-install.yml` (from A4), keep A4's piecewise job and add a second manually triggered job, `entry-point`, that runs `./setup.sh -y --skip-codegraph` and then `MISE_DISABLE_TOOLS=npm:@colbymchenry/codegraph mise bootstrap status --missing`. The runner has no terminal, so `setup.sh` skips `sudo -v` and mise elevates with the runner's passwordless sudo. This is the only test of the mise installer path (D11). `pnpm check` lints the file with actionlint.

- [ ] **Step 6: Prove nothing stale is left**

Run: `grep -rnE -e '--skip-brew|DOTFILES_SUDO_KEPT|setup/zsh\.sh|brew → zsh|link_config_dir' --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=superpowers --exclude-dir=.archify . | grep -v 'bin/lib/test-bootstrap' | grep -v 'bootstrap-runtime'`
Expected: hits in `setup.sh` only, the `--skip-brew)` case and its "is gone" message.

Run: `pnpm check`
Expected: exit 0.

- [ ] **Step 7: Commit Tasks 1 and 2 together**

```bash
git add -A setup.sh setup/ tilde/.config/mise/conf.d/50-bootstrap.toml bin/ .claude/ .github/workflows/fresh-install.yml README.md CLAUDE.md docs/README.md docs/privacy.md docs/rea.md
git commit -m "Make setup.sh a wrapper around mise bootstrap"
```

### Task 3: Prune report in `upup`

A4 already upgrades packages in `upup` through `mise bootstrap packages upgrade` and compares `packages status --json` before and after. What is left for A6 is the prune report.

**Files:**
- Modify: `bin/upup` (after A4's `packages status` step), `bin/lib/test-upup`, `.claude/rules/upup.md`, `README.md` (the Updating list)

**Interfaces:**
- Consumes: `mise bootstrap packages prune --dry-run` prints one `remove <manager>:<name>@<version>` line per package and exits 0 (measured). With `-m brew-cask` it also prints `mise WARN  brew-cask:<name>: skipped: Homebrew owns this cask` lines, which are not removals (measured).
- Produces: one `upup` step, `packages prune`.

- [ ] **Step 1: Write the failing assertions in `bin/lib/test-upup`**

Extend A4's `mise` stub: `bootstrap packages prune --dry-run` prints `remove brew:old@1.0` and `remove brew:older@0.9` when `$STATE/undeclared` exists, prints nothing otherwise, and exits 1 when `$STATE/prune-report-fails` exists. Record every `bootstrap packages prune` call's arguments in `$STATE/prune-args.log`.

```bash
check_true "up to date: nothing undeclared" has '^✔ packages prune +nothing undeclared$'
check_true "undeclared: a notice with the command" has '^● packages prune +2 packages no config declares; review: mise bootstrap packages prune --dry-run$'
only_dry_runs() { ! grep -v -- --dry-run "$STATE/prune-args.log" | grep -q .; }
check_true "undeclared: upup never prunes" only_dry_runs
check_true "prune report fails: fail line names the command" has '^✖ packages prune +run: mise bootstrap packages prune --dry-run$'
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash bin/lib/test-upup`
Expected: `FAIL: up to date: nothing undeclared`.

- [ ] **Step 3: Implement `step "packages prune"` in `bin/upup`**

`capture mise bootstrap packages prune --dry-run`, then the same with `-m brew-cask`, and count the `^remove ` lines of both. Zero is `ok`, more is one `notice`, a non-zero exit is `fail`. The step never runs prune without `--dry-run`.

- [ ] **Step 4: Run the test**

Run: `bash bin/lib/test-upup`
Expected: every line starts with `ok:`.

- [ ] **Step 5: Docs**

`.claude/rules/upup.md`: add to A4's packages bullet that prune is reported and never run, because it removes every formula no config declares. `README.md`, Updating list: one bullet for the report and the command that removes.

- [ ] **Step 6: Commit**

```bash
pnpm check
git add bin/upup bin/lib/test-upup .claude/rules/upup.md README.md
git commit -m "Report undeclared packages in upup"
```

### Task 4: Regenerate the setup diagram

**Files:**
- Modify: `setup/bootstrap-runtime.archify.json`, `setup/bootstrap-runtime.svg`

**Interfaces:**
- Consumes: the commit from Task 2 (line references pin to it).
- Produces: the image `setup/README.md:5` embeds.

- [ ] **Step 1: Edit the JSON**

Set `meta.repository.revision` to `git rev-parse HEAD`. Remove the `brew`, `symlinks` and `homebrew` nodes and their edges. Add a `mise` node (`mise bootstrap`, sublabel `packages · files · dotfiles · defaults · shell · tools · task`, source `tilde/.config/mise/conf.d/50-bootstrap.toml`) between `setup` and `misc`. Repoint every `sources` entry to lines that exist now. The `system` node's sources become the `[bootstrap.files]` and `[bootstrap.user]` tables. Rewrite the cards: the primary path is `setup.sh → mise bootstrap → setup/misc.sh`, the trust card says sudo is held until the `pre-tools` hook, and the upup card says `mise bootstrap packages upgrade`.

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

### Task 5: Run it on this Mac

This task changes the machine. Stop and ask the user for an explicit go-ahead before Step 2. The Part B `setup` step for this phase must have landed first.

- [ ] **Step 1: Preview.** Run `/validate-setup before`. Read its `mise bootstrap --dry-run` output with the user.
- [ ] **Step 2: The user runs `./setup.sh` in their own terminal.**
- [ ] **Step 3: Check.** Run `/validate-setup after`, then:

| Command | Expected |
| --- | --- |
| `mise bootstrap status --missing; echo $?` | `0` |
| `sudo -n true; echo $?`, in the terminal that ran `setup.sh` | `1` (the credential was dropped) |
| `dscl . -read ~ UserShell` | `UserShell: /opt/homebrew/bin/zsh` |
| `cat /etc/pam.d/sudo_local` | `auth       sufficient     pam_tid.so` |
| `command -v codegraph` | still resolves |

- [ ] **Step 4: Second run changes nothing.** Copy `after.txt` to `before.txt`, have the user run `./setup.sh -y` again, take a new `after.txt`. `diff -u` is empty, and the new log has no line that reports an install, a link or a write outside the task's own "already" lines.
- [ ] **Step 5: Close the phase.** `git mv` this plan to `docs/superpowers/plans/completed/`, commit and push.

## Part B hook: what the `setup` step needs

Only the old method left these on disk. A6 carries no code for them.

- `/etc/pam.d/sudo_local` with other content. The old `setup.sh` created the file only when it was missing, so a hand-edited one survived. mise now rewrites it. B shows the diff, backs the file up and asks, before the first bootstrap.
- A leftover mise rust install (`~/.local/share/mise/installs/rust`) and a foreign `~/.cargo/bin/rustup`. The removal and the warning move out of `setup/misc.sh` (inventory M16, M17) into B.
- The `mise` MCP server registered with Homebrew's path. `register_mcp` in `misc.sh` only warns when the command differs from `$(command -v mise)`. B re-registers it: `claude mcp remove mise -s user`, then `claude mcp add --scope user mise -- "$(command -v mise)" mcp`.
- The log path did not move. `private/setup-logs/` stays, so B has nothing to remove there, and the spec's "old logs path" item can go.
- The `~/.config/mise` and `~/dotfiles` links the old method made are the ones the new `setup.sh` expects. Nothing to do.
