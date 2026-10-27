# Packages, CI and Docs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `brew bundle check` pass, remove the Quick Look plugins that cannot load on Apple Silicon, pin and bound the CI job, fix the four doc mismatches, and record the telemetry and licensing decisions.

**Architecture:** Package changes live in `setup/Brewfile` and follow its header rules (fully qualified tap packages with `trusted: true`, alphabetical sections, one-line comments); `pnpm check`'s Brewfile parse step and `bin/lib/test-conventions`'s trust check are the regression lock. CI changes stay in `.github/workflows/check.yml` with SHA-pinned actions as today. Doc fixes are verified by re-running the `docs-auditor` agent on the changed files. Decisions (telemetry opt-outs, unlisted packages) are recorded in the task that would implement them, with a default, so an executor can proceed without a conversation.

**Tech Stack:** Homebrew bundle, GitHub Actions, Renovate, Prettier, the `docs-audit` skill.

**Spec:** `docs/superpowers/specs/2026-10-27-repo-audit-assessment.md`, sections E and F, plus A14 and A15.

## Global Constraints

- A Brewfile entry from a tap is fully qualified and marked `trusted: true`; `bin/lib/test-conventions` fails otherwise. `pnpm check` parses the Brewfile with `manual` lines stripped.
- `.github/workflows/check.yml` keeps SHA-pinned `uses:` lines with a version comment, `permissions: contents: read` and `persist-credentials: false`.
- Telemetry opt-outs are listed in both `setup.sh` and `zsh/env.zsh` and in `docs/privacy.md` (the `telemetry-sync.md` rule); one that a Claude Code plugin reads also goes into `agents/claude-settings.json`'s `env`.
- Every doc edit is checked by `/docs-audit <path>` before its commit.
- One task, one commit, `pnpm check` green, trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` (omitted below). No em-dash characters.

## Review Focus

1. `brew bundle check` on this Mac after Task 1 must print `The Brewfile's dependencies are satisfied.`
2. A fresh Mac after Task 2: `setup/symlinks.sh` must not reference a deleted `ql-plugins/` directory (grep before committing).
3. CI after Task 3: the pinned runner must still have `/bin/bash` 3.2 and zsh; the first run on the new image is the proof.
4. `DISABLE_TELEMETRY=1` (Task 6) also disables Claude Code feature flags and Remote Control (vendor docs); the decision must weigh that.
5. The LICENSE note (Task 5) must not claim a license for `ql-plugins/` once Task 2 deletes them.

---

### Task 1: Brewfile matches this Mac (E1, E3, E4, E5)

**Files:**
- Modify: `setup/Brewfile:10` (add `tap "jesseduffield/lazydocker"`), `:77` (devpack), `:26-27`, `:228-234`, `:247-252` (font sections)
- Modify: `setup/README.md` (`brew` section, only if a section rename changes what it describes)

Decisions recorded here, change them before Step 2: `microsoft/foundry/devpack` is removed (it is not installed and pulls the azure-cli cask); of the unlisted packages, `git-filter-repo`, `komac` and `llama.cpp` are added, the `jrmatherly/ai-kb` formulas, `gcloud-cli`, `signal` and the ten VS Code extensions are left out (uninstall them by hand or add rows if you want them on a fresh Mac).

- [x] **Step 1: Baseline**: `grep -v '^manual' setup/Brewfile > /tmp/bf && brew bundle check --verbose --no-upgrade --file=/tmp/bf`; expected today: `Cask devpack needs to be installed`.
- [x] **Step 2: Edit**: add the tap line; delete the devpack line; add the three formulas in their alphabetical places with a comment each; move the `font-*-nerd-font` casks under the `# Fonts` tap header at `:26` (rename `:247` to `# Manual installs (skipped by brewpick --all)`).
- [x] **Step 3: Verify**: rerun the Step 1 command; expected `The Brewfile's dependencies are satisfied.`; then `pnpm check`.
- [x] **Step 4: Commit**: `git commit -m "Match the Brewfile to what is installed and regroup the fonts"`.

### Task 2: Retire the Intel-only Quick Look plugins (E2)

**Files:**
- Delete: `ql-plugins/` (both bundles)
- Modify: `setup/symlinks.sh:389-390` (delete the `symlink_file … ~/Library/QuickLook` call), `.claude/settings.json` (the `Edit(/ql-plugins/**)` deny), `setup/README.md:87`, `CLAUDE.md` (architecture tree line and the deny mention in `.claude/rules/claude-config.md`), `.prettierignore` if it lists the directory

Decision recorded here: delete without replacement. `syntax-highlight` (already a cask) covers text previews; a Markdown or archive Quick Look app is a separate `add-tool` request if wanted.

- [x] **Step 1: Confirm**: `file ql-plugins/*/Contents/MacOS/*` shows only `x86_64`; `qlmanage -m plugins | grep -ci 'betterzip\|qlmarkdown'` is 0.
- [x] **Step 2: `git rm -r ql-plugins`**, remove the references, `grep -rn ql-plugins --exclude-dir=node_modules .` must print only `docs/superpowers/` history.
- [ ] **Step 3: On this Mac**: `rm ~/Library/QuickLook` if it is the symlink (check with `readlink`), then `qlmanage -r`. skip: needs the owner (`~/Library/QuickLook` is still the symlink to the repo's `ql-plugins`, now dangling; run `rm ~/Library/QuickLook && qlmanage -r`)
- [x] **Step 4: `pnpm check`, commit**: `git commit -m "Remove the Intel-only Quick Look plugins"`.

### Task 3: Pinned, bounded CI (E6)

**Files:**
- Modify: `.github/workflows/check.yml:20` (`runs-on: macos-15`, or the newest macOS image Renovate's github-runners manager recognises), add `timeout-minutes: 15` under the job, add `actionlint` to the `brew install` line
- Modify: `bin/lib/check` (run `actionlint .github/workflows/*.yml` behind `command -v actionlint`)
- Modify: `renovate.json` (enable the `github-runners` manager if not already covered; check the Dependency Dashboard after the push)
- Modify: `CLAUDE.md` (the `pnpm check` list gains actionlint; the Renovate bullet names the actions, pnpm and runner managers, F4)

- [ ] **Step 1: Edit**, run `actionlint .github/workflows/check.yml` locally (it is in the Brewfile), then `pnpm check`.
- [ ] **Step 2: Push and watch the first run** on the pinned image: `gh run watch` must end green; if the image lacks zsh or Homebrew, revert the pin in a follow-up commit and say so.
- [ ] **Step 3: Commit**: `git commit -m "Pin the CI runner, bound the job and lint the workflow"`.

### Task 4: Ignore rules and stale entries (E7, A14)

**Files:**
- Modify: `.gitignore:1` (delete `Brewfile.lock.json`), add `.claude/settings.local.json` and `agents/*.tmp`
- Modify: `.prettierignore:1` (keep `vscode/User/prompts/` with a one-line comment that VS Code writes prompt files into the linked dir, or delete it)
- Modify: `setup/symlinks.sh:8` (`EXCLUDE_FILES` still names `Brewfile.lock.json`; drop it)

- [ ] **Step 1: Verify**: `brew bundle --help | grep -ci lock` is 0 (no lockfile support), `git check-ignore -v .claude/settings.local.json` currently resolves to the global ignore only.
- [ ] **Step 2: Edit, then `git check-ignore -v .claude/settings.local.json`** must name the repo's `.gitignore`.
- [ ] **Step 3: `pnpm check`, commit**: `git commit -m "Refresh the ignore rules"`.

### Task 5: Third-party terms in LICENSE (E8)

**Files:**
- Modify: `LICENSE` (append a short section), `README.md` (one sentence near the license mention)

- [ ] **Step 1: Append** after the MIT text: `icons/` (origins in `icons/README.md`, several are trademarks of their owners), `colors/` and the other Squirrelsong theme files (Artem Sapegin, MIT per the upstream repo; confirm the license file at https://github.com/sapegin/squirrelsong and name it), and any vendored binary, remain under their owners' terms.
- [ ] **Step 2: `/docs-audit LICENSE README.md`**, fix what it reports, `pnpm check`, commit: `git commit -m "Name the third-party terms the repo redistributes"`.

### Task 6: Telemetry decisions (A15)

**Files:**
- Modify (only for the opt-outs chosen): `zsh/env.zsh`, `setup.sh`, `docs/privacy.md`, `agents/claude-settings.json` (`env`), `vscode/User/settings.json.j2`, `tilde/.codex/config.toml`

Defaults recorded here: VS Code `"telemetry.telemetryLevel": "off"` is added (no feature cost). `JFROG_CLI_REPORT_USAGE=false` is added after confirming the default with `jf options | grep -i usage` or the JFrog docs. Claude Code's `DISABLE_TELEMETRY` is not set (it also disables feature flags and Remote Control per the vendor docs); `DISABLE_ERROR_REPORTING=1` is set. Codex's `approval_policy = "never"` stays, with one comment line in the config explaining the sandbox boundary.

- [ ] **Step 1: Confirm each default**: the VS Code setting name in VS Code's Default Settings (`Cmd+Shift+P`, "Open Default Settings (JSON)"); `jf options`; Claude Code's `~/.claude-code-docs/cache/claude-code__data-usage.md`.
- [ ] **Step 2: Edit the files**; for each env opt-out, add it to both `setup.sh` and `zsh/env.zsh` and the `docs/privacy.md` list (`bin/lib/test-conventions` checks the pairing), and to `agents/claude-settings.json` `env` only if a hook reads it.
- [ ] **Step 3: `bin/vscode-settings --check`**, `/docs-audit docs/privacy.md`, `pnpm check`, commit: `git commit -m "Opt out of VS Code, JFrog and Claude Code error telemetry"`.

### Task 7: Doc mismatches (F1, F2, F3) and the mise comment (E9)

**Files:**
- Modify: `README.md:164-173` (rows for `package.json` author and `setup/bootstrap-runtime.archify.json` clone URL; a sentence that `docs/jstack.md` and `docs/gui/raycast.md` link the owner's own projects)
- Modify: `setup/README.md:65` (state that the MCP registration is skipped when the `ghidra` formula is absent; the launcher's Ghidra fallback applies to a registration made earlier)
- Modify: `docs/privacy.md:27` (drop the build count or make it "five")
- Modify: `tilde/.config/mise/config.toml:9-11` (when Node 26 is LTS: 26 Active, 24 Maintenance; decide whether the global default moves; today's order is `["24", "22", "26"]`)

- [ ] **Step 1: Check Node's status**: `curl -s https://nodejs.org/dist/index.json | jq -r '.[] | select(.lts != false) | "\(.version) \(.lts)"' | head -3`.
- [ ] **Step 2: Edit the four files**, `/docs-audit README.md setup/README.md docs/privacy.md`, expected `0 mismatches`.
- [ ] **Step 3: `pnpm check`, commit**: `git commit -m "Fix the owner table, the REA note, the Hindsight count and the Node comment"`.

---

## Self-review notes

- Spec coverage: E1, E3, E4, E5 Task 1; E2 Task 2; E6 and F4 Task 3; E7 and A14 Task 4; E8 Task 5; A15 Task 6; F1, F2, F3, E9 Task 7.
- Tasks 1, 2, 6 and 7 carry decisions with defaults so an executor can proceed; each names where to change the default.
- Review Focus items map to Tasks 1, 2, 3, 6, 5.
