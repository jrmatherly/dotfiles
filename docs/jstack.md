# jstack

jstack is the Claude Code plugin that holds my working habits as skills: one command puts the agent into a written playbook for the kind of task at hand, it designs and verifies before it claims "done", and it writes replies you can read in one pass. It is a fork of [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (pinned upstream commit and pstack version in the skills repo README), maintained in [jrmatherly/skills](https://github.com/jrmatherly/skills) (`plugins/jstack`, MIT), and installed here from that repo's marketplace (`plugin jstack@jrmatherly-skills` in `agents/claude-plugins.txt`, restored by `claude-config restore`). Counts below come from the installed plugin's own files on 2026-10-24: 54 skills, of which 24 are principles, 23 playbooks, 2 subagents, 1 hooks module that draws the band above the prompt.

## Summary

- Start a task with `/jstack:j-mode <task>`. It picks a playbook, copies its steps into a todolist mirrored in the band, reads the principles that apply and names them in the reply, and verifies on the real artifact before reporting.
- Every skill also runs on its own as `/jstack:<name>`. The agent cannot pick jstack skills on its own (they set `disable-model-invocation`); j-mode reads them as files when a trigger fires, and you run them as commands.
- `/jstack:setup-jstack` writes `~/.claude/rules/jstack-models.md`, one `model effort` line per role. This machine runs Fable for judgment, synthesis and the lead seat on each panel, Opus for code, Sonnet for exploration, all at medium effort (the tracked copy is `tilde/.claude/rules/jstack-models.md`).
- Reversible work proceeds without asking. It pauses for force pushes, deploys, data deletion and customer-facing messages, and for pushes or merges no standing approval covers. A "which approach?" question it can settle by running code gets a prototype, not a question.
- The plugin updates with `upup` (`claude plugin update`); the skills repo is the place to change it.

## Start here

```text
/jstack:j-mode fix the flaky login test
```

What changes once you type it:

1. A playbook is chosen (Bug fix, Feature, Investigation, Refactoring, …). Its steps become the todolist in the band, so you see where the agent is, and a skipped step stays listed with its reason.
2. Nontrivial changes route through `how` for a walkthrough of the affected code and `architect` for a design pass before any code.
3. The result is proven on the real thing. A bug is reproduced first; a feature counts as done when it ran, not when it compiled.
4. The reply follows `unslop`: short sentences, each claim marked measured, inferred or guessed, no filler, no long dashes.

## The band

The hooks module draws one line above the prompt: the current playbook step, the context fill (green, yellow from 60%, red from 85%), a Level menu for Ponytail, an Actions menu (Simplify, Review, Remember, Board, Check for `pnpm check`), a Memory button, and a More toggle for cost, tokens, turns, agent time, quota and the running subagents. Memory shows Hindsight's state: `on` means the daemon answers, not that the current repo is opted in (a repo outside `~/.hindsight/coding-agent.json`'s paths shows `on` with no 🧠 banner); `off`, `down` when the daemon is not answering, `n/a` when there is nothing to report. The button opens Hindsight's dashboard. Desktop's Code tab draws the band but no status line, so there the band is the only live per-session readout. The design history is in `docs/superpowers/specs/completed/2026-10-22-claude-code-mods-band-reassessment.md`.

## Skill map

| Group | Skills | What they do |
| --- | --- | --- |
| Understand code (read-only) | `how`, `why`, `teach`, `bro`, `recall`, `ketchup`, `in-your-own-words` | How a subsystem works and where something should live; why it was built that way from git, tickets and docs; both woven together; the last message with no jargon; rebuilding context after a break; what changed in the chat since you looked; the agent restating your goal before it starts |
| Design before coding | `architect`, `arena`, `interrogate`, `swarm`, `figure-it-out`, `sharpen` | Types and signatures first; N parallel attempts with the best parts grafted into one; several models attacking a change from independent angles; parallel workers for coverage matrices and races; a bespoke playbook when none of the 23 fits; a task made deeper, not bigger |
| Verify | `blast-radius`, `benchmark-checklist`, `tdd`, `create-verification-skill`, `create-formal-verification-skill`, `maintain-verification-skill`, `maintain-formal-verification-skill`, `show-me-your-work` | What a diff could break elsewhere, proven by running code; vetting a measured speedup; a failing test first when cheap; a project skill that drives your app like a user; model-checking races and invariants; keeping both current; a decision log for work reviewed later |
| Write clean | `unslop`, `no-comments`, `technical-writing`, `typescript-best-practices` | AI tells cut from any text (numbered rules other skills cite); comments reduced to the non-obvious why; docs, RFCs, PR descriptions and commit messages; conventions loaded whenever a `.ts` or `.tsx` file is touched |
| Improve the agent | `reflect`, `correct`, `automate-me`, `setup-jstack` | Three reviewers read the transcript and route each lesson into a skill edit; a repeated mistake made impossible in structure (architecture, then types, then a lint, then a test); your working style turned into a personal mode skill; model and effort per role |
| Subagents | `j-agent`, `comment-sicko` | The delegate for code-writing work inside a run (reads j-mode in full first); the comment auditor `no-comments` spawns |

## Playbooks

j-mode copies a playbook's steps into the todolist verbatim. The 23 files live in the plugin's `skills/j-mode/playbooks/`.

| Playbook | Use it when | What you get back |
| --- | --- | --- |
| Investigation | "How does X work?", "Are we sure about Z?" | A cited explanation or a recommendation with tradeoffs, no code change |
| Bug fix | A reported defect | Reproduced first, root cause fixed, runtime evidence in the reply |
| Feature | New or changed behavior | Built from a named data shape, with a design pass before code |
| Refactoring | Rename, extract, dedupe, move | Behavior preserved and shown to be preserved |
| Prototype | A design fork you could settle by trying it | A throwaway sketch and the observed answer instead of a question |
| Perf issue, Hillclimb | Measured slowness, or sustained work on one metric | Before and after numbers, one commit per accepted win |
| Runtime forensics, Trace forensics | A leak, a spin, or a captured profile | A diagnosis, not a fix |
| Babysit, Shipping | "Get this PR green", "land the stack" | CI, review threads and conflicts driven to merge-ready, then landed bottom-up after independent verification |
| Autonomous run, Autopilot-full, Autopilot-stack | "Run until done", a queue of independent PRs | Long unattended work with a decision trail to audit later |
| Orchestrate | A multi-day program with many stacked PRs | One coordinator chat running a fleet of subagents |
| Session pickup, Pause safely | Resuming someone's branch, or stopping cleanly | State written down so the next session starts where this one stopped |
| Eval, Authoring a skill | Changing how the agent itself behaves | A measured before and after |
| Multi-phase plan | Work that spans phases or stacked PRs | Phase boundaries with a check at each |
| Visual parity | Pixel-exact UI equivalence | Two implementations matched, measured in the browser |
| Worktree cleanup, Opening a PR | Old worktrees and simulators, or the end of any other playbook | Safe pruning; a PR that went through simplify, the comment audit and review |

## Principles

Twenty-four short skills, each naming when it applies. j-mode reads the relevant one before acting and names it in the reply, so you can see which rule shaped a decision.

- Core: laziness protocol (smallest change, bias to deletion), foundational thinking (types first), redesign from first principles, attack the premise (after two fixes fail the same gate), subtract before you add, minimize reader load, outcome-oriented execution, experience first, exhaust the design space, build the lever (a script, not hand edits).
- Architecture: model the domain, boundary discipline, type system discipline, make operations idempotent, migrate callers then delete legacy APIs, separate before serializing shared state.
- Verification: prove it works (on the real artifact), fix root causes, sequence verifiable units, test behavior not implementation, explain the number.
- Delegation and meta: guard the context window, never block on the human, encode lessons in structure.

## A first week

1. Run `/jstack:j-mode` on a small bug. Watch the band fill with the Bug fix steps and read the reply's evidence line.
2. Ask `/jstack:how` about a part of your codebase you avoid. Compare the answer with what you believed.
3. Before a change you are unsure about, run `/jstack:blast-radius` on the diff.
4. Paste a paragraph you wrote into `/jstack:unslop` and see what it cuts.
5. At the end of a long session, run `/jstack:reflect`. Each lesson becomes an edit to a skill.
6. Run `/jstack:setup-jstack` once to set which models each role uses.

## Things that surprise people

- The agent will answer a "which approach?" question by building both and measuring instead of asking. That is the Prototype playbook.
- Every subagent's work is reviewed by the main chat before it reaches you. A subagent report is a hypothesis, not a result.
- Automated PR reviewers such as Bugbot get a skeptical read: real bugs are fixed, noise is dismissed with a stated reason.
- A broken skill found mid-task gets its own PR. The agent does not silently work around it.
- Global rules in `~/.claude/rules/` still apply under j-mode: `verify-first.md`, `tool-checks.md`, `handoffs.md` and `chrome-devtools.md` are the ones j-mode's playbooks lean on most.
