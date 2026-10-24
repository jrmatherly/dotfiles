# jrmatherly/skills after going public: hardening, and the pstack upstream gap (2026-10-23)

Assessment behind `docs/superpowers/plans/2026-10-23-skills-public-and-upstream.md`. Claude Code is 2.1.310; the skills repo is public at `392cba0..c08b1a8` after a history rewrite; upstream pstack is at `e73df471cd4bd918367e99f3dd9c51bd53ddf5f0` (0.15.32) against the fork's pin `12d587dfb20741cafc376c42c696c5f6e2a64487` (0.15.5).

## Findings, each with how it was checked

### The purged declarations file is still served by GitHub

`git filter-repo` removed `jstack/types/claude-code.d.ts` from every commit on `main`, but GitHub keeps unreachable commits and the public events API lists the pre-rewrite SHAs. `curl -o /dev/null -w '%{http_code}' https://raw.githubusercontent.com/jrmatherly/skills/fadacbd78981/jstack/types/claude-code.d.ts` returns 200 with 848,832 bytes; a made-up SHA returns 404. Two remedies: GitHub Support's "remove sensitive data" process, or delete and recreate the repo (0 forks, 3 weeks old; the dotfiles reference only the name; one ruleset requiring the `check` status would need recreating). This is Jason's call; the plan carries both paths.

### The engine-written declarations are temporary files

`check-jstack` reads `/tmp/claude-<uid>/bundled-skills/<version>/*/plugin-authoring/types/claude-code.d.ts`, written when `/plugin-authoring` runs. macOS's `tmp_cleaner` (`man tmp_cleaner`, daemon `com.apple.tmp_cleaner`, daily at 00:00) deletes `/tmp` content whose atime, mtime and ctime are all older than 3 days (`daily_clean_tmps_days="3"` in `/usr/libexec/tmp_cleaner`). So the check fails after any 3-day pause, not only after `claude update`, and a failed types step also skips `claude plugin test` in that run because `fail=1` short-circuits it. Fix: copy the file to `~/.cache/jstack/claude-code-<version>.d.ts` whenever the `/tmp` copy is found, resolve from the cache when `/tmp` has none, and fall back to the newest cached version with the existing drift warning. Only a machine that never ran `/plugin-authoring` then fails.

### CI for the skills repo is feasible without a login

`CLAUDE_CONFIG_DIR=<empty dir> claude plugin validate` and `claude plugin test` both exit 0 with no credentials (measured on `plugins/resume` and the jstack mod). So a workflow can `npm install -g @anthropic-ai/claude-code` and run `check-resume` (needs ruby, present on GitHub runners), shellcheck on `scripts/*`, and the jstack validate and test steps. Only the `tsc` step needs the declarations and stays local; `check-jstack` needs a `--no-types` flag to skip it. gitleaks-action v3 needs no license for a personal account ("If you are scanning repos that belong to a personal account, then no license key is required.").

### Local secret guard

gitleaks 8.30.1 found nothing in the history. A committed `.githooks/pre-push` running `gitleaks git --log-opts="origin/main..HEAD"` plus `git config core.hooksPath .githooks` (one README line) gives every clone the guard; the CI job covers pushes that skip the hook.

### Board before Ponytail's first turn

`plugins/jstack/hooks/meter.tsx` runs macOS `open` on `~/.config/ponytail/band/board.html`, which only Ponytail's module writes (after its first recorded turn). On a fresh machine the user sees `open`'s "does not exist" error. Fix: `$.fs.read` the file first and toast "Ponytail has not built the board yet; it writes it after the first turn" when it is missing.

### Items accepted as is

- Dotfiles CI runs Python 3.15 while the mise default is 3.14. The only stated floor is 3.11 for `tomllib`; CI passed on 3.15. Pinning CI to the mise default would need a Renovate rule for one comment's benefit. Accept.
- `mise prune npm:yaml-language-server` would remove 1.25.0 next to 2.0.0 (dry run verified, scoped to that tool). One command, in the plan.

## The upstream gap

72 commits, 142 files, +14,907/−1,467 since the pin (subagent-verified on a fresh clone; the clone is under this session's scratchpad). A plain pin bump does not apply: 74 of the fork's 114 patch hunks reject, every hunk of `30-models` included. Upstream added its own Claude Code support, but it is the raw skills plus a two-line pointer (in 23 files) to `pstack/docs/harness/claude-code.md`, a mapping table the model reads at runtime (measured: `git diff HEAD:pstack/skills HEAD:harness/pstack/claude-code/skills` is 23 files, +46 lines). The fork's baked translation stays the stronger design; the adapter is a reference when rebuilding `20-runtime` and `30-models`.

Adopt as is: watch-pr fixes (review-thread paging past 100, which the fork's `github.ts` lacks; deadline-bounded polling; fork heads in stack discovery), orch without Graphite (`--forge gh|origin`, default `gh`), `check-plan.mjs` fixes and its new test, new prose skills (`benchmark-checklist`, `correct`, `in-your-own-words`, `sharpen`, `principle-explain-the-number`, the two formal-verification skills), principle rewrites, and upstream's own fixes to `comment-sicko` and `poteto-mode` frontmatter (which retire hunks of `10-router` and `40-comments`).

Adopt with patch rebuilds: `j-mode` SKILL.md (new subagent guidance on effort and fast mode; Claude Code's `Agent` tool takes `effort`, has no fast mode), `j-agent` as a delegate (its `~/.cursor/plugins` lookup becomes `~/.claude/plugins`), model defaults (`-max` to `-xhigh`, Sol removed, Grok seats), `setup-jstack`, `reflect`, the panel skills, the playbooks (now built around `/loop 1h`, a Claude Code built-in), `worktree-audit.sh` (`--base`, GNU stat/date fix), `ketchup` (its `/visualize` is Cursor's; map to Mermaid).

Skip or delete in `sync-jstack`: `poteto-help` (19 forbidden-term hits, Cursor Custom Modes, links outside the copied tree, wrong install line after substitution), `ketchup-video` (needs a video renderer), `statechart` (first run `npm install`s two pins with unpinned transitive dependencies into `~/.cache/statechart` and installs TLC plus Java through mise, about 305 MB; against the `60-safety` posture). Also add `check-plan.test.ts` to the bun test line.

Decision for Jason inside the update: adopt upstream's `<model> <effort>` role format in `~/.claude/rules/jstack-models.md` (recommended, since `Agent` takes `effort`), which means re-running `/jstack:setup-jstack` after the update and a dotfiles commit for the tracked rule.
