# Hindsight Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Claude Code and Codex automatic, per-repo, local long-term memory through the Hindsight hook package, installed at a pinned version and upgraded by these dotfiles, with an opt-in path list, a kill switch and an uninstall behind one `bin/` command.

**Architecture:** The vendor's installer (`npx -y @vectorize-io/hindsight-coding-agents@<pin> install claude-code codex --server daemon`) owns the hooks, the MCP registration and the local `hindsight-embed` daemon. A new `bin/hindsight-memory` script wraps it. `init` runs the installer when the config is missing, persists the extraction provider in the daemon profile, and merges the repo's defaults into `~/.hindsight/coding-agent.json` without overwriting edits. `upgrade` re-runs the pinned installer and reports a newer npm release as a notice. `paths`, `on`, `off`, `status` and `uninstall` manage it afterwards. `setup/misc.sh` calls `init`, `upup` calls `upgrade`, and the two model-invoked memory skills are dropped so memory lives in one place.

**Tech Stack:** bash 3.2, jq, the `skills` CLI, uv and node through mise, `@vectorize-io/hindsight-coding-agents` 0.8.2, `hindsight-embed` and `hindsight-api` 1.1.0.

**Spec:** `docs/superpowers/specs/2026-10-24-hindsight-memory.md`

## Global Constraints

- Scripts are bash 3.2 compatible (`#!/bin/bash`, no associative arrays, `[ ${#arr[@]} -eq 0 ]` guards under `set -u`), start with the `help`-renderable header comment, and pass `bash -n`, `shellcheck --severity=warning` and `prettier --check`. `${p/#$HOME/\~}` prints a literal backslash on bash 3.2, so `~` substitution is `"~${p#"$HOME"}"` behind a prefix test.
- Versions are pinned in one place, two constants at the top of `bin/hindsight-memory`: `CODING_AGENTS_VERSION=0.8.2` and `EMBED_VERSION=1.1.0`. Every `npx` and `uvx` call in the script uses them. Bumping them is a reviewed commit.
- Every machine-changing step is idempotent and warns instead of failing when its tool is missing (`command_exists uv`, `command_exists node`, `command_exists jq`).
- The extraction provider is `claude-code`. No API key is written anywhere by these dotfiles.
- `~/.hindsight/coding-agent.json` is never tracked in the repo. Defaults are merged into it additively, existing keys win. The installer itself writes only `serverMode` (and `apiUrl`/`apiToken` for the other modes), verified in `dist/installer.js`.
- Opt-in paths are stored as typed, trailing slash stripped, with `$HOME` or `$HOME/` collapsed to `~`. No `realpath`. The plugin expands only `~` and `~/`, normalises, and tests a literal prefix (`configuredDir` and `isWithin` in `dist/claude-sessionstart-hook.js`).
- The defaults merged by `init`:

  ```json
  {
    "serverMode": "daemon",
    "optInOnly": true,
    "optInPaths": ["~/dev"],
    "autoUpdate": false,
    "embedVersion": "1.1.0",
    "codebaseSurvey": false,
    "autoInject": "pages",
    "pageTriggerCron": "H */6 * * *",
    "pageRefreshEveryTurns": 10,
    "defaultBankConfig": {
      "memory_defense": {
        "enabled": true,
        "rules": [{ "on": "sensitive_data", "action": "redact" }]
      }
    }
  }
  ```

  `embedVersion` must equal `EMBED_VERSION`. The survey is off because it runs `claude -p` with Read over the whole repo (untracked `.env` included) on the subscription; `hindsight-memory survey on` is the one-line way to enable it per machine. Pages on the first prompt instead of a reflect (the reflect ran past the 20 s hook window on every measured start), a six-hourly staggered page refresh and a page roster every ten turns cut the background model calls.

- `pnpm check` is the gate before every commit. Commits go straight to `main` under the repo's standing approval, one per task.
- Docs change in the same commit as the behaviour they describe (`README.md`, `setup/README.md`, `agents/README.md`, `docs/README.md`, `docs/privacy.md`, `bin/CLAUDE.md`, `CLAUDE.md`, `tilde/.claude/rules/verify-first.md`).

## Review Focus

1. `paths add` with a trailing slash, with a path outside `$HOME`, and with a home-prefixed sibling such as `/Users/jason2/x`. Expected: stored once, slash stripped, only a true `$HOME` prefix collapses to `~`. Tests in Task 1.
2. A hand-edited `optInPaths` list, then `init` and `upgrade`. Expected: the list survives both and the installer runs again only from `upgrade`. Tests in Task 1 and Task 4.
3. A Claude Code session launched from the Desktop app, where no `.zshrc` ran. Expected: the SessionStart hook finds `node`, `uv` and `claude`, the daemon starts under the `coding-agent` profile, and its log names the `claude-code` provider. Checked live in Task 6.
4. A session with the daemon stopped. Expected: the reply is not delayed beyond the 2 s health probe and `diag.jsonl` records the failed reflect. Checked live in Task 6.
5. `hindsight-memory off`, then `uninstall`, then `init`. Expected: `off` makes every hook inert in the next session, `uninstall` leaves no hindsight entry in `~/.claude/settings.json`, `~/.codex/hooks.json` or `claude mcp list`, and `init` restores them. Tests in Task 1 for the config side, live in Task 6 for the host files.

---

### Task 1: `bin/hindsight-memory` with its self-check

**Files:**
- Create: `bin/hindsight-memory`
- Create: `bin/lib/test-hindsight-memory`
- Modify: `bin/lib/check` (after the `test-claude-desktop-account` line)
- Modify: `README.md` (the `bin/` script list, see `bin/CLAUDE.md` for where scripts are documented)
- Modify: `bin/CLAUDE.md` (one bullet under the per-script notes)

**Interfaces:**
- Produces: `hindsight-memory init` (installer when the config is missing, then profile env, then defaults; exit 1 when the installer fails), `hindsight-memory upgrade` (installer always, then the same two steps, then a notice line `newer release <v> on npm; bump CODING_AGENTS_VERSION` when `npm view` is newer; exit 1 only when the installer fails), `hindsight-memory paths [list]`, `paths add <dir>`, `paths remove <dir>` (exit 1 when absent), `hindsight-memory on|off` (writes `disabled` false or true), `hindsight-memory survey on|off` (writes `codebaseSurvey`), `hindsight-memory status`, `hindsight-memory uninstall` (vendor `uninstall all`, then `daemon stop` for the `coding-agent` profile; the config file and the database stay).
- Environment overrides, used by the tests and documented in the header: `HINDSIGHT_CONFIG` (the config file; the plugin honours the same variable), `HINDSIGHT_MEMORY_INSTALLER` (the command run in place of `npx -y @vectorize-io/hindsight-coding-agents@$CODING_AGENTS_VERSION`), `HINDSIGHT_MEMORY_EMBED` (in place of `uvx hindsight-embed@$EMBED_VERSION`), `HINDSIGHT_MEMORY_NPM` (in place of `npm`). Each is split on whitespace into an array before use, so a stub path with spaces is not supported and the header says so.
- Consumes: nothing from other tasks.

- [x] **Step 1: Write the failing self-check**

`bin/lib/test-hindsight-memory` follows `bin/lib/test-claude-desktop-account`: `set -euo pipefail`, `script="$(cd "$(dirname "$0")/.." && pwd -P)/hindsight-memory"`, `tmp=$(mktemp -d)`, `export HOME=$(cd "$tmp" && pwd -P)` (the `pwd -P` matters, `mktemp` returns `/var/…` and the real path is `/private/var/…`), `hm() { "$script" "$@"; }`, `check name expected actual` and `check_true name cmd…` copied from that file. Stubs are scripts in `$HOME/bin`: `installer` appends `"$*"` to `$HOME/installer.log` and, on `install`, writes `{"serverMode":"daemon"}` to `$HINDSIGHT_CONFIG` unless `$HOME/installer-fails` exists, in which case it exits 1; `embed` appends `"$*"` to `$HOME/embed.log`; `npm` prints `0.8.2`, or `0.9.0` when `$HOME/npm-newer` exists. Export `HINDSIGHT_CONFIG="$HOME/.hindsight/coding-agent.json"` and the three overrides pointing at the stubs. `cfg=$HINDSIGHT_CONFIG`.

```bash
check_true "init runs the installer once with both harnesses" hm init
check "installer args" "install claude-code codex --server daemon" "$(cat "$HOME/installer.log")"
check "init persists the provider in the daemon profile" "profile create coding-agent --merge --port 9077 --env HINDSIGHT_API_LLM_PROVIDER=claude-code" "$(cat "$HOME/embed.log")"
check "init writes the default paths" '["~/dev"]' "$(jq -c .optInPaths "$cfg")"
check "init writes the other defaults" "true false 1.1.0 false 10 redact" "$(jq -r '[.optInOnly, .autoUpdate, .embedVersion, .codebaseSurvey, .pageRefreshEveryTurns, .defaultBankConfig.memory_defense.rules[0].action] | join(" ")' "$cfg")"
jq '.optInPaths = ["~/work"]' "$cfg" > "$cfg.t" && mv "$cfg.t" "$cfg"
check_true "init again keeps the edited list and skips the installer" hm init
check "edited list kept" '["~/work"]' "$(jq -c .optInPaths "$cfg")"
check "installer not rerun by init" 1 "$(wc -l < "$HOME/installer.log" | tr -d ' ')"
check_true "upgrade reruns the installer" hm upgrade
check "installer rerun by upgrade" 2 "$(wc -l < "$HOME/installer.log" | tr -d ' ')"
check "upgrade keeps the edited list" '["~/work"]' "$(jq -c .optInPaths "$cfg")"
touch "$HOME/npm-newer"
check_true "upgrade notices a newer release" bash -c 'hm upgrade | grep -q "newer release 0.9.0 on npm"'
check_true "paths add strips a trailing slash and collapses HOME" hm paths add "$HOME/dev/x/"
check "stored list" '["~/work","~/dev/x"]' "$(jq -c .optInPaths "$cfg")"
check_true "paths add is idempotent" hm paths add "$HOME/dev/x"
check "no duplicate" 2 "$(jq length <<< "$(jq -c .optInPaths "$cfg")")"
check_true "paths add keeps a path outside HOME" hm paths add /opt/src
check_true "paths add does not collapse a sibling of HOME" hm paths add "${HOME}2/x"
check "outside and sibling stored literally" "/opt/src ${HOME}2/x" "$(jq -r '.optInPaths[2:] | join(" ")' "$cfg")"
check "paths list prints one per line" "$(printf '~/work\n~/dev/x\n/opt/src\n%s2/x' "$HOME")" "$(hm paths list)"
check_true "paths remove drops the path" hm paths remove ~/work
check "removed" '["~/dev/x","/opt/src","'"${HOME}"'2/x"]' "$(jq -c .optInPaths "$cfg")"
check_true "paths remove of an unknown path exits 1" bash -c '! hm paths remove ~/nope 2> /dev/null'
check_true "off writes disabled" hm off
check "disabled true" true "$(jq .disabled "$cfg")"
check_true "on clears it" hm on
check "disabled false" false "$(jq .disabled "$cfg")"
check_true "survey on writes codebaseSurvey" hm survey on
check "survey true" true "$(jq .codebaseSurvey "$cfg")"
check_true "uninstall calls the vendor uninstall and stops the daemon" hm uninstall
check "uninstall args" "uninstall all" "$(tail -1 "$HOME/installer.log")"
check "daemon stopped" "-p coding-agent daemon stop" "$(tail -1 "$HOME/embed.log")"
rm "$cfg"
check_true "paths add without a config creates it with the defaults first" hm paths add ~/dev/y
check "defaults then the new path" '["~/dev","~/dev/y"]' "$(jq -c .optInPaths "$cfg")"
touch "$HOME/installer-fails" && rm "$cfg"
check_true "init exits 1 when the installer fails and leaves no config" bash -c '! hm init > /dev/null 2>&1 && [ ! -e "$cfg" ]'
```

`hm` must be exported or the `bash -c` checks must call `"$script"` directly; pick the latter.

- [x] **Step 2: Run it to make sure it fails**

Run: `bash bin/lib/test-hindsight-memory`
Expected: the first `check_true` fails because `bin/hindsight-memory` does not exist.

- [x] **Step 3: Implement `bin/hindsight-memory`**

Header comment in the `help` format with one example per subcommand and the four override variables. Then, in order: the two version constants; `cfg=${HINDSIGHT_CONFIG:-$HOME/.hindsight/coding-agent.json}`; `installer=(${HINDSIGHT_MEMORY_INSTALLER:-npx -y @vectorize-io/hindsight-coding-agents@$CODING_AGENTS_VERSION})`, `embed=(${HINDSIGHT_MEMORY_EMBED:-uvx hindsight-embed@$EMBED_VERSION})`, `npm_cmd=(${HINDSIGHT_MEMORY_NPM:-npm})` (unquoted on purpose, with a `# shellcheck disable=SC2206` and the reason); `defaults()` printing the JSON above; `write_cfg()` taking a jq filter, running `jq "$filter" "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"`; `ensure_config()` which runs `"${installer[@]}" install claude-code codex --server daemon` when `$cfg` is missing and returns 1 if that fails or still left no file, then `jq -s '.[0] * .[1]' <(defaults) "$cfg"` written the same way, so the file's keys win; `persist_provider()` running `"${embed[@]}" profile create coding-agent --merge --port 9077 --env HINDSIGHT_API_LLM_PROVIDER=claude-code`; `norm_path()` which strips one trailing `/` and, when the path is `$HOME` or starts with `$HOME/`, prints `"~${p#"$HOME"}"`; `paths_list|add|remove`, `set_flag key value`, `status()` (the `embed -p coding-agent daemon status`, a `jq` summary of `serverMode`, `disabled`, `optInOnly`, `optInPaths`, `codebaseSurvey`, then `model calls today: N` from `grep -c "^$(date +%F).*scope=" ~/.hindsight/profiles/coding-agent.log`, 0 when the file is absent, then the last 10 lines of `~/.hindsight/coding-agents-logs/plugin.log` when present), `upgrade()` which runs the installer unconditionally, then `persist_provider` and the merge, then compares `"${npm_cmd[@]}" view @vectorize-io/hindsight-coding-agents version` with the constant and prints the notice when they differ, `uninstall()`. Output helpers inline with `tput`, as the other scripts do. `init` and `upgrade` need `jq`; print `jq is required` and exit 1 without it.

- [x] **Step 4: Run the self-check and the one-file gate**

Run: `bash bin/lib/test-hindsight-memory && bash -n bin/hindsight-memory && shellcheck --severity=warning bin/hindsight-memory && prettier --check bin/hindsight-memory && help hindsight-memory`
Expected: every check prints `ok:`, no lint output, the header renders.

- [x] **Step 5: Wire the test into the gate and document the command**

Add `bash bin/lib/test-hindsight-memory > /dev/null` under the `test-claude-desktop-account` line in `bin/lib/check` with a one-line comment. Add the script to the `bin/` list in `README.md` in the same style as `claude-config`, and a `bin/CLAUDE.md` bullet stating the additive merge rule, the two version constants, the override variables and that the config is never tracked.

- [x] **Step 6: Gate and commit**

Run: `pnpm check`
Expected: exit 0.

```bash
git add bin/hindsight-memory bin/lib/test-hindsight-memory bin/lib/check README.md bin/CLAUDE.md
git commit -m "Add hindsight-memory to manage the coding-agent memory config"
```

### Task 2: Pin the extraction provider where every session reads it

**Files:**
- Modify: `tilde/.zshenv` (after the `DOTFILES` export)
- Modify: `docs/privacy.md` (a Hindsight entry)
- Modify: `tilde/.claude/rules/verify-first.md` (one clause)

**Interfaces:**
- Produces: `HINDSIGHT_API_LLM_PROVIDER=claude-code` in every zsh, interactive or not. The daemon profile written by Task 1 carries the same value for sessions that never ran zsh.

- [x] **Step 1: Add the export with its why**

One `export HINDSIGHT_API_LLM_PROVIDER=claude-code` line in `tilde/.zshenv` with a comment: the Hindsight daemon picks the first API key it finds when this is unset, a running daemon is adopted rather than restarted, so the first session of the day would decide billing; `zsh/env.zsh` is not used because only interactive shells read it.

- [x] **Step 2: Document what is stored and what leaves the machine**

In `docs/privacy.md` add a Hindsight entry: the Stop hook stores each turn's user text, assistant text and one line per tool call (the tool name and the first line of its main input, for Bash the command), never tool results, in a local Postgres under `~/.pg0`; extraction calls go to Anthropic through the `claude` CLI on the subscription; the `sensitive_data` redact rule matches 45 known key shapes and not passwords or opaque tokens, and never rescans; the codebase survey is off by default because it reads the repo with `claude -p`; the docs name no vendor telemetry; the uv cache holds 1.5 GB per `hindsight-embed` version.

- [x] **Step 3: Name it in the verification rule**

In `tilde/.claude/rules/verify-first.md`, extend the line that lists memory and earlier messages as leads, not evidence, with "recalled Hindsight memory and its knowledge pages".

- [x] **Step 4: Verify and commit**

Run: `zsh -n tilde/.zshenv && zsh -c 'echo $HINDSIGHT_API_LLM_PROVIDER' && pnpm check`
Expected: `claude-code` from a non-interactive zsh, gate exit 0.

```bash
git add tilde/.zshenv docs/privacy.md tilde/.claude/rules/verify-first.md
git commit -m "Pin Hindsight's extraction provider to the Claude subscription"
```

### Task 3: Install from setup

**Files:**
- Modify: `setup/misc.sh` (a new block after the Scrapling block and before REA)
- Modify: `setup/README.md` (the misc section)
- Modify: `README.md` (the line that lists what setup covers for coding agents)
- Modify: `CLAUDE.md` (the Setup order sentence and a new Architecture bullet)

**Interfaces:**
- Consumes: `hindsight-memory init` from Task 1. `setup/misc.sh` names the repo root as `$DOTFILES_DIR`.

- [x] **Step 1: Add the setup block**

Guarded by `command_exists uv && command_exists node && command_exists jq && [ -x "$claude_bin" ]`. It runs `"$DOTFILES_DIR/bin/hindsight-memory" init 2>&1 | indent || warning "Hindsight memory setup failed — run it later: hindsight-memory init"`. A comment block above it names what the installer writes (three hooks in `~/.claude/settings.json`, three in `~/.codex/hooks.json` plus `[mcp_servers]` in `~/.codex/config.toml`, a user-scope `hindsight` MCP server, the `hindsight-coding-agent` skill), that each touched file is backed up as `<file>.hindsight-backup`, that `claude-config save` drops `hooks` and never reads `~/.claude.json`, and that `~/.codex/config.toml` is a seeded copy so the appended section survives (`setup/symlinks.sh`, the `codex-config` test).

- [x] **Step 2: Document it**

`setup/README.md` gets a bullet in the misc list in the style of the Scrapling one: the pinned package, the opt-in default, `hindsight-memory paths|on|off|survey|status|uninstall`, the provider, the daemon profile and port, the backups. `README.md` names Hindsight memory where it lists the coding-agent setup. `CLAUDE.md` adds "Hindsight memory" to the setup-order list after Scrapling and one Architecture bullet pointing at the spec.

- [x] **Step 3: Run the new block on this machine**

Run: `bin/hindsight-memory init`
Expected: the installer's summary with `claude-code` and `codex` wired, `~/.hindsight/coding-agent.json` holding the defaults with `serverMode` `daemon`, `jq '.hooks | keys' ~/.claude/settings.json` listing the existing events with hindsight entries under `SessionStart`, `UserPromptSubmit` and `Stop`, `claude mcp get hindsight` succeeding, `grep -c hindsight ~/.codex/hooks.json` at least 3, and `~/.hindsight/profiles/coding-agent.toml` (or the profile file `profile show -p coding-agent -o json` names) carrying the provider. This edits `~/.claude/settings.json`, `~/.codex/hooks.json` and `~/.codex/config.toml`.

- [x] **Step 4: Confirm the tracked snapshots are unchanged**

Run: `bin/claude-config save && git status --short agents/ && bash setup/tests/codex-config.sh`
Expected: no diff under `agents/`, the Codex copy test passes.

- [x] **Step 5: Gate and commit**

Run: `pnpm check`
Expected: exit 0.

```bash
git add setup/misc.sh setup/README.md README.md CLAUDE.md
git commit -m "Install Hindsight coding-agent memory from setup"
```

### Task 4: Upgrade through upup

**Files:**
- Modify: `bin/upup` (a `Hindsight memory` step after `agent skills`, inside the existing `command -v claude` block)
- Modify: `bin/lib/test-upup` (one stub, one fixture file, four assertions)
- Modify: `README.md` and `bin/CLAUDE.md` (the upup step lists)

**Interfaces:**
- Consumes: `hindsight-memory upgrade` from Task 1, and `HINDSIGHT_CONFIG` to find the config.

- [x] **Step 1: Write the failing assertions**

`bin/lib/test-upup` stubs tools by name in `$tmp/bin` and never sets `HOME`, so: `stub hindsight-memory '[ -e "$STATE/hindsight-fails" ] && { echo "installer failed"; exit 1; }; [ -e "$STATE/hindsight-newer" ] && echo "newer release 0.9.0 on npm; bump CODING_AGENTS_VERSION"; echo "runtime re-staged"'`, and `export HINDSIGHT_CONFIG="$STATE/coding-agent.json"` with `echo '{}' > "$HINDSIGHT_CONFIG"`. The clean first run must stay free of `↻●✖` lines, so assert there `has '^✔ Hindsight memory +runtime re-staged, hooks re-wired$'`. In the changes run, where the uv failure already lives, touch `$STATE/hindsight-newer` and assert `has '^● Hindsight memory +newer release 0.9.0 on npm; bump CODING_AGENTS_VERSION in bin/hindsight-memory$'`. Add a third scenario or reuse the second with `$STATE/hindsight-fails` to assert `has '^✖ Hindsight memory +run: hindsight-memory upgrade$'` and `has '^    installer failed$'`. A fourth assertion removes `$HINDSIGHT_CONFIG` and asserts the report `lacks 'Hindsight memory'`.

- [x] **Step 2: Run to verify they fail**

Run: `bash bin/lib/test-upup`
Expected: the new assertions fail, the existing ones still pass.

- [x] **Step 3: Add the step**

```bash
if [ -f "${HINDSIGHT_CONFIG:-$HOME/.hindsight/coding-agent.json}" ]; then
  step "Hindsight memory"
  if capture hindsight-memory upgrade; then
    if newer=$(grep -o 'newer release [^;]*' "$capture_file"); then
      status notice "Hindsight memory" "$newer on npm; bump CODING_AGENTS_VERSION in bin/hindsight-memory"
    else
      status ok "Hindsight memory" "runtime re-staged, hooks re-wired"
    fi
  else
    status fail "Hindsight memory" "run: hindsight-memory upgrade"
    show
  fi
fi
```

Use whatever name `capture` gives the captured output file in `bin/upup` (read `capture()` first) in place of `$capture_file`. The step re-runs the pinned installer, which is the vendor's documented update and re-wires hook entry points a release adds; a newer release is only reported, never installed, because the pin is a reviewed commit.

- [x] **Step 4: Verify and commit**

Run: `bash bin/lib/test-upup && pnpm check`
Expected: all assertions pass, gate exit 0. Add the step to the `upup` bullets in `README.md` and `bin/CLAUDE.md`, including that the version pin is bumped by hand.

```bash
git add bin/upup bin/lib/test-upup README.md bin/CLAUDE.md
git commit -m "Upgrade Hindsight coding-agent memory in upup"
```

### Task 5: One memory, not three

**Files:**
- Modify: `agents/claude-skills.txt` (remove `hindsight-local` and `hindsight-self-hosted`)
- Modify: `agents/README.md` (rewrite the hindsight bullet)
- Modify: `agents/catalog/curated.toml` (add `hindsight-docs` and `hindsight-architect` to the "Look up documentation" group's items)

- [x] **Step 1: Uninstall the two memory skills here and clear the prototype's default profile**

Run: `npx -y skills remove hindsight-local hindsight-self-hosted -g -y && bin/claude-config save && git diff --stat agents/claude-skills.txt && ls ~/.claude/skills | grep hindsight`
Expected: two lines removed and nothing else changed; only `hindsight-docs` and `hindsight-architect` left. If a dangling symlink remains in `~/.claude/skills`, delete it and re-run `save`. Then `uvx hindsight-embed@1.1.0 daemon status` must say the default-profile daemon on 8888 is not running (stop it if it is). `~/.local/bin/hindsight` stays, `hindsight-embed memory …` forwards to it.

- [x] **Step 2: Rewrite the docs bullet**

The `agents/README.md` bullet now says two hindsight skills are tracked (docs and architect), that coding memory comes from the hook package installed by `setup/misc.sh` with the companion `hindsight-coding-agent` skill it writes itself, and why the model-invoked memory skills were dropped (two "use to remember" skills the model would pick between, `hindsight-local` writing to the default profile on 8888 and bank `default`, `hindsight-self-hosted` to a server and bank the user types in, neither the per-repo bank the hooks use).

- [x] **Step 3: Verify the catalog and gate**

Run: `claude-catalog && pnpm check`
Expected: catalog build exit 0 with no lint line and the two skills in the documentation group, gate exit 0.

```bash
git add agents/claude-skills.txt agents/README.md agents/catalog/curated.toml
git commit -m "Keep one Hindsight memory path and file its docs skills in the catalog"
```

### Task 6: Prove it live and hand off

**Files:**
- Modify: `.remember/remember.md` through the `remember` skill at the end.
- Modify: `docs/superpowers/specs/2026-10-24-hindsight-memory.md` (the measured numbers go in Risks).

- [x] **Step 1: Claude Code in an opted-in repo** (2026-10-24: banner names `coding-agent::dotfiles`; `session_start` with 5 pages; the sync and the credited answer were seen in the day's sessions)

Open a fresh Claude Code session in `~/dev/dotfiles`. Expected: the 🧠 banner names bank `coding-agent::dotfiles`, `~/.hindsight/coding-agents-logs/plugin.log` shows `seed_started`, `~/.hindsight/profiles/coding-agent.log` shows `Claude Code: Using Claude Agent SDK`, and within two minutes `hindsight_sync_status` reports `"synced": true`. Ask "what is this repo's gate before a commit" and expect an answer that credits Hindsight memory after the seed has run.

- [ ] **Step 2: Codex in the same repo** (deferred: Codex is not in use on this machine)

Run `codex` in `~/dev/dotfiles`, one prompt. Expected: `diag.jsonl` gains a line with `"harness": "codex"` and `reflect_ok` or an `inject_*` event, and `npx -y @vectorize-io/hindsight-coding-agents@0.8.2 stats` lists both harnesses.

- [ ] **Step 3: A repo outside the list** (deferred by the owner on 2026-10-24)

Clone any small public repo to `/tmp/outside` and open Claude Code there. Expected: the banner reports memory inert, and `uvx hindsight-embed@1.1.0 -p coding-agent bank list` (which starts the daemon if it is down) shows no bank for it.

- [x] **Step 4: Desktop-launched session** (2026-10-24 19:03Z: `command -v cargo node uv claude` resolved all four, `cargo` from `/opt/homebrew/opt/rustup/bin`; `diag.jsonl` shows `session_start` 5 pages, `inject_pages` 482 ms, `pages_ok`, `retain_ok`)

Start Claude Code from the Claude Desktop app's Code tab in `~/dev/dotfiles`. Expected: the same banner, a `reflect_ok` or fallback event in `diag.jsonl`, and the provider line in `profiles/coding-agent.log`, which together prove PATH held `node`, `uv` and `claude`.

- [ ] **Step 5: Daemon down and kill switch** (deferred by the owner on 2026-10-24)

Run `uvx hindsight-embed@1.1.0 -p coding-agent daemon stop`, open a session, send one prompt. Expected: the reply starts within a few seconds and `diag.jsonl` records `reflect_failed` or an `inject_*_failed`. Then `hindsight-memory off`, a new session. Expected: no banner, no new `diag.jsonl` line. `hindsight-memory on` afterwards.

- [ ] **Step 6: Uninstall and reinstall round trip** (deferred by the owner on 2026-10-24)

Run `hindsight-memory uninstall`. Expected: `jq '.hooks[][] .hooks[].command' ~/.claude/settings.json | grep -c hindsight` prints 0, `claude mcp get hindsight` fails, `~/.codex/hooks.json` has no hindsight entry, NotchBar's and rtk's hooks are untouched. Run `hindsight-memory init`. Expected: all three back, `optInPaths` unchanged.

- [x] **Step 7: Measure the turn cost** (2026-10-24: the first-prompt reflect timed out at 20 s in 5 of 5 sessions, which is why `autoInject` became `pages`; the pages injection took 482 ms; the numbers are in the spec's Risks)

From `diag.jsonl`, record the `ms` of the first-prompt reflect for three sessions. From `hindsight-memory status`, record `model calls today` after a normal day. Put both numbers in the spec's Risks section, and flag it if the reflect exceeds 20 s or the day exceeds 150 calls.

- [x] **Step 8: Handoff** (`.remember/remember.md`, 2026-10-24)

Run the `remember` skill with the measured numbers, the bank name, and the open question of whether to add `permissions.allow` rules for the read-only `mcp__hindsight__*` tools in `agents/claude-settings.json`.
