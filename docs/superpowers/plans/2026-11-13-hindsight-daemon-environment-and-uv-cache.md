# Hindsight Daemon Environment and uv Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Hindsight daemon runs from one reviewed, locked environment that never multiplies, and `sysup` prunes the uv cache when it safely can.

**Architecture:** A tracked uv project (`hindsight/pyproject.toml` + `uv.lock`) pins `hindsight-embed`, `hindsight-api` and all 231 resolved dependencies. `hindsight-memory init|upgrade` copies both files to `~/.hindsight/daemon-env`, syncs a `.venv` there and sets `embedPackagePath` in `coding-agent.json`, so the vendor's hook runs `uv run --directory ~/.hindsight/daemon-env hindsight-embed` and `hindsight-embed` starts the `hindsight-api` beside it with no `uvx`. `sysup` gets a `uv cache` step that prunes with a short lock timeout and reports a busy cache instead of waiting.

**Tech Stack:** bash (`bin/hindsight-memory`, `bin/sysup`, their `bin/lib/test-*` self-checks), uv 0.13, jq.

**Spec:** `docs/superpowers/specs/2026-11-13-hindsight-daemon-environment-and-uv-cache.md`. Read its Goal and the owner's decisions 1 to 6 first. Task 1 builds decision 3 (A), Task 2 builds decisions 1 and 4 (the prune step and B), Task 4 is decision 5 (C), and decision 6 (D) is already carried out.

## Global Constraints

- Never run `sysup`, `./setup.sh` or `hindsight-memory init|upgrade|uninstall` on this Mac outside Task 3 and Task 4 Step 6. The self-checks use stubs and a fixture `HOME`.
- `uv cache prune` never gets `--force`, and nothing in this plan runs a prune against the real `~/.cache/uv` except the owner in Task 3.
- Every `hindsight-embed` call names its profile with `-p`, except `profile create` and `profile delete`, which take the name as an argument. A call without one can start a second daemon on port 8888 with its own database (spec fact 16). After any hand-run `hindsight-embed` command, `lsof -nP -iTCP:8888 -sTCP:LISTEN` must print nothing.
- The versions appear in exactly one place: `hindsight/pyproject.toml`. `bin/hindsight-memory` reads `EMBED_VERSION` from it. `CODING_AGENTS_VERSION` stays in the script.
- `requires-python = ">=3.13,<3.14"`, the interpreter the cached environments already use (`pyvenv.cfg`: 3.13.15).
- The environment directory is `~/.hindsight/daemon-env` (override `HINDSIGHT_DAEMON_ENV`). It is written into the config as an absolute path, because the plugin passes `embedPackagePath` to `uv run --directory` as it is, with no `~` expansion (`daemon-start.js`, `raw.embedPackagePath`). The environment variable `HINDSIGHT_EMBED_PACKAGE_PATH` sets the same key; this plan does not use it.
- `sysup` report contract (`.claude/rules/sysup.md`): one status line per step; `changed` only on a real before/after difference; a failed step never aborts the run.
- Every commit passes `pnpm check`. Docs change in the same commit as the behavior. Commit subjects: short, imperative, sentence case, no prefix.
- `docs/superpowers/` and `tilde/.claude/rules/jstack-models.md` are not hand-formatted (`.prettierignore`).

## Review Focus

1. **`uv` missing or `uv sync` failing during `init`** (offline, PyPI down): the config must not gain `embedPackagePath` for an environment that does not exist, or the daemon cannot start at all. Expected: the installed lock is removed, the key is unset until a sync succeeds, a warning names `hindsight-memory upgrade`, and the vendor's `uvx` path keeps working meanwhile. Test in Task 1.
2. **A hand-edited `embedPackagePath`** in the config: `merge_defaults` lets existing keys win, so a stale path would survive. Expected: like `embedVersion`, this key always follows the script. Test in Task 1.
3. **The lock changes while the daemon runs** (a pin bump pulled by `sysup`): the running daemon keeps the old environment until it restarts. Expected: `upgrade` stops the daemon after a sync that changed the lock, and only then, and a stop that hangs cannot stall `sysup`. Test in Task 1.
4. **The cache is busy on every `sysup` run** (sessions are usually open): the step must cost seconds, not the default 300, and must not fail the run. Test in Task 2.
5. **`uv cache prune` exits non-zero for a reason other than the lock** (permissions, a full disk): that is a `fail` line with the command, not the busy branch. Test in Task 2.

---

### Task 1: Run the daemon from a locked environment

**Files:**
- Create: `hindsight/pyproject.toml`, `hindsight/uv.lock`
- Modify: `bin/hindsight-memory`, `bin/lib/test-hindsight-memory`, `.gitignore` (add `hindsight/.venv/` beside `settings/.venv/`), `renovate.json`
- Modify (docs, same commit): `.claude/rules/hindsight-wiring.md`, `tilde/.claude/rules/hindsight.md`, `setup/README.md` (the Hindsight bullet near line 137), `docs/privacy.md` (line 28's last sentence), `docs/updating.md` (the Hindsight bullet near line 23), the one-line description of the self-check in `bin/lib/check` (near line 129)
- Do not add `hindsight/` to the tree in `CLAUDE.md`: the file is 11,995 of its 12,000 byte cap (`bin/lib/test-conventions`).

**Interfaces:**
- Produces: `~/.hindsight/daemon-env/{pyproject.toml,uv.lock,.venv}`; config key `embedPackagePath` (absolute path, the plugin passes it through unexpanded); `hindsight-memory upgrade` prints `daemon environment updated` when the installed lock changed. Task 2 does not parse that line: `sysup`'s before/after checksum gains the lock file.
- New overrides for the self-check: `HINDSIGHT_MEMORY_UV` (instead of `uv`), `HINDSIGHT_DAEMON_ENV` (instead of `~/.hindsight/daemon-env`).

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
Expected: `Resolved 231 packages` (a few more or fewer as dependencies release) and `hindsight/uv.lock` exists. `uv lock` creates no `.venv`.

- [ ] **Step 2: Keep Renovate off the two pins**

Renovate is active here (`config:recommended`, PR 19) and would open a PR for each package alone, against "both together, behind a backup" (Task 4). Add to `packageRules` in `renovate.json`:

```json
{
  "description": "The Hindsight daemon moves with its hook package, behind a database backup: docs/superpowers/specs/2026-11-13-hindsight-daemon-environment-and-uv-cache.md",
  "matchPackageNames": ["hindsight-embed", "hindsight-api"],
  "enabled": false
}
```

- [ ] **Step 3: Write the failing self-check cases** in `bin/lib/test-hindsight-memory`

Move the `repo=` assignment from line 159 up to sit under `script=` (line 18); `set -u` is on and the new cases need it early. Add a `uv` stub to `$HOME/bin` that appends its arguments to `$HOME/uv.log`, exits 1 when `$HOME/uv-fails` exists, and on `sync` creates `$HINDSIGHT_DAEMON_ENV/.venv/bin/hindsight-embed`. Export `HINDSIGHT_MEMORY_UV="$HOME/bin/uv"` and `HINDSIGHT_DAEMON_ENV="$HOME/.hindsight/daemon-env"` with the other overrides. `HINDSIGHT_MEMORY_EMBED` stays set, so the existing cases keep their stub. In the two existing assertions that hold the literal `1.1.0` (lines 85 and 93), read the version from `hindsight/pyproject.toml` instead. Put the new cases after the `upgrade notices a newer release` check (line 108) and before `paths add` (line 109). Not earlier: line 101 asserts the installer ran exactly twice, and every `upgrade` runs it again.

```bash
check "init copies the lock" "$(cksum < "$repo/hindsight/uv.lock")" "$(cksum < "$HINDSIGHT_DAEMON_ENV/uv.lock")"
check "init syncs the environment frozen" "sync --frozen --directory $HINDSIGHT_DAEMON_ENV" "$(tail -1 "$HOME/uv.log")"
check "init points the hook at the environment" "$HINDSIGHT_DAEMON_ENV" "$(jq -r .embedPackagePath "$cfg")"
# Review Focus 2
jq '.embedPackagePath = "/stale"' "$cfg" > "$cfg.t" && mv "$cfg.t" "$cfg"
check_true "init again" hm init
check "a hand-edited embedPackagePath is reset" "$HINDSIGHT_DAEMON_ENV" "$(jq -r .embedPackagePath "$cfg")"
# Review Focus 3: an unchanged lock leaves the daemon alone, a changed one stops it once
: > "$HOME/embed.log"
check_true "upgrade, lock unchanged" hm upgrade
check "no daemon stop when the lock is unchanged" 0 "$(grep -c 'daemon stop' "$HOME/embed.log" || true)"
echo '# older' >> "$HINDSIGHT_DAEMON_ENV/uv.lock"
check "upgrade reports the change" "daemon environment updated" "$(hm upgrade | grep 'daemon environment')"
check "a changed lock stops the daemon once" 1 "$(grep -c -- '-p coding-agent daemon stop' "$HOME/embed.log")"
# Review Focus 1: a failed sync leaves no lock, so the hook goes back to uvx
touch "$HOME/uv-fails"
check_true "upgrade survives a failed sync" hm upgrade
check_true "a failed sync leaves no installed lock" [ ! -e "$HINDSIGHT_DAEMON_ENV/uv.lock" ]
check "a failed sync unsets embedPackagePath" null "$(jq -c .embedPackagePath "$cfg")"
rm "$HOME/uv-fails"
check_true "upgrade recovers" hm upgrade
check "embedPackagePath is back" "$HINDSIGHT_DAEMON_ENV" "$(jq -r .embedPackagePath "$cfg")"
# the script's own embed command, which Task 3 relies on
: > "$HOME/uv.log"
bash -c 'unset HINDSIGHT_MEMORY_EMBED; "$0" status' "$script" > /dev/null
check_true "status runs hindsight-embed from the environment" grep -qx -- "run --frozen --directory $HINDSIGHT_DAEMON_ENV hindsight-embed -p coding-agent daemon status" "$HOME/uv.log"
```

- [ ] **Step 4: Run it to see it fail**

Run: `bin/lib/test-hindsight-memory`
Expected: `FAIL: init copies the lock`.

- [ ] **Step 5: Implement in `bin/hindsight-memory`**

- `EMBED_VERSION` is read from `hindsight/pyproject.toml` with `sed -n 's/.*"hindsight-embed==\([^"]*\)".*/\1/p'`, the repo root resolved from the script's own path (`$(cd "$(dirname "$0")/.." && pwd -P)`). Fail with a clear message when it is empty.
- `env_dir=${HINDSIGHT_DAEMON_ENV:-$HOME/.hindsight/daemon-env}`. `uv_cmd=(${HINDSIGHT_MEMORY_UV:-uv})` goes inside the existing `# shellcheck disable=SC2206` block with the other three.
- `embed` moves out of the SC2206 block, because a `${VAR:-default}` cannot hold a quoted path. After `env_dir` is known:

  ```bash
  if [ -n "${HINDSIGHT_MEMORY_EMBED:-}" ]; then
    # shellcheck disable=SC2206 # a command plus arguments, split on purpose
    embed=($HINDSIGHT_MEMORY_EMBED)
  elif [ -x "$env_dir/.venv/bin/hindsight-embed" ] && [ -f "$env_dir/uv.lock" ]; then
    embed=("${uv_cmd[@]}" run --frozen --directory "$env_dir" hindsight-embed)
  else
    embed=(uvx "hindsight-embed@$EMBED_VERSION")
  fi
  ```

  It is set once, before any sync, so the first migration on a machine stops the old daemon through `uvx`, the command that started it.
- `sync_env()` sets a global `env_changed` (0 or 1) and never fails the script (the script runs under `set -euo pipefail`, and a missing `uv` is a failed sync, not an exit). It takes the `cksum` of the installed `uv.lock` (empty when there is none), runs `mkdir -p "$env_dir"`, copies the repo's `pyproject.toml` and `uv.lock` in, and runs `"${uv_cmd[@]}" sync --frozen --directory "$env_dir"` every time (about 1 s when nothing changed). On success, `env_changed=1` when the lock's `cksum` differs from before (a first sync counts). On failure it removes `$env_dir/uv.lock`, warns `the daemon environment did not build; run: hindsight-memory upgrade`, and leaves `env_changed=0`. No backup of the old pair is kept: without a lock, `merge_defaults` unsets the key and the hook is back on `uvx` until a sync succeeds.
- `merge_defaults` sets `.embedPackagePath = $p` only when `$env_dir/.venv/bin/hindsight-embed` exists and the installed `uv.lock` is byte-equal to the repo's (`cmp -s`); otherwise it deletes the key, so the hook falls back to `uvx hindsight-embed@<embedVersion>` and never runs `uv run` against a lock that is not the reviewed one. Like `embedVersion`, the key follows the script on every run.
- `cmd_init` and `cmd_upgrade` call `sync_env` before `merge_defaults`. `cmd_upgrade` then, when `env_changed` is 1, prints `daemon environment updated` and stops the daemon so the next prompt's hook starts it from the new environment: `"${embed[@]}" -p coding-agent daemon stop || true`, prefixed with `timeout 30` when `timeout` is on PATH (the `prune=(timeout 600 …)` pattern in `bin/sysup`), because `sysup` runs `upgrade` with no bound of its own. `cmd_init` never stops the daemon.
- Header comment: the line that says `embedVersion alone always follows the pin` now names `embedPackagePath` too; one line under `init` and `upgrade` names the environment; the two new overrides join the Overrides list. Each header line stays one sentence on one line (`help` renders it).

- [ ] **Step 6: Run the self-check and the gate**

Run: `bin/lib/test-hindsight-memory && help hindsight-memory > /dev/null && pnpm check`
Expected: every line `ok: …`, exit 0. Prettier does not check TOML or the lock (`bin/lib/check` globs `js,cjs,ts,md,json,sh`).

- [ ] **Step 7: Docs and instruction files**

- `.claude/rules/hindsight-wiring.md`: replace the first bullet. The hook-package pin is `CODING_AGENTS_VERSION` in the script, the daemon's versions are `hindsight/pyproject.toml`, and the `uv.lock` beside it is why the daemon does not run through `uvx` (this plan's spec). Add that `embedPackagePath` follows the script on every run and is unset whenever the installed lock is not the repo's.
- `tilde/.claude/rules/hindsight.md`: in the "Manage it" bullet, the daemon's versions are pinned in `hindsight/pyproject.toml` and the hook package's in `bin/hindsight-memory`.
- `setup/README.md` line 137: "pinned in the script" becomes the two places, and the sentence gains the locked environment at `~/.hindsight/daemon-env`.
- `docs/privacy.md` line 28: replace the last sentence (each build holds about 1.9 GB in the uv cache) with: the daemon runs from one environment at `~/.hindsight/daemon-env`.
- `docs/updating.md` Hindsight bullet: `sysup` also syncs the daemon's locked environment and restarts the daemon when the lock changed.
- `bin/lib/check` line 129 and the self-check's own header: add `uv` to the stubbed commands.

- [ ] **Step 8: Commit**

```bash
git add hindsight .gitignore renovate.json bin/hindsight-memory bin/lib/test-hindsight-memory bin/lib/check .claude/rules/hindsight-wiring.md tilde/.claude/rules/hindsight.md setup/README.md docs/privacy.md docs/updating.md
git commit -m "Run the Hindsight daemon from a locked environment"
```

---

### Task 2: Prune the uv cache in sysup

**Files:**
- Modify: `bin/sysup` (inside the `uv` block at lines 493 to 525, and `hindsight_state` near line 618), `bin/lib/test-sysup`
- Modify (docs, same commit): `docs/updating.md`, `.claude/rules/sysup.md`

**Interfaces:**
- Consumes: Task 1's `~/.hindsight/daemon-env/uv.lock`.
- Produces: a `uv cache` status line.

- [ ] **Step 1: Write the failing self-check cases** in `bin/lib/test-sysup`

The `uv` stub (lines 115 to 120) ignores its arguments today. Make it a `case "$1 $2"` dispatcher: the existing body under `tool upgrade`; `cache dir` prints `$HOME/.cache/uv`; `cache prune` writes `$UV_LOCK_TIMEOUT` to `$STATE/lock-timeout`, then, when `$STATE/cache-busy` exists, prints the two lines from spec fact 6 and exits 2, when `$STATE/cache-fails` exists prints `error: Permission denied` and exits 2, and otherwise removes `$HOME/.cache/uv/archive-v0/*` when `$STATE/cache-stale` exists and exits 0. Do not add runs. The file calls `run` 23 times and a `$STATE` flag stays set until an `rm` clears it, so say where each flag lives: the nothing-to-prune case needs no flag and belongs to the first run (line 193; no `archive-v0` directory at all, which is a fresh Mac). Set `cache-stale` and create 25 fixture directories `archive-v0/e$i`, each with an empty `pyvenv.cfg`, with the flags the "changes" run sets (line 239). Before the next run (the `rm` at line 296), clear `cache-stale`, create the 25 fixtures again and set `cache-busy`. Before the run that collects failures (the `touch` at line 336), clear `cache-busy` and set `cache-fails`, and clear `cache-fails` in the `rm` that follows that run. The dispatcher tests `cache-busy` first, so a busy flag left set would hide the failure case. `test-sysup` has `check_true` and `has` only, no `check`. Assertions, with the glyphs `bin/sysup` defines (`✔` ok, `↻` changed, `●` notice, `✖` fail):

```bash
check_true "cache: nothing to prune is ok" has '^✔ uv cache +nothing to prune$'
check_true "cache: the wait is bounded" [ "$(cat "$STATE/lock-timeout")" = 10 ]
check_true "cache: a prune that removed entries is a change" has '^↻ uv cache +pruned 25 entries$'
check_true "cache: busy is ok and carries the count" has '^✔ uv cache +in use, not pruned \(25 cached environments\)$'
check_true "cache: another failure names the command" has '^✖ uv cache +run: uv cache prune$'
```

- [ ] **Step 2: Run it to see it fail**

Run: `bin/lib/test-sysup`
Expected: `FAIL: cache: nothing to prune is ok`.

- [ ] **Step 3: Implement the step in `bin/sysup`**

Inside the existing `if command -v uv` block, after the tools `if`/`elif` chain (a failed `uv tool upgrade` does not skip it): `step "uv cache"`, then `uv_cache=$(uv cache dir 2> /dev/null) || uv_cache=''`. When it is empty, `status fail "uv cache" "run: uv cache dir"` and skip the prune. Otherwise count the entries before and after `UV_LOCK_TIMEOUT=10 capture uv cache prune` (the prefix reaches the command through the `capture` function in bash 3.2; checked). `sysup` runs under `set -euo pipefail` and `archive-v0` may not exist, so every count has this shape, which also strips the padding macOS `wc` adds:

```bash
{ find "$uv_cache/archive-v0" -mindepth 1 -maxdepth 1 2> /dev/null || true; } | wc -l | tr -d ' '
```

- exit 0 and the count dropped: `changed`, `pruned <before minus after> entries`.
- exit 0 and the count is the same: `ok`, `nothing to prune`.
- non-zero and the output contains `waiting for`: `ok`, `in use, not pruned (<N> cached environments)`, where N counts `archive-v0/*/pyvenv.cfg` the same guarded way. No notice (spec decision 4): sessions are usually open, and what a prune frees is unmeasured until Task 3.
- any other failure: `fail`, `run: uv cache prune`, then `show`.

One comment above the step: the timeout is 10 because uvx-launched MCP servers hold the lock for as long as their session is open, and uv's default wait is 300 s.

Also add `"${HINDSIGHT_DAEMON_ENV:-$HOME/.hindsight/daemon-env}/uv.lock"` to the files `hindsight_state` checksums, and change that step's `changed` text to `hooks, runtime or daemon environment updated`. Update the matching assertion in `test-sysup`.

- [ ] **Step 4: Run the self-check and the gate**

Run: `bin/lib/test-sysup && pnpm check`
Expected: exit 0.

- [ ] **Step 5: Docs**

- `docs/updating.md`, after the uv tools bullet: `sysup` prunes the uv cache (`uv cache prune`, waiting at most 10 s for the lock) and reports how many cached environments are waiting when open Claude Code sessions keep it busy.
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
Expected: `daemon environment updated`, exit 0, `UV_OFFLINE=1 uv run --directory ~/.hindsight/daemon-env python -c ''` exits 0 (the hook's `uv run` has no `--frozen`; this runs the same lock check with the network off and does not depend on the daemon, which `upgrade` has just stopped), `lsof -nP -iTCP:8888 -sTCP:LISTEN` prints nothing, `jq -r .embedPackagePath ~/.hindsight/coding-agent.json` prints `/Users/<you>/.hindsight/daemon-env`, and `pgrep -fl 'uvx hindsight-api'` prints nothing (the old daemon stopped).

- [ ] **Step 3: Prove the hook's cold start**

Open a new Claude Code session in `~/dev/dotfiles` and send one prompt. Then run: `pgrep -fl hindsight-api`, the Step 1 bank count, and `tail -3 ~/.hindsight/coding-agents-logs/plugin.log`.
Expected: one process whose path starts with `~/.hindsight/daemon-env/.venv/bin/python`, no `uv tool uvx hindsight-api` process, the same bank count, the 🧠 banner in the session, and no error in the log tail. If the daemon does not start, go back in this order, because every `hindsight-memory upgrade` (so every `sysup`) sets the key again: `git revert <Task 1's commit>` (Task 2 also edited the Hindsight bullet's neighbour in `docs/updating.md`; keep Task 2's bullet if the revert conflicts there), `pnpm check`, push, then `jq 'del(.embedPackagePath)' ~/.hindsight/coding-agent.json` through a temp file. Report the log tail and stop.

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

- [x] **Step 6: Stale leftovers (decision D)**

Done on 2026-11-14: the owner said yes and `~/.pg0/instances/hindsight-embed-` was removed (spec decision 6). Leave `coding-agent.json.pre-pages.bak` and `.hindsight-backup` alone.

- [ ] **Step 7: Write down what was measured, then commit**

Spec: add the cold-start proof and the prune's freed size as "Verified facts" rows and remove the matching "Not verified" lines. Memory `uv-cache-prune-in-sysup`: replace the "interpretation, not measured" paragraph with the measured cause and the freed size, and drop the constraints the code now carries.

```bash
git add docs/superpowers/specs/2026-11-13-hindsight-daemon-environment-and-uv-cache.md
git commit -m "Record the Hindsight daemon move and the first measured prune"
```

---

### Task 4: Bump the pins (decision C, its own commit)

Both pins move together, because no vendor page says which hook versions work with which server versions. Spec fact 14 lists what is known about the releases.

**Files:**
- Modify: `hindsight/pyproject.toml`, `hindsight/uv.lock`, `bin/hindsight-memory` (`CODING_AGENTS_VERSION`, and `defaults()` only if a key was renamed), `bin/lib/test-hindsight-memory`
- Modify for the 0.8.7 tool rename: `tilde/.claude/rules/hindsight.md`, `agents/catalog/curated.toml`, and any permission rule in `agents/claude-settings.json` or `.claude/settings.json` that names an old tool (`grep -rn knowledge_page . --exclude-dir=.git --exclude-dir=docs`)

- [ ] **Step 1: Read what changed**

Read https://hindsight.vectorize.io/changelog/integrations/coding-agents for 0.8.4 to the newest version `npm pack --dry-run --json @vectorize-io/hindsight-coding-agents | jq -r '.[0].version'` prints, and the GitHub release notes of vectorize-io/hindsight for every server release after 1.1.0. Then settle the two things the spec could not: stage the new hook package in a scratch directory (`npm pack @vectorize-io/hindsight-coding-agents@<version>` there, untar) and run `grep -c 'knowledge_page' package/dist/mcp-server.js` and `grep -o 'embedPackagePath[^,]*' package/dist/daemon-start.js | head -3`.
Expected: a written list of renamed tools and config keys with the URL for each; whether the old tool names survive in the MCP server; and `embedPackagePath` still mapped to `uv run --directory`. If `embedPackagePath` is gone, stop and report: Task 1's design depends on it.

- [ ] **Step 2: Bump and re-lock**

Set both versions in `hindsight/pyproject.toml` to the newest release, run `uv lock --directory hindsight`, and read which packages the lock gained or lost (`git diff hindsight/uv.lock | grep '^[+-]name'`).
Expected: the two Hindsight packages move; new dependencies, if any, are named in the commit body.

- [ ] **Step 3: Try it on a throwaway profile before the live daemon**

In a scratch copy of `hindsight/`: `uv sync --frozen`, then, every call with its profile:

```bash
uv run hindsight-embed profile create pinbump --port 9199 --env HINDSIGHT_API_LLM_PROVIDER=claude-code --env HINDSIGHT_API_LLM_MODEL=claude-haiku-5-5
```

```bash
uv run hindsight-embed -p pinbump daemon start
```

```bash
curl -sf http://127.0.0.1:9199/health
```

Run `lsof -nP -iTCP:8888 -sTCP:LISTEN` right after `profile create` as well: it must print nothing (spec fact 16's cause was found by elimination, so check after every call). Expected from the last command: `"status":"healthy"`. Then `uv run hindsight-embed -p pinbump daemon stop`, `uv run hindsight-embed profile delete pinbump`, check `lsof -nP -iTCP:8888 -sTCP:LISTEN` and `pgrep -fl pinbump` print nothing, and ask the owner before removing `~/.pg0/instances/hindsight-embed-pinbump`. This sequence passed for 1.1.0 on 2026-11-13.

- [ ] **Step 4: Bump `CODING_AGENTS_VERSION`** to the version Step 1's `npm pack` printed, apply any key rename to `defaults()` and its test, rename the tools in the files listed above, and run `bin/lib/test-hindsight-memory && pnpm check`.

- [ ] **Step 5: Commit**

```bash
git add hindsight bin/hindsight-memory bin/lib/test-hindsight-memory tilde/.claude/rules/hindsight.md agents/catalog/curated.toml
git add agents/claude-settings.json .claude/settings.json # only if Step 4 renamed a tool in a permission rule
git commit -m "Update Hindsight to <daemon version> and its hook package to <package version>"
```

- [ ] **Step 6: Apply on this Mac, on the owner's word, behind a backup**

The new server migrates the database at its first start and no downgrade is documented, so the copy is the way back. With every Claude Code and Codex session closed:

```bash
hindsight-memory status | head -3
```

```bash
uv run --frozen --directory ~/.hindsight/daemon-env hindsight-embed -p coding-agent daemon stop
```

```bash
pgrep -fl 'instances/hindsight-embed-coding-agent'
```

That must print nothing before the copy: a daemon that is killed can leave its Postgres running (spec fact 16), and a copy of a live data directory is not a backup. If it prints a process, stop it with `~/.pg0/installation/18.1.0/bin/pg_ctl -D ~/.pg0/instances/hindsight-embed-coding-agent/data stop -m fast`.

```bash
cp -Rp ~/.pg0/instances/hindsight-embed-coding-agent ~/.pg0/instances/hindsight-embed-coding-agent.before-bump
```

```bash
hindsight-memory upgrade
```

Then repeat Task 3 Step 3 and Step 1's bank count. Expected: the same bank count, the 🧠 banner, a search through the renamed tool returns pages. To go back, in this order, so no hook can start the old server against the migrated database:

1. Close every Claude Code and Codex session.
2. Stop the daemon with the `daemon stop` command above, then the `pgrep` check (and `pg_ctl stop`) above.
3. `mv ~/.pg0/instances/hindsight-embed-coding-agent ~/.pg0/instances/hindsight-embed-coding-agent.after-bump`, then `mv ~/.pg0/instances/hindsight-embed-coding-agent.before-bump ~/.pg0/instances/hindsight-embed-coding-agent`. Two moves, because `mv` onto an existing directory nests the copy inside it.
4. `git revert` the Step 5 commit, `pnpm check`, push.
5. `hindsight-memory upgrade`, then Task 3 Step 3.

The owner removes the `.before-bump` copy (or `.after-bump`) once a week of sessions has gone by without a problem.

---

## Later, not in this plan

- astral-sh/uv#20116 (`cache-autoprune`, and `uvx` releasing the lock before it runs the command). When it ships, the busy branch in Task 2 mostly disappears; re-read the step then.
- The browser-use plugin's `uvx … browser-use@latest`, 61 cached environments. Its launch line belongs to the plugin; the prune covers it.
