# jstack Step Band Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Claude Code mod to the jstack plugin that draws one row above the prompt with the current j-mode playbook, the current step and the done count, fed by a private tool the model calls at zero model cost.

**Architecture:** A hooks module `hooks/register.tsx` registers `step` as `mcp__jstack__step` at `session.start` and answers its calls in a `tool.call` hook. The list lives in `$.state` as one typed atom, is mirrored to `$.store` under the session id, and is reloaded by a `classic.SessionStart` hook when the session is resumed (`/resume`, `claude --continue`, `claude --resume`), which keeps the session id. `/clear` and `/branch` start a new session id, so the band starts empty there, on purpose: the model has lost the todolist too and calls `set` again when it opens one. One `ui.render` hook on `AbovePrompt` draws the row and keeps the band below it. One `prompt.compose` hook appends the list as a session-scoped system prompt section. All files reach the generated plugin through a new `jstack/patches/80-mod.patch` in the `~/dev/skills` repo, never by hand.

**Tech Stack:** Claude Code 2.1.295 (`claude plugin validate`, `claude plugin test`), TypeScript with JSX against the global `h`, `tsc` 6.0.3 from mise (`npm-typescript`, on PATH), bun 1.4.2 (already required by `sync-jstack`), bash 3.2 for `check-jstack`.

**Spec:** `docs/superpowers/specs/2026-10-08-claude-code-mods-assessment.md`. Its "Design notes for the prototype rows" is the sketch, "Configuring, implementing, testing: the recommended way" items 2, 5, 6, 8, 9, 10, 14, 15 and 16 are the rules, and "Review corrections" settles that band props live under `e.props`. The companion plan `2026-10-08-claude-code-mods-adoption.md` runs first (its Task 3 restores the task tools). This plan was revised on 2026-10-08 after an adversarial review that built the edit tree and ran the tests; the "Decisions for review" section records what changed.

## Global constraints

- Version floor is Claude Code 2.1.293, for `isDeferred: false` on `$.tool.register` (api page, "Add a tool", Tip). Installed is 2.1.295 (`claude --version` prints `2.1.295 (Claude Code)`). The README states both.
- `plugins/jstack/` is generated. Every file change goes through `jstack/patches/80-mod.patch` or the `sync-jstack` heredoc, then `scripts/sync-jstack` (skills README, "jstack: generated from upstream").
- Patches are authored against base plus every lower-numbered patch (skills README, "Change or refresh a patch"). The README's `sed` drops the `diff --git` header of a new file, so `git apply` fails with `inconsistent new filename`. Task 1 uses the corrected `sed`, verified on 2026-10-08, and Task 2 fixes the README.
- `claude plugin test <dir>` runs every `*.test.ts` and `*.test.tsx` under `<dir>` in the hooks-module sandbox. The generated tree ships four upstream Bun test files (`skills/j-mode/scripts/orch/orch.test.ts`, `skills/j-mode/scripts/watch-pr/{cli,github,policy}.test.ts`) that import `bun:test` and fail to load there (verified 2026-10-08: `12 pass, 5 fail` on the full tree). The mod's tests therefore always run on a trimmed copy holding only `.claude-plugin/`, `hooks/`, `types/` and `tests/`. `claude plugin test <dir>/tests` does not work (no `hooks/hooks.json` to load).
- Write every mods API call as `$.namespace.method(...)`, event names and matcher values as string literals, and pass `$` only to top-level functions of the same file (create page, "Check what Claude Code reads from your mod"). No module-level mutable state. Hot reload resets module variables and `$.state` survives it (interface page, "Keep state").
- `.catch` on every registration (`Registration.catch`, `claude-code.d.ts` line 9339; `Caught.called` line 1192). Call `next(e)` on every path that does not answer. Colors are theme keys (`ThemeKey`, line 12590), never hex. A `.catch` that only calls `next(e)` behaves the same as no `.catch` (a failed hook is absent and the chain continues), so it documents intent and cannot be unit-tested; the test kit also rejects a `ui.resolve` stub that returns anything but an element table.
- Every write to the list goes through `update($, board, change)`, with parsing and applying inside `change`, because `update` re-reads and retries on a version miss (`UpdateFunction`, line 14585) and the model does send parallel `step` calls in one turn (verified: a read-then-write version lost one of two parallel `done` calls).
- `claude plugin validate` runs without `--strict`: strict mode turns the deliberate missing `version` (and the two informational `types` lines) into a failure. The spec's checklist item 15 suggests `--strict`; it does not fit a plugin that omits `version` on purpose.
- `check-jstack` must stay bash 3.2. `claude plugin validate` and `claude plugin test` do not type-check (GitHub issue #99771 via the spec), so `tsc` is a separate step. New text in `plugins/jstack` must pass `check-jstack`'s forbidden regex (`\bTask tool\b`, `AskQuestion\b`, `[A-Za-z]jstack`, `\bCursor\b` and the rest). `mcp__jstack__step` passes because `_` precedes `jstack` (checked with `grep -E` on 2026-10-08).
- Commit subjects in `~/dev/skills` are short, imperative, sentence case. Run `/simplify` then `/code-review` on each commit's diff before committing. Plan prose and code comments follow j-mode. Short sentences, no long dashes, and comments only for a non-obvious why.
- Task 1's steps share one shell: `$base` and `$edit` are set in step 1 and used through step 11.

## Review focus

1. A `set` whose `steps` is empty, or has any entry that is not a non-empty string. The tool answers with the valid shape and the list keeps what it had. Pinned in Task 1 test `set with no usable steps is refused`, which sends both an all-bad list and a mixed one.
2. `done 7` on a three-step list, or `skip` with no reason. The result names the valid range or the missing field and nothing changes. Pinned in Task 1 test `an index outside the list is refused and nothing changes`.
3. A store record from an older build after a resume, such as a step with an unknown state or a bare string. The band draws nothing and the band below stays. Pinned in Task 1 test `a bad store record after a resume draws nothing`, which tries both shapes. (Whether `toBoard` returned `null` or threw into the `.catch` is not distinguishable from outside; the kit cannot pin "nothing throws".)
4. Two `step` calls in one turn (the model marks two steps done at once). Both land. Pinned in Task 1 test `parallel done calls both land`.
5. A survey holding the band, `e.props.hasSurvey` true (`claude-code.d.ts` line 10259). The hook yields with `next(e)`. Pinned in Task 1 test `the band yields to a survey`.

A subagent call (`e.agentId` set, `AgentLoop` line 194) leaving the main list untouched is pinned by test `a subagent call never touches the main list`. The empty band after `/clear` and `/branch` cannot be tested in the kit, whose `session.id` stub is constant; Task 3 step 2 checks it live.

---

### Task 1: The mod, its tests and the patch (estimate 4 person-hours)

**Files:**
- Create via patch: `plugins/jstack/hooks/hooks.json`, `plugins/jstack/hooks/register.tsx`, `plugins/jstack/types/index.d.ts`, `plugins/jstack/tests/step-band.test.tsx`, `plugins/jstack/.gitignore`
- Modify via patch: `plugins/jstack/skills/j-mode/SKILL.md` (the Playbooks paragraph, line 123 in the current tree)
- Create: `~/dev/skills/jstack/patches/80-mod.patch`
- Modify: `~/dev/skills/scripts/sync-jstack` (the `plugin.json` heredoc)

**Interfaces:**
- Consumes: `Register` (`claude-code.d.ts` line 9301), `atom`, `read`, `update` from `claude-code` (lines 14701, 14726, 14735; `UpdateFunction` line 14585 resolves to what it wrote), `ToolSpec` with `isDeferred?: boolean` (lines 13117 and 13140, `ToolDeferral` line 12903), `ToolCallResult` `{ result }` (line 12701), tool arguments flat on the `tool.call` event beside `tool` (`ToolCallEnvelope` line 12647), `e.agentId` (line 194), `e.props.hasSurvey` and `e.props.bodyColumns` (lines 10259 and 10284), `$.store.get/set` (lines 3351 to 3366), `$.session.id()` (line 2796, "the transcript file's name"), `classic.SessionStart` `source` values `startup | resume | clear | compact | fork` (line 11645), `PromptComposeSection { id, text, scope }` (line 8382).
- Produces: the tool `mcp__jstack__step` (api page, "Add a tool": `mcp__`, plugin name, two underscores, registered name) with ops `set`, `done`, `skip`, `add`, `show`; the atom `{ plugin: 'jstack', key: 'board' }`; store key `steps:<session id>`; system prompt section id `jstack:steps`.

- [ ] **Step 1: Build the base tree and an edit copy**

```bash
cd ~/dev/skills
base=$(mktemp -d)/jstack-base
JSTACK_NO_CHECK=1 scripts/sync-jstack --out "$base"
edit="${base%-base}-edit" && cp -R "$base" "$edit"
mod() { rm -rf "$1/../mod" && mkdir "$1/../mod" && cp -R "$1/.claude-plugin" "$1/hooks" "$1/types" "$1/tests" "$1/../mod/" && echo "$1/../mod"; }
```

Expected: `sync-jstack: … from https://github.com/cursor/plugins.git@12d587…`. Patches 10 to 70 are applied, so the edit tree already has the todolist rule at `skills/j-mode/SKILL.md` line 13. `mod` builds the trimmed copy the tests run on (Global constraints, fourth bullet); keep this shell open through step 11.

- [ ] **Step 2: Write the type contract**

Create `$edit/types/index.d.ts`:

```typescript
export type StepState = 'todo' | 'done' | 'skip'
export type Step = { text: string; state: StepState; reason?: string }
export type Board = { playbook: string; steps: Step[]; current: number }

declare module 'claude-code' {
  interface PluginState {
    jstack: { board: Board | null }
  }
}
```

- [ ] **Step 3: Write the failing tests**

Create `$edit/tests/step-band.test.tsx`:

```tsx
import { expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On, RenderPropsOf } from 'claude-code'

const TOOL = 'mcp__jstack__step'
const BAND: RenderPropsOf['AbovePrompt'] = { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 80, scroll: { offset: 0, bodyRows: 10 }, view: {} }
function world(on: On, saved = new Map<string, unknown>()) {
  on('store.get', ($, e) => ({ value: saved.get(e.key) }))
  on('store.set', ($, e) => { saved.set(e.key, e.value); return { value: undefined } })
  on('session.id', () => ({ value: 'S1' }))
  on('session.start', () => ({ cwd: '/work' }))
  on('classic.SessionStart', () => ({}))
  on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'engine', scope: 'shared' as const }] }))
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['below'] }))
  return saved
}

const call = ($: Engine, input: Record<string, unknown>) => $.tool.call({ tool: TOOL, ...input })
const mount = ($: Engine, surface: 'terminal' | 'desktop', props = BAND) =>
  $.ui.mount({ plugin: 'jstack', surface, component: 'AbovePrompt', props })
const set = ($: Engine) => call($, { op: 'set', playbook: 'Feature', steps: ['Name the shape', 'Write the test', 'Implement'] })
test('session.start registers step upfront', async ($, on) => {
  world(on)
  const specs: unknown[] = []
  on('tool.register', ($, e) => { specs.push(e); return { value: { tool: 'mcp__jstack__' + e.name } } })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  expect(specs[0]).toMatchObject({ name: 'step', isDeferred: false })
})
test('set, done and skip draw the row on both surfaces and save the list', async ($, on) => {
  const saved = world(on)
  const first = await set($)
  expect(first.result).toBe('Feature\n1. [ ] Name the shape\n2. [ ] Write the test\n3. [ ] Implement')
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await mount($, surface)
    expect(await ui.find({ type: 'Text', text: 'Feature · step 1/3 · 0 done: Name the shape' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'below' })).toBeDefined()
    await ui.unmount()
  }
  await call($, { op: 'done', index: 1 })
  const skipped = await call($, { op: 'skip', index: 2, reason: 'covered by the existing suite' })
  expect(skipped.result).toContain('2. [-] Write the test (skip: covered by the existing suite)')
  const ui = await mount($, 'terminal')
  expect(await ui.find({ type: 'Text', text: 'Feature · step 3/3 · 1 done: Implement' })).toBeDefined()
  await ui.unmount()
  expect(saved.get('steps:S1')).toMatchObject({ playbook: 'Feature', current: 2 })
})
test('parallel done calls both land', async ($, on) => {
  world(on)
  await set($)
  await Promise.all([call($, { op: 'done', index: 1 }), call($, { op: 'done', index: 2 })])
  expect((await call($, { op: 'show' })).result).toBe('Feature\n1. [x] Name the shape\n2. [x] Write the test\n3. [ ] Implement')
})
test('an empty list draws nothing and the band below stays', async ($, on) => {
  world(on)
  const ui = await mount($, 'terminal')
  expect(await ui.find({ type: 'Text', text: /Feature/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'below' })).toBeDefined()
})
test('a long row is cut to bodyColumns', async ($, on) => {
  world(on)
  await call($, { op: 'set', playbook: 'Feature', steps: ['x'.repeat(200)] })
  const ui = await mount($, 'terminal', { ...BAND, bodyColumns: 40 })
  const row = await ui.find({ type: 'Text', text: /^Feature/ })
  expect(row?.text.length).toBe(40)
})
test('a bad op returns the help string', async ($, on) => {
  world(on)
  const out = await call($, { op: 'finish' })
  expect(out.result).toBe('step: unknown op "finish"; valid ops: set (playbook, steps), done (index), skip (index, reason), add (text), show')
})
test('set with no usable steps is refused', async ($, on) => {
  world(on)
  await set($)
  const refused = 'step: set needs playbook (string) and steps (non-empty string array)'
  expect((await call($, { op: 'set', playbook: 'Bug fix', steps: [1, ''] })).result).toBe(refused)
  expect((await call($, { op: 'set', playbook: 'Bug fix', steps: ['Reproduce', 1] })).result).toBe(refused)
  expect((await call($, { op: 'show' })).result).toContain('Feature')
})
test('an index outside the list is refused and nothing changes', async ($, on) => {
  world(on)
  expect((await call($, { op: 'done', index: 1 })).result).toBe('step: no list yet; call set first')
  await set($)
  expect((await call($, { op: 'done', index: 7 })).result).toBe('step: done needs index between 1 and 3')
  expect((await call($, { op: 'skip', index: 2 })).result).toBe('step: skip needs reason (string)')
  expect((await call($, { op: 'show' })).result).toContain('1. [ ] Name the shape')
})
test('a subagent call never touches the main list', async ($, on) => {
  world(on)
  await set($)
  const out = await call($, { op: 'done', index: 1, agentId: 'agent-7' })
  expect(out.result).toBe('step: ignored; the band shows the main session only, keep your own todolist')
  expect((await call($, { op: 'show' })).result).toContain('1. [ ] Name the shape')
})
test('the band yields to a survey', async ($, on) => {
  world(on)
  await set($)
  const ui = await mount($, 'terminal', { ...BAND, hasSurvey: true })
  expect(await ui.find({ type: 'Text', text: /Feature/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'below' })).toBeDefined()
})
test('a valid store record comes back after a resume', async ($, on) => {
  const record = { playbook: 'Bug fix', steps: [{ text: 'Reproduce', state: 'done' }, { text: 'Fix', state: 'todo' }], current: 1 }
  world(on, new Map([['steps:S1', record]]))
  await $.classic.SessionStart({ source: 'resume' })
  const ui = await mount($, 'terminal')
  expect(await ui.find({ type: 'Text', text: 'Bug fix · step 2/2 · 1 done: Fix' })).toBeDefined()
})
test('a bad store record after a resume draws nothing', async ($, on) => {
  const saved = world(on, new Map<string, unknown>([['steps:S1', { playbook: 'Bug fix', steps: [{ text: 'Fix', state: 'later' }], current: 0 }]]))
  await $.classic.SessionStart({ source: 'resume' })
  let ui = await mount($, 'terminal')
  expect(await ui.find({ type: 'Text', text: /Bug fix/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'below' })).toBeDefined()
  await ui.unmount()
  saved.set('steps:S1', 'old-format')
  await $.classic.SessionStart({ source: 'resume' })
  ui = await mount($, 'terminal')
  expect(await ui.find({ type: 'Text', text: /old-format|Bug fix/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'below' })).toBeDefined()
})
test('prompt.compose appends one session section listing the steps', async ($, on) => {
  world(on)
  await set($)
  await call($, { op: 'done', index: 1 })
  const composed = await $.prompt.compose({ model: 'm', promptModel: 'm', surfaces: ['terminal'], tools: [], outputStyle: null, traits: [] })
  const last = composed.sections[composed.sections.length - 1]
  expect(last).toMatchObject({ id: 'jstack:steps', scope: 'session' })
  expect(last?.text).toContain('1. [x] Name the shape')
})
```

- [ ] **Step 4: Run the tests to verify they fail**

Run `claude plugin test "$(mod "$edit")"`. Expected: `no hooks module to load; there is no hooks/hooks.json naming one in "modules"` (verified 2026-10-08). Nothing passes yet.

- [ ] **Step 5: Write the hooks pointer and the gitignore**

Create `$edit/hooks/hooks.json`:

```json
{ "modules": ["./register.tsx"] }
```

Create `$edit/.gitignore`:

```gitignore
# Claude Code writes the mod's TypeScript types here on each --plugin-dir load,
# and a tsconfig.json at the mod root when the mod has none (create page,
# "Get type definitions for your version")
.claude-plugin/types/
/tsconfig.json
```

- [ ] **Step 6: Write the hooks module**

Create `$edit/hooks/register.tsx`:

```tsx
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Board, Step } from '../types'

const board = atom({ plugin: 'jstack', key: 'board' } as const, null)
const OPS = 'set (playbook, steps), done (index), skip (index, reason), add (text), show'
const STATES = new Set(['todo', 'done', 'skip'])
const MARK = { todo: ' ', done: 'x', skip: '-' } as const
type Op = { op: 'set'; playbook: string; steps: string[] } | { op: 'done' | 'skip'; index: number; reason?: string } | { op: 'add'; text: string } | { op: 'show' }
function isStep(x: unknown): x is Step {
  if (typeof x !== 'object' || x === null) return false
  const s = x as Record<string, unknown>
  return typeof s.text === 'string' && typeof s.state === 'string' && STATES.has(s.state) && (s.reason === undefined || typeof s.reason === 'string')
}

// The store outlives this code, so a record from an older build must read as empty
function toBoard(x: unknown): Board | null {
  if (typeof x !== 'object' || x === null) return null
  const b = x as Record<string, unknown>
  if (typeof b.playbook !== 'string' || !Array.isArray(b.steps) || !b.steps.every(isStep)) return null
  return normalize(b.playbook, b.steps)
}
function normalize(playbook: string, steps: Step[]): Board {
  const current = steps.findIndex(s => s.state === 'todo')
  return { playbook, steps, current: current === -1 ? steps.length : current }
}
function show(b: Board): string {
  const lines = b.steps.map((s, i) =>
    `${i + 1}. [${MARK[s.state]}] ${s.text}${s.state === 'skip' && s.reason ? ` (skip: ${s.reason})` : ''}`)
  return [b.playbook, ...lines].join('\n')
}
function rowText(b: Board, columns: number): string {
  const done = b.steps.filter(s => s.state === 'done').length
  const step = b.steps[b.current]
  const text = step
    ? `${b.playbook} · step ${b.current + 1}/${b.steps.length} · ${done} done: ${step.text}`
    : `${b.playbook} · ${b.steps.length}/${b.steps.length} finished · ${done} done`
  return text.length > columns ? text.slice(0, Math.max(0, columns - 1)) + '…' : text
}
function parse(input: Record<string, unknown>, size: number): Op | string {
  const str = (k: string) => (typeof input[k] === 'string' && (input[k] as string).trim()) || undefined
  switch (input.op) {
    case 'set': {
      const playbook = str('playbook')
      const steps = (Array.isArray(input.steps) ? input.steps : []).map(s => (typeof s === 'string' ? s.trim() : ''))
      return playbook && steps.length && steps.every(s => s !== '')
        ? { op: 'set', playbook, steps }
        : 'set needs playbook (string) and steps (non-empty string array)'
    }
    case 'done':
    case 'skip': {
      if (size === 0) return 'no list yet; call set first'
      const index = Number(input.index)
      if (!Number.isInteger(index) || index < 1 || index > size) return `${input.op} needs index between 1 and ${size}`
      if (input.op === 'skip' && !str('reason')) return 'skip needs reason (string)'
      return { op: input.op, index, reason: str('reason') }
    }
    case 'add': {
      if (size === 0) return 'no list yet; call set first'
      const text = str('text')
      return text ? { op: 'add', text } : 'add needs text (string)'
    }
    case 'show':
      return size === 0 ? 'no list yet; call set first' : { op: 'show' }
    default:
      return `unknown op ${JSON.stringify(input.op)}; valid ops: ${OPS}`
  }
}
function apply(prev: Board | null, op: Op): Board | null {
  if (op.op === 'set') return normalize(op.playbook, op.steps.map(text => ({ text, state: 'todo' as const })))
  if (!prev || op.op === 'show') return prev
  if (op.op === 'add') return normalize(prev.playbook, [...prev.steps, { text: op.text, state: 'todo' }])
  const steps = prev.steps.map((s, i) => {
    if (i !== op.index - 1) return s
    return op.op === 'done' ? { text: s.text, state: 'done' as const } : { text: s.text, state: 'skip' as const, reason: op.reason }
  })
  return normalize(prev.playbook, steps)
}
async function save($: EngineInterface, b: Board): Promise<void> {
  await $.store.set(`steps:${await $.session.id()}`, b)
}
async function load($: EngineInterface): Promise<void> {
  const raw = await $.store.get(`steps:${await $.session.id()}`)
  await update($, board, () => toBoard(raw))
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.tool.register({
      name: 'step',
      description:
        'Mirror the j-mode playbook todolist into the band above the prompt. Call with op "set" (playbook, steps) when you open the todolist, ' +
        'then "done" (index) or "skip" (index, reason) per step, "add" (text) for a new step, "show" to print it. Indexes start at 1. No model call, nothing runs.',
      inputSchema: {
        type: 'object',
        required: ['op'],
        properties: {
          op: { type: 'string', enum: ['set', 'done', 'skip', 'add', 'show'] },
          playbook: { type: 'string', description: 'The playbook name, for set.' },
          steps: { type: 'array', items: { type: 'string' }, description: 'The step texts in order, for set.' },
          index: { type: 'integer', minimum: 1, description: 'The step number, for done and skip.' },
          reason: { type: 'string', description: 'Why the step is skipped, for skip.' },
          text: { type: 'string', description: 'The new step, for add.' },
        },
      },
      isDeferred: false,
    })
    return next(e)
  }).catch(($, e, next) => next(e))

  // A resume keeps the session id but resets $.state; /clear and /branch start a
  // new id, so their band begins empty and the model calls set again
  on('classic.SessionStart', { source: ['resume'] }, async ($, e, next) => {
    await load($)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('tool.call', { tool: 'mcp__jstack__step' }, async ($, e) => {
    if (e.agentId !== undefined) return { result: 'step: ignored; the band shows the main session only, keep your own todolist' }
    const input = e as unknown as Record<string, unknown>
    // Parse and apply inside the updater, so two calls in one turn both land
    const out: { refusal: string | null } = { refusal: null }
    const after = await update($, board, prev => {
      const op = parse(input, prev?.steps.length ?? 0)
      if (typeof op === 'string') {
        out.refusal = op
        return prev ?? null
      }
      out.refusal = null
      return apply(prev ?? null, op)
    })
    if (out.refusal !== null) return { result: `step: ${out.refusal}` }
    if (after) await save($, after)
    return { result: after ? show(after) : 'step: no list yet; call set first' }
  }).catch(($, e, next) => ({ result: `step: the tool failed (${next.error.kind}); call show to read the list` }))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const b = await read($, board)
    if (!b || b.steps.length === 0) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const below = await next(e)
    return (
      <Box flexDirection="column">
        <Text color="suggestion" wrap="truncate-end">{rowText(b, e.props.bodyColumns)}</Text>
        {below}
      </Box>
    )
  }).catch(($, e, next) => next(e))

  on('prompt.compose', async ($, e, next) => {
    const composed = await next(e)
    const b = await read($, board)
    if (!b || b.steps.length === 0) return composed
    const text = `The playbook todolist this session, as the jstack step band shows it:\n${show(b)}`
    return { sections: [...composed.sections, { id: 'jstack:steps', text, scope: 'session' as const }] }
  }).catch(($, e, next) => next(e))
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `claude plugin test "$(mod "$edit")"`
Expected: `13 pass`, `0 fail`, `Ran 13 tests across 1 file.`

- [ ] **Step 8: Validate the edit tree**

The manifest needs `types` for validate to check the atom against the contract (interface page, "Point the manifest at the declaration"). Add it to the heredoc in `~/dev/skills/scripts/sync-jstack`, after the `"author"` line:

```json
  "author": { "name": "Jason Matherly" },
  "types": "./types/index.d.ts",
  "license": "MIT"
```

Then apply the same line to `$edit/.claude-plugin/plugin.json` by hand (the edit tree is scratch) and run:

```bash
claude plugin validate "$edit"
```

Expected, verified on 2026-10-08 (the `version` warning is deliberate: `sync-jstack` omits `version` so Claude Code tracks the repo's commits):

```text
⚠ Found 1 warning:
  ❯ version: No version specified. …
  ❯ types ./types/index.d.ts declares on $: nothing (no EngineInterface member)
  ❯ types ./types/index.d.ts declares state: jstack.board
Validating hooks: …/jstack-edit/hooks/hooks.json
  ❯ ./register.tsx hooks: session.start, classic.SessionStart{source=resume}, tool.call{tool=mcp__jstack__step}, ui.render{component=AbovePrompt}, prompt.compose
  ❯ ./register.tsx gating hook with .catch: classic.SessionStart{source=resume}
  ❯ ./register.tsx gating hook with .catch: tool.call{tool=mcp__jstack__step}
  ❯ ./register.tsx calls: $.session.id (via load, save), $.state.get, $.state.set, $.store.get (via load), $.store.set (via save), $.tool.register, $.ui.resolve
  ❯ ./register.tsx state writes: jstack.board
  ❯ ./register.tsx state reads: jstack.board
✔ Validation passed with warnings
```

No `gating hook without .catch` line may appear. Keep the printed `calls:` line for Task 2.

- [ ] **Step 9: Add the SKILL.md sentence**

In `$edit/skills/j-mode/SKILL.md`, the Playbooks paragraph (line 123) ends with `copy its steps in verbatim.` Append to that paragraph, then confirm `grep -nE '\bTask tool\b|AskQuestion\b|[A-Za-z]jstack|\bCursor\b' "$edit/skills/j-mode/SKILL.md"` prints nothing:

```markdown
 When the `mcp__jstack__step` tool is present, mirror the list into it. Call it with `op: "set"` (the playbook name and the step texts) as you open the todolist, then `done` or `skip` with the step number as you go, and `set` again after `/clear` or `/branch`, which empty the band. The todolist stays the record. The band is the operator's view.
```

- [ ] **Step 10: Write the patch**

A new file diffs as `a/jstack-edit/… b/jstack-edit/…`. The second `sed` rule below rewrites that header, so `git apply` creates the file from `--- /dev/null` plus `new file mode` (verified on 2026-10-08: six headers, `git apply --check` clean against a fresh base, applied tree byte-identical to the edit tree):

```bash
cd ~/dev/skills
rm -f "$edit/.claude-plugin/plugin.json" && cp "$base/.claude-plugin/plugin.json" "$edit/.claude-plugin/"
(cd "$(dirname "$base")" && git diff --no-index jstack-base jstack-edit || true) \
  | sed -E 's#^(---|\+\+\+) (a|b)/jstack-(base|edit)/#\1 \2/#; s#^diff --git a/jstack-(base|edit)/(.*) b/jstack-(base|edit)/#diff --git a/\2 b/#' \
  > jstack/patches/80-mod.patch
grep -c '^diff --git' jstack/patches/80-mod.patch
```

Expected: `6` (gitignore, hooks.json, register.tsx, SKILL.md, step-band.test.tsx, index.d.ts). The manifest is restored first because `sync-jstack` writes it itself.

- [ ] **Step 11: Regenerate and check**

Run: `scripts/sync-jstack && git status --short`
Expected: `sync-jstack: …/plugins/jstack from …`, and `git status` lists `jstack/patches/80-mod.patch`, `scripts/sync-jstack` and the new files under `plugins/jstack/`. `check-jstack` runs `claude plugin validate` on the result and passes (its `tsc` and test steps arrive in Task 2).

- [ ] **Step 12: Commit**

```bash
git add jstack/patches/80-mod.patch scripts/sync-jstack plugins/jstack
git commit -m "Add the step band mod to jstack"
```

### Task 2: Gate the mod in check-jstack and document it (estimate 1.5 person-hours)

**Files:**
- Create: `~/dev/skills/jstack/types/claude-code.d.ts` (a copy of the 2.1.295 declarations, 798,976 bytes)
- Create: `~/dev/skills/.gitattributes`
- Modify: `~/dev/skills/scripts/check-jstack` (the `dir=` line and after the `claude plugin validate` line)
- Modify: `~/dev/skills/README.md` ("Install", "jstack: generated from upstream", "Change or refresh a patch")

**Interfaces:**
- Consumes: the tsconfig the declarations' header prescribes (`claude-code.d.ts` lines 68 to 78: `target es2023`, `lib ["es2023"]`, `types []`, `module esnext`, `moduleResolution bundler`, `strict`, `noUncheckedIndexedAccess`, `noEmit`, `skipLibCheck`, `jsx react`, `jsxFactory h`, `jsxFragmentFactory Fragment`); `tsc` 6.0.3 accepts it with absolute `include` paths and no `ignoreDeprecations` (verified 2026-10-08).
- Produces: `check-jstack` fails on a type error or a failing test, so `sync-jstack` never replaces `plugins/jstack` with a broken mod.

- [ ] **Step 1: Copy the declarations into the repo**

Neither `claude plugin validate` nor `claude plugin test` writes the declarations; only a `--plugin-dir` load does, beside the loaded mod (create page, "Get type definitions for your version"), and `plugins/jstack` is rebuilt on every sync. So the copy lives outside it. The bundled `plugin-authoring` skill carries the same file, under a session-local temp path that exists only after the skill has run once in some session on this machine. Run `/plugin-authoring` in a Claude Code session if the `ls` below finds nothing; its reply names the file.

```bash
mkdir -p ~/dev/skills/jstack/types
cp "$(ls -t /private/tmp/claude-501/bundled-skills/*/*/plugin-authoring/types/claude-code.d.ts | head -1)" ~/dev/skills/jstack/types/claude-code.d.ts
head -1 ~/dev/skills/jstack/types/claude-code.d.ts
printf 'jstack/types/claude-code.d.ts linguist-generated -diff\n' > ~/dev/skills/.gitattributes
```

Expected: `// Written by Claude Code 2.1.295.` The `.gitattributes` line keeps the 780 KiB file out of `git diff` output and language statistics.

- [ ] **Step 2: Add the type check and the tests to check-jstack**

In `scripts/check-jstack`, replace the `dir=` line with these lines (the script sets `-u` but not `-e`, so a missing directory must stop it here rather than leave `dir` empty):

```bash
dir="${1:-$(cd "$(dirname "$0")/.." && pwd -P)/plugins/jstack}"
dir="$(cd "$dir" 2> /dev/null && pwd -P)" || { echo "check-jstack: no such directory: ${1:-plugins/jstack}" >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd -P)"
```

Then add this block after the `claude plugin validate` line:

```bash
# validate and test do not type-check (GitHub issue #99771), so tsc runs against a committed copy of the declarations
types="$root/jstack/types/claude-code.d.ts"
built=$(sed -n '1s/.*Claude Code \([0-9.]*\)\..*/\1/p' "$types")
have=$(claude --version | cut -d' ' -f1)
[ "$built" = "$have" ] || echo "check-jstack: jstack/types/claude-code.d.ts is from $built, claude is $have" >&2
tsdir=$(mktemp -d)
trap 'rm -rf "$tsdir"' EXIT
cat > "$tsdir/tsconfig.json" << JSON
{
  "compilerOptions": { "target": "es2023", "lib": ["es2023"], "types": [], "module": "esnext", "moduleResolution": "bundler",
    "strict": true, "noUncheckedIndexedAccess": true, "noEmit": true, "skipLibCheck": true,
    "jsx": "react", "jsxFactory": "h", "jsxFragmentFactory": "Fragment" },
  "include": ["$types", "$dir/hooks", "$dir/types", "$dir/tests"]
}
JSON
command -v tsc > /dev/null || bad "tsc: not found (mise install npm:typescript)"
tsc -p "$tsdir/tsconfig.json" || bad "tsc: $dir does not type-check"
# claude plugin test runs every *.test.ts(x) under the dir, and upstream's bun:test files cannot load in its sandbox
mkdir "$tsdir/mod" && cp -R "$dir/.claude-plugin" "$dir/hooks" "$dir/types" "$dir/tests" "$tsdir/mod/"
claude plugin test "$tsdir/mod" > /dev/null 2>&1 || bad "claude plugin test failed on $dir (run it on a copy of .claude-plugin, hooks, types and tests for the output)"
```

- [ ] **Step 3: Run the check on the generated tree, then break it on purpose**

Run `scripts/check-jstack && echo OK`. Expected: `OK` and no version warning. Then prove the gate bites on a scratch copy:

```bash
tmp=$(mktemp -d) && cp -R plugins/jstack "$tmp/jstack"
sed -i '' 's/const done = b.steps.filter/const done: string = b.steps.filter/' "$tmp/jstack/hooks/register.tsx"
scripts/check-jstack "$tmp/jstack"; echo "exit $?"
scripts/check-jstack /no/such/dir; echo "exit $?"
```

Expected: a `tsc` error `register.tsx(…): error TS2322`, then `tsc: …/jstack does not type-check` and `exit 1`; then `check-jstack: no such directory: /no/such/dir` and `exit 2`.

- [ ] **Step 4: Document in the skills README**

In "Install", after the fenced block ending `claude plugin install resume@jrmatherly-skills`, add this paragraph. Its `calls:` line is the one `claude plugin validate` printed in Task 1 step 8; paste that output if it differs:

```markdown
jstack ships a mod (a hooks module) that draws the j-mode step band above
the prompt. It needs Claude Code 2.1.293 or later and was tested on 2.1.295.
`claude plugin validate plugins/jstack` lists what it can reach as
`calls: $.session.id, $.state.get, $.state.set, $.store.get, $.store.set,
$.tool.register, $.ui.resolve`. No process, file, network or model calls.
Its private tool `mcp__jstack__step` costs no model call.
```

In "jstack: generated from upstream", add `80-mod` to the patch list, and add this bullet to the list of checks that gate the replace:

```markdown
- `tsc --noEmit` over `hooks/`, `types/` and `tests/` against
  `jstack/types/claude-code.d.ts`, then `claude plugin test` on a copy that
  holds only the mod (neither `claude plugin validate` nor `claude plugin
  test` type-checks, and the upstream `bun:test` files cannot load in the
  test sandbox)
```

In "Change or refresh a patch", replace the `sed` line in the code block with the one from Task 1 step 10, and add this paragraph right after that code block:

```markdown
A new file diffs as `a/jstack-edit/… b/jstack-edit/…`. The second `sed`
rule rewrites that header so `git apply` creates the file. Without it
`git apply` stops with `inconsistent new filename`.
```

Then add this subsection before "### Attribution":

```markdown
### Refresh the mod types

`jstack/types/claude-code.d.ts` is the mods API as the installed Claude Code
declares it. After `claude update`, run `/plugin-authoring` once in a session,
copy the `claude-code.d.ts` it names over this file and commit. `check-jstack`
prints a one-line warning while the two versions differ.
```

- [ ] **Step 5: Commit**

```bash
scripts/check-jstack && git add .gitattributes jstack/types/claude-code.d.ts scripts/check-jstack README.md
git commit -m "Type-check and test the jstack mod in check-jstack"
```

### Task 3: Prove it live, then publish (estimate 1 person-hour)

**Files:**
- Read: `~/dev/skills/plugins/jstack`, loaded with `--plugin-dir`, which writes `.claude-plugin/types/` and a root `tsconfig.json` into it (create page, "Get type definitions for your version"), both ignored by the new `.gitignore`.
- Modify: none in `~/dev/skills`. The push and `claude plugin update jstack@jrmatherly-skills` are the deliverable. Then this plan moves to `docs/superpowers/plans/completed/`.

- [ ] **Step 1: Load the mod in a scratch repo and drive the band**

```bash
mkdir -p /tmp/step-band-live && cd /tmp/step-band-live && git init -q
claude --plugin-dir ~/dev/skills/plugins/jstack
```

In the session run `/plugin`. Expected: `1 mod active · jstack` under the tabs (reference page, "Commands"). Then send:

```text
Call mcp__jstack__step with op "set", playbook "Feature" and steps ["Name the data shape", "Write the failing test", "Implement"]. Then call it with op "done" and index 1. Reply with only the second result.
```

Expected: the band reads `Feature · step 2/3 · 1 done: Write the failing test` and the reply quotes `1. [x] Name the data shape`. If the band shows Claude Code's usual content, read the transcript line `jstack: ui.render (AbovePrompt) refused: …` (interface page, "Build a tree from elements") and fix the prop it names.

- [ ] **Step 2: Check resume, clear and the git tree**

Exit the session (Ctrl-D), then run `claude --continue --plugin-dir ~/dev/skills/plugins/jstack`. Expected: the row is drawn again as soon as the session opens, reloaded from the store by the `classic.SessionStart` hook (a resume keeps the session id). Then run `/clear`. Expected: the row disappears (a new session id has no record), and Claude Code's own band content shows. Exit, then run `git -C ~/dev/skills status --short`. Expected: empty, because `.claude-plugin/types/` and the root `tsconfig.json` the load wrote are ignored. If `tsconfig.json` shows up anyway, read the create page for where this version writes it and widen the `.gitignore` in a follow-up patch.

- [ ] **Step 3: Publish, update the installed plugin, file the plan**

```bash
cd ~/dev/skills && git push
claude plugin marketplace update jrmatherly-skills && claude plugin update jstack@jrmatherly-skills
claude plugin validate "$(ls -td ~/.claude/plugins/cache/jrmatherly-skills/jstack/*/ | head -1)"
cd ~/dev/dotfiles && git mv docs/superpowers/plans/2026-10-08-jstack-step-band.md docs/superpowers/plans/completed/
pnpm check && git commit -m "Mark the jstack step band plan completed" && git push
```

Expected: `Validation passed with warnings` with the same `hooks:` and `calls:` lines as Task 1 step 8 (the cache keeps one directory per commit, so the newest is validated, not the first in sort order), and `/plugin` in a new session in any repo shows `1 mod active · jstack`.

## Decisions for review

1. **One atom, `board`, holding `Board | null`.** `current` is recomputed on every write as the first `todo` index, so the model cannot set it inconsistently. Indexes start at 1 in the tool and in `show`, matching `step k/n`. The done count counts `done` only; skipped steps keep their reason in `show` and advance `current`.
2. **Subagent calls are ignored** (`e.agentId` set). j-agent subagents also load j-mode and would overwrite the operator's band.
3. **`/clear` and `/branch` empty the band; only a resume reloads it** (revised after review). The store key is the session id, and those two commands start a new id (how-claude-code-works page, line 111; `claude-code.d.ts` lines 11054 to 11060). The first draft listed `clear` and `fork` as reload sources, which could never find the record. Carrying the list across would need a shared hand-off key written from a `session.end` hook, with the cross-session race the interface page describes; not worth it for a prototype. The SKILL.md sentence tells the model to `set` again after those commands.
4. **Store keys are never deleted.** One record per session, under 1 KB, against the 4 MiB limit (reference page, "Limits"). A `session.end` cleanup waits until the store shows growth.
5. **The `prompt.compose` section is `scope: 'session'`**, after the cache boundary (`PromptComposeScope`, `claude-code.d.ts` line 8373). Each step change misses the session side of the cache, the same cost the task tools' reminders pay.
6. **The declarations are committed** at `jstack/types/claude-code.d.ts` (780 KiB), marked `linguist-generated -diff`. `check-jstack` runs on a fresh stage with no `.claude-plugin/types/`, and a `--plugin-dir` load inside a check would start a session.
7. **The matcher value is a string literal**, so `claude plugin validate` prints `tool.call{tool=mcp__jstack__step}` without depending on constant folding. **Row color is the `suggestion` theme key**, one `Text` with `wrap: 'truncate-end'` plus a `slice` to `bodyColumns`, so Desktop and terminal agree on one row.
8. **No render-hook `.catch` test** (revised after review). The kit rejects a `ui.resolve` stub that returns a deny, and a pass-through `.catch` is indistinguishable from no `.catch`, so the first draft's thirteenth test was dropped and a parallel-calls test took its place.
9. **Nothing changes in the dotfiles repo** beyond this plan file. `agents/claude-plugins.txt` already names `jstack@jrmatherly-skills`.

## Open questions

- Is `below` from `await next(e)` on `AbovePrompt` a valid child when no other mod draws there (null or an engine reference)? Settled by Task 3 step 1 in the live session; a refused tree prints the reason in the transcript.
- Does `claude --continue` fire `classic.SessionStart` with `source: 'resume'`, so the band returns in Task 3 step 2? The hooks reference lists `resume` for resumed sessions; the live step settles it. If it fires `startup`, add `startup` to the matcher (a startup with no record loads nothing).
- Is MCP tool search active in Jason's sessions, so that `isDeferred: false` is doing work? Settled by `claude --debug` output at session start in Task 3 step 1 (mcp docs page, "Scale with MCP tool search").
- Does this Claude Code version write the root `tsconfig.json` on a `--plugin-dir` load as the create page says? Settled by Task 3 step 2's `git status`.
