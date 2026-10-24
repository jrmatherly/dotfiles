# Skills Repo Hardening and pstack Upstream Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the now-public `jrmatherly/skills` repo safe and self-checking, then bring its jstack plugin up to pstack 0.15.32 without losing the fork's Claude Code translation.

**Architecture:** Part A hardens the repo in place: a durable declarations cache for `check-jstack`, a CI workflow that runs everything that needs no login, a gitleaks pre-push hook, and a Board guard. Part B moves the upstream pin and rebuilds the nine patches in order with the README's "Change or refresh a patch" loop, deleting three Cursor-bound skills in `sync-jstack`. Every task ends with `scripts/sync-jstack` or `scripts/check-jstack` green and a commit on `main`.

**Tech Stack:** bash 3.2 (macOS `/bin/bash`), shellcheck, bun, tsc, `claude plugin validate|test`, GitHub Actions, gitleaks 8.x, git-filter-repo already applied.

**Spec:** `docs/superpowers/specs/2026-10-23-skills-public-and-upstream-assessment.md`

## Global Constraints

- Never hand-edit `plugins/jstack/`; change `jstack/patches/*.patch`, `jstack/substitutions.tsv` or `scripts/sync-jstack`, then regenerate with `scripts/sync-jstack` (skills README, "jstack: generated from upstream").
- Patch `NN` is diffed against upstream + substitutions + every lower-numbered patch, with the exact `sed` header rewrite from the README's "Change or refresh a patch" block.
- `check-jstack`'s forbidden regex must stay clean: no `poteto`, `pstack`, `Cursor`, `~/.cursor`, `Grok`, `deslop`, `create-skill`, `claude-opus-5-5-(max|xhigh|high|medium)` in the generated tree. Added during execution: `Task spawn`, `grok` (any case), `composer-`, `/visualize`, and every backticked `/name` must resolve to a jstack skill, a Claude Code built-in or a named plugin command.
- Comments explain only a non-obvious why; shortcuts are marked `shortcut: <limit>, <when to upgrade>`.
- Skills repo commits: short imperative subject, body with the why, trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Dotfiles commits need `pnpm check` green first.
- Irreversible GitHub actions (repo delete, force-push) happen only in Task 1 and only after Jason's explicit word in that task.

## Review Focus

- A machine that has never run `/plugin-authoring` and has no cache: `check-jstack` must fail with the run-it-once instruction, not a bash error (Task 2 test `no copy anywhere`).
- `/tmp` wiped by `tmp_cleaner` after 3 idle days with a cache present: the check passes from the cache with no warning when versions match (Task 2 test `tmp gone, cache matches`).
- Cache holds only an older version after `claude update`: the check passes and prints the drift warning naming both versions (Task 2 test `cache older than claude`).
- A CI run with no Claude credentials: `claude plugin validate` and `claude plugin test` exit 0 (no committed test; Task 3 Step 3 watches the first workflow run, and Linux behavior is unverified until then).
- A pre-push from a branch with no `origin/main` yet (fresh clone, first push): the hook must scan `HEAD` rather than crash on a missing ref (Task 4 Step 1 hand check).

---

### Task 1: Settle the dangling declarations commits on GitHub

**Done 2026-10-23.** Jason chose delete-and-recreate and did both on github.com. `main` was pushed to the new repo (`c08b1a8`), `curl -o /dev/null -w '%{http_code}' https://raw.githubusercontent.com/jrmatherly/skills/fadacbd78981/jstack/types/claude-code.d.ts` returns 404 (also for `03657cff7f39` and `f609b8c`), `gh api repos/jrmatherly/skills/commits/fadacbd78981` answers "No commit found", and both plugins were reinstalled at `c08b1a8d751b`. The new repo has no rulesets, so Task 3 Step 4 creates one.

### Task 2: Cache the engine-written declarations for `check-jstack`

**Files:**
- Modify: `~/dev/skills/scripts/check-jstack` (the `have=` ... `types=` block and the `if [ ! -f "$types" ]` block, currently lines 51-65)
- Create: `~/dev/skills/jstack/tests/check-jstack-types.sh`
- Modify: `~/dev/skills/scripts/sync-jstack` (the `check:` step also runs the new test, next to `jstack/tests/worktree-audit.sh`)
- Modify: `~/dev/skills/README.md` ("Refresh the mod types" section)

**Interfaces:**
- Produces: `check-jstack` resolves the declarations in this order and prints which it used on stderr as `check-jstack: declarations from <path>`: `$JSTACK_CLAUDE_TYPES`; newest `${JSTACK_TYPES_TMP:-/tmp/claude-$(id -u)}/bundled-skills/<have>/*/plugin-authoring/types/claude-code.d.ts` (copied to the cache when found); `${XDG_CACHE_HOME:-$HOME/.cache}/jstack/claude-code-<have>.d.ts`; newest `${XDG_CACHE_HOME:-$HOME/.cache}/jstack/claude-code-*.d.ts` with the existing drift warning. `JSTACK_TYPES_TMP` exists for the test only.
- Produces: `check-jstack --no-types <dir>` skips the tsc step and the declarations lookup (Task 3 uses it).

- [ ] **Step 1: Write the failing test `jstack/tests/check-jstack-types.sh`**

A bash script that builds a fixture: a stub `claude` on `PATH` printing `9.9.9 (Claude Code)` for `--version` and exiting 0 for `plugin validate` and `plugin test`; a stub `tsc` that exits 0; `HOME` and `JSTACK_TYPES_TMP` pointing at temp dirs; a minimal plugin dir with `.claude-plugin/plugin.json`, `hooks/`, `types/`, `tests/` and a `LICENSE` holding `Copyright (c) 2026 Lauren Tan`, plus `skills/` and `agents/` empty (Step 3 makes the skills loop safe for that). Cases, each asserting on `check-jstack`'s exit code and stderr with `grep -q`:

```bash
case "no copy anywhere":        rc=1, stderr has "run /plugin-authoring once"
case "tmp copy present":        rc=0, stderr has "declarations from $JSTACK_TYPES_TMP/", and "$HOME/.cache/jstack/claude-code-9.9.9.d.ts" exists afterwards
case "tmp gone, cache matches": rc=0, stderr has "declarations from $HOME/.cache/jstack/claude-code-9.9.9.d.ts", stderr lacks "is from"
case "cache older than claude": only claude-code-9.9.8.d.ts cached, rc=0, stderr has "is from 9.9.8, claude is 9.9.9"
case "override missing":        JSTACK_CLAUDE_TYPES=/nonexistent, rc=1, stderr has "JSTACK_CLAUDE_TYPES=/nonexistent: not found"
case "--no-types":              no copy anywhere, rc=0
```

Each fixture declarations file is one line, `// Written by Claude Code <version>.`, so the version parse works. The script prints `ok` and exits 0 only when every case passes.

- [ ] **Step 2: Run it to verify it fails**

Run: `bash jstack/tests/check-jstack-types.sh`
Expected: `no copy anywhere` and `override missing` already pass (their messages exist); FAIL on `tmp copy present` (no `declarations from` line, no cache file), `tmp gone, cache matches`, `cache older than claude`, and `--no-types` (taken as the directory argument, exit 2), and two `bad` lines from the empty `skills/` glob.

- [ ] **Step 3: Implement the resolver and the flag in `scripts/check-jstack`**

Parse `--no-types` before `dir=`. Add `[ -e "$f" ] || continue` as the first line of the `for f in "$dir"/skills/*/SKILL.md` loop, since bash 3.2 has no nullglob and an empty `skills/` otherwise yields the literal pattern. Replace the `types=` line with a function `resolve_types` that walks the order in Interfaces, copies a found `/tmp` file into the cache dir (`mkdir -p` first), and echoes the chosen path; print `check-jstack: declarations from <path>` to stderr. Keep the existing two failure messages. Under `--no-types`, skip the whole tsc block and the lookup.

- [ ] **Step 4: Run the test and the real check**

Run: `bash jstack/tests/check-jstack-types.sh && scripts/check-jstack`
Expected: `ok`, then exit 0 with `check-jstack: declarations from /tmp/claude-501/bundled-skills/2.1.310/...` on stderr.

- [ ] **Step 5: Wire the test into `sync-jstack` and update the README**

Add `bash "$root/jstack/tests/check-jstack-types.sh" > /dev/null || die "test: jstack/tests/check-jstack-types.sh failed"` next to the worktree-audit test. In the README's "Refresh the mod types", state the four-step resolution, the cache path, that `tmp_cleaner` deletes `/tmp` content after 3 idle days (hence the cache), and the `--no-types` flag.

- [ ] **Step 6: Run `scripts/sync-jstack` to prove the pipeline still passes, then commit**

```bash
git add scripts/check-jstack scripts/sync-jstack jstack/tests/check-jstack-types.sh README.md
git commit -m "Cache the engine's declarations so check-jstack survives tmp_cleaner"
```

### Task 3: CI for the skills repo

**Files:**
- Create: `~/dev/skills/.github/workflows/check.yml`
- Modify: `~/dev/skills/README.md` (a "Checks" paragraph naming what CI runs and what stays local)

**Interfaces:**
- Consumes: `check-jstack --no-types` from Task 2.
- Produces: a required-status-capable job named `check` on `ubuntu-latest`, plus a `gitleaks` job.

- [ ] **Step 1: Write the workflow**

Triggers `pull_request` and `push` to `main`, `permissions: contents: read`, actions pinned by SHA with a `# vN` comment (copy the pins from `~/dev/dotfiles/.github/workflows/check.yml` for checkout; look up `oven-sh/setup-bun` and `actions/setup-node` current SHAs with `gh api repos/<owner>/<repo>/git/ref/tags/<tag>`). Steps of job `check`: checkout with `persist-credentials: false`; setup-node 24; `npm install -g @anthropic-ai/claude-code`; setup-bun; `sudo apt-get install -y shellcheck`; `shellcheck --severity=warning scripts/*`; `scripts/check-resume`; `scripts/check-jstack --no-types`; `(cd plugins/jstack/skills/j-mode/scripts && bun install --frozen-lockfile --production --ignore-scripts && bun test orch watch-pr)` (Task 7 adds `check-plan.test.ts` to this line once the file exists in the tree). Copy the dotfiles workflow's `concurrency` block with `cancel-in-progress` on pull requests. Job `gitleaks`: checkout with `fetch-depth: 0`, then `uses: gitleaks/gitleaks-action@<v3 SHA>` with `env: GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}` and no license line.

- [ ] **Step 2: Run the workflow's commands locally where possible**

Run: `scripts/check-resume && scripts/check-jstack --no-types && (cd plugins/jstack/skills/j-mode/scripts && bun install --frozen-lockfile --production --ignore-scripts && bun test orch watch-pr; rm -rf node_modules)`
Expected: each exits 0.

- [ ] **Step 3: Commit, push, and watch the first run**

```bash
git add .github/workflows/check.yml README.md
git commit -m "Run the login-free checks and gitleaks in CI"
git push origin main
gh run watch --exit-status "$(gh run list --branch main --limit 1 --json databaseId -q '.[0].databaseId')"
```
Expected: both jobs succeed. If `check-resume` fails on ruby or `claude plugin validate` fails without a login, fix the step rather than removing it, and record what was wrong.

- [ ] **Step 4: Make `check` a required status through a new ruleset**

The repo has no ruleset today (`gh api repos/jrmatherly/skills/rulesets` returns `[]`). Create one: `gh api --method POST repos/jrmatherly/skills/rulesets --input <json>` with `target: branch`, `enforcement: active`, `conditions.ref_name.include: ["~DEFAULT_BRANCH"]`, and one rule `{ "type": "required_status_checks", "parameters": { "strict_required_status_checks_policy": false, "required_status_checks": [{ "context": "check" }] } }`. Expected: `gh api repos/jrmatherly/skills/rulesets` lists it, and the next push to `main` shows the required status. If Task 1 Path A runs later, repeat this step on the new repo.

### Task 4: gitleaks pre-push hook

**Files:**
- Create: `~/dev/skills/.githooks/pre-push`
- Modify: `~/dev/skills/README.md` (Install section: one line `git config core.hooksPath .githooks` after cloning for contributors)

**Interfaces:**
- Produces: a hook that runs `gitleaks git --no-banner --redact --log-opts="<range>"` where `<range>` is `origin/main..HEAD` when `git rev-parse --verify -q origin/main` succeeds, else `HEAD`; exits non-zero on a leak; prints `gitleaks: not installed, skipping (brew install gitleaks)` and exits 0 when `command -v gitleaks` fails.

- [ ] **Step 1: Write the hook and a check**

`#!/bin/bash` with `set -uo pipefail`. Test by hand: `GIT_DIR` of a scratch clone with a fake secret `AKIAIOSFODNN7EXAMPLE` committed on a branch, then `.githooks/pre-push` from that clone. Expected: non-zero exit with the finding redacted. Then from a scratch clone with no `origin/main` ref: exit 0 with no bash error.

- [ ] **Step 2: Enable locally and commit**

```bash
chmod +x .githooks/pre-push && git config core.hooksPath .githooks
shellcheck --severity=warning .githooks/pre-push
git add .githooks/pre-push README.md
git commit -m "Add a gitleaks pre-push hook"
git push origin main   # the hook runs here; expected: no findings
```

### Task 5: Board guard before Ponytail's first turn

**Files:**
- Modify: `~/dev/skills/jstack/patches/90-band.patch` via the README loop (edit tree files `hooks/meter.tsx` `openBoard`, `tests/meter-band.test.tsx`)
- Regenerate: `~/dev/skills/plugins/jstack/`

**Interfaces:**
- Produces: `openBoard($, file)` first checks `await $.fs.exists(file)` (the engine's `fs.exists: (path) => Promise<boolean>`, declarations line 3357; cheaper than reading the 170 KB page); when false it toasts exactly `Ponytail has not built the board yet; it writes it after the first turn` and returns without running `open`.

- [ ] **Step 1: Add the failing test to the edit tree's `tests/meter-band.test.tsx`**

```ts
test('Board without a board page toasts instead of opening', async ($, on) => {
  const { toasts } = world(on)   // world() has no board.html in its files map
  const opened: unknown[] = []
  on('process.run', ($, e) => { opened.push(e.argv); return { value: PASS } })
  await start($); const ui = await mount($)
  await ui.select({ key: 'actions', value: 'board' })
  expect(opened).toEqual([])
  expect(toasts).toEqual(['Ponytail has not built the board yet; it writes it after the first turn'])
})
```
Add `on('fs.exists', ($, e) => ({ value: e.path in files }))` to `world()` next to its `fs.read` stub, and give the existing Board test a `files['/home/u/.config/ponytail/band/board.html'] = '<html>'` entry through a new `World` field `board?: boolean` so it still opens.

- [ ] **Step 2: Run `claude plugin test` on the edit tree's mod copy to see it fail**

Expected: the new test fails (Board ran `open`).

- [ ] **Step 3: Implement in the edit tree's `hooks/meter.tsx`, regenerate the patch, run `scripts/sync-jstack`**

Expected: 41 tests pass, `plugins/jstack` regenerated, `git diff --stat` shows the patch and the two generated files.

- [ ] **Step 4: Commit**

```bash
git add jstack/patches/90-band.patch plugins/jstack
git commit -m "Tell the user when Ponytail has not built the board yet"
```

### Task 6: Prune the superseded language server

**Files:** none.

- [ ] **Step 1: Run and verify**

Run: `mise prune npm:yaml-language-server && mise ls | grep yaml`
Expected: only `2.0.0` listed.

### Task 7: Move the pstack pin and trim Cursor-bound skills in `sync-jstack`

**Files:**
- Modify: `~/dev/skills/jstack/upstream` (`commit=e73df471cd4bd918367e99f3dd9c51bd53ddf5f0`)
- Modify: `~/dev/skills/scripts/sync-jstack` (after `rm -rf "$stage/skills/make-bot-ui"`: also remove `skills/poteto-help`, `skills/ketchup-video`, `skills/statechart` with a one-line why each; change the bun test line to `bun test orch watch-pr check-plan.test.ts`; `check-plan.test.ts` needs only `bun:test`, `node:*` and `node` on PATH, so the `--production` install suffices)
- Modify: `~/dev/skills/.github/workflows/check.yml` (same bun test line)
- Modify: `~/dev/skills/README.md` ("jstack: generated from upstream": list the four dropped skills and why; Attribution: `0.15.32`)

**Interfaces:**
- Produces: `JSTACK_NO_CHECK=1 scripts/sync-jstack --no-patches --out <base>` yields the new unpatched tree the patch tasks diff against.

- [ ] **Step 1: Edit the three files**

Reasons to write: `poteto-help` describes Cursor Custom Modes and links docs sync does not copy; `ketchup-video` needs a video renderer; `statechart` installs npm packages with unpinned transitive dependencies plus TLC and Java (about 305 MB) on first use.

- [ ] **Step 2: Confirm the unpatched stage is clean of the three and that the first patch is the only blocker**

Run: `JSTACK_NO_CHECK=1 scripts/sync-jstack --no-patches --out /tmp/claude-501/.../scratchpad/base && ls .../base/skills | grep -cE 'poteto-help|ketchup-video|statechart'`
Expected: `0`. Then `JSTACK_NO_CHECK=1 scripts/sync-jstack --out /tmp/.../trial` is expected to stop at `patch: 10-router.patch no longer applies`; that is the input to Task 8.

- [ ] **Step 3: Commit the pin move alone (the generated tree is not regenerated yet; say so in the body)**

```bash
git add jstack/upstream scripts/sync-jstack README.md .github/workflows/check.yml
git commit -m "Pin pstack 0.15.32 and drop three Cursor-bound skills"
```

### Task 8: Rebuild patches 10 to 70 against the new base

**Files:**
- Modify: `~/dev/skills/jstack/patches/10-router.patch`, `20-runtime.patch`, `30-models.patch`, `40-comments.patch`, `50-skill-refs.patch`, `60-safety.patch`, `70-reflect.patch`
- Reference: upstream `pstack/docs/harness/claude-code.md` at the new pin (model and tool mappings), and the subagent's reject table in the spec's source session (hunk starts per patch)

**Interfaces:**
- Consumes: the unpatched base from Task 7.
- Produces: `git apply --check` passes for each patch in order against base plus lower patches.

For each patch NN, in order, one loop iteration:

- [ ] **Step NN.1: Build the base for this patch**

Move patch NN and every patch numbered above it aside (sync applies every patch present and dies on the first failure), run `JSTACK_NO_CHECK=1 scripts/sync-jstack --out "$base"` (applies the lower, already-rebuilt patches), copy to `"${base%-base}-edit"`, restore the moved patches.

- [ ] **Step NN.2: Re-apply the old patch's intent to the edit tree**

`git -C <edit> init && git -C <edit> apply --reject <old NN patch>`; for each `.rej`, re-make the change by hand in the new text, then delete the `.rej` files and `.git`. Decisions fixed here, per patch: 10, `j-agent` keeps today's `${CLAUDE_PLUGIN_ROOT}/skills/j-mode/SKILL.md` path and drops upstream's `~/.cursor/plugins/` search entirely (its tie-break reads `plugin.json` `version`, which the fork omits on purpose), and the two hunks upstream made redundant (frontmatter `name:`, `mode:`/`reminder:`) are dropped. 20, Cursor "fast mode" per subagent maps to nothing (omit), effort maps to the `Agent` tool's `effort`; `/visualize` in `ketchup` becomes a Mermaid block in the reply; `create-formal-verification-skill/SKILL.md` line 35 links `../statechart/SKILL.md`, which Task 7 deletes and `check-jstack` would flag as a broken link, so rewrite that paragraph to read the TLC output directly and add the file to this patch; `worktree-audit.sh`'s transcript lookup re-anchors on the new `--base` code; playbooks keep upstream's `/loop 1h` wording. 30, adopt upstream's role grammar and budget mechanics (Jason's decision, 2026-10-23): every real model line is `<model> <effort>` and the budget ladder stays upstream's (`unlimited` max, `large` xhigh, `medium` high, `small` medium), with `inherit` and `codex` unchanged; j-mode passes `effort` from the line on every Agent call. Slugs map per the adapter doc: `claude-opus-5-5-<effort>` is `opus <effort>`, `grok-*` and `gpt-*` seats become `inherit`, `-fast` is dropped. The fork's own defaults (`sonnet` for code, `opus` for prose, fable seats) keep their current models and take the budget's effort. The fork sentence "There is no per-call reasoning setting" goes. The per-role step of `setup-jstack` offers the five effort values with `medium` preselected on every role. 40, keep only the hunks upstream did not fix. 50, re-anchor the seven `:6` hunks. 60, re-anchor on the new `setup-jstack` steps including step 8 (formal verification offer: keep, it is prose). 70, keep the fork's "learnings go to `jstack/patches/70-reflect.patch`" rule and drop the now-duplicate "never edit `plugins/cache`" sentence upstream added.

- [ ] **Step NN.3: Regenerate the patch with the README's exact diff and sed pipeline, then check it**

Run: `git -C <edit-parent> diff --no-index jstack-base jstack-edit | sed -E '<README sed>' > jstack/patches/NN-area.patch && JSTACK_NO_CHECK=1 scripts/sync-jstack --out /tmp/.../trial 2>&1 | tail -1`
Expected: either `sync-jstack: ... from ...` (all patches apply) or a failure naming a patch numbered above NN.

- [ ] **Step NN.4: Commit the one patch**

```bash
git add jstack/patches/NN-area.patch
git commit -m "Rebuild NN-area against pstack 0.15.32"
```

### Task 9: Rebuild patches 80 and 90, regenerate, verify the fork's intent survived

**Files:**
- Modify: `~/dev/skills/jstack/patches/80-mod.patch`, `90-band.patch` (one rejected SKILL.md sentence each; the TS, hooks, types and tests hunks apply)
- Regenerate: `~/dev/skills/plugins/jstack/`

- [ ] **Step 1: Rebuild 80 then 90 with the Task 8 loop**

The rejected hunk is the "Open a todolist whose first items..." sentence in `skills/j-mode/SKILL.md`; re-add the band and step-tool sentences after upstream's reworded sentence.

- [ ] **Step 2: Full sync with checks**

Run: `scripts/sync-jstack`
Expected: exit 0 after check-jstack (declarations from Task 2's resolver), bun tests including `check-plan.test.ts`, `jstack/tests/worktree-audit.sh`, `jstack/tests/check-jstack-types.sh`, and `claude plugin test` with 41 passing.

- [ ] **Step 3: Verify the three fork guarantees on the generated tree**

Run: `grep -rnE 'reviewThreads\(first: 100\)' plugins/jstack/skills/j-mode/scripts/watch-pr/github.ts | grep -vc 'after'` expected `0` (paging adopted); `grep -rn 'command -v gt\|graphite' plugins/jstack/skills/j-mode/scripts/orch | wc -l` expected `0`; `grep -rn 'Board' plugins/jstack/hooks/meter.tsx | wc -l` expected `>= 2`.

- [ ] **Step 4: Review the generated diff and commit**

Run: `git diff --stat plugins/ | tail -1` and read `git diff plugins/jstack/skills/j-mode/SKILL.md` in full.

```bash
git add jstack/patches/80-mod.patch jstack/patches/90-band.patch plugins/jstack
git commit -m "Regenerate jstack from pstack 0.15.32"
git push origin main
```

### Task 10: Re-run setup, refresh the model rule, update the installed plugin

**Files:**
- Modify (through its symlink): `~/dev/dotfiles/tilde/.claude/rules/jstack-models.md`
- Modify: `~/dev/dotfiles/CLAUDE.md` and `tilde/.claude/rules/index.md` (the rule's line format changes to `<model> <effort>`; update the one-line descriptions of `jstack-models.md`)

- [ ] **Step 1: Decision recorded 2026-10-23: upstream grammar, effort `medium` by default, picked per role**

Run `/jstack:setup-jstack` with the budget whose effort is `medium` (`small` on upstream's ladder; the label is upstream's) and answer the per-role question, which preselects `medium`; Jason adjusts roles there. The result is every line as `<model> <effort>`, models as today (fable for judgment and panel leads, opus for code, sonnet for explorers).

- [ ] **Step 2: Update the plugin and re-run setup**

Run: `claude plugin marketplace update jrmatherly-skills && claude plugin update jstack@jrmatherly-skills`, then in a new session `/jstack:setup-jstack` as Step 1 says.
Expected: `~/.claude/rules/jstack-models.md` rewritten through the symlink; `git -C ~/dev/dotfiles diff tilde/.claude/rules/jstack-models.md` shows the new lines.

- [ ] **Step 3: Gate and commit in dotfiles**

```bash
cd ~/dev/dotfiles && (pnpm check || { pnpm format && pnpm check; }) && git add tilde/.claude/rules/jstack-models.md CLAUDE.md tilde/.claude/rules/index.md && git commit -m "Refresh the jstack model rule for pstack 0.15.32" && git push origin main
```

### Task 11: Close out

- [ ] **Step 1: Move this plan to `docs/superpowers/plans/completed/` and commit**
- [ ] **Step 2: Refresh the session handoff with `/remember`**, recording Task 1's outcome (404 or pending support ticket) and the new pin.
