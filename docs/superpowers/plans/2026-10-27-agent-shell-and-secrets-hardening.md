# Agent Shell and Secrets Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the interactive shell from handing agents and child processes a GitHub token, a hijacked `cd`, a broken `source`, an auto-installing `git clone` and a permissive Claude Code allowlist, with a self-check that keeps them gone.

**Architecture:** Every shell fix lands in the `zsh/*.zsh` file that owns the behavior, gated on `CLAUDECODE` where agents and people need different behavior, in the style of the existing `CLAUDECODE` blocks in `zsh/aliases.zsh:196-198` and `zsh/options.zsh:76-78`. A new `bin/lib/test-shell` self-check boots the repo's zsh config under a scratch `ZDOTDIR`, once as an agent shell and once as a user shell, and asserts each invariant; `bin/lib/check` runs it. Permission changes go to the tracked `agents/claude-settings.json` and the project `.claude/settings.json`, with `bin/lib/test-conventions` asserting the rules that must never return.

**Tech Stack:** zsh (Homebrew), bash 3.2 for the self-checks, jq, Claude Code 2.1.310 permission rules.

**Spec:** `docs/superpowers/specs/2026-10-27-repo-audit-assessment.md`, section A (A1 to A8, A10, A12, A13). A9 is in `2026-10-27-bin-script-fixes.md`; A11 in `2026-10-27-setup-robustness.md`; A14 and A15 in `2026-10-27-packages-ci-and-docs.md`.

## Global Constraints

- Scripts start with `#!/bin/bash`, a header comment block, `set -euo pipefail`, inline output helpers, no sourced library. New `bin/lib/test-*` files are `chmod +x` and are already in `bin/lib/check`'s shellcheck list (`bin/lib/check:12`).
- The gate is `pnpm check` (never a bare `bin/lib/check`). The commit-gate hook runs it before every `git commit` from Claude's shell.
- Every behavior change gets its doc edit in the same commit: `docs/README.md` for alias rows, `CLAUDE.md`'s zsh bullet for what agent shells drop, `agents/README.md` for the tracked settings, `.claude/rules/claude-config.md` for project permissions, `setup/Brewfile` comments that name an alias.
- The live `~/.claude/settings.json` is changed only through `/permissions` (to remove a rule) and `bin/claude-config restore settings` (to add rules), then `bin/claude-config save` must leave `git diff agents/` empty.
- Commit subjects: short, imperative, sentence case, no prefix. Each commit ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` (omitted from the snippets below).
- No em-dash characters in prose or comments. Prettier ignores zsh files; the lint hook shellchecks `bin/lib/test-*`.
- zsh assertions run against the repo tree through `ZDOTDIR`, never against `~/.zshrc`, so they hold on the CI runner too. An assertion that needs a tool the runner lacks (zoxide, gh, rg) skips with a line on stderr when `command -v` fails.

## Review Focus

1. A user shell that still needs `GITHUB_TOKEN` for a private registry: after Task 3 nothing exports it, so `npm install` against such a registry fails with a 401 rather than silently using a stale token. Task 3's test asserts the user shell has no token either, and the task documents the per-command form.
2. `git clone` with flags before the URL (`git clone --depth 1 URL`): the wrapper must not `cd` into `1`. Task 5's test covers it.
3. A fresh Mac without zoxide, fzf, gh or rg: every assertion must skip, not fail. Task 1's harness checks `command -v` per tool.
4. A `Read` deny rule written with the wrong prefix (`/vscode/...` is project-relative, `//` is absolute, `~/` is home) silently denies nothing. Task 9's step verifies each rule shape against the permissions doc before committing.
5. Removing `Bash(curl:*)` from the live settings while the tracked file still has it: `restore settings` would add it back. Task 9 edits the tracked file first and asserts the live file matches after `save`.

---

### Task 1: Shell self-check harness, and `.` sources again (A3)

**Files:**
- Create: `bin/lib/test-shell`
- Modify: `bin/lib/check:64-66` (add the new self-check next to `test-upup`)
- Modify: `zsh/aliases.zsh:7`
- Modify: `docs/README.md:65`

**Interfaces:**
- Produces: `bin/lib/test-shell` with two functions later tasks call. `agent_zsh '<zsh code>'` runs it in an interactive zsh with `CLAUDECODE=1` and `ZDOTDIR=$tmp`; `user_zsh '<zsh code>'` runs it with `CLAUDECODE` unset. Both print stdout only, and return the shell's exit code. `need <tool>` returns 1 and prints `skip: <tool> not installed` to stderr when `command -v` fails. `fail '<msg>'` exits 1.

- [ ] **Step 1: Write the harness and the failing assertion**

`$tmp/.zshenv` holds `export DOTFILES=<repo root>`; `$tmp/.zshrc` holds `source "$DOTFILES/tilde/.zshrc"`. The first assertion:

```bash
printf 'echo sourced-ok\n' > "$tmp/s.zsh"
[ "$(agent_zsh ". $tmp/s.zsh")" = sourced-ok ] || fail "agent shell: . does not source"
[ "$(user_zsh ". $tmp/s.zsh")" = sourced-ok ] || fail "user shell: . does not source"
```

End the script with `echo "shell: all checks passed"`.

- [ ] **Step 2: Run it and watch it fail**

Run: `bash bin/lib/test-shell`
Expected: `FAIL: agent shell: . does not source`, exit 1.

- [ ] **Step 3: Rename the alias**

In `zsh/aliases.zsh:7` change `alias .=` to `alias here=`; keep the printf and `pwd`. In `docs/README.md:65` change the row's command to `` `here` ``.

- [ ] **Step 4: Run the self-check and the gate**

Run: `bash bin/lib/test-shell && pnpm check`
Expected: `shell: all checks passed`, then the gate exits 0 (add `bash bin/lib/test-shell > /dev/null` to `bin/lib/check` under the `test-upup` line first).

- [ ] **Step 5: Commit**

```bash
git add bin/lib/test-shell bin/lib/check zsh/aliases.zsh docs/README.md CLAUDE.md
git commit -m "Add a shell self-check and stop aliasing the source builtin"
```

Add `bin/lib/test-shell` to the `pnpm check` list in `CLAUDE.md` in the same commit.

### Task 2: Plain `cd` in agent shells (A4)

**Files:**
- Modify: `zsh/init.zsh:37-40`
- Modify: `bin/lib/test-shell`
- Modify: `CLAUDE.md` (the zsh load-order bullet's `CLAUDECODE` sentence)

- [ ] **Step 1: Add the failing assertion**

```bash
if need zoxide; then
  out=$(agent_zsh 'cd /tmp && cd no-such-dir-$$ 2> /dev/null; pwd')
  [ "$out" = /tmp ] || fail "agent shell: cd jumped to $out"
  user_zsh 'whence -w z | grep -q function' || fail "user shell: z is not defined"
fi
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash bin/lib/test-shell`
Expected: `FAIL: agent shell: cd jumped to /Users/jason/dev/dotfiles` (or another frecency match).

- [ ] **Step 3: Gate the `--cmd cd` flag on `CLAUDECODE`**

In `zsh/init.zsh` replace the single `eval "$(zoxide init --cmd cd zsh)"` with: agent shells (`[[ -n $CLAUDECODE ]]`) get `zoxide init zsh` (defines `z` and `zi` only), user shells keep `--cmd cd`. One comment line on why.

- [ ] **Step 4: Run the self-check and the gate**

Run: `bash bin/lib/test-shell && pnpm check`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add zsh/init.zsh bin/lib/test-shell CLAUDE.md
git commit -m "Keep the stock cd in agent shells"
```

### Task 3: Stop exporting the GitHub token (A1)

**Files:**
- Modify: `zsh/env.zsh:169-173`
- Modify: `bin/lib/test-shell`
- Modify: `docs/privacy.md` (one line under the GitHub CLI entry, if present, else the Tools list)

Decision recorded here: `~/.npmrc` holds a literal registry token and does not reference `GITHUB_TOKEN` (`grep -c GITHUB_TOKEN ~/.npmrc` is 0, measured 2026-10-27), so no shell consumer needs the export. The one named consumer, giget, takes `GIGET_AUTH` per command.

- [ ] **Step 1: Add the failing assertion**

```bash
if need gh; then
  [ -z "$(agent_zsh 'echo -n $GITHUB_TOKEN$GIGET_AUTH')" ] || fail "agent shell exports a GitHub token"
  [ -z "$(user_zsh 'echo -n $GITHUB_TOKEN$GIGET_AUTH')" ] || fail "user shell exports a GitHub token"
fi
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash bin/lib/test-shell`
Expected: `FAIL: agent shell exports a GitHub token`.

- [ ] **Step 3: Delete the export block**

Remove `zsh/env.zsh:169-173` (the comment and the `if command -v gh` block). Add a two-line comment in its place: tools that need the token get it per command, `GITHUB_TOKEN=$(gh auth token) giget …`, and why (every child process would otherwise inherit a `repo` + `workflow` token).

- [ ] **Step 4: Run the self-check and the gate**

Run: `bash bin/lib/test-shell && pnpm check`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add zsh/env.zsh bin/lib/test-shell docs/privacy.md
git commit -m "Stop exporting the GitHub token into every shell"
```

### Task 4: Agent shells get the stock `git`, and the wrapper keeps every argument (A5, A12)

**Files:**
- Modify: `zsh/aliases.zsh:155-178` and the `CLAUDECODE` block at `:196-198`
- Modify: `bin/lib/test-shell`
- Modify: `docs/README.md` (the `git` row, if the index describes the clone behavior)

- [ ] **Step 1: Add the failing assertions**

```bash
[ "$(user_zsh 'git rev-parse --sq-quote "" "a b"')" = " '' 'a b'" ] || fail "git wrapper drops empty args"
agent_zsh 'whence -w git' | grep -q command || fail "agent shell still has the git wrapper"
! grep -qE 'yarn|pnpm install|npm install|bun install' zsh/aliases.zsh || fail "git clone still auto-installs"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash bin/lib/test-shell`
Expected: `FAIL: git wrapper drops empty args`.

- [ ] **Step 3: Rewrite the wrapper**

Signature stays `git()`. Body: when `"$1"` is `clone`, run `command git clone "${@:2}"`, then `cd` into the clone only when the last argument is an existing directory after the clone (`[ -d "${@: -1}" ]`), else into `$(basename "${@: -1}" .git)` when that exists. No package install. Otherwise `command git "$@"`. In the `CLAUDECODE` block add `unfunction git 2> /dev/null`.

- [ ] **Step 4: Run the self-check and the gate**

Run: `bash bin/lib/test-shell && pnpm check`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add zsh/aliases.zsh bin/lib/test-shell docs/README.md
git commit -m "Quote the git wrapper's arguments and drop its clone-time install"
```

### Task 5: Drop `protocol.file.allow = always` (A6)

**Files:**
- Modify: `tilde/.gitconfig:90-92`
- Modify: `bin/lib/test-conventions`
- Modify: `tilde/README.md` (only if it documents the setting)

- [ ] **Step 1: Add the failing assertion to `test-conventions`**

```bash
! grep -qE '^\s*allow\s*=\s*always' tilde/.gitconfig || fail "gitconfig: protocol.file.allow = always (CVE-2022-39253)"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash bin/lib/test-conventions`
Expected: `FAIL: gitconfig: protocol.file.allow = always`.

- [ ] **Step 3: Delete the section**

Remove `tilde/.gitconfig:90-92`. Where a local clone needs it, the form is `git -c protocol.file.allow=always clone …`; put that in the comment block above `[protocol]`'s former place only if the file keeps a comment there.

- [ ] **Step 4: Run the gate**

Run: `pnpm check`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add tilde/.gitconfig bin/lib/test-conventions
git commit -m "Restore git's default file protocol policy"
```

### Task 6: Honest curl defaults (A7)

**Files:**
- Modify: `tilde/.curlrc:8,17`
- Modify: `bin/lib/test-conventions`

- [ ] **Step 1: Add the failing assertion**

```bash
! grep -qE '^(user-agent|referer)' tilde/.curlrc || fail "curlrc: spoofed user-agent or auto referer"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash bin/lib/test-conventions`
Expected: `FAIL: curlrc: spoofed user-agent or auto referer`.

- [ ] **Step 3: Delete both lines and their comments**

Keep `connect-timeout`, `progress-bar` and `show-error`.

- [ ] **Step 4: Verify live**

Run: `curl -s https://httpbin.org/user-agent`
Expected: a `curl/<version>` agent.

- [ ] **Step 5: Commit**

```bash
git add tilde/.curlrc bin/lib/test-conventions
git commit -m "Stop curl spoofing its user agent and sending referers"
```

### Task 7: ripgrep output agents can parse (A10)

**Files:**
- Modify: `tilde/.ripgreprc:21`
- Modify: `zsh/env.zsh:195-196`
- Modify: `bin/lib/test-shell`

- [ ] **Step 1: Add the failing assertion**

```bash
if need rg; then
  agent_zsh "cd $root && rg -n fsmonitor tilde/.gitconfig" | grep -qE '^tilde/\.gitconfig:[0-9]+:' || fail "agent rg output is not path:line:text"
fi
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash bin/lib/test-shell`
Expected: `FAIL: agent rg output is not path:line:text`.

- [ ] **Step 3: Fix both sides**

Delete `--field-match-separator=` from `tilde/.ripgreprc`. In `zsh/env.zsh` export `RIPGREP_CONFIG_PATH` only when `CLAUDECODE` is unset, with a one-line comment (agents expect stock `rg`, like the aliases dropped in `aliases.zsh`).

- [ ] **Step 4: Run the self-check and the gate**

Run: `bash bin/lib/test-shell && pnpm check`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add tilde/.ripgreprc zsh/env.zsh bin/lib/test-shell CLAUDE.md
git commit -m "Give agent shells stock rg output"
```

### Task 8: `ld` and `where` no longer shadow (A12, D8)

**Files:**
- Modify: `zsh/aliases.zsh:46,73`
- Modify: `docs/README.md:97`
- Modify: `setup/Brewfile:58` (the `(zsh `ld` alias)` comment)
- Modify: `bin/lib/test-shell`

- [ ] **Step 1: Add the failing assertion**

```bash
! user_zsh 'alias ld' > /dev/null 2>&1 || fail "ld alias shadows the linker"
[ "$(user_zsh 'whence -w where')" = "where: builtin" ] || fail "where is not the builtin"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash bin/lib/test-shell`
Expected: `FAIL: ld alias shadows the linker`.

- [ ] **Step 3: Rename `ld` to `lzd`, delete the `where` alias**

Update the `docs/README.md` row and the Brewfile comment to `lzd`.

- [ ] **Step 4: Run the self-check and the gate**

Run: `bash bin/lib/test-shell && pnpm check`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add zsh/aliases.zsh docs/README.md setup/Brewfile bin/lib/test-shell
git commit -m "Rename the ld alias and drop the where alias"
```

### Task 9: Tighten the tracked Claude Code permissions (A2, A8)

**Files:**
- Modify: `agents/claude-settings.json` (`permissions.allow`, `permissions.ask`, `permissions.deny`)
- Modify: `.claude/settings.json` (`permissions.deny`)
- Modify: `bin/lib/test-conventions`
- Modify: `agents/README.md`, `.claude/rules/claude-config.md` (permissions bullets)

Decision recorded here, change it before Step 3 if you disagree: `curl` and `gh api` move from `allow` to `ask`; bare `WebFetch` leaves `allow` (prompts per domain; add `WebFetch(domain:…)` rules for the docs hosts you use most). `git add` stays allowed and `git add -f` is denied.

- [ ] **Step 1: Add the failing assertions to `test-conventions`**

```bash
for rule in 'Bash(curl:*)' 'Bash(gh api:*)' 'WebFetch'; do
  jq -e --arg r "$rule" '.permissions.allow | index($r) == null' agents/claude-settings.json > /dev/null \
    || fail "claude-settings allow: $rule"
done
for rule in 'Read(~/.ssh/**)' 'Read(~/.aws/**)' 'Read(~/.config/gh/hosts.yml)' 'Read(**/.env)' 'Read(**/.env.*)' 'Bash(git add -f*)' 'Bash(git add --force*)'; do
  jq -e --arg r "$rule" '.permissions.deny | index($r) != null' agents/claude-settings.json > /dev/null \
    || fail "claude-settings deny missing: $rule"
done
for rule in 'Read(/vscode/User/History/**)' 'Read(/vscode/User/workspaceStorage/**)' 'Read(/vscode/User/globalStorage/**)'; do
  jq -e --arg r "$rule" '.permissions.deny | index($r) != null' .claude/settings.json > /dev/null \
    || fail "project deny missing: $rule"
done
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash bin/lib/test-conventions`
Expected: `FAIL: claude-settings allow: Bash(curl:*)`.

- [ ] **Step 3: Edit the tracked files**

In `agents/claude-settings.json` remove the three allow entries, add `Bash(curl *)` and `Bash(gh api *)` to `ask`, add the seven deny rules. In `.claude/settings.json` add the three project deny rules. Check each rule shape against the permissions doc (`~/.claude-code-docs/cache/claude-code__permissions.md`, "Read and Edit rules" and "Wildcard patterns") before saving. Keep both files `jq .`-clean and the lists sorted.

- [ ] **Step 4: Apply to the live settings**

Remove `Bash(curl:*)`, `Bash(gh api:*)` and `WebFetch` from `~/.claude/settings.json` through `/permissions` in an interactive `claude`, then run `bin/claude-config restore settings` and `bin/claude-config save`.
Run: `git diff --stat agents/`
Expected: no output (live and tracked agree).

- [ ] **Step 5: Run the gate, then commit**

Run: `pnpm check`

```bash
git add agents/claude-settings.json .claude/settings.json bin/lib/test-conventions agents/README.md .claude/rules/claude-config.md
git commit -m "Ask before curl and gh api, deny credential paths and VS Code state"
```

### Task 10: Decide the SSH identity policy (A13)

**Files:**
- Modify: `tilde/.ssh/config:23-24` (only if the decision is to change it)

No default change. `IdentitiesOnly yes` under `Host *` with the 1Password agent means every host needs its own `IdentityFile` in `config.local`, or ssh offers nothing. The current layout pins only github.com. Record the choice in `tilde/README.md`'s SSH paragraph either way.

- [ ] **Step 1: Decide**: keep (default) or pin per host.
- [ ] **Step 2: If pinning**: add `IdentitiesOnly yes` under `Host *` and an `IdentityFile` per host in `~/.ssh/config.local`; verify with `ssh -G <host> | grep -E 'identitiesonly|identityfile'` for each host you use.
- [ ] **Step 3: Commit** the README line (and the config, if changed): `git commit -m "Document the SSH identity policy"`.

---

## Self-review notes

- Spec coverage: A1 Task 3, A2 Task 9, A3 Task 1, A4 Task 2, A5 Task 4, A6 Task 5, A7 Task 6, A8 Task 9, A10 Task 7, A12 Tasks 2, 4, 7 and 8, A13 Task 10. A9, A11, A14 and A15 are owned by the other plans named in the header.
- Each task is one commit and leaves `pnpm check` green; the self-checks are the regression lock.
- Review Focus items 1 to 5 map to Tasks 3, 4, 1, 9 and 9.
