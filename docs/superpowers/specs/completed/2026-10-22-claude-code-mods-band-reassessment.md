# Claude Code mods, third pass: the band above the prompt (2026-10-22)

Reassessment of what a mod can do for Jason's Desktop Code tab, prompted by Ponytail 5.3.2's band. Claude Code is 2.1.309; the bundled plugin-authoring skill and its type declarations are from 2.1.308. Sources: three explorer reports kept in the session scratchpad (explorer-ponytail, explorer-api, explorer-web), the two earlier specs (`2026-10-08-claude-code-mods-assessment.md`, `2026-10-09-claude-code-mods-use-cases.md`), the live jstack mod, and the type declarations, which the session lead re-read for every claim marked (types).

## Overview

The screenshot shows two mods, not one. Ponytail draws the pills, the buttons and the metrics. The blue "Session pickup · step 1/5" line is jstack's own mod, built on 2026-10-08, drawing into the same `AbovePrompt` slot (jstack `hooks/register.tsx:142-154`; Ponytail has no reference to jstack). Ponytail exposes no layout, colour, button or column options at all; its only knobs are the ledger CSV, an optional webhook, `/ponytail band on|off`, the level, and a compact toggle. Everything Ponytail's band does is built from engine calls jstack's mod already has access to, and most of it is cheaper to do ourselves: cost and quota come from one `$.session.usage()` call and tokens from `turn.complete`, while Ponytail adds two transcript greps, a `git grep` per removed definition and a board rebuild on every turn.

The two earlier passes said no to a cost band because the terminal status line already shows context and rate limits. In the Desktop Code tab that reasoning does not hold. The status line is configured (`~/.claude/settings.json:246`) but the app draws none of its output (observed in the screenshot: the bottom row is the app's own model and effort picker). In Desktop, the band is the only live, per-session dashboard surface Jason has. That is why Ponytail's band reads as useful there, and it is the premise change this pass rests on.

Recommendation in one sentence: turn Ponytail's band off, and grow the existing jstack mod into one band that shows what Jason actually watches (step, cost, tokens, 5h/7d quota, context fill, running subagents by model) with buttons for his own workflow, rather than fork Ponytail or write a second band beside it.

## Key concepts

- A mod is a plugin hooks module. `on(event, matcher?, hook)`, each hook `($, e, next)`; `$` is the engine, `e` a frozen input, `next(e)` the chain below. No DOM, no Node, no dynamic `import()`.
- `AbovePrompt` is one instance per session drawn on terminal and desktop only (types line 9812 and the props at 10796). Plugins compose by wrapping `await next(e)`; which plugin sits on top follows engine handler order, which no document states. Ponytail 5.3.1 put itself above others; jstack's row lands inside Ponytail's box today.
- Desktop element table (types line 3951): `Box Text Button Input Select Svg Link Code Markdown Client`. No `Table`, `Progress`, `Chart` or `Image`; a chart is an `Svg` (Ponytail's cost sparkline is one, desktop only).
- Band budget: `maxRows` is at most half the terminal rows, prompt included; `bodyColumns` is the width to lay out in (types line 10796+). A taller tree scrolls; the person can collapse the band.
- `Pane` (`$.ui.open`) is drawn on every attached surface, Desktop included. An unasked open is placed only at 144 columns or wider (110 after the person has opened it once); an open the person asked for places at any width. How the Desktop app places a pane (docked or inline) is not in the types; a 10-minute prototype settles it.
- Data a band can read without spawning anything: `$.session.usage()` gives `startedAt`, `context` (the status line's figures), `rateLimits` (`five_hour`, `seven_day`) and `cost` in USD (types SessionUsage); `turn.complete` carries per-turn usage with `model`, `durationMs` and `agentId` for subagents; `agent.spawn` carries `subagentType`, `model`, `description`; `$.agent.list()` the running ones.
- State. `$.state` is session-scoped and typed by a `PluginState` contract; "Any plugin reads any value; its owner alone writes it" (types line 3471). So a mod can read `ponytail.band` (its `Band` type is in `hooks/band/types.d.ts`) and `jstack.board`. `dependencies` in `plugin.json` only lays the other plugin's types beside yours. `$.store` persists across sessions, 4 MiB of JSON per plugin.
- Buttons run commands or prompts. `$.command.run({ command: 'ponytail:ponytail', args: 'lite' })` is what Ponytail's own pills do (register.tsx:110, 339), and `$.prompt.submit({ text })` queues a user prompt; slash text goes through `command.run`.

## How Ponytail's band works, and what is yours to change

| Piece | Source | Customizable? |
|---|---|---|
| Level pills | `Button` per level, `$.command.run('ponytail:ponytail', level)` (register.tsx:453-460) | Which level, nothing else |
| Copy | `$.ui.copy` of a Markdown snapshot, toast | No |
| Review, Audit | `$.command.run` of `ponytail:ponytail-review` / `-audit` | No |
| Board | Rebuild `~/.config/ponytail/band/board.html` from every project CSV, then `open` | `ledger: false` stops the CSV and board |
| Compact / Details | Flag in `$.state` and `$.store` key `details` | The toggle itself |
| cost | `$.session.usage().cost.usd`, delta per turn, last 20 kept for the sparkline | No |
| tokens, turns, agent time | summed from `turn.complete` usage and `durationMs`, subagents included | No |
| reuse, dupes, callers, tests | regex over Edit/Write inputs plus `git grep`; Bash `tool.call` matched against test commands; marked `shortcut:` in source | No |
| model, session name | two greps over the transcript JSONL each turn | No |
| Hide | `~/.claude/.ponytail-band` containing `off`, via `/ponytail band off` | Yes |
| Webhook | optional https POST per turn, Bearer token in keychain | `webhookUrl`, `webhookToken`, `sendNames` |

Layout, colours (theme tokens `suggestion`, `inactive`, `warning`, `success`, `error`), the button set and the metric columns are hard-coded. The only ways to change them are editing the plugin cache (lost on update) or a fork. Issue #1178's author took a third road: a separate mod that reads `ponytail.band` state and draws a quieter line with quota. Open Ponytail issues that touch Jason: #1183 (compact mode wraps to about four lines in Desktop; PR #1212), #1215 (band missing in some Desktop sessions), #1240 (a slow first prompt in git-root sessions with large untracked trees, from the `git grep --untracked` at `session.start`).

## What the ecosystem shows (October 2026)

- The catalogue (karanb192/awesome-claude-code-mods) lists 6,092 mods, up from 2,647 on 2026-10-08. Nothing in it is star-ranked per mod.
- Bands like Ponytail's are the commonest shape: hamzafer/claude-code-mods (context-bar, usage-meter with 5h/7d, where-am-i, merge-gate, agent-radar), augiefra/claude-mods (one combined band: context, limits, cache countdown, cost, agents), GarvitNangru (task progress bar), scasella/claude-flightdeck (a dashboard pane: context, cost, permission checks, subagents).
- Guides (Hari Krishna 2026-10-06, explainx.ai 2026-10-03) repeat three pitfalls: forgetting `next(e)` hides every band below yours, module variables reset on hot reload while `$.state` survives, and a pane opened unasked needs a wide terminal.
- Changelog since the last pass (2.1.296 to 2.1.309) that matters here: Text `size`, `weight`, `mono`, `tabular` and Box spacing steps (2.1.299, `bold` deprecated); `claude plugin test` trees now carry `part: { plugin }` (2.1.299); `prompt.change` (2.1.300); multiline `Input` (2.1.301); a transcript line when an earlier plugin skips your hook, `decider: "person"`, `isReadOnly` (2.1.304); docked pane capped at 45% width (2.1.305); `turn.step` model aliases fixed (2.1.309). The API is still unversioned and moves most weeks.
- Security posture is unchanged. A mod is code with your permissions: it reads every prompt and tool call, can submit prompts and approve tool calls, and the sandbox does not cover processes it starts. `claude plugin validate <dir>` lists a mod's hooks and `$` calls before you install it. Ponytail's band makes no network call unless `webhookUrl` is set (verified in source).

## Where things live

- Live jstack mod: `~/dev/skills/jstack` builds it as `patches/80-mod.patch`; installed copy at `~/.claude/plugins/cache/jrmatherly-skills/jstack/<hash>/hooks/register.tsx` (163 lines), contract `types/index.d.ts`, tests under `tests/`, checked by `scripts/check-jstack` (validate, `tsc`, `claude plugin test`).
- Ponytail band: `~/.claude/plugins/cache/ponytail/ponytail/5.3.2/hooks/band/{register.tsx,metrics.ts,board.ts,logo.ts,types.d.ts}`; ledger at `~/.config/ponytail/band/<project>.csv` and `board.html`; flags `~/.claude/.ponytail-active` and `.ponytail-band`.
- Engine types for this build: `/private/tmp/claude-501/bundled-skills/2.1.308/<hash>/plugin-authoring/types/claude-code.d.ts` (22,516 lines), rewritten on each skill load; the committed `~/dev/skills/jstack/types/claude-code.d.ts` is the pinned copy jstack type-checks against.
- Official docs: code.claude.com/docs/en/plugins/mods/{overview,interface,events,api,create,test,troubleshoot,admin,gallery,reference}. The local claude-code-docs cache has no mods pages; the changelog is cached.
- Writing a mod in-session: the plugin-authoring skill watches `~/.claude/dev-mods/<session>/`; the first file written there asks the person once to turn session mods on, then hot-reloads at turn end. For a permanent mod in Desktop, `CLAUDE_CODE_PLUGIN_DIRS` goes in `~/.claude/settings.json` `env`, and `CLAUDE_CODE_PLUGIN_DIR_WATCH=1` turns on reload-on-save there.

## Candidates, ranked

Effort: S under a day, M one to three.

| Idea | What Jason notices | Mechanism | Effort | Running cost | Verdict |
|---|---|---|---|---|---|
| One jstack band: step row, then cost · tokens (main + subagents) · turns · elapsed · context % · 5h and 7d quota with reset time | Ponytail's numbers plus the two quota bars it lacks, drawn once per turn, no greps | `$.session.usage()`, `turn.complete`, existing `AbovePrompt` hook; `Text` with `tabular`; desktop `Svg` sparkline optional | S | One usage call and one redraw per turn | Build |
| Subagent row: "3 running: opus ×2, sonnet · 1 done" | Fan-out progress during how, swarm, arena, architect | `agent.spawn`, `turn.complete` with `agentId`, `$.agent.list()` | S, in the same module | A redraw per spawn and completion | Build with the above |
| Workflow buttons: level pills, Simplify, Review, Check, Remember, Compact | The commands the playbooks already mandate, one click away; level pills keep working through Ponytail's command | `$.command.run('ponytail:ponytail', level)`, `$.command.run('simplify')`, `$.command.run('code-review')`, `$.process.run(['pnpm','check'])` with a toast and the tail in a `Code` block, `$.command.run('remember:remember')` | S | None until pressed | Build; confirm each command name with `$.command.list()` first |
| Turn Ponytail's band off | Two transcript greps, a `git grep` per removed definition and a board rebuild stop running every turn; the level still switches by `/ponytail` or our pills | `/ponytail band off` | 0 | Saves the above | Do first, reversible |
| Read `ponytail.band` instead of recomputing | Keeps Ponytail's reuse and test heuristics in our layout | `$.state.get({ plugin: 'ponytail', key: 'band' })`, contract from its `types.d.ts` | S | Ponytail's per-turn work stays on | Only if Jason wants the reuse and test columns; otherwise no |
| Session board pane | Per-project ledger across sessions, replacing `board.html` | `$.store`, `$.ui.open`, `Pane` with `Markdown` or `Svg` | M | None | Later; prototype Desktop pane placement first (10 minutes) |
| Fork Ponytail's band | Full control of its layout | Fork, maintain against weekly API moves | M, then ongoing | Ponytail's costs | No |
| Context and hook ledger, model-per-role auditor, commit-review observer (pass two) | Unchanged | Unchanged | S each | None | Unchanged verdicts; they are not band work |

## Design notes for the band

Data shape first. The existing `jstack.board` atom stays. One new atom `jstack.meter`:

```ts
type Meter = {
  cost: number | null
  tokens: { in: number; out: number; cacheRead: number; cacheWrite: number }
  turns: number
  busyMs: number
  context: { percent: number | null }
  limits: { window: string; percent: number; resetsAt: number | null }[]
  agents: { id: string; model: string; type: string; startedAt: number; done: boolean }[]
}
```

Events. `turn.complete` sums `e.usage` into `tokens` and `busyMs`, then reads `$.session.usage()` once for `cost`, `context` and `limits` (no breakdown, so the call is free). `agent.spawn` pushes a row after `await next(e)` returns `agentId`; `turn.complete` with `agentId` marks it done; cap the list at 20. `ui.render { AbovePrompt }` draws the step row, the meter row and the button row inside one `Box`, then `below`. `tool.call { tool: 'mcp__jstack__step' }` is unchanged. Every hook keeps the house `.catch(($, e, next) => next(e))`.

Surface. `e.surface === 'desktop'` may add an `Svg` sparkline of per-turn cost deltas; terminal gets text only. Size everything to `e.props.bodyColumns`; keep the tree under four rows so it never scrolls. Redraw only from `update()` calls, never a timer.

Buttons. Each `Button` gets a `key`. Level pills call `$.command.run` with Ponytail's namespaced command, the same call Ponytail's pills make; if a cross-plugin `command.run` is refused, the fallback is `$.prompt.submit` of the level as plain text, which the Ponytail skill also understands. Confirm every command name against `$.command.list()` in `session.start` and hide a button whose command is absent.

Shipping. A second module next to `register.tsx` in the jstack plugin (`hooks/hooks.json` `modules` takes a list), as `patches/90-band.patch` in `~/dev/skills/jstack`, so the step band patch stays as it is. `types/index.d.ts` gains `meter` by interface merge. `check-jstack` already runs validate, `tsc` and `claude plugin test` over `hooks types tests`. Tests: mount `AbovePrompt` on `desktop` and `terminal` with a stubbed `session.usage`, drive one `turn.complete` and one `agent.spawn`, assert the row text; press the Check button with a stubbed `process.run` and assert the toast.

Proof. A live session in the Desktop Code tab with Ponytail's band off: the band shows cost within a cent of `/cost`, the quota rows match `/usage`, and a `how` fan-out shows its explorers appear and finish.

## Gotchas

- The engine API is unversioned and changed in 11 of the 14 releases since the last pass. Pin the types copy in `~/dev/skills/jstack/types/` and re-run `check-jstack` after each `claude update`.
- `AbovePrompt` ordering between plugins is undocumented; with Ponytail's band off this stops mattering.
- A `.catch`-less gating hook is refused since 2.1.299; render hooks must not call `$.state.set`; `Button`s without `key` lose clicks when redrawn unchanged (fixed 2.1.304, but keep keys).
- Desktop draws no status line and no `tail` for the band (types line 10770); do not rely on either.
- Mods do not draw in `claude -p`, cloud sessions or WSL Desktop sessions; the skills keep their prose fallback.
- The remote rollout switch can turn installed mods off without a local cause.
- Team-account sessions seat `cc-plugin-sec-default` outermost and it skips plugins' `classic.*` hooks (Ponytail #1186, upstream claude-code#103626); the design above uses no `classic.*` event for the meter.
- Cost from `$.session.usage()` is a session total; per-turn cost is a difference of two readings.

## Not verified this pass

- Desktop pane placement (`dock` or `inline`, width) and whether the Code tab honours `$.ui.open` at all. One `--plugin-dir` prototype settles it.
- Whether `$.command.run` of another plugin's namespaced command is allowed from a mod. The types document the call shape, not a cross-plugin rule; the fallback above covers a refusal.
- The exact `rateLimits` entry shape (`window`, `percent`, `resetsAt` names are a guess; read `SessionRateLimit` in the types before coding).
- The Ponytail band's actual per-turn wall time on this machine; `next.trace` on `turn.complete` would give it.

## Built the same evening

The band shipped as `jstack/patches/90-band.patch` in `~/dev/skills` (commits `2a4a54a`, `fcddc50`), installed at user scope, with Ponytail's band hidden through its own `~/.claude/.ponytail-band` flag. Three engine rules the design notes above got wrong, learned from `claude plugin validate` and a live `--plugin-dir` session on 2.1.309:

- A plugin lists one hooks module. The meter lives in `hooks/meter.tsx` and `register.tsx` imports it; `hooks.json` is unchanged.
- A plugin may hook `session.start` once without a matcher, so the meter's startup work runs from the step band's hook. Validate also refuses handing `$` to an imported arrow function; an imported function declaration is fine.
- The engine refuses its own node (the `below` tree from `next(e)`) under a `Box` that carries `width`. The whole band was skipped on every redraw until the width moved to the metrics row alone. `claude plugin test` did not catch it; the debug log did (`a hook returned a tree that does not validate`).

Live on the terminal surface, the band drew the buttons from startup, the metrics after the first turn with cost, context and both quota windows matching the status line, and the agents row through one Explore fan-out, with no engine warnings. The Desktop Code tab is unverified until a new session starts there.

### After the code review

A reviewer read the Desktop renderer in the app bundle: a `Text` whose `wrap` is not `wrap` becomes `overflow:hidden; text-overflow:ellipsis; min-width:0` with the default flex-shrink, and a `Box` `width` becomes `${n}ch`. A sized row of seven cells therefore shrinks every cell to an ellipsis on Desktop, and would on any terminal narrower than about 115 columns. `claude plugin test` cannot see overflow; it never paints. The fix is a row with `flexWrap="wrap"` and `columnGap`, no width, pinned by a structural test on those props. Verified on a 90-column terminal, where the row wraps to two lines. Two more review corrections landed: the token headline now shows input, output and cached apart (cache reads had made it 8.8M against 19.8k output), and the counters restart when `session.usage().startedAt` changes, so `/clear` resets them without a `classic.*` hook. The Compact button and the Svg sparkline stay deferred. A Desktop screenshot after a `claude plugin update` is the remaining proof.

### Second iteration, from use

After a day's use the full metrics row read as noise, so the band collapsed to one line: the context fill coloured green, yellow from 60% and red from 85%, a Level menu and an Actions menu drawn as `Select` elements (the engine's dropdown, present on terminal, desktop and VS Code, absent on mobile), and a More toggle that reveals the cost, token, turn, agent-time and quota cells. The agents row became its own collapsible row with one line per running agent. Both toggles persist in the plugin store, and the More reveal draws stat tiles (a dim caption over a semibold value, sub lines for cached tokens and reset times). Shipped as skills `main` at `38865f6`; the Desktop Code tab confirmed the collapsed line, both menus and the tiles on 2026-10-23.
