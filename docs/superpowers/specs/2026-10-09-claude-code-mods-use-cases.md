# Claude Code mods, second pass: what to build next (2026-10-09)

Since the 2026-10-08 assessment (`2026-10-08-claude-code-mods-assessment.md`, "the baseline") one mod went live, the jstack step band, with 27 `mcp__jstack__step` calls in seven days (explorer-local, Usage patterns). A throwaway `--plugin-dir` probe on Claude Code 2.1.295 measured what the baseline could only infer (probe-measurements, items 1 to 19). The public ecosystem grew from 2,692 to 2,904 listed mods and now includes a context ledger, three model routers, two compaction helpers and five fan-out trackers (explorer-web, Mods found). The cached docs are unchanged and the session lead verified them byte-identical to the live pages; the type declarations at 2.1.295 remain newer than the docs reference, which is pinned to 2.1.290 (explorer-docs, header). Build one more small module inside jstack, a context and hook-latency ledger that reads what the probe proved is visible, because it is the only candidate that answers a persisting pain with no process, model or redraw cost. Prototype a model-per-role auditor and an observe-only commit-review check to decide with a week of data, fix the two step band minors, and say no to the pane and poller ideas because `/loop`, `watch-pr`, the status line and the remember plugin already cover them.

The baseline's "How it works" sections are not repeated. Effort is S under one day, M one to three, L over three.

## What the probe settled

| Yesterday's open question | Measured answer | What it unlocks |
|---|---|---|
| Does `next(e)` on `classic.UserPromptSubmit` or `classic.SessionStart` include settings hooks' `additionalContext`? | Yes. UserPromptSubmit resolved to `{ additionalContext: [...] }` of 1401 and 2204 chars on the two prompts, prompt-improver's PROMPT EVALUATION text first; SessionStart to 3652 chars, superpowers first; PreToolUse, PostToolUse and Stop to `{}` (probe item 1). | The context ledger. A mod sees every non-managed hook's injected text and its size. |
| Can a mod drop or shrink an injection? | Yes. The same text reaches the model as a `prompt.attachment` event with `type: 'hook_additional_context'` and `origin: { kind: 'hook', event }`; a hook may return `{ text }` to rewrite or `{ text: null }` to drop (probe item 2). Other attachment types seen across both runs: `model`, `date`, `skill_listing`, `deferred_tools_delta`, `total_tokens_reminder`, `hook_success` (probe item 17). | The injection trimmer. The origin names the event, not the hook, so a trimmer matches on text content. |
| Does `classic.PreToolUse` reach mods? Issue 96831 said no on 2.1.281 (explorer-web, Known bugs). | Yes on 2.1.295. The probe received `classic.PreToolUse` in both runs, four rows (probe item 15). The issue is stale for that event; `skill.prompt` was not exercised. | The hook latency meter over `classic.*`. |
| Does a Bash `tool.call` hook break worktree-isolated subagents (issue 92533, explorer-web)? | No on 2.1.295. With the probe's unmatched `tool.call` hook live, an Explore subagent with `isolation: worktree` ran `pwd` through the hook and returned the worktree path (probe item 14). | Every Bash `tool.call` design below, the commit guard first. |
| What is the tool-call id field? | `tool_use_id`, a 30-char string, on `tool.call`, `tool.check` and `classic.PreToolUse` (probe item 3; explorer-docs settled question 1 from d.ts lines 1011 to 1014). | Any in-flight map keyed per call. |
| Is MCP tool search active, so `isDeferred: false` matters? | Yes. A `deferred_tools_delta` attachment went to the subagent's first request (probe item 4); ToolSearch was called 119 times in seven days (explorer-local, Usage patterns). | The step tool's `isDeferred: false` stays. |
| What does a classic batch cost? | With every plugin on, inside `await next(e)`: SessionStart 6773 ms in the first run and 8602 in the second, UserPromptSubmit 202 and 168, PreToolUse 40, PostToolUse 179, Stop 542 (probe items 5 and 16). | A 10-line meter, and a baseline to re-measure after pruning. |
| What does `agent.spawn` carry? | `tool_use_id, prompt, description, subagentType, provider {plugin, tier}, model` (the requested alias), `parentModel`, `permissionMode, background, fork, name, cwd`; result `{ model, agentId }` (probe item 6). The Agent tool input seen at `classic.PreToolUse` also carries `isolation` (probe item 16). | Model display or enforcement per spawn. No role field. |
| What does `turn.step` carry? | `turnId, index, model, effort, messageCount, agentId` for subagent requests (probe item 7). Override by `next({ ...e, model })` or `next({ ...e, effort })` is documented, not exercised. | Per-request effort control, later. |
| What does `prompt.compose` return? | 11 sections, 8418 chars, in the Haiku `-p` session, each with id, text and scope (probe item 8). `prompt.context` returned 3 blocks, the first 29,228 chars of CLAUDE.md stack, plus 10 instruction files (probe item 9). | Per-turn section sizes in the ledger. |
| What do `session.measure` and `turn.complete` give? | `session.measure` fires after each turn with context tokens and percent, two rate-limit entries, cost in USD and a `changed` list; `turn.complete` carries per-turn usage with model, `durationMs`, `reason` and `agentId` for subagent turns (probe item 10). | Per-agent token accounting without polling. |
| Does validate accept loops over event names or hook factories? | No. It rejects a variable event name, a factory-produced hook, `.catch` on `turn.step` unless the hook is an async generator, and `$` calls not spelled `$.noun.method(...)` at the call site (probe item 12). | One named function per event in every design below. |
| Do TaskCreate and TaskUpdate fire `tool.call`? | Yes. TaskCreate produced `classic.PreToolUse`, `tool.check` and `tool.call` rows with keys subject, description, tool, tool_use_id; the model reached it through ToolSearch first (probe item 18). | A band that mirrors the task tools. |
| Where are the generated types? | A `-p` session on 2.1.295 does not write `.claude-plugin/types/` for a `--plugin-dir` mod. The committed `~/dev/skills/jstack/types/claude-code.d.ts` (21,283 lines, "Written by Claude Code 2.1.295") is the ground truth (probe item 13). | Type-check against that file. |

The session lead also verified in the declarations that `next.trace` gives a `TraceEntry` per link with `index, plugin, tier, event, outcome, ms, received, returned` for mod chains while classic settings hooks appear as one engine entry (explorer-docs, settled question 4, d.ts lines 6587 to 6595 and 13212 to 13256). A latency meter names other mods, never a settings hook.

## What a mod can do that the current setup cannot

Only the capabilities that touch a pain below. Limits from explorer-docs, Limits table, unless cited otherwise.

- Classic hook visibility and timing. `on('classic.*')` fires for every settings-hook event whether or not a hook exists; `await next(e)` returns the batch's `additionalContext` and the wall time covers all hooks of that event together (probe items 1 and 5). Limit. No per-hook names; managed hooks sit above every mod (explorer-docs, settled question 3).
- `prompt.attachment` rewrite or drop. `{ text }` or `{ text: null }` per attachment, origin gives kind and event (probe item 2). Limit. Match on content, not on the hook's name. Dropping a section changes Claude's behaviour; prompt-xray's README warns the same (explorer-web, Mechanism per candidate).
- `agent.spawn` model control. `next({ ...e, model })` or `{ deny }`; ignored for forks; a deny after `next` fails the hook since 2.1.292 (explorer-docs, Events table). Limit. No role field; `codex` seats never pass through it (explorer-skills, row 4).
- `turn.step` effort control. `next({ ...e, effort })` with `agentId` to scope a subagent (probe item 7). Limit. Must be an async generator; not exercised.
- `session.measure` and `turn.complete` usage. Context, rate limits, cost and per-turn tokens with model and `agentId` (probe item 10). Limit. Cost is session-total only; per-turn cost is a diff of two readings (explorer-docs, settled question 7).
- `$.store` across sessions. One JSON file per plugin under `~/.claude/plugins/store/`, 4 MiB, shared by every session on the machine, get-then-set not atomic, expires after `cleanupPeriodDays` of no access (explorer-docs, `$` table).
- `$.session.send`. Same delivery as SendMessage, resolves on queueing, arrives as peer input, never as the user (explorer-web, issue 99614). No candidate below needs it.
- `$.command.register` without a model call. A `command.run` hook returning `{ text }` runs with no Claude turn; `immediate: true` lets it run mid-turn (explorer-docs, settled question 10).
- `$.tool.register` answered in-process. A `tool.call` hook returning `{ result }` never calls a model; the model still spends tokens on the schema and decides to call it (explorer-docs, settled question 10). The step band uses this.
- `$.clock.every`. Runs outside events, no turn started; cancelled on hot reload and at session end (explorer-docs, `$` table; explorer-skills, Boundaries).
- `$.process.run`. Argv only, no shell, 30 s default, 10 min max, outside the Bash sandbox (explorer-docs, `$` table and Non-obvious things).
- `next.trace`. Per-link timing for mods in the chain; settings hooks are one engine entry (above).

A mod still cannot replace the `statusLine` command, remove another plugin's settings hook, or run on the Amp and Codex paths (baseline, Gotchas; explorer-local, Boundaries; explorer-skills, Boundaries).

## Pain points today

Refreshed from explorer-local, Pain points, keeping the baseline's numbering. Each line says the mod answer, the non-mod answer, and which is cheaper.

1. Hook fan-out. Persists, smaller. 9 spawns per Bash call (hookify off, `lint-bash-edits.sh` added), about 56,000 hook processes per week for Bash alone (explorer-local, Hooks per event). Mod answer. Time the batch, nothing more. Non-mod answer. Disable auto-memory and prompt-improver where unused; auto-memory spawns 196 memory-updater agents per week in two repos and runs its Python hooks in every repo (pain 16). Cheaper. Non-mod. The meter only proves the pruning worked.
2. Context injection with no visibility. Persists. About 50 KB fixed prefix (explorer-local, Context injected), plus 1.4 to 2.2 KB of hook context on every prompt (probe item 1). The codegraph miss is now 0 B (explorer-local, Context injected; re-measured, probe item 19), so yesterday's main trim target is gone. Mod answer. Ledger of sections and attachments per turn with sizes; drop list for named noise. Non-mod answer. None exists; nothing else sees `additionalContext`. Cheaper. Mod, and it is small.
3. Status line is one command. Persists, 0.32 s (explorer-local, pain 3). Mod answer. None; `$.ui.status` adds a line. Non-mod answer. Collapse the 11 `jq` extractions into one. Cheaper. Non-mod.
4. and 5. Handoff staleness and remember failures. Resolved for now; `remember.md` matches the live commit and one warning since 2026-09-30 (explorer-local, pains 4 and 5). No mod.
6. jstack todolist prose-only. Resolved in part. Step band live; TaskCreate and TaskUpdate present with `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` (explorer-local, pain 6). Remaining work is the two minors and the nesting question (explorer-skills, rows 10 and the two minors).
7. Babysit loops have no live view. Persists with little observed demand; one `/loop` session and no `/babysit` command or request in seven days of transcripts (probe item 19). Mod answer. A `gh` poller pane. Non-mod answer. `watch-pr` under `/loop`, which the playbook already mandates (explorer-skills, row 3). Cheaper. Non-mod, already built.
8. Decision trail manual. Persists; `private/*-ledger.md` are hand-kept (explorer-local, pain 8). Mod answer. Passive observer. Non-mod answer. `scripts/log.sh` already stamps rows (explorer-skills, row 12). Cheaper. Non-mod.
9. Permissions over four mechanisms. Persists; rtk 0.51.0 rewrites but carries no `permissionDecision` (explorer-local, pain 9). No mod value.
10. Lint hook misses Bash edits. Resolved by `lint-bash-edits.sh` on `bashEditDiff` (explorer-local, pain 10).
11. Notification overload. Persists; a mod cannot take over NotchBar's or Warp's hooks (explorer-local, pain 11).
12. Model and cost awareness. Persists. 142 sonnet, 122 opus, 61 haiku and 37 fable model hints in seven days, spend invisible (explorer-local, pain 12). Mod answer. Per-agent model and tokens from `agent.spawn` and `turn.complete` (probe items 6 and 10). Non-mod answer. None gives per-agent figures. Cheaper. Mod, as a display first.
13. Plugin hygiene manual. Persists; 59 enabled plugins, about 200 voltagent agents in the list (explorer-local, pain 13). Mod answer. None; no API lists which plugin's hook fired. Non-mod answer. `claude plugin list` and the catalog. Cheaper. Non-mod.
14. and 15. New. rtk output truncation and 1.2 GB of transcripts (explorer-local, pains 14 and 15). Shell answers (`rtk proxy`, a `du` line); no mod.
16. New. Per-repo hooks always on. auto-memory is user-scope and spawns Python per Bash call in repos where it never acts (explorer-local, pain 16). Non-mod answer. Project-scoped enable. Cheaper. Non-mod.

The commit-review rule in j-mode ("before every commit, `/simplify` then `/code-review`", explorer-skills row 5) is a jstack pain rather than a dotfiles one and has no number here; it is the only playbook rule that is both mechanical and unenforced.

## Candidates, ranked

| Idea | What Jason would notice | Pain it answers | Mechanism (events and $ methods) | Proven by | Effort | Running cost | Risk and maintenance | Verdict |
|---|---|---|---|---|---|---|---|---|
| Context and hook ledger (one module: sizes per turn plus classic batch times) | `/ledger` prints sections, attachments by origin, CLAUDE.md blocks and the last turn's hook batch times with sizes; a dim transcript line when a batch exceeds a threshold | 2, 1 (proof of pruning), 13 partly | `prompt.compose`, `prompt.context`, `prompt.attachment`, `classic.*` with `$.clock.now()` around `await next(e)`, `$.command.register`, `command.run`, `$.state` | prompt-xray px.tsx lines 16 to 24 (char to token rule, origin label) and 127 to 140 (`$.prompt.compose()` for the rows); probe items 1, 2, 5, 8, 9 | S | None. No process, model or timer; one redraw per `/ledger` call | A `prompt.attachment` or `prompt.compose` hook that throws is skipped and fails open (explorer-docs, Events). Attachment types may grow between releases; the ledger lists unknown types as-is | Build next |
| Injection trimmer (drop list inside the ledger module) | A named attachment, such as prompt-improver's evaluation text, stops reaching the model; the ledger shows it as dropped | 2 | `prompt.attachment` returning `{ text: null }` for a matched origin and text prefix; drop list in `$.store` | probe item 2; prompt-xray drops `prompt.compose` sections persisted in `$.store` (explorer-web, Mechanism per candidate) | S, after the ledger | None | Changes Claude's behaviour silently; a stale drop rule hides a hook that later matters. Dropping an attachment that the engine's prompt cache saw may cost a cache miss on that turn (inferred from issue 100083, explorer-web) | Build next, but only the mechanism and an empty list; populate from a week of ledger output |
| Model-per-role auditor and enforcer for subagents | A toast or dim line per spawn, "swarm worker (opus) -> opus" or "role missing"; later, a rewrite when the description carries a role tag that disagrees with the rule file | 12 | `agent.spawn` reading `e.description`, `e.model`, `e.subagentType`; `$.fs.read` of `~/.claude/rules/jstack-models.md`; `$.ui.log`; `turn.complete` with `agentId` for tokens per agent | redjackfred model-router register.ts lines 3 to 14 (`next({ ...e, model })`, explicit model left alone); claude-cockpit lines 323 to 343 (explorer-web); probe items 6 and 10 | S for audit, M for enforcement | One file read at `session.start`; one log line per spawn (589 Agent calls per week, explorer-local) | No role field on the event, so a tag convention in the spawn description is new coupling between seven skills and the mod (explorer-skills, row 4). `codex` seats are `codex exec`, unreachable. A silent rewrite surprises; a deny after `next` fails the hook. Eight playbooks still default to `grok-4.7-xhigh-fast` (explorer-skills, Non-obvious things), which the auditor would flag first | Prototype to decide (audit only, no rewrite) |
| Commit guard requiring `/simplify` and `/code-review` | At first a dim line "commit without a review this session" with a count; if the count is real, a `tool.call` deny on `git commit` unless the staged diff hash was reviewed, `wip:` exempt | jstack rule (explorer-skills, row 5) | `skill.prompt` to record a review start, `tool.call { tool: 'Bash' }` matching `git commit`, `$.process.run(['git', 'diff', '--cached'])` for a hash, `$.state` for the last reviewed hash | explorer-skills row 5; hamzafer merge-gate uses a Bash `tool.call` gate with six `$.process.run` calls (explorer-web, table) | S observe, M gate | One `git diff --cached` per commit | Issue 92533 (Bash `tool.call` hooks versus worktree subagents) was retested today and does not reproduce on 2.1.295 (probe item 14), so nothing blocks the hook. Review completion versus start is fuzzy; a false deny stalls autonomous runs. The dotfiles standing approval commits without review on small changes, so the rule itself is contested | Prototype to decide (observe only) |
| Subagent fan-out tracker (band row or pane with role, model, state, elapsed) | A second band row "3 running (opus x2, sonnet), 1 done" during how, why, swarm and arena fan-outs | 12 | `agent.spawn`, `turn.complete` with `agentId`, `$.agent.list()` for status, `ui.render { AbovePrompt }` | hamzafer agent-radar, erikdarlingdata subagent-band, agent-warehouse (explorer-web, Mechanism per candidate); probe items 6 and 10 | M | A redraw per spawn and per completion; a pane needs 144 columns unsolicited | Claude Code already lists background agents; the only new column is role and model, which depends on the auditor's tag (explorer-skills, row 16). Band height is capped at half the terminal | Later, after the auditor proves the tag |
| `turn.step` effort control per role | Subagent requests run at an effort the rule file names, not the parent's | 12 partly | `turn.step` async generator filtered on `agentId`, `next({ ...e, effort })` | probe item 7 (keys), not exercised; effortless ships a per-agent effort pane (explorer-web, table) | M | None | Unexercised override; the rule file has no effort column; the model must be an async generator or validate rejects `.catch` (probe item 12) | Later |
| Step band iteration | A `/resume` after a parallel `done` burst shows the right list; the store stops growing | 6 | `$.store.set` ordering, `$.store.keys` and `delete` | explorer-skills, The two deferred minors | S | None | Covered below | Iterate the existing mod |
| Step band mirroring TaskCreate and TaskUpdate | The band fills without the model calling `step` | 6 | `tool.call { tool: ['TaskCreate', 'TaskUpdate'] }` observer | bob-park claude-task-progress reads `TodoWrite` in `tool.call` line 147 (explorer-web, Mechanism per candidate); 12 TaskCreate calls in seven days (explorer-local) | S | None | TaskCreate fires `tool.call` (probe item 18), so the observer works; two sources of truth for one band, and the band would fill with task rows the playbook never named | Later |
| Audit tick for multi-phase and autopilot playbooks | The 30-minute tick prompt is submitted by a timer and the band shows the next tick | explorer-skills row 1 | `$.clock.every`, `$.prompt.submit`, `$.ui.status` | oakoss pr-watch tick at line 668 (explorer-web); `$.prompt.submit` rejects `/` text and waits for idle (compact-adviser register.ts lines 14 to 21) | M | A timer; a user turn per tick | Duplicates the built-in `/loop` skill, which the playbook already arms (explorer-skills, row 1); babysit.md:12 forbids a second loop; timers die on hot reload and session end; unattended prompt injection needs a stop switch | No |
| Babysit and PR watch pane | PR, CI and verdict in a pane | 7 | `$.clock.every`, `$.process.run(['gh', ...])`, Pane | oakoss pr-watch lines 134, 163, 449, 498, 668; narrowstacks pr-watch 195 lines (explorer-web) | M | `gh` on a timer against the API quota | Duplicates `watch-pr`; the playbook makes watcher output the only wake source (explorer-skills, row 3); no `/babysit` use in seven days (probe item 19) | No |
| Compaction and handoff helper | A pre-compaction instruction or a Haiku-written brief | 4 | `session.compact` with `instructions`, `$.session.messages`, `$.model.complete` | compact-adviser register.ts line 394; claude-auto-handoff lines 11 to 21 and 197 to 214 (explorer-web) | M | A model call per handoff | 0 compaction markers in seven days of transcripts (explorer-local, Usage patterns), so the trigger may never fire; `prompt.compose` already carries the step list through compaction (explorer-skills, Flow); the remember plugin owns the handoff; `$.session.compact` rejects mid-turn | No, until compaction is shown to happen |
| Playbook-scoped denials (no merge outside Shipping, no `git add -A` in Hillclimb) | A denied Bash call with the playbook named | explorer-skills row 6 | `tool.call { tool: 'Bash' }` plus the board atom's `playbook` | explorer-skills row 6 | S | None | `playbook` is a free string the model sets; Jean's MCP merge tools bypass Bash; settings ask lists already gate pushes | No |
| Orch inbox and status for the orchestrate playbook | Inbox rows pushed on each completion; `orch status` in the band | explorer-skills row 2 | `agent.spawn`, `turn.complete`, `$.process.run(['bun', ...orch])` | explorer-skills row 2 | M | A `bun` process per completion | Needs the orch repo path and `bun`; the mod knows `agentId` and answer text, not the unit id, so it logs arrivals and cannot classify; no orchestrate use in seven days of command tags | Later, display only, when orchestrate is in use |
| Cost and rate-limit band | A second limits bar with cost | 12 | `session.measure`, `$.session.usage()` | probe item 10; four usage HUD mods (explorer-web, table) | S | A redraw per turn | The status line already draws both limit bars from the same stdin data (explorer-local, pain 3); cost alone is one `jq` line there | No |
| Decision trail recorder | Automatic rows for commits and predicate runs | 8 | `tool.call` observer, `$.fs.write` | cc-pr-tracker and coord-router pieces (explorer-web) | M | None | `log.sh` already deterministic; the valuable cells are semantic (explorer-skills, row 12) | No |
| Auto-memory and plugin hygiene observers | Which plugins' hooks fired this session | 13, 16 | None exists | explorer-docs, settled question 4 | n/a | n/a | The API gives no per-settings-hook identity | No; prune by hand |

## Design notes for the Build next and Prototype rows

Three constraints from validate shape every module (probe item 12; explorer-docs, Module constraints). Event names are string literals, one `on(...)` per event with a named or literal function, no loops over names. `$` calls are spelled `$.noun.method(...)` at the call site, no aliasing. A `.catch` on `turn.step` requires an async generator. Gating hooks (`tool.call`, `agent.spawn`, `prompt.submit`) get a `.catch`; observers end in `.catch(($, e, next) => next(e))`, the house pattern (explorer-skills, Components found).

### Context and hook ledger

Data shape.

```ts
type LedgerTurn = {
  turnId: string | null
  sections: { id: string; chars: number; scope: string }[]
  attachments: { type: string; origin: string; chars: number; head: string }[]
  classic: { event: string; ms: number; chars: number }[]
}
declare module 'claude-code' {
  interface PluginState {
    jstack: { board: Board | null; ledger: LedgerTurn | null; dropped: string[] }
  }
}
```

Events. `prompt.compose` with no matcher records `composed.sections` ids and lengths after `await next(e)`. `prompt.context` records block lengths once. `prompt.attachment` records `e.type`, the origin label from `kind` and `event` (px.tsx lines 22 to 24), the length and the first 40 chars, then returns `next(e)` unless the drop list matches, in which case `{ text: null }`. One hook per classic event the probe timed, `classic.SessionStart`, `classic.UserPromptSubmit`, `classic.PreToolUse`, `classic.PostToolUse` and `classic.Stop`, each a named function that reads `$.clock.now()` before and after `await next(e)`, sums the returned `additionalContext` lengths, and writes the row; a loop over names would not validate. `command.run { command: 'ledger' }` returns `{ text }` with the last turn's rows, no model call; `$.command.register({ name: 'ledger', immediate: true })` runs last in `session.start`. A dim `$.ui.log` line fires when a batch exceeds a threshold held in `userConfig` (default 1000 ms, which catches SessionStart's 6773 to 8602 ms).

State. `$.state` under `jstack.ledger` for the current turn; the drop list in `$.store` under `ledger:dropped` as a string array, re-read in `classic.SessionStart` like the board. No pruning needed; one small key.

Tests. `claude plugin test` with stubs for `clock.now`, `store.get`, `store.set`, `session.id`; drive `$.classic.UserPromptSubmit` with a stub returning `{ additionalContext: ['x'.repeat(1401)] }` and assert the row; drive `$.command.run('ledger')` and assert the text names the event and the size; a drop-list test feeds `prompt.attachment` with a matching head and expects `{ text: null }`; one `$.ui.mount` is unnecessary since the module draws nothing.

Shipping. A second module in `plugins/jstack/hooks/hooks.json` `modules`, shipped as `jstack/patches/90-ledger.patch` so the 80 patch stays the step band (explorer-skills, Does a second mod fit). `types/index.d.ts` gains the two keys by interface merge. check-jstack needs nothing new; it already runs validate, tsc and test over `hooks types tests`. The README's "No process, file, network or model calls" line stays true. `claude plugin validate` must print `hooks:` with the five classic names and `calls: $.clock.now, $.command.register, $.store.get, $.store.set, ...`.

First measurement. Run one session with every plugin on and `/ledger` after the second prompt. It earns its place when it reproduces the probe's SessionStart figure within a factor of two and names the top three attachment sources by size, which turns pain 2 from "about 50 KB" into a list to prune.

### Model-per-role auditor

Data shape.

```ts
type Spawn = { agentId: string; role: string | null; requested: string | undefined; resolved: string; tokens: number }
```

Events. `agent.spawn` with no matcher parses a role from `e.description` by the convention `[role] ...` (the seven fan-out skills would add it in one patch hunk each), looks the role up in the rule table read once at `session.start` by `$.fs.read` of `~/.claude/rules/jstack-models.md`, compares with `e.model`, writes a `$.ui.log` line "role -> requested (rule says X)" and returns `next(e)`; it never rewrites in the prototype. `turn.complete` with `agentId` adds `e.usage` tokens to the matching row. A `.catch` returning `next(e)`, since an audit must never deny. `command.run { command: 'spawns' }` lists rows.

State. `$.state` under `jstack.spawns`, an array capped at 50; nothing durable.

Tests. Stub `fs.read` with the rule text, `ui.log`; call `$.agent.spawn` style through the test kit's `agent.spawn` event with `description: '[swarm worker] ...'` and `model: 'sonnet'`, expect a log line naming opus; a spawn without a tag expects "role missing".

Shipping. Same module file as the ledger or a third module; same 90 patch. The skills' description hunks ride in the same patch because the tool contract and the skill text must move together (explorer-skills, What the existing mod teaches, item 8).

First measurement. A week of `/spawns` output. It earns enforcement if the log shows more than a handful of spawns where the requested model disagrees with the rule, and it is deleted if it shows none.

### Commit-review observer

Issue 92533 was retested today and does not reproduce (probe item 14), so a Bash `tool.call` hook is safe with worktree subagents on 2.1.295.

Data shape.

```ts
type Review = { hash: string; at: number; by: 'simplify' | 'code-review' }
```

Events. `skill.prompt` records the skill name when it is `simplify` or `code-review` (names from the Skill tool counts, explorer-local). `tool.call { tool: 'Bash' }` with `e.command` matching `git commit` runs `$.process.run(['git', 'diff', '--cached'])` under `$.session.cwd()`, hashes with `crypto.subtle`, and logs "commit after review" or "commit without review" with the count in `$.state`; `wip:` subjects are skipped. It returns `next(e)` always in the prototype; a `.catch` returns `next(e)`.

Tests. Stub `process.run` to return a fixed diff; drive `$.tool.call({ tool: 'Bash', command: 'git commit -m x' })` and expect the log line; a `skill.prompt` stub for `code-review` first, then the same commit, expects the other line.

Shipping. Only after the observe week, and only in the 90 patch behind a `userConfig` switch, since the dotfiles standing approval commits without review by design. The observer must skip subagent calls (`e.agentId !== undefined`, which the probe confirmed is set on worktree subagent calls, item 16) so worktree workers are never gated.

First measurement. The ratio of commits without a review in one week of real sessions. Below a handful, delete the observer.

## Iterate the existing step band

Both from explorer-skills, The two deferred minors, confirmed against `plugins/jstack/hooks/register.tsx`.

- Parallel `step` calls can save out of order (register.tsx lines 126 to 138). Each call snapshots `after` from its own `update()` and then calls `save($, after)` outside the updater; `save` awaits `key($)` then `$.store.set` (lines 81 to 82), so two concurrent saves race and the older snapshot can land last. The atom stays right; a later `/resume` or fork can load a stale list. Fix. Make `save` write the atom's current value rather than the caller's snapshot, `await $.store.set(await key($), await read($, board))`, so whichever save runs last writes the newest board; or chain saves through a module-level promise (`pending = pending.then(() => write)`), which resets on reload, acceptable because the atom survives reload and the next call saves again. Add a test that fires two `done` calls, lets both resolve, and asserts the store stub's last written value has both marks.
- No age pruning before the 4 MiB store cap. No `store.keys` or `store.delete` call exists; one `steps:<sessionId>` record is written per session and never removed, and on overflow `save().catch(() => undefined)` swallows the rejection so persistence stops silently. Fix. In `load()` after a successful read, list `$.store.keys()`, and delete `steps:*` records older than a count (keep the newest 50 by a `savedAt` field added to `Board`, or by key order if the store returns insertion order, which is unverified). One test with 51 stubbed keys expects one delete.

A third, cheaper change from explorer-skills row 10. The arena, swarm, architect and figure-it-out skills say "open a todolist with one entry per phase" but j-mode line 123 only mirrors playbook lists; extend that sentence so phase lists reach the band too. Nesting (architect runs arena inside it) would overwrite the single `board` atom and needs a stack; leave it until nesting is shown to hurt.

## Gotchas and maintenance

New since the baseline's Gotchas section.

- Validate is strict static analysis. Variable event names, factory-produced hooks, `.catch` on a non-generator `turn.step` hook and `$` calls not spelled at the call site all fail (probe item 12). Multi-event mods are one named function per event.
- `$.fs.write` from parallel hooks corrupts. Three of the probe's 31 log rows were damaged by concurrent writes in one 15-second run (probe-measurements, header). Any mod that logs to a file serializes writes or uses `$.store` per key.
- `-p` sessions do not write generated types for a `--plugin-dir` mod on 2.1.295 (probe item 13). Type-check against the committed `jstack/types/claude-code.d.ts` and refresh it through `/plugin-authoring` after each `claude update` (explorer-skills, Flow step 5).
- Timers die on hot reload and at session end (explorer-docs, `$` table; explorer-skills, Boundaries). A design that needs a cadence across sessions is not a mod design.
- The remote rollout switch. Anthropic can turn installed mods off; the message is `hooks modules are turned off ... the rollout switch served off`, or `was saved off by an earlier session`, which a fresh `claude` start refreshes (explorer-docs, Maintenance hazards). The step band and anything built here can vanish without a local cause; the skills keep their prose fallback.
- The docs reference is pinned to 2.1.290 while the declarations are 2.1.295; `isDeferred`, `mock.session`, `prompt.autocomplete`, `$.ui.notify`, Button children and `next.trace` are in the d.ts and not in the docs tables (explorer-docs, Maintenance hazards). The public d.ts on GitHub main is older still, 2.1.277 (explorer-web, Non-obvious things).
- `$.session.compact` rejects while a turn runs and skips the caller's own `session.compact` hook; `$.prompt.submit` rejects text starting with `/` and expands no slash command or `@file`, so a command goes through `$.command.run` (compact-adviser register.ts lines 14 to 21, verified by its author on 2.1.294).
- The plugin-dir watcher walks `CLAUDE_CODE_PLUGIN_DIRS` on the main thread every 30 s and can freeze input in large dirs (issue 100150, explorer-web). Keep `--plugin-dir` trees small.
- Issues 96831 and 92533 are both open upstream and both stale here: `classic.PreToolUse` reaches mods, and a Bash `tool.call` hook leaves worktree subagents working (probe items 14 and 15, retested 2026-10-09). Re-check both after each `claude update`, since neither issue is closed.
- The grok default. Eight playbooks and two skills still name `grok-4.7-xhigh-fast` as the default model; check-jstack's forbidden regex has `\bGrok\b` with a capital G and misses the lowercase id (explorer-skills, Non-obvious things; `scripts/check-jstack` line 13). Any model auditor flags these first. Fix the regex to match case-insensitively and replace the defaults in the same patch.
- The installed plugin cache keeps nine old jstack version dirs and nothing prunes them (explorer-skills, Non-obvious things). Separate from the store.

## Open questions

- Are compactions happening at all? The session lead's grep over every transcript found 0 markers of three kinds (probe item 19), which supports the No. What remains. `/context` at the end of one long matherlynet session, and whether `autoCompact` is on in `~/.claude/settings.json`.
- Does `$.store.keys()` return insertion order? Check. d.ts `store.keys` doc comment, then a test with three stubbed sets. Settles the pruning design.
- Does `turn.step` `next({ ...e, effort })` take effect for a subagent request? Check. The probe with an async generator hook on `turn.step` filtered on `agentId`, `effort: 'low'`, and the subagent's `turn.complete` usage compared to a run without it.
- What does `pluginUsage.azure = 27,360` count? Check. Watch the counter in `~/.claude.json` across one session with no Azure call (explorer-local, Open questions).
- Does rtk 0.51.0 still bypass prompts? Check. Run an unlisted `curl` write in auto mode (explorer-local, Open questions).
- Per-hook wall time of the Python plugin hooks? Check. `time` each of auto-memory `trigger.py`, prompt-improver `engine.py` and security-guidance's prompt hook with a recorded stdin payload in a scratch dir (explorer-local, Open questions). The ledger gives only the batch.

## Sources

- Baseline spec. `docs/superpowers/specs/2026-10-08-claude-code-mods-assessment.md`, lines 159 to 266.
- Probe. `2026-10-09-mods-probe/probe-measurements.md` (probe source beside it as `register.ts`; the raw log was session-local), items 1 to 19 (two runs, the second with a worktree-isolated subagent); probe source `2026-10-09-mods-probe/register.ts`.
- Explorer reports, kept locally in the gitignored `private/mods-second-pass/`. `explorer-docs.md` (capability catalog, settled questions 1 to 11, Non-obvious things), `explorer-local.md` (inventory, usage, pain points 1 to 16), `explorer-skills.md` (candidate rows 1 to 17, the two minors, Boundaries), `explorer-web.md` (mods table, mechanism per candidate, issues table).
- Docs. `~/.claude-code-docs/cache/claude-code__plugins__mods__*.md` and `changelog.md`, as cited through explorer-docs.
- Declarations. `/Users/jason/dev/skills/jstack/types/claude-code.d.ts`, "Written by Claude Code 2.1.295".
- The existing mod. `/Users/jason/dev/skills/plugins/jstack/hooks/register.tsx` lines 81 to 82 and 100 to 163; `scripts/check-jstack` line 13.
- Public mods, fetched copies were session-local, URLs in `private/mods-second-pass/explorer-web.md`. dynamous-community/workshops prompt-xray (`px.tsx`), redjackfred/claude-code-mods model-router (`register.ts`), kunchenguid/compact-adviser (`f_kunchenguid_...register.ts`), oakoss/claude-plugins pr-watch, hamzafer/claude-code-mods merge-gate and agent-radar, bob-park/claude-task-progress, alexknowshtml/claude-auto-handoff, erikdarlingdata subagent-band.
- Issues in anthropics/claude-code. 96831 and 92533 (both retested stale on 2.1.295), 100575, 99614, 100083, 100150, 99771.
