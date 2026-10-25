# Claude Code Guardrails Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the repo's prompt-only conventions into deterministic checks (a commit gate hook, gate tests, permission rules, a read-only guard for the auditor) and slim the always-loaded instructions into path-scoped rules.

**Architecture:** Each convention moves to the lowest layer that can hold it: a permission rule where one rule expresses it, a PreToolUse hook (exit 2) where a script must decide, a `bin/lib/test-*` script run by `bin/lib/check` for tree invariants, and a `.claude/rules/*.md` file with `paths:` for guidance tied to a directory. Every hook and test ships with a fixture self-check in the existing `test-lint-edited.sh` / `test-upup` style, and the gate runs those self-checks.

**Tech Stack:** bash 3.2 (macOS `/bin/bash`), jq, shellcheck, Prettier with prettier-plugin-sh, Claude Code 2.1.310 hooks and permission rules.

**Spec:** `docs/superpowers/specs/2026-10-25-claude-code-guardrails-assessment.md`

## Global Constraints

- Scripts start with `#!/bin/bash`, a header comment block in the `bin/CLAUDE.md` shape, `set -euo pipefail` for tests (`set -uo pipefail` for hooks, which must not die on a failing check), inline output helpers, no sourced library.
- The gate is `pnpm check`, never a bare `bin/lib/check`: `check:57` calls `prettier`, which is only on PATH under `pnpm` (a bare run exits 127, measured). Until Task 1 lands, run it as `LC_ALL=en_US.UTF-8 pnpm check`.
- Every behavior change gets its doc edit in the same commit: `CLAUDE.md` for the Claude config bullets (which move to `.claude/rules/claude-config.md` in Task 8), `README.md` only where it already describes the thing (it does not describe hooks or the gate's tests), `agents/README.md` for the tracked settings snapshot.
- Hooks enforce with `exit 2`; exit 1 is non-blocking (hooks doc). A hook that times out or crashes lets the call through unless the handler sets `"onFailure": "block"` (hooks doc "Block the action when a hook fails", v2.1.295+). Hook JSON goes to stdout only, one object, nothing else. Hooks reference scripts as `${CLAUDE_PROJECT_DIR}/.claude/hooks/<name>.sh` with `"args": []` (exec form), like the two existing entries in `.claude/settings.json:39-66`.
- The live user settings file `~/.claude/settings.json` is never edited by hand or by `jq` in this plan. Permission rules are added to the tracked `agents/claude-settings.json` and applied with `bin/claude-config restore settings`, which unions the `allow`, `deny` and `ask` lists with the live values winning (`bin/claude-config:168-173`).
- New hook scripts and test scripts are `chmod +x`; `.claude/hooks/*.sh` and `bin/lib/test-*` are already in the gate's shellcheck list (`bin/lib/check:12-13`).
- Commit subjects: short, imperative, sentence case, no conventional-commit prefix. Every commit in this plan ends with the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`; the `git commit -m` snippets below omit it for brevity, add it each time.
- Prettier ignores `CLAUDE.md`, `.claude/settings.local.json` and `docs/superpowers/` (`.prettierignore`); the lint hook formats every other edited `.md`, `.json` and `.sh` file on save.
- No em-dash characters in new prose or comments.

## Rollback and escape hatches

- A hook that blocks wrongly: run the session with `claude --settings '{"disableAllHooks": true}'` (turns off every hook for that run), fix the script, run its self-check, then start normally. `disableAllHooks` in a settings file does the same persistently (settings reference).
- A settings syntax error: Claude Code skips the malformed file with a "Settings Warning" and keeps the rest; a broken `.claude/settings.json` therefore silently drops the project's deny and ask rules until fixed (settings doc "Fix a broken settings file"). Validate with `jq . .claude/settings.json` after every edit.
- A deny rule that matches too much: `bin/claude-config restore settings` cannot remove rules, so delete the rule from `~/.claude/settings.json` through the `/permissions` UI, then `bin/claude-config save`.
- Any task: `git revert` the task's commit; every task is one commit.

## Review Focus

1. A commit command spelled differently from `git commit -m` (`git -C . commit`, `git -c k=v commit`, `/usr/bin/git commit`, `GIT_EDITOR=true git commit`, `git add x && git commit`) must still trigger the gate; a command that merely mentions the word (`gh pr view --json commits`, `pre-commit run`, `echo "git commit"`, `git commit-tree`) must not. `git log --grep commit` triggers it, an accepted false positive that only costs a gate run. Test in Task 5.
2. The gate must pass under `LC_ALL=C` and under an unset locale, since Claude's Bash shell sets none; a regression here fails every commit through the hook. Test in Task 1.
3. The auditor guard must deny a write hidden behind an allowed prefix (`cat x > y`, `jq . a | tee b`, `git log; rm x`, `ls $(rm x)`, `find . -delete`, `gh api -X DELETE`) and must allow quoted pipes and quoted `>` (`jq '.a | keys'`, `grep -E 'a|b'`, `grep '=>'`), `2>&1` and `> /dev/null`. Test in Task 6.
4. A Brewfile line that qualifies a package with a tap but spells trust wrongly (`trusted:true`, `Trusted: true`) must fail the trust check. Test in Task 3.
5. The hook self-checks create files under the repo; they must clean up on failure too, or a failed run dirties the tree for the next `pnpm check`. Covered by the `trap ... EXIT` pattern in Task 5 and Task 6 tests; verified by the "break it" steps.

---

### Task 1: Locale-proof the gate

**Files:**

- Modify: `bin/lib/check:5-6`
- Modify: `CLAUDE.md:22` (the sentence describing the gate's tests)

**Interfaces:**

- Produces: `pnpm check` passes from any locale; Task 5's hook calls it without setting one.

- [ ] **Step 1: Reproduce the failure**

Run: `LC_ALL=C pnpm check > /dev/null 2>&1; echo rc=$?`
Expected: `rc=1` (the `test-upup` assertion "no changed, notice or failed line" fails because `grep -E '^ *[↻●✖]'` matches a byte of `›` under a single-byte locale)

- [ ] **Step 2: Export the locale at the top of `bin/lib/check`**

After `set -euo pipefail` (line 5) add `export LC_ALL=en_US.UTF-8` with a one-line comment saying why: the self-checks grep for UTF-8 glyphs with bracket expressions, which match single bytes under the C locale that Claude Code's Bash tool runs in (both `en_US.UTF-8` and `C.UTF-8` exist on macOS, measured with `locale -a`; `en_US.UTF-8` is what `zsh/env.zsh:6` sets).

- [ ] **Step 3: Verify both ways**

Run: `LC_ALL=C pnpm check > /dev/null 2>&1; echo rc=$?` then `env -u LC_ALL -u LANG -u LC_CTYPE pnpm check > /dev/null 2>&1; echo rc=$?`
Expected: `rc=0` both times

- [ ] **Step 4: Update the doc**

`CLAUDE.md:22`: replace the clause "Its tests are fixture self-checks: the catalog generator's (…), the codex-config seeding test, the Claude Desktop account switcher's and the VS Code renderer's." with one that says the tests are the fixture self-checks listed in the bullet below (the list at line 29 is already complete) and that `check` exports `LC_ALL=en_US.UTF-8` because the self-checks grep for UTF-8 glyphs.

- [ ] **Step 5: Commit**

```bash
git add bin/lib/check CLAUDE.md
git commit -m "Run the gate under a UTF-8 locale so it passes from Claude's shell"
```

---

### Task 2: Run the hook self-checks in the gate and shellcheck the status line

**Files:**

- Modify: `bin/lib/check:7-16` (add `tilde/.claude/*.sh` to `shell_scripts`) and after line 67 (run the two hook self-checks)
- Modify: `.claude/hooks/lint-edited.sh:64` (gating regex) and `:3` (header)
- Modify: `.claude/hooks/test-lint-edited.sh` (one new case)
- Modify: `CLAUDE.md:36` (the hooks bullet: scope sentence and "Self-checks" sentence)

**Interfaces:**

- Produces: the pattern "`bash .claude/hooks/test-<name>.sh > /dev/null`" in `bin/lib/check`, which Tasks 5 and 6 follow.

- [ ] **Step 1: Write the failing hook test case**

Append to `.claude/hooks/test-lint-edited.sh`, before the final "all checks passed" line, a case that writes a bash file with a warning-level shellcheck finding (SC2046, an unquoted command substitution; SC2086 from `echo $1` is only info level and passes `--severity=warning`, measured) at `tilde/.claude/hooktest-$$.sh`, runs the hook on it, and asserts exit 2. Add that path to the `trap` cleanup on line 12.

```bash
# N. tilde/.claude/*.sh is shellchecked like the gate does
printf '#!/bin/bash\ncat $(ls)\n' > "tilde/.claude/hooktest-$$.sh"
set +e
run "$root/tilde/.claude/hooktest-$$.sh"
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "tilde/.claude script: expected exit 2, got $rc"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `.claude/hooks/test-lint-edited.sh; echo rc=$?`
Expected: `FAIL: tilde/.claude script: expected exit 2, got 0` and `rc=1`

- [ ] **Step 3: Extend the gate list and the hook's mirror of it**

`bin/lib/check`: add `tilde/.claude/*.sh` to `shell_scripts` after line 13. `lint-edited.sh:64`: add `|| $rel =~ ^tilde/\.claude/[^/]+\.sh$` to the gated regex, and extend the comment above it that enumerates the list. `lint-edited.sh:3`: change "(Edit|Write)" to "(Edit, Write and Serena's edit tools)".

- [ ] **Step 4: Run the hook test and shellcheck the status line**

Run: `.claude/hooks/test-lint-edited.sh && shellcheck --severity=warning tilde/.claude/statusline-command.sh; echo rc=$?`
Expected: `lint-edited: all checks passed` and `rc=0`

- [ ] **Step 5: Run the self-checks from the gate**

In `bin/lib/check`, after the `test-rea-mcp` line (67), add two lines with a comment in the file's style ("the Claude Code edit hooks against sample payloads"): `bash .claude/hooks/test-lint-edited.sh > /dev/null` and `bash .claude/hooks/test-lint-bash-edits.sh > /dev/null`.

- [ ] **Step 6: Prove the gate sees them**

Run: `echo 'exit 1' >> .claude/hooks/test-lint-bash-edits.sh; pnpm check > /dev/null 2>&1; echo rc=$?; git checkout .claude/hooks/test-lint-bash-edits.sh`
Expected: `rc=1` while the self-check is forced to fail, then the checkout restores it.

- [ ] **Step 7: Run the gate clean and update the doc**

Run: `pnpm check; echo rc=$?` Expected: `rc=0`.
`CLAUDE.md:36`: in the scope sentence add `tilde/.claude/*.sh` to the shellcheck list, and change "Self-checks: …" to say the gate runs them.

- [ ] **Step 8: Commit**

```bash
git add bin/lib/check .claude/hooks/lint-edited.sh .claude/hooks/test-lint-edited.sh CLAUDE.md
git commit -m "Run the hook self-checks in the gate and shellcheck the status line"
```

---

### Task 3: Convention tests in the gate

**Files:**

- Create: `bin/lib/test-conventions`
- Modify: `bin/lib/check` (run it after the hook self-checks)
- Modify: `.claude/rules/telemetry-sync.md:10` ("the same" becomes "a subset of")
- Modify: `CLAUDE.md:29` (add the test to the gate's list) and `CLAUDE.md:107` (name the test)

**Interfaces:**

- Produces: `bin/lib/test-conventions`, exit 0 when every invariant holds, exit 1 naming the first broken one on stderr as `FAIL: <check>: <detail>`.

- [ ] **Step 1: Write the test script**

`bin/lib/test-conventions`, header in the `bin/CLAUDE.md` shape ("Tree invariants the docs promise; run by pnpm check"), `set -euo pipefail`, `cd "$(dirname "$0")/../.."`, a `fail() { echo "FAIL: $1" >&2; exit 1; }`, then four checks in this order:

1. **telemetry**: every name matched by `^export ([A-Z_]*(TELEMETRY|OPTOUT|DO_NOT_TRACK)[A-Z_]*)=` in `setup.sh` also appears as `^export <name>=` in `zsh/env.zsh`. Failure text: `telemetry: <NAME> missing from zsh/env.zsh`. (`docs/privacy.md` names tools in prose, not variable names, so it is not checked; the spec's wording of that row was wider than the file allows.)
2. **zsh prettier-ignored**: for each of `tilde/.zshenv tilde/.zprofile tilde/.zshrc zsh/*.zsh`, `node_modules/.bin/prettier --file-info <file> | jq -e .ignored` succeeds. Failure text: `zsh prettier-ignored: <file>`.
3. **bin headers**: for each regular file in `bin/` except `bin/CLAUDE.md`, line 2 matches `^(#|//)`. Failure text: `bin headers: <file>`.
4. **Brewfile trust**: no line matching `^(brew|cask) "[^"]+/[^"]+/[^"]+"` in `setup/Brewfile` lacks the exact text `, trusted: true`. Failure text: `Brewfile trust: line <n>`.

End with `echo "conventions: all checks passed"`.

- [ ] **Step 2: Run it and prove each check by breaking it**

Run: `bin/lib/test-conventions; echo rc=$?` Expected: `conventions: all checks passed`, `rc=0`.
Then, one at a time, each followed by `git checkout -- <file>`:

- `echo 'export FAKE_TELEMETRY_OPTOUT=1' >> setup.sh` then run. Expected: `FAIL: telemetry: FAKE_TELEMETRY_OPTOUT missing from zsh/env.zsh`, `rc=1`.
- `sed -i '' '/^\*\.zsh$/d' .prettierignore` then run. Expected: `FAIL: zsh prettier-ignored: zsh/aliases.zsh`, `rc=1`.
- `printf '#!/bin/bash\n\necho\n' > bin/zz-hooktest && chmod +x bin/zz-hooktest` then run, then `rm bin/zz-hooktest`. Expected: `FAIL: bin headers: bin/zz-hooktest`, `rc=1`.
- `sed -i '' 's/^brew "modem-dev\/tap\/hunk", trusted: true/brew "modem-dev\/tap\/hunk", trusted:true/' setup/Brewfile` then run. Expected: `FAIL: Brewfile trust: line 43`, `rc=1`.

- [ ] **Step 3: Wire it into the gate and fix the wording**

`bin/lib/check`: after the hook self-check lines from Task 2, add `# Tree invariants CLAUDE.md promises (telemetry pairing, zsh ignored by prettier, bin/ headers, Brewfile trust)` and `bash bin/lib/test-conventions > /dev/null`.
`.claude/rules/telemetry-sync.md:10`: "exports the same telemetry opt-out variables as" becomes "exports a subset of the telemetry opt-out variables in", and add a sentence: `bin/lib/test-conventions` fails the gate when a `setup.sh` export is missing from `env.zsh`.
`CLAUDE.md:29`: add `bin/lib/test-conventions` to the list of tests the gate runs, naming the four invariants. `CLAUDE.md:107`: append "(checked by `bin/lib/test-conventions`)".

- [ ] **Step 4: Run the gate**

Run: `pnpm check; echo rc=$?` Expected: `rc=0`

- [ ] **Step 5: Commit**

```bash
git add bin/lib/test-conventions bin/lib/check .claude/rules/telemetry-sync.md CLAUDE.md
git commit -m "Check the telemetry pairing, zsh ignores, bin headers and Brewfile trust in the gate"
```

---

### Task 4: Deny `npm -g` with a permission rule

**Files:**

- Modify: `agents/claude-settings.json` (`permissions.deny`, currently `[]`), applied with `bin/claude-config restore settings`
- Modify: `CLAUDE.md:69` (the "never `npm -g`" sentence)

**Interfaces:**

- Produces: deny rules `Bash(npm install -g *)`, `Bash(npm i -g *)`, `Bash(npm install --global *)` in the tracked snapshot and in the live user settings.

- [ ] **Step 1: Add the rules to the tracked snapshot**

Run:

```bash
jq '.permissions.deny += ["Bash(npm i -g *)","Bash(npm install --global *)","Bash(npm install -g *)"]' agents/claude-settings.json > agents/claude-settings.json.tmp && mv agents/claude-settings.json.tmp agents/claude-settings.json
```

(`save` sorts permission lists; this order is already sorted.)

- [ ] **Step 2: Apply to the live settings and confirm the round trip**

Run: `cp ~/.claude/settings.json ~/.claude/settings.json.bak && bin/claude-config restore settings && jq '.permissions.deny' ~/.claude/settings.json && bin/claude-config save && git status --short agents/`
Expected: the three strings, and `git status` shows only `agents/claude-settings.json` and the pre-existing `agents/claude-plugins.txt` as modified (the tracked snapshot and the live file agree). Delete the `.bak` once confirmed.

- [ ] **Step 3: Confirm the harness enforces it**

Through the Bash tool in this session, run `npm install -g cowsay --dry-run`.
Expected: the tool result reports the call as denied by a permission rule before anything runs (the settings file watcher reloads `permissions` without a restart, settings doc "When edits take effect").

- [ ] **Step 4: Update the doc**

`CLAUDE.md:69`: after "never `npm -g`" add "(denied by a user-settings permission rule, tracked in `agents/claude-settings.json`)".

- [ ] **Step 5: Commit**

```bash
git add agents/claude-settings.json CLAUDE.md
git commit -m "Deny npm -g in the tracked user permissions"
```

---

### Task 5: Commit gate hook

**Files:**

- Create: `.claude/hooks/commit-gate.sh`
- Create: `.claude/hooks/test-commit-gate.sh`
- Modify: `.claude/settings.json` (a `PreToolUse` entry, matcher `Bash`; an allow rule for the new self-check)
- Modify: `bin/lib/check` (run the self-check)
- Modify: `CLAUDE.md:36` (hooks bullet) and `CLAUDE.md:121` (standing approval mentions the gate hook)

**Interfaces:**

- Consumes: `pnpm check` (Task 1), exit 0 or non-zero.
- Produces: `.claude/hooks/commit-gate.sh`, a PreToolUse command hook. Reads the hook JSON on stdin. Exits 0 at once unless `.tool_input.command` is a git commit (detector below). Resolves the repo the commit targets as `root=$(git -C "$cwd" rev-parse --show-toplevel)` with `cwd` from the input JSON (so a worktree session gates its own checkout), and exits 0 when `$root/bin/lib/check` does not exist. Otherwise runs `(cd "$root" && pnpm check)`, exits 2 with the check's last 40 output lines on stderr when it fails. On success, when `git -C "$root" status --porcelain` lists a path matching `^(setup\.sh|setup/[^/]+\.sh|tilde/\.config/mise/config\.toml)$` and no path matching `README\.md$` (the working tree, not the index: in `git add x && git commit` the hook runs before `git add`), prints `{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"<fact>"}}` and exits 0.

Commit detector (the tests do not determine it, so the algorithm is fixed here; it passed all twelve Review Focus spellings under bash 3.2, measured): split the command on `&&`, `||`, `;` and `|` with `sed -E 's/(&&|\|\||;|\|)/\n/g'`; for each segment, word-split it (`for w in $seg`), skip leading `NAME=value` words, take the first remaining word's basename; the segment is a commit when that basename is `git` and a later word equals `commit`. `git log --grep commit` therefore also gates (accepted). Quoted text is not parsed, so `echo "git commit"` does not match because its first word is `echo`.

- [ ] **Step 1: Write the failing self-check**

`.claude/hooks/test-commit-gate.sh` in the `test-lint-edited.sh` style: `set -euo pipefail`; a temp project `$proj` under `$TMPDIR` with `git init` and one committed file, containing `bin/lib/check` as an empty executable (its presence is the gate's "this is the repo" marker); a stub `pnpm` first on PATH that touches `$STATE/check-ran` and exits with the number in `$STATE/check-rc` (default 0); a `run <cmd>` that builds the payload with `jq -cn --arg c "$1" --arg d "$proj" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}'`, pipes it into the real hook with `CLAUDE_PROJECT_DIR=$proj`, and sets `out` (stdout) and `rc`; a `touch_path <path>` that writes a line to `$proj/<path>`, creating parent dirs; `trap 'rm -rf "$tmp"' EXIT`. Cases:

```bash
# 1. a non-commit command never runs the check, exit 0
run 'gh pr view --json commits'; [ "$rc" -eq 0 ] && [ ! -e "$STATE/check-ran" ] || fail "non-commit ran the check"
# 2. a failing check blocks the commit
echo 1 > "$STATE/check-rc"; run 'git commit -m "x"'; [ "$rc" -eq 2 ] || fail "failing check: expected exit 2, got $rc"
# 3. every commit spelling gates
echo 0 > "$STATE/check-rc"
for c in 'git -C . commit --amend' 'git -c commit.gpgsign=false commit' '/usr/bin/git commit' 'GIT_EDITOR=true git commit' 'git add x && git commit -m y'; do
  rm -f "$STATE/check-ran"; run "$c"; [ -e "$STATE/check-ran" ] || fail "not gated: $c"
done
# 4. mentions of the word do not gate
for c in 'pre-commit run' 'echo "git commit"' 'git commit-tree HEAD^{tree}'; do
  rm -f "$STATE/check-ran"; run "$c"; [ ! -e "$STATE/check-ran" ] || fail "wrongly gated: $c"
done
# 5. a passing check with setup/x.sh changed and no README warns
touch_path setup/x.sh; run 'git commit -m "x"'; [ "$rc" -eq 0 ] && grep -q README <<< "$out" || fail "docs-mirror warning missing"
# 6. a README changed alongside silences the warning
touch_path setup/README.md; run 'git commit -m "x"'; [ "$rc" -eq 0 ] && [ -z "$out" ] || fail "warning printed with README changed"
# 7. a commit in a repo without bin/lib/check is not gated
rm "$proj/bin/lib/check"; rm -f "$STATE/check-ran"; run 'git commit -m "x"'; [ "$rc" -eq 0 ] && [ ! -e "$STATE/check-ran" ] || fail "foreign repo was gated"
```

The script ends with `echo "commit-gate: all checks passed"`.

- [ ] **Step 2: Run it to verify it fails**

Run: `.claude/hooks/test-commit-gate.sh; echo rc=$?`
Expected: a "No such file" error for the hook or `FAIL: failing check: expected exit 2`, and `rc=1`

- [ ] **Step 3: Write the hook**

`.claude/hooks/commit-gate.sh` with the interface and detector above. Decisions: `set -uo pipefail` (not `-e`); read stdin once into a variable; `cwd=$(jq -r '.cwd // empty' <<< "$input")`, falling back to `${CLAUDE_PROJECT_DIR:-$(pwd -P)}`; the context sentence is a fact, not an order, for example "Changed: setup/x.sh. No README is changed; CLAUDE.md's docs-mirror rule expects a README edit in the same commit for setup or mise changes." `chmod +x` both scripts.

- [ ] **Step 4: Run the self-check**

Run: `.claude/hooks/test-commit-gate.sh; echo rc=$?`
Expected: `commit-gate: all checks passed`, `rc=0`

- [ ] **Step 5: Register the hook and the allow rule**

`.claude/settings.json`: add to `hooks` a `"PreToolUse"` array with one group, `"matcher": "Bash"`, one handler: `{"type":"command","command":"${CLAUDE_PROJECT_DIR}/.claude/hooks/commit-gate.sh","args":[],"timeout":180,"onFailure":"block","statusMessage":"Running pnpm check before the commit"}`. `onFailure: "block"` makes a timeout or crash block the commit instead of letting it through (hooks doc "Timeouts"); 180 s is eight times the measured 22 s gate. Add `"Bash(.claude/hooks/test-commit-gate.sh *)"` to `permissions.allow` next to the other two self-checks. Do not use the `if` field: the docs call it best-effort for Bash, and the script's own detector handles `git -C`. Validate: `jq . .claude/settings.json > /dev/null; echo rc=$?` Expected: `rc=0`.

- [ ] **Step 6: Exercise the live hook, both ways**

Through the Bash tool in this session: `echo 'exit 1' >> bin/lib/test-conventions` then `git commit --allow-empty -m "hook probe"`.
Expected: the tool result shows the hook blocked the call (exit 2) with the gate's failing tail, and `git log -1 --format=%s` is not "hook probe". Then `git checkout bin/lib/test-conventions` and `git commit --allow-empty -m "hook probe"` again.
Expected: the commit succeeds after about 22 s. Drop it with `git reset --soft HEAD~1` (an empty commit leaves nothing staged). If the hook never fired, validate `.claude/settings.json` with `jq` and check the matcher spelling.

- [ ] **Step 7: Add the self-check to the gate and update the docs**

`bin/lib/check`: `bash .claude/hooks/test-commit-gate.sh > /dev/null` next to the other hook self-checks.
`CLAUDE.md:36`: add a sentence: a PreToolUse hook on Bash (`commit-gate.sh`) runs `pnpm check` in the repo a `git commit` targets and blocks the commit when the check fails or the hook cannot run (`onFailure: block`); it tells Claude when setup or mise files are changed without a README; the gate tests the working tree, not the index; self-check `test-commit-gate.sh`.
`CLAUDE.md:121`: after "once `pnpm check` passes" add "(the commit-gate hook runs it)".

- [ ] **Step 8: Run the gate and commit**

Run: `pnpm check; echo rc=$?` Expected: `rc=0`.

```bash
git add .claude/hooks/commit-gate.sh .claude/hooks/test-commit-gate.sh .claude/settings.json bin/lib/check CLAUDE.md
git commit -m "Gate every commit on pnpm check with a PreToolUse hook"
```

Expected: this commit itself runs through the hook.

---

### Task 6: Enforce the docs-auditor's read-only allowlist

**Files:**

- Create: `.claude/hooks/auditor-readonly.sh`
- Create: `.claude/hooks/test-auditor-readonly.sh`
- Modify: `.claude/settings.json` (a second `PreToolUse` group, matcher `Bash`; allow rule for the self-check), `bin/lib/check` (run it)
- Modify: `.claude/agents/docs-auditor.md:16` (one sentence pointing at the hook)
- Modify: `CLAUDE.md:78` ("may run allowlisted read-only commands" becomes "runs only allowlisted read-only commands, enforced by a PreToolUse hook that applies inside that subagent")

The hook lives in `.claude/settings.json`, not the agent's frontmatter: settings hooks run inside every subagent and their input then carries `agent_type` (hooks doc "Hook locations"), which needs no workspace-trust step and holds whether the agent starts from the Agent tool or from `docs-audit`'s `context: fork` plus `agent:` (the docs do not say whether frontmatter hooks fire on that path).

**Interfaces:**

- Produces: `.claude/hooks/auditor-readonly.sh`, a PreToolUse command hook for `Bash`. Exits 0 at once unless `.agent_type` in the input equals `docs-auditor`. Otherwise it takes `.tool_input.command` and works in this order (a prototype of exactly this order passed all 25 cases below, measured): deny (exit 2, `auditor-readonly: not allowed: <text>` on stderr) when the raw command contains `$(`, a backtick or `&>`; strip single- and double-quoted strings (`sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g"`) so a quoted `>` or `|` is data; on that stripped text, remove `2>&1`, `2>/dev/null`, `2> /dev/null`, `>/dev/null` and `> /dev/null`, and deny if any `>` remains; split the stripped text on `&&`, `||`, `;`, `|` and newlines, left-trim each segment, skip empty ones, and require every segment to match one allowlist pattern and none of the command-specific deny patterns.

Allowlist (extended regexes, anchored at the segment start):

```text
^(sw_vers|mdfind|ls|wc|du|jq|cat|bat|head|tail|grep|rg|find|stat|file|which|sort|uniq|cut|tr|awk|sed -n|diff|test|\[|echo|printf|cd|pwd|true|command -v|help|shellcheck)([[:space:]]|$)
^brew (list|info)([[:space:]]|$)
^mise (--version|ls)([[:space:]]|$)
^defaults read([[:space:]]|$)
^claude (--version|mcp get|plugin list)([[:space:]]|$)
^uv tool list([[:space:]]|$)
^curl -sf https?://127\.0\.0\.1(:[0-9]+)?(/|$)
^git (-C [^[:space:]]+ )?(log|show|diff|status|grep|rev-parse|ls-files|check-ignore|remote -v)([[:space:]]|$)
^gh (run (list|view)|api)([[:space:]]|$)
```

Command-specific deny patterns (a segment matching one is denied even though its prefix is allowed):

```text
^find .*(-delete|-exec|-ok|-fprint)
^sed -n.*[[:space:]]-i
^sort.*[[:space:]]-o([[:space:]]|$)
^gh api.*[[:space:]](-X|--method|-f|-F|--field|--raw-field|--input)([[:space:]]|$)
^awk .*system\(
```

- [ ] **Step 1: Write the failing self-check**

`.claude/hooks/test-auditor-readonly.sh` in the `test-lint-edited.sh` style. `run <cmd> [agent_type]` builds the payload with `jq -cn --arg c "$1" --arg a "${2:-docs-auditor}" '{tool_name:"Bash",tool_input:{command:$c},agent_type:$a}'` and returns the hook's exit code. `allow` fails the test unless the hook exits 0; `deny` fails unless it exits 2. Cases:

```bash
allow 'brew list --versions shellcheck'
allow 'git log --oneline -5 && gh run list --limit 3'
allow "jq '.a | keys' ~/.claude/settings.json"
allow "grep -E 'a|b' README.md"
allow "grep '=>' zsh/aliases.zsh"
allow "sed -n '1p;2p' setup.sh"
allow 'curl -sf http://127.0.0.1:9077/health 2>&1'
allow 'ls /nonexistent > /dev/null 2>&1'
allow 'git -C /tmp/x show HEAD'
allow 'help upup'
deny  'brew install foo'
deny  'cat x > y'
deny  'jq . a | tee b'
deny  'git log; rm -rf x'
deny  'ls $(rm x)'
deny  'find . -name x -delete'
deny  'sed -n -i 1p x'
deny  'gh api -X DELETE repos/a/b'
deny  'curl -sf http://127.0.0.1.evil/x'
deny  'git diff 2> /tmp/x'
deny  'defaults write com.apple.dock tilesize 36'
deny  'sudo ls'
deny  'claude plugin install foo'
deny  "echo 'x' > out"
deny  'sort -o x y'
# 26. another agent, or the main session, is never touched
run 'brew install foo' general-purpose; [ "$rc" -eq 0 ] || fail "non-auditor agent was gated"
run 'brew install foo' ''; [ "$rc" -eq 0 ] || fail "main session was gated"
```

End with `echo "auditor-readonly: all checks passed"`.

- [ ] **Step 2: Run it to verify it fails**

Run: `.claude/hooks/test-auditor-readonly.sh; echo rc=$?` Expected: `rc=1`

- [ ] **Step 3: Write the hook**

`.claude/hooks/auditor-readonly.sh` with the interface above; `set -uo pipefail`; read stdin once; `chmod +x` both scripts.

- [ ] **Step 4: Run the self-check**

Run: `.claude/hooks/test-auditor-readonly.sh; echo rc=$?` Expected: `auditor-readonly: all checks passed`, `rc=0`

- [ ] **Step 5: Register the hook**

`.claude/settings.json`: add a second group to `hooks.PreToolUse`, `"matcher": "Bash"`, handler `{"type":"command","command":"${CLAUDE_PROJECT_DIR}/.claude/hooks/auditor-readonly.sh","args":[],"timeout":10,"onFailure":"block","statusMessage":"Checking the auditor's command is read-only"}`. Add `"Bash(.claude/hooks/test-auditor-readonly.sh *)"` to `permissions.allow`. `.claude/agents/docs-auditor.md:16`: append "A PreToolUse hook (`.claude/hooks/auditor-readonly.sh`) rejects anything outside this list; quoted pipes are fine, command substitution and redirects into files are not." Validate: `jq . .claude/settings.json > /dev/null; echo rc=$?` Expected: `rc=0`.

- [ ] **Step 6: Prove it fires inside the subagent**

Spawn the agent with the Agent tool, `subagent_type: docs-auditor`, prompt: "Run exactly `brew install cowsay --dry-run` through Bash and report the full tool result text verbatim, then stop." Expected: the report contains `auditor-readonly: not allowed`. If it contains brew's own output instead, the hook did not reach the subagent: check `agent_type` in a debug run (`claude --debug-file /tmp/hooks.txt`, then `grep auditor /tmp/hooks.txt`) and fix the comparison before continuing.

- [ ] **Step 7: Gate, docs, commit**

`bin/lib/check`: `bash .claude/hooks/test-auditor-readonly.sh > /dev/null`. `CLAUDE.md:78` as listed under Files.
Run: `pnpm check; echo rc=$?` Expected: `rc=0`.

```bash
git add .claude/hooks/auditor-readonly.sh .claude/hooks/test-auditor-readonly.sh .claude/agents/docs-auditor.md .claude/settings.json bin/lib/check CLAUDE.md
git commit -m "Enforce the docs-auditor's read-only command list with a hook"
```

---

### Task 7: Config hygiene

**Files:**

- Modify: `.claude/settings.json:42` (anchor the matcher), `permissions.allow` (add `"Bash(bash vscode/test-vscode-settings.sh)"`)
- Modify: `.claude/settings.local.json` (empty its allow list)
- Modify: `agents/claude-settings.json` (the three `rtk` allow rules), applied with `bin/claude-config restore settings`
- Modify: `.claude/skills/validate-setup/SKILL.md:6` (`allowed-tools`)
- Modify: `tilde/.claude/statusline-command.sh:3` (dead spec reference)

**Interfaces:** none.

- [ ] **Step 1: Anchor the edit matcher and prove the hook still fires**

`.claude/settings.json:42`: wrap the matcher as `^(Edit|Write|mcp__serena__(replace_content|replace_in_files|replace_symbol_body|insert_after_symbol|insert_before_symbol|rename_symbol|safe_delete_symbol))$`. Then, with the Write tool, create `docs/hooktest.md` containing `# T\n\n* a\n`; the hook reformats it on write.
Run: `grep -c '^- a$' docs/hooktest.md; rm docs/hooktest.md` Expected: `1` (Prettier rewrote `* a` to `- a`, so the PostToolUse hook fired through the anchored matcher).

- [ ] **Step 2: Move the local allow rules**

Add `"Bash(bash vscode/test-vscode-settings.sh)"` to `.claude/settings.json` `permissions.allow`. Add `"Bash(rtk grep *)"`, `"Bash(rtk read *)"`, `"Bash(rtk wc *)"` to `agents/claude-settings.json` `permissions.allow` (sorted position), then run `bin/claude-config restore settings && bin/claude-config save && git status --short agents/`. Expected: only `agents/claude-settings.json` (and the pre-existing `agents/claude-plugins.txt`) modified. Then rewrite `.claude/settings.local.json` to `{"permissions":{"allow":[]}}` (gitignored by `~/.gitignore:30`; keep the file so Claude Code's own writes land in it).

- [ ] **Step 3: Pre-approve the snapshot redirects**

`.claude/skills/validate-setup/SKILL.md:6`: append ` Edit(/private/setup-snapshots/**)` to `allowed-tools`. Run `claude plugin validate .claude/skills` and expect `Validation passed`. Whether an `Edit(/…)` rule in `allowed-tools` anchors at the repo root like a project settings rule is not stated in the docs; `/validate-setup before` in a later session settles it (it should not prompt on the `>` redirect).

- [ ] **Step 4: Fix the dead reference**

`tilde/.claude/statusline-command.sh:3`: the spec file named there does not exist in the tree or history (measured). Replace the line with `# Documented in agents/README.md (symlinked by setup/symlinks.sh)` or delete it.

- [ ] **Step 5: Gate and commit**

Run: `pnpm check; echo rc=$?` Expected: `rc=0`.

```bash
git add .claude/settings.json agents/claude-settings.json .claude/skills/validate-setup/SKILL.md tilde/.claude/statusline-command.sh
git commit -m "Anchor the edit-hook matcher and move local allow rules where they belong"
```

---

### Task 8: Slim CLAUDE.md into path-scoped rules

**Files:**

- Create: `.claude/rules/claude-config.md`
- Modify: `CLAUDE.md` (remove bullets 36, 37, 73, 74, 75, 76, 77, 78, 79, 80 as they stand after Tasks 1-7; update bullet 81; keep 22-29 and 121)
- Modify: `.claude/rules/vscode.md`, `.claude/rules/setup.md` (receive bullets 79-80 and 74)
- Modify: `tilde/.claude/rules/index.md` (add `paths:` frontmatter)
- Modify: `tilde/.claude/rules/hindsight.md` (receives the operating facts from bullet 77 that it lacks, if any)

Path-scoped rules load when Claude uses Read, Write or Edit on a matching file, or a single-file Bash read such as `cat` (memory doc "Path-specific rules"); they do not load on CodeGraph or Serena navigation. The files this rule covers are JSON, Markdown and shell, which `code-navigation.md` already routes to native Read and Edit, so the trigger holds; bullet 81 in `CLAUDE.md` keeps a one-line pointer to the rule for sessions that never touch them.

**Interfaces:**

- Produces: `.claude/rules/claude-config.md` with frontmatter `paths: ['.claude/**', 'agents/claude-*', 'agents/catalog/**', 'tilde/.claude/**', 'bin/claude-*', 'bin/hindsight-memory']`.

- [ ] **Step 1: Record the baseline**

Run: `wc -c CLAUDE.md` Expected: about 27,500 bytes (26,299 before this plan plus the sentences Tasks 1-7 added).

- [ ] **Step 2: Create the rule and move the bullets**

`.claude/rules/claude-config.md`: the frontmatter above, a `# Claude Code config in this repo` heading, then the text of bullets 36 (hooks), 37 (permissions), 73 (global rules), 75 (catalog), 76 (claude-config), 78 (project skills and agents) verbatim, and bullet 77 (Hindsight) cut to the repo wiring: `bin/hindsight-memory`'s subcommands, where the env pins live (`tilde/.zshenv`, `agents/claude-settings.json` `env`), and the pointer to the spec; the operating facts (`autoInject: pages`, the six-hourly cron, the cargo preflight) stay in `tilde/.claude/rules/hindsight.md` (add any that file lacks).
Move bullets 79 and 80 into `.claude/rules/vscode.md` and bullet 74 into `.claude/rules/setup.md`, each as a new bullet in that file's voice.
Delete those bullets from `CLAUDE.md`. Rewrite bullet 81 to list the six rule files and say `claude-config.md` (hooks, permissions, skills, agents, catalog, `claude-config`, Hindsight wiring) loads on `.claude/**`, `agents/claude-*`, `agents/catalog/**`, `tilde/.claude/**` and `bin/claude-*` edits.
`tilde/.claude/rules/index.md`: add frontmatter `paths: ['tilde/.claude/rules/**']` and a line saying it loads only when the rules are edited in the dotfiles repo.

- [ ] **Step 3: Check nothing was lost or duplicated**

Run, for each moved bullet, a distinctive phrase with `git grep --untracked -c '<phrase>' -- CLAUDE.md <target>`: `lint-edited.sh` and `claude-config save` against `.claude/rules/claude-config.md`, `SpaceBox Enable UI Enhancer` against `.claude/rules/vscode.md`, `bootstrap-runtime.archify.json` against `.claude/rules/setup.md`. Expected: `CLAUDE.md:0` is absent from the output (no match) and the target reports a count of at least 1. Then `wc -c CLAUDE.md`: expect under 18,000 bytes.

- [ ] **Step 4: Prove the rule loads on a matching edit**

Write a one-off settings file `/tmp/instr-settings.json` holding an `InstructionsLoaded` hook with `"matcher": "path_glob_match"` and the handler `{"type":"command","command":"jq -r '.load_reason + \" \" + .file_path' >> /tmp/instr.log"}` (`file_path` and `load_reason` are the event's documented input fields). Run `env -u CLAUDECODE claude -p "Read .claude/settings.json and reply ok" --settings /tmp/instr-settings.json` from the repo root, then `grep claude-config.md /tmp/instr.log`. Expected: one line `path_glob_match /Users/jason/dev/dotfiles/.claude/rules/claude-config.md`. Delete both temp files afterwards.

- [ ] **Step 5: Gate and commit**

Run: `pnpm check; echo rc=$?` Expected: `rc=0`.

```bash
git add CLAUDE.md .claude/rules/claude-config.md .claude/rules/vscode.md .claude/rules/setup.md tilde/.claude/rules/index.md tilde/.claude/rules/hindsight.md
git commit -m "Move the Claude config bullets out of CLAUDE.md into path-scoped rules"
```

---

### Task 9: Audit the instruction files and close the spec

**Files:**

- Modify: move `docs/superpowers/specs/2026-10-25-claude-code-guardrails-assessment.md` to `docs/superpowers/specs/completed/` and this plan to `docs/superpowers/plans/completed/`

- [ ] **Step 1 (human only): Run the built-in audit**

The owner runs `/doctor prompt-audit` in an interactive session (v2.1.283+; this is 2.1.310). It proposes edits and changes nothing; apply the correct ones in a commit of their own.

- [ ] **Step 2: Push and confirm CI**

Run: `git push && gh run watch "$(gh run list --branch main --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status; echo rc=$?` Expected: `rc=0` (the `check` workflow succeeds on macOS, which also proves Task 3's `prettier --file-info` calls work on the runner).

- [ ] **Step 3: Close the spec and the plan**

The spec and this plan were never committed, so stage them first, then move them into their `completed/` folders (the `CLAUDE.md` rule for finished plans and specs):

```bash
git add docs/superpowers/specs/2026-10-25-claude-code-guardrails-assessment.md docs/superpowers/plans/2026-10-25-claude-code-guardrails.md
git mv docs/superpowers/specs/2026-10-25-claude-code-guardrails-assessment.md docs/superpowers/specs/completed/
git mv docs/superpowers/plans/2026-10-25-claude-code-guardrails.md docs/superpowers/plans/completed/
git commit -m "Complete the Claude Code guardrails plan"
git push
```
