# jstack Step Band Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Claude Code mod to the jstack plugin that draws one row above the prompt with the current j-mode playbook, the current step and the done count, fed by a private tool the model calls at zero model cost.

**Architecture:** A hooks module `hooks/register.tsx` registers `step` as `mcp__jstack__step` at `session.start` and answers its calls in a `tool.call` hook. The list lives in `$.state` as one typed atom, is mirrored to `$.store` under the session id, and is reloaded by a `classic.SessionStart` hook after `/clear`, `/resume` and `/branch`. One `ui.render` hook on `AbovePrompt` draws the row and keeps the band below it. One `prompt.compose` hook appends the list as a session-scoped system prompt section. All files reach the generated plugin through a new `jstack/patches/80-mod.patch` in the `~/dev/skills` repo, never by hand.

**Tech Stack:** Claude Code 2.1.295 (`claude plugin validate`, `claude plugin test`), TypeScript with JSX against the global `h`, `tsc` from mise (`npm-typescript` 6, on PATH), bun 1.4.2 (already required by `sync-jstack`), bash 3.2 for `check-jstack`.

**Spec:** `docs/superpowers/specs/2026-10-08-claude-code-mods-assessment.md`. Its "Design notes for the prototype rows" is the sketch, "Configuring, implementing, testing: the recommended way" items 2, 5, 6, 8, 9, 10, 14, 15 and 16 are the rules, and "Review corrections" settles that band props live under `e.props`. The companion plan `2026-10-08-claude-code-mods-adoption.md` runs first (its Task 3 restores the task tools).

## Global constraints

- Version floor is Claude Code 2.1.293, for `isDeferred: false` on `$.tool.register` (api page, "Add a tool", Tip). Installed is 2.1.295 (`claude --version`). The README states both.
- `plugins/jstack/` is generated. Every file change goes through `jstack/patches/80-mod.patch` or the `sync-jstack` heredoc, then `scripts/sync-jstack` (skills README, "jstack: generated from upstream").
- Patches are authored against base plus every lower-numbered patch (skills README, "Change or refresh a patch"). The README's `sed` drops the `diff --git` header of a new file, so `git apply` fails with `inconsistent new filename`. Task 1 uses the corrected `sed`, verified on 2026-10-08, and Task 2 fixes the README.
- Write every mods API call as `$.namespace.method(...)`, event names and matcher values as string literals, and pass `$` only to top-level functions of the same file (create page, "Check what Claude Code reads from your mod"). No module-level mutable state. Hot reload resets module variables and `$.state` survives it (interface page, "Keep state").
- `.catch` on every registration (`Registration.catch`, `claude-code.d.ts` line 9318; `Caught.called` line 1192). Call `next(e)` on every path that does not answer. Colors are theme keys (`ThemeKey`, line 12590), never hex.
- `check-jstack` must stay bash 3.2. `claude plugin validate` and `claude plugin test` do not type-check (GitHub issue #99771 via the spec), so `tsc` is a separate step. New text in `plugins/jstack` must pass `check-jstack`'s forbidden regex (`\bTask tool\b`, `AskQuestion\b`, `[A-Za-z]jstack`, `\bCursor\b` and the rest). `mcp__jstack__step` passes because `_` precedes `jstack` (checked with `grep -E` on 2026-10-08).
- Commit subjects in `~/dev/skills` are short, imperative, sentence case. Run `/simplify` then `/code-review` on each commit's diff before committing. Plan prose and code comments follow j-mode. Short sentences, no long dashes, and comments only for a non-obvious why.

## Review focus

1. A `set` whose `steps` is empty, or whose entries are not strings. The tool answers with the valid shape and the band keeps what it had. Pinned in Task 1 test `set with no usable steps is refused`.
2. `done 7` on a three-step list, or `skip` with no reason. The result names the valid range or the missing field and nothing changes. Pinned in Task 1 test `an index outside the list is refused and nothing changes`.
3. A store record from an older build after `/resume`, such as a string or a step with an unknown state. The band draws nothing and nothing throws. Pinned in Task 1 test `a bad store record after /resume draws nothing`.
4. A call from a subagent, where `e.agentId` is set (`AgentLoop`, `claude-code.d.ts` line 194). The main list is untouched and the result says so. Pinned in Task 1 test `a subagent call never touches the main list`.
5. A survey holding the band, `e.props.hasSurvey` true (`claude-code.d.ts` line 10259). The hook yields with `next(e)`. Pinned in Task 1 test `the band yields to a survey`.

---

### Task 1: The mod, its tests and the patch (estimate 4 person-hours)

**Files:**
- Create via patch: `plugins/jstack/hooks/hooks.json`, `plugins/jstack/hooks/register.tsx`, `plugins/jstack/types/index.d.ts`, `plugins/jstack/tests/step-band.test.tsx`, `plugins/jstack/.gitignore`
- Modify via patch: `plugins/jstack/skills/j-mode/SKILL.md` (the Playbooks paragraph, line 123 in the current tree)
- Create: `~/dev/skills/jstack/patches/80-mod.patch`
- Modify: `~/dev/skills/scripts/sync-jstack` (the `plugin.json` heredoc)

**Interfaces:**
- Consumes: `Register` (`claude-code.d.ts` line 9301), `atom`, `read`, `update` from `claude-code` (lines 14701, 14726, 14735), `ToolSpec` with `isDeferred?: boolean` (lines 13117 and 13140, `ToolDeferral` line 12903), `ToolCallResult` `{ result }` (line 12701), `e.agentId` (line 194), `e.props.hasSurvey` and `e.props.bodyColumns` (lines 10259 and 10284), `$.store.get/set` (lines 3351 to 3366), `$.session.id()` (line 2796), `classic.SessionStart` `source` values `startup | resume | clear | compact | fork` (line 11645), `PromptComposeSection { id, text, scope }` (line 8381).
- Produces: the tool `mcp__jstack__step` (api page, "Add a tool": `mcp__`, plugin name, two underscores, registered name) with ops `set`, `done`, `skip`, `add`, `show`; the atom `{ plugin: 'jstack', key: 'board' }`; store key `steps:<session id>`; system prompt section id `jstack:steps`.

- [ ] **Step 1: Build the base tree and an edit copy**

```bash
cd ~/dev/skills
base=$(mktemp -d)/jstack-base
JSTACK_NO_CHECK=1 scripts/sync-jstack --out "$base"
edit="${base%-base}-edit" && cp -R "$base" "$edit"
```

Expected: `sync-jstack: … from https://github.com/cursor/plugins.git@12d587…`. Patches 10 to 70 are applied, so the edit tree already has the todolist rule at `skills/j-mode/SKILL.md` line 13.

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
import { expect, mock, test } from 'claude-code/testing'
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
  const out = await call($, { op: 'set', playbook: 'Bug fix', steps: [1, ''] })
  expect(out.result).toBe('step: set needs playbook (string) and steps (non-empty string array)')
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
test('a valid store record comes back after /resume', async ($, on) => {
  const record = { playbook: 'Bug fix', steps: [{ text: 'Reproduce', state: 'done' }, { text: 'Fix', state: 'todo' }], current: 1 }
  world(on, new Map([['steps:S1', record]]))
  await $.classic.SessionStart({ source: 'resume' })
  const ui = await mount($, 'terminal')
  expect(await ui.find({ type: 'Text', text: 'Bug fix · step 2/2 · 1 done: Fix' })).toBeDefined()
})
test('a bad store record after /resume draws nothing', async ($, on) => {
  world(on, new Map([['steps:S1', { playbook: 'Bug fix', steps: [{ text: 'Fix', state: 'later' }], current: 0 }]]))
  await $.classic.SessionStart({ source: 'clear' })
  const ui = await mount($, 'terminal')
  expect(await ui.find({ type: 'Text', text: /Bug fix/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'below' })).toBeDefined()
})
test('a throw inside the render hook passes through to the band below', async ($, on) => {
  world(on)
  on('ui.resolve', () => ({ deny: 'no element table' }))
  await set($)
  const ui = await mount($, 'terminal')
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

Run `claude plugin test "$edit"`. Expected: a line starting `claude plugin test:` saying no hooks module loads, or every test failing. Nothing passes yet.

- [ ] **Step 5: Write the hooks pointer and the gitignore**

Create `$edit/hooks/hooks.json`:

```json
{ "modules": ["./register.tsx"] }
```

Create `$edit/.gitignore`:

```gitignore
# Claude Code writes the mod's TypeScript types here on each --plugin-dir load
.claude-plugin/types/
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
      const steps = Array.isArray(input.steps)
        ? input.steps.filter((s): s is string => typeof s === 'string' && s.trim() !== '').map(s => s.trim())
        : []
      return playbook && steps.length ? { op: 'set', playbook, steps } : 'set needs playbook (string) and steps (non-empty string array)'
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

  // /clear, /resume and /branch reset $.state and skip session.start
  on('classic.SessionStart', { source: ['clear', 'resume', 'fork'] }, async ($, e, next) => {
    await load($)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('tool.call', { tool: 'mcp__jstack__step' }, async ($, e) => {
    if (e.agentId !== undefined) return { result: 'step: ignored; the band shows the main session only, keep your own todolist' }
    const prev = await read($, board)
    const op = parse(e as unknown as Record<string, unknown>, prev?.steps.length ?? 0)
    if (typeof op === 'string') return { result: `step: ${op}` }
    const after = apply(prev, op)
    if (after !== prev && after) {
      await update($, board, () => after)
      await save($, after)
    }
    return { result: after ? show(after) : 'step: no list yet; call set first' }
  }).catch(($, e, next) => ({ result: `step: the tool failed (${next.error.kind}); the band is unchanged` }))

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

Run: `claude plugin test "$edit"`
Expected: `13 pass`, `0 fail`. If the render `.catch` test fails because the kit answers `ui.resolve` itself, make the throw happen on the `classic.SessionStart` path instead (`on('store.get', () => ({ deny: 'store down' }))`, fire `$.classic.SessionStart({ source: 'clear' })`, expect the row from a prior `set` still drawn) and say so in the commit body.

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

Expected: `Validation passed`, with lines including `hooks: session.start, classic.SessionStart{source=clear|resume|fork}, tool.call{tool=mcp__jstack__step}, ui.render{component=AbovePrompt}, prompt.compose`, `calls: $.tool.register, $.store.set (via save), $.store.get (via load), $.session.id (via save, load), $.ui.resolve`, and `state reads:` and `state writes:` naming `jstack.board`. Keep the printed `calls:` line for Task 2. No `gating hook without .catch` line may appear.

- [ ] **Step 9: Add the SKILL.md sentence**

In `$edit/skills/j-mode/SKILL.md`, the Playbooks paragraph (line 123) ends with `copy its steps in verbatim.` Append to that paragraph, then confirm `grep -nE '\bTask tool\b|AskQuestion\b|[A-Za-z]jstack|\bCursor\b' "$edit/skills/j-mode/SKILL.md"` prints nothing:

```markdown
 When the `mcp__jstack__step` tool is present, mirror the list into it. Call it with `op: "set"` (the playbook name and the step texts) as you open the todolist, then `done` or `skip` with the step number as you go. The todolist stays the record. The band is the operator's view.
```

- [ ] **Step 10: Write the patch**

A new file diffs as `a/jstack-edit/… b/jstack-edit/…`. The second `sed` rule below rewrites that header, so `git apply` creates the file from `--- /dev/null` plus `new file mode` (verified on a two-file sample on 2026-10-08):

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
Expected: `sync-jstack: …/plugins/jstack from …`, and `git status` lists `jstack/patches/80-mod.patch`, `scripts/sync-jstack` and the new files under `plugins/jstack/`. `check-jstack` runs `claude plugin validate` on the result and passes.

- [ ] **Step 12: Commit**

```bash
git add jstack/patches/80-mod.patch scripts/sync-jstack plugins/jstack
git commit -m "Add the step band mod to jstack"
```

### Task 2: Gate the mod in check-jstack and document it (estimate 1.5 person-hours)

**Files:**
- Create: `~/dev/skills/jstack/types/claude-code.d.ts` (a copy of the 2.1.295 declarations, about 800 KB)
- Modify: `~/dev/skills/scripts/check-jstack` (after the `claude plugin validate` line)
- Modify: `~/dev/skills/README.md` ("Install" and "jstack: generated from upstream")

**Interfaces:**
- Consumes: the tsconfig the declarations' header prescribes (`claude-code.d.ts` lines 68 to 78: `target es2023`, `lib ["es2023"]`, `types []`, `module esnext`, `moduleResolution bundler`, `strict`, `noUncheckedIndexedAccess`, `noEmit`, `skipLibCheck`, `jsx react`, `jsxFactory h`, `jsxFragmentFactory Fragment`).
- Produces: `check-jstack` fails on a type error or a failing test, so `sync-jstack` never replaces `plugins/jstack` with a broken mod.

- [ ] **Step 1: Copy the declarations into the repo**

The engine writes them only beside a mod it loads from a folder the person owns (create page, "Get type definitions for your version"), and `plugins/jstack` is rebuilt on every sync, so the copy lives outside it. Run `/plugin-authoring` in a Claude Code session. Its reply names the file, on 2026-10-08 `/private/tmp/claude-501/bundled-skills/2.1.295/874577937dfd7a6691cffed1541707f8/plugin-authoring/types/claude-code.d.ts`.

```bash
mkdir -p ~/dev/skills/jstack/types
cp "$(ls -t /private/tmp/claude-501/bundled-skills/*/*/plugin-authoring/types/claude-code.d.ts | head -1)" ~/dev/skills/jstack/types/claude-code.d.ts
head -1 ~/dev/skills/jstack/types/claude-code.d.ts
```

Expected: `// Written by Claude Code 2.1.295.`

- [ ] **Step 2: Add the type check and the tests to check-jstack**

In `scripts/check-jstack`, replace the `dir=` line with these two (the tsconfig below holds absolute paths), then add the block after the `claude plugin validate` line:

```bash
dir="$(cd "${1:-$(cd "$(dirname "$0")/.." && pwd -P)/plugins/jstack}" && pwd -P)"
root="$(cd "$(dirname "$0")/.." && pwd -P)"
```

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
tsc -p "$tsdir/tsconfig.json" || bad "tsc: $dir/hooks does not type-check"
claude plugin test "$dir" > /dev/null 2>&1 || bad "claude plugin test $dir failed (run it by hand for the output)"
```

- [ ] **Step 3: Run the check on the generated tree, then break it on purpose**

Run `scripts/check-jstack && echo OK`. Expected: `OK` and no version warning. Then prove the gate bites on a scratch copy:

```bash
tmp=$(mktemp -d) && cp -R plugins/jstack "$tmp/jstack"
sed -i '' 's/const done = b.steps.filter/const done: string = b.steps.filter/' "$tmp/jstack/hooks/register.tsx"
scripts/check-jstack "$tmp/jstack"; echo "exit $?"
```

Expected: a `tsc` error naming `register.tsx`, then `check-jstack: … does not type-check` and `exit 1`.

- [ ] **Step 4: Document in the skills README**

In "Install", after the fenced block ending `claude plugin install resume@jrmatherly-skills`, add this paragraph, with the `calls:` line pasted as Task 1 step 8 printed it:

```markdown
jstack ships a mod (a hooks module) that draws the j-mode step band above
the prompt. It needs Claude Code 2.1.293 or later and was tested on 2.1.295.
`claude plugin validate plugins/jstack` lists what it can reach as
`calls: $.tool.register, $.store.set, $.store.get, $.session.id, $.ui.resolve`
plus `$.state` reads and writes of `jstack.board`. No process, file, network
or model calls. Its private tool `mcp__jstack__step` costs no model call.
```

In "jstack: generated from upstream", add `80-mod` to the patch list, and to the list of checks that gate the replace:

```markdown
- `tsc --noEmit` over `hooks/`, `types/` and `tests/` against
  `jstack/types/claude-code.d.ts`, then `claude plugin test` (neither
  `claude plugin validate` nor `claude plugin test` type-checks)
```

In "Change or refresh a patch", replace the `sed` line with the one from Task 1 step 10 and add after the code block, then add the subsection before "Attribution":

```markdown
A new file diffs as `a/jstack-edit/… b/jstack-edit/…`. The second `sed`
rule rewrites that header so `git apply` creates the file. Without it
`git apply` stops with `inconsistent new filename`.

### Refresh the mod types

`jstack/types/claude-code.d.ts` is the mods API as the installed Claude Code
declares it. After `claude update`, run `/plugin-authoring` once in a session,
copy the `claude-code.d.ts` it names over this file and commit. `check-jstack`
prints a one-line warning while the two versions differ.
```

- [ ] **Step 5: Commit**

```bash
scripts/check-jstack && git add jstack/types/claude-code.d.ts scripts/check-jstack README.md
git commit -m "Type-check and test the jstack mod in check-jstack"
```

### Task 3: Prove it live, then publish (estimate 1 person-hour)

**Files:**
- Read: `~/dev/skills/plugins/jstack`, loaded with `--plugin-dir`, which writes `.claude-plugin/types/` into it (create page, "Get type definitions for your version"), ignored by the new `.gitignore`.
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

- [ ] **Step 2: Check reload and the git tree**

Run `/clear`. Expected: the row is still drawn, reloaded from the store by the `classic.SessionStart` hook. Exit, then run `git -C ~/dev/skills status --short`. Expected: empty, because the `.claude-plugin/types/` folder the load wrote is ignored.

- [ ] **Step 3: Publish, update the installed plugin, file the plan**

```bash
cd ~/dev/skills && git push
claude plugin marketplace update jrmatherly-skills && claude plugin update jstack@jrmatherly-skills
claude plugin validate ~/.claude/plugins/cache/jrmatherly-skills/jstack/*/
cd ~/dev/dotfiles && git mv docs/superpowers/plans/2026-10-08-jstack-step-band.md docs/superpowers/plans/completed/
pnpm check && git commit -m "Mark the jstack step band plan completed" && git push
```

Expected: `Validation passed` with the same `hooks:` and `calls:` lines as Task 1 step 8, and `/plugin` in a new session in any repo shows `1 mod active · jstack`.

## Decisions for review

1. **One atom, `board`, holding `Board | null`.** `current` is recomputed on every write as the first `todo` index, so the model cannot set it inconsistently. Indexes start at 1 in the tool and in `show`, matching `step k/n`. The done count counts `done` only; skipped steps keep their reason in `show` and advance `current`.
2. **Subagent calls are ignored** (`e.agentId` set). j-agent subagents also load j-mode and would overwrite the operator's band.
3. **Store keys are never deleted.** One record per session, under 1 KB, against the 4 MiB limit (reference page, "Limits"). A `session.end` cleanup waits until the store shows growth.
5. **The `prompt.compose` section is `scope: 'session'`**, after the cache boundary (`claude-code.d.ts` line 8372). Each step change misses the session side of the cache, the same cost the task tools' reminders pay.
6. **The declarations are committed** at `jstack/types/claude-code.d.ts` (800 KB). `check-jstack` runs on a fresh stage with no `.claude-plugin/types/`, and a `--plugin-dir` load inside a check would start a session.
7. **The matcher value is a string literal**, so `claude plugin validate` prints `tool.call{tool=mcp__jstack__step}` without depending on constant folding. **Row color is the `suggestion` theme key**, one `Text` with `wrap: 'truncate-end'` plus a `slice` to `bodyColumns`, so Desktop and terminal agree on one row.
8. **Nothing changes in the dotfiles repo** beyond this plan file. `agents/claude-plugins.txt` already names `jstack@jrmatherly-skills`.

## Open questions

- Does the test kit let a `ui.resolve` stub deny the mod's `$.ui.resolve(e)` call, so the render `.catch` test fails the hook as intended? Settled by `claude plugin test "$edit"` in Task 1 step 7; the fallback is written there.
- Does `claude plugin validate` print the `source` matcher as `classic.SessionStart{source=clear|resume|fork}` or in another spelling? Settled by Task 1 step 8's output; the README paste in Task 2 step 4 copies whatever it prints.
- Is `below` from `await next(e)` on `AbovePrompt` a valid child when no other mod draws there (null or an engine reference)? Settled by Task 3 step 2 in the live session; a refused tree prints the reason in the transcript.
- Is MCP tool search active in Jason's sessions, so that `isDeferred: false` is doing work? Settled by `claude --debug` output at session start in Task 3 step 1 (mcp docs page, "Scale with MCP tool search").
- Does `tsc` 6 from mise accept the header's tsconfig without `ignoreDeprecations`? Settled by Task 2 step 3's first run.
