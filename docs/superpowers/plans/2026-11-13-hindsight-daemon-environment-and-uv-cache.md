# Hindsight Daemon Environment and uv Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Hindsight daemon runs from one reviewed, locked environment that never multiplies, and `sysup` prunes the uv cache when it safely can.

**Architecture:** A tracked uv project (`hindsight/pyproject.toml` + `uv.lock`) pins `hindsight-embed`, `hindsight-api` and all 231 resolved dependencies. `hindsight-memory init|upgrade` copies both files to `~/.hindsight/daemon-env`, syncs a `.venv` there and sets `embedPackagePath` in `coding-agent.json`, so the vendor's hook runs `uv run --directory ~/.hindsight/daemon-env hindsight-embed` and `hindsight-embed` starts the `hindsight-api` beside it with no `uvx`. `sysup` gets a `uv cache` step that prunes with a short lock timeout and reports a busy cache instead of waiting.

**Tech Stack:** bash (`bin/hindsight-memory`, `bin/sysup`, their `bin/lib/test-*` self-checks), uv 0.13, jq.

**Spec:** `docs/superpowers/specs/2026-11-13-hindsight-daemon-environment-and-uv-cache.md`. Read its Goal, the owner's decisions and the open decisions A to D first. Tasks 1 and 2 assume A and B are answered as recommended; Task 4 is decision C, Task 3 Step 6 is decision D.

## Global Constraints

- Never run `sysup`, `./setup.sh` or `hindsight-memory init|upgrade|uninstall` on this Mac outside Task 3. The self-checks use stubs and a fixture `HOME`.
- `uv cache prune` never gets `--force`, and nothing in this plan runs a prune against the real `~/.cache/uv` except the owner in Task 3.
- The versions appear in exactly one place: `hindsight/pyproject.toml`. `bin/hindsight-memory` reads `EMBED_VERSION` from it. `CODING_AGENTS_VERSION` stays in the script.
- `requires-python = ">=3.13,<3.14"`, the interpreter the cached environments already use (`pyvenv.cfg`: 3.13.15).
- The environment directory is `~/.hindsight/daemon-env` (override `HINDSIGHT_DAEMON_ENV`). It is written into the config as an absolute path, because whether the plugin expands `~` in `embedPackagePath` is unchecked.
- `sysup` report contract (`.claude/rules/sysup.md`): one status line per step; `changed` only on a real before/after difference; a failed step never aborts the run.
- Every commit passes `pnpm check`. Docs change in the same commit as the behavior. Commit subjects: short, imperative, sentence case, no prefix.
- `docs/superpowers/` and `tilde/.claude/rules/jstack-models.md` are not hand-formatted (`.prettierignore`).

## Review Focus

1. **`uv` missing or `uv sync` failing during `init`** (offline, PyPI down): the config must not gain `embedPackagePath` for an environment that does not exist, or the daemon cannot start at all. Expected: the key is left unset, a warning names `hindsight-memory upgrade`, and the vendor's `uvx` path keeps working. Test in Task 1.
2. **A hand-edited `embedPackagePath`** in the config: `merge_defaults` lets existing keys win, so a stale path would survive. Expected: like `embedVersion`, this key always follows the script. Test in Task 1.
3. **The lock changes while the daemon runs** (a pin bump pulled by `sysup`): the running daemon keeps the old environment until it restarts. Expected: `upgrade` stops the daemon after a sync that changed the lock, and only then. Test in Task 1.
4. **The cache is busy on every `sysup` run** (sessions are usually open): the step must cost seconds, not the default 300, and must not fail the run. Test in Task 2.
5. **`uv cache prune` exits non-zero for a reason other than the lock** (permissions, a full disk): that is a `fail` line with the command, not the busy branch. Test in Task 2.

---

### Task 1: Run the daemon from a locked environment

**Files:**
- Create: `hindsight/pyproject.toml`, `hindsight/uv.lock`
- Modify: `bin/hindsight-memory`, `bin/lib/test-hindsight-memory`
- Modify (docs, same commit): `.claude/rules/hindsight-wiring.md`, `tilde/.claude/rules/hindsight.md`, `docs/privacy.md` only if its Hindsight line names `uvx`, `docs/forking.md` only if it lists the pins

**Interfaces:**
- Produces: `~/.hindsight/daemon-env/{pyproject.toml,uv.lock,.venv}`; config key `embedPackagePath` (absolute path); `hindsight-memory upgrade` prints the line `daemon environment updated` when the installed lock changed (Task 2 does not parse it; `sysup`'s existing before/after checksum gains the lock file instead).
- New overrides for the self-check, same style as the existing ones: `HINDSIGHT_MEMORY_UV` (instead of `uv`), `HINDSIGHT_DAEMON_ENV` (instead of `~/.hindsight/daemon-env`).

- [ ] **Step 1: Create the project and its lock**

`hindsight/pyproject.toml`:

```toml
# The Hindsight daemon's environment. bin/hindsight-memory copies this file and
# uv.lock to ~/.hindsight/daemon-env and syncs a .venv there. hindsight-api sits
# beside hindsight-embed so the daemon starts from this environment, not from
# `uvx hindsight-api@<version>`, which re-resolved ~200 unbounded dependencies
# and cached a new 2 GiB environment at every cold start.
# Bumping a version here, then `uv lock --directory hindsight`, is a reviewed commit.
[project]
name = "hindsight-daemon"
version = "0"
requires-python = ">=3.13,<3.14"
dependencies = ["hindsight-embed==1.1.0", "hindsight-api==1.1.0"]
```

Run: `uv lock --directory hindsight`
Expected: `Resolved 231 packages` (the count may differ by a few as dependencies release), and `hindsight/uv.lock` exists. No `.venv` is created by `uv lock`.

- [ ] **Step 2: Write the failing self-check cases** in `bin/lib/test-hindsight-memory`

Add a `uv` stub that logs its arguments to `$HOME/uv.log`, exits 1 when `$HOME/uv-fails` exists, and on `sync` creates `$HINDSIGHT_DAEMON_ENV/.venv/bin/hindsight-embed`. Export `HINDSIGHT_MEMORY_UV="$HOME/bin/uv"` and `HINDSIGHT_DAEMON_ENV="$HOME/.hindsight/daemon-env"`. Leave `HINDSIGHT_MEMORY_EMBED` set as today so existing cases keep their stub. Cases, in the file's `check`/`check_true` style:

```bash
check "init copies the lock" "$(cksum < "$repo/hindsight/uv.lock")" "$(cksum < "$HINDSIGHT_DAEMON_ENV/uv.lock")"
check "init syncs the environment frozen" "sync --frozen --directory $HINDSIGHT_DAEMON_ENV" "$(tail -1 "$HOME/uv.log")"
check "init points the hook at the environment" "$HINDSIGHT_DAEMON_ENV" "$(jq -r .embedPackagePath "$cfg")"
check "embedVersion follows pyproject" "$(sed -n 's/.*"hindsight-embed==\([^"]*\)".*/\1/p' "$repo/hindsight/pyproject.toml")" "$(jq -r .embedVersion "$cfg")"
# Review Focus 2
jq '.embedPackagePath = "/stale"' "$cfg" > "$cfg.t" && mv "$cfg.t" "$cfg"
check_true "init again" hm init
check "a hand-edited embedPackagePath is reset" "$HINDSIGHT_DAEMON_ENV" "$(jq -r .embedPackagePath "$cfg")"
# Review Focus 3: unchanged lock leaves the daemon alone, a changed one stops it
: > "$HOME/embed.log"; check_true "upgrade, lock unchanged" hm upgrade
check "no daemon stop when the lock is unchanged" 0 "$(grep -c 'daemon stop' "$HOME/embed.log" || true)"
echo '# changed' >> "$HINDSIGHT_DAEMON_ENV/uv.lock"
check "upgrade reports the change" "daemon environment updated" "$(hm upgrade | grep 'daemon environment')"
check "a changed lock stops the daemon once" 1 "$(grep -c -- '-p coding-agent daemon stop' "$HOME/embed.log")"
# Review Focus 1
rm -rf "$HINDSIGHT_DAEMON_ENV"; touch "$HOME/uv-fails"
check_true "init survives a failed sync" hm init
check "a failed sync leaves embedPackagePath unset" null "$(jq -c .embedPackagePath "$cfg")"
rm "$HOME/uv-fails"
```

`$repo` is the repo root the test already derives for `$script`.

- [ ] **Step 3: Run it to see it fail**

Run: `bin/lib/test-hindsight-memory`
Expected: `FAIL: init copies the lock` (the directory does not exist yet).

- [ ] **Step 4: Implement in `bin/hindsight-memory`**

- `EMBED_VERSION` is read from `hindsight/pyproject.toml` with the `sed` expression in the test, the repo root resolved from the script's own path (`$(cd "$(dirname "$0")/.." && pwd -P)`); fail with a clear message when it is empty.
- `env_dir=${HINDSIGHT_DAEMON_ENV:-$HOME/.hindsight/daemon-env}` and `uv_cmd=(${HINDSIGHT_MEMORY_UV:-uv})`.
- The default `embed` command becomes `"${uv_cmd[@]}" run --frozen --directory "$env_dir" hindsight-embed` when `$env_dir/.venv` exists, else the current `uvx hindsight-embed@$EMBED_VERSION` (a machine that never synced still gets `status` and `uninstall`).
- `sync_env()`: returns 0 and prints nothing when both files already match and `.venv` exists; otherwise copies `pyproject.toml` and `uv.lock`, runs `"${uv_cmd[@]}" sync --frozen --directory "$env_dir"`, and prints `daemon environment updated`. On a failed sync it removes the copied lock (so the next run retries), warns `the daemon environment did not build; run: hindsight-memory upgrade`, and returns 1.
- `merge_defaults` sets `.embedPackagePath = $p` when `sync_env` succeeded or the environment already exists, and deletes the key otherwise. It follows the script on every run, like `embedVersion`.
- `cmd_init` and `cmd_upgrade` call `sync_env` before `merge_defaults`. `cmd_upgrade` runs `"${embed[@]}" -p coding-agent daemon stop || true` only when `sync_env` printed the update line. That covers the first sync on a machine whose daemon still runs from `uvx`, and stopping a daemon that is not running is harmless. `cmd_init` never stops it.
- Header comment: one line under `init` and `upgrade` naming the environment, and the two new overrides in the Overrides list.

- [ ] **Step 5: Run the self-check and the gate**

Run: `bin/lib/test-hindsight-memory && help hindsight-memory > /dev/null && pnpm check`
Expected: every line `ok: …`, exit 0. If `pnpm check` lints `hindsight/uv.lock` or `pyproject.toml` and fails, add `hindsight/uv.lock` to `.prettierignore` (a generated file) and say so in the commit body.

- [ ] **Step 6: Update the instruction files**

- `.claude/rules/hindsight-wiring.md`: replace the first bullet with: the hook-package pin is `CODING_AGENTS_VERSION` in the script, the daemon's versions are `hindsight/pyproject.toml`, and `uv.lock` beside it is why the daemon no longer runs through `uvx` (spec `2026-11-13-hindsight-daemon-environment-and-uv-cache.md`). Add: `embedPackagePath` follows the script on every run.
- `tilde/.claude/rules/hindsight.md`: in the "Manage it" bullet, the pinned versions are now in two files as above.

- [ ] **Step 7: Commit**

```bash
git add hindsight bin/hindsight-memory bin/lib/test-hindsight-memory .claude/rules/hindsight-wiring.md tilde/.claude/rules/hindsight.md
git commit -m "Run the Hindsight daemon from a locked environment"
```

---

### Task 2: Prune the uv cache in sysup

**Files:**
- Modify: `bin/sysup` (after the `uv` tools step near line 493, and `hindsight_state` near line 618), `bin/lib/test-sysup`
- Modify (docs, same commit): `docs/updating.md`, `.claude/rules/sysup.md`

**Interfaces:**
- Consumes: Task 1's `~/.hindsight/daemon-env/uv.lock`.
- Produces: a `uv cache` status line.

- [ ] **Step 1: Write the failing self-check cases** in `bin/lib/test-sysup`

Extend the `uv` stub: on `cache dir` print `$HOME/.cache/uv`; on `cache prune`, when `$STATE/cache-busy` exists print the two real lines from spec fact 6 and exit 2, when `$STATE/cache-fails` exists print `error: Permission denied` and exit 2, otherwise remove `$HOME/.cache/uv/archive-v0/*` when `$STATE/cache-stale` exists and exit 0. Record `UV_LOCK_TIMEOUT` to `$STATE/lock-timeout`. Create 25 fixture directories `archive-v0/e$i` each holding an empty `pyvenv.cfg` for the busy and stale cases. Assertions:

```bash
check_true "cache: nothing to prune is ok" has '^✔ uv cache +nothing to prune$'
check "cache: the wait is bounded" 10 "$(cat "$STATE/lock-timeout")"
check_true "cache: a prune that removed entries is a change" has '^● uv cache +pruned 25 entries$'
check_true "cache: busy with many environments is a notice" has '^● uv cache +in use, 25 cached environments; close Claude Code sessions, then run: uv cache prune$'
check_true "cache: busy with few environments is ok" has '^✔ uv cache +in use, not pruned$'
check_true "cache: another failure names the command" has '^✖ uv cache +run: uv cache prune$'
```

Use the glyphs the file's existing `ok`, `changed`, `notice` and `fail` assertions use; the ones above are placeholders for them.

- [ ] **Step 2: Run it to see it fail**

Run: `bin/lib/test-sysup`
Expected: `FAIL: cache: nothing to prune is ok`.

- [ ] **Step 3: Implement the step in `bin/sysup`**

Inside the existing `if command -v uv` block, after the tools branch: `step "uv cache"`; count entries with `find "$(uv cache dir)/archive-v0" -mindepth 1 -maxdepth 1 | wc -l` before and after; run `UV_LOCK_TIMEOUT=10 capture uv cache prune`.

- exit 0 and the count dropped: `changed`, `pruned <before minus after> entries`.
- exit 0 and the count is the same: `ok`, `nothing to prune`.
- non-zero and the output contains `waiting for lock`: count `archive-v0/*/pyvenv.cfg`; 20 or more is `notice` with the text in the test, fewer is `ok`, `in use, not pruned`.
- any other failure: `fail`, `run: uv cache prune`, then `show`.

One comment above the step: the timeout is 10 because uvx-launched MCP servers hold the lock for as long as their session is open, and uv's default wait is 300 s.

Also add `"${HINDSIGHT_DAEMON_ENV:-$HOME/.hindsight/daemon-env}/uv.lock"` to the files `hindsight_state` checksums, and change the `changed` text to `hooks, runtime or daemon environment updated`. Update the matching assertion in `test-sysup`.

- [ ] **Step 4: Run the self-check and the gate**

Run: `bin/lib/test-sysup && pnpm check`
Expected: exit 0.

- [ ] **Step 5: Docs**

- `docs/updating.md`, after the uv tools bullet: `sysup` prunes the uv cache (`uv cache prune`, waiting at most 10 s for the lock) and says so when open Claude Code sessions keep it busy. In the Hindsight bullet: it also syncs the daemon's locked environment.
- `.claude/rules/sysup.md`, one bullet **uv cache**: the 10 s `UV_LOCK_TIMEOUT` and why, never `--force` (it ignores the in-use check), `changed` comes from the `archive-v0` entry count, and a prune removes every cached tool environment, which the next `uvx` rebuilds.

- [ ] **Step 6: Commit**

```bash
git add bin/sysup bin/lib/test-sysup docs/updating.md .claude/rules/sysup.md
git commit -m "Prune the uv cache in sysup"
```

---

### Task 3: Move this Mac's daemon over and measure the prune

This task changes the live machine. Start it only on the owner's word, and give the owner the Step 4 commands only after running each line here first where that is possible without a prune (memory: `vm-runbook-commands-tested-end-to-end`).

**Files:**
- Modify: the spec's "Verified facts" and "Not verified" sections; the memory `uv-cache-prune-in-sysup`.

- [ ] **Step 1: Record the before state**

Run: `curl -sf http://127.0.0.1:9077/v1/default/banks | jq '.banks | length'`, `du -sh ~/.pg0`, `pgrep -fl 'uvx hindsight-api'`.
Expected: a bank count (20 or more on 2026-11-13), about 1.2G, and one `uv tool uvx hindsight-api@1.1.0` line.

- [ ] **Step 2: Migrate**

Run: `hindsight-memory upgrade`
Expected: `daemon environment updated`, exit 0, `jq -r .embedPackagePath ~/.hindsight/coding-agent.json` prints `/Users/<you>/.hindsight/daemon-env`, and `pgrep -fl 'uvx hindsight-api'` prints nothing (the old daemon stopped).

- [ ] **Step 3: Prove the hook's cold start**

Open a new Claude Code session in `~/dev/dotfiles` and send one prompt. Then run: `pgrep -fl hindsight-api`, the Step 1 bank count, and `tail -3 ~/.hindsight/coding-agents-logs/plugin.log`.
Expected: one process whose path starts with `~/.hindsight/daemon-env/.venv/bin/python`, no `uv tool uvx hindsight-api` process, the same bank count, the 🧠 banner in the session, and no error in the log tail. If the daemon does not start, set it back with `jq 'del(.embedPackagePath)' ~/.hindsight/coding-agent.json` (through a temp file), report the log tail, and stop.

- [ ] **Step 4: The owner measures a real prune**

The owner quits every Claude Code session and runs, in a terminal:

```bash
df -k /System/Volumes/Data | awk 'NR==2{print $4}'
```

```bash
UV_LOCK_TIMEOUT=30 uv cache prune
```

```bash
df -k /System/Volumes/Data | awk 'NR==2{print $4}'
```

Expected: the prune prints `Removed N files (X)`. The difference of the two `df` numbers, in KiB, is the first real measurement of what a prune frees here. If it times out, `pgrep -fl 'uv tool uvx'` names the process still holding the lock.

- [ ] **Step 5: Check memory defence is applied**

Run: `curl -sf "http://127.0.0.1:9077/v1/default/banks/coding-agent::dotfiles" | jq '.. | .memory_defense? // empty'` (if that path 404s, list the routes with `curl -sf http://127.0.0.1:9077/openapi.json | jq -r '.paths | keys[]' | grep -i bank` and read the bank's config route).
Expected: `enabled: true` with the `sensitive_data` redact rule. If it is absent, record that in the spec as a finding; do not change the config in this task.

- [ ] **Step 6: Stale leftovers (decision D)**

Run: `cat ~/.pg0/instances/hindsight-embed-/instance.json` and `pgrep -fl 'instances/hindsight-embed-/'`.
Expected: no process. With the owner's yes, `rm -rf ~/.pg0/instances/hindsight-embed-`. Leave `coding-agent.json.pre-pages.bak` and `.hindsight-backup` alone.

- [ ] **Step 7: Write down what was measured, then commit**

Spec: add the cold-start proof and the prune's freed size as "Verified facts" rows and remove the matching "Not verified" lines. Memory `uv-cache-prune-in-sysup`: replace the "interpretation, not measured" paragraph with the measured cause and the freed size, and drop the constraints the code now carries.

```bash
git add docs/superpowers/specs/2026-11-13-hindsight-daemon-environment-and-uv-cache.md
git commit -m "Record the Hindsight daemon move and the first measured prune"
```

---

### Task 4: Bump the pins (decision C, its own commit)

**Files:**
- Modify: `hindsight/pyproject.toml`, `hindsight/uv.lock`, `bin/hindsight-memory` (`CODING_AGENTS_VERSION`, and `defaults()` only if a key was renamed)

- [ ] **Step 1: Read what changed**

Read https://hindsight.vectorize.io/changelog/integrations/coding-agents for 0.8.4 to the newest version `npm pack --dry-run --json @vectorize-io/hindsight-coding-agents | jq -r '.[0].version'` prints, and the GitHub release notes of vectorize-io/hindsight 1.2.0 and 1.2.1. Write down every renamed or removed config key, especially what 0.8.7's "Knowledge Pages to Pages" rename does to `autoInject: "pages"`, `pageTriggerCron` and `pageRefreshEveryTurns`.
Expected: a list, or "none", with the URL for each entry.

- [ ] **Step 2: Bump and re-lock**

Set both versions in `hindsight/pyproject.toml` to the newest release, run `uv lock --directory hindsight`, and read the `uv.lock` diff's added and removed package names (`git diff --stat` plus `git diff hindsight/uv.lock | grep '^[+-]name'`).
Expected: the two Hindsight packages move; new top-level dependencies, if any, are named in the commit body.

- [ ] **Step 3: Try it on a throwaway profile before the live daemon**

In a scratch copy of `hindsight/`: `uv sync --frozen`, then `uv run hindsight-embed profile create pinbump --port 9199 --env HINDSIGHT_API_LLM_PROVIDER=claude-code --env HINDSIGHT_API_LLM_MODEL=claude-haiku-5-5`, `uv run hindsight-embed -p pinbump daemon start`, `curl -sf http://127.0.0.1:9199/health`.
Expected: `"status":"healthy"`. Then `daemon stop`, `profile delete pinbump`, and `rm -rf ~/.pg0/instances/hindsight-embed-pinbump`. This is the sequence that passed for 1.1.0 on 2026-11-13.

- [ ] **Step 4: Bump `CODING_AGENTS_VERSION`** to the newest version Step 1's `npm pack` printed, apply any key rename to `defaults()` and its test, run `bin/lib/test-hindsight-memory && pnpm check`.

- [ ] **Step 5: Commit, then apply on this Mac on the owner's word** with `hindsight-memory upgrade`, and repeat Task 3 Step 3. A database migration between daemon versions is one-way; say so when asking.

```bash
git add hindsight bin/hindsight-memory bin/lib/test-hindsight-memory
git commit -m "Update Hindsight to <daemon version> and its hook package to <package version>"
```

---

## Later, not in this plan

- astral-sh/uv#20116 (`cache-autoprune`, and `uvx` releasing the lock before it runs the command). When it ships, the busy branch in Task 2 mostly disappears; re-read the step then.
- The browser-use plugin's `uvx … browser-use@latest`, 61 cached environments. Its launch line belongs to the plugin; the prune covers it.
