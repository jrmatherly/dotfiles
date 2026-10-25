# Claude Code guardrails for this repo: assessment

Date: 2026-10-25. Claude Code 2.1.310. HEAD `bd3a26a`.

Question: how should agents, hooks, rules and skills be built here so coding assistants keep to the repo's conventions? Sources: the official Claude Code docs (local copies synced 2026-10-25), the installed `claude-automation-recommender`, `skill-creator` and `hook-development` plugin skills, and a file-by-file audit of this repo's `.claude/` surface. Every claim below is labelled measured (a command was run), doc (read in the docs) or inferred.

## Verdict

The repo already follows the docs' core guidance. Formatting and lint run as deterministic hooks, permissions guard the scripts that change the machine, conventions are split between an always-loaded `CLAUDE.md` and path-scoped rules, and the one agent is read-only by tool list. Nothing in the config is malformed: `claude plugin validate` passes for skills and agents, every hook and skill field used is documented, and both hook self-checks pass (measured).

The gaps are of one kind. Several rules the repo relies on are prompt text only, and the docs are explicit that prompt text is advisory: "Use hooks for actions that must happen every time with zero exceptions" (best-practices) and "To block an action regardless of what Claude decides, use a PreToolUse hook" (memory). The biggest is the commit itself: under the standing approval Claude pushes straight to `main`, so CI is a post-landing check and nothing deterministic runs `pnpm check` before a commit.

One blocker was found on the way: `pnpm check` fails in Claude's own Bash shell because that shell runs in the C locale, so any hook that runs the gate must set `LC_ALL`. Details under R1.

## Enforcement ladder

| Layer                          | Deterministic | Sees                      | Use for                                                  |
| ------------------------------ | ------------- | ------------------------- | -------------------------------------------------------- |
| Permission rules               | yes           | one tool call             | hard never-do rules (`npm -g`, edits to vendored dirs)   |
| PreToolUse hook (exit 2)       | yes           | one tool call, pre-run    | gates that need logic a rule can't express (commit gate) |
| PostToolUse hook (exit 2)      | yes           | one tool call, post-run   | fix-it-now feedback (format, lint)                       |
| `pnpm check` test              | yes, in CI    | the whole tree            | tree invariants (paired lists, headers, ignore files)    |
| Path-scoped rule               | no            | loads on matching file    | conventions tied to a directory                          |
| `CLAUDE.md`                    | no            | every session             | commands, layout, always-true conventions                |
| Skill                          | no            | loads on invocation       | multi-step procedures                                    |
| Subagent                       | partly        | its own context           | isolation plus a tool allowlist                          |

Doc basis: hooks are "deterministic and guarantee the action happens" while CLAUDE.md is "advisory" (best-practices); exit 1 from a hook is non-blocking, "If your hook is meant to enforce a policy, use `exit 2`" (hooks); "Permission rules are enforced by Claude Code, not by the model" (permissions); a hook exiting 2 "stops the tool call before permission rules are evaluated", so it beats allow rules (permissions).

## Recommendations

Ranked by how much enforcement each buys per line of change. R1 to R5 are deterministic. R6 to R8 shape the prompt layer. R9 is process.

### R1. Commit gate hook

A PreToolUse hook on `Bash` with `"if": "Bash(git commit *)"` that runs `bin/lib/check` and exits 2 on failure. This is the only pre-landing deterministic point here, because hooks fire per tool call and CI runs after the push.

- `pnpm check` takes about 22 s on this machine (measured), acceptable for a per-commit gate.
- The hook must export `LC_ALL=en_US.UTF-8` (or `C.UTF-8`). In this session's Bash shell `LANG`, `LC_ALL` and `LC_CTYPE` are empty and `locale` reports `LC_CTYPE="C"`. Under that locale `bin/lib/test-upup` fails its "no changed, notice or failed line" assertion because `grep -E '^ *[↻●✖]'` matches a byte of the `›` in the stub's sudo line, and `pnpm check` exits 1. With `LC_ALL=en_US.UTF-8` the same tree passes (measured, both ways). CI passed on `bd3a26a` (measured, `gh run list`), so this is a local-shell condition, not a broken tree. The cleaner fix is inside `bin/lib/check` or the test, so the gate stops depending on the caller's locale.
- The same hook can read `git diff --cached --name-only` and warn (not block) when `setup.sh`, `setup/*.sh` or the mise config is staged with no `*README.md`. That is the only point where the "docs mirror behavior" rule can be checked, since a per-edit hook fires before the README edit exists and `pnpm check` has no base to diff against. Keep it a warning: `add-tool` step 8 says a plain Brewfile line needs no README change.
- `if` is documented as best-effort for Bash and only evaluated on tool events (hooks), so also check the command string inside the script before running the gate.
- Alternative the docs offer: a project skill named `verify` makes Claude's built-in commit instructions run it before each commit (skills, v2.1.286+). That is prompt-level and does not fire when `includeGitInstructions` is off or the commit comes from a subagent prompt that bypasses it. Prefer the hook; the skill can sit beside it for sessions where the hook is disabled.

| Option                              | Deterministic | Pre-landing | Cost                               |
| ----------------------------------- | ------------- | ----------- | ---------------------------------- |
| PreToolUse hook on `git commit`     | yes           | yes         | ~22 s per commit, one script       |
| Project `verify` skill              | no            | yes         | one SKILL.md                       |
| Stop hook running the gate          | yes           | no (after)  | runs on every turn end, too broad  |
| CI only (today)                     | yes           | no          | nothing                            |

### R2. Run the hook self-checks in the gate

`bin/lib/check:13` syntax-checks `.claude/hooks/*.sh` but never runs `test-lint-edited.sh` or `test-lint-bash-edits.sh` (measured). Two lines next to the other fixture tests put hook regressions under CI. `CLAUDE.md:36` already names them as the self-checks.

### R3. Deny `npm -g` with a permission rule

`CLAUDE.md:69` and `add-tool` say global npm CLIs are mise tools, never `npm -g`. No deny exists in the tracked user settings (measured). Add `Bash(npm install -g *)`, `Bash(npm i -g *)` and `Bash(npm install --global *)` to `permissions.deny` in user settings (machine-wide rule, and `claude-config save` tracks it). Flag-order variants slip past a Bash rule, which the docs call "a guard, not a security boundary"; that is acceptable here.

### R4. Turn five tree invariants into `pnpm check` tests

All pass today by manual check (measured) and nothing holds them.

| Invariant (source)                                                          | Check                                                                               |
| --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Telemetry exports in `setup.sh` are a subset of `zsh/env.zsh` and all named in `docs/privacy.md` (`telemetry-sync.md`) | `comm` on the two export lists, grep in the doc                                      |
| Every zsh file in the gate's `zsh -n` list is Prettier-ignored (`CLAUDE.md:35`) | `prettier --file-info` reports `ignored: true` for each                              |
| Every `bin/*` script has a header `help` can render (`bin/CLAUDE.md`)        | line 2 is a comment and `bin/lib/get-tldr-md <name>` exits 0                         |
| Tap packages in the Brewfile carry `trusted: true` (Brewfile header)         | grep for qualified `brew`/`cask` lines without it                                    |
| `tilde/.claude/statusline-command.sh` passes shellcheck                      | add `tilde/.claude/*.sh` to `shell_scripts`, and mirror it in `lint-edited.sh`'s gating regex |

Also note `telemetry-sync.md:10` says `setup.sh` exports "the same" variables; it exports a subset (measured with `comm`). Fix the sentence when the test lands.

### R5. Make the docs-auditor's read-only allowlist real

`docs-auditor.md` lists `tools: Read, Grep, Glob, Bash, WebFetch`. The command allowlist in its body is prompt text, so `CLAUDE.md:78` overstates it ("may run allowlisted read-only commands"). Options:

- A `hooks:` block in the agent's frontmatter with a PreToolUse `Bash` hook that exits 2 for anything outside the allowlist. Docs: subagent frontmatter hooks run only while that subagent runs, and project-subagent hooks run only after the workspace trust dialog has been accepted (sub-agents, hooks).
- `disallowedTools` cannot do it: an entry like `Bash(rm *)` removes the whole Bash tool (sub-agents).

Either way, reword `CLAUDE.md:78` to "is instructed to run only".

### R6. Slim `CLAUDE.md` into path-scoped rules

`CLAUDE.md` is 123 lines but 26 KB, about 6.6k tokens, because each bullet is a paragraph; 22 lines exceed 400 characters (measured). The docs' target is under 200 lines, and their rule is "If an entry is a multi-step procedure or only matters for one part of the codebase, move it to a skill or a path-scoped rule" (memory). About 9.4k tokens load in every session here (measured, bytes/4). None of the following is enforced deterministically, so moving it costs no enforcement, only loads it when the matching files are touched:

| Move                                                                  | To                                                                                                         | ~Tokens per session |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- | ------------------: |
| Claude-config bullets (hooks, permissions, global rules, catalog, `claude-config`, project skills and agents) | new `.claude/rules/claude-config.md`, `paths: ['.claude/**', 'agents/claude-*', 'agents/catalog/**', 'tilde/.claude/**', 'bin/claude-*']` | ~1,450 |
| Hindsight wiring bullet                                               | same rule plus `bin/hindsight-memory`; the operating facts already live in the global `hindsight.md`        |                ~480 |
| VS Code template and SpaceBox bullets                                 | `.claude/rules/vscode.md`                                                                                  |                ~430 |
| Archify diagram bullet                                                | `.claude/rules/setup.md`                                                                                   |                ~105 |
| `tilde/.claude/rules/index.md`                                        | add `paths: ['tilde/.claude/rules/**']` or delete it; `CLAUDE.md:73` lists the same rules                   | ~500, every project |

Keep always loaded: the build and check commands, code conventions, detected patterns, the standing approval, `verify-first.md`, `tool-checks.md`, `hindsight.md`.

Rule mechanics to respect (doc): `paths` is the only frontmatter field read; project-rule globs anchor at the repo root; user-rule globs anchor at the session's working directory, which is why `serena.md`'s `**/serena_config.yml` never matches `~/.serena/serena_config.yml` from a repo session (inferred); a rule without `paths` loads at launch like `CLAUDE.md`.

### R7. Fix the drift the audit found

| Where                                   | Issue                                                                                                  |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `CLAUDE.md:22`                          | names four fixture self-checks; the gate runs seven (the list at line 29 is complete)                   |
| `CLAUDE.md:78`                          | see R5                                                                                                 |
| `tilde/.claude/statusline-command.sh:3` | points at `docs/superpowers/specs/2026-05-09-statusline-enhancement-design.md`, which does not exist in the tree or history (measured) |
| `.claude/settings.json:42`              | the Edit/Write matcher contains parentheses, so it is an unanchored regex and `Edit` also matches `NotebookEdit` (doc). Harmless today; anchor it as `^(...)$` to say what is meant |
| `.claude/settings.local.json`           | the three `rtk` allows are machine-wide and belong in user settings; `bash vscode/test-vscode-settings.sh` is a gate fixture and belongs in `.claude/settings.json`; the `awk` one-off can go |
| `lint-edited.sh:3`                      | header says "(Edit\|Write)"; the matcher also covers seven Serena tools                                 |

Not drift: `CLAUDE.md:108`'s "auto-memory plugin is off for this repo" is accurate. The plugin's scripts gate on `.claude/auto-memory/config.json` and keep "the plugin entirely inert" without it (measured in `post-tool-use.py`); the four `dirty-files-*` there are empty and dated 2026-09-30 to 2026-10-01, before it was turned off. Also not drift: the three `Edit(/...)` deny rules. A single leading `/` anchors at the repo root in project settings; `//` would mean the filesystem root (doc). Leave them.

### R8. Skills and the agent: what to keep doing

The three project skills already match the authoring guidance: "when to use" lives in the description, `disable-model-invocation: true` on the one with side effects (`validate-setup`), `context: fork` plus `agent:` for the audit. Two refinements:

- `validate-setup` writes `> private/setup-snapshots/*.txt`. Output redirects are checked against Edit rules, and a `Bash(...)` grant "allows the command, not the target" (permissions), so outside auto mode this likely prompts (inferred). Add `Edit(/private/setup-snapshots/**)` to its `allowed-tools`.
- skill-creator's `quick_validate.py` rejects Claude Code-only keys (`disable-model-invocation`, `context`, `agent`) that these skills use. Use `claude plugin validate .claude/skills` instead (passes, measured). skill-creator's description-tuning loop (20 queries, 60/40 train and held-out split, best description by held-out score) is the right tool if a skill ever under-triggers; it costs real `claude -p` runs.

### R9. Process

- `/doctor prompt-audit` (v2.1.283+, available on 2.1.310) finds stale references and contradictions across `CLAUDE.md`, rules, skills and agents and proposes edits without changing anything. Run it after R6 and R7, then periodically; it would have caught the dead statusline reference.
- `/skill-doctor` reports per-skill context cost and never-invoked skills.
- An `InstructionsLoaded` hook can log which rule loaded and why (`path_glob_match`, `session_start`), which is how to prove a new path-scoped rule fires.

## What not to do

- Do not rerun `/auto-memory:init` (the `codebase-analyzer` skill). `CLAUDE.md` already carries its `AUTO-MANAGED` markers, the plugin was disabled here on 2026-10-01 because its Stop hook blocked editing turns, and the analyzer would ask to migrate, back up or merge a file that is already in its format.

  > 🧠 **From Hindsight memory (Conventions and patterns)** — the auto-memory plugin was disabled for this repo on October 1, 2026 because its Stop hook blocked editing turns to spawn a CLAUDE.md updater for mostly no-ops.

- Do not use the installed `hook-development` skill (plugin-dev, `version: 0.1.0`) as a reference for hook syntax. Checked against the official hooks page it lists 9 of about 38 events, uses `$TOOL_INPUT` where the real placeholder is `$ARGUMENTS`, documents a `decision: "approve"` value that does not exist, reads `tool_result` where the field is `tool_response`, says `systemMessage` goes to Claude (it goes to the user), and gives a 60 s default command timeout (600 s). Its security checklist and test-script approach are still fine.
- Do not use `tool_response.bashEditDiff` to block anything. The docs mark it public beta: "Use the list to find what to review, not to enforce a policy." The current use (lint feedback) is within that.
- Do not add prompt-type or agent-type hooks for these rules. Everything above is decidable by a script; agent hooks are marked experimental.
- Do not package `.claude/skills` as a plugin just to use `claude plugin eval`. It loads only the plugin under test, with no `.claude/`, `CLAUDE.md` or `.mcp.json`, so it cannot test this repo's skills in context.
- Do not widen the recommender's app-shaped suggestions onto this repo. Its tables key on React, databases, Jest and `tsc`; it has no signal for a Brewfile, mise, shellcheck, Renovate or `pnpm check`. The parts that carried over (format-and-lint on edit, generated-file guards, GitHub via `gh`) are already in place.

## Verification record

Measured in this session: `claude --version`; `claude plugin validate .claude/skills` and `.claude/agents` (both pass); both hook self-checks (pass); `bash -n` and `shellcheck` on the hook scripts, `snapshot.sh` and the statusline (clean); `pnpm check` in the C locale (exit 1, `test-upup` assertion) and under `LC_ALL=en_US.UTF-8` (exit 0, 22 s); `gh run list` (CI green on the last three pushes); `wc -c` on every always-loaded file; `grep` for `npm -g` deny rules, telemetry list parity, Brewfile trust, bin/ headers; `find` and `stat` on `.claude/auto-memory/`; the plugin's `post-tool-use.py` gating; the three `Edit(/...)` deny targets through the `~/.config/gh` symlink.

Inferred, not exercised: the `NotebookEdit` matcher overlap; the leading-`*` ask rules prompting on read-only commands that name absolute `setup/` or `bin/upup` paths; `validate-setup`'s redirect prompting outside auto mode; `lint-edited.sh` skipping shellcheck for edits inside a `.claude/worktrees/` checkout because `rel` no longer matches its gating regexes. `autoDreamEnabled` in `agents/claude-settings.json` appears nowhere in the local docs cache.

## Sources

Official docs, local copies in `~/.claude-code-docs/cache/`: `claude-code__best-practices.md`, `memory.md`, `hooks.md`, `hooks-guide.md`, `skills.md`, `sub-agents.md`, `settings.md`, `permissions.md`, `plugin-evals.md`, `settings-reference.md` (two keys). Plugin skills: `claude-code-setup/1.0.0/skills/claude-automation-recommender`, `skill-creator/58267944f921/skills/skill-creator`, `plugin-dev/58267944f921/skills/hook-development`.
