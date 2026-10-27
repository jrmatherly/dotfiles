# Shell Startup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut about 150 ms from every interactive shell, make the completion cache hit every day of the year, stop `path.zsh` dropping what `.zprofile` built, and fix the config entries that are dead or wrong on a second Mac.

**Architecture:** Each change lands in the `zsh/*.zsh` or `tilde/` file that owns it. Timings are measured before and after with the same probe (five interleaved runs of `zsh -i -c exit` under a scratch `ZDOTDIR`, median reported), and behavioral invariants go into `bin/lib/test-shell` from `2026-10-27-agent-shell-and-secrets-hardening.md` Task 1, which must land first.

**Tech Stack:** zsh, `bin/lib/test-shell`, `/usr/bin/time`, `EPOCHREALTIME`.

**Spec:** `docs/superpowers/specs/2026-10-27-repo-audit-assessment.md`, section D (D1 to D16; D8 is done by the hardening plan's Task 8).

## Global Constraints

- Depends on `bin/lib/test-shell` (hardening plan, Task 1). Each task's assertion goes there; a tool the CI runner lacks makes the assertion skip with a stderr line, never fail.
- Timing claims in commit messages name the probe and the median of five runs at trunk and at head, interleaved (the **benchmark-checklist** rule: trunk first, same machine, same probe).
- `CLAUDE.md`'s zsh bullet and `docs/README.md` are edited in the same commit when load order or an alias changes.
- One task, one commit, `pnpm check` green, trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` (omitted below). No em-dash characters.

## Review Focus

1. A Mac without Homebrew (`.zprofile` guard, Task 8): a login shell must start without an error line.
2. January 1 to April 9 (`%j` below 100): `compinit -C` must be the branch taken when the dump is from today (Task 1's test uses a fixed day string).
3. A shell started by VS Code or Finder (login, non-interactive), then an interactive child: the child must keep SnippetsLab's `lab` and anything the parent exported (Task 3).
4. SSH sessions: `git commit` must open `nano`, not wait on CotEditor (Task 5).
5. `fast-theme` after the theme file changes: the new theme must apply on the next shell (Task 6's test touches the ini).

---

### Task 1: Completion cache that hits every day (D1)

**Files:**
- Modify: `zsh/completion.zsh:20-26`
- Modify: `bin/lib/test-shell`

- [x] **Step 1: Add the failing assertion**

The decision logic becomes a function `zcompdump_is_stale <dumpfile>` so the test can call it with a fake day. Test:

```bash
touch "$tmp/dump"
user_zsh "source $root/zsh/completion.zsh; today=027; zcompdump_is_stale $tmp/dump && echo stale || echo fresh" | grep -qx fresh || fail "compinit cache miss on a day below 100"
```

(The function reads `${today:-$(date +%j)}` so the test can pin the day; `stat -f %Sm -t %j` gives the file's day.)

- [x] **Step 2: Run it and watch it fail** (today's string compare says stale).

- [x] **Step 3: Rewrite the check** as an arithmetic compare: `(( ${today:-$(date +%j)} != $(stat -f '%Sm' -t '%j' "$1") ))`, drop the invalid `date +'%j' -r` attempt.

- [x] **Step 4: Measure**: `for i in 1 2 3 4 5; do /usr/bin/time -p zsh -i -c exit; done 2>&1 | grep real` at trunk and head on a day below 100 (or with `today` pinned); expect roughly 300 ms less on those days.

- [x] **Step 5: `pnpm check`, commit**: `git commit -m "Compare completion dump days as numbers"`.

### Task 2: One `brew --prefix` per shell (D2)

**Files:**
- Modify: `zsh/init.zsh:5-11`

- [ ] **Step 1: Baseline**: five runs of `zsh -i -c exit`, note the median.
- [ ] **Step 2: Change `source_brew_plugin`** to use `${HOMEBREW_PREFIX:-/opt/homebrew}` (exported by `brew shellenv` in `.zprofile`) instead of `$(brew --prefix)`.
- [ ] **Step 3: Assertion** in `test-shell`: `user_zsh 'whence -w _zsh_autosuggest_start' | grep -q function` when `brew --prefix zsh-autosuggestions` exists (skip otherwise).
- [ ] **Step 4: Measure again**, five runs interleaved with trunk; commit with both medians: `git commit -m "Use HOMEBREW_PREFIX for the zsh plugins"`.

### Task 3: `path.zsh` builds on the inherited PATH (D3)

**Files:**
- Modify: `zsh/path.zsh:3-5`
- Modify: `tilde/.zprofile` (only if an entry must move)

- [ ] **Step 1: Add the failing assertion**: `user_zsh 'echo $PATH' | tr : '\n' | grep -qx /Applications/SnippetsLab.app/Contents/Helpers` when that directory exists; and `FOO_PATH_PROBE=$tmp/probe-bin user_zsh 'echo $PATH'` contains the probe dir when it is prepended to `PATH` before launching (`PATH=$tmp/probe-bin:$PATH user_zsh …`).
- [ ] **Step 2: Watch it fail** (`getconf PATH` reset).
- [ ] **Step 3: Fix**: replace the reset with `typeset -U path` deduplication only; keep every `prepend`. The comment explains that `.zprofile` already builds the base PATH and `prepend` moves our entries to the front.
- [ ] **Step 4: Check nothing regressed**: `user_zsh 'echo $PATH'` still has mise shims first, then pnpm, then `$DOTFILES/bin`, and `whence -p rust-analyzer` is `/opt/homebrew/bin/rust-analyzer`.
- [ ] **Step 5: `pnpm check`, commit**: `git commit -m "Keep the login PATH in interactive shells"`.

### Task 4: `NPM_CONFIG_INIT_AUTHOR_NAME` reads the included identity (D4)

**Files:**
- Modify: `zsh/env.zsh:176`

- [ ] **Step 1: Assertion**: `[ -n "$(user_zsh 'echo -n $NPM_CONFIG_INIT_AUTHOR_NAME')" ]` when `~/.gitconfig.local` sets `user.name` (skip otherwise).
- [ ] **Step 2: Fix**: `git config --global --includes user.name`.
- [ ] **Step 3: `pnpm check`, commit**: `git commit -m "Read the npm init author through git's includes"`.

### Task 5: SSH sessions get a terminal git editor (D5)

**Files:**
- Modify: `tilde/.gitconfig:25` (delete `editor = cot --wait`), `zsh/env.zsh:18-23` (export `GIT_EDITOR="$EDITOR --wait"` locally is wrong for nano; set `GIT_EDITOR=cot --wait` in the non-SSH branch and `GIT_EDITOR=nano` in the SSH branch)
- Modify: `tilde/README.md` (the git editor sentence, if present)

- [ ] **Step 1: Assertion**: `SSH_CONNECTION=1 user_zsh 'echo $GIT_EDITOR'` is `nano`; without it, `cot --wait`.
- [ ] **Step 2: Fix both files**, run `git var GIT_EDITOR` in a fresh shell to confirm the value.
- [ ] **Step 3: `pnpm check`, commit**: `git commit -m "Pick the git editor per session instead of in gitconfig"`.

### Task 6: `fast-theme` runs only when the theme changed (D6)

**Files:**
- Modify: `zsh/init.zsh:24-29`

- [ ] **Step 1: Assertion**: after `touch "$root/colors/fast-syntax-highlighting.ini"`, `user_zsh 'echo $FAST_THEME_NAME'` names the repo theme; a second shell start without touching does not rewrite `${XDG_CACHE_HOME:-$HOME/.cache}/fsh/*` (compare `stat -f %m` before and after).
- [ ] **Step 2: Fix**: apply `fast-theme` only when the ini is newer than the stored theme file (`[[ $ini -nt $FAST_WORK_DIR/current_theme.zsh ]]`; check the plugin's actual stored-theme path with `fast-theme -l` and `echo $FAST_WORK_DIR` first).
- [ ] **Step 3: Measure** five runs, commit with both medians: `git commit -m "Apply fast-theme only when the theme file changed"`.

### Task 7: Small fixes that need no measurement (D9, D10, D11, D13, D14, D15)

**Files:**
- Modify: `zsh/fzf.zsh:63-64,71`, `zsh/env.zsh:10,167`, `zsh/aliases.zsh:76`, `tilde/.gitconfig:41`
- Modify: `docs/README.md` (the `lg` row if its description changes)

- [ ] **Step 1: fzf**: guard the source with `[[ -o zle ]] &&`; delete the dead `llt` case. Assertion: `user_zsh 'true' 2>&1 | grep -c "can't change option"` is 0.
- [ ] **Step 2: TERM**: export `xterm-256color` only when `SSH_CONNECTION` is set. Assertion: `TERM=xterm-ghostty user_zsh 'echo $TERM'` prints `xterm-ghostty`.
- [ ] **Step 3: lazygit**: export `LG_CONFIG_FILE="$DOTFILES/lazygit/config.yml"` and reduce the alias to `alias lg=lazygit`. Verify `lazygit --print-config-dir` or `lg` opens with the repo theme.
- [ ] **Step 4: azd**: export `AZD_BICEP_TOOL_PATH` only when the file exists.
- [ ] **Step 5: git autoCorrect**: `autoCorrect = prompt`.
- [ ] **Step 6: `pnpm check`, one commit**: `git commit -m "Tidy the fzf, TERM, lazygit, azd and git autocorrect settings"`.

### Task 8: `.zprofile` survives a Mac without Homebrew (D12)

**Files:**
- Modify: `tilde/.zprofile:5`

- [ ] **Step 1: Assertion**: `env -i HOME=$HOME ZDOTDIR=$tmp zsh -l -c true 2>&1` with `$tmp/.zprofile` sourcing the repo's `.zprofile` and `PATH=/usr/bin:/bin` prints nothing (no `no such file` line) when `/opt/homebrew/bin/brew` is temporarily shadowed; simplest: assert the file's eval line is wrapped in `[[ -x /opt/homebrew/bin/brew ]]` via `test-conventions`, since the runner has Homebrew.
- [ ] **Step 2: Fix and commit**: `git commit -m "Guard brew shellenv in .zprofile"`.

### Task 9: Settle the write-back guesses (D16)

- [ ] **Step 1: btop**: run `btop`, quit, `git status --short tilde/.config/btop`. A diff means btop rewrites its tracked config on exit; then either commit the 1.4.8 rewrite once and set `save_config_on_exit = false`, or stop tracking it. No diff: nothing to do, note it in `tilde/README.md`.
- [ ] **Step 2: tlrc**: `cd $(mktemp -d) && tldr --config ~/.tlrc.toml --info`. If a `.tlrc/` appears in that directory, change `dir` in `tilde/.tlrc.toml` to `~/.cache/tlrc` (tlrc expands `~`; confirm with `tldr --info` afterwards).
- [ ] **Step 3: Commit** any change: `git commit -m "Pin the tldr cache dir"`.

### Task 10: Report the total (D7)

- [ ] **Step 1:** Five interleaved runs of `zsh -i -c exit` at the plan's start SHA and at head; record both medians and the per-section split (`EPOCHREALTIME` around each `source` in a scratch `.zshrc`) in the final commit message or in `tilde/README.md`'s shell section.

---

## Self-review notes

- Spec coverage: D1 Task 1, D2 Task 2, D3 Task 3, D4 Task 4, D5 Task 5, D6 Task 6, D7 Task 10, D9 to D11 and D13 to D15 Task 7, D12 Task 8, D16 Task 9, D8 in the hardening plan.
- Tasks 2, 6 and 10 carry timing claims and name the probe; Task 1's saving applies only on days below 100, which the commit message must say.
- Review Focus items map to Tasks 8, 1, 3, 5, 6.
