# Hindsight Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Claude Code and Codex automatic, per-repo, local long-term memory through the Hindsight hook package, installed and upgraded by these dotfiles, with an opt-in path list managed by one `bin/` command.

**Architecture:** The vendor's installer (`npx @vectorize-io/hindsight-coding-agents install claude-code codex --server daemon`) owns the hooks, the MCP registration and the local `hindsight-embed` daemon. A new `bin/hindsight-memory` script wraps it: `init` runs the installer when the config is missing and merges the repo's defaults into `~/.hindsight/coding-agent.json` without overwriting edits, and `paths` edits the opt-in list. `setup/misc.sh` calls `init`, `upup` re-runs the installer as the upgrade, and the two model-invoked memory skills are dropped so memory lives in one place.

**Tech Stack:** bash 3.2, jq, the `skills` CLI, uv and node through mise, `@vectorize-io/hindsight-coding-agents` 0.8.2, `hindsight-embed` and `hindsight-api` 1.1.0.

**Spec:** `docs/superpowers/specs/2026-10-24-hindsight-memory.md`

## Global Constraints

- Scripts are bash 3.2 compatible (`#!/bin/bash`, no associative arrays, `[ ${#arr[@]} -eq 0 ]` guards under `set -u`), start with the `help`-renderable header comment, and pass `bash -n`, `shellcheck --severity=warning` and `prettier --check`.
- Every machine-changing step is idempotent and warns instead of failing when its tool is missing (`command_exists uv`, `command_exists node`, `jq`).
- The extraction provider is `claude-code`. No API key is written anywhere by these dotfiles.
- `~/.hindsight/coding-agent.json` is never tracked in the repo. Defaults are merged into it additively, existing keys win.
- Default opt-in list is `["~/dev"]`. Paths are stored with `$HOME` collapsed to `~`.
- Memory defence default is `{"enabled": true, "rules": [{"on": "sensitive_data", "action": "redact"}]}` under `defaultBankConfig.memory_defense`.
- `autoUpdate` is written as `false`. `upup` is the only upgrade path.
- `pnpm check` is the gate before every commit. Commits go straight to `main` under the repo's standing approval, one per task.
- Docs change in the same commit as the behaviour they describe (`README.md`, `setup/README.md`, `agents/README.md`, `docs/README.md`, `docs/privacy.md`, `bin/CLAUDE.md`, `CLAUDE.md`).

## Review Focus

1. `paths add` with a path that is a symlink or has a trailing slash, or lies outside `$HOME`. Expected: stored once, normalised, and matched by the plugin as a prefix. Test in Task 1.
2. `init` on a machine where the installer already wrote `optInPaths`. Expected: the user's list survives, only missing keys are added. Test in Task 1.
3. A Claude Code session launched from the Desktop app, where PATH comes from `.zprofile` only. Expected: the SessionStart hook finds `node` and `uv` and the daemon starts. Checked live in Task 6.
4. A stray clone outside `~/dev`. Expected: the session banner shows memory inert and no bank is created. Checked live in Task 6.
5. The `Stop` hook on a 60 s window while the daemon is cold. Expected: the hook returns without blocking the reply and the turns land once the daemon is up. Checked live in Task 6.

---

### Task 1: `bin/hindsight-memory` with its self-check

**Files:**
- Create: `bin/hindsight-memory`
- Create: `bin/lib/test-hindsight-memory`
- Modify: `bin/lib/check` (after the `test-claude-desktop-account` line)
- Modify: `docs/README.md` (the `bin/` command table, next to the `claude-config` row)
- Modify: `bin/CLAUDE.md` (one bullet under the per-script notes)

**Interfaces:**
- Produces: `hindsight-memory init` (exit 0 when the config exists and holds the defaults, 1 when the installer failed), `hindsight-memory paths [list]`, `hindsight-memory paths add <dir>`, `hindsight-memory paths remove <dir>` (exit 1 when the path is not in the list), `hindsight-memory status`, `hindsight-memory log [-n N]`. Config path from `HINDSIGHT_CONFIG` if set, else `$HOME/.hindsight/coding-agent.json`. Installer command from `HINDSIGHT_MEMORY_INSTALLER` if set (the tests stub it), else `npx -y @vectorize-io/hindsight-coding-agents`.
- Consumes: nothing from other tasks.

- [ ] **Step 1: Write the failing self-check**

`bin/lib/test-hindsight-memory` builds a temp `HOME`, puts a stub `npx` on PATH that appends its arguments to `$HOME/npx.log` and writes `{"serverMode":"daemon"}` to `$HOME/.hindsight/coding-agent.json`, and asserts with a `check <name> <command>` helper in the style of `bin/lib/test-claude-desktop-account`:

```bash
check "init runs the installer once with both harnesses" \
  'hindsight-memory init > /dev/null && grep -qx "install claude-code codex --server daemon" "$HOME/npx.log"'
check "init writes the defaults" \
  '[ "$(jq -c .optInPaths "$cfg")" = "[\"~/dev\"]" ] && [ "$(jq .optInOnly "$cfg")" = true ] && [ "$(jq .autoUpdate "$cfg")" = false ] && [ "$(jq -r .defaultBankConfig.memory_defense.rules[0].action "$cfg")" = redact ]'
check "init keeps an existing list and does not rerun the installer" \
  'jq ".optInPaths=[\"~/work\"]" "$cfg" > "$cfg.t" && mv "$cfg.t" "$cfg" && hindsight-memory init > /dev/null && [ "$(jq -c .optInPaths "$cfg")" = "[\"~/work\"]" ] && [ "$(grep -c install "$HOME/npx.log")" = 1 ]'
check "paths add collapses HOME and strips a trailing slash" \
  'hindsight-memory paths add "$HOME/dev/x/" > /dev/null && [ "$(jq -c .optInPaths "$cfg")" = "[\"~/work\",\"~/dev/x\"]"]'
check "paths add is idempotent" \
  'hindsight-memory paths add ~/dev/x > /dev/null && [ "$(jq length <<< "$(jq -c .optInPaths "$cfg")")" = 2 ]'
check "paths add resolves a symlink to its target" \
  'ln -s "$HOME/dev/x" "$HOME/link" && hindsight-memory paths add "$HOME/link" > /dev/null && [ "$(jq length <<< "$(jq -c .optInPaths "$cfg")")" = 2 ]'
check "paths list prints one path per line" \
  '[ "$(hindsight-memory paths list)" = "$(printf "~/work\n~/dev/x")" ]'
check "paths remove drops the path" \
  'hindsight-memory paths remove ~/work > /dev/null && [ "$(jq -c .optInPaths "$cfg")" = "[\"~/dev/x\"]" ]'
check "paths remove of an unknown path exits 1" \
  '! hindsight-memory paths remove ~/nope > /dev/null 2>&1'
check "paths add without a config file creates it with the defaults first" \
  'rm "$cfg" && hindsight-memory paths add ~/dev/y > /dev/null && [ "$(jq -c .optInPaths "$cfg")" = "[\"~/dev\",\"~/dev/y\"]"]'
```

Create `$HOME/dev/x` in the fixture so `realpath` works. The stub `npx` must not be the real one, so prepend the fixture `bin` to PATH and point `HINDSIGHT_MEMORY_INSTALLER` at it.

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash bin/lib/test-hindsight-memory`
Expected: every check fails with `hindsight-memory: command not found`.

- [ ] **Step 3: Implement `bin/hindsight-memory`**

Header comment in the `help` format with the five usage examples. Functions `cfg_path`, `defaults` (a heredoc with the JSON from the spec), `ensure_config` (installer when the file is missing, then `jq -s '.[1] * .[0]'` so the file's keys win over the defaults, written via `.tmp` and `mv`), `norm_path` (`realpath` of the argument with the trailing slash stripped, then `${p/#$HOME/\~}`), `paths_list`, `paths_add`, `paths_remove`, `status` (`uvx hindsight-embed -p coding-agent daemon status` when `uvx` exists, then `jq` of `optInOnly`, `optInPaths` and `serverMode`, then the last 20 lines of `~/.hindsight/coding-agents-logs/plugin.log` if present), `log`. `init` also prints the hook summary the installer printed, through `indent`. Output helpers inline with `tput`, as the other scripts do.

- [ ] **Step 4: Run the self-check and the one-file gate**

Run: `bash bin/lib/test-hindsight-memory && bash -n bin/hindsight-memory && shellcheck --severity=warning bin/hindsight-memory && prettier --check bin/hindsight-memory && help hindsight-memory`
Expected: every check PASS, no lint output, the header renders.

- [ ] **Step 5: Wire the test into the gate and document the command**

Add `bash bin/lib/test-hindsight-memory > /dev/null` under the `test-claude-desktop-account` line in `bin/lib/check` with a one-line comment. Add a `docs/README.md` row for `hindsight-memory` (`init`, `paths add {{dir}}`, `paths remove {{dir}}`, `status`) next to `claude-config`, and a `bin/CLAUDE.md` bullet stating the additive merge rule and that the config is never tracked.

- [ ] **Step 6: Gate and commit**

Run: `pnpm check`
Expected: exit 0.

```bash
git add bin/hindsight-memory bin/lib/test-hindsight-memory bin/lib/check docs/README.md bin/CLAUDE.md
git commit -m "Add hindsight-memory to manage the coding-agent memory config"
```

### Task 2: Pin the extraction provider in the shell environment

**Files:**
- Modify: `zsh/env.zsh` (next to the telemetry exports)
- Modify: `docs/privacy.md` (a Hindsight entry)

**Interfaces:**
- Produces: `HINDSIGHT_API_LLM_PROVIDER=claude-code` in every interactive shell.

- [ ] **Step 1: Add the export with its why**

One `export HINDSIGHT_API_LLM_PROVIDER=claude-code` line with a two-line comment saying the daemon would otherwise switch to the first API key it finds in the environment, and that the vendor's terms-of-service notice for this provider is in the spec.

- [ ] **Step 2: Document what leaves the machine**

In `docs/privacy.md` add a Hindsight entry stating that memory, transcripts and git history stay in a local Postgres under `~/.pg0`, that extraction calls go to Anthropic through the `claude` CLI on the subscription, and that the docs name no vendor telemetry. Note the `uv cache` footprint of 1.5 GB per version.

- [ ] **Step 3: Verify and commit**

Run: `zsh -n zsh/env.zsh && zsh -ic 'echo $HINDSIGHT_API_LLM_PROVIDER'`
Expected: `claude-code`.

```bash
git add zsh/env.zsh docs/privacy.md
git commit -m "Pin Hindsight's extraction provider to the Claude subscription"
```

### Task 3: Install from setup

**Files:**
- Modify: `setup/misc.sh` (a new block after the Scrapling block and before REA)
- Modify: `setup/README.md` (the misc section)
- Modify: `README.md` (the line that lists what setup covers for coding agents)
- Modify: `CLAUDE.md` (the Setup order sentence and a new Architecture bullet)

**Interfaces:**
- Consumes: `hindsight-memory init` from Task 1.

- [ ] **Step 1: Add the setup block**

Guarded by `command_exists uv && command_exists node && [ -x "$claude_bin" ]`. It runs `"$DOTFILES/bin/hindsight-memory" init | indent || warning "Hindsight memory setup failed — run it later: hindsight-memory init"`. A comment block above it names what the installer writes (three hooks in `~/.claude/settings.json`, three in `~/.codex/hooks.json` plus `[mcp_servers]` in `~/.codex/config.toml`, a user-scope `hindsight` MCP server, the `hindsight-coding-agent` skill) and why none of it is tracked.

- [ ] **Step 2: Document it**

`setup/README.md` gets a bullet in the misc list in the style of the Scrapling one, including the opt-in default, the `hindsight-memory paths` command, the provider, and the `.hindsight-backup` files the installer leaves. `README.md` names Hindsight memory where it lists the coding-agent setup. `CLAUDE.md` adds "Hindsight memory" to the setup-order list after Scrapling and one Architecture bullet pointing at the spec.

- [ ] **Step 3: Run the new block on this machine**

Run: `bin/hindsight-memory init`
Expected: the installer's summary with `claude-code` and `codex` wired, `~/.hindsight/coding-agent.json` holding the defaults, `jq '.hooks | keys' ~/.claude/settings.json` listing the existing events plus the hindsight entries under `SessionStart`, `UserPromptSubmit` and `Stop`, and `claude mcp get hindsight` succeeding. This edits `~/.claude/settings.json` and `~/.codex/config.toml`; the installer backs each up as `<file>.hindsight-backup`.

- [ ] **Step 4: Confirm the tracked settings snapshot is unchanged**

Run: `bin/claude-config save && git status --short agents/`
Expected: no diff, because `save` drops `hooks` and never reads `~/.claude.json`.

- [ ] **Step 5: Gate and commit**

Run: `pnpm check`
Expected: exit 0.

```bash
git add setup/misc.sh setup/README.md README.md CLAUDE.md
git commit -m "Install Hindsight coding-agent memory from setup"
```

### Task 4: Upgrade through upup

**Files:**
- Modify: `bin/upup` (a `Hindsight memory` step after `agent skills`)
- Modify: `bin/lib/test-upup` (a stub and three assertions)
- Modify: `README.md` and `bin/CLAUDE.md` (the upup step lists)

**Interfaces:**
- Consumes: the installer command string from `bin/hindsight-memory` (`HINDSIGHT_MEMORY_INSTALLER` override honoured in both).

- [ ] **Step 1: Write the failing assertions**

In `bin/lib/test-upup`, stub `npx` to log its arguments. Assert that with `~/.hindsight/coding-agent.json` present the report has an `ok` line `Hindsight memory` and the log holds `install claude-code codex`, that without the file the step is skipped with no line, and that a failing stub produces a `fail` line naming `hindsight-memory init`.

- [ ] **Step 2: Run to verify they fail**

Run: `bash bin/lib/test-upup`
Expected: the three new assertions fail.

- [ ] **Step 3: Add the step**

```bash
if [ -f "$HOME/.hindsight/coding-agent.json" ]; then
  step "Hindsight memory"
  if capture hindsight-memory init; then
    status ok "Hindsight memory" "runtime re-staged and hooks re-wired"
  else
    status fail "Hindsight memory" "run: hindsight-memory init"
    show
  fi
fi
```

`init` re-runs the installer every time (the vendor's documented update, which also wires hook entry points a release adds), since `autoUpdate` is off.

- [ ] **Step 4: Verify and commit**

Run: `bash bin/lib/test-upup && pnpm check`
Expected: all assertions pass, gate exit 0. Add the step to the `upup` bullets in `README.md` and `bin/CLAUDE.md`.

```bash
git add bin/upup bin/lib/test-upup README.md bin/CLAUDE.md
git commit -m "Upgrade Hindsight coding-agent memory in upup"
```

### Task 5: One memory, not three

**Files:**
- Modify: `agents/claude-skills.txt` (remove `hindsight-local` and `hindsight-self-hosted`)
- Modify: `agents/README.md` (rewrite the hindsight bullet)
- Modify: `agents/catalog/curated.toml` (add `hindsight-docs` and `hindsight-architect` to the "Look up documentation" group's items)

- [ ] **Step 1: Uninstall the two memory skills here**

Run: `npx -y skills remove hindsight-local hindsight-self-hosted -g -y && bin/claude-config save && git diff --stat agents/claude-skills.txt`
Expected: two lines removed and nothing else changed. If `skills remove` keeps a symlink in `~/.claude/skills`, delete it and re-run `save`.

- [ ] **Step 2: Rewrite the docs bullet**

The `agents/README.md` bullet now says two hindsight skills are tracked (docs and architect), that coding memory comes from the hook package installed by `setup/misc.sh` with the companion `hindsight-coding-agent` skill it writes itself, and why the model-invoked memory skills were dropped (two "use to remember" skills, a second daemon profile and bank).

- [ ] **Step 3: Verify the catalog and gate**

Run: `claude-catalog && pnpm check`
Expected: catalog build exit 0 with the two skills in the documentation group, gate exit 0.

```bash
git add agents/claude-skills.txt agents/README.md agents/catalog/curated.toml
git commit -m "Keep one Hindsight memory path and file its docs skills in the catalog"
```

### Task 6: Prove it live and hand off

**Files:**
- Modify: `.remember/remember.md` through the `remember` skill at the end.

- [ ] **Step 1: Claude Code in an opted-in repo**

Open a fresh Claude Code session in `~/dev/dotfiles`. Expected: the 🧠 banner names bank `coding-agent::dotfiles`, `~/.hindsight/coding-agents-logs/plugin.log` shows `seed_started`, and within two minutes `hindsight_sync_status` reports `"synced": true`. Ask "what is this repo's gate before a commit" and expect an answer that credits Hindsight memory after the seed has run.

- [ ] **Step 2: Codex in the same repo**

Run `codex` in `~/dev/dotfiles`, one prompt. Expected: `~/.hindsight/coding-agents-logs/diag.jsonl` gains a line with `"harness": "codex"` and `reflect_ok` or an `inject_*` event, and `npx -y @vectorize-io/hindsight-coding-agents stats` lists both harnesses.

- [ ] **Step 3: A repo outside the list**

Clone any small public repo to `/tmp/outside` and open Claude Code there. Expected: the banner reports memory inert and `uvx hindsight-embed -p coding-agent bank list` shows no bank for it.

- [ ] **Step 4: Desktop-launched session**

Start Claude Code from the Claude Desktop app's Code tab in `~/dev/dotfiles`. Expected: the same banner and a `reflect_ok` or fallback event in `diag.jsonl`, which proves PATH held `node` and `uv`. Record any `[survey]` error lines from `plugin.log`.

- [ ] **Step 5: Measure the turn cost**

From `diag.jsonl`, record the `ms` of the first-prompt reflect for three sessions, and from `daemon.log` the time between a `Stop` and the matching extraction finishing. Put the numbers in the spec's Risks section if the first-prompt reflect exceeds 20 s or a retain exceeds 60 s.

- [ ] **Step 6: Handoff**

Run the `remember` skill with the measured numbers, the bank name, and the open question of whether to add `permissions.allow` rules for the read-only `mcp__hindsight__*` tools in `agents/claude-settings.json`.
