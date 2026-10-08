# Claude Code Mods Adoption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the two gaps the mods assessment confirmed with the smallest mechanism that works (classic hooks for Bash edits that escape `lint-edited.sh`, one settings key for the task tools that Fable 5.1 lacks), trim the plugin hook fan-out the inventory measured, and park the one mod worth building as a separate plan.

**Architecture:** No mod is built in this plan. A PreToolUse Bash hook drops a marker keyed by `session_id` and `tool_use_id`; a PostToolUse Bash hook runs `find -newer` against it and feeds each changed file to the existing `lint-edited.sh`, which stays the single owner of lint scope and rules. `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` goes into the tracked settings snapshot and is merged into the live settings by `claude-config restore settings`. Plugin changes go through `claude plugin disable` plus `claude-config save`, so `agents/claude-plugins.txt` stays the record.

**Tech Stack:** Claude Code 2.1.295, `/bin/bash` 3.2.57 (the shebang every script here uses; no `mapfile`, no associative arrays), jq 1.8, prettier 3 with prettier-plugin-sh, shellcheck, `bin/claude-config`, `claude plugin`.

**Spec:** `docs/superpowers/specs/2026-10-08-claude-code-mods-assessment.md`. Its "Review corrections" section holds the checks that shaped this plan: `tool_use_id` is on both hook events (hooks.md lines 1595 and 2046), the task tools are absent on Fable without the env var (tools-reference.md "Task tool availability"), hookify has no rule files, security-guidance's seven Bash entries are `if`-gated to commits and pushes and its model reviews have never run here, Warp's hooks exit at once outside Warp.

## Global Constraints

- Hook scripts start with `#!/bin/bash` and a header comment, use `set -uo pipefail` (not `-e`: a failing lint must not kill the hook before it reports), and run on bash 3.2: `while IFS= read -r -d '' f` with process substitution instead of `mapfile`; `${#arr[@]}` is safe under `set -u`, `"${arr[@]}"` only after a length check (both verified on this machine).
- `pnpm check` passes after every task. It already covers `.claude/hooks/*.sh` with `bash -n`, shellcheck `--severity=warning` and prettier, so new hook scripts need no wiring there.
- The lint hook self-checks are not part of `pnpm check`; each is run by hand and allowed in `.claude/settings.json` permissions, like `test-lint-edited.sh` today.
- Never track `~/.claude/settings.json` or `~/.claude.json`. The tracked snapshot is `agents/claude-settings.json`; `claude-config restore settings` merges it with `jq '$base * $cur'` (live values win, missing keys added, lists unioned), and `claude-config save` writes it back keeping only `CLAUDE_CODE_*`, `DISABLE_*` and `MAX_*` env keys.
- Docs mirror behavior in the same commit: `CLAUDE.md` line 34 (the hook bullet) and the permissions bullet two lines below it, plus `docs/` and `agents/` READMEs where they describe the changed thing.
- Commit subjects: short, imperative, sentence case, no prefix. Stage files explicitly. On `main`, commit and push once `pnpm check` passes (standing approval in `CLAUDE.md`, Custom Notes).
- Before each commit, run the built-in `/simplify` and then `/code-review` on that commit's diff, and keep comments to a non-obvious why (j-mode rules in `~/.claude/rules/jstack-models.md`'s plugin).
- Settings-file hook edits are read at session start. After Task 2, start a new session before the live check.

## Review Focus

1. Two Bash tool calls in flight at once (one parallel tool block). Each call owns a marker named by its `tool_use_id`. A file written between the two markers is reported by at least one PostToolUse run and never by neither. Pinned in Task 1, check 9.
2. A hook payload without `session_id` or `tool_use_id` (an older event shape, a payload edited by another hook). Both hooks exit 0, write no marker and lint nothing. Pinned in Task 1, check 8.
3. One command that rewrites many files (`pnpm format`, `scripts/sync-*`). Above 25 changed files the hook prints one line telling Claude to run `pnpm check` and exits 2 without linting file by file. Pinned in Task 1, check 7.
4. Paths with spaces. The file list comes from `find -print0` and the payload for `lint-edited.sh` is built with `jq --arg`, so a path like `docs/a b.md` is linted and formatted. Pinned in Task 1, check 6.
5. The common case, a Bash call that reads and writes nothing. `find` over the 5,934 files in this checkout took 0.15 s; the hook finds nothing and exits 0. Measured in Task 2, step 5.

---

### Task 1: Hooks that lint files written through Bash

**Files:**
- Create: `.claude/hooks/mark-tool-start.sh`
- Create: `.claude/hooks/lint-bash-edits.sh`
- Create: `.claude/hooks/test-lint-bash-edits.sh`
- Read: `.claude/hooks/lint-edited.sh` (unchanged; it reads `{"tool_input":{"file_path":…}}` on stdin, exits 2 with problems on stderr, 0 otherwise)
- Read: `.claude/hooks/test-lint-edited.sh` (the style to match)

**Interfaces:**
- Consumes: hook stdin JSON with `session_id`, `tool_use_id`, `tool_name`, `tool_input`; `CLAUDE_PROJECT_DIR`; `TMPDIR`.
- Produces: marker files at `${TMPDIR:-/tmp}/claude-lint-markers/<session_id>-<tool_use_id>`; `lint-bash-edits.sh` exit 2 with `lint-edited.sh`'s stderr per file, or exit 0. Task 2 wires both scripts into `.claude/settings.json`.

- [ ] **Step 1: Write the failing self-check**

Create `.claude/hooks/test-lint-bash-edits.sh`:

```bash
#!/bin/bash
#
# Self-check for mark-tool-start.sh + lint-bash-edits.sh — run:
# .claude/hooks/test-lint-bash-edits.sh

set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd -P)
cd "$root"
pre=.claude/hooks/mark-tool-start.sh
post=.claude/hooks/lint-bash-edits.sh
# Files to lint live in $tmp (tracked path, so find and lint-edited.sh see
# them); markers and captured stderr live under private/, which find prunes
# and git ignores, so the test never counts its own scratch as a changed file
tmp=hooktest-$$
scratch=private/hooktest-$$
mkdir -p "$tmp" "$scratch"
export TMPDIR=$root/$scratch
markers=$TMPDIR/claude-lint-markers
err=$scratch/err
trap 'rm -rf "$root/$tmp" "$root/$scratch"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
payload() {
  printf '{"session_id":"s1","tool_use_id":"%s","tool_name":"Bash","tool_input":{"command":"true"}}' "$1"
}
# PreToolUse: drop the marker for a call id; returns the hook's exit code
mark() { payload "$1" | CLAUDE_PROJECT_DIR=$root "$pre"; }
# PostToolUse: lint what changed since the marker; stderr to $err, returns the exit code
lint() {
  set +e
  payload "$1" | CLAUDE_PROJECT_DIR=$root "$post" 2> "$err"
  rc=$?
  set -e
  return $rc
}

# 1. A Bash call that writes a shell syntax error → exit 2, problem names the file
mark t1 || fail "mark: non-zero exit"
printf '#!/bin/bash\nif then\n' > "$tmp/b.sh"
lint t1 && fail "syntax error via Bash: expected exit 2, got 0"
[ $? -eq 2 ] || fail "syntax error via Bash: expected exit 2"
grep -q "$tmp/b.sh" "$err" || fail "syntax error via Bash: file not named in stderr"
rm "$tmp/b.sh"

# 2. A call that writes nothing → exit 0, and its marker is gone afterwards
mark t2
lint t2 || fail "no writes: non-zero exit"
[ ! -e "$markers/s1-t2" ] || fail "no writes: marker left behind"

# 3. PostToolUse without a PreToolUse marker (hook added mid-session) → exit 0
lint t3 || fail "no marker: non-zero exit"

# 4. A write into a gitignored path (private/) → exit 0
mark t4
printf '#!/bin/bash\nif then\n' > "$scratch/bad.sh"
lint t4 || fail "gitignored write: should be skipped"

# 5. Unformatted Markdown written via Bash gets formatted, exit 0
mark t5
printf '# T\n\n* a\n' > "$tmp/a.md"
lint t5 || fail "markdown: non-zero exit"
grep -q '^- a$' "$tmp/a.md" || fail "markdown: not formatted"

# 6. A path with a space is found and formatted
mark t6
printf '# T\n\n* b\n' > "$tmp/a b.md"
lint t6 || fail "path with space: non-zero exit"
grep -q '^- b$' "$tmp/a b.md" || fail "path with space: not formatted"

# 7. More than 25 changed files → one line pointing at pnpm check, exit 2, nothing linted
mark t7
for i in $(seq 1 26); do printf '# T\n\n* c\n' > "$tmp/bulk$i.md"; done
lint t7 && fail "bulk: expected exit 2, got 0"
grep -q 'pnpm check' "$err" || fail "bulk: stderr does not point at pnpm check"
grep -q '^\* c$' "$tmp/bulk1.md" || fail "bulk: files were linted one by one"

# 8. A payload without tool_use_id → both hooks exit 0 and write no marker
before=$(ls "$markers" 2> /dev/null | wc -l)
printf '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"true"}}' \
  | CLAUDE_PROJECT_DIR=$root "$pre" || fail "no id: pre exited non-zero"
printf '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"true"}}' \
  | CLAUDE_PROJECT_DIR=$root "$post" || fail "no id: post exited non-zero"
[ "$(ls "$markers" 2> /dev/null | wc -l)" -eq "$before" ] || fail "no id: a marker was written"

# 9. Two calls in flight: a write between the two markers is caught by the first
mark p1
printf '#!/bin/bash\nif then\n' > "$tmp/p.sh"
mark p2
lint p1 && fail "parallel: first call should report the write"
lint p2 || fail "parallel: second call should see nothing newer than its marker"
rm "$tmp/p.sh"

echo "lint-bash-edits: all checks passed"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `chmod +x .claude/hooks/test-lint-bash-edits.sh && .claude/hooks/test-lint-bash-edits.sh`
Expected: `FAIL: mark: non-zero exit` (the hook script does not exist yet; the pipe into a missing file fails).

- [ ] **Step 3: Write the PreToolUse marker hook**

Create `.claude/hooks/mark-tool-start.sh`:

```bash
#!/bin/bash
#
# Claude Code PreToolUse hook (Bash): drop a marker before the command runs
# so lint-bash-edits.sh can `find -newer` the files it wrote. One marker per
# session + tool_use_id, so parallel Bash calls never share one. Wired up in
# .claude/settings.json; self-check: .claude/hooks/test-lint-bash-edits.sh

set -uo pipefail

key=$(jq -r 'select(.session_id and .tool_use_id) | "\(.session_id)-\(.tool_use_id)"')
[[ $key =~ ^[A-Za-z0-9_-]+$ ]] || exit 0

dir=${TMPDIR:-/tmp}/claude-lint-markers
mkdir -p "$dir" || exit 0
# A call that never reaches PostToolUse (interrupted turn) leaves its marker
find "$dir" -type f -mmin +60 -delete 2> /dev/null
touch "$dir/$key"
exit 0
```

- [ ] **Step 4: Write the PostToolUse lint hook**

Create `.claude/hooks/lint-bash-edits.sh`:

```bash
#!/bin/bash
#
# Claude Code PostToolUse hook (Bash): lint the files this Bash call wrote
# (heredocs, sed -i, tee, cp…), which the Edit/Write hook never sees. Every
# file in the checkout newer than the marker mark-tool-start.sh dropped goes
# through lint-edited.sh, which owns the scope and the rules. Problems go to
# stderr with exit 2, so Claude sees them although the command already ran.
# Wired up in .claude/settings.json; self-check: .claude/hooks/test-lint-bash-edits.sh

set -uo pipefail

project=${CLAUDE_PROJECT_DIR:-$(pwd -P)}
key=$(jq -r 'select(.session_id and .tool_use_id) | "\(.session_id)-\(.tool_use_id)"')
[[ $key =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
marker=${TMPDIR:-/tmp}/claude-lint-markers/$key
[ -f "$marker" ] || exit 0
trap 'rm -f "$marker"' EXIT

cd "$project" || exit 0
hook=$project/.claude/hooks/lint-edited.sh

# .git, node_modules and private/ are never ours; lint-edited.sh applies
# .gitignore and pnpm check's scope to everything else
files=()
while IFS= read -r -d '' f; do
  files+=("${f#./}")
done < <(find . \( -name .git -o -name node_modules -o -path ./private \) -prune -o -type f -newer "$marker" -print0 2> /dev/null)
[ "${#files[@]}" -gt 0 ] || exit 0

# A bulk rewrite (pnpm format, a sync script) is pnpm check's job, not 26 hook runs
if [ "${#files[@]}" -gt 25 ]; then
  echo "lint-bash-edits: ${#files[@]} files changed in one command; run pnpm check" >&2
  exit 2
fi

problems=""
for f in "${files[@]}"; do
  out=$(jq -cn --arg p "$project/$f" '{tool_name: "Bash", tool_input: {file_path: $p}}' | "$hook" 2>&1)
  [ $? -eq 2 ] && problems+="$out"$'\n'
done

if [ -n "$problems" ]; then
  printf '%s' "$problems" >&2
  exit 2
fi
exit 0
```

- [ ] **Step 5: Make both executable and run the self-check**

Run: `chmod +x .claude/hooks/mark-tool-start.sh .claude/hooks/lint-bash-edits.sh && .claude/hooks/test-lint-bash-edits.sh`
Expected: `lint-bash-edits: all checks passed`

- [ ] **Step 6: Run the repo gate and the existing self-check**

Run: `pnpm check && .claude/hooks/test-lint-edited.sh`
Expected: both pass. The gate runs shellcheck at `--severity=warning`, so the style-level SC2181 on `[ $? -eq 2 ]` does not fire; the exit code wanted is the pipeline's, which `pipefail` makes the hook's.

- [ ] **Step 7: Commit**

```bash
git add .claude/hooks/mark-tool-start.sh .claude/hooks/lint-bash-edits.sh .claude/hooks/test-lint-bash-edits.sh
git commit -m "Add hooks that lint files written through Bash"
```

### Task 2: Wire the hooks, verify live, document

**Files:**
- Modify: `.claude/settings.json` (`permissions.allow`, `hooks`)
- Modify: `CLAUDE.md:34` (the hook bullet) and `CLAUDE.md:35` (the permissions bullet)

**Interfaces:**
- Consumes: the two scripts from Task 1 at `${CLAUDE_PROJECT_DIR}/.claude/hooks/`.
- Produces: a `PreToolUse` block with matcher `Bash` and a second `PostToolUse` entry with matcher `Bash`.

- [ ] **Step 1: Add the permission for the new self-check**

In `.claude/settings.json`, after `"Bash(.claude/hooks/test-lint-edited.sh *)"` add:

```json
      "Bash(.claude/hooks/test-lint-bash-edits.sh *)"
```

- [ ] **Step 2: Add the hooks**

Replace the `"hooks"` object with:

```json
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/mark-tool-start.sh",
            "args": [],
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write|mcp__serena__(replace_content|replace_in_files|replace_symbol_body|insert_after_symbol|insert_before_symbol|rename_symbol|safe_delete_symbol)",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/lint-edited.sh",
            "args": [],
            "timeout": 60,
            "statusMessage": "Formatting and linting the edited file"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/lint-bash-edits.sh",
            "args": [],
            "timeout": 60,
            "statusMessage": "Linting files the command wrote"
          }
        ]
      }
    ]
  }
```

- [ ] **Step 3: Validate the JSON and the gate**

Run: `jq . .claude/settings.json > /dev/null && pnpm check`
Expected: no jq error; `pnpm check` passes (prettier formats `settings.json` through the Edit hook already).

- [ ] **Step 4: Live check in a fresh session**

Start a new Claude Code session in this repo (hook config is read at startup). Ask it to run, through its Bash tool:

```bash
printf '#!/bin/bash\nif then\n' > hooktest-live.sh
```

Expected: the transcript shows a `PostToolUse:Bash` hook error block whose text starts with `lint-edited: problems in hooktest-live.sh`, and Claude reacts to it. Then have it run `rm hooktest-live.sh` and confirm no hook output appears for that call.

- [ ] **Step 5: Measure the no-write cost**

Time the PostToolUse hook directly on a call that wrote nothing:

```bash
printf '{"session_id":"s1","tool_use_id":"m1","tool_name":"Bash","tool_input":{"command":"true"}}' | CLAUDE_PROJECT_DIR=$PWD .claude/hooks/mark-tool-start.sh
time (printf '{"session_id":"s1","tool_use_id":"m1","tool_name":"Bash","tool_input":{"command":"true"}}' | CLAUDE_PROJECT_DIR=$PWD .claude/hooks/lint-bash-edits.sh)
```

Expected: exit 0 in under 0.5 s. Record the number in the commit message body.

- [ ] **Step 6: Update CLAUDE.md**

Replace the bullet at line 34 with:

```markdown
- Claude Code hooks: `.claude/settings.json` runs `.claude/hooks/lint-edited.sh` after Edit/Write (and Serena edit tools). It prettier-formats and lints the one edited file, but only within `pnpm check`'s scope (prettier globs and top-level `bin/*`; `bash -n` + shellcheck only for `bin/lib/check`'s list, so sourced snippets like `colors/*.sh` and `bin/lib/` are skipped), exiting 2 so Claude sees problems. Files written through Bash (heredocs, `sed -i`, `tee`) get the same treatment: `mark-tool-start.sh` (PreToolUse Bash) drops a marker keyed by `session_id` and `tool_use_id` under `$TMPDIR/claude-lint-markers/`, and `lint-bash-edits.sh` (PostToolUse Bash) feeds every file newer than it to `lint-edited.sh`, or asks for `pnpm check` when more than 25 changed. Self-checks: `.claude/hooks/test-lint-edited.sh`, `.claude/hooks/test-lint-bash-edits.sh`.
```

In the permissions bullet on the next line, change "and the hook self-check" to "and the hook self-checks".

- [ ] **Step 7: Commit and push**

```bash
pnpm check
git add .claude/settings.json CLAUDE.md
git commit -m "Lint files written through Bash in the project hooks"
git push
```

### Task 3: Task tools on every model

**Files:**
- Modify: `agents/claude-settings.json` (`env`)
- Read: `bin/claude-config` (`restore_settings`, `save_settings`)
- Modify (conditional): whichever of `agents/README.md`, `README.md`, `CLAUDE.md` documents `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`

**Interfaces:**
- Consumes: `claude-config restore settings`, which merges the snapshot into `~/.claude/settings.json` with live values winning.
- Produces: `TaskCreate`, `TaskGet`, `TaskList`, `TaskUpdate` present in sessions on Fable 5.1, so j-mode's "open the todolist first" rule has a tool to open.

- [ ] **Step 1: Add the key to the tracked snapshot**

Run:

```bash
jq '.env["CLAUDE_CODE_ENABLE_TODO_TOOLS"] = "1" | .env |= (to_entries | sort_by(.key) | from_entries)' agents/claude-settings.json > agents/claude-settings.json.tmp && mv agents/claude-settings.json.tmp agents/claude-settings.json
git diff agents/claude-settings.json
```

Expected diff: one added line `"CLAUDE_CODE_ENABLE_TODO_TOOLS": "1",` inside `env`, nothing else.

- [ ] **Step 2: Dry-run the merge, then apply it**

Run: `claude-config restore settings --dry-run`
Expected: a line `merge ~/dotfiles/agents/claude-settings.json into ~/.claude/settings.json` (path spelling per `tildify`), no error.

Run: `claude-config restore settings && jq .env ~/.claude/settings.json`
Expected:

```json
{
  "CLAUDE_CODE_ENABLE_TODO_TOOLS": "1",
  "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
}
```

- [ ] **Step 3: Verify the tools appear on the pinned model**

Run in a new terminal (a new process reads the new env):

```bash
claude -p "Reply with only the names of your task-tracking tools, comma separated, or NONE."
```

Expected: `TaskCreate, TaskGet, TaskList, TaskUpdate` (order may differ). `NONE` means the setting did not take; check `jq .env ~/.claude/settings.json` and that no `--settings` flag or managed setting overrides it.

- [ ] **Step 4: Round-trip the snapshot**

Run: `claude-config save && git status --short agents/`
Expected: `agents/claude-settings.json` shows the same one-line diff as Step 1 and no other file changed. `save` keeps `CLAUDE_CODE_*` env keys, so the key survives.

- [ ] **Step 5: Document where the other env key is documented**

Run: `grep -n 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' agents/README.md README.md CLAUDE.md docs/*.md`
If it is listed anywhere, add directly beneath it, in the same list style: `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` gives the task tools (`TaskCreate` and friends) on every model; Claude Code only ships them by default on Claude 3.x, Opus 4 to 4.7, Sonnet 4 to 4.6 and Haiku 4.5, and jstack's j-mode expects a todolist. If the grep finds nothing, no docs change: `CLAUDE.md`'s "Claude config" bullet already states that `CLAUDE_CODE_*` env keys are tracked.

- [ ] **Step 6: Commit and push**

```bash
pnpm check
git add agents/claude-settings.json
git add -u agents/README.md README.md CLAUDE.md docs 2> /dev/null || true
git commit -m "Keep the task tools on every model"
git push
```

### Task 4: Disable hookify

**Files:**
- Modify (via `claude-config save`): `agents/claude-plugins.txt`

**Interfaces:**
- Consumes: `claude plugin disable`, `claude-config save`, `claude-catalog`.
- Produces: the line `plugin hookify@claude-plugins-official disabled`, so a fresh `./setup.sh` installs it off.

- [ ] **Step 1: Confirm there is still nothing for it to do**

Run: `find ~/dev ~/.claude -maxdepth 4 -name 'hookify.*.local.md'`
Expected: no output. hookify reads only `.claude/hookify.*.local.md` under the current project (`core/config_loader.py` line 210), and its four Python hooks (PreToolUse, PostToolUse, Stop, UserPromptSubmit) run on every cycle looking for them. The gain is hygiene more than speed: a no-rules spawn returns in 0.01 s (measured), so this removes about 20 ms per tool call. If a rule file appears here, stop and ask Jason whether it is wanted.

- [ ] **Step 2: Disable and record**

Run:

```bash
claude plugin disable hookify@claude-plugins-official
claude-config save
git diff agents/claude-plugins.txt
```

Expected diff: `-plugin hookify@claude-plugins-official` / `+plugin hookify@claude-plugins-official disabled`, nothing else. If `save` also writes unrelated changes (a plugin updated since the last save), keep them; they are the live state.

- [ ] **Step 3: Rebuild the catalog**

Run: `claude-catalog`
Expected: exit 0. `curated.toml` may still name hookify items; a disabled plugin is still installed, so the generator does not exit 1. If it does, remove the hookify entries it names from `agents/catalog/curated.toml` and rerun.

- [ ] **Step 4: Commit and push**

```bash
pnpm check
git add agents/claude-plugins.txt agents/catalog/curated.toml
git commit -m "Turn hookify off: no rule files anywhere, four idle hooks per cycle"
git push
```

### Task 5: security-guidance, keep or disable

**Files:**
- Read: `~/.claude/plugins/cache/claude-plugins-official/security-guidance/*/hooks/hooks.json`
- Read: `~/.claude/security/log.txt`
- Modify (only if the decision is "disable"): `agents/claude-plugins.txt` via `claude-config save`

**Interfaces:**
- Consumes: `claude plugin disable`, `claude-config save`.
- Produces: either no change, or the line `plugin security-guidance@claude-plugins-official disabled`.

What the plugin does on this machine, measured on 2026-10-08 (spec, "Review corrections"):

| Event | Handler | Cost here |
|---|---|---|
| UserPromptSubmit | `git stash create` baseline for a later diff review | one Python spawn per prompt, 0.10 to 0.16 s |
| PostToolUse Edit, Write | 25 built-in regex patterns (secrets, SQL and command injection, path traversal, insecure session config), warning injected as `additionalContext` | one spawn per edit |
| PostToolUse Bash, 7 entries | each gated by its own `if` (`git commit`, `git -C … commit`, `git push`, `git -C … push`, `gt create`, `gt modify`, `gt submit`), reviews the commit diff with a model | one spawn per commit or push; exits at once, "no API credentials" (9 log lines) |
| Stop, SubagentStop | model review of the turn's diff | one spawn per turn; exits at once, "no API credentials" (142 log lines) |
| SessionStart | state setup | one spawn per session |

The model reviews need `ANTHROPIC_API_KEY` or a passed OAuth token and have never run here. The regex reminders do run, in every repo on this machine.

- [ ] **Step 1: Confirm the facts still hold**

Run:

```bash
jq -c '.hooks.PostToolUse[] | select(.matcher=="Bash") | .hooks[] | .if' ~/.claude/plugins/cache/claude-plugins-official/security-guidance/*/hooks/hooks.json
grep -c 'LLM review disabled or no API credentials' ~/.claude/security/log.txt
grep -c -i 'review complete\|findings:' ~/.claude/security/log.txt
```

Expected: seven distinct `if` strings; the second count in the hundreds; the third 0. If the third is not 0, the model review has started running here; read those lines before deciding, because it then costs a model call per turn.

- [ ] **Step 2: Record the outcome**

Decided on 2026-10-08: keep. If Step 1's facts still hold, Task 5 ends here with no change. If the third count is no longer 0 (the model review has started running and now costs a model call per turn), stop and bring the log lines to Jason before anything else. The disable path, should the decision ever change:

```bash
claude plugin disable security-guidance@claude-plugins-official
claude-config save
pnpm check
git add agents/claude-plugins.txt
git commit -m "Turn security-guidance off: its reviews never ran, one spawn per prompt and edit"
git push
```

## Not doing, and why

- **Warp plugin.** Its scripts source `should-use-structured.sh`, which returns false and exits unless `WARP_CLI_AGENT_PROTOCOL_VERSION` is set, so outside Warp each hook is one bash spawn that exits at once. Warp is installed and used. Keep.
- **NotchBar hooks.** Jason's menu-bar agent status; nine events by design. Keep.
- **codegraph prompt-hook's 700-character miss injection.** `codegraph prompt-hook --help` lists no flag. Nothing local fixes it; an upstream request is Jason's call.
- **A j-mode wording patch for sessions without a task tool.** After Task 3 the tools exist on every model, and background and cloud sessions always have them. Not needed.
- **A status line mod, a context gauge, a Bash hold-and-preview guard, claude-skins, cache-tax, terminal-browser, reflect-mod rule capture, next-steps.** Each is a "no" in the spec's recommendation table with its reason: not possible (`statusLine` cannot be replaced), already shown by the status line, already gated by auto mode and the ask list, no pain point, or a model call per turn for a convenience.
- **A hook latency meter mod.** Reading the live `hooks.json` files and timing one spawn of each handler answered the fan-out question (about 10 ungated handlers per Bash call, 10 ms for hookify, 0.10 to 0.16 s for security-guidance's prompt hook) without a mod.

## Companion plan: jstack step band mod

A learning prototype, not a fix, now that Task 3 restores the task tools. Jason chose to plan it now; the plan is `docs/superpowers/plans/2026-10-08-jstack-step-band.md`, written from this sketch in the `~/dev/skills` repo's patch workflow (`docs/superpowers/plans/2026-10-01-jstack.md`, "Patch authoring workflow"). It runs after this plan, since Task 3 decides whether the todolist rule already has what it needs:

- Data shape first: `{ playbook: string, steps: { text: string, state: 'todo' | 'done' | 'skip', reason?: string }[], current: number }` in `$.state` under a typed `PluginState['jstack']`, mirrored to `$.store` by session id and reloaded in a `classic.SessionStart` hook filtered on `source: ['clear', 'resume', 'fork']` (claude-skins `register.tsx` lines 172 to 177).
- Files, added by a new `80-mod.patch` so `sync-jstack` regenerates them: `hooks/hooks.json` with `{ "modules": ["./register.tsx"] }`, `hooks/register.tsx`, `types/index.d.ts`, `tests/band.test.tsx`. `check-jstack` already runs `claude plugin validate`; add `claude plugin test` and `tsc --noEmit` to it, since validate and test do not type-check (issue #99771).
- Mechanism: `$.tool.register` a private `step` tool with `isDeferred: false` (2.1.293 or later), answered by a `tool.call` hook returning `{ result }` at zero model cost (savvy-progress `register.tsx` lines 716 to 746); one-row `AbovePrompt` band composed with `const below = await next(e)` and a bail on `e.props.hasSurvey` (reflect-mod `register.tsx` lines 379 to 405); theme keys, not hex; `.catch` on every hook even though none gates.
- Proof: `claude plugin test` mounts `AbovePrompt` on `terminal` and `desktop`; one `--plugin-dir` run where `claude plugin validate` prints `calls: $.tool.register` and the band changes after a `step` call.

## Decisions (taken by Jason on 2026-10-08)

1. **Task tools on (Task 3).** Decided: on. The docs note the tools' definitions and reminders take context on newer models; j-mode's playbooks are written around a visible todolist, so the context is spent on purpose.
2. **25-file cap and an always-on `find` (Task 1).** Decided: as planned. Every Bash call in this repo pays one `find` over about 6,000 files (0.15 s measured) and one marker touch. Revisit only if the cost shows up in practice.
3. **security-guidance (Task 5).** Decided: keep. The 25 regex reminders run on every edit in every repo here; the never-run model reviews cost one short spawn per prompt and turn. No upstream report. Task 5 is therefore Step 1 only (confirm the facts still hold) and no change.
4. **hookify off (Task 4).** Decided: disable. Hygiene, not speed: about 20 ms per tool call. Reverse with `claude plugin enable hookify@claude-plugins-official && claude-config save`.
5. **The step band mod.** Decided: write its plan now, as `docs/superpowers/plans/2026-10-08-jstack-step-band.md`, executed after this plan. The sketch below is its starting point.
6. **Execution.** Not started. Jason reviews both plans first, then picks native or subagent-driven execution.
